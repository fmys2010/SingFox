# Builds libbox.aar (the sing-box core as an Android library) from the fork
# into android/app/libs/. Needs Go, the Android SDK + NDK and a JDK.
param(
  [string]$Source = "E:\CC\Singbox With XHTTP",
  [string]$Sdk = "$env:LOCALAPPDATA\Android\Sdk",
  [string]$Abis = "android/arm64,android/amd64"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "android\app\libs\libbox.aar"
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null

$ndk = (Get-ChildItem (Join-Path $Sdk "ndk") | Sort-Object Name -Descending | Select-Object -First 1).FullName
$env:ANDROID_HOME = $Sdk
$env:ANDROID_NDK_HOME = $ndk
$env:PATH = "$(go env GOPATH)\bin;$env:PATH"
$tags = "with_quic,with_wireguard,with_utls,with_clash_api,with_gvisor,badlinkname,tfogo_checklinkname0"
$ldflags = "-X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

Push-Location $Source
try {
  go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.12
  go install github.com/sagernet/gomobile/cmd/gobind@v0.1.12
  gomobile init
  # One quoted string per argument: PowerShell would otherwise split on "." and spaces.
  $bindArgs = @('bind', '-v', '-o', $out, '-target', $Abis, '-androidapi', '24', '-javapkg=io.nekohasekai', '-libname=box',
    '-trimpath', '-buildvcs=false', "-ldflags=$ldflags", '-tags', $tags, './experimental/libbox')
  & gomobile @bindArgs
  if ($LASTEXITCODE -ne 0) { throw "gomobile bind failed" }
} finally {
  Pop-Location
}
