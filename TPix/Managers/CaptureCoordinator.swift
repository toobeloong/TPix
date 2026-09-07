import AppKit
import ScreenCaptureKit
import Vision
import AVFoundation

final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    weak var pinManager: PinManager?

    private var captureController: CaptureOverlayController?
    private var recordingManager: RecordingManager?
    private var colorPickerPanel: ColorPickerPanel?
    private var ocrController: CaptureOverlayController?
    private var countdownWindow: NSWindow?
    private var countdownTimer: Timer?
    private var lastCaptureRect: NSRect?

    private init() {}

    private var isCaptureActive: Bool {
        captureController != nil || ocrController != nil
    }

    // MARK: - Area Capture

    func startAreaCapture() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        let ctrl = CaptureOverlayController(mode: .area)
        ctrl.onComplete = { [weak self] image, rect in
            self?.handleCaptureResult(image: image, rect: rect)
        }
        ctrl.onCancel = { [weak self] in
            self?.captureController = nil
        }
        ctrl.show()
        captureController = ctrl
    }

    // MARK: - Full Screen Capture

    func startFullScreenCapture() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        Task {
            for screen in NSScreen.screens {
                guard let image = await captureScreen(screen) else { continue }
                await MainActor.run {
                    handleCaptureResult(image: image, rect: nil)
                }
                break
            }
        }
    }

    // MARK: - Delay Capture

    // MARK: - Window Under Cursor Capture

    func captureWindowUnderCursor() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        // NSEvent.mouseLocation is global NS coordinate (bottom-left origin), same as kCGWindowBounds
        let cursor = NSEvent.mouseLocation
        let cgPoint = CGPoint(x: cursor.x, y: cursor.y)

        guard let windowInfo = WindowDetector.findWindow(at: cgPoint) else {
            startFullScreenCapture()
            return
        }

        Task {
            await captureWindowByID(windowInfo: windowInfo)
        }
    }

    private func captureWindowByID(windowInfo: WindowInfo) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard content.displays.first != nil else {
                fallbackWindowCapture(windowInfo: windowInfo)
                return
            }
            guard let window = content.windows.first(where: { $0.windowID == windowInfo.windowID }) else {
                fallbackWindowCapture(windowInfo: windowInfo)
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            config.width = Int(windowInfo.rect.width * scale)
            config.height = Int(windowInfo.rect.height * scale)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let image = NSImage(cgImage: cgImage, size: windowInfo.rect.size)
            handleCaptureResult(image: image, rect: windowInfo.rect)
            lastCaptureRect = windowInfo.rect
        } catch {
            fallbackWindowCapture(windowInfo: windowInfo)
        }
    }

    private func fallbackWindowCapture(windowInfo: WindowInfo) {
        guard let cgImage = CGWindowListCreateImage(
            windowInfo.rect,
            .optionOnScreenOnly,
            windowInfo.windowID,
            [.bestResolution]
        ) else { return }
        let image = NSImage(cgImage: cgImage, size: windowInfo.rect.size)
        handleCaptureResult(image: image, rect: windowInfo.rect)
        lastCaptureRect = windowInfo.rect
    }

    // MARK: - Repeat Last Capture

    func repeatLastCapture() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        guard let rect = lastCaptureRect else {
            // No previous capture, start area capture
            startAreaCapture()
            return
        }

        Task {
            await captureRect(rect)
        }
    }

    private func captureRect(_ rect: NSRect) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            config.width = Int(rect.width * scale)
            config.height = Int(rect.height * scale)
            // sourceRect is in CG coordinates (bottom-left origin), same as windowInfo.rect
            config.sourceRect = CGRect(
                x: rect.minX * scale,
                y: rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let image = NSImage(cgImage: cgImage, size: rect.size)
            handleCaptureResult(image: image, rect: rect)
        } catch {
            NSLog("[TPix] repeatLastCapture failed: \(error)")
        }
    }

    func startDelayCapture() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        let delay = SettingsStore.shared.settings.delaySeconds
        showCountdown(seconds: delay) { [weak self] in
            self?.startFullScreenCapture()
        }
    }

    private func showCountdown(seconds: Int, completion: @escaping () -> Void) {
        // Clean up any existing countdown
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownWindow?.orderOut(nil)
        countdownWindow = nil

        guard let screen = NSScreen.main else { completion(); return }
        let frame = screen.frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: CountdownView(totalSeconds: seconds))
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window

        var remaining = seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining > 0 {
                NSSound.beep()
                NotificationCenter.default.post(name: NSNotification.Name("CountdownTick"), object: remaining)
            } else {
                timer.invalidate()
                self?.countdownTimer = nil
                self?.countdownWindow?.orderOut(nil)
                self?.countdownWindow = nil
                completion()
            }
        }
        NSSound.beep()
    }

    // MARK: - Scroll Capture

    func startScrollCapture() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        let ctrl = CaptureOverlayController(mode: .scroll)
        ctrl.onComplete = { [weak self] image, rect in
            self?.handleCaptureResult(image: image, rect: rect)
        }
        ctrl.onCancel = { [weak self] in
            self?.captureController = nil
        }
        ctrl.show()
        captureController = ctrl
    }

    // MARK: - Recording

    func toggleRecording() {
        if recordingManager != nil {
            recordingManager?.stop()
            recordingManager = nil
        } else {
            let ctrl = CaptureOverlayController(mode: .record)
            ctrl.onComplete = { [weak self] image, rect in
                guard let rect = rect else { return }
                self?.startRecording(rect: rect)
                self?.captureController = nil
            }
            ctrl.onCancel = { [weak self] in
                self?.captureController = nil
            }
            ctrl.show()
            captureController = ctrl
        }
    }

    private func startRecording(rect: NSRect) {
        let mgr = RecordingManager()
        mgr.onFinish = { [weak self] url in
            self?.recordingManager = nil
            self?.showRecordingResult(url: url)
        }
        mgr.start(rect: rect)
        recordingManager = mgr
    }

    private func showRecordingResult(url: URL) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.directoryURL = url.deletingLastPathComponent()
            panel.message = "录屏已保存: \(url.lastPathComponent)"
            panel.runModal()
        }
    }

    // MARK: - Pin

    func startPinFromClipboard() {
        let pb = NSPasteboard.general
        if let imgData = pb.data(forType: .png), let img = NSImage(data: imgData) {
            pinManager?.pin(image: img)
        } else if let tiff = pb.data(forType: .tiff), let img = NSImage(data: tiff) {
            pinManager?.pin(image: img)
        }
    }

    // MARK: - Color Picker

    func startColorPicker() {
        let panel = ColorPickerPanel()
        panel.show()
        colorPickerPanel = panel
    }

    // MARK: - OCR

    func startOCR() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        let ctrl = CaptureOverlayController(mode: .ocr)
        ctrl.onComplete = { [weak self] image, rect in
            guard let image = image else { return }
            self?.performOCR(on: image)
            self?.captureController = nil
        }
        ctrl.onCancel = { [weak self] in
            self?.captureController = nil
        }
        ctrl.show()
        captureController = ctrl
    }

    private func performOCR(on image: NSImage) {
        OCRManager.shared.recognize(image: image) { text in
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                let alert = NSAlert()
                alert.messageText = "OCR 识别完成"
                alert.informativeText = "已复制到剪贴板:\n\n\(text.prefix(500))"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }
    }

    // MARK: - Helpers

    private func handleCaptureResult(image: NSImage?, rect: NSRect?) {
        guard let image = image else { return }
        let s = SettingsStore.shared.settings
        if s.autoCopyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
        if s.saveToFolder {
            ImageSaver.shared.save(image: image)
        }
        if let pinManager = pinManager, s.autoCopyToClipboard == false {
            pinManager.pin(image: image)
        }
        captureController = nil
    }

    private func checkPermission() -> Bool {
        NSLog("[TPix] 检查屏幕录制权限...")
        let granted = ScreenPermissionChecker.shared.check()
        NSLog("[TPix] 权限结果: \(granted)")
        return granted
    }

    func captureScreen(_ screen: NSScreen) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return fallbackScreenCapture(screen) }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width)
            config.height = Int(screen.frame.height)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            return fallbackScreenCapture(screen)
        }
    }

    private func fallbackScreenCapture(_ screen: NSScreen) -> NSImage? {
        let rect = screen.frame
        guard let windowID = screen.deviceDescription[NSDeviceDescriptionKey("NSWindowNumber")] as? NSNumber else {
            return nil
        }
        guard let cgImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, CGWindowID(windowID.intValue), [.bestResolution]) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: rect.size)
    }
}

import SwiftUI

struct CountdownView: View {
    let totalSeconds: Int
    @State private var remaining: Int

    init(totalSeconds: Int) {
        self.totalSeconds = totalSeconds
        _remaining = State(initialValue: totalSeconds)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("\(remaining)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CountdownTick"))) { note in
                        if let val = note.object as? Int {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                remaining = val
                            }
                        }
                    }

                Text("即将开始截图...")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
