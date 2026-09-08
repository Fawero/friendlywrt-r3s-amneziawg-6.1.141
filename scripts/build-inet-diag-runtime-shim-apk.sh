#!/usr/bin/env bash
set -Eeuo pipefail

SDK_URL='https://downloads.openwrt.org/releases/25.12.2/targets/rockchip/armv8/openwrt-sdk-25.12.2-rockchip-armv8_gcc-14.3.0_musl.Linux-x86_64.tar.zst'
SDK_SHA256='ef6739acc91c346bd1b6b1bea8a6a950120892136cd0b9b849428203d6d6fa94'
EXPECTED_KREL='6.1.141'
PKG_NAME='friendlywrt-kmod-inet-diag-runtime'
EXPECTED_PROVIDE='kmod-inet-diag'

REPO_DIR="${REPO_DIR:-$HOME/friendlywrt-r3s-amneziawg-6.1.141}"
WORK="${WORK:-$HOME/friendlywrt-inet-diag-shim-apk}"
SDK_ARCHIVE="$WORK/openwrt-sdk.tar.zst"
SDK_DIR="$WORK/sdk"
PKG_SRC="$REPO_DIR/package/$PKG_NAME"
PKG_DST="$SDK_DIR/package/$PKG_NAME"
OUT="$WORK/output"
VERIFY_DIR="$WORK/verify-root"

log() { printf '\n===== %s =====\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$WORK" "$OUT"

log 'PRECHECK HOST TOOLS'
REQUIRED_TOOLS='wget tar zstd sha256sum make gcc g++ flex bison gawk gettext git rsync swig unzip file python3'
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
mkdir -p "$PKG_DST"
cp -f "$PKG_SRC/Makefile" "$PKG_DST/Makefile"

log 'SDK DEFCONFIG'
cd "$SDK_DIR"
make defconfig V=s

log 'BUILD APK'
make "package/$PKG_NAME/clean" V=s
make "package/$PKG_NAME/compile" V=s

log 'LOCATE APK'
mapfile -t APKS < <(find "$SDK_DIR/bin" -type f -name "$PKG_NAME*.apk" -print | sort)
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
grep -q "$PKG_NAME" "$ADB_DUMP" || fail 'package name missing from APK metadata'
grep -q "$EXPECTED_PROVIDE" "$ADB_DUMP" || fail 'kmod-inet-diag provide missing from APK metadata'
grep -q "$EXPECTED_KREL" "$ADB_DUMP" || fail 'runtime kernel guard missing from APK metadata/scripts'

log 'EXTRACT / VERIFY APK'
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
"$APK_TOOL" extract --allow-untrusted --destination "$VERIFY_DIR" "$APK_OUT"

MODS_D="$VERIFY_DIR/etc/modules.d/31-inet-diag"
INFO="$VERIFY_DIR/usr/share/korobka/inet-diag-runtime-info.txt"

test -s "$MODS_D" || fail 'packed modules.d file missing'
test -s "$INFO" || fail 'packed runtime info missing'

grep -qx 'inet_diag' "$MODS_D" || fail 'inet_diag autoload entry missing'
grep -qx 'tcp_diag' "$MODS_D" || fail 'tcp_diag autoload entry missing'
grep -qx 'udp_diag' "$MODS_D" || fail 'udp_diag autoload entry missing'
grep -qx 'raw_diag' "$MODS_D" || fail 'raw_diag autoload entry missing'
grep -qx 'contains_kernel_modules=no' "$INFO" || fail 'runtime info does not mark shim as module-free'

if find "$VERIFY_DIR" -type f -name '*.ko*' | grep -q .; then
    find "$VERIFY_DIR" -type f -name '*.ko*' -print
    fail 'shim APK unexpectedly contains kernel modules'
fi

log 'SUCCESS'
echo "apk=$APK_OUT"
echo "apk_sha256=$(awk '{print $1}' "$APK_OUT.sha256")"
echo "apk_metadata=$ADB_DUMP"
echo "verified_root=$VERIFY_DIR"
echo "provides=$EXPECTED_PROVIDE"
echo "runtime_kernel=$EXPECTED_KREL"
