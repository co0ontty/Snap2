import AppKit
import Foundation

/// 自动下载 + 解压 + 替换正在运行的 .app + relaunch。
///
/// 流程：下载 zip/dmg → 解压到临时目录 → 写一个 helper bash 脚本 →
/// 由 helper 等当前进程退出后，覆盖原 .app 并 open 启动新版本。
///
/// 不依赖 Sparkle。zip 优先（ditto -xk），dmg 兜底（hdiutil attach/detach）。
final class UpdateInstaller: NSObject {

    enum Stage {
        case downloading(received: Int64, total: Int64)
        case extracting
        case readyToRelaunch(stagedAppPath: String)
        case failed(String)
    }

    typealias ProgressHandler = (Stage) -> Void

    static let shared = UpdateInstaller()
    private override init() {}

    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var progressHandler: ProgressHandler?
    private var isRunning = false

    /// 当前 app 是否处于可安装的位置（父目录可写）
    static var canInstallInPlace: Bool {
        let parent = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: parent)
    }

    func startUpdate(assets: UpdateChecker.ReleaseAssets,
                     progress: @escaping ProgressHandler) {
        guard !isRunning else { return }
        guard let pick = assets.preferredDownload else {
            progress(.failed("Release 没有可下载的产物（zip/dmg）"))
            return
        }
        isRunning = true
        progressHandler = progress
        downloadAsset(url: pick.url, isZip: pick.isZip, expectedSize: pick.size)
    }

    /// 用户确认重启更新：启动 helper 脚本并退出自身
    func relaunch(stagedAppPath: String) -> Result<Void, Error> {
        let destAppPath = Bundle.main.bundlePath
        do {
            let scriptPath = try writeHelperScript(
                parentPID: ProcessInfo.processInfo.processIdentifier,
                stagedAppPath: stagedAppPath,
                destAppPath: destAppPath
            )
            try launchHelper(scriptPath: scriptPath)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        isRunning = false
    }

    // MARK: - Download

    private func downloadAsset(url: URL, isZip: Bool, expectedSize: Int64?) {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForResource = 600
        let delegate = DownloadDelegate(
            isZip: isZip,
            onProgress: { [weak self] received, totalReported in
                let total = totalReported > 0 ? totalReported : (expectedSize ?? -1)
                self?.dispatch(.downloading(received: received, total: total))
            },
            onFinish: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let url):
                    self.process(downloaded: url, isZip: isZip)
                case .failure(let err):
                    self.dispatch(.failed("下载失败: \(err.localizedDescription)"))
                    self.isRunning = false
                }
            }
        )
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.setValue("Snap2-UpdateInstaller", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        downloadTask = task
        task.resume()
    }

    private func dispatch(_ stage: Stage) {
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(stage)
        }
    }

    // MARK: - Extract

    private func process(downloaded fileURL: URL, isZip: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.dispatch(.extracting)
            do {
                let stageDir = try self.makeStagingDir()
                let appPath: String
                if isZip {
                    appPath = try self.extractZip(fileURL.path, into: stageDir)
                } else {
                    appPath = try self.extractDMG(fileURL.path, into: stageDir)
                }
                try? FileManager.default.removeItem(at: fileURL)
                self.dispatch(.readyToRelaunch(stagedAppPath: appPath))
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                self.dispatch(.failed("解压失败: \(error.localizedDescription)"))
            }
            self.isRunning = false
        }
    }

    private func makeStagingDir() throws -> String {
        let cacheBase = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        let dir = (cacheBase as NSString)
            .appendingPathComponent("Snap2/Updates/staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func extractZip(_ zipPath: String, into dir: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-xk", zipPath, dir]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "UpdateInstaller", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "ditto 退出码 \(p.terminationStatus)"])
        }
        return try findApp(in: dir)
    }

    private func extractDMG(_ dmgPath: String, into dir: String) throws -> String {
        let mountPoint = (dir as NSString).appendingPathComponent("mnt")
        try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", "-nobrowse", "-noautoopen",
                            "-mountpoint", mountPoint, dmgPath]
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else {
            throw NSError(domain: "UpdateInstaller", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "hdiutil attach 失败"])
        }
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint, "-quiet", "-force"]
            try? detach.run()
            detach.waitUntilExit()
        }
        let mountedAppPath = try findApp(in: mountPoint)
        let stagedAppPath = (dir as NSString)
            .appendingPathComponent((mountedAppPath as NSString).lastPathComponent)
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        cp.arguments = [mountedAppPath, stagedAppPath]
        try cp.run()
        cp.waitUntilExit()
        guard cp.terminationStatus == 0 else {
            throw NSError(domain: "UpdateInstaller", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "ditto 拷出 .app 失败"])
        }
        return stagedAppPath
    }

    private func findApp(in directory: String) throws -> String {
        let fm = FileManager.default
        let firstLevel = (try? fm.contentsOfDirectory(atPath: directory)) ?? []
        for item in firstLevel where item.hasSuffix(".app") {
            return (directory as NSString).appendingPathComponent(item)
        }
        for item in firstLevel {
            let sub = (directory as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue else { continue }
            let inner = (try? fm.contentsOfDirectory(atPath: sub)) ?? []
            for s in inner where s.hasSuffix(".app") {
                return (sub as NSString).appendingPathComponent(s)
            }
        }
        throw NSError(domain: "UpdateInstaller", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "在解压目录未找到 .app"])
    }

    // MARK: - Helper script

    private func writeHelperScript(parentPID: Int32,
                                   stagedAppPath: String,
                                   destAppPath: String) throws -> String {
        let scriptPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("snap2-update-\(UUID().uuidString).sh")
        let staged = shellQuote(stagedAppPath)
        let dest = shellQuote(destAppPath)
        let stagedDir = shellQuote((stagedAppPath as NSString).deletingLastPathComponent)
        let script = """
        #!/bin/bash
        # Snap² update helper. 自动生成，请勿手动调用。
        set -u
        STAGED=\(staged)
        DEST=\(dest)
        STAGED_DIR=\(stagedDir)
        PARENT_PID=\(parentPID)

        # 等当前进程退出，最多 10s 兜底
        for _ in $(seq 1 50); do
            if ! kill -0 "$PARENT_PID" 2>/dev/null; then break; fi
            sleep 0.2
        done

        if [ -d "$DEST" ]; then
            rm -rf "$DEST" || exit 11
        fi
        /usr/bin/ditto "$STAGED" "$DEST" || exit 12
        # 清掉 quarantine bit，避免新版本被 Gatekeeper 二次拦截
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

        /usr/bin/open "$DEST"

        # 自删
        rm -rf "$STAGED_DIR"
        rm -f "$0"
        """
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: scriptPath)
        return scriptPath
    }

    private func shellQuote(_ s: String) -> String {
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func launchHelper(scriptPath: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [scriptPath]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        // 不等待，让子进程脱离父进程生命周期
    }
}

// MARK: - URLSession Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {

    private let isZip: Bool
    private let onProgress: (Int64, Int64) -> Void
    private let onFinish: (Result<URL, Error>) -> Void
    private var didFinish = false

    init(isZip: Bool,
         onProgress: @escaping (Int64, Int64) -> Void,
         onFinish: @escaping (Result<URL, Error>) -> Void) {
        self.isZip = isZip
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // delegate 返回后系统会删除 temp file，必须立刻 move
        let dst = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snap2-update-\(UUID().uuidString)")
            .appendingPathExtension(isZip ? "zip" : "dmg")
        do {
            try FileManager.default.moveItem(at: location, to: dst)
            didFinish = true
            onFinish(.success(dst))
        } catch {
            didFinish = true
            onFinish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let e = error, !didFinish {
            onFinish(.failure(e))
        }
    }
}
