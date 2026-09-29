# ADR-0003 技术支点：ksud 扩展 + 自研 metamodule（用户空间）

- 状态：**已部分验证**（注入点已通过源码核验，见 ADR-0008）；实现细节待 M1 原型
- 责任：维护者 + 真机冒烟

## 背景

- A1 安全模式必须在"模块挂载 / 模块脚本执行"之前介入；A2 快照回滚、A4 失败日志同理。
- 硬约束：零内核改动（无编内核能力）。
- 事实基础（已源码核验）：
  - KernelSU 的模块挂载**委托给 metamodule**（用户空间组件，如 meta-overlayfs）；
  - 脚本 / sepolicy / system.prop 由 ksud 的 init 事件统一处理；
  - **preinit rc 注入面**（`/metadata/*/ksu/modules.rc`）比 post-fs-data 更早，由 ksud 生成、内核注入。

## 决策

在用户空间的三个注入点做扩展：

1. **ksud `on_post_data_fs()` 最早期**（`init_event.rs:36` 附近）：自动失败判定 → 复用上游 `disable_all_modules()` 实现自动安全模式；生效顺序天然在"脚本执行 / metamodule 挂载"之前。
2. **preinit rc 生成点**（`module.rs:411` `regenerate_preinit_rc`）：作为"下一轮兜底"，阻止内核继续注入模块 rc。
3. **自研/定制 metamodule（挂载器）**：挂载兼容、快照与回滚（A2）的落点。
4. 管理器负责"一键安装我们的 metamodule"引导（大众向必需）。

## 备选与被否原因

| 备选 | 否因 |
| --- | --- |
| 内核侧实现 | 需要编译内核，与能力约束冲突 |
| 纯管理器实现 | 启动阶段无法接管，自动安全模式不可靠 |
| 只用 metamodule | 覆盖不到 preinit rc 面，故障类型覆盖不全（见 ADR-0008 边界） |

## 后果

- 正向：零内核改动；复用上游既有安全模式基础设施（`disable_all_modules` / preinit rc）；组件可独立热更新；与上游 merge 友好。
- 负向：自动判定对 initrc 类故障**下一轮才生效**（诚实限界）；依赖 metamodule 安装率。

## 可逆性与重评触发

- 属**双向门**。
- 触发条件：上游内置"自动失败判定" → 删除自研，回归上游。