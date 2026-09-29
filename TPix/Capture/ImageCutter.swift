import AppKit
import CoreGraphics

/// 图像裁剪工具：将全屏截图按选区矩形裁剪为选区图像。
/// 坐标系：selectionRect 与 cgImage.cropping(to:) 均使用左上角原点，
/// 与 CaptureOverlayView 原有逻辑完全一致，确保裁剪结果不偏移。
enum ImageCutter {

    /// 从全屏图像中裁剪出指定矩形区域。
    /// - Parameters:
    ///   - fullImage: 全屏截图（NSImage，size 为逻辑点尺寸）
    ///   - rect: 选区矩形（左上角原点，逻辑点坐标）
    /// - Returns: 裁剪后的 NSImage（size 为选区逻辑点尺寸），失败时返回原图
    static func crop(_ fullImage: NSImage, rect: NSRect) -> NSImage {
        guard let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fullImage
        }
        guard rect.width > 0, rect.height > 0 else {
            return fullImage
        }
        let scale = fullImage.size.width == 0 ? 1 : CGFloat(cgImage.width) / fullImage.size.width
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
}
