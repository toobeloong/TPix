import AppKit
import SwiftUI

final class PinManager {
    static let shared = PinManager()

    private var windows: [PinnedWindow] = []

    func pin(image: NSImage, at point: CGPoint? = nil) {
        let win = PinnedWindow(image: image, position: point)
        win.onClose = { [weak self] in
            self?.windows.removeAll { $0 === win }
        }
        win.show()
        windows.append(win)
    }
}

final class PinnedWindow: NSWindow {
    var onClose: (() -> Void)?

    init(image: NSImage, position: CGPoint? = nil) {
        let size = image.size
        let pos = position ?? CGPoint(x: 100, y: 100)
        let rect = NSRect(x: pos.x, y: pos.y, width: size.width, height: size.height)

        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: PinnedView(image: image, onClose: { [weak self] in
            self?.close()
        }))
        contentView = hostingView
    }

    func show() {
        orderFrontRegardless()
    }

    override func close() {
        onClose?()
        super.close()
    }
}

struct PinnedView: View {
    let image: NSImage
    let onClose: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    @State private var showControls = false

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .opacity(opacity)
                .onHover { hovering in
                    withAnimation { showControls = hovering }
                }
        }
        .overlay(alignment: .topTrailing) {
            if showControls {
                HStack(spacing: 4) {
                    Button(action: { scale = max(0.2, scale - 0.2) }) {
                        Image(systemName: "minus.magnifying")
                    }
                    Button(action: { scale = min(5, scale + 0.2) }) {
                        Image(systemName: "plus.magnifying")
                    }
                    Button(action: { opacity = opacity == 1.0 ? 0.5 : 1.0 }) {
                        Image(systemName: opacity < 1.0 ? "circle.lefthalf.filled" : "circle")
                    }
                    Button(action: { copyToClipboard() }) {
                        Image(systemName: "doc.on.doc")
                    }
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(6)
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
