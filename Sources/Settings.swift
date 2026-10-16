// 用户设置: 内存里直接读写(事件回调里高频访问), didSet 时落盘并广播

import AppKit
import ServiceManagement

extension Notification.Name {
    static let uuSettingsChanged = Notification.Name("uuchat.settingsChanged")
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// 远端键盘接管: UU 注入的按键进远端输入框(含拼音组词), 不再打到本机焦点窗口
    var keyboardCapture: Bool { didSet { save("keyboardCapture", keyboardCapture) } }
    /// 远端鼠标接管: 双光标, 远端用紫色光标, 主机光标不受影响
    var mouseCapture: Bool { didSet { save("mouseCapture", mouseCapture) } }
    var alwaysOnTop: Bool { didSet { save("alwaysOnTop", alwaysOnTop) } }
    var windowOpacity: Double { didSet { save("windowOpacity", windowOpacity) } }
    var sound: Bool { didSet { save("sound", sound) } }
    var showOnLaunch: Bool { didSet { save("showOnLaunch", showOnLaunch) } }
    var debugLog: Bool { didSet { save("debugLog", debugLog) } }

    private init() {
        d.register(defaults: ["keyboardCapture": true, "mouseCapture": true, "alwaysOnTop": true,
                              "windowOpacity": 1.0, "sound": true, "showOnLaunch": true, "debugLog": false])
        keyboardCapture = d.bool(forKey: "keyboardCapture")
        mouseCapture = d.bool(forKey: "mouseCapture")
        alwaysOnTop = d.bool(forKey: "alwaysOnTop")
        windowOpacity = d.double(forKey: "windowOpacity")
        sound = d.bool(forKey: "sound")
        showOnLaunch = d.bool(forKey: "showOnLaunch")
        debugLog = d.bool(forKey: "debugLog")
    }

    private func save(_ key: String, _ value: Any) {
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: .uuSettingsChanged, object: nil)
    }

    /// 开机自启(SMAppService, 需要 App 在 /Applications 之类的正式位置)
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                appendLog(text: "开机自启设置失败: \(error.localizedDescription)(请把 App 放进「应用程序」再试)",
                          color: .systemOrange, prefix: "⚙设置")
            }
            NotificationCenter.default.post(name: .uuSettingsChanged, object: nil)
        }
    }
}
