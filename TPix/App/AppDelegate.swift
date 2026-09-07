import AppKit
import ApplicationServices
import ScreenCaptureKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotkeyManager: HotkeyManager?
    private var captureCoordinator: CaptureCoordinator?
    private var pinManager: PinManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsStore.shared

        pinManager = PinManager.shared
        captureCoordinator = CaptureCoordinator.shared
        captureCoordinator?.pinManager = pinManager
        
        // 静默检查权限（不会重复弹窗，只在首次需要时触发）
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
        menu.addItem(withTitle: "全屏截图", action: #selector(startFullScreenCapture), keyEquivalent: "")
        menu.addItem(withTitle: "延时截图", action: #selector(startDelayCapture), keyEquivalent: "")
        menu.addItem(withTitle: "光标下窗口截图", action: #selector(captureWindowUnderCursor), keyEquivalent: "")
        menu.addItem(withTitle: "重复上次截图", action: #selector(repeatLastCapture), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "长截图", action: #selector(startScrollCapture), keyEquivalent: "")
        menu.addItem(withTitle: "录屏", action: #selector(toggleRecording), keyEquivalent: "")
        menu.addItem(withTitle: "贴图", action: #selector(startPin), keyEquivalent: "")
        menu.addItem(withTitle: "取色器", action: #selector(startColorPicker), keyEquivalent: "")
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
    @objc private func startFullScreenCapture() { CaptureCoordinator.shared.startFullScreenCapture() }
    @objc private func startDelayCapture() { CaptureCoordinator.shared.startDelayCapture() }
    @objc private func captureWindowUnderCursor() { CaptureCoordinator.shared.captureWindowUnderCursor() }
    @objc private func repeatLastCapture() { CaptureCoordinator.shared.repeatLastCapture() }
    @objc private func startScrollCapture() { CaptureCoordinator.shared.startScrollCapture() }
    @objc private func toggleRecording() { CaptureCoordinator.shared.toggleRecording() }
    @objc private func startPin() { CaptureCoordinator.shared.startPinFromClipboard() }
    @objc private func startColorPicker() { CaptureCoordinator.shared.startColorPicker() }
    @objc private func startOCR() { CaptureCoordinator.shared.startOCR() }
    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        SettingsWindowController.shared.show()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let s = SettingsStore.shared.settings
        let titles = [
            "区域截图  \(s.areaCaptureHotkey.displayString)",
            "全屏截图  \(s.fullScreenHotkey.displayString)",
            "延时截图  \(s.delayCaptureHotkey.displayString)",
            "光标下窗口截图  \(s.windowUnderCursorHotkey.displayString)",
            "重复上次截图  \(s.repeatLastCaptureHotkey.displayString)",
            "长截图  \(s.scrollCaptureHotkey.displayString)",
            "录屏  \(s.recordHotkey.displayString)",
            "贴图  \(s.pinHotkey.displayString)",
            "取色器  \(s.colorPickerHotkey.displayString)",
            "OCR  \(s.ocrHotkey.displayString)",
        ]
        for item in menu.items {
            if item.action == #selector(startAreaCapture) { item.title = titles[0] }
            else if item.action == #selector(startFullScreenCapture) { item.title = titles[1] }
            else if item.action == #selector(startDelayCapture) { item.title = titles[2] }
            else if item.action == #selector(captureWindowUnderCursor) { item.title = titles[3] }
            else if item.action == #selector(repeatLastCapture) { item.title = titles[4] }
            else if item.action == #selector(startScrollCapture) { item.title = titles[5] }
            else if item.action == #selector(toggleRecording) { item.title = titles[6] }
            else if item.action == #selector(startPin) { item.title = titles[7] }
            else if item.action == #selector(startColorPicker) { item.title = titles[8] }
            else if item.action == #selector(startOCR) { item.title = titles[9] }
        }
    }
}
