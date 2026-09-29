# ADR-0008 上游能力盘点（源码核验）与 A1/A4 重新定义

- 状态：已接受（2026-09-29，基于官方 KernelSU 源码核验）
- 核验对象：`upstream/KernelSU-main/`（官方 main 分支快照）

## 核验结论：上游已有的能力（此前被低估）

| 能力 | 上游实现位置 | 说明 |
| --- | --- | --- |
| 内置安全模式（内核侧） | `kernel/supercall/dispatch.c` `do_check_safemode()` + 音量键监听 | **首次开机画面后连按音量下 3 次**（press-release ×3，非长按）→ 安全模式；内核初始化时注册监听、`on_post_fs_data` 阶段注销 |
| 安全模式下的自动禁用 | `userspace/ksud/src/init_event.rs:36-59` | 安全模式 → `disable_all_modules()` + 跳过所有模块脚本、跳过 post-fs-data.d |
| 系统安全模式联动 | `userspace/ksud/src/utils.rs:152` | 读 `persist.sys.safemode` / `ro.sys.safemode`（系统安全模式也会让 KSU 进安全模式） |
| 启动日志采集（单轮） | `init_event.rs:26-29, 176-211` | logcat + dmesg 各采集 30s，保留一轮 `.old.log` |
| 手动救砖通道 | `rescue-from-bootloop.md` | `ksud module disable/uninstall <id>`（ADB/Recovery 可用）；删 `/data/adb/ksud`；删 `/metadata/*/ksu/modules.rc` |
| **preinit rc 注入面** | `userspace/ksud/src/module.rs:411-421`（`regenerate_preinit_rc`）、`defs.rs:27-30` | ksud 把启用模块的 `*.rc` 拼成 `/metadata/watchdog/ksu/modules.rc`（或 `/metadata/ksu/modules.rc`），**内核在更早的阶段注入**，早于 ksud 的 post-fs-data |

## 由此得出的 A1 重新定义（从"从零做"改为"做上游缺的那半"）

上游安全模式是**手动触发**（时机窗口短，官方文档明确承认可能错过：设备启动快或按得晚就进不去）。
我们做的是**自动失败判定 + 精准归因 + 大众向引导**，零内核改动：

**两段式实现（M1 原型，插入点已定位）**

1. **本轮的"启动开始"标记**：ksud `on_post_data_fs()` 最早期写入状态文件（例如 `/data/adb/slksu/boot.state = starting` + 递增轮次）。
2. **本轮结束标记**：在 `on_boot_completed()` 写入 `completed` 并清零失败计数。
3. **下一轮启动判定**：`on_post_data_fs()` 读到上次状态 ≠ `completed` → 失败计数 +1；达到阈值（默认 2）→
   - 本轮：`disable_all_modules()`（复用上游函数）+ 跳过脚本与挂载；
   - 为**下一轮**兜底：清理/重写 preinit rc（`regenerate_preinit_rc()`），让内核不再注入模块 rc；
   - 记录"嫌疑人"：结合模块变更时间线，指出最近新增/改动的模块。
4. **大众向呈现**：管理器首页提示"上次启动失败，已自动进入安全模式"，提供一键卸载/恢复/导出诊断包。

**边界（必须诚实地写进文档）**

- 本轮已经被内核 preinit 注入执行的模块 initrc **无法撤回**（官方文档同样限定）；自动判定对 initrc 类故障生效于**下一轮**。
- 当轮救砖仍属上游音量键 Safe Mode 的职责（内核侧，已有）。
- 阈值、是否只禁用"嫌疑模块"而非全部，M1 原型阶段定。

## A4 重新定义

上游已做单轮 logcat/dmesg 采集 → 我们做**增强**而非从零：
- 多轮留存（按启动轮次保留 N 份，失败轮优先保留）；
- 与 A1 联动：自动进入安全模式时自动打包"上一失败轮日志"；
- 一键诊断包（D1）统一出口。

## 对 ADR-0003 的影响

技术支点验证**加强**：除 metamodule 外，新增发现 **preinit rc 面**（比 metamodule 更早）。
结论：A1 可行，零内核改动；但必须按"两段式 + 下一轮生效"设计，不夸大宣传。