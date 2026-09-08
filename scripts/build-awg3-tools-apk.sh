#!/usr/bin/env bash
set -Eeuo pipefail

SDK_URL='https://downloads.openwrt.org/releases/25.12.2/targets/rockchip/armv8/openwrt-sdk-25.12.2-rockchip-armv8_gcc-14.3.0_musl.Linux-x86_64.tar.zst'
SDK_SHA256='ef6739acc91c346bd1b6b1bea8a6a950120892136cd0b9b849428203d6d6fa94'
TOOLS_REPO='https://github.com/amnezia-vpn/amneziawg-tools.git'
TOOLS_TAG='v3.1.20260812'
TOOLS_COMMIT='ee0f0a9aa34ff0a0da4b3433b9512781cfe02843'

REPO_DIR="${REPO_DIR:-$HOME/friendlywrt-r3s-amneziawg-6.1.141}"
WORK="${WORK:-$HOME/friendlywrt-awg3-tools-apk}"
SDK_ARCHIVE="$WORK/openwrt-sdk.tar.zst"
SDK_DIR="$WORK/sdk"
SRC_DIR="$WORK/amneziawg-tools"
PKG_SRC="$REPO_DIR/package/amneziawg-tools"
PKG_DST="$SDK_DIR/package/amneziawg-tools"
OUT="$WORK/output"

log() { printf '\n===== %s =====\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$WORK" "$OUT"

log 'PRECHECK HOST TOOLS'
for tool in wget tar zstd sha256sum make gcc g++ git rsync file python3; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing host tool: $tool"
done

test -s "$PKG_SRC/Makefile" || fail "package Makefile not found: $PKG_SRC/Makefile"

log 'FETCH AMNEZIAWG TOOLS'
rm -rf "$SRC_DIR"
git clone --depth 1 --branch "$TOOLS_TAG" "$TOOLS_REPO" "$SRC_DIR"
ACTUAL_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
echo "tools_tag=$TOOLS_TAG"
echo "tools_commit=$ACTUAL_COMMIT"
[ "$ACTUAL_COMMIT" = "$TOOLS_COMMIT" ] || fail 'tools commit mismatch'

log 'FETCH OPENWRT 25.12.2 SDK'
if [ ! -s "$SDK_ARCHIVE" ]; then
    wget -O "$SDK_ARCHIVE" "$SDK_URL"
fi
SDK_SHA="$(sha256sum "$SDK_ARCHIVE" | awk '{print $1}')"
echo "sdk_sha256=$SDK_SHA"
[ "$SDK_SHA" = "$SDK_SHA256" ] || fail 'SDK SHA256 mismatch'

log 'EXTRACT SDK'
rm -rf "$SDK_DIR"
mkdir -p "$SDK_DIR"
tar --use-compress-program=unzstd -xf "$SDK_ARCHIVE" -C "$SDK_DIR" --strip-components=1
test -s "$SDK_DIR/rules.mk" || fail 'invalid SDK extraction'

log 'PREPARE PACKAGE'
rm -rf "$PKG_DST"
mkdir -p "$PKG_DST/files" "$PKG_DST/src"
cp -f "$PKG_SRC/Makefile" "$PKG_DST/Makefile"
cp -a "$SRC_DIR/." "$PKG_DST/src/"
cat > "$PKG_DST/files/amneziawg-tools-build-info.txt" <<EOF
product=korobka
package=amneziawg-tools
package_version=3.1.20260812-r1
upstream_tag=$TOOLS_TAG
upstream_commit=$TOOLS_COMMIT
binary=/usr/bin/awg
awg_quick_included=no
build_method=openwrt-sdk-25.12.2-rockchip-armv8
EOF

log 'SDK PREREQUISITES / DEFCONFIG'
cd "$SDK_DIR"
make defconfig V=s

log 'BUILD APK'
make package/amneziawg-tools/clean V=s
make package/amneziawg-tools/compile V=s

log 'LOCATE APK'
mapfile -t APKS < <(find "$SDK_DIR/bin" -type f -name 'amneziawg-tools*.apk' -print | sort)
[ "${#APKS[@]}" -eq 1 ] || {
    printf 'Found APK candidates:\n'
    printf '%s\n' "${APKS[@]:-}"
    fail "expected exactly one APK, found ${#APKS[@]}"
}

APK="${APKS[0]}"
cp -f "$APK" "$OUT/"
APK_OUT="$OUT/$(basename "$APK")"
sha256sum "$APK_OUT" | tee "$APK_OUT.sha256"

log 'BINARY PRECHECK'
BIN="$(find "$SDK_DIR/build_dir" -path '*/amneziawg-tools-*/src/wg' -type f | head -n1)"
test -n "$BIN" -a -s "$BIN" || fail 'built awg binary not found'
file "$BIN"
"$SDK_DIR/staging_dir/toolchain-aarch64_generic_gcc-14.3.0_musl/bin/aarch64-openwrt-linux-musl-readelf" -h "$BIN" | grep -E 'Class:|Machine:|Type:' || true

log 'SUCCESS'
echo "apk=$APK_OUT"
echo "apk_sha256=$(awk '{print $1}' "$APK_OUT.sha256")"
echo "tools_tag=$TOOLS_TAG"
echo "tools_commit=$TOOLS_COMMIT"
