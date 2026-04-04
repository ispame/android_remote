# OpenClaw Android Remote Control

将安卓手机变成 OpenClaw / Nanobot 的轻量远程控制设备，支持文本聊天，并保留原来的 Nanobot 语音流接入方式。

## 架构

```
[Android App] <--WebSocket--> [Nanobot Android Channel]
            \--Gateway WS--> [OpenClaw Gateway]
```

当前兼容范围：

- `Nanobot`：兼容原来的 `/ws` 文本 + 流式音频协议
- `OpenClaw`：兼容 Gateway 聊天协议（`connect` / `chat.send` / `chat.history` / `chat.subscribe`）

说明：

- OpenClaw 兼容模式目前先完成了文本聊天链路
- 语音按钮仍然只走 Nanobot 那套原始音频流协议

## Nanobot 服务器端配置

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

## OpenClaw Gateway 配置

在 App 里切换到 `OpenClaw` 后端后，填写：

- 服务器地址
- 端口，默认 `18789`
- 是否启用 `TLS / WSS`
- `Shared Token` / `Bootstrap Token` / `Password` 中可用的那一种
- `Session Key`，通常保留 `main`

兼容实现参考了 OpenClaw 官方 Gateway 协议与 Android 端握手格式，包括：

- `connect.challenge`
- `connect`
- `chat.send`
- `chat.history`
- `node.event(chat.subscribe)`
- Ed25519 设备签名与设备 token 持久化

## Android 客户端

1. 用 Android Studio 打开 `android_remote` 项目
2. 编译并安装到手机
3. 在 App 里选择后端类型并填写连接配置

## 使用

- 文本输入：在输入框输入文字，点击“发送”
- Nanobot 语音输入：点击“开始语音发送”，再次点击停止
- OpenClaw 文本输入：直接通过 Gateway 聊天

## 测试

使用 wscat 测试 WebSocket 连接：

```bash
npm install -g wscat
wscat -c ws://localhost:8765/ws

# 发送文本消息
{"type":"text","content":"hello","sender_id":"test"}
```
