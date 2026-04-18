# iOS 项目设置指南

## 方式一：使用 Android Studio KMP Wizard（推荐）

1. 在 Android Studio 中打开项目
2. File -> New -> New Module...
3. 选择 "Kotlin Multiplatform" -> "iOS Framework"
4. 按照向导完成设置

## 方式二：手动设置 Xcode 项目

1. 在 Android Studio 中运行以下 Gradle task 生成 iOS 框架：
   ```bash
   ./gradlew :shared:embedAndSignAppleFrameworkForXcode
   ```

2. 打开 Xcode 创建新项目：
   - Create a new Xcode project
   - Select "iOS" -> "App"
   - Name it "OpenClawRemote"

3. 在项目设置中：
   - Link Binary With Libraries: 添加 shared.framework
   - Framework Search Paths: 添加 `$(SRCROOT)/../shared/build/xcode-frameworks/`

4. 复制以下文件到项目中：
   - `iosApp/OpenClawRemote/Sources/AppDelegate.swift`
   - `iosApp/OpenClawRemote/Sources/ComposeViewController.swift`
   - `iosApp/OpenClawRemote/Info.plist`

5. 运行 `pod install` 安装依赖

## iOS 权限配置

在 `Info.plist` 中已配置：
- `NSCameraUsageDescription`: QR 码扫描
- `NSMicrophoneUsageDescription`: 语音录制
