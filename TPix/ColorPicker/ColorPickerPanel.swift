import AppKit
import SwiftUI

final class ColorPickerPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovable = true
        self.hasShadow = true

        guard let screen = NSScreen.main else {
            return
        }
        let x = (screen.frame.width - 220) / 2
        let y = (screen.frame.height - 140) / 2
        self.setFrameOrigin(CGPoint(x: x, y: y))

        let hostingView = NSHostingView(rootView: ColorPickerView(onClose: { [weak self] in
            self?.close()
        }))
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }

    func show() {
        orderFrontRegardless()
    }
}

struct ColorPickerView: View {
    let onClose: () -> Void

    @State private var pickedColor: NSColor = .red
    @State private var hexString: String = "#FF0000"
    @State private var rgbString: String = "RGB(255, 0, 0)"
    @State private var monitor: Any?
    @State private var clickMonitor: Any?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color(nsColor: pickedColor))
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.3), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(hexString)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(rgbString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Text("移动鼠标取色，点击确认")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))

            HStack(spacing: 8) {
                Button("复制 HEX") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hexString, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("复制 RGB") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rgbString.replacingOccurrences(of: "RGB", with: ""), forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("关闭") { onClose() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .onAppear {
            startPicking()
        }
        .onDisappear {
            stopPicking()
        }
    }

    private func startPicking() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            DispatchQueue.main.async {
                pickColorAtCursor()
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hexString, forType: .string)
                onClose()
            }
        }
    }

    private func stopPicking() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }

    private func pickColorAtCursor() {
        let pos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pos, $0.frame, false) }) else { return }

        // Find the topmost window under cursor that is NOT our app's window
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return }

        let myWindowIDs = Set(NSApp.windows.map { CGWindowID($0.windowNumber) })

        // kCGWindowBounds is in CG coords (top-left origin), pos is in NS coords (bottom-left origin)
        // Convert pos to CG coords for bounds.contains check
        let screenHeight = NSScreen.main?.frame.height ?? screen.frame.height
        let cgPos = CGPoint(x: pos.x, y: screenHeight - pos.y)

        var targetWindowID: CGWindowID?
        for info in windowInfo {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? CGRect,
                  bounds.contains(cgPos),
                  !myWindowIDs.contains(wid) else { continue }
            targetWindowID = wid
            break
        }

        guard let wid = targetWindowID else { return }

        // Capture just that window
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionOnScreenOnly,
            wid,
            [.bestResolution]
        ) else { return }

        // Get window bounds again for coordinate calculation
        guard let info2 = CGWindowListCopyWindowInfo([.optionOnScreenOnly], wid) as? [[String: Any]],
              let firstInfo = info2.first,
              let bounds = firstInfo[kCGWindowBounds as String] as? CGRect else { return }

        // pos is NS coords (bottom-left), bounds is CG coords (top-left)
        // Convert pos to CG coords relative to window
        let cgY = screenHeight - pos.y
        let localX = pos.x - bounds.minX
        let localY = cgY - bounds.minY

        let scale = screen.backingScaleFactor
        let pixelX = Int(localX * scale)
        let pixelY = Int(cgImage.height) - Int(localY * scale) - 1

        guard pixelX >= 0, pixelX < cgImage.width,
              pixelY >= 0, pixelY < cgImage.height else { return }

        guard let color = cgImage.pixel(at: CGPoint(x: pixelX, y: pixelY)) else { return }

        pickedColor = color
        hexString = String(format: "#%02X%02X%02X",
                           Int(color.redComponent * 255),
                           Int(color.greenComponent * 255),
                           Int(color.blueComponent * 255))
        rgbString = "RGB(\(Int(color.redComponent * 255)), \(Int(color.greenComponent * 255)), \(Int(color.blueComponent * 255)))"
    }
}

extension CGImage {
    func pixel(at point: CGPoint) -> NSColor? {
        let width = self.width
        let height = self.height
        guard point.x >= 0, point.y >= 0,
              Int(point.x) < width, Int(point.y) < height else { return nil }

        let bytesPerPixel = 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(self, in: CGRect(x: -CGFloat(point.x), y: -CGFloat(point.y), width: CGFloat(width), height: CGFloat(height)))

        let r = CGFloat(pixelData[0]) / 255
        let g = CGFloat(pixelData[1]) / 255
        let b = CGFloat(pixelData[2]) / 255
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}
