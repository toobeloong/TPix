import AppKit
import ScreenCaptureKit
import Vision
import AVFoundation

final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var captureController: CaptureOverlayController?
    private var recordingManager: RecordingManager?
    private var ocrController: CaptureOverlayController?
    private var recordingIndicator: RecordingIndicatorController?
    private var ocrResultAlert: NSAlert?
    private var ocrResultSession: Any?

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

    // MARK: - Recording

    func toggleRecording() {
        NSLog("[TPix] toggleRecording called, recordingManager=\(String(describing: recordingManager))")
        if recordingManager != nil {
            stopRecording()
        } else {
            guard !isCaptureActive else {
                NSLog("[TPix] toggleRecording: capture already active, ignoring")
                return
            }
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
        #if arch(arm64)
        NSLog("[TPix] startRecording: running arm64 (native)")
        #elseif arch(x86_64)
        NSLog("[TPix] startRecording: running x86_64 (Rosetta)")
        #endif
        let mgr = RecordingManager()
        mgr.onFinish = { [weak self] url in
            self?.recordingManager = nil
            self?.recordingIndicator?.close()
            self?.recordingIndicator = nil
            self?.showRecordingResult(url: url)
        }
        mgr.onFailure = { [weak self] in
            NSLog("[TPix] startRecording: onFailure called")
            self?.recordingManager = nil
            self?.recordingIndicator?.close()
            self?.recordingIndicator = nil
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "录屏启动失败"
                alert.informativeText = "无法启动屏幕捕获，请检查屏幕录制权限或重启应用。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }
        mgr.start(rect: rect)
        recordingManager = mgr

        let indicator = RecordingIndicatorController()
        indicator.show { [weak self] in
            self?.stopRecording()
        }
        recordingIndicator = indicator
    }

    private func stopRecording() {
        recordingManager?.stop()
        recordingIndicator?.close()
        recordingIndicator = nil
        // 不立即释放 recordingManager，等 onFinish/onFailure 回调再清理
    }
    private func showRecordingResult(url: URL) {
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - OCR

    func startOCR() {
        // 如果已有 OCR 结果弹窗，先关闭它
        if let alert = ocrResultAlert {
            alert.window.close()
            ocrResultAlert = nil
        }
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

    func startQuickOCR() {
        guard !isCaptureActive else { return }
        guard checkPermission() else { return }
        let ctrl = CaptureOverlayController(mode: .quickOcr)
        ctrl.onComplete = { [weak self] image, rect in
            guard let image = image else { return }
            self?.performQuickOCR(on: image)
            self?.captureController = nil
        }
        ctrl.onCancel = { [weak self] in
            self?.captureController = nil
        }
        ctrl.show()
        captureController = ctrl
    }

    private func performQuickOCR(on image: NSImage) {
        OCRManager.shared.recognize(image: image) { result in
            DispatchQueue.main.async {
                if result.isEmpty {
                    self.showToast(message: "未识别到内容", success: false)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.clipboardText, forType: .string)
                self.showToast(message: "已复制到剪贴板", success: true)
            }
        }
    }

    private func performOCR(on image: NSImage) {
        OCRManager.shared.recognize(image: image) { result in
            DispatchQueue.main.async {
                if result.isEmpty {
                    self.showToast(message: "未识别到内容", success: false)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.clipboardText, forType: .string)
                self.showToast(message: "已复制到剪贴板", success: true)
            }
        }
    }

    /// 统一的 Toast 提示浮窗
    private func showToast(message: String, success: Bool) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces]

        let icon = success ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        let iconColor = success ? NSColor.systemGreen : NSColor.systemOrange

        let iconView = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil)!)
        iconView.contentTintColor = iconColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        let bgView = NSVisualEffectView(frame: container.bounds)
        bgView.material = .hudWindow
        bgView.blendingMode = .behindWindow
        bgView.state = .active
        bgView.layer?.cornerRadius = 12
        bgView.wantsLayer = true

        bgView.addSubview(iconView)
        bgView.addSubview(label)
        container.addSubview(bgView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: bgView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: bgView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: bgView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: bgView.trailingAnchor, constant: -16),
        ])

        panel.contentView = container

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sf = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: sf.midX - 140, y: sf.maxY - 80))
        panel.orderFrontRegardless()

        // 淡入淡出动画
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak panel] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                panel?.animator().alphaValue = 0
            }, completionHandler: {
                panel?.orderOut(nil)
            })
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
        captureController = nil
    }

    private func checkPermission() -> Bool {
        NSLog("[TPix] 检查屏幕录制权限...")
        let granted = ScreenPermissionChecker.shared.check()
        NSLog("[TPix] 权限结果: \(granted)")
        return granted
    }
}
