# SL-KernelSU

基于**官方 KernelSU** 的 Android 内核级 Root 分支。定位：**大众向、可靠优先、可美化**。

- 隐藏性目标：**不低于上游**；v1.x 起提供可选 SUSFS 内核工作线。不做"过检测/过银行"宣传。
- 主线差异化：自动安全模式（防砖）、启动失败日志留存、授权增强、日志中心与诊断包、模块快照回滚。
- 视觉：默认「水色」（玻璃拟态），可切换「樱粉柔光」皮肤包。

## 当前状态

- 阶段：**M0 骨架 + 上游源码就位 + 构建线就绪**（管理器 APK 可出包；内核模块走 CI）
- 基线：官方 KernelSU **v3.3.0**（官方最新发布，versionCode 32601；源码快照 `upstream/KernelSU-3.3.0/`，见 ADR-0001）
- 参考项目：7kimisu（`reference/7kimisu-main/`，仅阅读，见 ADR-0007）
- 包名：`com.slksu.dtby`（已冻结，见 ADR-0005）
- 本机验证目标：`6.6.118-android15-8`（KMI `android15-6.6`）
- 管理器：**v0.0.4-alpha**（versionCode **32602**，自签 RSA 2048 证书）
- 内核模块：GitHub Actions + DDK 编译（`.github/workflows/lkm.yml`），编译时注入我们的证书指纹（ADR-0009 / ADR-0011）

## Go / No-Go 门禁

开始功能开发前必须完成本机冒烟：**我们的 LKM（kernelsu.ko）在 `6.6.118-android15-8` 上正常 root 且不 bootloop**。
结论为 No-Go 时，ADR-0001 需重评。

## 目录结构

```
SL-KernelSU/
├─ docs/
│  ├─ adr/                     # 决策记录（0001–0011）
│  └─ roadmap.md               # 里程碑与功能优先级
├─ upstream/KernelSU-3.3.0/    # 官方 KernelSU 源码快照（基线，未改动；不入库）
├─ reference/7kimisu-main/     # 参考项目归档（只读参考，禁止复制代码；不入库）
├─ scripts/                    # 工具链安装 / 管理器构建 / 补丁清单（ADR-0010）
├─ .github/workflows/lkm.yml   # 内核模块 CI（手动触发，DDK 容器）
└─ manager/theme/              # 视觉 token 层（默认水色 / 樱粉皮肤包）
```

## 构建

### 管理器 APK（本地 Windows）

工具链与构建都在**纯 ASCII 路径**下（AGP 拒绝非 ASCII 项目路径，实测）：
- 工具链：`E:\slksu-tools\`（JDK 21 / android-sdk / PortableGit / keystore）
- 构建树：`E:\slksu-build\`（源码仍在本仓库 `upstream/`）
- 产物：本仓库 `dist/`
- Rust 工具链：未就位（M1 自编译 ksud 时需要）

```powershell
# 首次：装工具链（JDK + SDK 组件 + 自签密钥库，密钥必须 RSA 2048）
powershell -ExecutionPolicy Bypass -File scripts\setup-toolchain.ps1

# 出包：准备 ASCII 构建树 → 应用补丁 → 构建 → 收集 APK 到 dist/
powershell -ExecutionPolicy Bypass -File scripts\build-manager.ps1
```

当前版本：`com.slksu.dtby` / `SL-KernelSU` / `v0.0.4-alpha`（versionCode **32602**）。
最新产物：`dist/SL-KernelSU_v0.0.4-alpha_32602-release.apk`（10.3 MB，arm64-v8a + x86_64）。

> v0.0.1–v0.0.3 由旧密钥（RSA 4096）签名，其证书 1332 字节**超过内核 1024 字节上限**，已全部废弃（见 ADR-0009 复核补记）。

### 内核模块 kernelsu.ko（GitHub Actions）

`.github/workflows/lkm.yml`：Actions → Build LKM → Run workflow（默认 `android15-6.6`）。
编译时注入（上游 Kbuild 原生支持，**零内核代码改动**）：

- `KSU_EXPECTED_SIZE=0x0310`、`KSU_EXPECTED_HASH=b78f4c9d…`：我们的自签管理器证书（ADR-0009）
- `KSU_MANAGER_PACKAGE=com.slksu.dtby`：管理器识别同时钉死在包名上
- 版本锚点：`KSU_VERSION=32602`，与管理器 versionCode 对齐（构建日志有四项断言，不符即失败）

> 本阶段 `libksud.so` 取自官方发布版 APK；M1 起改为用 Rust 从源码编译（见 roadmap）。
> 脚本改动后必须以「UTF-8 带 BOM」保存，否则 Windows PowerShell 5.1 会按 GBK 解析中文导致语法错误。

## 许可证

与上游一致，不附加额外限制：`kernel/` GPL-2.0-only，其余（`manager/` `userspace/` `uapi/` 等）GPL-3.0-or-later。
发布前补齐 LICENSE 原文（从上游复制）与 fork 归属声明。