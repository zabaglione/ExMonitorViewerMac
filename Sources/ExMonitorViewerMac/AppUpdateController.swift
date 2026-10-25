import AppKit
import Sparkle

@MainActor
final class AppUpdateController: NSObject, NSMenuItemValidation {
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        do {
            _ = try UpdateConfiguration(feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                                        publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
            controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        } catch {
            controller = nil
        }
    }

    func addMenuItems(to menu: NSMenu) {
        let check = NSMenuItem(title: "Check for Updates...", action: nil, keyEquivalent: "")
        if let controller {
            check.target = controller
            check.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        } else {
            check.target = self
            check.action = #selector(showConfigurationError)
        }
        menu.addItem(check)
        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomaticChecks(_:)), keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)
    }

    func start() { controller?.startUpdater() }

    @objc private func toggleAutomaticChecks(_ sender: NSMenuItem) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        sender.state = updater.automaticallyChecksForUpdates ? .on : .off
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomaticChecks(_:)) {
            menuItem.state = controller?.updater.automaticallyChecksForUpdates == true ? .on : .off
            return controller != nil
        }
        return true
    }

    @objc private func showConfigurationError() {
        let alert = NSAlert()
        alert.messageText = "Update Checking Is Unavailable"
        alert.informativeText = "The update service is not configured correctly. Please download the latest release from the official repository."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
