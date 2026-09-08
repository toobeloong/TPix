# TPix

一款轻量级 macOS 截图与录屏工具，常驻菜单栏，支持区域截图、实时标注、OCR 文字识别和屏幕录制。

## 功能概览

### 区域截图

- 拖拽选择任意区域，支持窗口自动识别（悬停窗口时自动吸附）
- 选区可拖动移动、八方向缩放调整
- 全屏十字标线与像素放大镜（显示 RGB 色值）
- 双击或 Enter 确认截图，Esc 取消

### 实时标注

选区确定后，底部工具栏提供以下标注工具：

| 工具 | 说明 |
|------|------|
| 移动 | 拖动选区或标注元素 |
| 矩形 | 绘制矩形框 |
| 椭圆 | 绘制椭圆 |
| 箭头 | 实心 / 空心 / 细线三种样式 |
| 直线 | 绘制直线 |
| 画笔 | 自由绘制 |
| 高亮 | 半透明高亮笔 |
| 文字 | 添加文字标注，支持自定义字体颜色、字号、背景色及背景透明度 |
| 马赛克 | 像素化 / 模糊两种样式，基于原图处理 |
| 序号 | 自动递增编号标注 |
| 橡皮 | 点击删除单个标注 |

- 每个工具独立记忆颜色、粗细等属性
- 支持撤销 / 重做
- 文字标注支持中文输入法（IME），候选词不会被误删
- 文字标注背景色可选透明、黑、白、黄、红、蓝、绿，透明度 10%–100% 可调

### OCR 文字识别

- 基于 Apple Vision 框架，支持中文（简体）和英文
- 识别区域截图中的文字，结果自动复制到剪贴板
- 弹窗预览识别结果

### 屏幕录制

- 选区确定后开始录制指定区域
- 录制状态浮窗显示在屏幕右上角，包含录制时长和停止按钮
- 使用 ScreenCaptureKit + AVAssetWriter 硬件编码 H.264
- 输出 MP4 格式，保存到"影片"目录
- 支持 15–60 fps 帧率和高 / 中 / 低三档质量
- 再次按下录屏快捷键或点击浮窗停止按钮可结束录制

## 快捷键

所有快捷键均需在设置中手动配置，默认不绑定任何快捷键。

| 功能 | 默认快捷键 |
|------|-----------|
| 区域截图 | 未设置 |
| 录屏 | 未设置 |
| OCR | 未设置 |

支持 ⌘ / ⇧ / ⌃ / ⌥ 修饰键组合，设置界面点击录制按钮按下组合键即可绑定。

## 设置

### 通用

- **启动时显示截图**：应用启动后自动进入截图模式
- **自动复制到剪贴板**：截图完成后自动复制到剪贴板
- **保存到文件夹**：将截图保存到指定路径（默认 `~/Pictures/TPix`）
- **图片格式**：PNG / JPEG

### 快捷键

- 区域截图、录屏、OCR 三个全局快捷键
- 快捷键冲突检测
- 一键恢复默认（清除所有快捷键）

### 截图

- **显示放大镜**：截图时显示像素级放大镜和 RGB 色值
- **显示十字线**：截图时显示全屏十字标线

### 录屏

- **帧率**：15 / 20 / 25 / 30 / 35 / 40 / 45 / 50 / 55 / 60 fps
- **录制质量**：高 / 中 / 低

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- 需要授予**屏幕录制**权限（系统设置 > 障私与安全性 > 屏幕录制）

## 项目结构

```
TPix/
├── TPix.xcodeproj/          # Xcode 项目文件
└── TPix/
    ├── App/
    │   ├── AppDelegate.swift          # 菜单栏、生命周期
    │   └── TPixApp.swift              # 应用入口
    ├── Capture/
    │   ├── CaptureOverlayController.swift  # 截图覆盖窗口控制器
    │   └── CaptureOverlayView.swift        # 截图主视图（选区、标注、工具栏）
    ├── Annotation/
    │   ├── AnnotationTypes.swift      # 标注类型定义（工具、样式、Shape 模型）
    │   └── FocusableTextEditor.swift  # 文字标注输入框（NSViewRepresentable）
    ├── Managers/
    │   ├── CaptureCoordinator.swift   # 截图/录屏/OCR 统一调度
    │   ├── HotkeyManager.swift        # 全局快捷键注册与管理
    │   └── ScreenPermissionChecker.swift  # 屏幕录制权限检查
    ├── OCR/
    │   └── OCRManager.swift           # Vision 框架文字识别
    ├── Recording/
    │   ├── RecordingManager.swift     # ScreenCaptureKit 录屏核心
    │   └── RecordingIndicator.swift   # 录制状态浮窗
    ├── Services/
    │   └── ImageSaver.swift           # 图片保存到文件
    ├── Settings/
    │   ├── SettingsStore.swift        # 设置持久化（UserDefaults）
    │   ├── SettingsView.swift         # 设置界面（SwiftUI）
    │   └── SettingsWindowController.swift  # 设置窗口控制器
    └── Resources/
        ├── Assets.xcassets            # 应用图标等资源
        └── p-favicon.png              # 菜单栏图标
```

## 技术栈

- **语言**：Swift 5
- **UI 框架**：SwiftUI + AppKit（NSViewRepresentable 桥接 NSTextView）
- **最低系统**：macOS 14.0 (Sonoma)
- **截图**：CGWindowListCreateImage
- **录屏**：ScreenCaptureKit + AVAssetWriter
- **OCR**：Vision 框架（VNRecognizeTextRequest）
- **快捷键**：Carbon EventHotKey API
- **设置存储**：UserDefaults（JSON 编码）

## 构建

```bash
# 克隆项目
git clone <repo-url>
cd TPix

# 使用 Xcode 构建
open TPix.xcodeproj

# 或使用命令行
xcodebuild -project TPix.xcodeproj -scheme TPix -configuration Release build

# 构建产物在 DerivedData 中，可手动拷贝到 Applications
```

## 权限说明

首次运行时，TPix 需要以下权限：

| 权限 | 用途 |
|------|------|
| 屏幕录制 | 截图、录屏、OCR 识别 |
| 桌面/文档/图片/影片文件夹 | 保存截图和录屏文件 |

应用启动时会自动检查屏幕录制权限，如未授权会弹窗引导用户到系统设置。

## 设计细节

### 坐标系处理

项目涉及多种坐标系，代码中做了统一转换：

- **SwiftUI 视图**：左上角原点，Y 轴向下
- **NSEvent.mouseLocation / kCGWindowBounds**：左下角原点，Y 轴向上
- **CGImage**：左上角原点，像素坐标
- **SCStreamConfiguration**：`sourceRect` 使用逻辑点，`width/height` 使用物理像素

Retina 屏上逻辑点与物理像素的转换通过 `NSScreen.main.backingScaleFactor`（通常为 2.0）完成。

### 文字标注 IME 兼容

`FocusableTextEditor` 封装 `NSTextView`，针对中文输入法做了特殊处理：

- `updateNSView` 中检查 `hasMarkedText()`，IME 输入过程中不重置文本
- `textDidChange` 在 IME marked text 期间不同步到 SwiftUI `@Binding`，避免重渲染中断输入

### 马赛克实现

马赛克基于原图裁剪后处理，正确处理 Retina 缩放：

- **像素化**：先将裁剪区域缩小到 blockSize 分辨率，再无插值放大
- **模糊**：使用 CIFilter CIGaussianBlur

裁剪坐标通过 `cgImage.width / img.size.width` 计算实际缩放比，确保在 Retina 屏上裁剪区域准确。

## 许可证

私有项目，未开源。
