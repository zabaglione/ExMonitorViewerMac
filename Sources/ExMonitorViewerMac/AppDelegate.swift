import AppKit
import MetalKit
import CoreGraphics

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let capture = CaptureController()
    private let store = SettingsStore()
    private let updates = AppUpdateController()
    private var settings = ViewerSettings()
    private var window: NSWindow!
    private var metalView: MTKView!
    private var renderer: MetalRenderer?
    private var statusPanel: NSStackView!
    private var statusLabel: NSTextField!
    private var displayMenu: NSMenu!
    private var fpsItems: [NSMenuItem] = []
    private var cursorItem: NSMenuItem!
    private var topItem: NSMenuItem!
    private var fullscreenItem: NSMenuItem!
    private var selectedDisplay: CGDirectDisplayID?
    private var captureTask: Task<Void, Never>?
    private var terminating = false
    private var fullscreenTransition = false
    private var captureConfiguration: DisplayConfiguration?

    private struct DisplayConfiguration: Equatable {
        let id: CGDirectDisplayID
        let pixelSize: CGSize
        let pointSize: CGSize
    }

    private func configuration(for display: CGDirectDisplayID?) -> DisplayConfiguration? {
        guard let display, let mode = CGDisplayCopyDisplayMode(display) else { return nil }
        return DisplayConfiguration(id: display,
                                    pixelSize: CGSize(width: mode.pixelWidth, height: mode.pixelHeight),
                                    pointSize: CGSize(width: mode.width, height: mode.height))
    }

    static func main() {
        let app = NSApplication.shared
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            app.applicationIconImage = icon
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        settings = store.load()
        buildMenu()
        buildWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refreshDisplays(chooseDefault: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if renderer != nil { restartCapture() }
        updates.start()
    }

    @discardableResult
    private func item(_ title: String, action: Selector?, key: String = "", menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    private func submenu(_ title: String, parent: NSMenu) -> NSMenu {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        entry.submenu = menu; parent.addItem(entry)
        return menu
    }

    private func buildMenu() {
        let root = NSMenu()
        let app = submenu("ExMonitorViewerMac", parent: root)
        item("About ExMonitorViewerMac", action: #selector(showAbout), menu: app)
        item("Third-Party Licenses", action: #selector(showLicenses), menu: app)
        updates.addMenuItems(to: app)
        app.addItem(.separator())
        item("Quit ExMonitorViewerMac", action: #selector(quit), key: "q", menu: app)
        displayMenu = submenu("Display", parent: root)
        let view = submenu("View", parent: root)
        item("Fit Window to Image", action: #selector(fitWindow), key: "f", menu: view)
        let scale = submenu("Scale", parent: view)
        for percent in [50, 100, 200] {
            let entry = item("\(percent)%", action: #selector(scaleWindow(_:)), menu: scale)
            entry.tag = percent
        }
        topItem = item("Always on Top", action: #selector(toggleTop), menu: view)
        fullscreenItem = item("Enter Full Screen", action: #selector(toggleFullscreen), key: "f", menu: view)
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        let captureMenu = submenu("Capture", parent: root)
        for (title, fps) in [("30 FPS",30),("60 FPS",60),("System Maximum",0)] {
            let entry = item(title, action: #selector(changeFPS(_:)), menu: captureMenu)
            entry.tag = fps; fpsItems.append(entry)
        }
        captureMenu.addItem(.separator())
        cursorItem = item("Show Cursor", action: #selector(toggleCursor), menu: captureMenu)
        item("Retry Capture", action: #selector(retryCapture), key: "r", menu: captureMenu)
        item("Open Screen Recording Settings", action: #selector(openPermissions), menu: captureMenu)
        NSApp.mainMenu = root
        updateMenuStates()
    }

    private func buildWindow() {
        let visible = NSScreen.screens.map(\.visibleFrame)
        let defaultFrame = CGRect(x: (visible.first?.midX ?? 640) - 480,
                                  y: (visible.first?.midY ?? 450) - 300, width: 960, height: 600)
        let frame = ViewGeometry.visibleWindowFrame(settings.windowFrame?.rect ?? defaultFrame, screens: visible)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.setFrame(frame, display: false)
        window.title = "ExMonitorViewerMac"
        window.minSize = NSSize(width: min(480, frame.width), height: min(300, frame.height))
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.level = settings.alwaysOnTop ? .floating : .normal
        let root = NSView()
        window.contentView = root
        metalView = MTKView(frame: .zero)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: root.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        statusLabel = NSTextField(wrappingLabelWithString: "Starting capture...")
        statusLabel.alignment = .center
        statusLabel.textColor = .white
        let retry = NSButton(title: "Retry Capture", target: self, action: #selector(retryCapture))
        let permission = NSButton(title: "Open Screen Recording Settings", target: self, action: #selector(openPermissions))
        statusPanel = NSStackView(views: [statusLabel, retry, permission])
        statusPanel.orientation = .vertical
        statusPanel.spacing = 14
        statusPanel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusPanel)
        NSLayoutConstraint.activate([
            statusPanel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            statusPanel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            statusPanel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -40)
        ])
        do { renderer = try MetalRenderer(view: metalView, frames: capture.frames) }
        catch { setStatus("Metal rendering is unavailable on this Mac.", running: false) }
        capture.onStatus = { [weak self] message, running in self?.setStatus(message, running: running) }
    }

    private func setStatus(_ message: String, running: Bool) {
        statusLabel.stringValue = message
        statusPanel.isHidden = running
        metalView.isPaused = !running
        if !running { metalView.draw() }
    }

    private func uuid(for display: CGDirectDisplayID) -> String? {
        guard let value = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, value) as String
    }

    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func refreshDisplays(chooseDefault: Bool) {
        displayMenu.removeAllItems()
        let screens = NSScreen.screens
        let ids = screens.compactMap(screenID)
        if chooseDefault {
            selectedDisplay = ids.first(where: { uuid(for: $0) == settings.displayUUID })
                ?? ids.first(where: { $0 != CGMainDisplayID() }) ?? ids.first
        }
        for (index, screen) in screens.enumerated() {
            guard let id = screenID(screen) else { continue }
            let title = "\(index + 1): \(screen.localizedName)\(id == CGMainDisplayID() ? " (Main)" : "")"
            let entry = item(title, action: #selector(selectDisplay(_:)), menu: displayMenu)
            entry.representedObject = NSNumber(value: id)
            entry.state = id == selectedDisplay ? .on : .off
        }
        if screens.isEmpty {
            let empty = item("No Displays Available", action: nil, menu: displayMenu)
            empty.isEnabled = false
        }
    }

    private func restartCapture() {
        guard renderer != nil, !terminating else { return }
        #if UPDATER_TESTING
        if Bundle.main.bundleIdentifier?.hasSuffix(".UpdateTest") == true {
            setStatus("Update installer test mode.", running: false)
            return
        }
        #endif
        captureTask?.cancel()
        captureConfiguration = configuration(for: selectedDisplay)
        guard let selectedDisplay else {
            captureTask = Task { await capture.stop(message: "Choose a display from the Display menu.") }
            return
        }
        settings.displayUUID = uuid(for: selectedDisplay)
        persist()
        metalView.preferredFramesPerSecond = settings.fps == 0 ? (window.screen?.maximumFramesPerSecond ?? 60) : settings.fps
        let fps = settings.fps, cursor = settings.showsCursor
        captureTask = Task { await capture.start(displayID: selectedDisplay, fps: fps, showsCursor: cursor) }
    }

    private func persist() { store.save(settings) }

    private func updateMenuStates() {
        fpsItems.forEach { $0.state = $0.tag == settings.fps ? .on : .off }
        cursorItem.state = settings.showsCursor ? .on : .off
        topItem.state = settings.alwaysOnTop ? .on : .off
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else { return }
        selectedDisplay = value.uint32Value
        refreshDisplays(chooseDefault: false)
        restartCapture()
    }

    @objc private func screenConfigurationChanged() {
        guard window != nil, !terminating else { return }
        let ids = NSScreen.screens.compactMap(screenID)
        if let selectedDisplay, !ids.contains(selectedDisplay) { self.selectedDisplay = nil }
        refreshDisplays(chooseDefault: false)
        if !fullscreenTransition, !window.styleMask.contains(.fullScreen) {
            window.setFrame(ViewGeometry.visibleWindowFrame(window.frame, screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        }
        // Spaceや全画面の変化だけではストリームを作り直さない。
        if configuration(for: selectedDisplay) != captureConfiguration { restartCapture() }
    }

    @objc private func retryCapture() { refreshDisplays(chooseDefault: selectedDisplay == nil); restartCapture() }
    @objc private func changeFPS(_ sender: NSMenuItem) { settings.fps = sender.tag; updateMenuStates(); restartCapture() }
    @objc private func toggleCursor() { settings.showsCursor.toggle(); updateMenuStates(); restartCapture() }
    @objc private func toggleTop() {
        settings.alwaysOnTop.toggle()
        window.level = settings.alwaysOnTop ? .floating : .normal
        updateMenuStates(); persist()
    }
    @objc private func toggleFullscreen() { window.toggleFullScreen(nil) }
    @objc private func fitWindow() { resizeImage(scale: nil) }
    @objc private func scaleWindow(_ sender: NSMenuItem) { resizeImage(scale: CGFloat(sender.tag) / 100) }

    private func resizeImage(scale: CGFloat?) {
        guard !window.styleMask.contains(.fullScreen), let selectedDisplay else { return }
        let source: CGSize
        if let frame = capture.frames.get() {
            source = CGSize(width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame))
        } else if let mode = CGDisplayCopyDisplayMode(selectedDisplay) {
            source = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        } else { return }
        guard source.width > 0, source.height > 0 else { return }
        let current = window.contentLayoutRect.size
        let size: CGSize
        if let scale {
            // 100%では取得元の1ピクセルを表示先の1ピクセルへ対応させる。
            let backing = window.backingScaleFactor
            size = CGSize(width: source.width * scale / backing, height: source.height * scale / backing)
        } else {
            size = ViewGeometry.aspectFit(source: source, destination: CGRect(origin: .zero, size: current)).size
        }
        let oldTop = window.frame.maxY
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        frame.origin = CGPoint(x: window.frame.minX, y: oldTop - frame.height)
        frame = ViewGeometry.visibleWindowFrame(frame, screens: NSScreen.screens.map(\.visibleFrame))
        window.minSize = NSSize(width: min(480, frame.width), height: min(300, frame.height))
        window.setFrame(frame, display: true)
    }

    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func showLicenses() {
        if let url = Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func windowWillEnterFullScreen(_ notification: Notification) {
        saveWindowFrame(); fullscreenTransition = true
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        fullscreenTransition = false
        fullscreenItem.title = "Exit Full Screen"
    }
    func windowWillExitFullScreen(_ notification: Notification) { fullscreenTransition = true }
    func windowDidExitFullScreen(_ notification: Notification) {
        fullscreenTransition = false
        fullscreenItem.title = "Enter Full Screen"
        saveWindowFrame()
    }

    func windowDidMove(_ notification: Notification) { saveWindowFrame() }
    func windowDidResize(_ notification: Notification) { saveWindowFrame() }
    func windowDidChangeScreen(_ notification: Notification) {
        if settings.fps == 0 { metalView.preferredFramesPerSecond = window.screen?.maximumFramesPerSecond ?? 60 }
    }
    private func saveWindowFrame() {
        guard window != nil, !fullscreenTransition, !window.styleMask.contains(.fullScreen) else { return }
        settings.windowFrame = WindowFrame(window.frame); persist()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateNow }
        terminating = true
        saveWindowFrame()
        captureTask?.cancel()
        Task {
            await capture.stop(message: "Stopping capture...")
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
