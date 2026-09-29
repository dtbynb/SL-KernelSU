# 构建 SL-KernelSU 管理器 APK（Windows / PowerShell）
#
# 重要约束（都是实际踩过的坑，别改）：
#   1) 本文件必须以「UTF-8 带 BOM」保存，否则 Windows PowerShell 5.1 会按 GBK 解析中文 → 语法错误
#   2) AGP 拒绝非 ASCII 项目路径 → 构建在 ASCII 目录（默认 E:\slksu-build）内进行，源码仍在原仓库
#   3) 构建树需要仓库根的 uapi/；上游的 manager/app/src/main/cpp/uapi 是符号链接，复制后会失效 → 必须用真实目录替换
#   4) Gradle 的 versionName/versionCode 来自 git → 构建树内要初始化本地 git 仓库并打标签
#   5) 必须设置 ANDROID_HOME（仅 local.properties 不够，实测 AGP 读不到）
#   6) libksud.so 目前取自官方发布版 APK（M1 起改为用 Rust 从源码编译，见 docs/roadmap.md）
#   7) 签名密钥库必须 RSA 2048（证书 784B/0x0310，需 ≤1024；指纹见 ADR-0009，内核模块编译时注入同一指纹）
#   8) APK 内置我们的内核模块（manager/prebuilt/*_kernelsu.ko → assets/slksu/），使「直接安装」开箱即用
#
# 用法：先跑 scripts/setup-toolchain.ps1，再运行本脚本
param(
  [string]$Root        = 'E:\slksu-tools',
  [string]$Repo        = 'e:\软件\AI项目\SL-KernelSU',
  [string]$Upstream    = 'KernelSU-3.3.0',
  [string]$BuildDir    = 'E:\slksu-build',
  [string]$PackageName = 'com.slksu.dtby',
  [string]$AppName     = 'SL-KernelSU',
  [string]$VersionTag  = 'v0.0.7-alpha',
  [int]$VersionCode    = 32602   # 基准：官方 v3.3.0 为 32601；我们的版本号取基准+1，保证不被判为降级
)

$ErrorActionPreference = 'Continue'
$Jdk    = Join-Path $Root 'jdk21'
$Sdk    = Join-Path $Root 'android-sdk'
$GitCmd = Join-Path $Root 'PortableGit\cmd'
$GitExe = Join-Path $GitCmd 'git.exe'
$KsPath = Join-Path $Root 'keystore\slksu.jks'
$src    = Join-Path $Repo "upstream\$Upstream"
$jni    = Join-Path $src 'manager\app\src\main\jniLibs'

$env:JAVA_HOME = $Jdk
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk
$env:PATH = "$Jdk\bin;$GitCmd;$env:PATH"

# 0) 确保源树里有 libksud.so（从官方发布版 APK 提取）
if (-not (Test-Path (Join-Path $jni 'arm64-v8a\libksud.so'))) {
  Write-Host '[0/4] 提取 libksud.so ...'
  $apk = Join-Path $Root 'dl\kernelsu-official.apk'
  $zipCopy = Join-Path $Root 'dl\kernelsu-official.zip'
  Copy-Item $apk $zipCopy -Force
  $tmp = Join-Path $Root 'ksud-extract'
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  Expand-Archive -Path $zipCopy -DestinationPath $tmp -Force
  foreach ($abi in @('arm64-v8a', 'x86_64')) {
    $s = Join-Path $tmp "lib\$abi\libksud.so"
    if (Test-Path $s) {
      New-Item -ItemType Directory -Force -Path (Join-Path $jni $abi) | Out-Null
      Copy-Item $s (Join-Path $jni "$abi\libksud.so") -Force
      Write-Host "  libksud.so -> $abi"
    }
  }
}

# 1) 准备 ASCII 构建树
Write-Host '[1/4] 准备构建树（ASCII 路径）...'
$manager = Join-Path $BuildDir 'manager'
if (Test-Path $BuildDir) { Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $manager | Out-Null
Copy-Item (Join-Path $src 'manager\*') $manager -Recurse -Force
foreach ($d in @('uapi', 'userspace', 'js')) {
  $p = Join-Path $src $d
  if (Test-Path $p) { Copy-Item $p (Join-Path $BuildDir $d) -Recurse -Force }
}
$cppUapi = Join-Path $manager 'app\src\main\cpp\uapi'
Remove-Item -LiteralPath $cppUapi -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $BuildDir 'uapi') $cppUapi -Recurse -Force
Set-Content (Join-Path $manager 'local.properties') ("sdk.dir=" + ($Sdk -replace '\\', '/'))
Add-Content (Join-Path $manager 'gradle.properties') "`nandroid.overridePathCheck=true"

# 1.5) 应用我们的补丁（更新源 / 默认主题色 / 内置内核模块）
Write-Host '[1.5/4] 应用补丁 ...'
& (Join-Path $Repo 'scripts\apply-patches.ps1') -ManagerDir $manager
if (-not $?) { throw '补丁脚本失败，构建中止' }

# 1.6) 内置内核模块：manager/prebuilt/*_kernelsu.ko → app/src/main/assets/slksu/
$prebuilt = Join-Path $Repo 'manager\prebuilt'
if (Test-Path $prebuilt) {
  $assetsSlksu = Join-Path $manager 'app\src\main\assets\slksu'
  New-Item -ItemType Directory -Force -Path $assetsSlksu | Out-Null
  Get-ChildItem $prebuilt -Filter '*_kernelsu.ko' | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $assetsSlksu $_.Name) -Force
    Write-Host "  内置 LKM: $($_.Name)"
  }
}

# 1.7) 源码覆盖层：manager/overlay/** → app/src/main/java/**（新增文件用覆盖层，修改用补丁，见 ADR-0010）
$overlay = Join-Path $Repo 'manager\overlay'
if (Test-Path $overlay) {
  Get-ChildItem $overlay -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($overlay.Length).TrimStart('\')
    $dst = Join-Path $manager ("app\src\main\java\" + $rel)
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $_.FullName $dst -Force
    Write-Host "  覆盖层: $rel"
  }
}

# 1.8) 资源覆盖层：manager/assets/** → app/src/main/assets/**（内置壁纸等）
$assetsSrc = Join-Path $Repo 'manager\assets'
if (Test-Path $assetsSrc) {
  Get-ChildItem $assetsSrc -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($assetsSrc.Length).TrimStart('\')
    $dst = Join-Path $manager ("app\src\main\assets\" + $rel)
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $_.FullName $dst -Force
    Write-Host "  资源: $rel"
  }
}

# 2) 构建树内初始化 git（versionName / versionCode 来源）
Write-Host '[2/4] 初始化构建树 git ...'
& $GitExe -C $manager init -b main 2>&1 | Out-Null
& $GitExe -C $manager add -A 2>&1 | Out-Null
& $GitExe -C $manager -c user.name="SLKSU" -c user.email="dev@slksu.local" commit -m "build tree" 2>&1 | Out-Null
& $GitExe -C $manager tag $VersionTag 2>&1 | Out-Null
Write-Host ("  versionName = " + (& $GitExe -C $manager describe --tags --always))

# 3) 编译
Write-Host '[3/4] gradle assembleRelease ...'
Push-Location $manager
& .\gradlew.bat :app:assembleRelease --no-daemon `
  "-PKSU_PACKAGE_NAME=$PackageName" "-PKSU_NAME=$AppName" "-PKSU_VERSION_CODE=$VersionCode" `
  "-PKEYSTORE_FILE=$KsPath" '-PKEYSTORE_PASSWORD=slksu-dev-2026' `
  '-PKEY_ALIAS=slksu' '-PKEY_PASSWORD=slksu-dev-2026'
$code = $LASTEXITCODE
Pop-Location

# 4) 收集产物
Write-Host '[4/4] 收集产物 ...'
$dist = Join-Path $Repo 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Get-ChildItem (Join-Path $manager 'app\build\outputs\apk') -Recurse -Filter *.apk -ErrorAction SilentlyContinue |
  ForEach-Object { Copy-Item $_.FullName (Join-Path $dist $_.Name) -Force; Write-Host "  APK: $($_.Name)" }
Write-Host "gradle_exit=$code"
Get-ChildItem $dist -ErrorAction SilentlyContinue |
  Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } |
  Format-Table -AutoSize | Out-String | Write-Host