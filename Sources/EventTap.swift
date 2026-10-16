// 全局事件拦截: HID 层 CGEventTap。真实输入一律放行; UU 注入的键鼠按设置接管

import AppKit
import ApplicationServices
import CoreGraphics

var activeTap: CFMachPort?

func accessibilityTrusted(prompt: Bool = false) -> Bool {
    let opts = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary   // = kAXTrustedCheckOptionPrompt
    return AXIsProcessTrustedWithOptions(opts)
}

func handleRemoteKeyDown(_ event: CGEvent) {
    let vk = event.getIntegerValueField(FIELD_KEYCODE)
    var len: Int = 0
    var uni = [UniChar](repeating: 0, count: 24)
    event.keyboardGetUnicodeString(maxStringLength: uni.count, actualStringLength: &len, unicodeString: &uni)
    let chars = String(utf16CodeUnits: uni, count: len)

    DispatchQueue.main.async {
        // 文本成品注入(手机端中文)或含非 ASCII: 直接进远端框, 不过 rime
        if let first = chars.first, let scalar = first.unicodeScalars.first,
           !scalar.isASCII || !chars.allSatisfy({ $0.isASCII }) {
            inputBuf += chars
            remoteField.stringValue = inputBuf
            return
        }
        if let ks = chars.first.flatMap(keysymFromChar(_:)) {
            feedRime(keysym: ks)
        } else {
            // 无字符键: 按虚拟键码补映射
            let keysym: Int32
            switch vk {
            case 51: keysym = 0xff08          // Backspace
            case 53: keysym = 0xff1b          // Esc
            case 36, 76: keysym = 0xff0d      // Return / 小键盘 Enter
            case 48: keysym = 0xff09          // Tab
            case 123: keysym = 0xff51         // ←
            case 124: keysym = 0xff53         // →
            case 125: keysym = 0xff54         // ↓
            case 126: keysym = 0xff52         // ↑
            default: keysym = 0
            }
            if keysym != 0 { feedRime(keysym: keysym) }
        }
    }
}

private func isMouse(_ t: CGEventType) -> Bool {
    switch t {
    case .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
         .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel: return true
    default: return false
    }
}

private func tapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                         _ ref: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = activeTap { CGEvent.tapEnable(tap: t, enable: true) }
        return nil
    }
    let mouse = isMouse(type)
    guard mouse || type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

    let upid = pid_t(event.getIntegerValueField(FIELD_UNIX_PID))
    let s = Settings.shared

    // ⌘⌥G = 全局切换键(吃掉, 防止 œ 进输入框)
    if type == .keyDown,
       event.getIntegerValueField(FIELD_KEYCODE) == Int64(kHotkeyCode),
       event.flags.intersection([.maskCommand, .maskAlternate]) == [.maskCommand, .maskAlternate] {
        DispatchQueue.main.async { toggleCapture() }
        return nil
    }
    if captureMode, s.mouseCapture, mouse, upid == 0 { handleHostMouse(event) }
    guard captureMode, upid != 0, remotePids.contains(upid) else { return Unmanaged.passUnretained(event) }
    if mouse {
        guard s.mouseCapture else { return Unmanaged.passUnretained(event) }
        handleRemoteMouse(type, event)
        return nil
    }
    guard s.keyboardCapture else { return Unmanaged.passUnretained(event) }
    if type == .keyDown { handleRemoteKeyDown(event) }
    return nil
}

/// 创建 tap; 没有辅助功能权限时返回 false
@discardableResult
func installTap() -> Bool {
    guard activeTap == nil else { return true }
    let types: [CGEventType] = [.keyDown, .keyUp, .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
    let mask: CGEventMask = types.reduce(0) { $0 | (1 << $1.rawValue) }
    guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                      options: .defaultTap, eventsOfInterest: mask,
                                      callback: tapCallback, userInfo: nil) else { return false }
    activeTap = tap
    CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .defaultMode)
    CGEvent.tapEnable(tap: tap, enable: true)
    hostPos = CGEvent(source: nil)?.location ?? .zero
    disableWarpSuppression()
    return true
}

/// 启动时调用: 有权限直接装 tap; 没有则弹系统授权提示并轮询, 授权后自动生效(无需重启)
func startTapWhenTrusted() {
    if installTap() { return }
    _ = accessibilityTrusted(prompt: true)
    appendLog(text: "需要「辅助功能」权限才能拦截 UU 的键鼠:系统设置 → 隐私与安全性 → 辅助功能 → 打开 uuchat",
              color: .systemOrange, prefix: "🔐权限")
    Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { t in
        if installTap() {
            t.invalidate()
            appendLog(text: "辅助功能已授权,键鼠接管已生效", color: .systemTeal, prefix: "🔐权限")
            NotificationCenter.default.post(name: .uuSettingsChanged, object: nil)
        }
    }
}

func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}

/// 总开关: 接管 ↔ 放行
func toggleCapture() {
    captureMode.toggle()
    if !captureMode { clearRimeComposition(); hideFakeCursor() }               // 放行: 清组词、收假光标
    else { hostPos = CGEvent(source: nil)?.location ?? hostPos }               // 接管: 以当前光标为主机位置
    appendLog(text: captureMode ? "接管:UU 注入的键鼠由 uuchat 处理" : "放行:UU 键鼠恢复原生行为",
              color: .systemOrange, prefix: "⚙切换")
    NotificationCenter.default.post(name: .uuSettingsChanged, object: nil)
}
