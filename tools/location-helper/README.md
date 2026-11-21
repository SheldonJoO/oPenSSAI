# location-helper（Mac 端）

oPenSSAI 虚拟定位的 Mac 助手：收 App 发来的坐标，经 USB（或 Wi-Fi）驱动手机的
DVT 位置模拟服务（苹果开发者机制，Xcode「模拟定位」同款）。完整原理见
`docs/location-simulation-design.md`。

## 前提

- 手机已开**开发者模式**（设置 → 隐私与安全性 → 开发者模式）。
- Mac 上装好 Rust（https://rustup.rs）。
- 手机 USB 连 Mac（首次需在手机上点「信任」），或与 Mac 在同一局域网（Wi-Fi 模式需配对文件，见下）。

## 构建与运行

```sh
cd tools/location-helper
cargo build --release

# USB 模式（推荐）：自动取第一台 USB 设备
./target/release/openssai-location-helper

# 指定设备
./target/release/openssai-location-helper --udid <UDID>

# Wi-Fi 模式：需 lockdown 配对文件
./target/release/openssai-location-helper --host <手机局域网IP> --pairing-file <配对文件.plist>

# 改端口 / 改重发间隔
./target/release/openssai-location-helper --port 17878 --refresh-secs 5
```

启动后记下 Mac 的局域网 IP（系统设置 → 网络），在 App 里：
我的 → 虚拟定位 → Helper 地址 → 填 `http://<Mac局域网IP>:17878`，点「测试连接」。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| `POST /location` | `{"latitude": 37.5, "longitude": 121.3}` | 开始/更新模拟 |
| `DELETE /location` | — | 停止模拟，恢复真实位置 |
| `GET /status` | — | `{"active","latitude","longitude","connected"}` |
| `GET /health` | — | `{"ok": true}` |

快速测试：

```sh
curl -X POST localhost:17878/location -H 'Content-Type: application/json' \
  -d '{"latitude": 37.54469, "longitude": 121.36857}'
curl localhost:17878/status
curl -X DELETE localhost:17878/location
```

## 注意

- 模拟状态寄生在 DVT 会话上，helper 在模拟激活时会每 5 秒重发一次坐标。
  **helper 退出或 Mac 休眠可能导致模拟状态异常**：如需恢复，先重开 helper，
  再从 App 点「停止并恢复真实位置」（或 `curl -X DELETE`）；重启手机也能清除模拟。
- 坐标是 WGS-84；中国境内的地点在苹果地图上可能偏移几百米（GCJ-02 差异）。
- 用完及时停止：模拟位置是全系统生效的，导航、打车、急救等功能都会读到假位置。
- idevice 锁死 0.1.68（上游声明 0.2.0 前 API 可随时 breaking）；升级前重对
  `docs/location-simulation-design.md` §1.2 的调用链。
