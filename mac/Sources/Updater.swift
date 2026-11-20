// Update check and one-click update. The check reads one small text file from GitHub (version-mac.txt). The update downloads
// the new app, checks it against the fingerprint (SHA-256) in that file, swaps it in and starts it. Nothing is ever
// installed without you pressing "Update now".
import Cocoa
import CryptoKit

struct UpdateInfo {
    let latest: String
    let url: String
    let notes: String
    let zip: String
    let sha256: String
}

enum Updater {
    static let infoURL = URL(string: "https://raw.githubusercontent.com/Coloseal/MAC-A-TAK-Overlay-JSOC/main/version-mac.txt")!
    static let fallbackPage = "https://github.com/Coloseal/MAC-A-TAK-Overlay-JSOC/releases"

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

    static func parse(_ text: String) -> UpdateInfo? {
        var latest = "", url = "", notes = "", zip = "", sha = ""
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "latest": latest = value
            case "url": url = value
            case "notes": notes = value
            case "zip": zip = value
            case "sha256": sha = value.lowercased()
            default: break
            }
        }
        if latest.isEmpty { return nil }
        return UpdateInfo(latest: latest, url: url.hasPrefix("https://") ? url : fallbackPage, notes: notes, zip: zip, sha256: sha)
    }

    // completion gets the info only when a NEWER version exists
    static func check(completion: @escaping (UpdateInfo?) -> Void) {
        var req = URLRequest(url: infoURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 6
        let task = URLSession.shared.dataTask(with: req) { data, response, _ in
            var found: UpdateInfo?
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data = data, let text = String(data: data, encoding: .utf8),
               let info = parse(text), isNewer(info.latest, than: current) {
                found = info
            }
            DispatchQueue.main.async { completion(found) }
        }
        task.resume()
    }

    // A one-click install needs a download address in our own GitHub, its fingerprint, and an app folder we may write to
    // (an app that was started straight from the Downloads folder runs from a locked copy and can't replace itself).
    static func canInstall(_ info: UpdateInfo) -> Bool {
        guard info.zip.hasPrefix("https://github.com/Coloseal/"), info.sha256.count == 64 else { return false }
        let path = Bundle.main.bundlePath
        if path.contains("/AppTranslocation/") { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: parent)
    }

    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // completion(true, "") = everything is ready, the helper swaps the app as soon as this one quits
    static func install(_ info: UpdateInfo, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: info.zip) else { completion(false, "The download address is not valid."); return }
        let task = URLSession.shared.downloadTask(with: url) { tmp, response, error in
            DispatchQueue.global(qos: .userInitiated).async {
                func fail(_ m: String) { DispatchQueue.main.async { completion(false, m) } }
                guard let tmp = tmp, error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    fail("The download failed. Check your connection."); return
                }
                guard let data = try? Data(contentsOf: tmp) else { fail("The downloaded file could not be read."); return }
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                if hash != info.sha256 { fail("The download does not match its fingerprint, so it was not installed."); return }

                let work = NSTemporaryDirectory() + "tacupdate-" + UUID().uuidString
                let zipPath = work + "/update.zip"
                let outDir = work + "/new"
                do {
                    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
                    try data.write(to: URL(fileURLWithPath: zipPath))
                } catch { fail("Could not prepare the update: \(error.localizedDescription)"); return }
                if run("/usr/bin/ditto", ["-x", "-k", zipPath, outDir]) != 0 { fail("Could not unpack the update."); return }

                let newApp = outDir + "/Tac Map Overlay.app"
                guard FileManager.default.fileExists(atPath: newApp + "/Contents/MacOS/TacMapOverlay") else { fail("The update does not contain the app."); return }
                if let plist = NSDictionary(contentsOfFile: newApp + "/Contents/Info.plist"),
                   let v = plist["CFBundleShortVersionString"] as? String, !isNewer(v, than: current) {
                    fail("The downloaded app is not newer than this one."); return
                }
                if run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp]) != 0 { fail("The downloaded app's signature is not valid."); return }
                _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp])

                // a helper script waits for this app to close, swaps the folders and starts the new one
                let script = """
                #!/bin/sh
                PID="$1"; NEW="$2"; OLD="$3"
                i=0
                while kill -0 "$PID" 2>/dev/null && [ $i -lt 60 ]; do sleep 0.25; i=$((i+1)); done
                if mv "$OLD" "$OLD.old"; then
                  if mv "$NEW" "$OLD"; then rm -rf "$OLD.old"; else mv "$OLD.old" "$OLD"; fi
                fi
                /usr/bin/open -n "$OLD"
                """
                let scriptPath = work + "/swap.sh"
                do { try script.write(toFile: scriptPath, atomically: true, encoding: .utf8) } catch { fail("Could not prepare the update helper."); return }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = [scriptPath, String(ProcessInfo.processInfo.processIdentifier), newApp, Bundle.main.bundlePath]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { fail("Could not start the update helper."); return }
                DispatchQueue.main.async { completion(true, "") }
            }
        }
        task.resume()
    }
}
