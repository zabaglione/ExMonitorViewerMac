import Foundation
import CoreGraphics

struct WindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x; y = rect.origin.y
        width = rect.width; height = rect.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct ViewerSettings: Codable, Equatable {
    var displayUUID: String? = nil
    var fps: Int = 60
    var showsCursor: Bool = true
    var alwaysOnTop: Bool = false
    var windowFrame: WindowFrame? = nil

    func normalized() -> ViewerSettings {
        var result = self
        if ![0, 30, 60].contains(result.fps) { result.fps = 60 }
        if let frame = result.windowFrame,
           ![frame.x, frame.y, frame.width, frame.height].allSatisfy({ $0.isFinite }) || frame.width <= 0 || frame.height <= 0 {
            result.windowFrame = nil
        }
        return result
    }
}

final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "viewerSettings.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> ViewerSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ViewerSettings.self, from: data) else {
            return ViewerSettings()
        }
        return settings.normalized()
    }

    func save(_ settings: ViewerSettings) {
        guard let data = try? JSONEncoder().encode(settings.normalized()) else { return }
        defaults.set(data, forKey: key)
    }
}
