import SwiftUI
import AppKit

struct RecordingIndicatorView: View {
    @ObservedObject var timer: RecordingTimer
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(timer.blinking ? 1 : 0.3)

            Text(timer.elapsedString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white)

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.3))

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.red)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.75))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }
}

final class RecordingTimer: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var blinking: Bool = true

    private var timer: Timer?
    private var blinkTimer: Timer?

    func start() {
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.elapsed += 1
        }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.blinking.toggle()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    var elapsedString: String {
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

final class RecordingIndicatorController {
    private var window: NSPanel?
    private let timer = RecordingTimer()

    func show(onStop: @escaping () -> Void) {
        timer.start()

        let view = RecordingIndicatorView(timer: timer, onStop: onStop)
        let hostingView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - 180
        let y = screenFrame.maxY - 50
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.orderFrontRegardless()
        window = panel
    }

    func close() {
        timer.stop()
        window?.orderOut(nil)
        window = nil
    }
}
