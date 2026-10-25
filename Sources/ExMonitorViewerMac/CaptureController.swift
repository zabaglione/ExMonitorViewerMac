import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import CoreVideo
import OSLog

private let captureLog = Logger(subsystem: "com.zabaglione.ExMonitorViewerMac", category: "Capture")

private final class StreamReceiver: NSObject, SCStreamOutput, SCStreamDelegate {
    let frames: LatestFrame
    let generation: Int
    let firstFrame: () -> Void
    let stopped: () -> Void
    private var receivedFrame = false

    init(frames: LatestFrame, generation: Int, firstFrame: @escaping () -> Void, stopped: @escaping () -> Void) {
        self.frames = frames; self.generation = generation; self.firstFrame = firstFrame; self.stopped = stopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        guard frames.put(buffer, generation: generation) else { return }
        if !receivedFrame {
            receivedFrame = true
            captureLog.info("First frame: \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))")
            firstFrame()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        captureLog.error("Capture stopped by system (code \((error as NSError).code))")
        stopped()
    }
}

@MainActor
final class CaptureController {
    let frames = LatestFrame()
    var onStatus: ((String, Bool) -> Void)?
    private var stream: SCStream?
    private var receiver: StreamReceiver?
    private var generation = 0

    func start(displayID: CGDirectDisplayID, fps: Int, showsCursor: Bool) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let request = generation
        frames.beginGeneration(request)
        let previous = stream
        stream = nil; receiver = nil
        if let previous { try? await previous.stopCapture() }
        guard request == generation else { return }
        onStatus?("Starting capture...", false)
        guard CGPreflightScreenCaptureAccess() else {
            onStatus?("Screen Recording permission is required.\nAllow ExMonitorViewerMac in System Settings, then retry.\nIf needed, quit and reopen the app.", false)
            // macOS自身の許可ダイアログを表示し、許可状態の変更はユーザーに委ねる。
            CGRequestScreenCaptureAccess()
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard request == generation else { return }
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                onStatus?("The selected display is unavailable.\nChoose a display from the Display menu.", false)
                return
            }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard !ownApps.isEmpty else {
                onStatus?("Unable to exclude the viewer from capture.\nKeep the viewer visible and retry.", false)
                return
            }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
            config.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.showsCursor = showsCursor
            config.capturesAudio = false
            config.queueDepth = 3
            config.minimumFrameInterval = fps == 0 ? .zero : CMTime(value: 1, timescale: CMTimeScale(fps))
            let nextReceiver = StreamReceiver(frames: frames, generation: request, firstFrame: { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == request else { return }
                    self.onStatus?("", true)
                }
            }, stopped: { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == request else { return }
                    self.generation += 1
                    self.stream = nil; self.receiver = nil
                    self.frames.beginGeneration(self.generation)
                    self.onStatus?("Capture stopped.\nCheck the display connection and permission, then retry.", false)
                }
            })
            let nextStream = SCStream(filter: filter, configuration: config, delegate: nextReceiver)
            try nextStream.addStreamOutput(nextReceiver, type: .screen,
                                           sampleHandlerQueue: DispatchQueue(label: "com.zabaglione.ExMonitorViewerMac.frames"))
            // 開始待ちの間に選択が変わっても、次の要求がこのストリームを停止できるよう保持する。
            stream = nextStream; receiver = nextReceiver
            try await nextStream.startCapture()
            guard request == generation else {
                try? await nextStream.stopCapture()
                return
            }
            captureLog.info("Capture started; FPS limit \(fps), cursor \(showsCursor)")
        } catch {
            guard request == generation else { return }
            let failed = stream
            generation += 1
            frames.beginGeneration(generation)
            stream = nil; receiver = nil
            if let failed { try? await failed.stopCapture() }
            guard generation == request + 1 else { return }
            captureLog.error("Capture start failed (code \((error as NSError).code))")
            onStatus?("Unable to start capture.\nCheck Screen Recording permission and retry.\nError code: \((error as NSError).code)", false)
        }
    }

    func stop(message: String) async {
        generation += 1
        frames.beginGeneration(generation)
        let previous = stream
        stream = nil; receiver = nil
        onStatus?(message, false)
        if let previous { try? await previous.stopCapture() }
    }
}
