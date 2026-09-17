import AppKit
import ScreenCaptureKit
import AVFoundation

final class RecordingManager: NSObject, SCStreamDelegate {
    var onFinish: ((URL) -> Void)?
    var onFailure: (() -> Void)?

    private var stream: SCStream?
    private var recordingOutput: Any?
    private let outputQueue = DispatchQueue(label: "com.pixaura.recording.output")
    private var isRecording = false
    private var saveURL: URL?
    private var isFinished = false

    func start(rect: NSRect) {
        let fps = SettingsStore.shared.settings.recordingFPS

        let url = makeSaveURL()
        saveURL = url
        NSLog("[TPix] RecordingManager.start: rect=\(rect), url=\(url)")

        let screen = NSScreen.main ?? NSScreen.screens.first!

        let scale = screen.backingScaleFactor
        let pixelWidth = Int(rect.width * scale)
        let pixelHeight = Int(rect.height * scale)
        // SCRecordingOutput/H264 需要偶数尺寸，对齐到最近的偶数
        let captureWidth = pixelWidth + (pixelWidth % 2)
        let captureHeight = pixelHeight + (pixelHeight % 2)
        NSLog("[TPix] RecordingManager.start: pixelSize=\(captureWidth)x\(captureHeight), scale=\(scale)")

        isRecording = true

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    NSLog("[TPix] RecordingManager: no display found")
                    await self.finishFailure()
                    return
                }

                // sourceRect: display 坐标系，逻辑点
                // 尝试不翻转 Y（SCStream 可能内部已处理坐标转换）
                let sourceRect = CGRect(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                NSLog("[TPix] RecordingManager: selectionRect=\(rect), sourceRect=\(sourceRect)")

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = captureWidth
                config.height = captureHeight
                config.sourceRect = sourceRect
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
                config.queueDepth = 5
                config.showsCursor = true

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                self.stream = stream

                if #available(macOS 15.0, *) {
                    // 使用 SCRecordingOutput 自动管理文件写入
                    let recordingConfig = SCRecordingOutputConfiguration()
                    recordingConfig.outputURL = url
                    recordingConfig.videoCodecType = .h264

                    let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
                    try stream.addRecordingOutput(output)
                    self.recordingOutput = output
                    NSLog("[TPix] RecordingManager: using SCRecordingOutput")
                } else {
                    // macOS 14 fallback: 不支持录屏
                    NSLog("[TPix] RecordingManager: SCRecordingOutput requires macOS 15+")
                    await self.finishFailure()
                    return
                }

                NSLog("[TPix] RecordingManager: starting capture...")
                try await stream.startCapture()
                NSLog("[TPix] RecordingManager: capture started successfully")
            } catch {
                NSLog("[TPix] RecordingManager: capture start failed: \(error)")
                NSLog("[TPix] RecordingManager: error domain=\(error.localizedDescription), reason=\((error as NSError).localizedFailureReason ?? "none")")
                await self.finishFailure()
            }
        }
    }

    func stop() {
        guard isRecording else {
            NSLog("[TPix] RecordingManager.stop: not recording, ignoring")
            return
        }
        isRecording = false
        NSLog("[TPix] RecordingManager.stop: stopping capture")

        stream?.stopCapture { [weak self] _ in
            NSLog("[TPix] RecordingManager.stop: stopCapture callback received")
            // SCRecordingOutput 会在文件写入完成后调 recordingOutputDidFinishRecording
            // 这里只停止流，onFinish 在 recordingOutputDidFinishRecording 中触发
        }
    }

    private func finishFailure() async {
        isRecording = false
        stream?.stopCapture { _ in }
        guard !isFinished else { return }
        isFinished = true
        if let url = saveURL {
            try? FileManager.default.removeItem(at: url)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[TPix] RecordingManager: stream stopped with error: \(error)")
        isRecording = false
    }

    private func makeSaveURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "TPix_\(formatter.string(from: Date())).mp4"
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(name)
    }
}

// SCRecordingOutputDelegate 需要 macOS 15+
@available(macOS 15.0, *)
extension RecordingManager: SCRecordingOutputDelegate {
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        NSLog("[TPix] RecordingManager: SCRecordingOutput error: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?()
        }
    }

    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        NSLog("[TPix] RecordingManager: SCRecordingOutput finished recording")
        guard !isFinished else { return }
        isFinished = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let url = self.saveURL else { return }
            self.onFinish?(url)
        }
    }

    func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        NSLog("[TPix] RecordingManager: SCRecordingOutput started recording")
    }
}
