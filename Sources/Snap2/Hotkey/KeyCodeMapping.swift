import AppKit
import Carbon.HIToolbox

// MARK: - 键码映射工具
/// 提供 Carbon 虚拟键码到可读字符串的映射，以及修饰键符号显示

enum KeyCodeMapping {

    // MARK: - 常用键码常量
    static let kVKA: UInt32         = UInt32(kVK_ANSI_A)
    static let kVKS: UInt32         = UInt32(kVK_ANSI_S)
    static let kVKD: UInt32         = UInt32(kVK_ANSI_D)
    static let kVKF: UInt32         = UInt32(kVK_ANSI_F)
    static let kVKX: UInt32         = UInt32(kVK_ANSI_X)
    static let kVKC: UInt32         = UInt32(kVK_ANSI_C)
    static let kVKV: UInt32         = UInt32(kVK_ANSI_V)
    static let kVKZ: UInt32         = UInt32(kVK_ANSI_Z)
    static let kVK1: UInt32         = UInt32(kVK_ANSI_1)
    static let kVK2: UInt32         = UInt32(kVK_ANSI_2)
    static let kVK3: UInt32         = UInt32(kVK_ANSI_3)
    static let kVK4: UInt32         = UInt32(kVK_ANSI_4)
    static let kVK5: UInt32         = UInt32(kVK_ANSI_5)
    static let kVKSpace: UInt32     = UInt32(kVK_Space)
    static let kVKReturn: UInt32    = UInt32(kVK_Return)
    static let kVKEscape: UInt32    = UInt32(kVK_Escape)
    static let kVKDelete: UInt32    = UInt32(kVK_Delete)
    static let kVKTab: UInt32       = UInt32(kVK_Tab)

    // MARK: - keyCode 到显示字符串的映射表
    /// 将 Carbon 虚拟键码转换为用户可读的字符串
    static let keyCodeToString: [UInt32: String] = [
        // 字母键
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",

        // 数字键
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",

        // 功能键
        UInt32(kVK_F1):  "F1",
        UInt32(kVK_F2):  "F2",
        UInt32(kVK_F3):  "F3",
        UInt32(kVK_F4):  "F4",
        UInt32(kVK_F5):  "F5",
        UInt32(kVK_F6):  "F6",
        UInt32(kVK_F7):  "F7",
        UInt32(kVK_F8):  "F8",
        UInt32(kVK_F9):  "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",

        // 特殊键
        UInt32(kVK_Space):           "Space",
        UInt32(kVK_Return):          "↩",
        UInt32(kVK_Tab):             "⇥",
        UInt32(kVK_Delete):          "⌫",
        UInt32(kVK_ForwardDelete):   "⌦",
        UInt32(kVK_Escape):          "⎋",
        UInt32(kVK_Home):            "↖",
        UInt32(kVK_End):             "↘",
        UInt32(kVK_PageUp):          "⇞",
        UInt32(kVK_PageDown):        "⇟",

        // 方向键
        UInt32(kVK_UpArrow):         "↑",
        UInt32(kVK_DownArrow):       "↓",
        UInt32(kVK_LeftArrow):       "←",
        UInt32(kVK_RightArrow):      "→",

        // 符号键
        UInt32(kVK_ANSI_Minus):         "-",
        UInt32(kVK_ANSI_Equal):         "=",
        UInt32(kVK_ANSI_LeftBracket):   "[",
        UInt32(kVK_ANSI_RightBracket):  "]",
        UInt32(kVK_ANSI_Backslash):     "\\",
        UInt32(kVK_ANSI_Semicolon):     ";",
        UInt32(kVK_ANSI_Quote):         "'",
        UInt32(kVK_ANSI_Comma):         ",",
        UInt32(kVK_ANSI_Period):        ".",
        UInt32(kVK_ANSI_Slash):         "/",
        UInt32(kVK_ANSI_Grave):         "`",
    ]

    // MARK: - 获取键码对应的字符串
    /// 将键码转换为显示字符串，未知键码返回 "???"
    static func stringForKeyCode(_ keyCode: UInt32) -> String {
        return keyCodeToString[keyCode] ?? "???"
    }

    // MARK: - 修饰键符号映射
    /// 将 NSEvent.ModifierFlags 转换为 macOS 标准符号字符串
    /// 按照 Apple HIG 标准顺序：⌃⌥⇧⌘
    static func symbolsForModifiers(_ modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) {
            symbols += "⌃"
        }
        if modifiers.contains(.option) {
            symbols += "⌥"
        }
        if modifiers.contains(.shift) {
            symbols += "⇧"
        }
        if modifiers.contains(.command) {
            symbols += "⌘"
        }
        return symbols
    }

    // MARK: - 将 Carbon 修饰键转换为符号字符串
    /// 将 Carbon 修饰键掩码转换为 macOS 标准符号字符串
    static func symbolsForCarbonModifiers(_ carbonModifiers: UInt32) -> String {
        let cocoaFlags = HotkeyManager.cocoaModifiers(from: carbonModifiers)
        return symbolsForModifiers(cocoaFlags)
    }

    // MARK: - 组合快捷键显示字符串
    /// 生成完整的快捷键显示字符串，如 "⌃⇧A"
    /// - Parameters:
    ///   - keyCode: Carbon 虚拟键码
    ///   - modifiers: NSEvent.ModifierFlags 修饰键
    /// - Returns: 组合快捷键的显示字符串
    static func displayString(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        let modSymbols = symbolsForModifiers(modifiers)
        let keyString  = stringForKeyCode(keyCode)
        return modSymbols + keyString
    }

    /// 使用 Carbon 修饰键生成显示字符串
    static func displayString(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        let modSymbols = symbolsForCarbonModifiers(carbonModifiers)
        let keyString  = stringForKeyCode(keyCode)
        return modSymbols + keyString
    }
}
