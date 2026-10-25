import AppKit
import CoreGraphics
import Foundation
import ImageIO

private let canvasSize = 1024
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

private func gradient(_ colors: [CGColor], locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
}

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func fillRounded(_ context: CGContext, rect: CGRect, radius: CGFloat, color: CGColor) {
    context.addPath(roundedPath(rect, radius: radius))
    context.setFillColor(color)
    context.fillPath()
}

private func drawWindow(
    _ context: CGContext,
    rect: CGRect,
    radius: CGFloat,
    borderWidth: CGFloat,
    frameColor: CGColor,
    screenColors: [CGColor],
    headerColor: CGColor
) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: color(0.025, 0.055, 0.19, 0.38))
    context.addPath(roundedPath(rect, radius: radius))
    context.setFillColor(frameColor)
    context.fillPath()
    context.restoreGState()

    let screen = rect.insetBy(dx: borderWidth, dy: borderWidth)
    context.saveGState()
    context.addPath(roundedPath(screen, radius: max(18, radius - borderWidth * 0.72)))
    context.clip()
    let screenGradient = gradient(screenColors)
    context.drawLinearGradient(
        screenGradient,
        start: CGPoint(x: screen.minX, y: screen.minY),
        end: CGPoint(x: screen.maxX, y: screen.maxY),
        options: []
    )

    let headerHeight = max(34, rect.height * 0.145)
    let header = CGRect(x: screen.minX, y: screen.maxY - headerHeight, width: screen.width, height: headerHeight)
    context.setFillColor(headerColor)
    context.fill(header)
    context.setFillColor(color(0.91, 0.98, 1, 0.34))
    context.fill(CGRect(x: screen.minX, y: header.minY - 3, width: screen.width, height: 5))
    context.restoreGState()
}

private func makeMasterIcon() -> CGImage {
    let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let backgroundBounds = CGRect(x: 56, y: 56, width: canvasSize - 112, height: canvasSize - 112)

    context.saveGState()
    context.addPath(roundedPath(backgroundBounds, radius: 190))
    context.clip()
    context.drawLinearGradient(
        gradient([
            color(0.13, 0.78, 0.97),
            color(0.17, 0.43, 0.92),
            color(0.18, 0.20, 0.61)
        ]),
        start: CGPoint(x: backgroundBounds.minX, y: backgroundBounds.maxY),
        end: CGPoint(x: backgroundBounds.maxX, y: backgroundBounds.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    drawWindow(
        context,
        rect: CGRect(x: 150, y: 380, width: 560, height: 420),
        radius: 64,
        borderWidth: 24,
        frameColor: color(0.80, 0.95, 1, 0.86),
        screenColors: [color(0.10, 0.34, 0.76), color(0.13, 0.72, 0.93)],
        headerColor: color(0.055, 0.17, 0.47, 0.64)
    )

    drawWindow(
        context,
        rect: CGRect(x: 350, y: 235, width: 530, height: 450),
        radius: 70,
        borderWidth: 28,
        frameColor: color(0.96, 0.99, 1),
        screenColors: [color(0.12, 0.75, 0.97), color(0.20, 0.40, 0.92)],
        headerColor: color(0.055, 0.15, 0.44, 0.88)
    )

    return context.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "ExMonitorViewerIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG output."])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "ExMonitorViewerIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not finish PNG output."])
    }
}

private func resized(_ image: CGImage, side: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
}

private func generateIconset(at directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let master = makeMasterIcon()
    let files: [(String, Int)] = [
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
    for (name, side) in files {
        let image = side == canvasSize ? master : resized(master, side: side)
        try writePNG(image, to: directory.appendingPathComponent(name))
    }
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon <iconset-directory>\n", stderr)
    exit(2)
}

do {
    try generateIconset(at: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
