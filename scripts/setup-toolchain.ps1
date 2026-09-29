# SL-KernelSU 工具链准备（Windows / PowerShell）
# 一次性动作：解压 JDK 21 → 安装 Android SDK 组件 → 生成自签密钥库
# 注意：脚本内的口令仅供本地开发，正式发布必须换成独立密钥库（且不入库）
$ErrorActionPreference = 'Stop'

# 注意：工具链必须放在纯 ASCII 路径下（AGP/NDK/CMake 对非 ASCII 路径不友好，本项目实测踩坑）
$Root   = 'E:\slksu-tools'
$Dl     = Join-Path $Root 'dl'
$JdkZip = Join-Path $Dl 'jdk21.zip'
$JdkDir = Join-Path $Root 'jdk21'
$CmdZip = Join-Path $Dl 'cmdline-tools.zip'
$SdkDir = Join-Path $Root 'android-sdk'
$KsDir  = Join-Path $Root 'keystore'

# 与上游 manager 配置一致：compileSdk 37 / buildTools 37.0.0 / NDK 29.0.14206865
# 注意：新版 cmdline-tools 的包名用 "/" 分隔（旧的 ";" 语法与 sdkmanager 均已废弃）
$Packages = @(
  'platform-tools',
  'platforms/android-37.0',
  'build-tools/37.0.0',
  'ndk/29.0.14206865',
  'cmake/3.22.1',
  'cmake/3.31.6'
)

# 1) JDK 21
if (-not (Test-Path (Join-Path $JdkDir 'bin\java.exe'))) {
  Write-Host '[1/4] 解压 JDK 21 ...'
  New-Item -ItemType Directory -Force -Path $JdkDir | Out-Null
  Expand-Archive -Path $JdkZip -DestinationPath $JdkDir -Force
  $inner = Get-ChildItem $JdkDir -Directory | Select-Object -First 1
  if ($inner) {
    Get-ChildItem $inner.FullName | Move-Item -Destination $JdkDir -Force
    Remove-Item $inner.FullName -Recurse -Force
  }
}

$env:JAVA_HOME = $JdkDir
$env:PATH = "$JdkDir\bin;$env:PATH"
# 注意：java -version 写的是 stderr，在 EAP=Stop 下会被当成终止性错误 → 单独兜住
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $javaVer = (& java -version 2>&1 | Out-String).Trim().Split("`n")[0]
  Write-Host "Java: $javaVer"
} catch {
  Write-Host 'Java: 已就位（版本输出被跳过）'
} finally {
  $ErrorActionPreference = $prevEap
}

# 2) cmdline-tools
$sdkmanager = Join-Path $SdkDir 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path $sdkmanager)) {
  Write-Host '[2/4] 安装 cmdline-tools ...'
  $tmp = Join-Path $Root 'cmdline-tools-extract'
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $CmdZip -DestinationPath $tmp -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $SdkDir 'cmdline-tools') | Out-Null
  Move-Item (Join-Path $tmp 'cmdline-tools') (Join-Path $SdkDir 'cmdline-tools\latest') -Force
  Remove-Item $tmp -Recurse -Force
}

# 3) SDK 组件（逐个安装，失败不中断）
# 注意：sdkmanager/keytool 会往 stderr 写日志，EAP=Stop 下会误判为终止错误 → 这里放宽
$ErrorActionPreference = 'Continue'
Write-Host '[3/4] 安装 Android SDK 组件（首次会很慢）...'
$androidCli = Join-Path $SdkDir 'cmdline-tools\latest\bin\android.exe'
foreach ($p in $Packages) {
  Write-Host "  -> $p"
  & $androidCli "--sdk=$SdkDir" sdk install $p
  if ($LASTEXITCODE -ne 0) { Write-Warning "安装失败：$p（可稍后重试或换版本号）" }
}

# 4) 自签密钥库
Write-Host '[4/4] 生成自签密钥库 ...'
New-Item -ItemType Directory -Force -Path $KsDir | Out-Null
$ks = Join-Path $KsDir 'slksu.jks'
if (-not (Test-Path $ks)) {
  # 必须 RSA 2048：证书 DER 要 ≤1024 字节（内核 apk_sign.c 的 CERT_MAX_LENGTH 限制），4096 位会超限导致内核永远不认管理器
  & keytool -genkeypair -v -keystore $ks -alias slksu -keyalg RSA -keysize 2048 -validity 10950 `
    -storepass slksu-dev-2026 -keypass slksu-dev-2026 `
    -dname "CN=SL-KernelSU Dev, OU=Dev, O=SLKSU, C=CN"
}
Write-Host '工具链就绪。'