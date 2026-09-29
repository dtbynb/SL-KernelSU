# ADR-0011 内核模块（LKM）构建线：GitHub Actions + DDK + 指纹注入

- 状态：已接受（2026-09-29，方案 A，维护者拍板）
- 前置：ADR-0009（自签管理器必须有自编内核模块）

## 决策

内核模块（`kernelsu.ko`）由 GitHub Actions 用 DDK 容器编译，工作流 `.github/workflows/lkm.yml`：

- 镜像：`ghcr.io/ylarod/ddk-min:<KMI>-<DDK日期>`（官方同款；容器内已含对应 KMI 的内核源码与工具链）
- 源码：CI 内 `git clone` 上游 `tiann/KernelSU` 的**发布标签**（当前 `v3.3.0`），不依赖本仓库内的快照
- 注入（上游 Kbuild 原生支持，**零内核代码改动**）：
  - `KSU_EXPECTED_SIZE=0x0310`、`KSU_EXPECTED_HASH=b78f4c9d…dd3ebc`：我们的自签管理器证书（ADR-0009）
  - `KSU_MANAGER_PACKAGE=com.slksu.dtby`：管理器识别同时钉死在包名上
- 版本：上游 Kbuild 按 `30000 + git 提交数` 计算 `KSU_VERSION`；CI 用空的"版本锚点提交"把提交数
  对齐到 2602 → **KSU_VERSION = 32602**，与管理器 versionCode（32602）一致，避免首页"版本不匹配"提示
- 产物：`<kmi>_kernelsu.ko`（aarch64，已 `llvm-strip`），以 artifact 上传；x86_64 本轮不构建（目标设备是 arm64）

## 为什么用 CI 而不是本地

- 本机是 Windows，无 Docker / WSL / Linux 环境；DDK 依赖 Linux 内核构建环境
- CI 可复现、可审计（构建日志即证据），与 ADR-0006 的 Tier 分级一致

## 验证与断言

- 构建日志**断言四项**：KSU_VERSION、指纹大小、指纹哈希、管理器包名；任一不符即失败——
  不允许"静默编出一个错的 .ko"
- 真机验证（Tier A）：`android15-6.6` 刷入后管理器应显示工作中且能授权 root；其余 KMI 标注 Tier B 实验性

## 边界与后续

- 上游换发布标签时（如 v3.3.x）提交数会变：断言会把它暴露为显式失败，需要同步调整 `TARGET_KSU_VERSION` 与管理器版本号
- 本仓库目前不携带内核源码快照；后续内核侧改动（如 SUSFS 线）以"克隆内叠加提交/补丁"为入口
- 私钥不入库：CI 只用公开指纹（证书 DER 的 SHA-256），签名动作仍在本地完成