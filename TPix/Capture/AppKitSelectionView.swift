import AppKit
import CoreGraphics

/// 纯 AppKit 选区视图：直接处理鼠标事件 + CGContext 绘制，
/// 替代 SwiftUI DragGesture + body 重算，获得接近 iShot 的选区流畅度。
final class AppKitSelectionView: NSView {

    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private let screenImage: NSImage?
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint = .zero
    private var isDragging = false
    private var selectionRect: NSRect?
    private var isDone = false

    init(frame: NSRect,
         screenImage: NSImage?,
         onComplete: @escaping (NSRect) -> Void,
         onCancel: @escaping () -> Void) {
        self.screenImage = screenImage
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint!
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        currentPoint = convert(event.locationInWindow, from: nil)

        guard let start = startPoint else { return }
        let rect = normalized(start, currentPoint)
        if rect.width >= 10 && rect.height >= 10 {
            selectionRect = rect
            isDone = true
            needsDisplay = true
            onComplete?(rect)
        } else {
            startPoint = nil
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. 屏幕截图背景
        if let cg = screenImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(origin: .zero, size: bounds.size))
            ctx.restoreGState()
        }

        // 2. 选区 / 暗化
        let activeRect = isDragging ? currentActiveRect() : selectionRect

        if let rect = activeRect {
            drawDimOutside(ctx, rect)
            drawSelectionBorder(ctx, rect)
            drawSizeLabel(ctx, rect)
        } else {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.fill(bounds)
        }
    }

    // MARK: - Private

    private func normalized(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x),
               y: min(a.y, b.y),
               width: abs(a.x - b.x),
               height: abs(a.y - b.y))
    }

    private func currentActiveRect() -> NSRect {
        guard let start = startPoint else { return .zero }
        return normalized(start, currentPoint)
    }

    private func drawDimOutside(_ ctx: CGContext, _ rect: NSRect) {
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(rect)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    private func drawSelectionBorder(_ ctx: CGContext, _ rect: NSRect) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)

        let h: CGFloat = 8
        let corners = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ]
        ctx.setFillColor(NSColor.white.cgColor)
        for c in corners {
            ctx.fill(NSRect(x: c.x - h/2, y: c.y - h/2, width: h, height: h))
        }
        ctx.restoreGState()
    }

    private func drawSizeLabel(_ ctx: CGContext, _ rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textSize = attributed.size()

        var labelRect = NSRect(x: rect.minX,
                               y: rect.minY - textSize.height - 8,
                               width: textSize.width + 12,
                               height: textSize.height + 6)
        if labelRect.minY < 0 {
            labelRect.origin.y = rect.minY + 4
        }

        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        let rounded = CGPath(roundedRect: labelRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(rounded)
        ctx.fillPath()
        ctx.restoreGState()

        attributed.draw(at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 3))
    }
}
