import AppKit
import SystemConfiguration

/// Tells the app when something it displays may have changed, so it can refresh
/// right away instead of waiting for the next timer tick.
@MainActor
final class ChangeMonitor: NSObject {
    enum Reason {
        case network, volumes, screens, wake
    }

    var onChange: (@MainActor (Reason) -> Void)?
    private var store: SCDynamicStore?
    private var source: CFRunLoopSource?

    func start() {
        startDynamicStore()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspace.didMountNotification, object: nil)
        workspace.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
        workspace.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspace.didRenameVolumeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Network, host name and computer name changes all come through the dynamic store.
    private func startDynamicStore() {
        var context = SCDynamicStoreContext(version: 0,
                                            info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "Nameplate.monitor" as CFString, dynamicStoreChanged, &context) else { return }
        let patterns = [
            "State:/Network/Global/.*",
            "State:/Network/Service/.*",
            "State:/Network/Interface/[^/]+/(Link|IPv4|IPv6|AirPort)",
            "Setup:/Network/Service/.*",
            "Setup:/System",
            "Setup:/Network/HostNames",
        ] as CFArray
        SCDynamicStoreSetNotificationKeys(store, nil, patterns)
        if let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            self.source = source
        }
        self.store = store
    }

    @objc private func volumesChanged(_ note: Notification) { onChange?(.volumes) }
    @objc private func didWake(_ note: Notification) { onChange?(.wake) }
    @objc private func screensChanged(_ note: Notification) { onChange?(.screens) }
}

/// Called by System Configuration on the main run loop when a watched key changes.
private func dynamicStoreChanged(_ store: SCDynamicStore, _ changedKeys: CFArray, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    let monitor = Unmanaged<ChangeMonitor>.fromOpaque(info).takeUnretainedValue()
    Task { @MainActor in
        monitor.onChange?(.network)
    }
}
