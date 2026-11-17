// Safety rules for the built-in browser: which addresses are allowed, what a typed address turns into,
// and the ad / tracker block list.
import Cocoa
import WebKit

enum WebSupport {
    static let blockedDomains: [String] = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com", "adservice.google.com",
        "google-analytics.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "advertising.com", "criteo.com", "criteo.net",
        "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com", "moatads.com", "rubiconproject.com",
        "pubmatic.com", "openx.net", "casalemedia.com", "indexww.com", "sharethrough.com", "smartadserver.com", "adform.net",
        "bidswitch.net", "contextweb.com", "yieldmo.com", "teads.tv", "mathtag.com", "bluekai.com", "krxd.net", "demdex.net",
        "everesttech.net", "omtrdc.net", "hotjar.com", "mouseflow.com", "fullstory.com", "ads-twitter.com", "analytics.twitter.com",
        "ads.linkedin.com", "bat.bing.com", "clarity.ms", "analytics.tiktok.com", "ads.tiktok.com", "ads.yahoo.com",
        "popads.net", "popcash.net", "propellerads.com", "exoclick.com", "trafficjunky.net", "juicyads.com", "adcash.com",
        "mgid.com", "revcontent.com", "adskeeper.com", "onclickads.net", "clickadu.com", "hilltopads.net", "a-ads.com",
        "ad-delivery.net", "adsafeprotected.com", "doubleverify.com", "serving-sys.com", "tapad.com", "adsterra.com",
        "pagead2.googlesyndication.com", "tpc.googlesyndication.com", "ct.pinterest.com", "ads.pinterest.com",
        "px.ads.linkedin.com", "tr.snapchat.com", "imrworldwide.com", "chartbeat.net", "app-measurement.com"
    ]

    // WebKit "content rules" (JSON): block any request whose address contains one of these domains.
    static func contentRuleJSON() -> String {
        var rules: [[String: Any]] = []
        for d in blockedDomains {
            let escaped = d.replacingOccurrences(of: ".", with: "\\.")
            let trigger: [String: Any] = ["url-filter": escaped]
            let action: [String: Any] = ["type": "block"]
            rules.append(["trigger": trigger, "action": action])
        }
        if let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "[]"
    }

    static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".localhost") { return true }
        if !h.contains(".") { return true }
        if h.hasPrefix("127.") || h.hasPrefix("10.") || h.hasPrefix("192.168.") { return true }
        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]), second >= 16 && second <= 31 { return true }
        }
        return false
    }

    // What was typed in the address box -> a safe address (nil if it can't be one).
    static func resolveInput(_ raw: String, search: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.contains("://") {
            if let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                return u
            }
            return nil
        }
        let schemeLike = s.range(of: "^[A-Za-z][A-Za-z0-9+.\\-]*:(?!\\d)", options: .regularExpression) != nil
        let hostLike = !schemeLike && !s.contains(" ") && (s.contains(".") || s.lowercased().hasPrefix("localhost"))
        if hostLike {
            let host = s.components(separatedBy: CharacterSet(charactersIn: "/?#:")).first ?? s
            let prefix = isLocalHost(host) ? "http://" : "https://"
            return URL(string: prefix + s)
        }
        let q = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        return URL(string: search + q)
    }
}
