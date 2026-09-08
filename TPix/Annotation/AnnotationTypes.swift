import SwiftUI
import AppKit

enum AnnotationTool: String, CaseIterable {
    case move = "移动"
    case rect = "矩形"
    case ellipse = "椭圆"
    case arrow = "箭头"
    case line = "直线"
    case pencil = "画笔"
    case highlight = "高亮"
    case text = "文字"
    case mosaic = "马赛克"
    case number = "序号"
    case eraser = "橡皮"

    var icon: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rect: return "square"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "minus"
        case .pencil: return "pencil"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .mosaic: return "square.dashed"
        case .number: return "number.circle"
        case .eraser: return "eraser"
        }
    }
}

enum ArrowStyle: Int, CaseIterable {
    case solid = 0   // 实心箭头
    case hollow = 1  // 空心箭头
    case thin = 2    // 细线箭头
}

enum MosaicStyle: Int, CaseIterable {
    case pixelate = 0  // 像素化
    case blur = 1      // 模糊
}

struct AnnotationShape: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var text: String
    var number: Int
    var fontSize: CGFloat
    var opacity: Double
    var arrowStyle: ArrowStyle
    var mosaicStyle: MosaicStyle
    var textBgColor: Color
    var textBgOpacity: Double

    init(tool: AnnotationTool, points: [CGPoint], color: Color, lineWidth: CGFloat, text: String = "", number: Int = 0, fontSize: CGFloat = 16, opacity: Double = 1.0, arrowStyle: ArrowStyle = .solid, mosaicStyle: MosaicStyle = .pixelate, textBgColor: Color = .black, textBgOpacity: Double = 0.8) {
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.number = number
        self.fontSize = fontSize
        self.opacity = opacity
        self.arrowStyle = arrowStyle
        self.mosaicStyle = mosaicStyle
        self.textBgColor = textBgColor
        self.textBgOpacity = textBgOpacity
    }

    func textBoundingBox() -> CGRect? {
        guard tool == .text, let p = points.first, !text.isEmpty else { return nil }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let insetX: CGFloat = 4
        let insetY: CGFloat = 2
        return CGRect(x: p.x, y: p.y, width: size.width + insetX * 2, height: size.height + insetY * 2)
    }
}
