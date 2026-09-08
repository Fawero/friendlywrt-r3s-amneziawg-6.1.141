#!/usr/bin/env bash
set -Eeuo pipefail

# Build AmneziaWG 3.1 for the exact FriendlyWrt NanoPi R3S/LTS kernel ABI.
# Reuses the already validated FriendlyARM 6.1.141 kernel build tree from the
# previous AWG2 build, but creates a separate AWG3 workspace and never modifies
# the AWG2 source tree.

AWG_TAG="${AWG_TAG:-v3.1.20260906}"
EXPECTED_KREL="6.1.141"
EXPECTED_VERMAGIC="6.1.141 SMP mod_unload modversions aarch64"

OLD_WORK="${OLD_WORK:-$HOME/friendlywrt-awg2-6.1.141}"
KERNEL="${KERNEL:-$OLD_WORK/kernel-rockchip}"
WORK="${WORK:-$HOME/friendlywrt-awg3-6.1.141}"
AWG="$WORK/amneziawg-linux-kernel-module"
OUT="$WORK/output"
LOGS="$WORK/logs"

mkdir -p "$WORK" "$OUT" "$LOGS"

log() { printf '\n===== %s =====\n' "$*"; }
fail() { echo "ОШИБКА: $*" >&2; exit 1; }

log "PRECHECK"
command -v git >/dev/null || fail "git не найден"
command -v make >/dev/null || fail "make не найден"
command -v aarch64-linux-gnu-gcc >/dev/null || fail "aarch64-linux-gnu-gcc не найден"
command -v modinfo >/dev/null || fail "modinfo не найден"
command -v modprobe >/dev/null || fail "modprobe не найден"

test -d "$KERNEL" || fail "нет kernel tree: $KERNEL"
test -s "$KERNEL/.config" || fail "нет $KERNEL/.config"
test -s "$KERNEL/Module.symvers" || fail "нет $KERNEL/Module.symvers"
test -s "$KERNEL/vmlinux" || fail "нет $KERNEL/vmlinux"

KREL="$(make -s -C "$KERNEL" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)"
echo "kernelrelease=$KREL"
[ "$KREL" = "$EXPECTED_KREL" ] || fail "ожидалось kernelrelease $EXPECTED_KREL"

grep -q '^CONFIG_MODVERSIONS=y' "$KERNEL/.config" || fail "CONFIG_MODVERSIONS != y"
grep -q '^CONFIG_MODULES=y' "$KERNEL/.config" || fail "CONFIG_MODULES != y"

log "FETCH AWG $AWG_TAG"
if [ ! -d "$AWG/.git" ]; then
    git clone https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git "$AWG"
else
    git -C "$AWG" fetch --tags --prune origin
fi

# Refuse to silently build a different revision if the requested tag does not exist.
git -C "$AWG" rev-parse -q --verify "refs/tags/$AWG_TAG" >/dev/null \
    || fail "tag $AWG_TAG не найден upstream"

git -C "$AWG" reset --hard
git -C "$AWG" clean -xfd
git -C "$AWG" checkout --detach "$AWG_TAG"

AWG_COMMIT="$(git -C "$AWG" rev-parse HEAD)"
echo "awg_tag=$AWG_TAG"
echo "awg_commit=$AWG_COMMIT"
git -C "$AWG" log -1 --decorate --oneline

log "SOURCE COMPATIBILITY SCAN"
# These are known compatibility boundaries for 6.1-era kernels. We deliberately
# do not patch them here: first establish what the selected upstream tag contains.
TIMER_SRC_COUNT="$(grep -RIlE '\b(timer_delete|timer_delete_sync)\b' "$AWG/src" --include='*.c' --include='*.h' 2>/dev/null | wc -l)"
NLA_SRC_COUNT="$(grep -RIlE '\bnla_put_uint[[:space:]]*\(' "$AWG/src" --include='*.c' --include='*.h' 2>/dev/null | wc -l)"

echo "files_using_new_timer_api=$TIMER_SRC_COUNT"
echo "files_using_nla_put_uint=$NLA_SRC_COUNT"

echo "kernel timer API:"
grep -nE '(^|[^A-Za-z0-9_])(timer_delete|timer_delete_sync|del_timer|del_timer_sync)[[:space:]]*\(' \
    "$KERNEL/include/linux/timer.h" | head -20 || true

echo "kernel nla_put_uint declaration:"
grep -RInE '\bnla_put_uint[[:space:]]*\(' "$KERNEL/include" --include='*.h' 2>/dev/null | head -20 || true

log "CLEAN EXTERNAL MODULE"
make -C "$KERNEL" \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    M="$AWG/src" \
    clean

log "BUILD"
set +e
make -j"$(nproc)" \
    -C "$KERNEL" \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    M="$AWG/src" \
    modules \
    2>&1 | tee "$LOGS/amneziawg-build.log"
RC=${PIPESTATUS[0]}
set -e

if [ "$RC" -ne 0 ]; then
    echo
    echo "BUILD FAILED (rc=$RC)"
    echo "Последние ошибки:"
    grep -Ei 'error:|implicit declaration|undefined|timer_delete|nla_put_uint' \
        "$LOGS/amneziawg-build.log" | tail -80 || true
    echo
    echo "Лог: $LOGS/amneziawg-build.log"
    exit "$RC"
fi

MODULE="$AWG/src/amneziawg.ko"
test -s "$MODULE" || fail "amneziawg.ko не создан"
cp -f "$MODULE" "$OUT/amneziawg-$AWG_TAG.ko"
MODULE="$OUT/amneziawg-$AWG_TAG.ko"

log "MODINFO"
file "$MODULE"
sha256sum "$MODULE" | tee "$OUT/amneziawg-$AWG_TAG.sha256"
modinfo "$MODULE" | grep -E '^(filename|version|description|author|license|srcversion|depends|vermagic):' || true

VM="$(modinfo -F vermagic "$MODULE" | sed 's/[[:space:]]*$//')"
echo "vermagic=$VM"
echo "expected_vermagic=$EXPECTED_VERMAGIC"
[ "$VM" = "$EXPECTED_VERMAGIC" ] || fail "vermagic не совпадает"

log "MODVERSIONS / ABI"
modprobe --show-modversions "$MODULE" > "$OUT/new-modversions.txt"
[ -s "$OUT/new-modversions.txt" ] || fail "модуль не содержит modversions"

awk '{print $2, $1}' "$OUT/new-modversions.txt" | sort -k1,1 > "$OUT/new-imports.txt"
awk '{print $2, $1}' "$KERNEL/Module.symvers" | sort -k1,1 > "$OUT/kernel-symbols.txt"

join "$OUT/new-imports.txt" "$OUT/kernel-symbols.txt" > "$OUT/new-vs-kernel.txt" || true
join -v1 "$OUT/new-imports.txt" "$OUT/kernel-symbols.txt" > "$OUT/new-missing.txt" || true
awk '$2 != $3' "$OUT/new-vs-kernel.txt" > "$OUT/new-crc-bad.txt"

TOTAL="$(wc -l < "$OUT/new-imports.txt")"
FOUND="$(wc -l < "$OUT/new-vs-kernel.txt")"
MISSING="$(wc -l < "$OUT/new-missing.txt")"
BAD="$(wc -l < "$OUT/new-crc-bad.txt")"

echo "imports=$TOTAL"
echo "found_in_kernel=$FOUND"
echo "missing=$MISSING"
echo "crc_mismatches=$BAD"

if [ "$MISSING" -ne 0 ]; then
    echo "--- missing symbols ---"
    cat "$OUT/new-missing.txt"
    fail "есть отсутствующие kernel symbols"
fi

if [ "$BAD" -ne 0 ]; then
    echo "--- CRC mismatches ---"
    cat "$OUT/new-crc-bad.txt"
    fail "есть CRC mismatches"
fi

log "SUCCESS"
echo "module=$MODULE"
echo "sha256=$(awk '{print $1}' "$OUT/amneziawg-$AWG_TAG.sha256")"
echo "awg_tag=$AWG_TAG"
echo "awg_commit=$AWG_COMMIT"
echo "kernelrelease=$KREL"
echo "vermagic=$VM"
