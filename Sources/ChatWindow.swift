// 浮窗聊天: 毛玻璃无边框面板 / 顶栏(键盘·鼠标·接管开关) / 历史 / 远端卡片(候选+回显+光标) / 主机输入

import AppKit

let logView = NSTextView(frame: .zero)
let hostField = NSTextField(frame: .zero)     // 主机输入框(可编辑)
let remoteField = RemoteLabel(frame: .zero)   // 远端回显(只读, 空时整张卡片隐藏)
var remoteCard: NSView?
let candBar = CandLabel(labelWithString: "")  // 候选条, 空串时隐藏
let kbButton = NSButton(frame: .zero)
let mouseButton = NSButton(frame: .zero)
let modeButton = NSButton(frame: .zero)
let chatPanel = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 230),
                      styleMask: [.borderless, .nonactivatingPanel, .resizable],
                      backing: .buffered, defer: false)
let coordinator = Coordinator()

// 无边框浮窗仍需能成为 key 才能打字; nonactivating 保证不抢前台 App 焦点
final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// 候选条与远端回显都空时, 整张远端卡片隐藏; 有内容才浮现
func refreshRemoteCard() {
    remoteCard?.isHidden = remoteField.stringValue.isEmpty && candBar.stringValue.isEmpty
}

final class CandLabel: NSTextField {
    override var stringValue: String {
        didSet { isHidden = stringValue.isEmpty; refreshRemoteCard() }
    }
}

final class RemoteLabel: NSTextField {
    override var stringValue: String {
        didSet { refreshRemoteCard() }
    }
}

// MARK: - 动作

final class Coordinator: NSObject {
    @objc func sendHost() {
        let t = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        hostField.stringValue = ""
        guard !t.isEmpty else { return }
        appendLog(text: t, color: .systemGreen, prefix: "🖥主机")
    }
    @objc func sendRemoteBtn() { sendRemote() }
    @objc func toggle() { toggleCapture() }
    @objc func toggleKeyboard() { Settings.shared.keyboardCapture.toggle() }
    @objc func toggleMouse() { Settings.shared.mouseCapture.toggle() }
    @objc func toggleWindow() { toggleWindowVisible() }
    @objc func showSettings() { SettingsWindow.show() }
    @objc func openAccessibility() { openAccessibilitySettings() }
    @objc func clearLog() { logView.textStorage?.setAttributedString(NSAttributedString()) }
    @objc func openRepo() { NSWorkspace.shared.open(URL(string: repoURL)!) }
    @objc func quit() { NSApp.terminate(nil) }
}

func toggleWindowVisible() {
    if chatPanel.isVisible { chatPanel.orderOut(nil) } else { chatPanel.orderFrontRegardless() }
}

func commitRemote(_ t: String) {
    appendLog(text: t, color: .systemPurple, prefix: "⌨UU远端")
    if Settings.shared.sound { NSSound(named: "Pop")?.play() }
}

func sendRemote() {
    let t = inputBuf.trimmingCharacters(in: .whitespacesAndNewlines)
    inputBuf = ""
    remoteField.stringValue = ""
    clearRimeComposition()
    guard !t.isEmpty else { return }
    commitRemote(t)
}

func appendLog(text: String, color: NSColor, prefix: String) {
    // 聊天消息: 主机 / 远端; 其余为系统提示(弱化显示)
    let isChat = prefix.contains("主机") || prefix.contains("远端")
    let name = isChat ? String(prefix.drop(while: { !$0.isLetter })) : ""
    let para = NSMutableParagraphStyle()
    para.paragraphSpacing = isChat ? 3 : 2
    para.lineSpacing = 1
    let time: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.30), .paragraphStyle: para]
    var parts: [(String, [NSAttributedString.Key: Any])] = [("\(timestamp())  ", time)]
    if isChat {
        parts.append((name, [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                             .foregroundColor: color, .paragraphStyle: para]))
        parts.append(("  " + text + "\n", [.font: NSFont.systemFont(ofSize: 13),
                                          .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                                          .paragraphStyle: para]))
    } else {
        parts.append((prefix + " " + text + "\n", [.font: NSFont.systemFont(ofSize: 11),
                                                  .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                                                  .paragraphStyle: para]))
    }
    DispatchQueue.main.async {
        for (s, a) in parts { logView.textStorage?.append(NSAttributedString(string: s, attributes: a)) }
        logView.scrollToEndOfDocument(nil)
    }
}

// MARK: - 控件工厂

/// 圆角容器: 内嵌一个控件, 无描边
func pill(_ inner: NSView, tint: NSColor, alpha: CGFloat = 0.16, radius: CGFloat = 8,
          hPad: CGFloat = 8, vPad: CGFloat = 4) -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.cornerRadius = radius
    v.layer?.backgroundColor = tint.withAlphaComponent(alpha).cgColor
    inner.translatesAutoresizingMaskIntoConstraints = false
    v.addSubview(inner)
    NSLayoutConstraint.activate([
        inner.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: hPad),
        inner.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -hPad),
        inner.topAnchor.constraint(equalTo: v.topAnchor, constant: vPad),
        inner.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -vPad)])
    return v
}

/// 单行、过长省略、不参与撑开窗口宽度
func flexible(_ f: NSTextField, truncate: NSLineBreakMode = .byTruncatingTail) {
    f.lineBreakMode = truncate
    f.maximumNumberOfLines = 1
    f.cell?.usesSingleLineMode = true
    f.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    f.setContentHuggingPriority(.init(1), for: .horizontal)
}

func styleField(_ f: NSTextField, placeholder: String) {
    f.isBordered = false
    f.drawsBackground = false
    f.focusRingType = .none
    f.font = NSFont.systemFont(ofSize: 13)
    f.textColor = NSColor.white.withAlphaComponent(0.95)
    f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
        .font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.white.withAlphaComponent(0.32)])
    flexible(f)
}

func chip(_ text: String, tint: NSColor) -> NSView {
    let l = NSTextField(labelWithString: text)
    l.font = NSFont.systemFont(ofSize: 10, weight: .bold)
    l.textColor = tint
    let v = pill(l, tint: tint, alpha: 0.2, radius: 4, hPad: 5, vPad: 1)
    v.setContentHuggingPriority(.required, for: .horizontal)
    v.setContentCompressionResistancePriority(.required, for: .horizontal)
    return v
}

func flatButton(_ title: String, tint: NSColor, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: coordinator, action: action)
    b.isBordered = false
    b.wantsLayer = true
    b.layer?.cornerRadius = 7
    b.layer?.backgroundColor = tint.withAlphaComponent(0.85).cgColor
    b.attributedTitle = NSAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: NSColor.white])
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 42).isActive = true
    b.heightAnchor.constraint(equalToConstant: 24).isActive = true
    b.setContentHuggingPriority(.required, for: .horizontal)
    b.setContentCompressionResistancePriority(.required, for: .horizontal)
    return b
}

/// 顶栏图标开关(键盘 / 鼠标)
func iconToggle(_ b: NSButton, symbol: String, action: Selector) {
    b.isBordered = false
    b.imagePosition = .imageOnly
    b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
    b.target = coordinator
    b.action = action
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 22).isActive = true
    b.heightAnchor.constraint(equalToConstant: 20).isActive = true
    b.setContentHuggingPriority(.required, for: .horizontal)
    b.setContentCompressionResistancePriority(.required, for: .horizontal)
}

/// 远端光标: 细竖条, 闪烁
func makeCaret() -> NSView {
    let c = NSView()
    c.wantsLayer = true
    c.layer?.backgroundColor = NSColor.systemPurple.blended(withFraction: 0.35, of: .white)!.cgColor
    c.translatesAutoresizingMaskIntoConstraints = false
    c.widthAnchor.constraint(equalToConstant: 1.5).isActive = true
    c.heightAnchor.constraint(equalToConstant: 15).isActive = true
    let blink = CABasicAnimation(keyPath: "opacity")
    blink.fromValue = 1; blink.toValue = 0
    blink.duration = 0.55; blink.autoreverses = true; blink.repeatCount = .infinity
    c.layer?.add(blink, forKey: "blink")
    return c
}

// MARK: - 状态刷新

/// 设置变化 / 总开关变化后统一刷新: 顶栏、窗口层级与透明度、鼠标状态
private var lastMouseCapture = true
func refreshUI() {
    let s = Settings.shared
    let on = captureMode
    let accent = NSColor.systemPurple
    let dim = NSColor.white.withAlphaComponent(0.28)

    kbButton.contentTintColor = (on && s.keyboardCapture) ? accent : dim
    kbButton.toolTip = "远端键盘接管:" + (s.keyboardCapture ? "开" : "关") + "(点击切换)"
    mouseButton.contentTintColor = (on && s.mouseCapture) ? accent : dim
    mouseButton.toolTip = "远端鼠标接管(紫色光标):" + (s.mouseCapture ? "开" : "关") + "(点击切换)"

    let c: NSColor = on ? .systemPurple : .systemOrange
    modeButton.attributedTitle = NSAttributedString(string: (on ? "● 接管中" : "● 放行"), attributes: [
        .font: NSFont.systemFont(ofSize: 10.5, weight: .medium), .foregroundColor: c])
    modeButton.toolTip = "总开关 ⌘⌥G:接管 ↔ 放行(放行时 UU 键鼠恢复原生行为)"

    chatPanel.level = s.alwaysOnTop ? .floating : .normal
    chatPanel.alphaValue = CGFloat(s.windowOpacity)

    if !s.mouseCapture { hideFakeCursor() }
    else if !lastMouseCapture { hostPos = CGEvent(source: nil)?.location ?? hostPos }
    lastMouseCapture = s.mouseCapture
}

// MARK: - 组装

func buildWindow() {
    chatPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    chatPanel.appearance = NSAppearance(named: .darkAqua)
    chatPanel.isOpaque = false
    chatPanel.backgroundColor = .clear
    chatPanel.hasShadow = false            // 系统阴影会在圆角外勾出一圈边
    chatPanel.isMovableByWindowBackground = true
    chatPanel.minSize = NSSize(width: 240, height: 150)

    let f = NSScreen.main!.visibleFrame
    chatPanel.setFrameOrigin(NSPoint(x: f.origin.x + 12, y: f.origin.y + 12))

    // 毛玻璃底, 无描边
    let fx = NSVisualEffectView()
    fx.material = .hudWindow
    fx.blendingMode = .behindWindow
    fx.state = .active
    fx.wantsLayer = true
    fx.layer?.cornerRadius = 12
    fx.layer?.masksToBounds = true
    chatPanel.contentView = fx

    // 顶栏: 标题 | 键盘 · 鼠标 · 接管开关; 过窄时先丢标题
    let title = NSTextField(labelWithString: "UU 聊天")
    title.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    title.textColor = NSColor.white.withAlphaComponent(0.8)
    iconToggle(kbButton, symbol: "keyboard", action: #selector(Coordinator.toggleKeyboard))
    iconToggle(mouseButton, symbol: "computermouse.fill", action: #selector(Coordinator.toggleMouse))
    modeButton.isBordered = false
    modeButton.target = coordinator
    modeButton.action = #selector(Coordinator.toggle)
    modeButton.setContentHuggingPriority(.required, for: .horizontal)
    modeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    let header = NSStackView(views: [title, spacer, kbButton, mouseButton, modeButton])
    header.orientation = .horizontal
    header.spacing = 3
    header.distribution = .fill
    header.setCustomSpacing(8, after: mouseButton)
    header.setVisibilityPriority(.init(200), for: title)
    header.setClippingResistancePriority(.init(100), for: .horizontal)

    // 历史
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    logView.isEditable = false
    logView.isSelectable = true
    logView.drawsBackground = false
    logView.textContainerInset = NSSize(width: 0, height: 0)
    logView.isHorizontallyResizable = false
    logView.autoresizingMask = [.width]
    logView.textContainer?.widthTracksTextView = true
    scroll.documentView = logView
    scroll.setContentHuggingPriority(.init(1), for: .vertical)
    scroll.setContentCompressionResistancePriority(.init(1), for: .vertical)
    scroll.setContentCompressionResistancePriority(.init(1), for: .horizontal)

    // 候选条: 独立于输入框, 像系统输入法的候选浮条, 无底框
    candBar.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    candBar.textColor = NSColor.systemPurple.blended(withFraction: 0.5, of: .white)
    candBar.isHidden = true
    flexible(candBar, truncate: .byTruncatingHead)

    // 远端行: 标签 + 已组文字 + 光标 + 代发
    remoteField.isEditable = false
    remoteField.isSelectable = false
    remoteField.isBordered = false
    remoteField.drawsBackground = false
    remoteField.font = NSFont.systemFont(ofSize: 13)
    remoteField.textColor = NSColor.white.withAlphaComponent(0.95)
    flexible(remoteField, truncate: .byTruncatingHead)
    remoteField.setContentHuggingPriority(.init(750), for: .horizontal)   // 光标紧跟文字
    let rSpacer = NSView()
    rSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
    let fwd = flatButton("代发", tint: .systemPurple, action: #selector(Coordinator.sendRemoteBtn))
    let rInner = NSStackView(views: [chip("远端", tint: .systemPurple), remoteField, makeCaret(), rSpacer, fwd])
    rInner.orientation = .horizontal
    rInner.alignment = .centerY
    rInner.spacing = 5
    rInner.distribution = .fill
    let card = pill(rInner, tint: .systemPurple, alpha: 0.2, radius: 8, hPad: 6, vPad: 3)
    card.isHidden = true
    remoteCard = card

    // 主机行(唯一常驻输入框)
    styleField(hostField, placeholder: "说点什么…  ↵ 发送")
    hostField.target = coordinator
    hostField.action = #selector(Coordinator.sendHost)
    let hostPill = pill(hostField, tint: .white, alpha: 0.09, radius: 8, vPad: 5)
    let hostRow = NSStackView(views: [hostPill, flatButton("发送", tint: .systemGreen, action: #selector(Coordinator.sendHost))])
    hostRow.spacing = 5
    hostRow.alignment = .centerY
    hostRow.distribution = .fill

    let stack = NSStackView(views: [header, scroll, candBar, card, hostRow])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 5
    stack.setCustomSpacing(2, after: candBar)
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 10, right: 10)
    stack.translatesAutoresizingMaskIntoConstraints = false
    fx.addSubview(stack)
    // 所有行宽度统一锁到窗口内容宽度, 内容永远不能反过来撑开窗口
    var cs = [
        stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
        stack.topAnchor.constraint(equalTo: fx.topAnchor),
        stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor)]
    for v in [header, scroll, candBar, card, hostRow] as [NSView] {
        cs.append(v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20))
    }
    NSLayoutConstraint.activate(cs)

    chatPanel.setContentSize(NSSize(width: 360, height: 230))
    if Settings.shared.showOnLaunch { chatPanel.orderFrontRegardless() }
    refreshUI()
}
