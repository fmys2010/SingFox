# Builds the sing-box fork (XHTTP + VLESS Encryption) into core/ and refreshes
# the bundled JSON schema the config editor completes from.
param(
  [string]$Source = "E:\CC\Singbox With XHTTP"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "core\sing-box.exe"
$tags = "with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_gvisor,badlinkname,tfogo_checklinkname0"
$ldflags = "-X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
Push-Location $Source
try {
  $env:CGO_ENABLED = "0"
  go build -trimpath -tags $tags -ldflags $ldflags -o $out ./cmd/sing-box
  if ($LASTEXITCODE -ne 0) { throw "go build failed" }
} finally {
  Pop-Location
}
& $out version
& $out schema -o (Join-Path $root "assets\schema\sing-box.schema.json")

# The TUN helper service (service/), installed on demand from 设置 → TUN.
Push-Location (Join-Path $root "service")
try {
  go build -trimpath -ldflags "-s -w -buildid=" -o (Join-Path $root "core\singfox-service.exe") .
  if ($LASTEXITCODE -ne 0) { throw "service build failed" }
} finally {
  Pop-Location
}
