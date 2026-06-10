import Foundation
import AppKit

struct UpdateChecker {
    static let currentVersion = "1.2.0"
    private static let apiURL = "https://api.github.com/repos/bssm-oss/PortSearcher/releases/latest"
    private static let releasesURL = "https://github.com/bssm-oss/PortSearcher/releases/latest"

    /// 최신 버전 반환 (현재보다 높을 때만), 없으면 nil
    func fetchLatestVersion(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: Self.apiURL) else { completion(nil); return }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                completion(nil); return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            completion(Self.isNewer(latest, than: Self.currentVersion) ? latest : nil)
        }.resume()
    }

    static func openReleasesPage() {
        guard let url = URL(string: releasesURL) else { return }
        NSWorkspace.shared.open(url)
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }
}
