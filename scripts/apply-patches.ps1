# SL-KernelSU 补丁清单：在构建树内对上游代码做最小改动
#
# 设计原则：
#   - 每条补丁 = 「文件 + 原文 + 新文」，应用后断言成功；上游一旦变更会**显式报错**，不会静默失效
#   - 改动保持最小且可追溯，便于后续与上游同步（见 ADR-0010）
#   - 多行补丁做换行符归一化（CRLF/LF 均可匹配），写回时恢复原文件的换行风格
#   - 本文件必须以「UTF-8 带 BOM」保存，否则 Windows PowerShell 5.1 会按 GBK 解析中文导致语法错误
param(
  [Parameter(Mandatory = $true)][string]$ManagerDir
)

$KsuCli = 'app\src\main\java\me\weishu\kernelsu\ui\util\KsuCli.kt'

# —— SL 内置内核模块：辅助函数（插在 writeLkmFile 之前）——
$BundledLkmHelpers = @'
// SL-KernelSU: 从 APK 内置资源提取与本分支签名匹配的内核模块（assets/slksu/<kmi>_kernelsu.ko）
// 目的：让「直接安装」像其他分支一样开箱即用，无需手动选择 .ko 文件
private fun writeBundledLkmFile(kmi: String?): File? {
    if (kmi.isNullOrBlank()) return null
    return try {
        val file = File(ksuApp.cacheDir, "kernelsu-bundled-lkm.ko")
        ksuApp.assets.open("slksu/${kmi}_kernelsu.ko").use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        }
        file
    } catch (e: Exception) {
        Log.w(TAG, "bundled LKM for $kmi not available: ${e.message}")
        null
    }
}

// SL-KernelSU: 同步读取当前设备 KMI（用于自动选择内置模块）
private fun getCurrentKmiBlocking(): String? = try {
    ShellUtils.fastCmd(getRootShell(), "${getKsuDaemonPath()} boot-info current-kmi").trim().ifBlank { null }
} catch (e: Exception) {
    Log.w(TAG, "get current kmi failed: ${e.message}")
    null
}

private fun writeLkmFile(lkm: LkmSelection): File? {
'@

# —— 「直接安装 / 修补本地镜像」：默认用内置模块（按当前设备 KMI）——
$InstallBootOld = @'
    val lkmFile = writeLkmFile(lkm)
    if (lkmFile != null) {
        cmd += " -m ${lkmFile.absolutePath}"
    } else if (lkm is LkmSelection.KmiString) {
        cmd += " --kmi ${lkm.value}"
    }

    if (bootFile != null) {
'@

$InstallBootNew = @'
    // SL-KernelSU: 未手动选择 .ko 时，使用 APK 内置的内核模块（按当前设备 KMI 取）
    val lkmFile = writeLkmFile(lkm) ?: writeBundledLkmFile(
        (lkm as? LkmSelection.KmiString)?.value ?: getCurrentKmiBlocking()
    )
    if (lkmFile != null) {
        cmd += " -m ${lkmFile.absolutePath}"
    }
    if (lkm is LkmSelection.KmiString) {
        cmd += " --kmi ${lkm.value}"
    }

    if (bootFile != null) {
'@

# —— 「下载镜像并修补」：默认用内置模块（按目标镜像 KMI）——
$DownloadBootOld = @'
    val lkmFile = writeLkmFile(lkm)
    if (lkmFile != null) {
        cmd += " -m ${lkmFile.absolutePath}"
    } else if (lkm is LkmSelection.KmiString) {
        cmd += " --kmi ${lkm.value}"
    }
    if (autoKmi != null) cmd += " --kmi $autoKmi"
'@

$DownloadBootNew = @'
    // SL-KernelSU: 未手动选择 .ko 时，使用 APK 内置的内核模块（按目标镜像 KMI 取）
    val lkmFile = writeLkmFile(lkm) ?: writeBundledLkmFile(
        (lkm as? LkmSelection.KmiString)?.value ?: autoKmi
    )
    if (lkmFile != null) {
        cmd += " -m ${lkmFile.absolutePath}"
    }
    if (lkm is LkmSelection.KmiString) {
        cmd += " --kmi ${lkm.value}"
    }
    if (autoKmi != null) cmd += " --kmi $autoKmi"
'@

# —— 壁纸：主题包一层壁纸透光层 ——
$ThemeWallpaperOld = @'
    when (uiMode) {
        UiMode.Miuix -> MiuixKernelSUTheme(
            appSettings = appSettings,
            content = content
        )

        UiMode.Material -> MaterialKernelSUTheme(
            appSettings = appSettings,
            content = content
        )
    }
}
'@

$ThemeWallpaperNew = @'
    // SL-KernelSU: 应用内背景壁纸（透光层，画在全部页面之上）
    SlWallpaper {
        when (uiMode) {
            UiMode.Miuix -> MiuixKernelSUTheme(
                appSettings = appSettings,
                content = content
            )

            UiMode.Material -> MaterialKernelSUTheme(
                appSettings = appSettings,
                content = content
            )
        }
    }
}
'@

# —— 壁纸：设置页（Miuix）新增一行 ——
$SettingsMiuixRowOld = @'
                            onClick = actions.onOpenTheme
                        )
                    }
'@

$SettingsMiuixRowNew = @'
                            onClick = actions.onOpenTheme
                        )
                        // SL-KernelSU: 应用内背景壁纸设置
                        me.weishu.kernelsu.ui.theme.SlWallpaperSettingRow()
                    }
'@

$Patches = @(
  @{
    Note = '更新检查指向自建更新源（尚未发布仓库 => 不再误报“有新版本”）'
    File = 'app\src\main\java\me\weishu\kernelsu\ui\util\Downloader.kt'
    Old  = 'val url = "https://api.github.com/repos/tiann/KernelSU/releases/latest"'
    New  = 'val url = "https://api.github.com/repos/dtbynb/SL-KernelSU/releases/latest"  // SL-KernelSU: 自建更新源（未发布时等价于关闭更新提示）'
  },
  @{
    Note = '默认主题种子色改为「水色」0xFF2E9BD6（开箱即用水蓝配色，而非系统取色）'
    File = 'app\src\main\java\me\weishu\kernelsu\data\repository\SettingsRepositoryImpl.kt'
    Old  = 'get() = prefs.getInt("key_color", 0)'
    New  = 'get() = prefs.getInt("key_color", 0xFF2E9BD6.toInt())'
  },
  @{
    Note = '支持 -PKSU_VERSION_CODE 显式指定版本号（用于对齐/超过官方版本号，避免被误判为旧版）'
    File = 'build.gradle.kts'
    Old  = 'extra["managerVersionCode"] = getVersionCode()'
    New  = 'extra["managerVersionCode"] = project.findProperty("KSU_VERSION_CODE")?.toString()?.toIntOrNull() ?: getVersionCode()  // SL-KernelSU'
  },
  @{
    Note = '（内置模块）加入读取 APK 内置 .ko 与当前 KMI 的辅助函数'
    File = $KsuCli
    Old  = 'private fun writeLkmFile(lkm: LkmSelection): File? {'
    New  = $BundledLkmHelpers
  },
  @{
    Note = '（内置模块）「直接安装/修补本地镜像」未手动选 .ko 时使用内置模块（当前设备 KMI）'
    File = $KsuCli
    Old  = $InstallBootOld
    New  = $InstallBootNew
  },
  @{
    Note = '（内置模块）「下载镜像并修补」未手动选 .ko 时使用内置模块（目标镜像 KMI）'
    File = $KsuCli
    Old  = $DownloadBootOld
    New  = $DownloadBootNew
  },
  @{
    Note = '（皮肤）默认开启模糊（玻璃拟态观感）'
    File = 'app\src\main\java\me\weishu\kernelsu\data\repository\SettingsRepositoryImpl.kt'
    Old  = 'get() = prefs.getBoolean("enable_blur", false)'
    New  = 'get() = prefs.getBoolean("enable_blur", true)  // SL-KernelSU: 默认开启模糊'
  },
  @{
    Note = '（皮肤）默认开启悬浮底栏'
    File = 'app\src\main\java\me\weishu\kernelsu\data\repository\SettingsRepositoryImpl.kt'
    Old  = 'get() = prefs.getBoolean("enable_floating_bottom_bar", false)'
    New  = 'get() = prefs.getBoolean("enable_floating_bottom_bar", true)  // SL-KernelSU: 默认悬浮底栏'
  },
  @{
    Note = '（皮肤）默认开启悬浮底栏毛玻璃'
    File = 'app\src\main\java\me\weishu\kernelsu\data\repository\SettingsRepositoryImpl.kt'
    Old  = 'get() = prefs.getBoolean("enable_floating_bottom_bar_blur", false)'
    New  = 'get() = prefs.getBoolean("enable_floating_bottom_bar_blur", true)  // SL-KernelSU: 默认底栏毛玻璃'
  },
  @{
    Note = '（皮肤）配色板置顶「水色（默认）/ 樱粉柔光」两个皮肤色'
    File = 'app\src\main\java\me\weishu\kernelsu\ui\theme\Colors.kt'
    Old  = 'val keyColorOptions = listOf('
    New  = "val keyColorOptions = listOf(`n    // SL-KernelSU 皮肤色：水色（默认）/ 樱粉柔光`n    Color(0xFF2E9BD6).toArgb(),`n    Color(0xFFFF9CA8).toArgb(),"
  },
  @{
    Note = '（皮肤）首次运行自动套用「水色玻璃拟态」皮肤（SlSkin.applyDefaultOnce）'
    File = 'app\src\main\java\me\weishu\kernelsu\ui\theme\Theme.kt'
    Old  = "        val colorMode = ColorMode.fromValue(colorModeValue)`n        val keyColor = repo.keyColor"
    New  = "        // SL-KernelSU: 首次运行套用默认皮肤「水色玻璃拟态」（仅一次，之后尊重用户设置）`n        SlSkin.applyDefaultOnce()`n`n        val colorMode = ColorMode.fromValue(colorModeValue)`n        val keyColor = repo.keyColor"
  },
  @{
    Note = '（壁纸）主题包一层壁纸透光层（SlWallpaper）'
    File = 'app\src\main\java\me\weishu\kernelsu\ui\theme\Theme.kt'
    Old  = $ThemeWallpaperOld
    New  = $ThemeWallpaperNew
  },
  @{
    Note = '（壁纸）设置页（Miuix）新增「壁纸」行（含选择对话框）'
    File = 'app\src\main\java\me\weishu\kernelsu\ui\screen\settings\SettingsMiuix.kt'
    Old  = $SettingsMiuixRowOld
    New  = $SettingsMiuixRowNew
  }
)

$failed = @()
foreach ($p in $Patches) {
  $path = Join-Path $ManagerDir $p.File
  if (-not (Test-Path $path)) { $failed += "文件不存在：$($p.File)"; continue }

  $text = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false)))
  $usesCrlf = $text.Contains("`r`n")
  $textLf = $text.Replace("`r`n", "`n")
  $oldLf = $p.Old.Replace("`r`n", "`n")
  $newLf = $p.New.Replace("`r`n", "`n")

  if ($textLf.Contains($newLf)) { Write-Host "  [已应用] $($p.Note)"; continue }
  if (-not $textLf.Contains($oldLf)) { $failed += "未找到原文（上游可能已变更）：$($p.File)"; continue }

  $resultLf = $textLf.Replace($oldLf, $newLf)
  $result = if ($usesCrlf) { $resultLf.Replace("`n", "`r`n") } else { $resultLf }
  [System.IO.File]::WriteAllText($path, $result, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "  [已打补丁] $($p.Note)"
}

if ($failed.Count -gt 0) {
  foreach ($f in $failed) { Write-Warning $f }
  throw '补丁未能全部应用，构建中止'
}
Write-Host ("补丁完成：{0} 条" -f $Patches.Count)