# OpenClaw Remote

跨平台移动应用（iOS + Android），用于通过 WebSocket 远程控制 OpenClaw 机器人，支持语音和文本输入。

## 架构

**Kotlin Multiplatform (KMP) + Compose Multiplatform**

```
[iOS App / Android App] <--WebSocket--> [Gateway] <--MessageBus--> [OpenClaw Robot]
```

### 项目结构

```
├── shared/              # 共享模块（业务逻辑 + UI）
│   ├── commonMain/      # 共享代码
│   ├── androidMain/     # Android 平台实现
│   └── iosMain/        # iOS 平台实现
├── androidApp/          # Android 应用
└── iosApp/             # iOS 应用
```


## 构建命令

### Android

```bash
./gradlew :androidApp:assembleDebug
```

### iOS（需要 macOS + Xcode）

```bash
# 生成 Xcode 框架
./gradlew :shared:embedAndSignAppleFrameworkForXcode

# 打开 Xcode 项目
cd iosApp/OpenClawRemote
pod install
open OpenClawRemote.xcworkspace
```

详细步骤请参考 [IOS_SETUP.md](IOS_SETUP.md)。

## 技术栈

| 组件 | Android | iOS |
|------|---------|-----|
| UI | Compose Multiplatform | Compose Multiplatform |
| WebSocket | Ktor Client (OKHttp) | Ktor Client (Darwin) |
| 设置存储 | DataStore | NSUserDefaults |
| 语音录制 | MediaRecorder | AVAudioRecorder |
| QR 扫描 | CameraX + ZXing | AVFoundation |

## 服务器端配置

1. 编辑 `nanobot/config.yaml`，添加：

```yaml
channels:
  android:
    enabled: true
    host: "0.0.0.0"
    port: 8765
    allow_from: ["*"]  # 或指定设备 ID
```

2. 启动 nanobot：

```bash
cd nanobot
python -m nanobot
```

## 客户端配置

### Android

1. 用 Android Studio 打开项目
2. 编译并安装到手机
3. 在设置中配置 Gateway 地址

### iOS

1. 参考 [IOS_SETUP.md](IOS_SETUP.md) 生成 Xcode 项目
2. 在 Xcode 中编译运行
3. 在设置中配置 Gateway 地址

## 使用

- **文本输入**：在输入框输入文字，点击发送按钮
- **语音输入**：按住麦克风按钮说话，滑动取消，上滑发送
- **扫码配对**：在设置中扫描 OpenClaw 生成的二维码

## 测试

使用 wscat 测试 WebSocket 连接：

```bash
npm install -g wscat
wscat -c ws://localhost:8765/ws

# 发送注册
{"type":"register","client_type":"app","client_id":"test","label":"Test Device"}
```
