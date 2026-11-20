# oPenSSAI

中文优先的开源 iOS 侧载应用：不用电脑，在手机上用自己的 Apple ID 签名、安装、续签应用。

名字取自四家：AltStore + SideStore + iloader + Seal。代码全部来自开源仓库，Seal 本身是闭源软件，本项目不碰它的二进制、不抄它的任何东西——只是做到了它那个效果：中文界面 + 手机端签名。

## 功能

- **手机端签名**：用个人 Apple ID（免费证书）在手机上直接签名安装 IPA，不用电脑常驻
- **后台自动续签**：7 天证书到期前自动刷新，不掉签
- **Anisette 服务器管理**：服务器列表可选择、拖动排序、隐藏；支持自定义服务器目录 URL、导入自己的服务器 JSON 文件；支持自动轮换开关
- **JIT**：经 SideJIT 服务器为应用启用 JIT（上游注释称 iOS 17+ 的新 JIT 实现在 SideStore 里有已知问题，见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)）
- **自定义应用图标**：可为已安装应用更换图标（上游 AltAppIcons）
- **应用源与更新**：添加应用源、浏览、安装、更新
- **中文优先**：界面以中文为第一语言（CFBundleDevelopmentRegion 为 zh-Hans），不是英文之上的翻译包

## 安装（首次）

首次安装用官方版 [iloader](https://iloader.app)（https://github.com/nab138/iloader）：手机连电脑，登录 Apple ID，选择“导入任意 IPA”装入 oPenSSAI 的 IPA。

> 注意：官方版 iloader 的“导入 IPA”只安装，不自动放置配对文件（pairing file）。配对文件是手机端签名/续签的前提——没有它，oPenSSAI 装上后无法在手机上自己续签。当前做法：用 iloader 导出配对文件后手动放进 oPenSSAI（或用 oPenSSAI 自身的文件导入）；一键安装 + 自动放配对文件的体验需要一个小幅 fork 的安装器（见下）。

**安装器 fork（计划中）**：基于 iloader v2.4.2 做一个小幅 fork（改名、换图标、换 bundle id；默认安装地址指向 oPenSSAI 的 release；配对文件表加入 oPenSSAI；更新密钥与地址换成自己的）。改动点很少，见 [docs/SCAFFOLD-PLAN.md](docs/SCAFFOLD-PLAN.md)。在 fork 完成之前，先用官方版 iloader + 手动放配对文件验证链路。

iloader 本身已有完整的简体中文界面（fork 后中文现成，只需补几条 oPenSSAI 相关文案）。

## 开源血缘与许可证

| 来源 | 作用 | 许可证 |
|---|---|---|
| [SideStore](https://github.com/SideStore/SideStore) | 代码基底：手机端签名、Anisette、minimuxer、JIT、全部界面 | AGPLv3 |
| [AltStore](https://github.com/rileytestut/AltStore) | 上游原版：应用模型、商店/应用源、AltSign 签名框架 | AGPLv3 |
| [iloader](https://github.com/nab138/iloader) | 桌面端 USB 安装器：官方版用于首次安装；计划小幅 fork 做一键安装 + 自动放配对文件 | MIT（品牌另有 LICENSE-BRANDING 约束） |

本项目以 **AGPLv3** 发布。SideStore 与 AltStore 的 LICENSE、版权头、署名全部保留；修改处按 AGPLv3 要求标注。

Fork 点：SideStore `4f3d18d98c5fbee72c80f787ceb2e8e09ded60a6`（2026-11-20 克隆，`--depth 1 --recurse-submodules`）；子模块 SideSign `752d1ef6`、minimuxer `12be70dc`，已转为普通目录随仓库携带（不再是 git 子模块）。

## 构建

要求：macOS + Xcode 15+，Rustup（`brew install rustup`）。

```sh
git clone --recurse-submodules https://github.com/SheldonJoO/oPenSSAI.git
cd oPenSSAI
cp CodeSigning.xcconfig.sample CodeSigning.xcconfig
# 填入你的 DEVELOPMENT_TEAM
open AltStore.xcodeproj
```

打包 IPA（命令行）：

```sh
make build fakesign ipa
```

> 注意：2026 年 11 月 GitHub 账号的免费 Actions 分钟已用完，12 月 1 日重置。在此之前用 Mac 上 Xcode 图形界面本地构建；12 月 1 日之后可用 GitHub Actions（nightly）构建。

首次在真机上使用前，需把配对文件放进应用（见上文“安装”一节），否则无法在手机上签名/续签。

## 中文优先是怎么做的

- `CFBundleDevelopmentRegion` 为 `zh-Hans`，中文是 base 语言，不是备选本地化
- `Localizable.strings`、各 storyboard 的 `.strings` 全部中文
- 出包后的验收步骤见 [docs/SCAFFOLD-PLAN.md](docs/SCAFFOLD-PLAN.md)（检查 IPA 内 `zh-Hans.lproj`、真机中文界面无英文回退）

上一次汉化尝试（SideStore-zh-Hans）出现过“翻译文件都在、App 却显示英文”的问题，本项目把本地化接线和出包验收写进了流程，不再重犯。

## 参与

欢迎提 Issue / PR。注意：如果要把改动贡献回上游 SideStore，请先读 SideStore 的 AGENTS.md——上游对 AI 生成内容参与贡献有严格限制（人类审阅资源稀缺），与上游维护者的沟通必须是人类对人类。

## 致谢

- Riley Testut（AltStore 原作者）
- SideStore 全体贡献者
- nab138（iloader）
- jkcoxson（minimuxer / em_proxy / idevice）
