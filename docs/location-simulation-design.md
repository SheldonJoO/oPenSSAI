# 虚拟定位（Location Simulation）设计文档

> 分支：`feature/location-simulation` · 状态：第一阶段（App 界面 + Mac helper 脚手架）
> 2026-11-21 · 本文档只写原理与公开资料的结论，不含任何非兼容许可代码。

## 0. 一句话结论

虚拟定位走苹果官方开发者机制：**DVT LocationSimulation 服务**（Xcode「模拟定位」用的就是这套），坐标直接注入系统 `locationd`，全系统生效（地图及所有 App 读到的都是模拟位置，户外 GPS 不会覆盖它）。iOS 26 上不需要挂开发者磁盘镜像，不需要越狱；需要**开发者模式 + 一次配对关系**。

oPenSSAI 已经具备本功能所需的全部关键部件（见 §5），所以分两个阶段：

- **第一阶段（本轮）**：App 界面 + Mac helper。App 把坐标发给局域网内的 Mac helper，helper 用 MIT 的 `idevice` 库经 USB（或 TCP）驱动手机的 DVT 位置模拟服务。helper 是验证载体：USB + Mac 是这条路被验证得最多的形态。
- **第二阶段（目标）**：本机直连。App 直接用已 vendored 的 `idevice` FFI（`IDevice.xcframework`）经现有 em_proxy/minimuxer 回环隧道 + 已存的 RPPairing 文件驱动本机的 DVT 服务，运行时不再需要 Mac。App 界面按 `LocationSimulationService` 协议抽象，第二阶段只换传输实现，不动界面。

wloc 路线已排除：2026-11-04 起苹果给 gs-loc 加了证书 pinning，iOS 26 上 MITM 失效；且它只改网络定位，GPS 会覆盖。WrapPin 的代码是 PolyForm 非商业许可，**绝不抄进 AGPL 项目**；本文档只引用其公开用户文档中的架构原理。

---

## 1. 工作机制

### 1.1 两代机制

| | 旧机制（iOS ≤ 16） | 新机制（iOS 17+，含 iOS 26） |
|---|---|---|
| 服务 | lockdown 服务 `com.apple.dt.simulatelocation` | DVT 通道 `com.apple.instruments.server.services.LocationSimulation` |
| 前提 | 挂载 DeveloperDiskImage | 开发者模式 + 配对关系，无需挂 DDI |
| 协议 | lockdown 直连，plist 发经纬度 | RemoteServer（DTServiceHub）通道，方法调用 |
| libimobiledevice | `idevicesetlocation` | 不支持（iOS 17 改了 DDI 机制后断裂） |
| idevice（Rust） | `services::simulate_location::LocationSimulationService` | `dvt::location_simulation::LocationSimulationClient` |

iOS 17 把开发者磁盘镜像改成个性化（Personalized DDI）后，旧路径事实上断了；Xcode 和 `devicectl` 现在都走 DVT 路径。本项目只实现新机制，旧机制仅作为 idevice 工具里的回退存在。

### 1.2 新机制的调用链（iOS 17+）

```
Host（Mac helper / 本机 App）
  │  1. Provider：usbmuxd（USB）或 TCP（Wi-Fi，配对文件）
  ▼
CoreDeviceProxy::connect(provider)
  │  2. 建软件隧道，拿到 RSD 端口
  ▼
adapter.connect(rsd_port) → RsdHandshake
  │  3. RSD（RemoteServerDaemon）握手
  ▼
RemoteServerClient::connect_rsd(adapter, handshake)
  │  4. 打开 DVT RemoteServer 会话
  ▼
LocationSimulationClient::new(rs_client)
  │  5. 打开通道 com.apple.instruments.server.services.LocationSimulation
  ▼
set(latitude, longitude) / clear()
     方法：simulateLocationWithLatitude:longitude: / stopLocationSimulation
```

坐标到达 `locationd` 后，全系统的位置读取都返回模拟值。**会话语义**：模拟状态寄生在 DVT 会话上；idevice 官方工具在 `set` 之后每 5 秒重发一次坐标并保持连接（"Press ctrl-c to stop"）。周期性重发是否严格必需、还是只需保持连接不断，尚无公开定论——helper 按 5 秒重发实现（与官方工具一致），第二阶段本机实现时在真机上验证能否放宽。

### 1.3 前提条件

1. **开发者模式**：设置 → 隐私与安全性 → 开发者模式，必须开启。DVT 服务是开发者服务，未开开发者模式时设备不提供。
2. **配对关系**：Host 与设备之间必须有配对记录。iOS 18–26 用 **RPPairing 文件**（见 §4）；iOS 27 起支持本机配对（设置里「与本 iPhone 配对」，6 位码）。
3. **隧道可达**：helper 形态走 USB（usbmuxd）或局域网 TCP；本机形态走回环隧道（LocalDevVPN 10.7.0.1，或 oPenSSAI 已有的 em_proxy/minimuxer 回环）。

---

### 1.4 坐标系注意（GCJ-02）

DVT 模拟接口接收的是 WGS-84 经纬度。中国境内的苹果地图显示用 GCJ-02（火星坐标系），
所以在中国境内模拟一个 WGS-84 坐标时，地图上的图钉可能偏移几百米——这是坐标系差异，
不是模拟失败。WrapPin 为此提供 GCJ-02/WGS-84 两种坐标模式；本轮只做 WGS-84，
界面脚注已说明偏移现象，后续可在预设地点里加 GCJ-02 转换。

## 2. 参考实现（只看原理与公开文档）

### 2.1 WrapPin（PolyForm 非商业许可——只参考原理，不读代码、不抄代码）

公开用户文档确认的架构：

- App 本机 + LocalDevVPN 回环隧道（默认 10.7.0.1）+ RPPairing（iOS 18–26 需电脑生成一次）或本机配对（iOS 27）。
- 两个版本：Standard（外部 LocalDevVPN，免费证书可签）；Tunnel（内置 Packet Tunnel，需要付费证书 + `packet-tunnel-provider` 权限）。
- 流程：配对一次 → 连隧道 → 选位置 → 开始模拟；换位置时复用已有会话；停止并恢复时清模拟、回真实位置。
- 配对记录存本机钥匙串，不上传。Wi-Fi 下经 mDNS 发现已配对设备；蜂窝数据下有特殊的开关数据流程（与隧道路由有关）。

### 2.2 Locus（MIT，ChrisMack32/Locus）

与 WrapPin 同架构的 MIT 开源实现，证明了本机路线的可行性：MIT 的 `idevice` FFI + DVT 位置模拟 + 本机开发者隧道（LocalDevVPN）。SETUP.md 确认：iOS 18–26 从 `idevice_pair` 生成 RPPairing 文件后导入 App（文件选择器 / 分享 / 剪贴板粘贴）。

### 2.3 Roam Control

同类源可用的 SwiftUI 应用，文档确认：RPPairing 记录存设备钥匙串；启动位置时经 LocalDevVPN 发现设备、验证身份、打开加密开发者会话；原生引擎是围绕 MIT `idevice` 库的窄桥接。

### 2.4 idevice（MIT，jkcoxson/idevice，v0.1.68）

纯 Rust 的 libimobiledevice 替代品，MIT 许可，AGPL 项目可依赖。关键部分：

- `location_simulation` feature：`dvt::location_simulation::LocationSimulationClient`（`new` / `set` / `clear`）+ 旧版 `services::simulate_location::LocationSimulationService`。
- `tools` crate 的 `location_simulation` 子命令（`set <lat> <lon>` / `clear`）是调用链的完整参考实现：先试 CoreDeviceProxy + DVT，失败回退 lockdown 服务。
- `ffi` crate 把同一能力暴露为 C API（见 §5），供 Swift 调用。

---

## 3. 第一阶段架构：App + Mac helper

```
┌─────────────────┐  HTTP/JSON   ┌──────────────────────┐  usbmuxd/USB   ┌─────────────────┐
│  oPenSSAI App   │  局域网      │  location-helper     │  或 TCP/Wi-Fi  │  iPhone (本机)  │
│  虚拟定位界面    │ ───────────► │  (Mac, Rust)         │ ─────────────► │  DVT Location   │
│  坐标/预设/启停  │  :17878      │  idevice 0.1.68      │  CoreDeviceProxy│  Simulation     │
└─────────────────┘              │  会话常驻 + 5s 重发   │  → RSD → DVT   │  → locationd    │
                                 └──────────────────────┘                └─────────────────┘
```

### 3.1 Helper（`tools/location-helper/`）

Rust CLI，依赖 `idevice`（`full` feature，与官方 tools 一致）+ `tokio` + `axum`：

- 启动参数：`--port`（默认 17878）、`--udid`（USB 指定设备）、`--host` + `--pairing-file`（TCP/Wi-Fi）、`--refresh-secs`（默认 5）。
- HTTP 接口：
  - `POST /location` `{"latitude": 37.5, "longitude": 121.3}` —— 开始/更新模拟。
  - `DELETE /location` —— 停止模拟，恢复真实位置。
  - `GET /status` —— `{"active": true, "latitude": …, "longitude": …, "device": "…"}`。
  - `GET /health` —— 存活检查。
- 实现要点：一个后台 actor 任务独占整条连接链（provider → proxy → adapter → handshake → RemoteServerClient → LocationSimulationClient），HTTP 层经 mpsc 发命令、oneshot 收结果——避开 Rust 跨请求持有借用链的生命周期问题。actor 在模拟激活时按间隔重发坐标；连接断开时下次命令触发重连。
- Provider 解析复刻 idevice tools 的 `get_provider`：有 UDID 走 usbmuxd；有 host + pairing file 走 TCP；都不给则取第一个 USB 设备。

### 3.2 App 端（`AltStore/Shell/`）

- 入口：我的 tab 新增「虚拟定位」分区（签名分区之后），行内显示当前状态（未开始 / 模拟中 · 坐标）。
- `LocationSimulationViewController`（UIKit，沿用 AnisetteSettingsViewController 的 insetGrouped 表格模式）：
  - **状态**区：当前状态 + 模拟中的坐标 + helper 连接状态。
  - **坐标**区：纬度 / 经度输入框（数字键盘），输完点开始即生效。
  - **常用地点**区：预设地点一键填充（烟台、北京、上海、深圳、香港、东京、纽约、伦敦、柏林、旧金山）。
  - **控制**区：开始模拟 / 停止并恢复真实位置。
  - **Helper**区：helper 地址（默认 `http://<Mac局域网IP>:17878`，可改）+ 连接测试。
- `LocationSimulationService` 协议 + `HelperLocationService`（URLSession 实现）+ `SimulatedLocation` / 预设模型。协议抽象让第二阶段只换实现。
- 字符串：key 英文、值中文，进 `AltStore/zh-Hans.lproj/Localizable.strings`。
- Info.plist 无需改动：`NSAllowsArbitraryLoads` 已开（局域网明文 HTTP 可行），`NSLocalNetworkUsageDescription` 与远程配对 Bonjour 服务已声明。

---

## 4. RPPairing（iOS 18–26 一次性导入）

- **生成**：电脑上用 idevice 工具 `idevice_pair`，手机 USB 连接、解锁并信任后生成 **RPPairing 文件**。注意不是 lockdown 的 `.mobiledevicepairing` 文件，两者格式不同。
- **导入**：AirDrop / 分享 / 文件选择器 / 剪贴板粘贴进 App，一次即可；记录应存钥匙串。
- **oPenSSAI 的现状**：无线配对流程已产生 RPPairing 文件（0702 修好识别后，管理页可看到），第二阶段本机实现可直接复用已存的配对文件，**可能不需要用户再导一次**——需在真机上验证已存文件的类型与可用性。
- iOS 27 起可本机配对（无需电脑），本项目目标机 iOS 26 暂不依赖该路径。

---

## 5. oPenSSAI 已有的部件（第二阶段直接复用）

以下均已实测确认（2026-11-21）：

1. **`IDevice.xcframework` 已 vendored**：`Dependencies/minimuxer/DeviceGateway/Package.swift` 引用 SideStore/idevice v0.1.68-ss-3e55c84。下载解包后核对头文件 `idevice.h`，位置模拟的 C API 全在：
   - `location_simulation_new / _set / _clear / _free`
   - `remote_server_connect_rsd / remote_server_new / _free`
   - `tunnel_create_rppairing_with_options`、`rp_pairing_file_from_bytes`
   - 旧版 `lockdown_location_simulation_*`（iOS ≤ 16）
2. **`IdeviceGateway` 已打通 RPPairing 隧道**：`syncStart` 解析配对文件 → `ensureRPConnection` 调 `tunnel_create_rppairing_with_options` 得到 adapter + handshake → 各服务经 `*_connect_rsd` 连接。位置模拟只需在同一 adapter/handshake 上加 `remote_server_connect_rsd` + `location_simulation_new`。
3. **回环隧道已存在**：em_proxy + minimuxer 本机 VPN，App 已能访问本机设备服务（与 LocalDevVPN 同类机制）。
4. **配对文件管理已存在**：`PairingFileManager`（0702 已修识别），无线配对已产出 RPPairing 文件。

### 第二阶段待做（不在本轮）

- 在 `IdeviceGateway`（或新增的 Gateway API）里加**常驻会话**方法：现有 `performWithService` 是一次性的（用完即 free），而位置模拟需要长期持有 `LocationSimulationHandle` + 定时重发。需要新的生命周期管理（持有句柄、后台重发计时器、App 退后台时的会话保持策略）。
- AltStore target 需能调用 IDevice 模块：经 DeviceGatewayAPI 暴露方法（推荐，不动 Dependencies 结构），或给 App target 加 IDevice 依赖。
- 开发者模式检测与引导、RPPairing 可用性检测（复用已存文件 vs 引导导入）。
- 会话恢复：App 被杀/手机重启后，模拟状态由系统持有还是随会话消失，需真机验证并在界面上如实呈现。

---

## 6. 风险与未验证项

| # | 风险 / 未知 | 状态 | 下一步 |
|---|---|---|---|
| 1 | DVT 会话是否必须周期性重发坐标，还是保持连接即可 | 未验证 | helper 先按 5 秒重发；真机联调时试停重发看模拟是否掉 |
| 2 | helper 的 USB 路径在用户 Mac 上是否直通（usbmuxd、信任关系） | 未验证 | Mac 上跑 helper + `POST /location` 实测 |
| 3 | 已存的无线配对 RPPairing 文件能否直接驱动位置隧道 | 未验证 | 第二阶段真机验证；不行则走 `idevice_pair` 重新生成导入 |
| 4 | 用户手机是否已开开发者模式 | 未知 | 告知用户检查：设置 → 隐私与安全性 → 开发者模式 |
| 5 | App 退后台 / 被杀后模拟是否持续 | 未知 | helper 形态不受影响（会话在 Mac 侧）；本机形态需验证 |
| 5b | helper 退出 / Mac 休眠后，模拟状态是否残留、如何清除 | 未知 | 先重开 helper 再从 App 停止；重启手机可清除（已写进 helper README） |
| 6 | idevice 0.1.x API 尚不稳定（官方声明 0.2.0 前每个小版本可 breaking） | 已知 | helper 锁死 0.1.68；升级时重对 API |
| 7 | 模拟位置对需要真实位置的功能的影响（导航、急救、打车） | 已知 | 界面文案提醒：用完及时停止并恢复 |

## 7. 用户下一步要配合的（第一阶段联调）

1. 手机开**开发者模式**（设置 → 隐私与安全性 → 开发者模式），如未开，按提示重启开启。
2. Mac 与手机连同一局域网（或 USB 连 Mac）；Mac 上跑 `location-helper`（见 `tools/location-helper/README.md`）。
3. App 里 我的 → 虚拟定位 → Helper 地址填 Mac 的局域网 IP（如 `http://192.168.1.5:17878`），点连接测试，通了之后选坐标开始模拟。
4. 在地图 App 里确认位置已变；用完点「停止并恢复」。

## 8. 参考资料

- idevice（MIT）：https://github.com/jkcoxson/idevice — `dvt::location_simulation`、`tools/src/location_simulation.rs`、`ffi/src/dvt/location_simulation.rs`
- Locus（MIT）：https://github.com/ChrisMack32/Locus — README + SETUP.md（本机架构、RPPairing 导入）
- WrapPin 公开用户文档（仅原理）：https://github.com/suversal/WrapPin — Documentation/UserGuide.md、Installation.md（PolyForm 非商业许可，代码不可复用）
- Roam Control 文档：https://baike.dev/en/tools/roam-control
- libimobiledevice `idevicesetlocation`（旧机制）：https://github.com/libimobiledevice/libimobiledevice/blob/master/docs/idevicesetlocation.1
