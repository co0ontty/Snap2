import AppKit
import CoreGraphics
import Foundation

/// 系统设置当前主窗口的快照——位置 + 尺寸 + 所在屏幕的 visibleFrame。
struct SettingsWindowSnapshot: Equatable {
    let pid: pid_t
    let frame: CGRect
    let visibleFrame: CGRect
}

/// 定位「系统设置」（com.apple.systempreferences）的最前窗口。
///
/// 实现照搬 Permiso 原版：
/// 1. 先确认系统设置是前台应用，否则不返回（气泡此时应该隐藏）。
/// 2. 用 `CGWindowListCopyWindowInfo` 取所有可见窗口，按 ownerPID 过滤。
/// 3. 取最大的那一扇（系统设置可能有多个辅助窗口，只贴主窗口下方）。
/// 4. CoreGraphics 坐标系是左上原点、AppKit 是左下原点，多屏场景下还要找到这个
///    frame 落在哪块屏幕上，做翻转换算。
enum SettingsWindowLocator {
    static let bundleIdentifier = "com.apple.systempreferences"

    static var isSystemSettingsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
    }

    static func frontmostWindow() -> SettingsWindowSnapshot? {
        guard isSystemSettingsFrontmost else { return nil }

        // 用 activationPolicy 排序选「正常应用」实例，避免 .prohibited 的辅助进程。
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .max(by: { lhs, rhs in
                (lhs.activationPolicy == .prohibited ? 0 : 1)
                    < (rhs.activationPolicy == .prohibited ? 0 : 1)
            }) else { return nil }

        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], .zero
        ) as? [[String: Any]] else { return nil }

        let candidates = windowInfo.compactMap { info -> SettingsWindowSnapshot? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == app.processIdentifier else { return nil }
            // layer == 0 是普通文档窗口，过滤掉 menu、tooltip 这类辅助层级。
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }

            let cgFrame = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            let converted = appKitGeometry(from: cgFrame)
            let frame = converted.frame
            // 太小的尺寸大概率是子窗口/抽屉，不是设置主窗口。
            guard frame.width > 320, frame.height > 240 else { return nil }
            return SettingsWindowSnapshot(
                pid: ownerPID,
                frame: frame,
                visibleFrame: converted.visibleFrame
            )
        }

        // 取面积最大的——系统设置的主窗口一定比辅助 sheet 大。
        return candidates.max(by: { $0.frame.width * $0.frame.height
                                  < $1.frame.width * $1.frame.height })
    }

    /// CoreGraphics(左上原点) → AppKit(左下原点) 的坐标转换。
    /// 多屏环境下要找到 cgFrame 主要落在哪块屏，再用那块屏的 frame.maxY 翻转。
    private static func appKitGeometry(from cgFrame: CGRect)
        -> (frame: CGRect, visibleFrame: CGRect)
    {
        let screens = NSScreen.screens.compactMap {
            screen -> (frame: CGRect, visibleFrame: CGRect, cgBounds: CGRect)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return (
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                cgBounds: CGDisplayBounds(displayID)
            )
        }

        // 选交集面积最大的那块屏
        let matched = screens
            .filter { $0.cgBounds.intersects(cgFrame) }
            .max { lhs, rhs in
                let l = lhs.cgBounds.intersection(cgFrame)
                let r = rhs.cgBounds.intersection(cgFrame)
                return l.width * l.height < r.width * r.height
            }

        guard let screen = matched else {
            // 兜底：直接用主屏 visibleFrame，frame 原样返回（极少触发）
            let fallback = NSScreen.main?.visibleFrame
                ?? CGRect(origin: .zero, size: cgFrame.size)
            return (frame: cgFrame, visibleFrame: fallback)
        }

        let localX = cgFrame.minX - screen.cgBounds.minX
        let localY = cgFrame.minY - screen.cgBounds.minY
        let frame = CGRect(
            x: screen.frame.minX + localX,
            y: screen.frame.maxY - localY - cgFrame.height,
            width: cgFrame.width,
            height: cgFrame.height
        )
        return (frame: frame, visibleFrame: screen.visibleFrame)
    }
}
