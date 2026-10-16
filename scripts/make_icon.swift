// 生成 App 图标: swiftc scripts/make_icon.swift -o /tmp/make_icon && /tmp/make_icon Resources/AppIcon.iconset
// 紫色渐变圆角底 + 白色聊天气泡(三点) + 紫色 UU 光标

import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // 底: macOS 图标网格 824x824 居中, 圆角 ~185
    let base = CGRect(x: 100, y: 100, width: 824, height: 824)
    let basePath = NSBezierPath(roundedRect: base, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); basePath.fill()
    ctx.restoreGState()
    ctx.saveGState()
    basePath.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.70, green: 0.50, blue: 1.00, alpha: 1),
                        NSColor(calibratedRed: 0.40, green: 0.20, blue: 0.86, alpha: 1)])!
        .draw(in: base, angle: -65)
    ctx.restoreGState()

    // 气泡
    let bubble = NSBezierPath(roundedRect: CGRect(x: 214, y: 400, width: 596, height: 400), xRadius: 130, yRadius: 130)
    let tail = NSBezierPath()
    tail.move(to: CGPoint(x: 290, y: 470)); tail.line(to: CGPoint(x: 262, y: 310)); tail.line(to: CGPoint(x: 450, y: 440)); tail.close()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    NSColor.white.setFill(); bubble.fill(); tail.fill()
    ctx.restoreGState()

    // 三个点
    NSColor(calibratedRed: 0.50, green: 0.30, blue: 0.95, alpha: 1).setFill()
    for i in 0..<3 {
        NSBezierPath(ovalIn: CGRect(x: 342 + CGFloat(i) * 120, y: 566, width: 68, height: 68)).fill()
    }

    // UU 光标(尖端在 (600, 520), 向右下)
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 16), (4, 12.2), (7, 18.5), (9.6, 17.4), (6.8, 11.2), (12, 11)]
    let k: CGFloat = 21
    let arrow = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let pt = CGPoint(x: 590 + p.0 * k, y: 530 - p.1 * k)
        i == 0 ? arrow.move(to: pt) : arrow.line(to: pt)
    }
    arrow.close()
    arrow.lineJoinStyle = .round
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: NSColor.black.withAlphaComponent(0.4).cgColor)
    NSColor.white.setStroke(); arrow.lineWidth = 30; arrow.stroke()
    ctx.restoreGState()
    NSColor(calibratedRed: 0.42, green: 0.18, blue: 0.92, alpha: 1).setFill(); arrow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
