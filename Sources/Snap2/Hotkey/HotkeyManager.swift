import AppKit
import Carbon.HIToolbox

// MARK: - 全局快捷键管理器
/// Carbon API 注册系统级全局热键。
///
/// 设计：每个 `Action` 对应一个独立的 Carbon hotkey 槽位。事件回调按 `hotkeyID.id`
/// 反查 Action，再派发到对应的 Notification——这样新增热键只要在 `Action` 枚举里加一
/// 个 case + 默认值映射即可，无需改回调底层。
final class HotkeyManager {

    // MARK: - 单例
    static let shared = HotkeyManager()

    // MARK: - Action 定义
    /// 一个 Action = 一个独立可绑定的全局热键
    enum Action: UInt32, CaseIterable {
        case capture = 1
        case record  = 2

        /// 触发后要发出的 Notification
        var notification: Notification.Name {
            switch self {
            case .capture: return .captureRequested
            case .record:  return .recordingRequested
            }
        }

        /// UserDefaults 持久化 key（keyCode / modifiers 各一）
        var keyCodeUDKey: String {
            switch self {
            case .capture: return UDKey.hotkeyKeyCode
            case .record:  return UDKey.recordingHotkeyKeyCode
            }
        }
        var modifiersUDKey: String {
            switch self {
            case .capture: return UDKey.hotkeyModifiers
            case .record:  return UDKey.recordingHotkeyModifiers
            }
        }

        /// 默认 keyCode / Carbon 修饰键
        var defaultKeyCode: UInt32 {
            switch self {
            case .capture: return UInt32(kVK_ANSI_A)
            case .record:  return UInt32(kVK_ANSI_R)
            }
        }
        var defaultCarbonModifiers: UInt32 {
            switch self {
            case .capture, .record:
                return UInt32(controlKey | shiftKey)
            }
        }
    }

    // MARK: - 内部状态
    private struct Binding {
        var keyCode: UInt32
        var modifiers: UInt32  // Carbon
        var ref: EventHotKeyRef?
    }

    private var bindings: [Action: Binding] = [:]
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = OSType(0x534E5032)  // "SNP2"

    // MARK: - 兼容旧 API（供菜单显示当前截图热键用）
    var currentKeyCode: UInt32   { bindings[.capture]?.keyCode ?? Action.capture.defaultKeyCode }
    var currentModifiers: UInt32 { bindings[.capture]?.modifiers ?? Action.capture.defaultCarbonModifiers }

    // MARK: - 初始化
    private init() {
        loadAllFromDefaults()
        installEventHandler()
        registerAll()
    }

    deinit {
        unregisterAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - 读取持久化
    private func loadAllFromDefaults() {
        let defaults = UserDefaults.standard
        for action in Action.allCases {
            let kc: UInt32
            let mods: UInt32
            if defaults.object(forKey: action.keyCodeUDKey) != nil {
                kc   = UInt32(defaults.integer(forKey: action.keyCodeUDKey))
                mods = UInt32(defaults.integer(forKey: action.modifiersUDKey))
            } else {
                kc   = action.defaultKeyCode
                mods = action.defaultCarbonModifiers
            }
            bindings[action] = Binding(keyCode: kc, modifiers: mods, ref: nil)
        }
    }

    private func saveToDefaults(_ action: Action) {
        guard let b = bindings[action] else { return }
        let defaults = UserDefaults.standard
        defaults.set(Int(b.keyCode), forKey: action.keyCodeUDKey)
        defaults.set(Int(b.modifiers), forKey: action.modifiersUDKey)
    }

    // MARK: - Carbon 事件处理器
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventCallback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
        if status != noErr {
            NSLog("[HotkeyManager] 安装事件处理器失败，错误码: \(status)")
        }
    }

    // MARK: - 注册 / 注销
    private func registerAll() {
        for action in Action.allCases {
            register(action)
        }
    }

    private func register(_ action: Action) {
        guard var b = bindings[action] else { return }
        unregister(action)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            b.keyCode,
            b.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            b.ref = ref
            bindings[action] = b
        } else {
            NSLog("[HotkeyManager] 注册热键失败 (\(action))，错误码: \(status)")
        }
    }

    private func unregister(_ action: Action) {
        guard var b = bindings[action], let ref = b.ref else { return }
        UnregisterEventHotKey(ref)
        b.ref = nil
        bindings[action] = b
    }

    private func unregisterAll() {
        for action in Action.allCases {
            unregister(action)
        }
    }

    /// AppDelegate.applicationWillTerminate 调用
    func unregisterHotkey() {
        unregisterAll()
    }

    // MARK: - 公开 API
    func keyCode(for action: Action) -> UInt32 {
        bindings[action]?.keyCode ?? action.defaultKeyCode
    }
    func modifiers(for action: Action) -> UInt32 {
        bindings[action]?.modifiers ?? action.defaultCarbonModifiers
    }

    /// 与其它 action 的快捷键冲突错误
    enum UpdateError: Error {
        /// 该组合已被另一个 action 占用。返回占用方便于 UI 提示。
        case conflict(occupiedBy: Action)
    }

    /// 更新某个 action 的快捷键并持久化。
    /// 冲突时（同样 keyCode + modifiers 已被另一个 action 占用）拒绝写入，
    /// 返回 .failure(.conflict(occupiedBy:))，UI 据此 flash 警告。
    @discardableResult
    func updateHotkey(_ action: Action,
                      keyCode: UInt32,
                      modifiers: UInt32) -> Result<Void, UpdateError>
    {
        if let conflicting = conflictingAction(forKeyCode: keyCode,
                                                modifiers: modifiers,
                                                excluding: action)
        {
            return .failure(.conflict(occupiedBy: conflicting))
        }
        bindings[action] = Binding(keyCode: keyCode, modifiers: modifiers, ref: nil)
        saveToDefaults(action)
        register(action)
        NotificationCenter.default.post(name: .hotkeyChanged, object: action)
        return .success(())
    }

    /// 检查是否有其它 action 已绑定相同 keyCode + modifiers
    private func conflictingAction(forKeyCode keyCode: UInt32,
                                   modifiers: UInt32,
                                   excluding self_: Action) -> Action?
    {
        for (act, b) in bindings where act != self_ {
            if b.keyCode == keyCode && b.modifiers == modifiers {
                return act
            }
        }
        return nil
    }

    /// 旧 API：默认指截图热键
    @discardableResult
    func updateHotkey(keyCode: UInt32, modifiers: UInt32) -> Result<Void, UpdateError> {
        updateHotkey(.capture, keyCode: keyCode, modifiers: modifiers)
    }

    @discardableResult
    func resetToDefault(_ action: Action) -> Result<Void, UpdateError> {
        updateHotkey(action, keyCode: action.defaultKeyCode, modifiers: action.defaultCarbonModifiers)
    }

    /// 旧 API：默认指截图热键
    @discardableResult
    func resetToDefault() -> Result<Void, UpdateError> {
        resetToDefault(.capture)
    }

    /// 给 UI 用的人类可读名称
    static func displayName(for action: Action) -> String {
        switch action {
        case .capture: return "区域截图"
        case .record:  return "区域录屏"
        }
    }

    // MARK: - 修饰键互转
    static func carbonModifiers(from cocoaModifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if cocoaModifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaModifiers.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if cocoaModifiers.contains(.option)  { carbon |= UInt32(optionKey) }
        if cocoaModifiers.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
    static func cocoaModifiers(from carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonMods & UInt32(cmdKey) != 0    { flags.insert(.command) }
        if carbonMods & UInt32(shiftKey) != 0  { flags.insert(.shift) }
        if carbonMods & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonMods & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    // MARK: - 触发派发
    /// 由 C 回调通过 hotkeyID.id 反查到 Action 后回调。
    /// 录屏热键的 "toggle" 语义（idle→start、picking→cancel、recording→stop）由 AppDelegate 网关
    /// 按 RecordingManager.state 翻译。这里只发原始 action 通知，避免两条 notification 在同一 runloop
    /// 段相互抵消（同一热键既触发 start 又触发 stop）。
    fileprivate func dispatch(id: UInt32) {
        guard let action = Action(rawValue: id) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: action.notification, object: nil)
        }
    }
}

// MARK: - Carbon 事件回调（C 函数指针）
private func hotkeyEventCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }

    // 拿到 hotkeyID 反查 action
    var hkID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.dispatch(id: hkID.id)
    return noErr
}
