// Update check: reads one small text file from GitHub (version-mac.txt) and, if a newer Mac version exists, tells the person.
// It never downloads or replaces anything by itself: it opens the download page.
import Cocoa

struct UpdateInfo {
    let latest: String
    let url: String
    let notes: String
}

enum Updater {
    static let infoURL = URL(string: "https://raw.githubusercontent.com/Coloseal/A-TAK-Overlay-JSOC/main/version-mac.txt")!
    static let fallbackPage = "https://github.com/Coloseal/A-TAK-Overlay-JSOC/releases"

    static var current: String {
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(x.count, y.count)
        for i in 0..<n {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        var req = URLRequest(url: infoURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 6
        let task = URLSession.shared.dataTask(with: req) { data, response, _ in
            var info: UpdateInfo?
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data = data, let text = String(data: data, encoding: .utf8) {
                var latest = "", url = "", notes = ""
                for raw in text.components(separatedBy: "\n") {
                    let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
                    let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    if key == "latest" { latest = value }
                    if key == "url" { url = value }
                    if key == "notes" { notes = value }
                }
                if !latest.isEmpty && isNewer(latest, than: current) {
                    info = UpdateInfo(latest: latest, url: url.hasPrefix("https://") ? url : fallbackPage, notes: notes)
                }
            }
            DispatchQueue.main.async { completion(info) }
        }
        task.resume()
    }
}
