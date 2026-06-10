import Foundation
import AppKit

enum UpdateState: Equatable {
    case idle
    case downloading(progress: Double)  // 0.0 ~ 1.0
    case ready(pkgURL: URL)
    case failed(String)
}

struct UpdateChecker {
    static let currentVersion = "1.4.0"
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
                  let tag = json["tag_name"] as? String else { completion(nil); return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            completion(Self.isNewer(latest, than: Self.currentVersion) ? latest : nil)
        }.resume()
    }

    /// pkg 다운로드 → macOS Installer.app 실행
    func downloadAndInstall(version: String, onState: @escaping (UpdateState) -> Void) {
        let pkgName = "PortSearcher-\(version).pkg"
        let pkgURL = "https://github.com/bssm-oss/PortSearcher/releases/download/v\(version)/\(pkgName)"
        guard let url = URL(string: pkgURL) else {
            onState(.failed("잘못된 URL")); return
        }

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(pkgName)

        // 이미 다운로드돼 있으면 바로 설치
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }

        onState(.downloading(progress: 0))

        let task = URLSession.shared.downloadTask(with: url) { tmpURL, _, error in
            if let error {
                DispatchQueue.main.async { onState(.failed(error.localizedDescription)) }
                return
            }
            guard let tmpURL else {
                DispatchQueue.main.async { onState(.failed("다운로드 실패")) }
                return
            }
            do {
                try FileManager.default.moveItem(at: tmpURL, to: dest)
                DispatchQueue.main.async {
                    onState(.ready(pkgURL: dest))
                    // macOS Installer.app으로 pkg 열기
                    NSWorkspace.shared.open(dest)
                    // 잠시 후 앱 종료 (installer가 교체)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        NSApp.terminate(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async { onState(.failed(error.localizedDescription)) }
            }
        }

        // 진행률 추적
        let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
            DispatchQueue.main.async {
                onState(.downloading(progress: progress.fractionCompleted))
            }
        }
        task.resume()

        // observation 유지 (retain)
        objc_setAssociatedObject(task, "obs", observation, .OBJC_ASSOCIATION_RETAIN)
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
