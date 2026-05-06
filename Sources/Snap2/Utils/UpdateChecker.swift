import Foundation

/// 通过 GitHub Tags API 检查 Snap² 是否有新版本。
/// 不依赖 Sparkle 等外部框架，仅用 URLSession + JSONSerialization。
///
/// 用 tags 接口而非 releases/latest——后者要求显式发布 Release，
/// 仓库当前只推 tag，tags 接口对此场景更稳。
final class UpdateChecker {

    static let shared = UpdateChecker()
    private init() {}

    /// 仓库 owner/repo
    private let repoSlug = "co0ontty/Snap2"
    /// 启动检查的防抖间隔（秒）
    private let checkInterval: TimeInterval = 24 * 3600
    /// 网络超时
    private let timeout: TimeInterval = 10

    enum Outcome {
        case upToDate(current: String)
        case newer(current: String, latest: String, releaseURL: URL)
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
        case .newer(_, let latest, _):
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
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/tags") else {
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
            guard http.statusCode == 200 else {
                return .error("GitHub 返回 HTTP \(http.statusCode)")
            }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return .error("解析 tags 失败")
            }
            guard let best = pickLatestTag(in: arr) else {
                return .error("未找到有效版本标签")
            }
            let releaseURL = URL(string: "https://github.com/\(repoSlug)/releases/tag/\(best.rawTag)")
                ?? URL(string: "https://github.com/\(repoSlug)/releases")!

            switch compare(currentVersion, best.semver) {
            case .orderedAscending:
                return .newer(current: currentVersion, latest: best.semver, releaseURL: releaseURL)
            default:
                return .upToDate(current: currentVersion)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// 按语义版本数值排序挑出最高的（容忍非数字 tag、跳过 lexicographic 排序坑）
    private func pickLatestTag(in tags: [[String: Any]]) -> (rawTag: String, semver: String)? {
        let parsed: [(String, String, [Int])] = tags.compactMap { obj in
            guard let name = obj["name"] as? String else { return nil }
            let stripped = name.hasPrefix("v") ? String(name.dropFirst()) : name
            let parts = stripped.split(separator: ".").compactMap { Int($0) }
            guard !parts.isEmpty else { return nil }
            return (name, stripped, parts)
        }
        let best = parsed.max { lhs, rhs in
            compareInts(lhs.2, rhs.2) == .orderedAscending
        }
        return best.map { ($0.0, $0.1) }
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
