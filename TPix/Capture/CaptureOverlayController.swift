import AppKit
import SwiftUI

enum CaptureMode {
    case area
    case record
    case ocr
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

        let view = CaptureOverlayView(
            mode: mode,
            frame: screenFrame,
            screenCapture: screenCapture,
            onComplete: { [weak self] image, rect in
                self?.completeCapture(image: image, rect: rect)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )
        let hostingView = NSHostingView(rootView: view)
        window?.contentView = hostingView

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.makeFirstResponder(hostingView)
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
    }
}
