import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

struct SettingsView: View {
    @StateObject private var store = SettingsStore.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var conflictMessage: String?

    enum SettingsTab: String, CaseIterable {
        case general = "通用"
        case hotkeys = "快捷键"
        case capture = "截图"
        case recording = "录屏"
        case ocr = "OCR"
        case watermark = "水印"
        
        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .hotkeys: return "keyboard.fill"
            case .capture: return "camera.fill"
            case .recording: return "record.circle.fill"
            case .ocr: return "doc.text.fill"
            case .watermark: return "drop.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    NavigationButton(tab: tab, selected: selectedTab == tab) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    }
                }
                Spacer()
            }
            .frame(width: 200, alignment: .top)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .padding(.horizontal, 12)
            .background(
                LinearGradient(
                    colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor).opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Divider()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    switch selectedTab {
                    case .general:
                        generalContent
                    case .hotkeys:
                        hotkeysContent
                    case .capture:
                        captureContent
                    case .recording:
                        recordingContent
                    case .ocr:
                        ocrContent
                    case .watermark:
                        watermarkContent
                    }
                    Spacer(minLength: 0)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 700, height: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            store.save()
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "启动选项", icon: "power")
            ModernCard {
                ModernToggle(
                    title: "开机自动启动",
                    subtitle: "登录时自动启动 TPix",
                    isOn: $store.settings.launchAtLogin
                )
                .onChange(of: store.settings.launchAtLogin) { _, newValue in
                    toggleLaunchAtLogin(enabled: newValue)
                }
                ModernToggle(
                    title: "启动时显示截图",
                    subtitle: "应用启动后自动进入截图模式",
                    isOn: $store.settings.showOnLaunch
                )
            }
            
            SectionHeader(title: "保存设置", icon: "folder.fill")
            ModernCard {
                ModernToggle(
                    title: "自动复制到剪贴板",
                    subtitle: "截图完成后自动复制到剪贴板",
                    isOn: $store.settings.autoCopyToClipboard
                )
                ModernToggle(
                    title: "保存到文件夹",
                    subtitle: "将截图保存到指定文件夹",
                    isOn: $store.settings.saveToFolder
                )
                
                if store.settings.saveToFolder {
                    Divider()
                        .padding(.vertical, 8)
                    HStack {
                        Text("保存路径")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        TextField("", text: $store.settings.savePath)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                            )
                            .frame(width: 220)
                        Button(action: chooseSaveFolder) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .padding(.leading, 8)
                        .help("选择文件夹")
                    }
                }
                
                Divider()
                    .padding(.vertical, 8)
                HStack {
                    Text("图片格式")
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Picker("", selection: $store.settings.imageFormat) {
                        Text("PNG").tag("png")
                        Text("JPEG").tag("jpg")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
        .onChange(of: store.settings) { _, _ in store.save() }
    }

    private var hotkeysContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "快捷键设置", icon: "command")
            
            HStack {
                Text("点击右侧按钮录制新的快捷键组合，按 Esc 取消录制")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                Spacer()
                Button(action: resetHotkeys) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13))
                        Text("恢复默认")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            
            if let msg = conflictMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
            }
            
            ModernCard {
                VStack(spacing: 12) {
                    ForEach(hotkeyItems, id: \.title) { item in
                        ModernHotkeyRow(title: item.title, combo: item.combo) {
                            checkConflict()
                        }
                        if item.title != hotkeyItems.last?.title {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onChange(of: store.settings) { _, _ in
            store.save()
            HotkeyManager.shared.unregisterAll()
            HotkeyManager.shared.registerAll()
        }
    }

    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "截图选项", icon: "camera.aperture")
            ModernCard {
                ModernToggle(
                    title: "显示放大镜",
                    subtitle: "截图时显示像素放大镜和色值",
                    isOn: $store.settings.showMagnifier
                )
                ModernToggle(
                    title: "显示十字线",
                    subtitle: "截图时显示全屏十字标线",
                    isOn: $store.settings.showCrosshair
                )
            }
        }
        .onChange(of: store.settings) { _, _ in store.save() }
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "录屏设置", icon: "video.fill")
            ModernCard {
                HStack {
                    Text("帧率")
                        .foregroundColor(.primary)
                        .frame(width: 100, alignment: .leading)
                    Spacer()
                    Stepper("", value: $store.settings.recordingFPS, in: 15...60, step: 5)
                        .labelsHidden()
                        .tint(.accentColor)
                    HStack(spacing: 4) {
                        Text("\(store.settings.recordingFPS)")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                        Text("fps")
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, alignment: .trailing)
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                HStack {
                    Text("录制质量")
                        .foregroundColor(.primary)
                        .frame(width: 100, alignment: .leading)
                    Spacer()
                    Picker("", selection: $store.settings.recordingQuality) {
                        Text("高").tag("high")
                        Text("中").tag("medium")
                        Text("低").tag("low")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }
        }
        .onChange(of: store.settings) { _, _ in store.save() }
    }

    private var ocrContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "识别设置", icon: "doc.text.fill")
            ModernCard {
                ModernToggle(
                    title: "自动整理纯文本",
                    subtitle: "合并断行、去除多余空行和首尾空白，输出更干净的文本",
                    isOn: $store.settings.ocrFormatText
                )
                ModernToggle(
                    title: "输出结构化 HTML",
                    subtitle: "根据文字大小推断标题/段落，采样文字颜色，生成带样式的 HTML 源码复制到剪贴板",
                    isOn: $store.settings.ocrOutputHTML
                )
            }
        }
        .onChange(of: store.settings) { _, _ in store.save() }
    }

    private var watermarkContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "水印设置", icon: "drop.fill")
            ModernCard {
                ModernToggle(
                    title: "启用水印",
                    subtitle: "截图时在图片上添加水印",
                    isOn: $store.settings.watermarkEnabled
                )

                if store.settings.watermarkEnabled {
                    Divider().padding(.vertical, 8)

                    HStack {
                        Text("水印文字")
                            .foregroundColor(.primary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        TextField("输入水印文字", text: $store.settings.watermarkText)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                            )
                            .frame(width: 220)
                    }

                    Divider().padding(.vertical, 8)

                    HStack {
                        Text("类型")
                            .foregroundColor(.primary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        ForEach(WatermarkType.allCases, id: \.self) { type in
                            Button(action: { store.settings.watermarkType = type.rawValue }) {
                                Text(type.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(store.settings.watermarkType == type.rawValue ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(store.settings.watermarkType == type.rawValue ? Color.accentColor : Color.gray.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider().padding(.vertical, 8)

                    HStack {
                        Text("字号")
                            .foregroundColor(.primary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Stepper("", value: $store.settings.watermarkFontSize, in: 8...48, step: 1)
                            .labelsHidden()
                            .tint(.accentColor)
                        Text("\(store.settings.watermarkFontSize)")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }

                    Divider().padding(.vertical, 8)

                    HStack {
                        Text("透明度")
                            .foregroundColor(.primary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Slider(value: $store.settings.watermarkOpacity, in: 0.1...1.0, step: 0.1)
                            .frame(width: 160)
                        Text("\(Int(store.settings.watermarkOpacity * 100))%")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }

                    Divider().padding(.vertical, 8)

                    HStack {
                        Text("颜色")
                            .foregroundColor(.primary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        ForEach(["#FFFFFF", "#000000", "#FF0000", "#FF8800", "#00AA00", "#0066FF", "#8800FF"], id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(store.settings.watermarkColor == hex ? Color.accentColor : Color.gray.opacity(0.3),
                                                lineWidth: store.settings.watermarkColor == hex ? 3 : 1)
                                        .frame(width: 26, height: 26)
                                )
                                .onTapGesture { store.settings.watermarkColor = hex }
                        }
                    }

                    // 角标模式：显示位置选择
                    if store.settings.watermarkType == 0 {
                        Divider().padding(.vertical, 8)

                        HStack {
                            Text("位置")
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            ForEach(WatermarkPosition.allCases, id: \.self) { pos in
                                Button(action: { store.settings.watermarkPosition = pos.rawValue }) {
                                    Image(systemName: pos.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(store.settings.watermarkPosition == pos.rawValue ? .white : .primary)
                                        .frame(width: 32, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(store.settings.watermarkPosition == pos.rawValue ? Color.accentColor : Color.gray.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 平铺模式：显示旋转角度和间隔
                    if store.settings.watermarkType == 1 {
                        Divider().padding(.vertical, 8)

                        HStack {
                            Text("旋转角度")
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Slider(value: Binding(
                                get: { Double(store.settings.watermarkRotation) },
                                set: { store.settings.watermarkRotation = Int($0) }
                            ), in: -90...90, step: 5)
                            .frame(width: 160)
                            Text("\(store.settings.watermarkRotation)°")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }

                        Divider().padding(.vertical, 8)

                        HStack {
                            Text("水平间隔")
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Slider(value: Binding(
                                get: { Double(store.settings.watermarkSpacing) },
                                set: { store.settings.watermarkSpacing = Int($0) }
                            ), in: 20...400, step: 10)
                            .frame(width: 160)
                            Text("\(store.settings.watermarkSpacing)")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }

                        Divider().padding(.vertical, 8)

                        HStack {
                            Text("垂直间隔")
                                .foregroundColor(.primary)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Slider(value: Binding(
                                get: { Double(store.settings.watermarkVSpacing) },
                                set: { store.settings.watermarkVSpacing = Int($0) }
                            ), in: 20...400, step: 10)
                            .frame(width: 160)
                            Text("\(store.settings.watermarkVSpacing)")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .onChange(of: store.settings) { _, _ in store.save() }
    }

    enum WatermarkType: Int, CaseIterable {
        case corner = 0, tile = 1

        var label: String {
            switch self {
            case .corner: return "角标"
            case .tile: return "平铺"
            }
        }
    }

    enum WatermarkPosition: Int, CaseIterable {
        case topLeft = 0, topRight = 1, bottomLeft = 2, bottomRight = 3

        var icon: String {
            switch self {
            case .topLeft: return "arrow.up.left"
            case .topRight: return "arrow.up.right"
            case .bottomLeft: return "arrow.down.left"
            case .bottomRight: return "arrow.down.right"
            }
        }

        var label: String {
            switch self {
            case .topLeft: return "左上"
            case .topRight: return "右上"
            case .bottomLeft: return "左下"
            case .bottomRight: return "右下"
            }
        }
    }

    private var hotkeyItems: [(title: String, combo: Binding<HotkeyCombo>)] {
        [
            ("区域截图", $store.settings.areaCaptureHotkey),
            ("录屏", $store.settings.recordHotkey),
            ("OCR", $store.settings.ocrHotkey),
            ("快速 OCR", $store.settings.quickOcrHotkey)
        ]
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                NSLog("[TPix] LaunchAtLogin: registered")
            } catch {
                NSLog("[TPix] LaunchAtLogin: register failed: \(error)")
                store.settings.launchAtLogin = false
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
                NSLog("[TPix] LaunchAtLogin: unregistered")
            } catch {
                NSLog("[TPix] LaunchAtLogin: unregister failed: \(error)")
            }
        }
        store.save()
    }

    private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.savePath = url.path
            store.save()
        }
    }
    
    private func resetHotkeys() {
        store.settings.areaCaptureHotkey = .none
        store.settings.recordHotkey = .none
        store.settings.ocrHotkey = .none
        store.settings.quickOcrHotkey = .none
        store.save()
        HotkeyManager.shared.unregisterAll()
        HotkeyManager.shared.registerAll()
        conflictMessage = nil
    }
    
    private func checkConflict() {
        let combos = hotkeyItems.map { $0.combo.wrappedValue }
        let duplicates = Dictionary(grouping: combos.filter { !$0.isEmpty }, by: { $0 })
            .filter { $1.count > 1 }
        if let dup = duplicates.first {
            conflictMessage = "快捷键冲突：\(dup.key.displayString) 被多次使用"
        } else {
            conflictMessage = nil
        }
    }
}

// MARK: - 导航按钮
struct NavigationButton: View {
    let tab: SettingsView.SettingsTab
    let selected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                Spacer()
                if selected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundColor(selected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        selected ? Color.accentColor :
                        (isHovered ? Color.gray.opacity(0.15) : Color.clear)
                    )
            )
            .shadow(
                color: selected ? Color.accentColor.opacity(0.3) : .clear,
                radius: selected ? 8 : 0,
                y: selected ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering && !selected
            }
        }
    }
}

// MARK: - 章节标题
struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

// MARK: - 现代卡片
struct ModernCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

// MARK: - 现代 Toggle
struct ModernToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .scaleEffect(1.1)
        }
    }
}

// MARK: - 现代快捷键行
struct ModernHotkeyRow: View {
    let title: String
    @Binding var combo: HotkeyCombo
    var onChange: () -> Void = {}
    
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 100, alignment: .leading)
            Spacer()
            
            Button(action: toggleRecording) {
                HStack(spacing: 8) {
                    if isRecording {
                        Image(systemName: "record.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                            .pulseAnimation()
                    }
                    Text(isRecording ? "按下快捷键…" : combo.displayString)
                        .font(.system(size: 13, design: .monospaced))
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isRecording ? Color.accentColor.opacity(0.15) :
                            (isHovered ? Color.gray.opacity(0.15) : Color.gray.opacity(0.1))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isRecording ? Color.accentColor : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .foregroundColor(isRecording ? .accentColor : .primary)
            }
            .buttonStyle(.plain)
            .frame(width: 160)
            .onHover { isHovered = $0 }
            
            if isRecording {
                Button("取消") {
                    stopRecording()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            } else {
                Button(action: clearHotkey) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除快捷键")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            
            if modifiers == 0 {
                return event
            }
            
            combo = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            onChange()
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
    
    private func clearHotkey() {
        combo = HotkeyCombo(keyCode: 0, modifiers: 0)
        onChange()
    }
}

// MARK: - 脉冲动画
struct PulseAnimation: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: UUID()
            )
    }
}

extension View {
    func pulseAnimation() -> some View {
        modifier(PulseAnimation())
    }
}

extension Color {
    init(hex: String) {
        let s = hex.replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
    
    func toHexString() -> String {
        let nsColor = NSColor(self)
        return String(format: "#%02X%02X%02X",
                      Int(nsColor.redComponent * 255),
                      Int(nsColor.greenComponent * 255),
                      Int(nsColor.blueComponent * 255))
    }
}
