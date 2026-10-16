// 菜单栏图标 + 菜单(浮窗上右键同一份菜单)

import AppKit

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

final class MenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = Settings.shared
        for item in menu.items {
            switch item.action {
            case #selector(Coordinator.toggle): item.state = captureMode ? .on : .off
            case #selector(Coordinator.toggleKeyboard): item.state = s.keyboardCapture ? .on : .off
            case #selector(Coordinator.toggleMouse): item.state = s.mouseCapture ? .on : .off
            case #selector(Coordinator.toggleWindow): item.title = chatPanel.isVisible ? "隐藏浮窗" : "显示浮窗"
            case #selector(Coordinator.openAccessibility): item.isHidden = accessibilityTrusted()
            default: break
            }
        }
    }
}

private let menuDelegate = MenuDelegate()

private func makeMenu() -> NSMenu {
    let m = NSMenu()
    m.delegate = menuDelegate
    func item(_ title: String, _ sel: Selector, _ key: String = "") {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = coordinator
        m.addItem(i)
    }
    item("显示浮窗", #selector(Coordinator.toggleWindow))
    m.addItem(.separator())
    item("接管 UU 键鼠(⌘⌥G)", #selector(Coordinator.toggle))
    item("　键盘接管", #selector(Coordinator.toggleKeyboard))
    item("　鼠标接管(紫色光标)", #selector(Coordinator.toggleMouse))
    m.addItem(.separator())
    item("⚠ 授予辅助功能权限…", #selector(Coordinator.openAccessibility))
    item("设置…", #selector(Coordinator.showSettings), ",")
    item("GitHub 主页", #selector(Coordinator.openRepo))
    m.addItem(.separator())
    item("退出 uuchat", #selector(Coordinator.quit), "q")
    return m
}

func installStatusItem() {
    if let b = statusItem.button {
        b.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: "uuchat")
        b.image?.isTemplate = true
        if b.image == nil { b.title = "💬" }
    }
    statusItem.menu = makeMenu()
    chatPanel.contentView?.menu = makeMenu()        // 浮窗上右键同样可用
}
