import CoreGraphics
import Foundation
import XCTest
import CoreVideo

final class ViewGeometryTests: XCTestCase {
    func testAspectFitPreservesAspectRatioAndCentersImage() {
        let source = CGSize(width: 1920, height: 1080)
        let destination = CGRect(x: 20, y: 30, width: 800, height: 600)

        let result = ViewGeometry.aspectFit(source: source, destination: destination)

        XCTAssertEqual(result, CGRect(x: 20, y: 105, width: 800, height: 450))
    }

    func testAspectFitReturnsZeroForEmptySource() {
        let result = ViewGeometry.aspectFit(
            source: .zero,
            destination: CGRect(x: 20, y: 30, width: 800, height: 600)
        )

        XCTAssertEqual(result, .zero)
    }

    func testOffscreenWindowIsMovedInsideAvailableScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let offscreen = CGRect(x: 2000, y: 1200, width: 640, height: 480)

        let result = ViewGeometry.visibleWindowFrame(offscreen, screens: [screen])

        XCTAssertTrue(screen.contains(result), "The corrected frame should be fully visible on the screen.")
    }

    func testOversizedWindowIsResizedAndKeptOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let oversized = CGRect(x: -400, y: -200, width: 1600, height: 1100)

        let result = ViewGeometry.visibleWindowFrame(oversized, screens: [screen])

        XCTAssertLessThanOrEqual(result.width, screen.width)
        XCTAssertLessThanOrEqual(result.height, screen.height)
        XCTAssertTrue(screen.contains(result), "The corrected frame should fit within the screen bounds.")
    }

    func testWindowOnNegativeCoordinateSecondaryScreenKeepsItsFrame() {
        let secondaryScreen = CGRect(x: -1920, y: -120, width: 1920, height: 1080)
        let frame = CGRect(x: -1800, y: 0, width: 800, height: 600)

        let result = ViewGeometry.visibleWindowFrame(frame, screens: [CGRect(x: 0, y: 0, width: 1440, height: 900), secondaryScreen])

        XCTAssertEqual(result, frame)
    }

    func testEmptyScreenListLeavesWindowFrameUnchanged() {
        let frame = CGRect(x: 2000, y: 1200, width: 640, height: 480)

        XCTAssertEqual(ViewGeometry.visibleWindowFrame(frame, screens: []), frame)
    }
}

final class ViewerSettingsTests: XCTestCase {
    func testSettingsRoundTripThroughCodable() throws {
        let settings = ViewerSettings(
            displayUUID: "display-uuid",
            fps: 30,
            showsCursor: false,
            alwaysOnTop: true,
            windowFrame: WindowFrame(CGRect(x: 120, y: 90, width: 640, height: 360))
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ViewerSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }

    func testInvalidFPSNormalizesToDefault() {
        var settings = ViewerSettings()
        settings.fps = -1

        XCTAssertEqual(settings.normalized().fps, 60)
    }

    func testSystemMaximumFPSRemainsValid() {
        var settings = ViewerSettings()
        settings.fps = 0

        XCTAssertEqual(settings.normalized().fps, 0)
    }

    func testInvalidWindowFrameIsRemovedDuringNormalization() {
        var settings = ViewerSettings()
        settings.windowFrame = WindowFrame(CGRect(x: 10, y: 20, width: 0, height: 300))

        XCTAssertNil(settings.normalized().windowFrame)
    }
}

final class RegressionTests: XCTestCase {
    func testSmallScaleWindowIsNotEnlargedByVisibilityCorrection() {
        let requested = CGRect(x: 40, y: 80, width: 320, height: 208)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(ViewGeometry.visibleWindowFrame(requested, screens: [screen]), requested)
    }

    func testLateFramesFromPreviousCaptureCannotReplaceCurrentFrame() throws {
        let frames = LatestFrame()
        var first: CVPixelBuffer?
        var second: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &first), kCVReturnSuccess)
        XCTAssertEqual(CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &second), kCVReturnSuccess)
        let oldFrame = try XCTUnwrap(first), newFrame = try XCTUnwrap(second)
        frames.beginGeneration(1)
        XCTAssertTrue(frames.put(oldFrame, generation: 1))
        frames.beginGeneration(2)
        XCTAssertNil(frames.get())
        XCTAssertFalse(frames.put(oldFrame, generation: 1))
        XCTAssertTrue(frames.put(newFrame, generation: 2))
        XCTAssertFalse(frames.put(oldFrame, generation: 1))
        XCTAssertTrue(frames.get() === newFrame)
        frames.beginGeneration(3)
        XCTAssertFalse(frames.put(newFrame, generation: 2))
        XCTAssertNil(frames.get())
    }
}
