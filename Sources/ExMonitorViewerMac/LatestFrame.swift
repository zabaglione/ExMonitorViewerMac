import Foundation
import CoreVideo

// 世代の検証と最新フレームの書き込みを同じロック下で行う。
final class LatestFrame {
    private let lock = NSLock()
    private var generation = 0
    private var buffer: CVPixelBuffer?

    func beginGeneration(_ value: Int) {
        lock.lock(); defer { lock.unlock() }
        generation = value
        buffer = nil
    }

    @discardableResult
    func put(_ value: CVPixelBuffer, generation expected: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == expected else { return false }
        buffer = value
        return true
    }

    func get() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}
