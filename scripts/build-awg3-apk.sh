#!/usr/bin/env bash
set -Eeuo pipefail

SDK_URL='https://downloads.openwrt.org/releases/25.12.2/targets/rockchip/armv8/openwrt-sdk-25.12.2-rockchip-armv8_gcc-14.3.0_musl.Linux-x86_64.tar.zst'
SDK_SHA256='ef6739acc91c346bd1b6b1bea8a6a950120892136cd0b9b849428203d6d6fa94'
AWG_TAG='v3.1.20260906'
AWG_COMMIT='4569c4c67f3a57414969260cafbbd04694fbaae0'
AWG_MODULE_VERSION='3.1.20260812'
EXPECTED_KREL='6.1.141'
EXPECTED_VERMAGIC='6.1.141 SMP mod_unload modversions aarch64'
EXPECTED_MODULE_SHA256='572f4250d8bbd470a46f9dd835efa6ebd90479ab0875c840b1277c949a7844f7'

REPO_DIR="${REPO_DIR:-$HOME/friendlywrt-r3s-amneziawg-6.1.141}"
MODULE="${MODULE:-$HOME/friendlywrt-awg3-6.1.141/output/amneziawg-$AWG_TAG.ko}"
WORK="${WORK:-$HOME/friendlywrt-awg3-apk}"
SDK_ARCHIVE="$WORK/openwrt-sdk.tar.zst"
SDK_DIR="$WORK/sdk"
PKG_SRC="$REPO_DIR/package/friendlywrt-amneziawg-kmod"
PKG_DST="$SDK_DIR/package/friendlywrt-amneziawg-kmod"
OUT="$WORK/output"
VERIFY_DIR="$WORK/verify-root"

log() { printf '\n===== %s =====\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$WORK" "$OUT"

log 'PRECHECK HOST TOOLS'
REQUIRED_TOOLS='wget tar zstd modinfo sha256sum make gcc g++ flex bison gawk gettext git rsync swig unzip file python3'
MISSING_TOOLS=''
for tool in $REQUIRED_TOOLS; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done
if [ -n "$MISSING_TOOLS" ]; then
    echo "Missing host tools:$MISSING_TOOLS" >&2
    echo "Install the OpenWrt SDK prerequisites for Ubuntu 24.04 and rerun." >&2
    exit 2
fi

log 'PRECHECK MODULE'
test -s "$MODULE" || fail "module not found: $MODULE"
test -s "$PKG_SRC/Makefile" || fail "package Makefile not found: $PKG_SRC/Makefile"

MODULE_SHA="$(sha256sum "$MODULE" | awk '{print $1}')"
echo "module=$MODULE"
echo "module_sha256=$MODULE_SHA"
[ "$MODULE_SHA" = "$EXPECTED_MODULE_SHA256" ] || fail 'module SHA256 mismatch'

VM="$(modinfo -F vermagic "$MODULE" | sed 's/[[:space:]]*$//')"
KVER="$(modinfo -F version "$MODULE" | sed 's/[[:space:]]*$//')"
echo "module_version=$KVER"
echo "vermagic=$VM"
[ "$VM" = "$EXPECTED_VERMAGIC" ] || fail 'module vermagic mismatch'

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
mkdir -p "$PKG_DST/files"
cp -f "$PKG_SRC/Makefile" "$PKG_DST/Makefile"
cp -f "$MODULE" "$PKG_DST/files/amneziawg.ko"
cat > "$PKG_DST/files/amneziawg-build-info.txt" <<EOF
product=korobka
package=friendlywrt-amneziawg-kmod
package_version=3.1.20260906-r1
runtime_kernel=$EXPECTED_KREL
vermagic=$EXPECTED_VERMAGIC
upstream_tag=$AWG_TAG
upstream_commit=$AWG_COMMIT
module_version=$AWG_MODULE_VERSION
module_sha256=$EXPECTED_MODULE_SHA256
build_method=external-module-against-friendlyarm-kernel-6.1.141
EOF

log 'SDK PREREQUISITES / DEFCONFIG'
cd "$SDK_DIR"
make defconfig V=s

log 'BUILD APK'
make package/friendlywrt-amneziawg-kmod/clean V=s
make package/friendlywrt-amneziawg-kmod/compile V=s

log 'LOCATE APK'
mapfile -t APKS < <(find "$SDK_DIR/bin" -type f -name 'friendlywrt-amneziawg-kmod*.apk' -print | sort)
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
grep -q 'friendlywrt-amneziawg-kmod' "$ADB_DUMP" || fail 'package name missing from APK metadata'
grep -q '6.1.141' "$ADB_DUMP" || fail 'runtime kernel guard is not visible in APK metadata/scripts'

log 'EXTRACT / VERIFY APK'
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
"$APK_TOOL" extract --allow-untrusted --destination "$VERIFY_DIR" "$APK_OUT"

PACKED_MODULE="$VERIFY_DIR/lib/modules/6.1.141/amneziawg.ko"
PACKED_MODULES_D="$VERIFY_DIR/etc/modules.d/30-amneziawg"
PACKED_INFO="$VERIFY_DIR/usr/share/korobka/amneziawg-build-info.txt"

test -s "$PACKED_MODULE" || fail 'packed amneziawg.ko missing'
test -s "$PACKED_MODULES_D" || fail 'packed /etc/modules.d/30-amneziawg missing'
test -s "$PACKED_INFO" || fail 'packed build-info missing'

grep -qx 'amneziawg' "$PACKED_MODULES_D" || fail 'modules.d entry is invalid'
grep -qx "runtime_kernel=$EXPECTED_KREL" "$PACKED_INFO" || fail 'build-info runtime kernel mismatch'
grep -qx "module_sha256=$EXPECTED_MODULE_SHA256" "$PACKED_INFO" || fail 'build-info module SHA mismatch'

PACKED_SHA="$(sha256sum "$PACKED_MODULE" | awk '{print $1}')"
echo "packed_module_sha256=$PACKED_SHA"
[ "$PACKED_SHA" = "$EXPECTED_MODULE_SHA256" ] || fail 'packed module SHA256 mismatch'

PACKED_VM="$(modinfo -F vermagic "$PACKED_MODULE" | sed 's/[[:space:]]*$//')"
PACKED_VER="$(modinfo -F version "$PACKED_MODULE" | sed 's/[[:space:]]*$//')"
echo "packed_module_version=$PACKED_VER"
echo "packed_vermagic=$PACKED_VM"
[ "$PACKED_VM" = "$EXPECTED_VERMAGIC" ] || fail 'packed module vermagic mismatch'

log 'SUCCESS'
echo "apk=$APK_OUT"
echo "apk_sha256=$(awk '{print $1}' "$APK_OUT.sha256")"
echo "apk_metadata=$ADB_DUMP"
echo "verified_root=$VERIFY_DIR"
echo "module_sha256=$MODULE_SHA"
echo "runtime_kernel=$EXPECTED_KREL"
echo "vermagic=$VM"
