import AppKit
import Vision

struct OCRResult {
    var text: String = ""
    var barcodes: [String] = []
    var html: String = ""
    var isEmpty: Bool {
        text.isEmpty && barcodes.isEmpty
    }
    var displayText: String {
        var parts: [String] = []
        if !barcodes.isEmpty {
            parts.append("二维码/条形码：")
            parts.append(barcodes.joined(separator: "\n"))
        }
        if !text.isEmpty {
            if !parts.isEmpty { parts.append("") }
            parts.append("文字：")
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }
    var clipboardText: String {
        if SettingsStore.shared.settings.ocrOutputHTML && !html.isEmpty {
            return html
        }
        var parts: [String] = []
        if !barcodes.isEmpty {
            parts.append(barcodes.joined(separator: "\n"))
        }
        if !text.isEmpty {
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }
}

/// 单个文字块的几何与样式信息
private struct TextBlock {
    let text: String
    let bbox: CGRect       // 归一化坐标 (0~1, origin bottom-left)
    let height: CGFloat    // 归一化高度，用于推断字号
    let fontSize: Int      // 推断的逻辑字号 (px)
    let color: String      // hex 颜色
    let left: CGFloat      // 归一化 X (left)
    let top: CGFloat       // 归一化 Y (top, from top)
    let width: CGFloat     // 归一化宽度
}

final class OCRManager {
    static let shared = OCRManager()

    func recognize(image: NSImage, completion: @escaping (OCRResult) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(OCRResult())
            return
        }

        let formatText = SettingsStore.shared.settings.ocrFormatText
        let outputHTML = SettingsStore.shared.settings.ocrOutputHTML

        // 获取屏幕缩放比，用于将物理像素字号转换为逻辑字号
        let scaleFactor = (NSScreen.main?.backingScaleFactor ?? 2.0)

        let textRequest = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []

            // 构建文字块（含几何信息）
            let blocks = observations.compactMap { obs -> TextBlock? in
                guard let candidate = obs.topCandidates(1).first else { return nil }
                let bbox = obs.boundingBox
                let height = bbox.height
                // 物理像素高度 / 缩放比 = 逻辑像素高度
                // bbox 包含行间距，实际字号约为 bbox 高度的 0.75
                let pxHeight = height * CGFloat(cgImage.height) / CGFloat(scaleFactor)
                let fontSize = max(10, Int(pxHeight * 0.75))
                let color = OCRManager.sampleColor(in: bbox, from: cgImage)
                // 转换为 HTML 坐标系：left/top/width (归一化, top from top)
                let left = bbox.minX
                let top = 1.0 - bbox.maxY
                let width = bbox.width
                return TextBlock(text: candidate.string, bbox: bbox, height: height, fontSize: fontSize, color: color, left: left, top: top, width: width)
            }

            let rawText = blocks.map { $0.text }.joined(separator: "\n")
            let text = formatText ? OCRManager.formatPlainText(rawText) : rawText
            let html = outputHTML ? OCRManager.buildHTML(blocks: blocks, imageWidth: cgImage.width, imageHeight: cgImage.height) : ""

            let barcodeRequest = VNDetectBarcodesRequest { req, _ in
                let observations = req.results as? [VNBarcodeObservation] ?? []
                let payloads = observations.compactMap { $0.payloadStringValue }

                DispatchQueue.main.async {
                    var result = OCRResult()
                    result.text = text
                    result.barcodes = payloads
                    result.html = html
                    completion(result)
                }
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([barcodeRequest])
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        textRequest.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([textRequest])
        }
    }

    /// 从原图中采样文字区域，通过亮度直方图分离前景（文字）和背景颜色
    private static func sampleColor(in normalizedRect: CGRect, from cgImage: CGImage) -> String {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        // Vision bbox: origin bottom-left, normalized
        let px = Int(normalizedRect.minX * w)
        let py = Int((1 - normalizedRect.maxY) * h)
        let pw = max(1, Int(normalizedRect.width * w))
        let ph = max(1, Int(normalizedRect.height * h))

        guard let provider = cgImage.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return "#000000"
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        let bitmapInfo = cgImage.bitmapInfo
        let isBigEndian = bitmapInfo.rawValue & CGBitmapInfo.byteOrder32Big.rawValue != 0

        // 收集采样区域所有像素的 RGB
        struct Pixel { let r: UInt8; let g: UInt8; let b: UInt8 }
        var pixels: [Pixel] = []
        pixels.reserveCapacity(pw * ph)

        for y in py..<(py + ph) {
            guard y >= 0, y < cgImage.height else { continue }
            for x in px..<(px + pw) {
                guard x >= 0, x < cgImage.width else { continue }
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r: UInt8, g: UInt8, b: UInt8
                if isBigEndian {
                    r = ptr[offset]; g = ptr[offset + 1]; b = ptr[offset + 2]
                } else {
                    r = ptr[offset + 2]; g = ptr[offset + 1]; b = ptr[offset]
                }
                pixels.append(Pixel(r: r, g: g, b: b))
            }
        }

        guard !pixels.isEmpty else { return "#000000" }

        // 计算每个像素的亮度，用 Otsu 方法找最佳阈值分离前景/背景
        let luminances: [Int] = pixels.map { p in
            let r = Double(p.r) * 0.299
            let g = Double(p.g) * 0.587
            let b = Double(p.b) * 0.114
            return Int(r + g + b)
        }

        // 构建亮度直方图
        var histogram = [Int](repeating: 0, count: 256)
        for lum in luminances { histogram[lum] += 1 }

        // Otsu 方法：找使类间方差最大的阈值
        let total = pixels.count
        var sumAll = 0
        for i in 0..<256 { sumAll += i * histogram[i] }

        var sumBg = 0
        var weightBg = 0
        var maxVariance = 0
        var threshold = 128

        for t in 0..<256 {
            weightBg += histogram[t]
            if weightBg == 0 { continue }
            let weightFg = total - weightBg
            if weightFg == 0 { break }
            sumBg += t * histogram[t]
            let meanBg = sumBg / weightBg
            let meanFg = (sumAll - sumBg) / weightFg
            let variance = weightBg * weightFg * (meanBg - meanFg) * (meanBg - meanFg)
            if variance > maxVariance {
                maxVariance = variance
                threshold = t
            }
        }

        // 判断前景是亮色还是暗色：比较阈值两侧的平均亮度
        // 通常文字像素较少（前景），背景像素较多
        let darkCount = luminances.filter { $0 < threshold }.count
        let lightCount = total - darkCount

        // 前景 = 像素数较少的那一组（文字通常占面积比背景小）
        let foregroundIsDark = darkCount < lightCount

        // 计算前景平均颜色
        var totalR: UInt64 = 0
        var totalG: UInt64 = 0
        var totalB: UInt64 = 0
        var count: UInt64 = 0

        for (i, p) in pixels.enumerated() {
            let isDark = luminances[i] < threshold
            if (isDark && foregroundIsDark) || (!isDark && !foregroundIsDark) {
                totalR += UInt64(p.r)
                totalG += UInt64(p.g)
                totalB += UInt64(p.b)
                count += 1
            }
        }

        guard count > 0 else { return "#000000" }
        let r = totalR / count
        let g = totalG / count
        let b = totalB / count
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 根据文字块构建结构化 HTML（绝对定位，保持原始位置）
    private static func buildHTML(blocks: [TextBlock], imageWidth: Int, imageHeight: Int) -> String {
        guard !blocks.isEmpty else { return "" }

        // 计算平均高度作为正文基准
        let avgHeight = blocks.map { $0.height }.reduce(0, +) / CGFloat(blocks.count)

        // 容器宽高比，用 padding-top 撑出正确高度，使百分比定位有参照
        let aspectRatio = CGFloat(imageHeight) / CGFloat(imageWidth) * 100
        var html = "<div style=\"position:relative; width:100%; padding-top:\(String(format: "%.2f%%", aspectRatio)); font-family:sans-serif;\">\n"

        for block in blocks {
            let escaped = escapeHTML(block.text)
            let isHeading = block.height > avgHeight * 1.3
            let tag = isHeading ? (block.height > avgHeight * 1.8 ? "h1" : "h2") : "p"
            let leftPct = String(format: "%.2f%%", block.left * 100)
            let topPct = String(format: "%.2f%%", block.top * 100)
            let widthPct = String(format: "%.2f%%", block.width * 100)
            let lineHeightPx = Int(Double(block.fontSize) * 1.4)

            html += "  <\(tag) style=\"position:absolute; left:\(leftPct); top:\(topPct); width:\(widthPct); margin:0; padding:0; font-size:\(block.fontSize)px; color:\(block.color); line-height:\(lineHeightPx)px; white-space:pre-wrap;\">\(escaped)</\(tag)>\n"
        }

        html += "</div>"
        return html
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 整理纯文本：合并断行、去多余空行、去首尾空白
    static func formatPlainText(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")

        // 去每行首尾空白
        lines = lines.map { $0.trimmingCharacters(in: .whitespaces) }

        // 合并断行：若上一行末尾不是句末标点且下一行以非标点开头，则拼接
        let sentenceEnds: Set<Character> = ["。", "！", "？", "…", ".", "!", "?", "；", ";", "：", ":"]
        var merged: [String] = []
        for line in lines {
            if var last = merged.last, !last.isEmpty, !line.isEmpty {
                let lastChar = last.last!
                if !sentenceEnds.contains(lastChar) {
                    // 中英文混排：行尾无标点 → 视为断行，拼接
                    last += line
                    merged[merged.count - 1] = last
                    continue
                }
            }
            merged.append(line)
        }

        // 去连续空行，只保留单个空行作为段落分隔
        var result: [String] = []
        var prevEmpty = false
        for line in merged {
            let isEmpty = line.isEmpty
            if isEmpty && prevEmpty { continue }
            result.append(line)
            prevEmpty = isEmpty
        }

        // 去首尾空行
        while result.first?.isEmpty == true { result.removeFirst() }
        while result.last?.isEmpty == true { result.removeLast() }

        return result.joined(separator: "\n")
    }
}
