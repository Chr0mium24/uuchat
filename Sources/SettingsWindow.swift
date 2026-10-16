// 设置窗口: 与浮窗同一套视觉(深色毛玻璃 / 紫色强调 / 圆角卡片), 分 接管 · 浮窗 · 通用 · 运行状态

import AppKit

private let purple = NSColor.systemPurple
private let textMain = NSColor.white.withAlphaComponent(0.92)
private let textDim = NSColor.white.withAlphaComponent(0.42)

private final class ActionTarget: NSObject {
    let fn: () -> Void
    init(_ fn: @escaping () -> Void) { self.fn = fn }
    @objc func fire(_ sender: Any?) { fn() }
}

/// 紫色胶囊开关(代替系统 NSSwitch 的蓝色强调色)
private final class PillSwitch: NSControl {
    var isOn = false { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 34, height: 20) }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let track = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        (isOn ? purple.withAlphaComponent(0.95) : NSColor.white.withAlphaComponent(0.18)).setFill()
        track.fill()
        let d = r.height - 4
        let x = isOn ? r.maxX - d - 2 : r.minX + 2
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: r.minY + 2, width: d, height: d)).fill()
    }
    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        if let a = action { NSApp.sendAction(a, to: target, from: self) }
    }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    static func show() { shared.present() }

    private var window: NSWindow?
    private var targets: [ActionTarget] = []          // 持有闭包目标, 防止释放
    private var refreshers: [() -> Void] = []
    private var statusTimer: Timer?

    private func present() {
        if window == nil { build() }
        refreshers.forEach { $0() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshers.forEach { $0() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        statusTimer?.invalidate(); statusTimer = nil
    }

    // MARK: - 控件

    private func target(_ fn: @escaping () -> Void) -> ActionTarget {
        let t = ActionTarget(fn); targets.append(t); return t
    }

    private func label(_ s: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                       color: NSColor = textMain) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }

    private func sectionTitle(_ title: String) -> NSView {
        let l = label(title, size: 11, weight: .semibold, color: textDim)
        let v = NSView()
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            l.topAnchor.constraint(equalTo: v.topAnchor), l.bottomAnchor.constraint(equalTo: v.bottomAnchor)])
        return v
    }

    /// 一行: 左文字(标题+说明), 右控件; 用约束固定, 保证控件右对齐
    private func row(_ title: String, _ sub: String?, control: NSView) -> NSView {
        let texts = NSStackView(views: [label(title)] + (sub.map { [label($0, size: 11, color: textDim)] } ?? []))
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        let r = NSView()
        texts.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        r.addSubview(texts); r.addSubview(control)
        NSLayoutConstraint.activate([
            texts.leadingAnchor.constraint(equalTo: r.leadingAnchor),
            texts.topAnchor.constraint(equalTo: r.topAnchor, constant: 8),
            texts.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -8),
            control.trailingAnchor.constraint(equalTo: r.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12)])
        return r
    }

    private func switchRow(_ title: String, _ sub: String?, get: @escaping () -> Bool,
                           set: @escaping (Bool) -> Void) -> NSView {
        let sw = PillSwitch()
        let t = target { set(sw.isOn) }
        sw.target = t; sw.action = #selector(ActionTarget.fire(_:))
        refreshers.append { sw.isOn = get() }
        return row(title, sub, control: sw)
    }

    private func pillButton(_ title: String, tint: NSColor = NSColor.white.withAlphaComponent(0.14),
                            _ fn: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: target(fn), action: #selector(ActionTarget.fire(_:)))
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.layer?.backgroundColor = tint.cgColor
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.white])
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        return b
    }

    private func statusRow(_ title: String, value: @escaping () -> (String, NSColor),
                           button: NSButton? = nil) -> NSView {
        let v = NSTextField(labelWithString: "")
        v.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        refreshers.append { let (s, c) = value(); v.stringValue = s; v.textColor = c }
        let inner = NSStackView(views: [v] + (button.map { [$0] } ?? []))
        inner.spacing = 8
        return row(title, nil, control: inner)
    }

    /// 圆角卡片: 与浮窗的「远端卡片 / 输入条」同款半透明底, 行间细分隔线
    private func card(_ rows: [NSView]) -> NSView {
        var items: [NSView] = []
        for (i, r) in rows.enumerated() {
            if i > 0 {
                let line = NSView()
                line.wantsLayer = true
                line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
                line.translatesAutoresizingMaskIntoConstraints = false
                line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                items.append(line)
            }
            items.append(r)
        }
        let stack = NSStackView(views: items)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        for v in items { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return pill(stack, tint: .white, alpha: 0.07, radius: 10, hPad: 12, vPad: 0)
    }

    /// 引擎未就绪时显示「一键安装」, 就绪或安装中隐藏
    private func installButton() -> NSButton {
        let b = pillButton("一键安装", tint: purple.withAlphaComponent(0.85)) { installEngineFlow() }
        refreshers.append { b.isHidden = rimeSession != 0 || EngineInstaller.busy || rimeApi != nil }
        return b
    }

    // MARK: - 组装

    private func build() {
        let s = Settings.shared

        let opacity = NSSlider(value: s.windowOpacity, minValue: 0.4, maxValue: 1.0, target: nil, action: nil)
        opacity.trackFillColor = purple
        let opT = target { s.windowOpacity = opacity.doubleValue }
        opacity.target = opT; opacity.action = #selector(ActionTarget.fire(_:))
        opacity.widthAnchor.constraint(equalToConstant: 130).isActive = true
        refreshers.append { opacity.doubleValue = s.windowOpacity }

        let sections: [(String, [NSView])] = [
            ("接管", [
                switchRow("远端键盘接管", "UU 注入的按键进远端输入框(含拼音组词),不再打到本机焦点窗口",
                          get: { s.keyboardCapture }, set: { s.keyboardCapture = $0 }),
                switchRow("远端鼠标接管", "双光标:远端用紫色 UU 光标,与主机光标互不影响",
                          get: { s.mouseCapture }, set: { s.mouseCapture = $0 }),
                switchRow("总开关", "快捷键 ⌘⌥G 随时切换;关闭时 UU 键鼠恢复原生行为",
                          get: { captureMode }, set: { if $0 != captureMode { toggleCapture() } }),
            ]),
            ("浮窗", [
                switchRow("窗口置顶", nil, get: { s.alwaysOnTop }, set: { s.alwaysOnTop = $0 }),
                switchRow("启动时显示浮窗", nil, get: { s.showOnLaunch }, set: { s.showOnLaunch = $0 }),
                switchRow("远端消息提示音", nil, get: { s.sound }, set: { s.sound = $0 }),
                row("窗口不透明度", nil, control: opacity),
            ]),
            ("通用", [
                switchRow("开机自动启动", "需要把 uuchat 放进「应用程序」文件夹",
                          get: { s.launchAtLogin }, set: { s.launchAtLogin = $0 }),
                switchRow("调试日志", "键鼠事件写入 /tmp/uuchat-mouse.log,排查问题时再开",
                          get: { s.debugLog }, set: { s.debugLog = $0 }),
            ]),
            ("运行状态", [
                statusRow("辅助功能权限",
                          value: { accessibilityTrusted() ? ("已授权", .systemGreen) : ("未授权", .systemRed) },
                          button: pillButton("打开设置", tint: purple.withAlphaComponent(0.85)) { openAccessibilitySettings() }),
                statusRow("拼音引擎", value: { (rimeStatus, rimeSession != 0 ? .systemGreen : textDim) },
                          button: installButton()),
                statusRow("UU 远控进程", value: {
                    remotePids.isEmpty ? ("未检测到", textDim)
                                       : ("已连接 (pid \(remotePids.sorted().map(String.init).joined(separator: ",")))", .systemGreen) }),
            ]),
        ]

        var views: [NSView] = []
        let header = label("uuchat 设置", size: 13, weight: .semibold, color: NSColor.white.withAlphaComponent(0.85))
        views.append(header)
        for (title, rows) in sections { views.append(sectionTitle(title)); views.append(card(rows)) }

        let footer = NSStackView(views: [
            label("uuchat \(appVersion)", size: 11, color: textDim),
            NSView(),
            pillButton("清空聊天记录") { coordinator.clearLog() },
            pillButton("GitHub") { coordinator.openRepo() },
        ])
        footer.spacing = 8
        views.append(footer)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(14, after: header)
        for v in views { v.widthAnchor.constraint(equalToConstant: 440 - 36).isActive = true }
        for (i, v) in views.enumerated() where i > 0 && i < views.count - 1 && !(v.subviews.first is NSStackView) {
            stack.setCustomSpacing(4, after: v)             // 段标题紧贴其下的卡片
        }
        for v in views where v.subviews.first is NSStackView && v !== footer { stack.setCustomSpacing(12, after: v) }
        stack.edgeInsets = NSEdgeInsets(top: 34, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor), stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor), stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor)])

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 100),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.isMovableByWindowBackground = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = fx
        fx.layoutSubtreeIfNeeded()
        w.setContentSize(stack.fittingSize)
        w.center()
        window = w

        NotificationCenter.default.addObserver(forName: .uuSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshers.forEach { $0() }
        }
    }
}
