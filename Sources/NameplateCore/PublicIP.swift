import Foundation

/// Looks up the address the internet sees (the NAT / public IP).
/// This is the only thing Nameplate ever sends off the Mac, and only when turned on.
public enum PublicIP {
    public static let serviceHost = "api.ipify.org"
    static let serviceURL = URL(string: "https://api.ipify.org")!

    public static func fetch(timeout: TimeInterval = 6, completion: @escaping (String?) -> Void) {
        let request = URLRequest(url: serviceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                completion(nil)
                return
            }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let looksLikeIP = !text.isEmpty && text.count <= 45
                && text.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" }
            completion(looksLikeIP ? text : nil)
        }.resume()
    }

    /// Blocking version for the command-line tool.
    public static func fetchAndWait(timeout: TimeInterval = 6) -> String? {
        final class Box: @unchecked Sendable { var value: String? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        fetch(timeout: timeout) { ip in
            box.value = ip
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout + 1)
        return box.value
    }
}
