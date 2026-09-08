import AppKit
import ApplicationServices
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var captureCoordinator: CaptureCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        captureCoordinator = CaptureCoordinator.shared

        Task { @MainActor in
            _ = ScreenPermissionChecker.shared.check()
        }

        setupStatusItem()

        hotkeyManager = HotkeyManager.shared
        hotkeyManager?.registerAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMenu()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterAll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let img = NSImage(contentsOfFile: Bundle.main.path(forResource: "p-favicon", ofType: "png") ?? "") {
                let size = NSSize(width: 18, height: 18)
                img.size = size
                button.image = img
            } else {
                button.image = NSImage(
                    systemSymbolName: "camera.metering.center.weighted",
                    accessibilityDescription: "TPix"
                )
                button.image?.isTemplate = true
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "区域截图", action: #selector(startAreaCapture), keyEquivalent: "")
        menu.addItem(withTitle: "录屏", action: #selector(toggleRecording), keyEquivalent: "")
        menu.addItem(withTitle: "OCR", action: #selector(startOCR), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 TPix", action: #selector(quitApp), keyEquivalent: "q")
        for m in menu.items where m.action != nil {
            m.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func showMenu() {
        statusItem?.button?.performClick(nil)
    }

    @objc private func startAreaCapture() { CaptureCoordinator.shared.startAreaCapture() }
    @objc private func toggleRecording() { CaptureCoordinator.shared.toggleRecording() }
    @objc private func startOCR() { CaptureCoordinator.shared.startOCR() }
    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        SettingsWindowController.shared.show()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = SettingsStore.shared.settings
        for item in menu.items {
            if item.action == #selector(startAreaCapture) {
                item.title = "区域截图  \(s.areaCaptureHotkey.displayString)"
            } else if item.action == #selector(toggleRecording) {
                item.title = "录屏  \(s.recordHotkey.displayString)"
            } else if item.action == #selector(startOCR) {
                item.title = "OCR  \(s.ocrHotkey.displayString)"
            }
        }
    }
}
