import AppKit
import Foundation

struct AppSettings: Codable, Equatable {
    var areaCaptureHotkey: HotkeyCombo = .none
    var fullScreenHotkey: HotkeyCombo = .none
    var delayCaptureHotkey: HotkeyCombo = .none
    var scrollCaptureHotkey: HotkeyCombo = .none
    var recordHotkey: HotkeyCombo = .none
    var pinHotkey: HotkeyCombo = .none
    var colorPickerHotkey: HotkeyCombo = .none
    var ocrHotkey: HotkeyCombo = .none
    var windowUnderCursorHotkey: HotkeyCombo = .none
    var repeatLastCaptureHotkey: HotkeyCombo = .none

    var showOnLaunch: Bool = false
    var autoCopyToClipboard: Bool = true
    var saveToFolder: Bool = true
    var savePath: String = "~/Pictures/TPix"
    var imageFormat: String = "png"
    var delaySeconds: Int = 3
    var recordingFPS: Int = 30
    var recordingQuality: String = "high"
    var showMagnifier: Bool = true
    var showCrosshair: Bool = true
    var defaultPencilColor: String = "#FF0000"
    var defaultPencilWidth: Float = 3.0
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings

    private let key = "com.pixaura.settings"
    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
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
