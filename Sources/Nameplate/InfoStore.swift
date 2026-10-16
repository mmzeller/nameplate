import Combine
import Foundation
import NameplateCore

/// Holds the latest information and the current layout.
/// The menu bar panel observes it; the app delegate redraws the desktop when it changes.
@MainActor
final class InfoStore: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot
    @Published private(set) var live = LiveStats()
    @Published private(set) var commandOutputs: [UUID: String] = [:]
    @Published private(set) var layout: Layout
    @Published private(set) var settings: RenderSettings
    @Published private(set) var now = Date()

    var onUpdate: (@MainActor () -> Void)?

    // Slow refresh (hardware, network setup, disks)
    private var isRefreshing = false
    private var refreshAgain = false

    // Public IP
    private var publicIPEnabled = false
    private var publicIP: String?

    // Live numbers and commands
    private let liveQueue = DispatchQueue(label: "Nameplate.live", qos: .utility)
    private let sampler = LiveSampler()
    private var liveNeeds: LiveNeeds = []
    private var liveInterval: TimeInterval = 2
    private var lastLiveSample = Date.distantPast
    private var isSampling = false
    private var commands: [LayoutEntry] = []
    private var nextCommandRun: [UUID: Date] = [:]
    private var runningCommands: Set<UUID> = []
    private var ticker: Timer?

    init() {
        snapshot = SystemCollector.collect()
        layout = Prefs.layout()
        settings = Prefs.renderSettings()
    }

    var input: RenderInput {
        RenderInput(snapshot: snapshot, live: live, commandOutputs: commandOutputs, now: now)
    }

    var lines: [InfoLine] {
        InfoFormatter.lines(layout: layout, input: input, settings: settings)
    }

    var templateValues: [String: String] {
        InfoFormatter.valueDictionary(input)
    }

    // MARK: Configuration

    func configure(layout newLayout: Layout, settings newSettings: RenderSettings,
                   liveNeeds newNeeds: LiveNeeds, liveInterval newInterval: TimeInterval, wantsPublicIP: Bool) {
        if newLayout != layout { layout = newLayout }
        if newSettings != settings { settings = newSettings }

        // Commands: run new or edited ones shortly (after typing pauses), drop removed ones.
        let newCommands = newLayout.activeCommands
        if newCommands != commands {
            let previous = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
            for command in newCommands where previous[command.id]?.text != command.text {
                nextCommandRun[command.id] = Date().addingTimeInterval(previous[command.id] == nil ? 0 : 1.5)
            }
            let ids = Set(newCommands.map { $0.id })
            nextCommandRun = nextCommandRun.filter { ids.contains($0.key) }
            let kept = commandOutputs.filter { ids.contains($0.key) }
            if kept.count != commandOutputs.count { commandOutputs = kept }
            commands = newCommands
        }

        if newNeeds != liveNeeds {
            let added = newNeeds.subtracting(liveNeeds)
            liveNeeds = newNeeds
            if !added.isEmpty { lastLiveSample = .distantPast }
            if added.contains(.clock) { now = Date() }
            let sampled = newNeeds.intersection(.sampled)
            if sampled.isEmpty, live != LiveStats() { live = LiveStats() }
        }
        liveInterval = max(1, newInterval)

        if wantsPublicIP != publicIPEnabled {
            publicIPEnabled = wantsPublicIP
            if wantsPublicIP {
                refreshPublicIP()
            } else {
                publicIP = nil
                snapshot.publicIP = nil
            }
        }
        updateTicker()
    }

    // MARK: Slow refresh

    /// Re-reads everything off the main thread. Calls made while a refresh is
    /// running are folded into one more pass when it finishes.
    func refresh() {
        if isRefreshing {
            refreshAgain = true
            return
        }
        isRefreshing = true
        let previous = snapshot
        DispatchQueue.global(qos: .utility).async {
            let fresh = SystemCollector.collect(reusingHardwareFrom: previous)
            Task { @MainActor in
                self.finish(fresh)
            }
        }
    }

    private func finish(_ fresh: SystemSnapshot) {
        var updated = fresh
        updated.publicIP = publicIPEnabled ? publicIP : nil
        if updated != snapshot { snapshot = updated }
        isRefreshing = false
        onUpdate?()
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }

    func refreshPublicIP() {
        guard publicIPEnabled else { return }
        PublicIP.fetch { ip in
            Task { @MainActor in
                guard self.publicIPEnabled else { return }
                self.publicIP = ip
                if self.snapshot.publicIP != ip { self.snapshot.publicIP = ip }
                self.onUpdate?()
            }
        }
    }

    // MARK: Live numbers and commands

    private func updateTicker() {
        let needed = !liveNeeds.isEmpty || !commands.isEmpty
        if needed, ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
            tick()
        } else if !needed, let timer = ticker {
            timer.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        guard ticker != nil else { return }
        let current = Date()

        if liveNeeds.contains(.clock),
           Calendar.current.component(.minute, from: current) != Calendar.current.component(.minute, from: now)
            || !Calendar.current.isDate(current, inSameDayAs: now) {
            now = current
            onUpdate?()
        }

        let sampleNeeds = liveNeeds.intersection(.sampled)
        if !sampleNeeds.isEmpty, !isSampling, current.timeIntervalSince(lastLiveSample) >= liveInterval - 0.1 {
            lastLiveSample = current
            isSampling = true
            let primary = snapshot.network.primaryInterface
            let sampler = self.sampler
            liveQueue.async {
                let stats = sampler.sample(sampleNeeds, primaryInterface: primary)
                Task { @MainActor in
                    self.finishSample(stats)
                }
            }
        }

        for command in commands where !runningCommands.contains(command.id) {
            guard current >= (nextCommandRun[command.id] ?? .distantPast) else { continue }
            runningCommands.insert(command.id)
            let id = command.id
            let text = command.text
            DispatchQueue.global(qos: .utility).async {
                let output = CommandRunner.run(text)
                Task { @MainActor in
                    self.finishCommand(id: id, ranText: text, output: output)
                }
            }
        }
    }

    private func finishSample(_ stats: LiveStats) {
        isSampling = false
        guard !liveNeeds.intersection(.sampled).isEmpty else { return }
        if stats != live {
            live = stats
            onUpdate?()
        }
    }

    private func finishCommand(id: UUID, ranText: String, output: String) {
        runningCommands.remove(id)
        guard let command = commands.first(where: { $0.id == id }) else { return }
        if command.text == ranText {
            nextCommandRun[id] = Date().addingTimeInterval(TimeInterval(max(command.interval, 2)))
            if commandOutputs[id] != output {
                commandOutputs[id] = output
                onUpdate?()
            }
        } else if (nextCommandRun[id] ?? .distantPast) < Date() {
            // Edited while it was running: run the new version now.
            nextCommandRun[id] = Date()
        }
    }

    /// Runs every command again right away (from the Refresh button).
    func rerunCommands() {
        for command in commands { nextCommandRun[command.id] = .distantPast }
    }
}
