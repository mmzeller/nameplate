import Foundation

/// Runs your own shell commands for "Command output" lines.
public enum CommandRunner {
    /// Runs `command` with zsh and returns what it printed (output and errors), trimmed.
    /// Stops it after `timeout` seconds.
    public static func run(_ command: String, timeout: TimeInterval = 10) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        // Apps start with a short PATH; add the usual places for Homebrew and friends.
        var environment = ProcessInfo.processInfo.environment
        let current = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = (current + extra.filter { !current.contains($0) }).joined(separator: ":")
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return "Couldn't run it: \(error.localizedDescription)"
        }

        let stopper = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: stopper)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stopper.cancel()

        var text = String(decoding: data.prefix(32_768), as: UTF8.self)
        // Remove terminal color codes.
        text = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && process.terminationReason == .uncaughtSignal {
            return "Timed out after \(Int(timeout)) seconds"
        }
        return text
    }
}
