import Foundation

/// 通过 GitHub Releases API 检查 Snap² 是否有新版本。
/// 不依赖 Sparkle 等外部框架，仅用 URLSession + JSONSerialization。
///
/// 使用 /releases/latest 而非 /tags：tags 接口拿不到 release assets，
/// 自动下载需要 assets[].browser_download_url。
final class UpdateChecker {

    static let shared = UpdateChecker()
    private init() {}

    /// 仓库 owner/repo
    private let repoSlug = "co0ontty/Snap2"
    /// 启动检查的防抖间隔（秒）
    private let checkInterval: TimeInterval = 24 * 3600
    /// 网络超时
    private let timeout: TimeInterval = 10

    /// release 中的可下载产物。优先 ZIP（自动更新流程更稳，不需要 hdiutil），DMG 兜底。
    struct ReleaseAssets {
        let zipURL: URL?
        let zipSize: Int64?
        let dmgURL: URL?
        let dmgSize: Int64?

        /// 自动更新优先选 zip，没有则用 dmg
        var preferredDownload: (url: URL, isZip: Bool, size: Int64?)? {
            if let zip = zipURL { return (zip, true, zipSize) }
            if let dmg = dmgURL { return (dmg, false, dmgSize) }
            return nil
        }
    }

    enum Outcome {
        case upToDate(current: String)
        case newer(current: String, latest: String, releaseURL: URL, assets: ReleaseAssets)
        case error(String)
    }

    /// 当前 app 的语义版本（取自 CFBundleShortVersionString）
    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    /// 启动时调用：24h 内已查过则跳过。结果通过 .updateAvailable 通知广播。
    func checkOnLaunchIfNeeded() {
        let last = UserDefaults.standard.double(forKey: UDKey.lastUpdateCheckAt)
        if Date().timeIntervalSince1970 - last < checkInterval { return }
        Task {
            let result = await self.fetch()
            await MainActor.run { self.persist(result) }
        }
    }

    /// 用户主动检查（菜单栏「检查更新...」），无防抖。
    func checkManually(_ completion: @escaping (Outcome) -> Void) {
        Task {
            let result = await self.fetch()
            await MainActor.run {
                self.persist(result)
                completion(result)
            }
        }
    }

    // MARK: - 内部

    @MainActor
    private func persist(_ result: Outcome) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastUpdateCheckAt)
        switch result {
        case .newer(_, let latest, _, _):
            UserDefaults.standard.set(latest, forKey: UDKey.lastKnownLatestVersion)
            NotificationCenter.default.post(name: .updateAvailable, object: result)
        case .upToDate:
            // 用户已升上来，清掉旧"新版本"角标提示
            UserDefaults.standard.removeObject(forKey: UDKey.lastKnownLatestVersion)
        case .error:
            break
        }
    }

    /// candidate > baseline 时返回 true（语义版本数值比较）
    static func isVersionNewer(_ candidate: String, than baseline: String) -> Bool {
        let cv = candidate.split(separator: ".").compactMap { Int($0) }
        let bv = baseline.split(separator: ".").compactMap { Int($0) }
        let n = max(cv.count, bv.count)
        for i in 0..<n {
            let c = i < cv.count ? cv[i] : 0
            let b = i < bv.count ? bv[i] : 0
            if c > b { return true }
            if c < b { return false }
        }
        return false
    }

    private func fetch() async -> Outcome {
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else {
            return .error("URL 构造失败")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Snap2-UpdateChecker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("无效响应")
            }
            // 404 通常意味着仓库还没有正式 publish 过 release（只有 tag）
            if http.statusCode == 404 {
                return .error("尚未发布 Release。请到 GitHub 先 Publish release 并上传产物。")
            }
            guard http.statusCode == 200 else {
                return .error("GitHub 返回 HTTP \(http.statusCode)")
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .error("解析 release 失败")
            }
            guard let parsed = parseRelease(obj) else {
                return .error("未找到有效版本号")
            }

            switch compare(currentVersion, parsed.semver) {
            case .orderedAscending:
                return .newer(current: currentVersion,
                              latest: parsed.semver,
                              releaseURL: parsed.releaseURL,
                              assets: parsed.assets)
            default:
                return .upToDate(current: currentVersion)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private struct ParsedRelease {
        let semver: String
        let releaseURL: URL
        let assets: ReleaseAssets
    }

    /// 从 /releases/latest 响应中提取版本号、release 页面 URL 与下载资产
    private func parseRelease(_ obj: [String: Any]) -> ParsedRelease? {
        guard let tagName = obj["tag_name"] as? String else { return nil }
        let stripped = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        guard !stripped.split(separator: ".").compactMap({ Int($0) }).isEmpty else { return nil }

        let releaseURL = (obj["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/\(repoSlug)/releases/tag/\(tagName)")
            ?? URL(string: "https://github.com/\(repoSlug)/releases")!

        let rawAssets = (obj["assets"] as? [[String: Any]]) ?? []
        var zipURL: URL?
        var zipSize: Int64?
        var dmgURL: URL?
        var dmgSize: Int64?
        for asset in rawAssets {
            guard let name = (asset["name"] as? String)?.lowercased(),
                  let dl = asset["browser_download_url"] as? String,
                  let url = URL(string: dl) else { continue }
            let size = (asset["size"] as? Int64) ?? (asset["size"] as? NSNumber).map { $0.int64Value }
            if name.hasSuffix(".zip"), zipURL == nil {
                zipURL = url
                zipSize = size
            } else if name.hasSuffix(".dmg"), dmgURL == nil {
                dmgURL = url
                dmgSize = size
            }
        }

        return ParsedRelease(
            semver: stripped,
            releaseURL: releaseURL,
            assets: ReleaseAssets(zipURL: zipURL, zipSize: zipSize,
                                  dmgURL: dmgURL, dmgSize: dmgSize)
        )
    }

    private func compare(_ a: String, _ b: String) -> ComparisonResult {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        return compareInts(av, bv)
    }

    private func compareInts(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        let n = max(a.count, b.count)
        for i in 0..<n {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }
}
