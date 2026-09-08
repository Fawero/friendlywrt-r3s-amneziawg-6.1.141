#!/bin/sh
set -eu

CONF="${1:-}"
IFACE="${2:-awg-test}"
TEST_IP="${3:-1.1.1.1}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -n "$CONF" ] || fail "usage: $0 <provider.conf> [interface] [test-ip]"
[ -f "$CONF" ] || fail "config not found: $CONF"
command -v awg >/dev/null 2>&1 || fail "awg is not installed"
command -v ip >/dev/null 2>&1 || fail "ip is not installed"
command -v ping >/dev/null 2>&1 || fail "ping is not installed"

SAN="/tmp/${IFACE}.awg-setconf.$$"
TEST_ROUTE_ADDED=0

cleanup() {
    if [ "$TEST_ROUTE_ADDED" = "1" ]; then
        ip route del "$TEST_IP/32" dev "$IFACE" 2>/dev/null || true
    fi
    ip link del "$IFACE" 2>/dev/null || true
    rm -f "$SAN"
}
trap cleanup EXIT INT TERM

# wg-quick/network-manager fields are not accepted by awg setconf and must not
# own routing on Korobka. Hooks are deliberately ignored and never executed.
ADDRS="$(sed -n 's/^[[:space:]]*Address[[:space:]]*=[[:space:]]*//p' "$CONF" | head -n1)"
MTU="$(sed -n 's/^[[:space:]]*MTU[[:space:]]*=[[:space:]]*//p' "$CONF" | head -n1)"
[ -n "$MTU" ] || MTU=1420
[ -n "$ADDRS" ] || fail "Address is missing in $CONF"

if grep -Eq '^[[:space:]]*(PreUp|PostUp|PreDown|PostDown)[[:space:]]*=' "$CONF"; then
    echo "WARNING: lifecycle hooks are present in the imported config; they will be ignored"
fi

umask 077
awk '
{
    l = tolower($0)
    if (l ~ /^[ \t]*(address|dns|mtu|table|preup|postup|predown|postdown)[ \t]*=/)
        next
    print
}
' "$CONF" > "$SAN"

SRC4=""
SRC6=""
OLDIFS="$IFS"
IFS=','
for raw in $ADDRS; do
    addr="$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$addr" ] || continue
    case "$addr" in
        *:*)
            case "$addr" in */*) : ;; *) addr="$addr/128" ;; esac
            [ -n "$SRC6" ] || SRC6="${addr%%/*}"
            ;;
        *)
            case "$addr" in */*) : ;; *) addr="$addr/32" ;; esac
            [ -n "$SRC4" ] || SRC4="${addr%%/*}"
            ;;
    esac
    ADDR_LIST="${ADDR_LIST:-} $addr"
done
IFS="$OLDIFS"

ip link del "$IFACE" 2>/dev/null || true
ip link add "$IFACE" type amneziawg
awg setconf "$IFACE" "$SAN"

for addr in ${ADDR_LIST:-}; do
    ip addr add "$addr" dev "$IFACE"
done
ip link set mtu "$MTU" dev "$IFACE"
ip link set "$IFACE" up

sleep 1

echo
echo "===== CONFIG ====="
echo "source=$CONF"
echo "interface=$IFACE"
echo "addresses=$ADDRS"
echo "mtu=$MTU"
echo "test_ip=$TEST_IP"
echo
echo "===== LINK ====="
ip -details link show "$IFACE"
echo
echo "===== AWG BEFORE TRAFFIC ====="
awg show "$IFACE"

if [ -n "$SRC4" ]; then
    echo
    echo "===== SAFE TEST ROUTE ====="
    ip route replace "$TEST_IP/32" dev "$IFACE" src "$SRC4"
    TEST_ROUTE_ADDED=1
    ip route get "$TEST_IP"

    echo
    echo "===== GENERATE TRAFFIC ====="
    ping -c 3 -W 3 -I "$SRC4" "$TEST_IP" || true

    ip route del "$TEST_IP/32" dev "$IFACE" 2>/dev/null || true
    TEST_ROUTE_ADDED=0
else
    echo "No IPv4 interface address; skipping IPv4 test traffic"
fi

sleep 1

echo
echo "===== AWG AFTER TRAFFIC ====="
awg show "$IFACE"

echo
echo "===== ROUTING SAFETY CHECK ====="
ip route show default

echo
echo "===== CLEANUP ====="
# EXIT trap removes only the test interface and host route. Default routing is
# never modified by this script.
