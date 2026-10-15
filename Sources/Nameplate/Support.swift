import AppKit
import Combine
import CoreLocation
import ServiceManagement

/// macOS only reveals the Wi-Fi network name (SSID) to apps allowed to use Location Services.
/// Nameplate never asks for or stores a location; this permission just unlocks the SSID.
@MainActor
final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: (@MainActor () -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    var isAllowed: Bool {
        switch status {
        case .notDetermined, .restricted, .denied: return false
        default: return true
        }
    }

    var statusText: String {
        switch status {
        case .notDetermined: return "Not asked yet"
        case .restricted: return "Restricted on this Mac"
        case .denied: return "Not allowed. Turn on Nameplate in System Settings › Privacy & Security › Location Services."
        default: return "Allowed"
        }
    }

    func requestIfNeeded() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.objectWillChange.send()
            self.onChange?()
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return true
        } catch {
            NSLog("Nameplate: launch at login change failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// Links /usr/local/bin/nameplate to the tool inside the app bundle.
enum CommandLineTool {
    static let linkPath = "/usr/local/bin/nameplate"

    static var bundledToolPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/nameplate").path
    }

    static var isInstalled: Bool {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath) else {
            return FileManager.default.isExecutableFile(atPath: linkPath)
        }
        return destination == bundledToolPath
    }

    /// Asks for an administrator password (the standard macOS prompt) and creates the link.
    @MainActor
    static func install() {
        guard FileManager.default.isExecutableFile(atPath: bundledToolPath) else {
            showAlert("The command-line tool isn't inside this copy of Nameplate.",
                      detail: "Rebuild with build.sh, which puts it at Contents/Helpers/nameplate.")
            return
        }
        let escaped = bundledToolPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        do shell script "mkdir -p /usr/local/bin && ln -sf " & quoted form of "\(escaped)" & " \(linkPath)" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error, (error[NSAppleScript.errorNumber] as? Int) != -128 {
            showAlert("Couldn't install the command-line tool.",
                      detail: (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error.")
        } else if error == nil {
            showAlert("Command-line tool installed.",
                      detail: "Open Terminal and type `nameplate`. Try `nameplate --help` for options.")
        }
    }

    @MainActor
    static func showAlert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
