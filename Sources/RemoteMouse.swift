// 远端鼠标: 吃掉 UU 注入的鼠标事件, 屏幕上画紫色 UU 光标, 点击/滚轮在虚拟坐标补发; 主机光标保持独立

import AppKit
import CoreGraphics

var virtualPos = CGPoint.zero            // 远端光标位置(全局坐标, 左上原点)
var virtualInited = false
var hostPos = CGPoint.zero               // 主机真光标应在的位置(UU 会直接 warp 真光标, 须自己维护)
var lastRemoteMouseAt = Date.distantPast

// 加速增益表: 按 |u|/2 分桶, 初值取自实测(中位数 acc/u), 运行中在线微调
var accelGain: [Double] = [0.5, 0.45, 0.44, 0.43, 0.47, 0.51, 0.58, 0.62, 0.69, 0.73, 0.8, 0.84, 0.92, 0.96, 0.99, 1.08,
                           1.14, 1.2, 1.26, 1.32, 1.38, 1.44, 1.5, 1.56, 1.6, 1.6, 1.6, 1.6, 1.6, 1.6, 1.6, 1.6]

// MARK: - 紫色假光标

final class CursorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height
        // 箭头尖在 (2, h-2); 点列按"尖端为原点, y 向下"书写
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 16), (4, 12.2), (7, 18.5), (9.6, 17.4), (6.8, 11.2), (12, 11)]
        let path = NSBezierPath()
        for (i, p) in pts.enumerated() {
            let pt = NSPoint(x: 2 + p.0, y: h - 2 - p.1)
            i == 0 ? path.move(to: pt) : path.line(to: pt)
        }
        path.close()
        NSColor.systemPurple.setFill(); path.fill()
        NSColor.white.setStroke(); path.lineWidth = 1.2; path.lineJoinStyle = .round; path.stroke()
        let tag = NSRect(x: 16, y: h - 30, width: 26, height: 13)
        let t = NSBezierPath(roundedRect: tag, xRadius: 4, yRadius: 4)
        NSColor.systemPurple.setFill(); t.fill()
        ("UU" as NSString).draw(in: tag.offsetBy(dx: 0, dy: -0.5).insetBy(dx: 5, dy: 0), withAttributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .heavy), .foregroundColor: NSColor.white])
    }
}

let cursorWin: NSWindow = {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 46, height: 34),
                     styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = .screenSaver
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    w.contentView = CursorView(frame: NSRect(x: 0, y: 0, width: 46, height: 34))
    return w
}()

func moveFakeCursor(to p: CGPoint) {
    let screenH = NSScreen.screens.first?.frame.height ?? 0
    cursorWin.setFrameOrigin(NSPoint(x: p.x - 2, y: screenH - p.y - cursorWin.frame.height + 2))
    if !cursorWin.isVisible { cursorWin.orderFrontRegardless() }
}

func hideFakeCursor() {
    cursorWin.orderOut(nil)
    virtualInited = false
}

// MARK: - 坐标工具

/// 所有显示器的并集(全局坐标, 左上原点)
func allDisplaysBounds() -> CGRect {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var n: UInt32 = 0
    CGGetActiveDisplayList(8, &ids, &n)
    return ids.prefix(Int(n)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
}

func clampToDisplays(_ p: CGPoint) -> CGPoint {
    let b = allDisplaysBounds()
    return CGPoint(x: min(max(p.x, b.minX), b.maxX - 1), y: min(max(p.y, b.minY), b.maxY - 1))
}

/// warp 默认会让本机硬件事件被抑制 0.25s, 关掉, 否则主机鼠标会卡顿
func disableWarpSuppression() {
    CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
}

// MARK: - 主机鼠标

/// 主机真实鼠标事件。有远端在线时, 事件自带的 location 与 delta 都不可信:
/// UU 直接 warp 真光标, warp 与我们拽回之间的窗口里, 主机事件的落点与位移都被污染(会瞬移到紫光标处)。
/// 做法: 只信 HID 原始位移(无加速, 不受 warp 影响)+ 实测加速增益表, 自己累加 hostPos,
/// 并把每个主机鼠标事件(含按下/抬起/滚轮)的落点改写成 hostPos。无远端在线时才直接采用事件位置。
func handleHostMouse(_ event: CGEvent) {
    defer { hostLog(event) }
    if remotePids.isEmpty {
        hostPos = event.location
        return
    }
    var dx = event.getDoubleValueField(.mouseEventDeltaX)
    var dy = event.getDoubleValueField(.mouseEventDeltaY)
    let ux = event.getDoubleValueField(FIELD_UNACCEL_X), uy = event.getDoubleValueField(FIELD_UNACCEL_Y)
    let um = hypot(ux, uy), am = hypot(dx, dy)
    let bin = min(Int(um / 2), accelGain.count - 1)
    let expect = um * accelGain[bin]
    if um >= 1, am < 0.6 * expect || am > 1.6 * expect + 3 {
        // 与模型不符: 被 warp 污染(多出一段位移, 或真实位移被抵消) => 用 u×增益 还原
        dx = ux * accelGain[bin]; dy = uy * accelGain[bin]
    } else if um >= 1 {
        accelGain[bin] = accelGain[bin] * 0.97 + (am / um) * 0.03          // 干净事件: 微调增益表
    }
    hostPos = clampToDisplays(CGPoint(x: hostPos.x + dx, y: hostPos.y + dy))
    event.location = hostPos
}

// MARK: - 远端鼠标

/// 在虚拟坐标补发事件, 随后把真光标放回原位, 主机光标不受影响
func postAtVirtual(_ ev: CGEvent?, _ p: CGPoint) {
    guard let ev = ev else { return }
    ev.location = p
    ev.post(tap: .cghidEventTap)
    CGWarpMouseCursorPosition(hostPos)
}

func handleRemoteMouse(_ type: CGEventType, _ event: CGEvent) {
    remoteLog(type, event)
    if !virtualInited { virtualPos = event.location; virtualInited = true }
    lastRemoteMouseAt = Date()
    CGWarpMouseCursorPosition(hostPos)       // UU 已把真光标拽到远端位置, 立刻拽回主机位置
    let loc = event.location
    let dx = event.getDoubleValueField(.mouseEventDeltaX)
    let dy = event.getDoubleValueField(.mouseEventDeltaY)
    // UU 空闲时仍以 ~8Hz 注入"当前光标位置"的回声; 我们把真光标拽回主机位置后, 回声坐标恰好 = 主机位置。
    // 落在主机位置附近的事件不是远端真实移动, 不能拿来覆盖紫光标位置(否则松手即被吸回主机光标)
    let echo = hypot(loc.x - hostPos.x, loc.y - hostPos.y) <= 2
    if !echo {
        virtualPos = loc
    } else if dx != 0 || dy != 0 {
        virtualPos = CGPoint(x: virtualPos.x + dx, y: virtualPos.y + dy)
    }
    virtualPos = clampToDisplays(virtualPos)

    let p = virtualPos
    let flags = event.flags
    let btn = event.getIntegerValueField(.mouseEventButtonNumber)
    let clicks = event.getIntegerValueField(.mouseEventClickState)
    let sdy = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let sdx = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    DispatchQueue.main.async {
        moveFakeCursor(to: p)
        switch type {
        case .mouseMoved:
            break                                                              // 只动假光标
        case .scrollWheel:
            let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                            wheel1: Int32(sdy), wheel2: Int32(sdx), wheel3: 0)
            e?.flags = flags
            postAtVirtual(e, p)
        default:
            let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p,
                            mouseButton: CGMouseButton(rawValue: UInt32(btn)) ?? .left)
            e?.flags = flags
            e?.setIntegerValueField(.mouseEventClickState, value: clicks)
            postAtVirtual(e, p)
        }
    }
}

// MARK: - 调试日志(设置里打开)

private var remoteLogN = 0

func hostLog(_ event: CGEvent) {
    guard Settings.shared.debugLog, !remotePids.isEmpty else { return }
    let l = event.location
    debugLog(String(format: "%.3f HOST loc=(%.0f,%.0f) d=(%.0f,%.0f) u=(%.1f,%.1f) hostPos=(%.0f,%.0f)\n",
        Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000), l.x, l.y,
        event.getDoubleValueField(.mouseEventDeltaX), event.getDoubleValueField(.mouseEventDeltaY),
        event.getDoubleValueField(FIELD_UNACCEL_X), event.getDoubleValueField(FIELD_UNACCEL_Y), hostPos.x, hostPos.y))
}

private func remoteLog(_ type: CGEventType, _ event: CGEvent) {
    guard Settings.shared.debugLog else { return }
    remoteLogN += 1
    if type == .mouseMoved || type == .leftMouseDragged, remoteLogN % 15 != 0 { return }   // 移动事件抽样
    let real = CGEvent(source: nil)?.location ?? .zero
    let l = event.location
    debugLog(String(format: "%.3f type=%d pid=%d loc=(%.0f,%.0f) d=(%.0f,%.0f) real=(%.0f,%.0f)\n",
        Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000), type.rawValue,
        Int32(event.getIntegerValueField(FIELD_UNIX_PID)), l.x, l.y,
        event.getDoubleValueField(.mouseEventDeltaX), event.getDoubleValueField(.mouseEventDeltaY), real.x, real.y))
}
