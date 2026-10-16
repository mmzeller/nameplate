import Foundation

/// Runs your own shell commands for "Command output" lines.
public enum CommandRunner {
    static let outputLimit = 32_768

    /// Runs `command` with zsh and returns what it printed (output and errors), trimmed.
    /// Stops it after `timeout` seconds. Never waits on programs the command leaves
    /// running in the background, and always closes its pipe.
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
        let reader = pipe.fileHandleForReading
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        defer {
            try? reader.close()
            try? pipe.fileHandleForWriting.close()
        }

        do {
            try process.run()
        } catch {
            return "Couldn't run it: \(error.localizedDescription)"
        }
        // Our copy of the write end isn't needed; closing it lets reads see the end of output.
        try? pipe.fileHandleForWriting.close()

        // Read without blocking, so a program left running in the background can't hold us up.
        let fd = reader.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        func drain() {
            while true {
                let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                guard count > 0 else { return }
                if output.count < outputLimit {
                    output.append(contentsOf: buffer[0..<min(count, outputLimit - output.count)])
                }
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            drain()
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            usleep(20_000)
        }
        // Give it a moment to stop, then make sure it does.
        let stopDeadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < stopDeadline { usleep(20_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        drain()

        var text = String(decoding: output, as: UTF8.self)
        // Remove terminal color codes.
        text = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if timedOut && text.isEmpty {
            return "Timed out after \(Int(timeout)) seconds"
        }
        return text
    }
}
