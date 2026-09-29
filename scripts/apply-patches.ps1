# SL-KernelSU 补丁清单：在构建树内对上游代码做最小改动
#
# 设计原则：
#   - 每条补丁 = 「文件 + 原文 + 新文」，应用后断言成功；上游一旦变更会**显式报错**，不会静默失效
#   - 改动保持最小且可追溯，便于后续与上游同步（见 ADR-0010）
#   - 本文件必须以「UTF-8 带 BOM」保存，否则 Windows PowerShell 5.1 会按 GBK 解析中文导致语法错误
param(
  [Parameter(Mandatory = $true)][string]$ManagerDir
)

$Patches = @(
  @{
    Note = '更新检查指向自建更新源（尚未发布仓库 => 不再误报“有新版本”）'
    File = 'app\src\main\java\me\weishu\kernelsu\ui\util\Downloader.kt'
    Old  = 'val url = "https://api.github.com/repos/tiann/KernelSU/releases/latest"'
    New  = 'val url = "https://api.github.com/repos/SL-KernelSU/SL-KernelSU/releases/latest"  // SL-KernelSU: 自建更新源（未发布时等价于关闭更新提示）'
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
  }
)

$failed = @()
foreach ($p in $Patches) {
  $path = Join-Path $ManagerDir $p.File
  if (-not (Test-Path $path)) { $failed += "文件不存在：$($p.File)"; continue }

  $text = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false)))
  if ($text.Contains($p.New)) { Write-Host "  [已应用] $($p.Note)"; continue }
  if (-not $text.Contains($p.Old)) { $failed += "未找到原文（上游可能已变更）：$($p.File)"; continue }

  $text = $text.Replace($p.Old, $p.New)
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "  [已打补丁] $($p.Note)"
}

if ($failed.Count -gt 0) {
  foreach ($f in $failed) { Write-Warning $f }
  throw '补丁未能全部应用，构建中止'
}
Write-Host ("补丁完成：{0} 条" -f $Patches.Count)