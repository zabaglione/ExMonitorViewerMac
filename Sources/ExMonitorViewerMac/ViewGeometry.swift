import CoreGraphics

// 座標は呼び出し側の単位に統一する（ウィンドウはポイント、描画はピクセル）。
enum ViewGeometry {
    static func aspectFit(source: CGSize, destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else { return .zero }
        let scale = min(destination.width / source.width, destination.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: destination.midX - size.width / 2, y: destination.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    static func visibleWindowFrame(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard !screens.isEmpty else { return frame }
        let screen = screens.max { a, b in
            intersectionArea(frame, a) < intersectionArea(frame, b)
        } ?? screens[0]
        let width = min(max(frame.width, 1), screen.width)
        let height = min(max(frame.height, 1), screen.height)
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height),
                      width: width, height: height)
    }

    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
