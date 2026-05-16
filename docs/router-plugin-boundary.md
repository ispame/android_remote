# Router ↔ Plugin 运行时接口边界

本文档定义 Router（Project A）和 Plugin（Project B）在运行时的交互边界，供部署人员参考。

---

## 架构概览

```
┌──────────────────────────┐         ┌──────────────────────────┐
│  android-remote-gateway  │         │ android-remote-gateway-   │
│  （Router Project A）     │         │   plugins（Plugin Project B）│
│                          │         │                          │
│  packages/router/        │◀── WS ──│  packages/gateway-plugin/│
│  GatewayRouter           │         │  GatewayChannel           │
│  port: 443              │         │  endpoint: ws://IP:443  │
└──────────────────────────┘         └──────────────────────────┘
```

- **连接方向**：Plugin 主动连接 Router（防火墙出站方向，最宽松）
- **协议**：Phase 1 JSON WebSocket 帧（见 `protocol-v1.md`）
- **无 TLS**：生产环境由 nginx / Cloudflare 终止 TLS，Router 监听内网 `127.0.0.1:443`

---

## 部署配置

### Router（Project A）

```bash
# 公网服务器上
node scripts/start-router.mjs
# 或指定端口
PORT=9000 node scripts/start-router.mjs
```

**环境变量：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PORT` | `443` | HTTP/WS 监听端口 |
| `HOST` | `0.0.0.0` | 监听地址 |

**Docker / systemd**：参考 `docs/deploy-tls-proxy.md`

---

### Plugin（Project B）

```bash
# OpenClaw 所在机器（内网）
node scripts/start-plugin.mjs \
  --endpoint ws://<router-public-ip>:443 \
  --agentId main
```

**环境变量：**

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ROUTER_URL` | `ws://127.0.0.1:443` | Router WebSocket 地址 |
| `AGENT_ID` | `main` | OpenClaw agentId |

**参数：**

| 参数 | 说明 |
|---|---|
| `--endpoint <url>` | Router WS 地址（必填） |
| `--agentId <id>` | Plugin 的 client_id（必填） |
| `--auto-reply` | 是否自动回复消息（默认 true） |

---

## QR 码格式

Plugin 生成 QR 码供 App 扫描：

```
openclaw://connect?gateway=ws://...&agentId=...&token=...
```

**字段说明：**

| 字段 | 来源 | 说明 |
|---|---|---|
| `gateway` | Plugin 配置 | Router 的 WS 地址（公网可访问） |
| `agentId` | Plugin 配置 | Plugin 的 client_id |
| `token` | 自动生成 | 16 字节 hex，标识本次会话 |

App 扫描后：
1. App 连接到 `gateway` 地址
2. App 发送 `register(client_type=app, client_id=<随机>, label=<手机名>)`
3. App 发送 `pair_request(target_backend_id=<agentId>)`
4. Plugin 收到 `pair_request` 并回复 `pair_response(approve=true)`

---

## 协议包依赖

```
gateway-plugin
  └─ @openclaw/protocol          ← Phase 1 帧类型定义
       ├─ Frame 类型并集
       ├─ serialize()
       └─ parse()

Router (@openclaw/router)
  └─ @openclaw/protocol          ← 相同协议包，零重复类型
```

两端使用完全相同的 `@openclaw/protocol` 包，类型完全一致。

---

## 内容类型透传

Router 对 `message.content_type` 不做任何处理：

| App 发送 content_type | Router 行为 | Plugin 收到 |
|---|---|---|
| `text` | 透传 | 原样 |
| `audio/opus` | 透传 | 原样（base64 内容） |
| `image/png` | 透传 | 原样（base64 内容） |
| `application/octet-stream` | 透传 | 原样 |

Plugin 负责根据 `content_type` 解码内容。

---

## 依赖版本对照

当 Plugin 连接到 Router 时，**不检查版本号**——协议完全由 JSON 结构决定，只要两端使用相同版本的 `@openclaw/protocol` 即可。

建议：发布 Project A 后打 git tag，Project B 锁定到对应 tag。

```bash
# Project A 发布后打标签
git tag protocol-v1.0.0 && git push origin protocol-v1.0.0

# Project B package.json 引用该标签
"@openclaw/protocol": "git+https://github.com/ispame/android-remote-gateway.git#protocol-v1.0.0"
```
