import Foundation

/// 通过 GitHub Releases API 检查 Snap² 是否有新版本。
/// 不依赖 Sparkle 等外部框架，仅用 URLSession + JSONSerialization。
///
/// 通道：
/// - 稳定通道：/releases/latest（GitHub 自动排除 pre-release）
/// - Beta 通道：/releases?per_page=20 → 取 published_at 最大的非 draft（含 pre-release）
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

    /// 当前 app 的语义版本（取自 CFBundleShortVersionString，可能含 -<commit4> 后缀）
    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    /// 是否订阅 Beta（commit）更新通道
    var useBetaChannel: Bool {
        UserDefaults.standard.bool(forKey: UDKey.betaUpdates)
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

    /// Beta 通道切换时调用：清理上次"最新版本"缓存，避免旧的 beta 提示在通道关闭后仍残留。
    func invalidateCacheForChannelChange() {
        UserDefaults.standard.removeObject(forKey: UDKey.lastUpdateCheckAt)
        UserDefaults.standard.removeObject(forKey: UDKey.lastKnownLatestVersion)
        // 让现有 UI（菜单栏角标、设置窗口"升级"胶囊）先回到无更新状态
        NotificationCenter.default.post(
            name: .updateNotAvailable,
            object: Outcome.upToDate(current: currentVersion)
        )
    }

    // MARK: - 内部

    @MainActor
    private func persist(_ result: Outcome) {
        switch result {
        case .newer(_, let latest, _, _):
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastUpdateCheckAt)
            UserDefaults.standard.set(latest, forKey: UDKey.lastKnownLatestVersion)
            NotificationCenter.default.post(name: .updateAvailable, object: result)
        case .upToDate:
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UDKey.lastUpdateCheckAt)
            // 用户已升上来，清掉旧"新版本"角标提示
            UserDefaults.standard.removeObject(forKey: UDKey.lastKnownLatestVersion)
            NotificationCenter.default.post(name: .updateNotAvailable, object: result)
        case .error:
            // 不写入 lastUpdateCheckAt：允许下次启动重新尝试，避免一次网络抖动锁死 24h
            break
        }
    }

    /// 解析后的版本号：数字段 + 可选后缀（commit hash 前 4 位）
    struct ParsedVersion {
        let numbers: [Int]
        let suffix: String?

        static func parse(_ raw: String) -> ParsedVersion {
            let stripped = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
            let parts = stripped.split(separator: "-", maxSplits: 1,
                                       omittingEmptySubsequences: true)
            let numPart = parts.first.map(String.init) ?? stripped
            let nums = numPart.split(separator: ".").compactMap { Int($0) }
            let sfx: String? = parts.count > 1 ? String(parts[1]) : nil
            return ParsedVersion(numbers: nums, suffix: sfx)
        }
    }

    /// candidate > baseline 时返回 true。
    /// 规则：
    ///   1. 数字段从高位到低位逐位比较；任意一位较大则胜出；
    ///   2. 数字段全部相同时：
    ///      - 两边都无后缀 → 同一版本，不更新；
    ///      - candidate 无后缀、baseline 有后缀 → 稳定版优于同号 beta，可更新（用户从 beta 升到 stable）；
    ///      - candidate 有后缀、baseline 无后缀 → 仅在 fetch 走 beta 端点时可能命中，视为同号有更新 beta；
    ///      - 两边都有后缀且不同 → 调用方已挑出"最新候选"，视为可更新。
    static func isVersionNewer(_ candidate: String, than baseline: String) -> Bool {
        let c = ParsedVersion.parse(candidate)
        let b = ParsedVersion.parse(baseline)
        let n = max(c.numbers.count, b.numbers.count)
        for i in 0..<n {
            let cv = i < c.numbers.count ? c.numbers[i] : 0
            let bv = i < b.numbers.count ? b.numbers[i] : 0
            if cv > bv { return true }
            if cv < bv { return false }
        }
        switch (c.suffix, b.suffix) {
        case (nil, nil):       return false
        case (nil, _?):        return true
        case (_?, nil):        return true
        case let (a?, bb?):    return a != bb
        }
    }

    private func fetch() async -> Outcome {
        let useBeta = useBetaChannel
        let path = useBeta ? "/releases?per_page=20" : "/releases/latest"
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)\(path)") else {
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
            let json = try JSONSerialization.jsonObject(with: data)

            let releaseObj: [String: Any]?
            if useBeta {
                guard let arr = json as? [[String: Any]] else {
                    return .error("解析 release 列表失败")
                }
                releaseObj = pickLatestRelease(from: arr)
            } else {
                releaseObj = json as? [String: Any]
            }
            guard let obj = releaseObj else {
                return .error("没有可用的 Release")
            }
            guard let parsed = parseRelease(obj) else {
                return .error("未找到有效版本号")
            }

            if Self.isVersionNewer(parsed.semver, than: currentVersion) {
                return .newer(current: currentVersion,
                              latest: parsed.semver,
                              releaseURL: parsed.releaseURL,
                              assets: parsed.assets)
            }
            return .upToDate(current: currentVersion)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// 从 /releases 列表中挑出"最新"候选：排除 draft，按 published_at 取最大。
    private func pickLatestRelease(from arr: [[String: Any]]) -> [String: Any]? {
        let iso = ISO8601DateFormatter()
        let candidates = arr.filter { ($0["draft"] as? Bool) != true }
        return candidates.max { a, b in
            let da = (a["published_at"] as? String).flatMap(iso.date(from:)) ?? .distantPast
            let db = (b["published_at"] as? String).flatMap(iso.date(from:)) ?? .distantPast
            return da < db
        }
    }

    private struct ParsedRelease {
        let semver: String
        let releaseURL: URL
        let assets: ReleaseAssets
    }

    /// 从单个 release 对象中提取版本号、release 页面 URL 与下载资产
    private func parseRelease(_ obj: [String: Any]) -> ParsedRelease? {
        guard let tagName = obj["tag_name"] as? String else { return nil }
        let stripped = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        // 至少要有一段数字（"1.2.3" 或 "1.2.3-abcd" 都能通过；纯字符串 tag 被拒）
        let parsed = ParsedVersion.parse(stripped)
        guard !parsed.numbers.isEmpty else { return nil }

        let releaseURL = (obj["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/\(repoSlug)/releases/tag/\(tagName)")
            ?? URL(string: "https://github.com/\(repoSlug)/releases")!

        let rawAssets = (obj["assets"] as? [[String: Any]]) ?? []

        // 当前进程架构（universal 下随实际加载架构）
        #if arch(arm64)
        let archHints = ["arm64", "aarch64", "applesilicon"]
        #elseif arch(x86_64)
        let archHints = ["x86_64", "x86-64", "intel", "amd64"]
        #else
        let archHints: [String] = []
        #endif

        // 1) 先尽量挑出名字含本架构标识的 zip / dmg
        // 2) 再退化到第一个 zip / dmg 作为兜底
        var zipURL: URL?
        var zipSize: Int64?
        var dmgURL: URL?
        var dmgSize: Int64?
        var fallbackZipURL: URL?
        var fallbackZipSize: Int64?
        var fallbackDmgURL: URL?
        var fallbackDmgSize: Int64?

        for asset in rawAssets {
            guard let name = (asset["name"] as? String)?.lowercased(),
                  let dl = asset["browser_download_url"] as? String,
                  let url = URL(string: dl) else { continue }
            let size = (asset["size"] as? Int64) ?? (asset["size"] as? NSNumber).map { $0.int64Value }
            let matchesArch = archHints.contains { name.contains($0) }
            if name.hasSuffix(".zip") {
                if matchesArch, zipURL == nil {
                    zipURL = url; zipSize = size
                } else if fallbackZipURL == nil {
                    fallbackZipURL = url; fallbackZipSize = size
                }
            } else if name.hasSuffix(".dmg") {
                if matchesArch, dmgURL == nil {
                    dmgURL = url; dmgSize = size
                } else if fallbackDmgURL == nil {
                    fallbackDmgURL = url; fallbackDmgSize = size
                }
            }
        }

        if zipURL == nil { zipURL = fallbackZipURL; zipSize = fallbackZipSize }
        if dmgURL == nil { dmgURL = fallbackDmgURL; dmgSize = fallbackDmgSize }

        return ParsedRelease(
            semver: stripped,
            releaseURL: releaseURL,
            assets: ReleaseAssets(zipURL: zipURL, zipSize: zipSize,
                                  dmgURL: dmgURL, dmgSize: dmgSize)
        )
    }
}
