import CoreGraphics
import Foundation

/// 一次"多显示器并行冻结"任务。
///
/// 为什么必须并行：`CGDisplayCreateImage` 同步抓单屏约 30~80ms（5K 屏更慢）。
/// 旧实现按屏幕串行循环，多屏总耗时很容易超过用户松开快捷键的时间（~100-300ms）。
/// Carbon 热键只吞 keyDown，松键产生的 keyUp / flagsChanged 仍会投递给前台 app，
/// hover / tooltip 在第二、三块屏读完 framebuffer 之前就被撤掉——这是"偶发消失"
/// 的主要来源之一。并行把总耗时压到 ≈ 最慢的单屏。
///
/// 为什么用 CGDisplayCreateImage 而不是 ScreenCaptureKit：
/// `SCShareableContent` + `SCScreenshotManager.captureImage` 都是 async，await 会让出
/// 主线程，期间主 runloop 被 pump，任何插队的激活/焦点事件都可能让前台 app resign
/// active → hover 提前消失。`CGDisplayCreateImage` 同步返回、不让出主线程、不依赖
/// AppKit，天然可并发（各显示器是独立 surface）。
///
/// 两条使用路径（见 CaptureManager）：
///  - **预冻结抢跑**：修饰键按满那一刻在后台 init，不等结果；稍后热键路径 `wait` 取帧；
///  - **热键补抓**：init 后立即在主线程有界 `wait`，只补预冻结缺失/过期/失败的屏。
///
/// 注意：CG 抓的是 framebuffer 全量，无法排除自身窗口——调用方必须保证抓取时刻
/// 屏幕上没有 Snap² 的 overlay（预冻结和热键补抓都发生在 overlay 创建之前，天然满足）。
final class ParallelDisplayFreezer {

    /// 单块显示器的冻结结果：原始像素 CGImage + 逻辑点尺寸。
    /// pointSize 传 NSScreen.frame.size；CGDisplayCreateImage 自动按显示器物理像素
    /// 抓取（已含 Retina），返回的像素尺寸 = frameSize × scale，下游 SelectionView
    /// 用 像素/点 反推 scale。
    struct FrozenFrame {
        let cgImage: CGImage
        let pointSize: NSSize
    }

    /// 后台线程安全的抓取请求。NSScreen 只能主线程访问，调用方先在主线程拆成标量。
    struct Request {
        let displayID: CGDirectDisplayID
        let frameSize: NSSize
    }

    /// 并发抓取队列。QoS 用 userInteractive：冻结是用户正等着的关键路径。
    private static let captureQueue = DispatchQueue(
        label: "snap2.display-freezer",
        qos: .userInteractive,
        attributes: .concurrent
    )

    private let lock = NSLock()
    private var results: [CGDirectDisplayID: FrozenFrame] = [:]
    private let group = DispatchGroup()

    /// 抓取发起时刻，用于热键路径判断预冻结帧是否仍然"新鲜"。
    let startedAt: DispatchTime

    init(requests: [Request]) {
        startedAt = .now()
        for request in requests where request.displayID != 0 {
            group.enter()
            Self.captureQueue.async { [self] in
                defer { group.leave() }
                guard let cgImage = CGDisplayCreateImage(request.displayID) else {
                    NSLog("[DisplayFreezer] 冻结失败: CGDisplayCreateImage 返回 nil (displayID=\(request.displayID))")
                    return
                }
                lock.lock()
                results[request.displayID] = FrozenFrame(
                    cgImage: cgImage,
                    pointSize: request.frameSize
                )
                lock.unlock()
            }
        }
    }

    /// 有界等待所有抓取收尾，返回已到手的帧；超时也返回部分结果（缺的屏由调用方兜底）。
    /// 主线程调用会短暂阻塞主 runloop——这正是想要的：冻结期间不 pump 任何焦点事件。
    func wait(timeout: DispatchTimeInterval) -> [CGDirectDisplayID: FrozenFrame] {
        _ = group.wait(timeout: .now() + timeout)
        lock.lock()
        defer { lock.unlock() }
        return results
    }

    /// 距抓取发起已过去的毫秒数（供"预冻结是否过期"判断）。
    var ageMilliseconds: Double {
        Double(DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
    }
}
