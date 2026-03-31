# OpenClaw Android Remote Control

将安卓手机变成 OpenClaw 机器人的远程控制设备，支持语音和文本输入。

## 架构

```
[Android App] <--WebSocket--> [Android Channel] <--MessageBus--> [Nanobot Agent]
```

## 服务器端配置

1. 编辑 `nanobot/config.yaml`，添加：

```yaml
channels:
  android:
    enabled: true
    host: "0.0.0.0"
    port: 8765
    allow_from: ["*"]  # 或指定设备 ID
    asr_url: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
```

2. 配置火山云 ASR 密钥（编辑 `asr_demo/huoshan_sdk.py`）：

```python
self.auth = {
    "app_key": "你的app_key",
    "access_key": "你的access_key"
}
```

3. 启动 nanobot：

```bash
cd nanobot
python -m nanobot
```

## Android 客户端

1. 用 Android Studio 打开 `android_remote` 项目
2. 修改 `MainActivity.kt` 中的服务器地址：
   ```kotlin
   wsManager = WebSocketManager("你的服务器IP", 8765)
   ```
3. 编译并安装到手机

## 使用

- 文本输入：在输入框输入文字，点击"发送"
- 语音输入：点击"按住说话"开始录音，再次点击停止并发送

## 测试

使用 wscat 测试 WebSocket 连接：

```bash
npm install -g wscat
wscat -c ws://localhost:8765/ws

# 发送文本消息
{"type":"text","content":"hello","sender_id":"test"}
```
