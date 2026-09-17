import AppKit
import Foundation

struct AppSettings: Codable, Equatable {
    var areaCaptureHotkey: HotkeyCombo = .none
    var recordHotkey: HotkeyCombo = .none
    var ocrHotkey: HotkeyCombo = .none
    var quickOcrHotkey: HotkeyCombo = .none

    var showOnLaunch: Bool = false
    var launchAtLogin: Bool = false
    var autoCopyToClipboard: Bool = true
    var saveToFolder: Bool = true
    var savePath: String = "~/Pictures/TPix"
    var imageFormat: String = "png"
    var recordingFPS: Int = 30
    var recordingQuality: String = "high"
    var showMagnifier: Bool = true
    var showCrosshair: Bool = true

    // OCR
    var ocrFormatText: Bool = false  // 自动整理纯文本：去多余空行、合并断行
    var ocrOutputHTML: Bool = false  // 输出结构化 HTML（含字号、颜色、段落）

    // Watermark
    var watermarkEnabled: Bool = false
    var watermarkText: String = "TPix"
    var watermarkType: Int = 0  // 0:角标 1:平铺
    var watermarkFontSize: Int = 14
    var watermarkColor: String = "#FFFFFF"
    var watermarkOpacity: Double = 0.5
    var watermarkPosition: Int = 3  // 0:左上 1:右上 2:左下 3:右下
    var watermarkRotation: Int = -45  // 平铺模式旋转角度
    var watermarkSpacing: Int = 100  // 平铺模式水平间隔(px)
    var watermarkVSpacing: Int = 60  // 平铺模式垂直间隔(px)

    // 自定义解码：逐字段 decodeIfPresent，新增字段缺失时用默认值，已有字段保留
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        areaCaptureHotkey = try c.decodeIfPresent(HotkeyCombo.self, forKey: .areaCaptureHotkey) ?? .none
        recordHotkey = try c.decodeIfPresent(HotkeyCombo.self, forKey: .recordHotkey) ?? .none
        ocrHotkey = try c.decodeIfPresent(HotkeyCombo.self, forKey: .ocrHotkey) ?? .none
        quickOcrHotkey = try c.decodeIfPresent(HotkeyCombo.self, forKey: .quickOcrHotkey) ?? .none
        showOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showOnLaunch) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        autoCopyToClipboard = try c.decodeIfPresent(Bool.self, forKey: .autoCopyToClipboard) ?? true
        saveToFolder = try c.decodeIfPresent(Bool.self, forKey: .saveToFolder) ?? true
        savePath = try c.decodeIfPresent(String.self, forKey: .savePath) ?? "~/Pictures/TPix"
        imageFormat = try c.decodeIfPresent(String.self, forKey: .imageFormat) ?? "png"
        recordingFPS = try c.decodeIfPresent(Int.self, forKey: .recordingFPS) ?? 30
        recordingQuality = try c.decodeIfPresent(String.self, forKey: .recordingQuality) ?? "high"
        showMagnifier = try c.decodeIfPresent(Bool.self, forKey: .showMagnifier) ?? true
        showCrosshair = try c.decodeIfPresent(Bool.self, forKey: .showCrosshair) ?? true
        ocrFormatText = try c.decodeIfPresent(Bool.self, forKey: .ocrFormatText) ?? false
        ocrOutputHTML = try c.decodeIfPresent(Bool.self, forKey: .ocrOutputHTML) ?? false
        watermarkEnabled = try c.decodeIfPresent(Bool.self, forKey: .watermarkEnabled) ?? false
        watermarkText = try c.decodeIfPresent(String.self, forKey: .watermarkText) ?? "TPix"
        watermarkType = try c.decodeIfPresent(Int.self, forKey: .watermarkType) ?? 0
        watermarkFontSize = try c.decodeIfPresent(Int.self, forKey: .watermarkFontSize) ?? 14
        watermarkColor = try c.decodeIfPresent(String.self, forKey: .watermarkColor) ?? "#FFFFFF"
        watermarkOpacity = try c.decodeIfPresent(Double.self, forKey: .watermarkOpacity) ?? 0.5
        watermarkPosition = try c.decodeIfPresent(Int.self, forKey: .watermarkPosition) ?? 3
        watermarkRotation = try c.decodeIfPresent(Int.self, forKey: .watermarkRotation) ?? -45
        watermarkSpacing = try c.decodeIfPresent(Int.self, forKey: .watermarkSpacing) ?? 100
        watermarkVSpacing = try c.decodeIfPresent(Int.self, forKey: .watermarkVSpacing) ?? 60
    }

    init() {}
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings

    private let key = "com.pixaura.settings"
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: key) {
            // 尝试解码，失败时逐字段合并保留已有设置
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                settings = decoded
            } else {
                // 解码失败：尝试保留旧字段，新字段用默认值
                var fallback = AppSettings()
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var merged = fallback
                    // 逐个尝试解码已知字段
                    if let hotkeyData = try? JSONSerialization.data(withJSONObject: dict),
                       let partial = try? JSONDecoder().decode(AppSettings.self, from: hotkeyData) {
                        merged = partial
                    }
                    fallback = merged
                }
                settings = fallback
                save()
            }
        } else {
            settings = AppSettings()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    func reset() {
        settings = AppSettings()
        save()
    }
}
