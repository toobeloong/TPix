import AppKit

final class ImageSaver {
    static let shared = ImageSaver()

    func save(image: NSImage) {
        let settings = SettingsStore.shared.settings
        var path = settings.savePath
        path = NSString(string: path).expandingTildeInPath

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "TPix_\(formatter.string(from: Date())).\(settings.imageFormat)"

        let url = URL(fileURLWithPath: path).appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

            if settings.imageFormat == "png" {
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                try png.write(to: url)
            } else {
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return }
                try jpg.write(to: url)
            }
        } catch {
            print("保存失败: \(error)")
        }
    }
}
