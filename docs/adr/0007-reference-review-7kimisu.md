# ADR-0007 参考项目评审：7kimisu（只参考，不抄袭）

- 状态：已评审（2026-09-29）
- 对象：[hartgerinktarcila-design/7kimisu](https://github.com/hartgerinktarcila-design/7kimisu) v2.28，GPL-3.0，官方 KernelSU 的第三方修改版
- 本地已归档：`reference/7kimisu-main/`（仅作阅读参考，不得复制代码进本仓库）

## 它实际做了什么（事实）

- **管理器**：壁纸/状态卡图片、扁平化、背景透明度、字体字重、主题调色板、导航图标自定义、开屏公告、下雪/巨魔雨特效。
- **隐身模式**：界面伪装成"未安装"，开关持久化在 `/data/adb/sevenk/stealth`；内核侧改 `GET_INFO` 行为，不上报 MANAGER 标志。
- **内核信任**：编译期写死管理器签名证书指纹（只信任本管理器）。
- **工程能力**：KMI 矩阵 `android12-5.10` → `android17-6.18`，用 DDK 镜像（`ghcr.io/ylarod/ddk-min:<KMI>`）出 `.ko`；`repack_apk.py` 把 ksud 作为 `libksud.so` 塞进 APK；`pack-source.sh` 随版本出源码包；构建参数化（`-PKSU_NAME/-PKSU_VERSION_NAME`）。
- **附加**：ksud 内嵌 Web 管理面板（自带 Nord/Dracula/Catppuccin 主题）、Miuix 风格 UI 变体、su 日志、模块仓库、迁移/恢复工具。

## 借鉴（思路与流程，代码自写）

1. **KMI/DDK 构建矩阵**：用 DDK 镜像按 KMI 出内核模块 —— 直接支撑 ADR-0006 的 Tier A/B 分级。
2. **发布流程**：参数化构建 + 把 ksud 作为 `libksud.so` 打进 APK + 随版本出源码包（GPL 合规动作）。
3. **隐身模式思路**：内核侧 `GET_INFO` 不上报 MANAGER 标志；状态持久化在 `/data/adb/` 下（与我们的"不新增暴露面"红线一致）。
4. **安全教训（直接吸收为我们的红线）**：
   - 任何"密令/拨号入口、广播入口"必须校验发送方（`SECRET_CODE` 非受保护广播，任何应用可伪造）+ 内容不进日志。
   - 不要自创模块管理机制（对方已在 v2.27 回退到上游写法）。

## 不借鉴

- 特效（下雪/巨魔雨）：与"大众向、可靠优先"定位不符；如做必须是可选且默认关闭。
- 内核写死签名信任集：会把管理器签名绑死，影响换机与开发者自编译；另开 ADR 评估（不默认采用）。
- 改名重打包工具链：我们的包名 `com.slksu.dtby` 已冻结，流程差异较大。

## 版权边界

- 本仓库**不得**包含其任何代码/资源/文案；仅允许在文档中记录"思路参考"并注明出处。
- 参考代码仅用于阅读理解，实现一律自行编写。