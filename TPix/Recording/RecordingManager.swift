import AppKit
import ScreenCaptureKit
import AVFoundation

final class RecordingManager: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFinish: ((URL) -> Void)?

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let outputQueue = DispatchQueue(label: "com.pixaura.recording.output")
    private var firstFrameTime: CMTime?
    private var sessionStarted = false
    private var isRecording = false
    private var saveURL: URL?

    func start(rect: NSRect) {
        let fps = SettingsStore.shared.settings.recordingFPS
        let quality = SettingsStore.shared.settings.recordingQuality

        let url = makeSaveURL()
        saveURL = url

        // SCStreamConfiguration: sourceRect is in logical points, width/height in physical pixels
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelWidth = Int(rect.width * scale)
        let pixelHeight = Int(rect.height * scale)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        assetWriter = writer

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        assetWriterInput = input

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight,
            ]
        )
        self.adaptor = adaptor

        isRecording = true

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    await self.finishFailure()
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = pixelWidth
                config.height = pixelHeight
                config.sourceRect = rect
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
                config.queueDepth = 5
                config.showsCursor = true

                if quality == "high" {
                    config.pixelFormat = kCVPixelFormatType_32ARGB
                }

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
                self.stream = stream
                try await stream.startCapture()
            } catch {
                print("录屏启动失败: \(error)")
                await self.finishFailure()
            }
        }
    }

    private func finishFailure() async {
        isRecording = false
        stream?.stopCapture { _ in }
        assetWriterInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            guard let url = self?.saveURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false

        stream?.stopCapture { [weak self] _ in
            guard let self = self else { return }
            self.assetWriterInput?.markAsFinished()
            self.assetWriter?.finishWriting { [weak self] in
                guard let url = self?.saveURL else { return }
                DispatchQueue.main.async {
                    self?.onFinish?(url)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let input = assetWriterInput, input.isReadyForMoreMediaData,
              let adaptor = adaptor else { return }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !sessionStarted {
            sessionStarted = true
            firstFrameTime = time
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: time)
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("录屏停止: \(error)")
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
