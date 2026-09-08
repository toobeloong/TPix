import AppKit
import Foundation

struct AppSettings: Codable, Equatable {
    var areaCaptureHotkey: HotkeyCombo = .none
    var recordHotkey: HotkeyCombo = .none
    var ocrHotkey: HotkeyCombo = .none

    var showOnLaunch: Bool = false
    var autoCopyToClipboard: Bool = true
    var saveToFolder: Bool = true
    var savePath: String = "~/Pictures/TPix"
    var imageFormat: String = "png"
    var recordingFPS: Int = 30
    var recordingQuality: String = "high"
    var showMagnifier: Bool = true
    var showCrosshair: Bool = true
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
