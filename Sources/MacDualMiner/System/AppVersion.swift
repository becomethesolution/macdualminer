import Foundation

/// "1.2.10" > "1.2.9"; ignores a leading "v".
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]
    let text: String

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let core = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let numbers = core.split(separator: ".").map { Int($0.prefix { $0.isNumber }) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
        text = core
    }

    var description: String { text }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

struct ReleaseInfo: Equatable {
    var version: String
    var name: String
    var notes: String
    var pageURL: URL
    var zipURL: URL?
    var publishedAt: Date?

    /// Parses GitHub's /releases/latest response.
    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let published = (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                           name: json["name"] as? String ?? tag,
                           notes: json["body"] as? String ?? "",
                           pageURL: page,
                           zipURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                           publishedAt: published)
    }
}
