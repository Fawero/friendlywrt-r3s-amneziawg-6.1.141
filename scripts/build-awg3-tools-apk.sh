#!/usr/bin/env bash
set -Eeuo pipefail

SDK_URL='https://downloads.openwrt.org/releases/25.12.2/targets/rockchip/armv8/openwrt-sdk-25.12.2-rockchip-armv8_gcc-14.3.0_musl.Linux-x86_64.tar.zst'
SDK_SHA256='ef6739acc91c346bd1b6b1bea8a6a950120892136cd0b9b849428203d6d6fa94'
TOOLS_REPO='https://github.com/amnezia-vpn/amneziawg-tools.git'
TOOLS_COMMIT='ee0f0a9aa34ff0a0da4b3433b9512781cfe02843'
TOOLS_VERSION='3.1.20260812'

REPO_DIR="${REPO_DIR:-$HOME/friendlywrt-r3s-amneziawg-6.1.141}"
WORK="${WORK:-$HOME/friendlywrt-awg3-tools-apk}"
SDK_ARCHIVE="${SDK_ARCHIVE:-$HOME/friendlywrt-awg3-apk/openwrt-sdk.tar.zst}"
SDK_DIR="$WORK/sdk"
SRC_DIR="$WORK/amneziawg-tools"
PKG_SRC="$REPO_DIR/package/amneziawg-tools"
PKG_DST="$SDK_DIR/package/amneziawg-tools"
OUT="$WORK/output"
VERIFY_DIR="$WORK/verify-root"

log() { printf '\n===== %s =====\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$WORK" "$OUT" "$(dirname "$SDK_ARCHIVE")"

log 'PRECHECK HOST TOOLS'
REQUIRED_TOOLS='wget tar zstd sha256sum make gcc g++ flex bison gawk gettext git rsync swig unzip file python3 readelf strings'
MISSING_TOOLS=''
for tool in $REQUIRED_TOOLS; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done
if [ -n "$MISSING_TOOLS" ]; then
    echo "Missing host tools:$MISSING_TOOLS" >&2
    exit 2
fi

test -s "$PKG_SRC/Makefile" || fail "package Makefile not found: $PKG_SRC/Makefile"

log 'FETCH PINNED AWG 3.1 USERSPACE SOURCE'
rm -rf "$SRC_DIR"
git clone "$TOOLS_REPO" "$SRC_DIR"
git -C "$SRC_DIR" checkout --detach "$TOOLS_COMMIT"
ACTUAL_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
echo "tools_commit=$ACTUAL_COMMIT"
[ "$ACTUAL_COMMIT" = "$TOOLS_COMMIT" ] || fail 'tools commit mismatch'
git -C "$SRC_DIR" log -1 --decorate --oneline

log 'VERIFY AWG 3.1 CLI SUPPORT IN SOURCE'
grep -q 'header-protection-key' "$SRC_DIR/src/set.c" || fail 'header-protection-key support missing'
grep -q 'content-padding-addition' "$SRC_DIR/src/set.c" || fail 'content-padding-addition support missing'
grep -q 'random-trailers' "$SRC_DIR/src/set.c" || fail 'random-trailers support missing'
grep -q 'disable-cookies' "$SRC_DIR/src/set.c" || fail 'disable-cookies support missing'
echo 'AWG 3.1 CLI markers: OK'

log 'FETCH OPENWRT 25.12.2 SDK'
if [ ! -s "$SDK_ARCHIVE" ]; then
    wget -O "$SDK_ARCHIVE" "$SDK_URL"
fi
SDK_SHA="$(sha256sum "$SDK_ARCHIVE" | awk '{print $1}')"
echo "sdk=$SDK_ARCHIVE"
echo "sdk_sha256=$SDK_SHA"
[ "$SDK_SHA" = "$SDK_SHA256" ] || fail 'SDK SHA256 mismatch'

log 'EXTRACT SDK'
rm -rf "$SDK_DIR"
mkdir -p "$SDK_DIR"
tar --use-compress-program=unzstd -xf "$SDK_ARCHIVE" -C "$SDK_DIR" --strip-components=1
test -s "$SDK_DIR/rules.mk" || fail 'invalid SDK extraction'

log 'PREPARE CUSTOM PACKAGE'
rm -rf "$PKG_DST"
mkdir -p "$PKG_DST/files" "$PKG_DST/src-tree"
cp -f "$PKG_SRC/Makefile" "$PKG_DST/Makefile"
rsync -a --delete "$SRC_DIR/" "$PKG_DST/src-tree/"
cat > "$PKG_DST/files/amneziawg-tools-build-info.txt" <<EOF
product=korobka
package=amneziawg-tools
package_version=${TOOLS_VERSION}-r1
upstream_repo=$TOOLS_REPO
upstream_commit=$TOOLS_COMMIT
upstream_commit_subject=feat: add awg 3.1 params
target=openwrt-25.12.2-rockchip-armv8
target_arch=aarch64_generic
libc=musl
binary=/usr/bin/awg
awg_quick_included=no
netifd_helper_included=no
features=header-protection-key,content-padding-addition,timings,random-trailers,disable-cookies
EOF

log 'SDK PREREQUISITES / DEFCONFIG'
cd "$SDK_DIR"
make defconfig V=s

log 'BUILD CUSTOM TOOLS APK'
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

APK_TOOL="$SDK_DIR/staging_dir/host/bin/apk"
[ -x "$APK_TOOL" ] || fail "SDK apk tool not found: $APK_TOOL"

log 'APK METADATA'
ADB_DUMP="$OUT/$(basename "$APK_OUT").adbdump.json"
"$APK_TOOL" adbdump --format json "$APK_OUT" > "$ADB_DUMP"
test -s "$ADB_DUMP" || fail 'apk adbdump returned empty metadata'
grep -q 'amneziawg-tools' "$ADB_DUMP" || fail 'package name missing from APK metadata'

log 'EXTRACT / VERIFY APK'
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
"$APK_TOOL" extract --allow-untrusted --destination "$VERIFY_DIR" "$APK_OUT"

AWG_BIN="$VERIFY_DIR/usr/bin/awg"
BUILD_INFO="$VERIFY_DIR/usr/share/korobka/amneziawg-tools-build-info.txt"
test -x "$AWG_BIN" || fail 'packed /usr/bin/awg missing or not executable'
test -s "$BUILD_INFO" || fail 'packed build-info missing'
grep -qx "upstream_commit=$TOOLS_COMMIT" "$BUILD_INFO" || fail 'packed source commit mismatch'

echo '--- file ---'
file "$AWG_BIN"
file "$AWG_BIN" | grep -qi 'ARM aarch64' || fail 'awg binary is not aarch64'

AWG_SHA="$(sha256sum "$AWG_BIN" | awk '{print $1}')"
echo "awg_binary_sha256=$AWG_SHA"

echo '--- ELF dynamic section ---'
readelf -d "$AWG_BIN" | grep -E 'NEEDED|RUNPATH|RPATH' || true

log 'VERIFY AWG 3.1 MARKERS IN PACKED BINARY'
for marker in header-protection-key content-padding-addition random-trailers disable-cookies; do
    strings "$AWG_BIN" | grep -Fq "$marker" || fail "packed awg binary missing marker: $marker"
    echo "$marker: OK"
done

log 'SUCCESS'
echo "apk=$APK_OUT"
echo "apk_sha256=$(awk '{print $1}' "$APK_OUT.sha256")"
echo "apk_metadata=$ADB_DUMP"
echo "verified_root=$VERIFY_DIR"
echo "awg_binary_sha256=$AWG_SHA"
echo "tools_commit=$TOOLS_COMMIT"
echo "target_arch=aarch64_generic"
echo "libc=musl"
