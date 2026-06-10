import Foundation

public struct UpdateChecker: Sendable {
    public static let currentVersion = "1.4.0"
    private static let apiURL = "https://api.github.com/repos/bssm-oss/PortSearcher/releases/latest"
    private static let releasesURL = "https://github.com/bssm-oss/PortSearcher/releases/latest"

    public init() {}

    /// 최신 버전 태그를 반환 (현재보다 높을 때만), 없으면 nil
    public func fetchLatestVersion() -> String? {
        guard let url = URL(string: Self.apiURL) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        var result: String? = nil
        let sema = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { sema.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }

            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.isNewer(latest, than: Self.currentVersion) {
                result = latest
            }
        }.resume()

        sema.wait()
        return result
    }

    public static var releasesPageURL: String { releasesURL }

    /// CLI용: open 명령으로 브라우저 열기
    public static func openReleasesPage() {
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [releasesURL])
    }

    // "1.2.0" > "1.1.0" 비교
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
