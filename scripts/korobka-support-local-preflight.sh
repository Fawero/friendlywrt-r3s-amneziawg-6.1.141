#!/bin/sh
set -u

echo "===== KOROBKA SUPPORT + LOCAL MANAGEMENT PREFLIGHT ====="

echo
echo "===== 1. BOARD / KERNEL ====="
ubus call system board 2>/dev/null || true
uname -a

echo
echo "===== 2. NETWORK UCI ====="
uci show network.lan 2>/dev/null || true
uci show network.wan 2>/dev/null || true

echo
echo "===== 3. LAN RUNTIME ====="
ifstatus lan 2>/dev/null || true
ip -4 addr show 2>/dev/null
ip -4 route show

echo
echo "===== 4. DHCP / DNS ====="
uci show dhcp.lan 2>/dev/null || true
uci show dhcp.@dnsmasq[0] 2>/dev/null || true
cat /tmp/dhcp.leases 2>/dev/null || true

echo
echo "===== 5. FIREWALL LAN/WAN ZONES ====="
uci show firewall | grep -E "=zone|\.name=|\.network=|\.input=|\.output=|\.forward=" || true

echo
echo "===== 6. NEIGHBOURS ON LAN ====="
ip neigh show 2>/dev/null || true

echo
echo "===== 7. DROPBEAR INSTANCES ====="
uci show dropbear 2>/dev/null || true
pgrep -af dropbear 2>/dev/null || true
netstat -lntp 2>/dev/null | grep dropbear || true

echo
echo "===== 8. DROPBEAR FEATURE FLAGS ====="
/usr/sbin/dropbear -h 2>&1 | grep -E -- "(^|[[:space:]])-D|(^|[[:space:]])-j|(^|[[:space:]])-k|(^|[[:space:]])-M|authorized" || true

echo
echo "===== 9. KEYGEN TOOLS ====="
command -v ssh-keygen || true
command -v dropbearkey || true
command -v dropbearconvert || true

TMP=/tmp/korobka-keygen-preflight-$$
rm -f "$TMP" "$TMP.pub"
if command -v ssh-keygen >/dev/null 2>&1; then
    if ssh-keygen -q -t ed25519 -N 'TEST-ONLY-NOT-A-SECRET' -f "$TMP" -C korobka-preflight >/dev/null 2>&1; then
        echo "openssh_ed25519_generation=yes"
        head -1 "$TMP" 2>/dev/null || true
    else
        echo "openssh_ed25519_generation=no"
    fi
fi
rm -f "$TMP" "$TMP.pub"

echo
echo "===== 10. OPENSSH-KEYGEN APK SIMULATION ====="
SIM=/tmp/korobka-openssh-keygen-sim-$$.txt
if apk add --simulate openssh-keygen >"$SIM" 2>&1; then
    echo "simulate_rc=0"
    cat "$SIM"
    if grep -Eiq '(^|[[:space:]])(kmod-|kernel-)' "$SIM"; then
        echo "kernel_dependency_detected=yes"
    else
        echo "kernel_dependency_detected=no"
    fi
else
    RC=$?
    echo "simulate_rc=$RC"
    cat "$SIM"
fi
rm -f "$SIM"

echo
echo "===== 11. PUBLIC ACCESS ====="
/usr/bin/korobka-public-access status 2>/dev/null | jq . || true

echo
echo "===== 12. LUCI LISTENERS ====="
netstat -lntp 2>/dev/null | grep -E ':(80|443)[[:space:]]' || true

echo
echo "===== PREFLIGHT FINISHED ====="
