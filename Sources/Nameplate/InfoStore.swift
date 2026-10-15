import Combine
import Foundation
import NameplateCore

/// Holds the latest snapshot and the current display options.
/// The menu bar panel observes it; the app delegate redraws the desktop when it changes.
@MainActor
final class InfoStore: ObservableObject {
    @Published private(set) var snapshot: SystemSnapshot
    @Published private(set) var options: DisplayOptions

    var onUpdate: (@MainActor () -> Void)?

    private var isRefreshing = false
    private var refreshAgain = false
    private var publicIPEnabled = false
    private var publicIP: String?

    init() {
        snapshot = SystemCollector.collect()
        options = Prefs.displayOptions()
    }

    var lines: [InfoLine] { InfoFormatter.lines(for: snapshot, options: options) }

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

    func setOptions(_ newOptions: DisplayOptions) {
        if newOptions != options { options = newOptions }
        let wantsPublicIP = newOptions.has(.publicIP)
        if wantsPublicIP != publicIPEnabled {
            publicIPEnabled = wantsPublicIP
            if wantsPublicIP { refreshPublicIP() } else { publicIP = nil; snapshot.publicIP = nil }
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
}
