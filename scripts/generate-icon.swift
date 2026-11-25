import AppKit
import CoreText
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift generate-icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func makeContinuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let cgPath = CGMutablePath()
    let count = path.elementCount
    var pts = [NSPoint](repeating: .zero, count: 3)
    for i in 0..<count {
        let type = path.element(at: i, associatedPoints: &pts)
        switch type {
        case .moveTo:
            cgPath.move(to: pts[0])
        case .lineTo:
            cgPath.addLine(to: pts[0])
        case .curveTo, .cubicCurveTo:
            cgPath.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
        case .quadraticCurveTo:
            cgPath.addQuadCurve(to: pts[1], control: pts[0])
        case .closePath:
            cgPath.closeSubpath()
        @unknown default:
            break
        }
    }
    return cgPath
}

func renderIcon(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }

    let s = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Standard macOS icon squircle proportions
    let inset = s * 0.098
    let iconRect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let cornerRadius = iconRect.width * 0.2237
    let squirclePath = makeContinuousRoundedRect(iconRect, radius: cornerRadius)

    // 1. Soft icon outer shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.018),
        blur: s * 0.032,
        color: CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.18)
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.96, green: 0.97, blue: 0.985, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clean light ceramic-white to silver-mist gradient
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let bgColors = [
        CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0),
        CGColor(red: 0.965, green: 0.972, blue: 0.982, alpha: 1.0),
        CGColor(red: 0.915, green: 0.928, blue: 0.946, alpha: 1.0)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: s * 0.5, y: iconRect.maxY),
            end: CGPoint(x: s * 0.5, y: iconRect.minY),
            options: []
        )
    }

    // 3. Crisp centered "CXW" typography via CoreText tight glyph bounds
    let baseFont = NSFont.systemFont(ofSize: iconRect.width * 0.278, weight: .heavy)
    let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded)
    let font = roundedDescriptor.flatMap { NSFont(descriptor: $0, size: iconRect.width * 0.278) } ?? baseFont

    let textColor = NSColor(red: 0.094, green: 0.110, blue: 0.141, alpha: 1.0)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
        .kern: iconRect.width * 0.012
    ]
    let attrString = NSAttributedString(string: "CXW", attributes: attrs)
    let ctLine = CTLineCreateWithAttributedString(attrString)
    let glyphBounds = CTLineGetBoundsWithOptions(ctLine, [.useGlyphPathBounds])

    let barWidth = iconRect.width * 0.34
    let barHeight = max(2.0, iconRect.height * 0.056)
    let gapBetweenTextAndBar = iconRect.height * 0.088
    let totalGroupHeight = glyphBounds.height + gapBetweenTextAndBar + barHeight

    let groupBottomY = iconRect.midY - totalGroupHeight * 0.5
    let barRect = CGRect(
        x: iconRect.midX - barWidth * 0.5,
        y: groupBottomY,
        width: barWidth,
        height: barHeight
    )

    let textTargetBottomY = barRect.maxY + gapBetweenTextAndBar
    let textX = iconRect.midX - (glyphBounds.origin.x + glyphBounds.width * 0.5)
    let textY = textTargetBottomY - glyphBounds.origin.y

    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.textPosition = CGPoint(x: textX, y: textY)
    CTLineDraw(ctLine, ctx)
    ctx.restoreGState()

    // Subtle Apple Blue accent pill directly beneath CXW
    let barPath = makeContinuousRoundedRect(barRect, radius: barHeight * 0.5)
    ctx.saveGState()
    ctx.addPath(barPath)
    let barColors = [
        CGColor(red: 0.0, green: 0.51, blue: 1.0, alpha: 1.0),
        CGColor(red: 0.0, green: 0.44, blue: 0.94, alpha: 1.0)
    ] as CFArray
    ctx.clip()
    if let barGrad = CGGradient(colorsSpace: colorSpace, colors: barColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            barGrad,
            start: CGPoint(x: barRect.midX, y: barRect.maxY),
            end: CGPoint(x: barRect.midX, y: barRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    ctx.restoreGState() // End squircle clip

    // 4. Delicate neutral rim
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.10))
    ctx.setLineWidth(max(1.0, s * 0.004))
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in specs {
    if let data = renderIcon(pixelSize: px) {
        try data.write(to: outputDir.appendingPathComponent(filename))
    }
}
