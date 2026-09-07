import SwiftUI
import AppKit
import ScreenCaptureKit

struct CaptureOverlayView: View {
    let mode: CaptureMode
    let frame: NSRect
    let screenCapture: NSImage?
    let onComplete: (NSImage?, NSRect?) -> Void
    let onCancel: () -> Void

    // Window capture image (set after window capture, used as background for editing)
    @State private var capturedWindowImage: NSImage? = nil
    @State private var isWindowCaptureMode: Bool = false  // true when selection is from window snap
    @State private var lastHoverCheckTime: Date = .distantPast

    // Selection state
    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false
    @State private var selectionRect: NSRect = .zero
    @State private var isSelectionDone = false

    // Magnifier
    @State private var mouseLocation: CGPoint = .zero

    // Resize / Move
    @State private var dragMode: SelectionDragMode = .none
    @State private var dragStartLocation: CGPoint = .zero
    @State private var dragStartRect: NSRect = .zero
    @State private var didDrag: Bool = false
    @State private var lastClickTime: Date = .distantPast
    @State private var lastClickLocation: CGPoint = .zero

    // Window capture
    @State private var hoveredWindowRect: NSRect = .zero
    @State private var hoveredWindowCenter: CGPoint = .zero
    @State private var hoveredWindowSize: CGSize = .zero
    @State private var hoveredWindowID: CGWindowID = 0
    @State private var lastHoveredWindowRect: NSRect = .zero
    @State private var lastHoveredWindowID: CGWindowID = 0
    @State private var isDraggingStarted: Bool = false

    // Annotation
    @State private var shapes: [AnnotationShape] = []
    @State private var redoStack: [AnnotationShape] = []
    @State private var currentTool: AnnotationTool = .move
    @State private var toolColors: [AnnotationTool: Color] = [:]
    @State private var toolLineWidths: [AnnotationTool: CGFloat] = [:]
    @State private var toolFontSizes: [AnnotationTool: CGFloat] = [:]
    @State private var arrowStyle: ArrowStyle = .solid
    @State private var mosaicStyle: MosaicStyle = .pixelate
    @State private var mosaicImageCache: [UUID: NSImage] = [:]
    @State private var numberCounter = 1
    @State private var isDrawing = false
    @State private var dragStart: CGPoint = .zero
    @State private var currentPoints: [CGPoint] = []
    @State private var textInput: String = ""
    @State private var textPosition: CGPoint?
    @State private var showTextInput = false
    @State private var textInputSize: CGSize = CGSize(width: 60, height: 28)
    @State private var editingTextShapeId: UUID? = nil
    @State private var hoveredTextShapeId: UUID? = nil
    @State private var textDragMode: TextDragMode = .none
    @State private var textDragStartLocation: CGPoint = .zero
    @State private var textDragStartPoint: CGPoint = .zero
    @State private var didCommitTextThisGesture = false

    enum TextDragMode {
        case none, move
    }

    private var currentColor: Color {
        get { toolColors[currentTool] ?? defaultColorForTool(currentTool) }
    }
    private var currentLineWidth: CGFloat {
        get { toolLineWidths[currentTool] ?? defaultLineWidthForTool(currentTool) }
    }
    private var currentFontSize: CGFloat {
        get { toolFontSizes[currentTool] ?? 16 }
    }

    private func defaultColorForTool(_ tool: AnnotationTool) -> Color {
        switch tool {
        case .highlight: return .yellow
        case .mosaic: return .gray
        default: return .red
        }
    }

    private func defaultLineWidthForTool(_ tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .highlight: return 8
        case .pencil: return 3
        case .text: return 2
        default: return 3
        }
    }

    private func setColor(_ c: Color) {
        toolColors[currentTool] = c
    }
    private func setLineWidth(_ w: CGFloat) {
        toolLineWidths[currentTool] = w
    }
    private func setFontSize(_ s: CGFloat) {
        toolFontSizes[currentTool] = s
    }

    enum SelectionDragMode {
        case none, move
        case resizeLeft, resizeRight, resizeTop, resizeBottom
        case resizeTopLeft, resizeTopRight, resizeBottomLeft, resizeBottomRight
    }

    private let handleSize: CGFloat = 8
    private let edgeTolerance: CGFloat = 8

    var body: some View {
        ZStack {
            // Full screen background
            if let img = screenCapture {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .allowsHitTesting(false)
            }

            // Window capture image displayed at window position (after window snap, for editing)
            if isWindowCaptureMode, let img = capturedWindowImage, isSelectionDone {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .allowsHitTesting(false)
            }

            // Dim outside selection (only when selecting or done)
            if isDragging || isSelectionDone {
                dimOverlay
                    .allowsHitTesting(false)
            } else {
                // Full dim before selection
                Color.black.opacity(0.3)
                    .allowsHitTesting(false)
            }

            // Window highlight (only before selection is done)
            if !isSelectionDone {
                windowHighlight
                    .allowsHitTesting(false)
            }

            // Selection border + handles
            if isDragging || isSelectionDone {
                selectionBorder
                    .allowsHitTesting(false)
            }

            // Annotation canvas (only when selection is done)
            if isSelectionDone {
                annotationCanvas
            }

            // Text input
            if showTextInput, let pos = textPosition {
                FocusableTextEditor(
                    text: $textInput,
                    onCommit: {
                        commitTextInput()
                    },
                    fontColor: NSColor(currentColor),
                    fontSize: currentFontSize,
                    onSizeChange: { size in
                        textInputSize = size
                    }
                )
                .frame(width: max(40, textInputSize.width), height: max(20, textInputSize.height), alignment: .topLeading)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.6), lineWidth: 1))
                .position(x: pos.x + selectionRect.minX + max(40, textInputSize.width) / 2,
                          y: pos.y + selectionRect.minY + max(20, textInputSize.height) / 2)
                .zIndex(50)
            }

            // Text shape hover highlight (when not editing text)
            if !showTextInput && (currentTool == .move || currentTool == .text) {
                ForEach(shapes) { shape in
                    if shape.tool == .text, let bbox = shape.textBoundingBox() {
                        let localRect = NSRect(
                            x: bbox.minX + selectionRect.minX,
                            y: bbox.minY + selectionRect.minY,
                            width: bbox.width,
                            height: bbox.height
                        )
                        if hoveredTextShapeId == shape.id {
                            Rectangle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                .frame(width: localRect.width + 8, height: localRect.height + 4)
                                .position(x: localRect.midX, y: localRect.midY)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }

            // Full-screen crosshair lines (only before selection is done)
            if !isSelectionDone {
                ZStack {
                    // Horizontal line
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: frame.width, height: 1)
                        .position(x: frame.width / 2, y: mouseLocation.y)
                    // Vertical line
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 1, height: frame.height)
                        .position(x: mouseLocation.x, y: frame.height / 2)
                }
                .allowsHitTesting(false)
            }

            // Magnifier (only before selection is done)
            if !isSelectionDone {
                MagnifierView(
                    mouseLocation: mouseLocation,
                    screenImage: screenCapture,
                    screenSize: frame.size
                )
                .allowsHitTesting(false)
            }

            // Hint text
            if !isDragging && !isSelectionDone {
                VStack(spacing: 8) {
                    Text(hintText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Text("按 ESC 取消")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .allowsHitTesting(false)
            }

            // Size label
            if isSelectionDone {
                selectionSizeLabel
                    .allowsHitTesting(false)
            }

            // Toolbar
            if isSelectionDone {
                toolbar
                    .position(x: toolbarPosition.x, y: toolbarPosition.y)
                    .zIndex(100)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let loc) = phase {
                mouseLocation = loc
                if !isSelectionDone && !isDraggingStarted {
                    let now = Date()
                    if now.timeIntervalSince(lastHoverCheckTime) > 0.05 {
                        lastHoverCheckTime = now
                        updateHoveredWindow(at: loc)
                    }
                }
                // Text shape hover detection (move or text tool, not editing)
                if isSelectionDone && !showTextInput && (currentTool == .move || currentTool == .text) && textDragMode == .none {
                    if let shape = findTextShape(at: loc) {
                        hoveredTextShapeId = shape.id
                    } else {
                        hoveredTextShapeId = nil
                    }
                }
            } else if case .ended = phase {
                hoveredTextShapeId = nil
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    mouseLocation = value.location

                    let dragDistance = sqrt(pow(value.location.x - value.startLocation.x, 2) +
                                            pow(value.location.y - value.startLocation.y, 2))
                    if dragDistance > 3 {
                        didDrag = true
                        isDraggingStarted = true
                        hoveredWindowID = 0
                        hoveredWindowRect = .zero
                    }

                    if isSelectionDone {
                        if isPointInToolbar(value.location) {
                            return
                        }

                        // If text input is showing and click is outside it, commit and stop
                        if showTextInput, let pos = textPosition {
                            let inputRect = NSRect(
                                x: pos.x + selectionRect.minX,
                                y: pos.y + selectionRect.minY,
                                width: max(40, textInputSize.width),
                                height: max(20, textInputSize.height)
                            )
                            if !inputRect.contains(value.location) {
                                commitTextInput()
                                didCommitTextThisGesture = true
                                return
                            }
                        }

                        // Text shape dragging
                        if textDragMode == .move, let _ = hoveredTextShapeId {
                            let dx = value.location.x - textDragStartLocation.x
                            let dy = value.location.y - textDragStartLocation.y
                            let newPoint = CGPoint(x: textDragStartPoint.x + dx, y: textDragStartPoint.y + dy)
                            if let idx = shapes.firstIndex(where: { $0.id == hoveredTextShapeId }) {
                                shapes[idx].points = [newPoint]
                            }
                            return
                        }

                        if dragMode == .none && textDragMode == .none {
                            // Check for text shape interaction (move or text tool)
                            if (currentTool == .move || currentTool == .text) && !showTextInput {
                                if let shape = findTextShape(at: value.location) {
                                    if isOnTextBorder(value.location, shape: shape) {
                                        textDragMode = .move
                                        textDragStartLocation = value.location
                                        textDragStartPoint = shape.points.first ?? .zero
                                        didDrag = false
                                        return
                                    } else {
                                        didDrag = false
                                        return
                                    }
                                }
                            }

                            // Window snap mode: no move/resize, only annotation
                            if isWindowCaptureMode {
                                if isInSelection(value.location) && currentTool != .move {
                                    didDrag = false
                                }
                            } else {
                                let m = hitTest(value.location)
                                if m != .none {
                                    dragMode = m
                                    dragStartLocation = value.location
                                    dragStartRect = selectionRect
                                    didDrag = false
                                } else if isInSelection(value.location) && currentTool != .move {
                                    didDrag = false
                                } else {
                                    isSelectionDone = false
                                    isDragging = true
                                    isDraggingStarted = false
                                    didDrag = false
                                    shapes = []
                                    redoStack = []
                                    startPoint = value.startLocation
                                    currentPoint = value.location
                                    updateSelectionRect()
                                }
                            }
                        }

                        if dragMode == .none && currentTool != .move {
                            handleAnnotationDraw(value)
                        } else if dragMode != .none && !isWindowCaptureMode {
                            applyDrag(value.location)
                        }
                    } else {
                        // 未选区时
                        if !isDragging {
                            startPoint = value.startLocation
                            isDragging = true
                            isDraggingStarted = false
                            didDrag = false
                        }
                        currentPoint = value.location
                        updateSelectionRect()
                    }
                }
                .onEnded { value in
                    // 窗口模式：单击截图窗口，拖动选区
                    if !isSelectionDone {
                        let dragDistance = sqrt(pow(value.location.x - value.startLocation.x, 2) +
                                               pow(value.location.y - value.startLocation.y, 2))
                        
                        // 单击：重新检测当前鼠标位置的窗口（确保窗口 ID 有效）
                        if dragDistance < 5 {
                            // 重新获取当前鼠标位置的窗口
                            // isFlipped=false: value.location is bottom-left origin, same as CG
                            let cgX = frame.origin.x + value.location.x
                            let cgY = frame.origin.y + value.location.y
                            let cgPoint = CGPoint(x: cgX, y: cgY)
                            
                            if let windowInfo = WindowDetector.findWindow(at: cgPoint, excludeWindowID: getCurrentWindowID()) {
                                NSLog("[TPix] onEnded: 单击截图窗口，windowID=\(windowInfo.windowID), rect=\(windowInfo.rect), title=\(windowInfo.title ?? "nil")")
                                
                                // 关键修复：在截图前隐藏所有 UI 元素，确保截取的是纯净的窗口内容
                                // 但由于 SwiftUI 是声明式的，我们无法在截图前"隐藏"再"显示"
                                // 所以改用 CGWindowListCreateImage 直接截取目标窗口，不经过屏幕渲染
                                
                                // 使用 .null 区域 + 窗口 ID 的方式，只截取目标窗口内容
                                // 这种方式不会包含我们的 UI（吸附框、放大镜等）
                                captureWindowFromInfo(windowInfo)
                                
                                // 重置状态
                                lastHoveredWindowID = 0
                                lastHoveredWindowRect = .zero
                                isDraggingStarted = false
                                return
                            }
                        }
                        
                        if dragDistance >= 5 {
                            // 拖动：选区截图
                            if selectionRect.width > 10 && selectionRect.height > 10 {
                                isSelectionDone = true
                                isDragging = false
                                didDrag = false
                            }
                        } else {
                            // 单击但没有悬停窗口，不处理
                        }
                    }

                    // 双击确认
                    let now = Date()
                    let clickDistance = sqrt(pow(value.location.x - lastClickLocation.x, 2) +
                                            pow(value.location.y - lastClickLocation.y, 2))
                    if isSelectionDone && !didDrag &&
                       now.timeIntervalSince(lastClickTime) < 0.3 && clickDistance < 10 {
                        confirmCapture()
                        lastClickTime = .distantPast
                        return
                    }
                    lastClickTime = now
                    lastClickLocation = value.location

                    // End text drag
                    if textDragMode == .move {
                        textDragMode = .none
                        didCommitTextThisGesture = false
                        return
                    }

                    // If we committed text input this gesture, don't create new input
                    if didCommitTextThisGesture {
                        didCommitTextThisGesture = false
                        return
                    }

                    // Click on existing text shape to edit (move or text tool, no drag)
                    if isSelectionDone && !didDrag && (currentTool == .move || currentTool == .text) && !showTextInput {
                        if let shape = findTextShape(at: value.location) {
                            startEditText(shape)
                            return
                        }
                    }

                    if isSelectionDone && dragMode == .none && !isPointInToolbar(value.location) {
                        handleAnnotationEnd()
                    } else if dragMode != .none {
                        dragMode = .none
                    } else if !isSelectionDone {
                        if selectionRect.width > 10 && selectionRect.height > 10 {
                            isDragging = false
                            isSelectionDone = true
                            didDrag = false
                        } else {
                            isDragging = false
                        }
                    }
                    didCommitTextThisGesture = false
                }
        )
        .focusable()
        .onKeyPress(.return) {
            if isSelectionDone && !showTextInput {
                confirmCapture()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress { keyEvent in
            // Single-key tool switching (only when selection done, not typing, no modifiers)
            guard isSelectionDone, !showTextInput, keyEvent.modifiers.isEmpty else { return .ignored }
            let key = keyEvent.characters.lowercased()
            let map: [String: AnnotationTool] = [
                "v": .move,
                "r": .rect,
                "o": .ellipse,
                "l": .line,
                "a": .arrow,
                "p": .pencil,
                "h": .highlight,
                "t": .text,
                "m": .mosaic,
                "n": .number,
                "e": .eraser,
            ]
            if let tool = map[key] {
                currentTool = tool
                return .handled
            }
            return .ignored
        }
        .background(ScrollWheelInterceptor(
            onScroll: { deltaY, location in
                handleScrollWheel(deltaY: deltaY, at: location)
            }
        ))
    }

    private func handleScrollWheel(deltaY: CGFloat, at location: CGPoint) {
        guard isSelectionDone else { return }
        // Check if cursor is on an existing annotation shape
        let local = CGPoint(x: location.x - selectionRect.minX, y: location.y - selectionRect.minY)
        if let idx = shapes.lastIndex(where: { shape in
            shape.tool != .text && shapeHitTest(shape, at: local)
        }) {
            // On annotation: adjust opacity
            let delta = deltaY > 0 ? 0.05 : -0.05
            shapes[idx].opacity = max(0.1, min(1.0, shapes[idx].opacity + delta))
        } else {
            // Outside annotation: adjust current tool line width
            let current = toolLineWidths[currentTool] ?? defaultLineWidth(for: currentTool)
            let delta = deltaY > 0 ? 1 : -1
            let newWidth = max(1, min(30, current + CGFloat(delta)))
            toolLineWidths[currentTool] = newWidth
        }
    }

    private func defaultLineWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .highlight: return 15
        case .pencil: return 3
        case .mosaic: return 20
        default: return 2
        }
    }

    private func getMosaicImage(for shape: AnnotationShape) -> NSImage? {
        if let cached = mosaicImageCache[shape.id] { return cached }
        guard shape.points.count >= 2 else { return nil }
        let fullImage: NSImage? = isWindowCaptureMode ? capturedWindowImage : screenCapture
        guard let img = fullImage, let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let r = rectFrom(shape.points)
        // In window capture mode, the image is already cropped to selection; no offset needed
        // In area capture mode, screenCapture is full screen, need to add selection offset
        let screenRect: CGRect
        if isWindowCaptureMode {
            screenRect = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height)
        } else {
            screenRect = CGRect(
                x: r.minX + selectionRect.minX,
                y: r.minY + selectionRect.minY,
                width: r.width,
                height: r.height
            )
        }
        // CGImage coordinate is top-left origin, need to flip Y
        let imgRect = CGRect(
            x: screenRect.minX,
            y: img.size.height - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
        guard imgRect.width > 1 && imgRect.height > 1,
              let cropped = cgImage.cropping(to: imgRect) else { return nil }

        let blockSize: Int = max(4, Int(shape.lineWidth))
        let smallWidth = max(1, Int(imgRect.width) / blockSize)
        let smallHeight = max(1, Int(imgRect.height) / blockSize)

        let result: NSImage?
        if shape.mosaicStyle == .pixelate {
            // Pixelate: draw small then scale up using CGContext
            let smallSize = CGSize(width: smallWidth, height: smallHeight)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let smallCtx = CGContext(data: nil, width: smallWidth, height: smallHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            smallCtx.draw(cropped, in: CGRect(origin: .zero, size: smallSize))
            guard let smallCG = smallCtx.makeImage() else { return nil }
            guard let bigCtx = CGContext(data: nil, width: Int(imgRect.width), height: Int(imgRect.height), bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            bigCtx.interpolationQuality = .none
            bigCtx.draw(smallCG, in: CGRect(origin: .zero, size: CGSize(width: Int(imgRect.width), height: Int(imgRect.height))))
            guard let scaledCG = bigCtx.makeImage() else { return nil }
            result = NSImage(cgImage: scaledCG, size: r.size)
        } else {
            // Blur: use CIFilter
            let ciImage = CIImage(cgImage: cropped)
            let blurRadius: Double = max(5, Double(blockSize) * 1.5)
            guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(blurRadius, forKey: kCIInputRadiusKey)
            guard let output = filter.outputImage else { return nil }
            let context = CIContext()
            let extent = output.extent
            guard let blurredCG = context.createCGImage(output, from: extent) else { return nil }
            result = NSImage(cgImage: blurredCG, size: r.size)
        }

        if let result = result {
            mosaicImageCache[shape.id] = result
        }
        return result
    }

    private func shapeHitTest(_ shape: AnnotationShape, at p: CGPoint) -> Bool {
        guard shape.points.count >= 2 else {
            if shape.points.count == 1 {
                return abs(p.x - shape.points[0].x) < 20 && abs(p.y - shape.points[0].y) < 20
            }
            return false
        }
        let p1 = shape.points[0]
        let p2 = shape.points[1]
        switch shape.tool {
        case .rect, .highlight, .mosaic:
            let minX = min(p1.x, p2.x), maxX = max(p1.x, p2.x)
            let minY = min(p1.y, p2.y), maxY = max(p1.y, p2.y)
            return p.x >= minX - 4 && p.x <= maxX + 4 && p.y >= minY - 4 && p.y <= maxY + 4
        case .ellipse:
            let cx = (p1.x + p2.x) / 2, cy = (p1.y + p2.y) / 2
            let rx = abs(p2.x - p1.x) / 2 + 4, ry = abs(p2.y - p1.y) / 2 + 4
            let dx = (p.x - cx) / rx, dy = (p.y - cy) / ry
            return dx * dx + dy * dy <= 1
        case .line, .arrow:
            return distanceToSegment(p, p1, p2) < 8
        case .pencil:
            for i in 0..<shape.points.count - 1 {
                if distanceToSegment(p, shape.points[i], shape.points[i + 1]) < 8 {
                    return true
                }
            }
            return false
        default:
            return false
        }
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: - Dim Overlay

    private var dimOverlay: some View {
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .mask(
                Rectangle()
                    .frame(width: frame.width, height: frame.height)
                    .overlay(
                        Rectangle()
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                            .blendMode(.destinationOut)
                    )
            )
    }

    // MARK: - Selection Border

    private var selectionBorder: some View {
        ZStack {
            Rectangle()
                .stroke(Color(red: 0.2, green: 0.6, blue: 1.0), lineWidth: 1)
                .frame(width: selectionRect.width, height: selectionRect.height)
                .position(x: selectionRect.midX, y: selectionRect.midY)

            if isSelectionDone {
                resizeHandles
            }

            // Show coordinates while dragging selection
            if isDragging && !isSelectionDone && selectionRect.width > 0 {
                Text("\(Int(selectionRect.width))x\(Int(selectionRect.height))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.85))
                    .cornerRadius(3)
                    .position(x: selectionRect.maxX - 30, y: selectionRect.minY + 12)
                    .allowsHitTesting(false)
            }
        }
    }

    private var resizeHandles: some View {
        ForEach(0..<8, id: \.self) { i in
            let pos = handlePosition(i)
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color(red: 0.2, green: 0.6, blue: 1.0), lineWidth: 1))
                .frame(width: handleSize, height: handleSize)
                .position(pos)
        }
    }

    private func handlePosition(_ index: Int) -> CGPoint {
        let r = selectionRect
        switch index {
        case 0: return CGPoint(x: r.minX, y: r.minY)
        case 1: return CGPoint(x: r.midX, y: r.minY)
        case 2: return CGPoint(x: r.maxX, y: r.minY)
        case 3: return CGPoint(x: r.maxX, y: r.midY)
        case 4: return CGPoint(x: r.maxX, y: r.maxY)
        case 5: return CGPoint(x: r.midX, y: r.maxY)
        case 6: return CGPoint(x: r.minX, y: r.maxY)
        case 7: return CGPoint(x: r.minX, y: r.midY)
        default: return .zero
        }
    }

    // MARK: - Annotation Canvas

    private var annotationCanvas: some View {
        Canvas { ctx, size in
            for shape in shapes {
                drawShapeInCanvas(ctx, shape, size: size)
            }
            if isDrawing && !currentPoints.isEmpty {
                let previewShape = AnnotationShape(
                    tool: currentTool,
                    points: currentPoints,
                    color: currentColor,
                    lineWidth: currentLineWidth,
                    text: "",
                    number: numberCounter,
                    arrowStyle: arrowStyle,
                    mosaicStyle: mosaicStyle
                )
                drawShapeInCanvas(ctx, previewShape, size: size)
            }
        }
        .frame(width: selectionRect.width, height: selectionRect.height)
        .position(x: selectionRect.midX, y: selectionRect.midY)
        .allowsHitTesting(false)
    }

    private func handleAnnotationDraw(_ value: DragGesture.Value) {
        guard currentTool != .move else { return }
        guard isInSelection(value.location) else { return }
        let localX = value.location.x - selectionRect.minX
        let localY = value.location.y - selectionRect.minY
        if !isDrawing {
            isDrawing = true
            dragStart = CGPoint(x: localX, y: localY)
            currentPoints = [CGPoint(x: localX, y: localY)]
        }
        if currentTool == .pencil || currentTool == .highlight {
            currentPoints.append(CGPoint(x: localX, y: localY))
        } else {
            currentPoints = [dragStart, CGPoint(x: localX, y: localY)]
        }
    }

    private func commitTextInput() {
        if showTextInput, let pos = textPosition, !textInput.isEmpty {
            if let editId = editingTextShapeId,
               let idx = shapes.firstIndex(where: { $0.id == editId }) {
                shapes[idx].text = textInput
                shapes[idx].points = [pos]
                shapes[idx].color = currentColor
                shapes[idx].fontSize = currentFontSize
            } else {
                shapes.append(AnnotationShape(
                    tool: .text,
                    points: [pos],
                    color: currentColor,
                    lineWidth: currentLineWidth,
                    text: textInput,
                    number: 0,
                    fontSize: currentFontSize
                ))
            }
        } else if let editId = editingTextShapeId {
            shapes.removeAll { $0.id == editId }
        }
        textInput = ""
        showTextInput = false
        textPosition = nil
        editingTextShapeId = nil
    }

    private func startEditText(_ shape: AnnotationShape) {
        editingTextShapeId = shape.id
        textInput = shape.text
        textPosition = shape.points.first
        showTextInput = true
        hoveredTextShapeId = nil
    }

    private func handleAnnotationEnd() {
        guard currentTool != .move else { return }
        if currentTool == .text {
            // Only create new text input if none is currently showing
            if !showTextInput {
                textInput = ""
                textPosition = dragStart
                showTextInput = true
            }
            isDrawing = false
            currentPoints = []
        } else if currentTool == .number {
            shapes.append(AnnotationShape(
                tool: .number,
                points: [dragStart],
                color: currentColor,
                lineWidth: currentLineWidth,
                text: "",
                number: numberCounter
            ))
            numberCounter += 1
        } else if currentTool == .eraser {
            eraseAt(point: dragStart)
        } else if currentPoints.count >= 2 {
            shapes.append(AnnotationShape(
                tool: currentTool,
                points: currentPoints,
                color: currentColor,
                lineWidth: currentLineWidth,
                text: "",
                number: 0,
                arrowStyle: arrowStyle,
                mosaicStyle: mosaicStyle
            ))
        }
        isDrawing = false
        currentPoints = []
        redoStack = []
    }

    // MARK: - Size Label

    private var selectionSizeLabel: some View {
        Text("\(Int(selectionRect.width)) × \(Int(selectionRect.height))")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
            .foregroundColor(.white)
            .position(
                x: selectionRect.maxX - 30,
                y: selectionRect.minY + 14
            )
    }

    // MARK: - Toolbar

    private func isPointInToolbar(_ point: CGPoint) -> Bool {
        let pos = toolbarPosition
        let tbWidth: CGFloat = 560
        let tbHeight: CGFloat = currentTool != .move ? 90 : 50
        return point.x >= pos.x - tbWidth / 2 && point.x <= pos.x + tbWidth / 2 &&
               point.y >= pos.y - tbHeight / 2 && point.y <= pos.y + tbHeight / 2
    }

    private var toolbarPosition: CGPoint {
        let screenHeight = frame.height
        let screenWidth = frame.width
        let toolbarHeight: CGFloat = currentTool != .move ? 90 : 50
        let toolbarWidth: CGFloat = 560
        let margin: CGFloat = 10
        var x = selectionRect.midX
        var y: CGFloat

        // Prefer below selection; if not enough space, put above
        let spaceBelow = screenHeight - selectionRect.maxY
        let spaceAbove = selectionRect.minY
        
        if spaceBelow >= toolbarHeight + margin {
            y = selectionRect.maxY + toolbarHeight / 2 + margin
        } else if spaceAbove >= toolbarHeight + margin {
            y = selectionRect.minY - toolbarHeight / 2 - margin
        } else {
            // Not enough space above or below: pick the side with more room
            if spaceBelow >= spaceAbove {
                y = screenHeight - toolbarHeight / 2 - margin
            } else {
                y = toolbarHeight / 2 + margin
            }
        }

        // Clamp X to keep toolbar fully visible
        x = max(toolbarWidth / 2 + margin, min(x, screenWidth - toolbarWidth / 2 - margin))
        // Clamp Y to keep toolbar fully visible
        y = max(toolbarHeight / 2 + margin, min(y, screenHeight - toolbarHeight / 2 - margin))
        return CGPoint(x: x, y: y)
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    toolButton(tool)
                }

                Divider().frame(height: 24).padding(.horizontal, 2)

                iconButton("arrow.uturn.backward", action: undo)
                iconButton("arrow.uturn.forward", action: redo)

                Divider().frame(height: 24).padding(.horizontal, 2)

                iconButton("xmark", color: .red, action: onCancel)
                iconButton("checkmark", color: .green, action: confirmCapture)
                iconButton("square.and.arrow.down", color: .blue, action: saveCapture)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Tool-specific properties panel
            if currentTool != .move {
                toolPropertiesPanel
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    private var toolPropertiesPanel: some View {
        HStack(spacing: 8) {
            Text(currentTool.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Divider().frame(height: 16)

            // Color picker
            ForEach([Color.red, .orange, .yellow, .green, .blue, .purple, .white, .black], id: \.self) { c in
                colorButton(c)
            }

            // Tool-specific controls
            if currentTool == .text {
                Divider().frame(height: 16)
                HStack(spacing: 4) {
                    Text("字号")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: Binding(
                        get: { currentFontSize },
                        set: { setFontSize($0) }
                    ), in: 10...48, step: 1)
                    .frame(width: 80)
                    Text("\(Int(currentFontSize))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 24)
                }
            } else if currentTool != .eraser && currentTool != .number && currentTool != .mosaic {
                Divider().frame(height: 16)
                HStack(spacing: 4) {
                    Text("粗细")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: Binding(
                        get: { currentLineWidth },
                        set: { setLineWidth($0) }
                    ), in: 1...20, step: 1)
                    .frame(width: 80)
                    Text("\(Int(currentLineWidth))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 24)
                }
            }

            // Arrow style selector
            if currentTool == .arrow {
                Divider().frame(height: 16)
                HStack(spacing: 4) {
                    ForEach(ArrowStyle.allCases, id: \.self) { style in
                        Button(action: { arrowStyle = style }) {
                            Text(style == .solid ? "实心" : style == .hollow ? "空心" : "细线")
                                .font(.system(size: 10))
                                .foregroundColor(arrowStyle == style ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(arrowStyle == style ? Color.white : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Mosaic style selector
            if currentTool == .mosaic {
                Divider().frame(height: 16)
                HStack(spacing: 4) {
                    ForEach(MosaicStyle.allCases, id: \.self) { style in
                        Button(action: { mosaicStyle = style }) {
                            Text(style == .pixelate ? "像素" : "模糊")
                                .font(.system(size: 10))
                                .foregroundColor(mosaicStyle == style ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(mosaicStyle == style ? Color.white : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = currentTool == tool
        return Button(action: { currentTool = tool }) {
            Image(systemName: tool.icon)
                .font(.system(size: 15))
                .foregroundColor(isSelected ? .black : .white.opacity(0.85))
                .padding(8)
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.white : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func colorButton(_ c: Color) -> some View {
        let isSelected = currentColor == c
        return Circle()
            .fill(c)
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.white : Color.gray.opacity(0.4), lineWidth: isSelected ? 3 : 1)
                    .frame(width: 24, height: 24)
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(c == .white || c == .yellow ? .black : .white)
                    .opacity(isSelected ? 1 : 0)
            )
            .padding(6)
            .contentShape(Circle().inset(by: -6))
            .onTapGesture { setColor(c) }
    }

    private func iconButton(_ icon: String, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.35))
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Window Highlight

    private var windowHighlight: some View {
        Group {
            if hoveredWindowID != 0 {
                Rectangle()
                    .stroke(Color(red: 0.2, green: 0.6, blue: 1.0), lineWidth: 2)
                    .background(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.15))
                    .frame(width: hoveredWindowSize.width, height: hoveredWindowSize.height)
                    .position(x: hoveredWindowCenter.x, y: hoveredWindowCenter.y)

                // Window coordinate label (top-left corner)
                let topLeftX = hoveredWindowCenter.x - hoveredWindowSize.width / 2
                let topLeftY = hoveredWindowCenter.y - hoveredWindowSize.height / 2
                Text("(\(Int(topLeftX)), \(Int(topLeftY))) \(Int(hoveredWindowSize.width))x\(Int(hoveredWindowSize.height))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.85))
                    .cornerRadius(3)
                    .position(
                        x: hoveredWindowCenter.x - hoveredWindowSize.width / 2,
                        y: hoveredWindowCenter.y - hoveredWindowSize.height / 2 - 12
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func updateHoveredWindow(at loc: CGPoint) {
        // 如果已经开始拖动，不再更新窗口吸附
        if isDraggingStarted {
            return
        }
        
        // isFlipped=false: loc is bottom-left origin, same as CG coordinates
        let cgX = frame.origin.x + loc.x
        let cgY = frame.origin.y + loc.y
        let cgPoint = CGPoint(x: cgX, y: cgY)

        guard let windowInfo = WindowDetector.findWindow(at: cgPoint, excludeWindowID: getCurrentWindowID()) else {
            hoveredWindowID = 0
            hoveredWindowRect = .zero
            hoveredWindowCenter = .zero
            hoveredWindowSize = .zero
            return
        }

        // windowInfo.rect is in global CG coordinates (bottom-left origin)
        let winRect = windowInfo.rect
        
        // Convert from global CG (bottom-left origin) to view coords (top-left origin)
        //
        // Screen's frame.origin is the screen's bottom-left corner in global CG coords
        // Screen's frame.height is the screen height
        //
        // Step 1: Convert window rect to screen-relative coords (still bottom-left origin)
        //   relativeX = winRect.minX - frame.origin.x
        //   relativeY = winRect.minY - frame.origin.y
        //
        // Step 2: Flip Y axis to convert from bottom-left to top-left origin
        //   In bottom-left: window bottom is at relativeY, top is at relativeY + height
        //   In top-left: window top is at (screenHeight - (relativeY + height))
        //              = screenHeight - relativeY - height
        //              = screenHeight - (winRect.minY - frame.origin.y) - height
        //              = screenHeight - winRect.minY + frame.origin.y - height
        //              = screenHeight - winRect.maxY + frame.origin.y
        //
        // isFlipped=false: view coords are bottom-left origin, same as CG
        // No Y flip needed
        let cgCenterX = winRect.midX
        let cgCenterY = winRect.midY
        let viewCenterX = cgCenterX - frame.origin.x
        let viewCenterY = cgCenterY - frame.origin.y
        
        hoveredWindowCenter = CGPoint(x: viewCenterX, y: viewCenterY)
        hoveredWindowSize = CGSize(width: winRect.width, height: winRect.height)
        
        // Also store as NSRect (bottom-left origin, same as CG, no flip)
        let viewX = winRect.minX - frame.origin.x
        let viewY = winRect.minY - frame.origin.y
        hoveredWindowRect = NSRect(
            x: viewX,
            y: viewY,
            width: winRect.width,
            height: winRect.height
        )
        hoveredWindowID = windowInfo.windowID
        
        // Save last hovered window for click detection
        lastHoveredWindowRect = hoveredWindowRect
        lastHoveredWindowID = hoveredWindowID
    }

    private func getCurrentWindowID() -> CGWindowID {
        // Get the overlay window's window number to exclude it from detection
        for window in NSApp.windows {
            if window.level == .screenSaver {
                return CGWindowID(window.windowNumber)
            }
        }
        return 0
    }

    // MARK: - Hit Test

    private func findTextShape(at point: CGPoint) -> AnnotationShape? {
        // point is in view coordinates, shapes are in selection-local coordinates
        let localX = point.x - selectionRect.minX
        let localY = point.y - selectionRect.minY
        for shape in shapes {
            if shape.tool == .text, let bbox = shape.textBoundingBox() {
                let expanded = bbox.insetBy(dx: -4, dy: -4)
                if expanded.contains(CGPoint(x: localX, y: localY)) {
                    return shape
                }
            }
        }
        return nil
    }

    private func isOnTextBorder(_ point: CGPoint, shape: AnnotationShape) -> Bool {
        let localX = point.x - selectionRect.minX
        let localY = point.y - selectionRect.minY
        guard let bbox = shape.textBoundingBox() else { return false }
        let expanded = bbox.insetBy(dx: -4, dy: -4)
        let inner = bbox.insetBy(dx: 4, dy: 4)
        return expanded.contains(CGPoint(x: localX, y: localY)) &&
               !inner.contains(CGPoint(x: localX, y: localY))
    }

    private func hitTest(_ point: CGPoint) -> SelectionDragMode {
        let r = selectionRect
        let onLeft = abs(point.x - r.minX) < edgeTolerance
        let onRight = abs(point.x - r.maxX) < edgeTolerance
        let onTop = abs(point.y - r.maxY) < edgeTolerance
        let onBottom = abs(point.y - r.minY) < edgeTolerance

        if onTop && onLeft { return .resizeTopLeft }
        if onTop && onRight { return .resizeTopRight }
        if onBottom && onLeft { return .resizeBottomLeft }
        if onBottom && onRight { return .resizeBottomRight }
        if onTop { return .resizeTop }
        if onBottom { return .resizeBottom }
        if onLeft { return .resizeLeft }
        if onRight { return .resizeRight }
        // Inside selection: move if current tool is move, otherwise annotate
        if r.contains(point) && currentTool == .move {
            return .move
        }
        return .none
    }

    private func applyDrag(_ location: CGPoint) {
        let dx = location.x - dragStartLocation.x
        let dy = location.y - dragStartLocation.y
        var r = dragStartRect

        switch dragMode {
        case .move:
            r.origin.x += dx
            r.origin.y += dy
        case .resizeLeft:
            let newMinX = dragStartRect.minX + dx
            if dragStartRect.maxX - newMinX > 20 {
                r = NSRect(x: newMinX, y: r.minY, width: dragStartRect.maxX - newMinX, height: r.height)
            }
        case .resizeRight:
            let newMaxX = dragStartRect.maxX + dx
            if newMaxX - dragStartRect.minX > 20 {
                r = NSRect(x: r.minX, y: r.minY, width: newMaxX - dragStartRect.minX, height: r.height)
            }
        case .resizeTop:
            let newMaxY = dragStartRect.maxY + dy
            if newMaxY - dragStartRect.minY > 20 {
                r = NSRect(x: r.minX, y: r.minY, width: r.width, height: newMaxY - dragStartRect.minY)
            }
        case .resizeBottom:
            let newMinY = dragStartRect.minY + dy
            if dragStartRect.maxY - newMinY > 20 {
                r = NSRect(x: r.minX, y: newMinY, width: r.width, height: dragStartRect.maxY - newMinY)
            }
        case .resizeTopLeft:
            let newMinX = dragStartRect.minX + dx
            let newMaxY = dragStartRect.maxY + dy
            if dragStartRect.maxX - newMinX > 20 && newMaxY - dragStartRect.minY > 20 {
                r = NSRect(x: newMinX, y: r.minY, width: dragStartRect.maxX - newMinX, height: newMaxY - dragStartRect.minY)
            }
        case .resizeTopRight:
            let newMaxX = dragStartRect.maxX + dx
            let newMaxY = dragStartRect.maxY + dy
            if newMaxX - dragStartRect.minX > 20 && newMaxY - dragStartRect.minY > 20 {
                r = NSRect(x: r.minX, y: r.minY, width: newMaxX - dragStartRect.minX, height: newMaxY - dragStartRect.minY)
            }
        case .resizeBottomLeft:
            let newMinX = dragStartRect.minX + dx
            let newMinY = dragStartRect.minY + dy
            if dragStartRect.maxX - newMinX > 20 && dragStartRect.maxY - newMinY > 20 {
                r = NSRect(x: newMinX, y: newMinY, width: dragStartRect.maxX - newMinX, height: dragStartRect.maxY - newMinY)
            }
        case .resizeBottomRight:
            let newMaxX = dragStartRect.maxX + dx
            let newMinY = dragStartRect.minY + dy
            if newMaxX - dragStartRect.minX > 20 && dragStartRect.maxY - newMinY > 20 {
                r = NSRect(x: r.minX, y: newMinY, width: newMaxX - dragStartRect.minX, height: dragStartRect.maxY - newMinY)
            }
        case .none:
            break
        }

        r.origin.x = max(0, min(r.origin.x, frame.width - r.width))
        r.origin.y = max(0, min(r.origin.y, frame.height - r.height))
        selectionRect = r
    }

    // MARK: - Helpers

    private var hintText: String {
        switch mode {
        case .area: return "拖动选择截图区域，或单击吸附窗口"
        case .scroll: return "拖动选择滚动截图区域"
        case .record: return "拖动选择录屏区域"
        case .ocr: return "拖动选择 OCR 识别区域"
        case .window: return "拖动选择截图区域，或单击吸附窗口"
        }
    }

    private func isInSelection(_ point: CGPoint) -> Bool {
        point.x >= selectionRect.minX && point.x <= selectionRect.maxX &&
        point.y >= selectionRect.minY && point.y <= selectionRect.maxY
    }

    private func updateSelectionRect() {
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let w = abs(currentPoint.x - startPoint.x)
        let h = abs(currentPoint.y - startPoint.y)
        selectionRect = NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Confirm Capture

    private func confirmCapture() {
        // For window snap mode, use captured window image; for area mode, use screen capture
        let fullImage: NSImage? = isWindowCaptureMode ? capturedWindowImage : screenCapture
        
        guard let image = fullImage else {
            NSLog("[TPix] confirmCapture: image is nil!")
            onCancel()
            return
        }

        NSLog("[TPix] confirmCapture: selectionRect=\(selectionRect) image.size=\(image.size)")

        // For window snap mode, the image IS the window screenshot, no need to crop
        // For area mode, crop selection from full screen image
        let finalImage: NSImage
        if isWindowCaptureMode {
            if shapes.isEmpty {
                finalImage = image
            } else {
                finalImage = renderAnnotations(on: image)
            }
        } else {
            let croppedImage = cropFromFullImage(image, rect: selectionRect)
            if shapes.isEmpty {
                finalImage = croppedImage
            } else {
                finalImage = renderAnnotations(on: croppedImage)
            }
        }

        NSLog("[TPix] confirmCapture: calling onComplete, finalImage.size=\(finalImage.size)")
        onComplete(finalImage, selectionRect)
    }

    private func generateFinalImage() -> NSImage? {
        let fullImage: NSImage? = isWindowCaptureMode ? capturedWindowImage : screenCapture
        guard let image = fullImage else { return nil }

        if isWindowCaptureMode {
            return shapes.isEmpty ? image : renderAnnotations(on: image)
        } else {
            let croppedImage = cropFromFullImage(image, rect: selectionRect)
            return shapes.isEmpty ? croppedImage : renderAnnotations(on: croppedImage)
        }
    }

    private func saveCapture() {
        guard let finalImage = generateFinalImage() else { return }

        // Hide overlay window so it doesn't block the save panel
        let overlayWindow = NSApp.windows.first { $0.level == .screenSaver }
        overlayWindow?.orderOut(nil)

        let panel = NSSavePanel()
        panel.title = "保存截图"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let s = SettingsStore.shared.settings
        panel.nameFieldStringValue = "TPix_\(formatter.string(from: Date()))"
        panel.allowedContentTypes = s.imageFormat == "png"
            ? [.png]
            : [.jpeg]
        panel.canCreateDirectories = true
        panel.level = .floating

        let result = panel.runModal()

        if result == .OK, let url = panel.url {
            if s.imageFormat == "png" {
                if let tiff = finalImage.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                }
            } else {
                if let tiff = finalImage.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                    try? jpg.write(to: url)
                }
            }
            onComplete(nil, nil)
        } else {
            // User cancelled save, show overlay again
            overlayWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func cropFromFullImage(_ fullImage: NSImage, rect: NSRect) -> NSImage {
        guard let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fullImage
        }
        let scale = fullImage.size.width == 0 ? 1 : CGFloat(cgImage.width) / fullImage.size.width
        // Both selectionRect and cgImage.cropping(to:) use top-left origin
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else {
            return fullImage
        }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    private func renderAnnotations(on image: NSImage) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()

        image.draw(in: NSRect(origin: .zero, size: size))

        let ctx = NSGraphicsContext.current!
        let cgCtx = ctx.cgContext
        cgCtx.saveGState()

        for shape in shapes {
            drawShapeInCGContext(cgCtx, shape, size: size)
        }

        cgCtx.restoreGState()
        result.unlockFocus()
        return result
    }

    private func captureWindow(_ windowID: CGWindowID, rect: NSRect) {
        NSLog("[TPix] captureWindow: windowID=\(windowID), viewRect=\(rect)")

        // Get the window's bounds in global CG coordinate
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], windowID) as? [[String: Any]],
              let info = windowList.first,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
              let ownerName = info[kCGWindowOwnerName as String] as? String else {
            NSLog("[TPix] captureWindow: failed to get window bounds")
            onCancel()
            return
        }

        let winBounds = CGRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )
        NSLog("[TPix] captureWindow: window='\(ownerName)' winBounds=\(winBounds)")

        // Method 1: Use CGWindowListCreateImage with the window's actual bounds
        guard let cgImage = CGWindowListCreateImage(
            winBounds,
            .optionOnScreenOnly,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            NSLog("[TPix] captureWindow: CGWindowListCreateImage returned nil, trying fallback...")
            
            // Method 2: Fallback - capture using window layer
            guard let cgImage2 = CGWindowListCreateImage(
                .null,
                .optionOnScreenOnly,
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            ) else {
                NSLog("[TPix] captureWindow: fallback also failed")
                onCancel()
                return
            }
            let image = NSImage(cgImage: cgImage2, size: NSSize(width: cgImage2.width, height: cgImage2.height))
            NSLog("[TPix] captureWindow: fallback image size=\(image.size)")
            onComplete(image, nil)
            return
        }

        NSLog("[TPix] captureWindow: cgImage size=\(cgImage.width)x\(cgImage.height)")
        
        // Use the actual cgImage size
        let actualSize = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: actualSize)
        NSLog("[TPix] captureWindow: final image size=\(image.size)")
        onComplete(image, nil)
    }
    
    private func captureWindowFromInfo(_ windowInfo: WindowInfo) {
        NSLog("[TPix] captureWindowFromInfo: windowID=\(windowInfo.windowID), title=\(windowInfo.title ?? "nil"), owner=\(windowInfo.ownerName ?? "nil")")
        
        // Use ScreenCaptureKit for macOS 12.0+
        // This is more reliable than CGWindowListCreateImage for unsigned apps
        Task { @MainActor in
            do {
                // Get the content to capture
                let content = try await SCShareableContent.current
                
                // Find the matching window
                guard let scWindow = content.windows.first(where: { $0.windowID == windowInfo.windowID }) else {
                    NSLog("[TPix] captureWindowFromInfo: Window not found in SCShareableContent")
                    onCancel()
                    return
                }
                
                NSLog("[TPix] captureWindowFromInfo: Found SCWindow, description=\(scWindow.description)")
                
                // Capture the window
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.width = Int(scWindow.frame.width) * 2  // Retina
                config.height = Int(scWindow.frame.height) * 2
                config.showsCursor = false
                config.scalesToFit = false
                
                let screenshot = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                
                if let cgImage = screenshot as? CGImage {
                    NSLog("[TPix] captureWindowFromInfo: success, size=\(cgImage.width)x\(cgImage.height)")
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
                    
                    // Enter edit mode instead of completing immediately
                    await MainActor.run {
                        enterWindowEditMode(image: image, windowInfo: windowInfo)
                    }
                } else {
                    NSLog("[TPix] captureWindowFromInfo: screenshot is nil or wrong type")
                    onCancel()
                }
            } catch {
                NSLog("[TPix] captureWindowFromInfo: ScreenCaptureKit error: \(error)")
                // Fallback to CGWindowListCreateImage
                fallbackCapture(windowInfo)
            }
        }
    }
    
    private func enterWindowEditMode(image: NSImage, windowInfo: WindowInfo) {
        NSLog("[TPix] enterWindowEditMode: image.size=\(image.size), windowRect=\(windowInfo.rect)")
        
        // Store captured window image
        capturedWindowImage = image
        isWindowCaptureMode = true
        
        // Set selection rect to window position (in view coords, bottom-left origin)
        let winRect = windowInfo.rect
        let viewX = winRect.minX - frame.origin.x
        let viewY = winRect.minY - frame.origin.y
        selectionRect = NSRect(x: viewX, y: viewY, width: winRect.width, height: winRect.height)
        
        // Clear window highlight
        hoveredWindowID = 0
        hoveredWindowRect = .zero
        hoveredWindowCenter = .zero
        hoveredWindowSize = .zero
        
        // Enter edit mode
        isSelectionDone = true
        isDragging = false
        isDraggingStarted = false
    }
    
    private func fallbackCapture(_ windowInfo: WindowInfo) {
        NSLog("[TPix] fallbackCapture: Using CGWindowListCreateImage as fallback")
        
        guard let cgImage = CGWindowListCreateImage(
            .null,
            [.optionOnScreenOnly, .excludeDesktopElements],
            windowInfo.windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            NSLog("[TPix] fallbackCapture: also failed!")
            onCancel()
            return
        }
        
        // Check if it's fullscreen (fallback failed)
        if cgImage.width > 5000 {
            NSLog("[TPix] fallbackCapture: Still getting fullscreen image, this is a known issue with unsigned apps")
        }
        
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
        enterWindowEditMode(image: image, windowInfo: windowInfo)
    }

    // MARK: - Annotation Drawing

    private func undo() {
        if let last = shapes.popLast() {
            redoStack.append(last)
            mosaicImageCache.removeValue(forKey: last.id)
            if last.tool == .number { numberCounter = max(1, numberCounter - 1) }
        }
    }

    private func redo() {
        if let shape = redoStack.popLast() {
            shapes.append(shape)
        }
    }

    private func eraseAt(point: CGPoint) {
        shapes.removeAll { shape in
            let hit = shape.points.contains { p in
                distance(p, point) < 20
            }
            if hit { mosaicImageCache.removeValue(forKey: shape.id) }
            return hit
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    private func drawShapeInCanvas(_ ctx: GraphicsContext, _ shape: AnnotationShape, size: CGSize) {
        let color = shape.color.opacity(shape.opacity)

        switch shape.tool {
        case .rect:
            guard shape.points.count >= 2 else { return }
            let r = rectFrom(shape.points)
            ctx.stroke(Path(r), with: .color(color), lineWidth: shape.lineWidth)
        case .ellipse:
            guard shape.points.count >= 2 else { return }
            let r = rectFrom(shape.points)
            ctx.stroke(Path(ellipseIn: r), with: .color(color), lineWidth: shape.lineWidth)
        case .arrow:
            guard shape.points.count >= 2 else { return }
            let p0 = shape.points[0], p1 = shape.points[1]
            let angle = atan2(p1.y - p0.y, p1.x - p0.x)
            let len: CGFloat = max(10, shape.lineWidth * 4)
            switch shape.arrowStyle {
            case .solid, .hollow:
                var path = Path()
                path.move(to: p0)
                path.addLine(to: p1)
                ctx.stroke(path, with: .color(color), lineWidth: shape.lineWidth)
                // Arrow head
                var head = Path()
                head.move(to: p1)
                head.addLine(to: CGPoint(x: p1.x - len * cos(angle - .pi / 6), y: p1.y - len * sin(angle - .pi / 6)))
                head.addLine(to: CGPoint(x: p1.x - len * cos(angle + .pi / 6), y: p1.y - len * sin(angle + .pi / 6)))
                head.closeSubpath()
                if shape.arrowStyle == .solid {
                    ctx.fill(head, with: .color(color))
                } else {
                    ctx.stroke(head, with: .color(color), lineWidth: shape.lineWidth)
                }
            case .thin:
                var path = Path()
                path.move(to: p0)
                path.addLine(to: p1)
                let halfLen = len * 0.7
                path.addLine(to: CGPoint(x: p1.x - halfLen * cos(angle - .pi / 6), y: p1.y - halfLen * sin(angle - .pi / 6)))
                path.move(to: p1)
                path.addLine(to: CGPoint(x: p1.x - halfLen * cos(angle + .pi / 6), y: p1.y - halfLen * sin(angle + .pi / 6)))
                ctx.stroke(path, with: .color(color), lineWidth: shape.lineWidth)
            }
        case .line:
            guard shape.points.count >= 2 else { return }
            var path = Path()
            path.move(to: shape.points[0])
            path.addLine(to: shape.points[1])
            ctx.stroke(path, with: .color(color), lineWidth: shape.lineWidth)
        case .pencil:
            guard shape.points.count >= 2 else { return }
            var path = Path()
            path.move(to: shape.points[0])
            for p in shape.points.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(color), lineWidth: shape.lineWidth)
        case .highlight:
            guard shape.points.count >= 2 else { return }
            var path = Path()
            path.move(to: shape.points[0])
            for p in shape.points.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(color.opacity(0.3)), lineWidth: shape.lineWidth * 3)
        case .text:
            guard let p = shape.points.first else { return }
            ctx.draw(Text(shape.text).font(.system(size: shape.fontSize)).foregroundColor(color), at: p, anchor: .topLeading)
        case .mosaic:
            guard shape.points.count >= 2 else { return }
            let r = rectFrom(shape.points)
            if let mosaicImg = getMosaicImage(for: shape),
               let cgImg = mosaicImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let img = Image(decorative: cgImg, scale: 1.0)
                ctx.draw(img, in: r)
            } else {
                ctx.fill(Path(r), with: .color(Color.gray.opacity(0.3)))
            }
        case .number:
            guard let p = shape.points.first else { return }
            let r = CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)
            ctx.fill(Path(ellipseIn: r), with: .color(color))
            ctx.draw(Text("\(shape.number)").font(.system(size: 14, weight: .bold)).foregroundColor(.white), at: p)
        case .eraser, .move:
            break
        }
    }

    private func rectFrom(_ points: [CGPoint]) -> CGRect {
        guard points.count >= 2 else { return .zero }
        let x = min(points[0].x, points[1].x)
        let y = min(points[0].y, points[1].y)
        let w = abs(points[1].x - points[0].x)
        let h = abs(points[1].y - points[0].y)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func drawShapeInCGContext(_ ctx: CGContext, _ shape: AnnotationShape, size: CGSize) {
        let nsColor = NSColor(shape.color).withAlphaComponent(shape.opacity)
        let cgColor = nsColor.cgColor
        ctx.setStrokeColor(cgColor)
        ctx.setFillColor(cgColor)
        ctx.setLineWidth(shape.lineWidth)

        func flipY(_ p: CGPoint) -> CGPoint {
            return CGPoint(x: p.x, y: size.height - p.y)
        }

        switch shape.tool {
        case .rect:
            guard shape.points.count >= 2 else { return }
            let r = rectFrom(shape.points)
            let flippedRect = CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
            ctx.stroke(flippedRect)
        case .ellipse:
            guard shape.points.count >= 2 else { return }
            let r = rectFrom(shape.points)
            let flippedRect = CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
            ctx.strokeEllipse(in: flippedRect)
        case .arrow:
            guard shape.points.count >= 2 else { return }
            let from = flipY(shape.points[0])
            let to = flipY(shape.points[1])
            let angle = atan2(to.y - from.y, to.x - from.x)
            let len: CGFloat = max(10, shape.lineWidth * 4)
            switch shape.arrowStyle {
            case .solid, .hollow:
                ctx.move(to: from)
                ctx.addLine(to: to)
                ctx.strokePath()
                ctx.move(to: to)
                ctx.addLine(to: CGPoint(x: to.x - len * cos(angle - .pi / 6), y: to.y - len * sin(angle - .pi / 6)))
                ctx.addLine(to: CGPoint(x: to.x - len * cos(angle + .pi / 6), y: to.y - len * sin(angle + .pi / 6)))
                ctx.closePath()
                if shape.arrowStyle == .solid {
                    ctx.fillPath()
                } else {
                    ctx.strokePath()
                }
            case .thin:
                let halfLen = len * 0.7
                ctx.move(to: from)
                ctx.addLine(to: to)
                ctx.addLine(to: CGPoint(x: to.x - halfLen * cos(angle - .pi / 6), y: to.y - halfLen * sin(angle - .pi / 6)))
                ctx.move(to: to)
                ctx.addLine(to: CGPoint(x: to.x - halfLen * cos(angle + .pi / 6), y: to.y - halfLen * sin(angle + .pi / 6)))
                ctx.strokePath()
            }
        case .line:
            guard shape.points.count >= 2 else { return }
            ctx.move(to: flipY(shape.points[0]))
            ctx.addLine(to: flipY(shape.points[1]))
            ctx.strokePath()
        case .pencil:
            guard shape.points.count >= 2 else { return }
            ctx.move(to: flipY(shape.points[0]))
            for p in shape.points.dropFirst() { ctx.addLine(to: flipY(p)) }
            ctx.strokePath()
        case .highlight:
            guard shape.points.count >= 2 else { return }
            let highlightColor = nsColor.withAlphaComponent(0.3)
            ctx.setStrokeColor(highlightColor.cgColor)
            ctx.setLineWidth(shape.lineWidth * 3)
            ctx.move(to: flipY(shape.points[0]))
            for p in shape.points.dropFirst() { ctx.addLine(to: flipY(p)) }
            ctx.strokePath()
        case .text:
            guard let p = shape.points.first else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: shape.fontSize),
                .foregroundColor: nsColor,
            ]
            let flippedPoint = CGPoint(x: p.x, y: size.height - p.y)
            (shape.text as NSString).draw(at: flippedPoint, withAttributes: attrs)
        case .mosaic:
            guard shape.points.count >= 2 else { return }
            let r = rectFrom(shape.points)
            let flippedRect = CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height)
            if let mosaicImg = getMosaicImage(for: shape),
               let cgImg = mosaicImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.saveGState()
                ctx.translateBy(x: 0, y: flippedRect.minY + flippedRect.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(cgImg, in: CGRect(x: flippedRect.minX, y: 0, width: flippedRect.width, height: flippedRect.height))
                ctx.restoreGState()
            } else {
                ctx.setFillColor(NSColor.gray.withAlphaComponent(0.3).cgColor)
                ctx.fill(flippedRect)
            }
        case .number:
            guard let p = shape.points.first else { return }
            let flippedPoint = flipY(p)
            let r = CGRect(x: flippedPoint.x - 12, y: flippedPoint.y - 12, width: 24, height: 24)
            ctx.fillEllipse(in: r)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.white,
            ]
            let str = "\(shape.number)" as NSString
            let textSize = str.size(withAttributes: attrs)
            str.draw(at: CGPoint(x: flippedPoint.x - textSize.width / 2, y: flippedPoint.y - textSize.height / 2), withAttributes: attrs)
        case .eraser, .move:
            break
        }
    }
}

// MARK: - Window Detector

struct WindowInfo {
    let windowID: CGWindowID
    let rect: NSRect
    let title: String?
    let ownerName: String?
}

enum WindowDetector {
    private static var cachedWindowList: [[String: Any]]? = nil
    private static var cacheTime: Date = .distantPast
    private static let cacheInterval: TimeInterval = 0.3
    
    static func findWindow(at cgPoint: CGPoint, excludeWindowID: CGWindowID = 0) -> WindowInfo? {
        let now = Date()
        if cachedWindowList == nil || now.timeIntervalSince(cacheTime) > cacheInterval {
            cachedWindowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
            cacheTime = now
        }
        
        guard let windowList = cachedWindowList else {
            return nil
        }

        for info in windowList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }

            // Skip our own app windows
            if let ownerName = info[kCGWindowOwnerName as String] as? String, ownerName == "TPix" {
                continue
            }

            // Skip excluded window
            if windowID == excludeWindowID {
                continue
            }

            // Skip windows with layer < 0 (menu bar, etc.) or non-normal layer
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 {
                continue
            }

            let winRect = NSRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            if winRect.width < 50 || winRect.height < 50 {
                continue
            }

            if winRect.contains(cgPoint) {
                let title = info[kCGWindowName as String] as? String
                let owner = info[kCGWindowOwnerName as String] as? String
                return WindowInfo(windowID: windowID, rect: winRect, title: title, ownerName: owner)
            }
        }
        return nil
    }
}

// MARK: - Magnifier

struct MagnifierView: View {
    let mouseLocation: CGPoint
    let screenImage: NSImage?
    let screenSize: NSSize

    private let magnifierSize: CGFloat = 140
    private let zoomFactor: CGFloat = 4
    private let offset: CGFloat = 20

    var body: some View {
        if let image = screenImage {
            let pos = magnifierPosition
            let sampleSize = magnifierSize / zoomFactor
            let cropRect = NSRect(
                x: mouseLocation.x - sampleSize / 2,
                y: mouseLocation.y - sampleSize / 2,
                width: sampleSize,
                height: sampleSize
            )

            let pixelColor = colorAtCenter(image: image, point: mouseLocation)

            ZStack {
                // Magnifier box
                VStack(spacing: 0) {
                    // Image area
                    ZStack {
                        Rectangle()
                            .fill(Color.black)

                        if let cropped = cropImage(image, rect: cropRect) {
                            Image(nsImage: cropped)
                                .resizable()
                                .frame(width: magnifierSize, height: magnifierSize)
                        }

                        // Crosshair in magnifier
                        CrosshairShape()
                            .stroke(Color.red, lineWidth: 1)
                            .frame(width: magnifierSize, height: magnifierSize)

                        // Center box highlight
                        Rectangle()
                            .stroke(Color.red, lineWidth: 2)
                            .frame(width: magnifierSize / zoomFactor, height: magnifierSize / zoomFactor)
                    }
                    .frame(width: magnifierSize, height: magnifierSize)
                    .clipped()

                    // Color info bar
                    if let c = pixelColor {
                        HStack(spacing: 6) {
                            // Color swatch
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: c.r, green: c.g, blue: c.b))
                                .frame(width: 14, height: 14)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.5), lineWidth: 0.5))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(hexString(c))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("(\(Int(mouseLocation.x)), \(Int(mouseLocation.y)))")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(width: magnifierSize)
                        .background(Color.black.opacity(0.9))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                )
                .cornerRadius(4)
            }
            .position(x: pos.x, y: pos.y)
        }
    }

    private struct PixelColor {
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
    }

    private func colorAtCenter(image: NSImage, point: CGPoint) -> PixelColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = image.size.width == 0 ? 1 : CGFloat(cgImage.width) / image.size.width
        let px = Int(point.x * scale)
        let py = Int(point.y * scale)

        let width = cgImage.width
        let height = cgImage.height

        guard px >= 0 && px < width && py >= 0 && py < height else {
            return nil
        }

        // Cache bitmapRep to avoid recreating every frame
        if MagnifierView.cachedBitmapRep == nil || MagnifierView.cachedCGImage !== cgImage {
            MagnifierView.cachedBitmapRep = NSBitmapImageRep(cgImage: cgImage)
            MagnifierView.cachedCGImage = cgImage
        }

        guard let bitmapRep = MagnifierView.cachedBitmapRep,
              let color = bitmapRep.colorAt(x: px, y: py) else {
            return nil
        }

        return PixelColor(
            r: color.redComponent,
            g: color.greenComponent,
            b: color.blueComponent
        )
    }

    private static var cachedBitmapRep: NSBitmapImageRep? = nil
    private static var cachedCGImage: CGImage? = nil

    private func hexString(_ c: PixelColor) -> String {
        String(format: "#%02X%02X%02X", Int(c.r*255), Int(c.g*255), Int(c.b*255))
    }

    private func cropImage(_ image: NSImage, rect: NSRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = image.size.width == 0 ? 1 : CGFloat(cgImage.width) / image.size.width
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    private var magnifierPosition: CGPoint {
        var x = mouseLocation.x + offset + magnifierSize / 2
        var y = mouseLocation.y + offset + magnifierSize / 2

        if x + magnifierSize / 2 > screenSize.width {
            x = mouseLocation.x - offset - magnifierSize / 2
        }
        if y + magnifierSize / 2 > screenSize.height {
            y = mouseLocation.y - offset - magnifierSize / 2
        }
        return CGPoint(x: x, y: y)
    }
}

struct CrosshairShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// Scroll wheel event interceptor
struct ScrollWheelInterceptor: NSViewRepresentable {
    let onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let v = ScrollWheelNSView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat, CGPoint) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let deltaY = event.scrollingDeltaY
        if deltaY != 0 {
            let loc = convert(event.locationInWindow, from: nil)
            onScroll?(deltaY, CGPoint(x: loc.x, y: loc.y))
        }
    }
}
