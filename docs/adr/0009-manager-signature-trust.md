# ADR-0009 管理器签名信任：自签管理器必须有自编内核模块

- 状态：已接受（2026-09-29，源码核验）
- 核验对象：`upstream/KernelSU-3.3.0/kernel/`

## 事实（源码核验）

- `kernel/Kbuild` 硬编码管理器证书指纹：`KSU_EXPECTED_SIZE := 0x033b`、`KSU_EXPECTED_HASH := c371061b...`。
- `kernel/manager/apk_sign.c` 校验管理器 APK 的 **V2 签名**（证书大小 + SHA256）是否与上述值一致；不一致则不认作管理器。

## 结论

我们的自签管理器 APK（证书 `CN=SL-KernelSU Dev`，SHA-256 `e3429afc...`）**无法被官方 LKM 认作管理器**：
即使刷入官方 LKM，应用内仍会显示"未安装"。

→ 要在设备上真正 root，必须提供**用我们证书指纹编译的内核模块**（编译时通过
`KSU_EXPECTED_SIZE` / `KSU_EXPECTED_HASH` 指向我们的证书）。

## 影响

- M5 内核线从"可选的隐藏升级（SUSFS）"升级为**root 能力的前置条件**。
- 发布物必须成对：管理器 APK（我们的签名）+ 各 KMI 的内核模块（我们证书指纹）。
- 与 ADR-0007 记录的参考项目做法一致（7kimisu 同样写死自己的证书指纹）。

## 缓解与流程

- 内核线沿用官方 DDK / LKM 构建流程（按 KMI 矩阵出 `.ko`），CI 承担编译（见 ADR-0006 分级）。
- 证书指纹取自本地密钥库（`keytool -exportcert` + `shasum`），编译时注入；**私钥不入库**。
- 本地开发期：可先只验证管理器可用性（UI/安装），root 验证等内核线具备后再说。

## 可逆性

由上游机制决定，无可逆空间；若未来上游改为"首次使用时记录签名"，再评估。

## 复核补记：证书体积硬上限（2026-09-29，决定密钥规格）

`apk_sign.c` 在比对前还有一道硬限制：`#define CERT_MAX_LENGTH 1024`，证书 DER 超过 1024 字节**直接判负**。

我们最初的密钥库用 RSA 4096 生成，证书 DER 为 1332 字节（`0x0534`）——**超限**：即便把指纹编进内核，也永远匹配不上。
已重新生成密钥库（RSA 2048）：

| 项 | 旧（已废弃） | 现行 |
| --- | --- | --- |
| 密钥规格 | RSA 4096 | **RSA 2048** |
| 证书 DER 大小 | 1332（0x0534，超限） | **784（0x0310）** |
| 证书 SHA-256 | e3429afc…f556789 | **b78f4c9d27d3758ebf81ee6ad93caecd474400a36aefe1e78befb98c97dd3ebc** |

- 旧密钥库备份于 `E:\slksu-tools\keystore\slksu-rsa4096.jks.bak`；其签名的 APK（v0.0.1–v0.0.3）全部废弃。
- 内核模块编译注入（见 ADR-0011）：`KSU_EXPECTED_SIZE=0x0310`、`KSU_EXPECTED_HASH=b78f…`，另加
  `KSU_MANAGER_PACKAGE=com.slksu.dtby`（上游 Kbuild 支持，把"谁算管理器"同时钉死在包名上）。
- 自 v0.0.4 起管理器 APK 用新密钥签名；`scripts/setup-toolchain.ps1` 已固化 RSA 2048（附原因注释），防止重蹈覆辙。