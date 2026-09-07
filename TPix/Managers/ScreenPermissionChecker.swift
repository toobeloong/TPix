import AppKit
import ScreenCaptureKit

final class ScreenPermissionChecker {
    static let shared = ScreenPermissionChecker()
    
    private var permissionChecked = false
    private var permissionGranted = false

    func check() -> Bool {
        // 如果已经检查过且授权，直接返回
        if permissionChecked && permissionGranted {
            return true
        }
        
        var granted = false
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                _ = content
                granted = true
            } catch {
                granted = false
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            granted = false
        }
        
        // 缓存结果
        permissionChecked = true
        permissionGranted = granted
        
        if !granted {
            DispatchQueue.main.async {
                self.showPermissionAlert()
            }
        }
        return granted
    }
    
    /// 重置权限检查状态（用于调试或用户手动刷新）
    func resetPermissionCheck() {
        permissionChecked = false
        permissionGranted = false
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "TPix 需要屏幕录制权限才能截图。请到 系统设置 > 隐私与安全性 > 屏幕录制 中允许 TPix。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
