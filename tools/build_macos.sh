#!/usr/bin/env bash
# Builds SingFox for macOS (Apple Silicon arm64 and/or Intel x86_64) as .app
# and .dmg packages, bundling the sing-box core from singbox-x or core/.
#
# Usage:
#   tools/build_macos.sh [--arch arm64|x86_64|both] [--source path/to/singbox-x]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="both"
SOURCE="${SINGBOX_SOURCE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ARCH="${2:?}"; shift 2 ;;
    --source) SOURCE="${2:?}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$ARCH" in
  arm64) ARCHS=(arm64) ;;
  x86_64|amd64) ARCHS=(x86_64) ;;
  both|all) ARCHS=(arm64 x86_64) ;;
  *) echo "Unsupported --arch: $ARCH (expected arm64, x86_64, or both)" >&2; exit 2 ;;
esac

VERSION="$(grep -E '^version:' "$ROOT/pubspec.yaml" | head -n1 | sed -E 's/^version:[[:space:]]*([^+]+).*/\1/' | tr -d '\r')"
TAGS="with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_gvisor,badlinkname,tfogo_checklinkname0"
LDFLAGS="-X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

build_core() {
  local goarch="$1"
  local dest="$2"
  if [[ -n "$SOURCE" && -d "$SOURCE" ]]; then
    echo "Building sing-box (darwin/$goarch) from $SOURCE..."
    mkdir -p "$(dirname "$dest")"
    (
      cd "$SOURCE"
      CGO_ENABLED=0 GOOS=darwin GOARCH="$goarch" \
        go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -o "$dest" ./cmd/sing-box
    )
    chmod +x "$dest"
    return 0
  fi
  if [[ -x "$ROOT/core/sing-box" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$ROOT/core/sing-box" "$dest"
    chmod +x "$dest"
    return 0
  fi
  echo "No sing-box binary found (pass --source path/to/singbox-x or place core/sing-box)" >&2
  return 1
}

build_arch() {
  local mac_arch="$1"
  local go_arch="arm64"
  local label="arm64"
  if [[ "$mac_arch" == "x86_64" ]]; then
    go_arch="amd64"
    label="x64"
  fi

  echo "==> Building SingFox for macOS ($mac_arch)..."
  cd "$ROOT"
  flutter pub get
  flutter build macos --release --config-only

  local build_dir="$ROOT/build/macos"
  xcodebuild \
    -workspace "$ROOT/macos/Runner.xcworkspace" \
    -scheme Runner \
    -configuration Release \
    -derivedDataPath "$build_dir" \
    -destination "generic/platform=macOS" \
    ARCHS="$mac_arch" \
    ONLY_ACTIVE_ARCH=NO \
    OBJROOT="$build_dir/Build/Intermediates.noindex" \
    SYMROOT="$build_dir/Build/Products" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    -quiet

  local app_src="$build_dir/Build/Products/Release/SingFox.app"
  local out_dir="$ROOT/build/macos-dist/$label"
  local app_dst="$out_dir/SingFox.app"
  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  ditto "$app_src" "$app_dst"

  build_core "$go_arch" "$app_dst/Contents/Resources/core/sing-box"

  # Refresh schema when running on matching/Rosetta-capable host.
  if "$app_dst/Contents/Resources/core/sing-box" version >/dev/null 2>&1; then
    "$app_dst/Contents/Resources/core/sing-box" version
  fi

  # Re-sign ad-hoc after embedding the core binary inside Contents/Resources.
  codesign --force --deep --sign - "$app_dst"

  local dmg="$ROOT/build/macos-dist/SingFox-$VERSION-macos-$label.dmg"
  rm -f "$dmg"
  local stage="$out_dir/dmg-stage"
  mkdir -p "$stage"
  ditto "$app_dst" "$stage/SingFox.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "SingFox" -srcfolder "$stage" -ov -format UDZO "$dmg"
  rm -rf "$stage"
  echo "Created $dmg"
}

for a in "${ARCHS[@]}"; do
  build_arch "$a"
done
