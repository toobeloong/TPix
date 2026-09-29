import AppKit
import SwiftUI

enum CaptureMode {
    case area
    case record
    case ocr
    case quickOcr
}

class CaptureOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CaptureOverlayController: NSWindowController {
    var onComplete: ((NSImage?, NSRect?) -> Void)?
    var onCancel: (() -> Void)?

    private let mode: CaptureMode
    private var screenCapture: NSImage?
    private var escLocalMonitor: Any?
    private var escGlobalMonitor: Any?
    private var isClosed = false
    private var previousApp: NSRunningApplication?

    init(mode: CaptureMode) {
        self.mode = mode
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.frame

        NSLog("[TPix] screen.frame=\(screenFrame), screen.backingScaleFactor=\(screen.backingScaleFactor)")

        let win = CaptureOverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.isMovable = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.ignoresMouseEvents = false

        super.init(window: win)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSLog("[TPix] CaptureOverlayController.show() 开始")

        // 记录当前活跃的 app，完成后恢复焦点
        previousApp = NSWorkspace.shared.frontmostApplication

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.frame

        NSLog("[TPix] screen.frame=\(screenFrame), screen.visibleFrame=\(screen.visibleFrame)")

        var screenCapture: NSImage? = nil
        if let cgImage = CGWindowListCreateImage(
            screenFrame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) {
            screenCapture = NSImage(cgImage: cgImage, size: screenFrame.size)
            NSLog("[TPix] 全屏截图成功，size=\(screenCapture?.size ?? .zero)")
        } else {
            NSLog("[TPix] 全屏截图失败!")
        }

        let selectionView = AppKitSelectionView(
            frame: screenFrame,
            screenImage: screenCapture,
            onComplete: { [weak self] rect in
                self?.handleSelection(rect, screenCapture: screenCapture)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )
        window?.contentView = selectionView

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.makeFirstResponder(selectionView)
        NSApp.activate(ignoringOtherApps: true)

        let cancel: () -> Void = { [weak self] in
            self?.cancelCapture()
        }

        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                cancel()
                return nil
            }
            return event
        }

        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                cancel()
            }
        }

        NSLog("[TPix] 窗口已 orderFront, isVisible=\(window?.isVisible ?? false)")
    }

    /// 选区完成后的分发：area 进入标注，其余模式直接产出结果。
    private func handleSelection(_ rect: NSRect, screenCapture: NSImage?) {
        switch mode {
        case .record:
            completeCapture(image: nil, rect: rect)
        case .ocr, .quickOcr:
            guard let image = screenCapture else {
                NSLog("[TPix] 全屏截图缺失，无法识别")
                completeCapture(image: nil, rect: rect)
                return
            }
            let cropped = ImageCutter.crop(image, rect: rect)
            completeCapture(image: cropped, rect: rect)
        case .area:
            enterAnnotationMode(rect: rect, screenCapture: screenCapture)
        }
    }

    /// area 模式：选区完成后切换为 SwiftUI 标注界面（预置选区）。
    private func enterAnnotationMode(rect: NSRect, screenCapture: NSImage?) {
        guard let win = window else { return }
        let screenFrame = win.frame

        let view = CaptureOverlayView(
            mode: .area,
            frame: screenFrame,
            screenCapture: screenCapture,
            initialSelectionRect: rect,
            onComplete: { [weak self] image, r in
                self?.completeCapture(image: image, rect: r ?? rect)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )
        let hostingView = NSHostingView(rootView: view)
        win.contentView = hostingView
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(hostingView)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func cancelCapture() {
        guard !isClosed else { return }
        isClosed = true
        onCancel?()
        close()
    }

    private func completeCapture(image: NSImage?, rect: NSRect?) {
        guard !isClosed else { return }
        isClosed = true
        onComplete?(image, rect)
        close()
    }

    override func close() {
        if let m = escLocalMonitor {
            NSEvent.removeMonitor(m)
            escLocalMonitor = nil
        }
        if let m = escGlobalMonitor {
            NSEvent.removeMonitor(m)
            escGlobalMonitor = nil
        }
        window?.close()
        // 截图/OCR 完成后将焦点还给之前活跃的 app
        if let app = previousApp, app != NSRunningApplication.current {
            app.activate(options: [])
        }
    }
}
