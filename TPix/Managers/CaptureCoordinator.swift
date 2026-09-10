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
        if recordingManager != nil {
            stopRecording()
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
            self?.recordingIndicator?.close()
            self?.recordingIndicator = nil
            self?.showRecordingResult(url: url)
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
        recordingManager = nil
        recordingIndicator?.close()
        recordingIndicator = nil
    }

    private func showRecordingResult(url: URL) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.directoryURL = url.deletingLastPathComponent()
            panel.message = "录屏已保存: \(url.lastPathComponent)"
            panel.runModal()
        }
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
        OCRManager.shared.recognize(image: image) { result in
            DispatchQueue.main.async {
                if result.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "未识别到内容"
                    alert.informativeText = "未在选区中识别到文字或二维码"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "好")
                    alert.runModal()
                    return
                }

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.clipboardText, forType: .string)

                let alert = NSAlert()
                alert.messageText = "识别完成"
                alert.informativeText = "已复制到剪贴板:\n\n\(result.displayText.prefix(500))"
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
        captureController = nil
    }

    private func checkPermission() -> Bool {
        NSLog("[TPix] 检查屏幕录制权限...")
        let granted = ScreenPermissionChecker.shared.check()
        NSLog("[TPix] 权限结果: \(granted)")
        return granted
    }
}
