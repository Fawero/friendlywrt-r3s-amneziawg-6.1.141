#!/bin/sh
set -eu

fail() {
    echo
    echo "=================================================="
    echo " FAILED: $*"
    echo "=================================================="
    exit 1
}

rpc() {
    METHOD="$1"
    shift
    ubus call luci.korobka "$METHOD" "$@"
}

check_up() {
    IFACE="$1"
    UP="$(ifstatus "$IFACE" 2>/dev/null | jsonfilter -e '@.up')"
    printf '%-12s %s\n' "$IFACE" "$UP"
    [ "$UP" = "true" ] || fail "$IFACE is down"
}

echo "=================================================="
echo " KOROBKA LUCI — FULL BACKEND VALIDATION"
echo "=================================================="

echo
echo "===== 1. BASELINE ====="
uptime
ip route show default
for I in awg_warp awg_lu awg_kz wg_clients; do check_up "$I"; done

echo
echo "===== 2. RPC OBJECT ====="
ubus -v list luci.korobka || fail "RPC object missing"

echo
echo "===== 3. STATUS CONTRACT ====="
STATUS="$(rpc status)" || fail "status transport"
echo "$STATUS" | jq .
echo "$STATUS" | jq -e '
    type == "object" and
    (has("error") | not) and
    (.awg.warp.up == true) and
    (.awg.lu.up == true) and
    (.awg.kz.up == true) and
    (.wireguard.running == true) and
    (.podkop.sing_box_running == true) and
    (.podkop.telegram_socks_ready == true) and
    (.mtg.running == true) and
    (.mtg.listening == true)
' >/dev/null || fail "status contract"
echo "status contract=OK"

echo
echo "===== 4. PEERS CONTRACT ====="
PEERS="$(rpc peers)" || fail "peers transport"
echo "$PEERS" | jq .
echo "$PEERS" | jq -e '
    type == "object" and
    (has("error") | not) and
    (.peers | type == "array") and
    (.peers | length >= 2) and
    any(.peers[]; .name == "phone1") and
    any(.peers[]; .name == "phone2")
' >/dev/null || fail "peers wrapped contract"
echo "peers contract=OK"

echo
echo "===== 5. INVALID INPUT SAFETY ====="
BAD="$(rpc add_peer '{"name":"bad peer;rm"}')" || fail "invalid-name transport"
echo "$BAD" | jq .
echo "$BAD" | jq -e 'type == "object" and has("error")' >/dev/null \
    || fail "invalid peer name accepted"
echo "invalid input rejected=OK"

echo
echo "===== 6. RPC PEER LIFECYCLE ====="
TEST_PEER="luci_test"

if uci -q get "network.$TEST_PEER" >/dev/null 2>&1; then
    CLEAN="$(rpc remove_peer "{\"name\":\"$TEST_PEER\"}")" || fail "cleanup transport"
    echo "$CLEAN" | jq .
fi

ADD="$(rpc add_peer "{\"name\":\"$TEST_PEER\"}")" || fail "add transport"
echo "$ADD" | jq .
echo "$ADD" | jq -e '.ok == true and .action == "added" and .name == "luci_test"' >/dev/null \
    || fail "add response"

uci -q get "network.$TEST_PEER" >/dev/null 2>&1 || fail "peer absent from UCI"
TEST_PUB="$(uci -q get "network.$TEST_PEER.public_key")"
TEST_ADDR="$(uci -q get "network.$TEST_PEER.allowed_ips")"
echo "test address=$TEST_ADDR"
wg show wg_clients peers | grep -Fxq "$TEST_PUB" || fail "peer absent from runtime"
[ "$(stat -c '%a' "/etc/korobka/wireguard/peers/$TEST_PEER/private.key")" = "600" ] \
    || fail "private key permissions"

echo "add runtime/UCI/files=OK"

AFTER_ADD="$(rpc peers)" || fail "peers after add transport"
echo "$AFTER_ADD" | jq .
echo "$AFTER_ADD" | jq -e 'any(.peers[]; .name == "luci_test")' >/dev/null \
    || fail "test peer missing from wrapped list"

REMOVE="$(rpc remove_peer "{\"name\":\"$TEST_PEER\"}")" || fail "remove transport"
echo "$REMOVE" | jq .
echo "$REMOVE" | jq -e '.ok == true and .action == "removed"' >/dev/null \
    || fail "remove response"

if uci -q get "network.$TEST_PEER" >/dev/null 2>&1; then fail "peer remains in UCI"; fi
if wg show wg_clients peers 2>/dev/null | grep -Fxq "$TEST_PUB"; then fail "peer remains in runtime"; fi
if [ -e "/etc/korobka/wireguard/peers/$TEST_PEER" ]; then fail "peer directory remains"; fi
echo "RPC peer lifecycle=OK"

echo
echo "===== 7. QR READINESS GATES ====="
WGQR="$(rpc wg_qr '{"name":"phone1"}')" || fail "wg_qr transport"
echo "$WGQR" | jq .
echo "$WGQR" | jq -e 'type == "object" and has("error")' >/dev/null \
    || fail "WG QR unexpectedly available"

echo "WG QR gate=OK"
MTGQR="$(rpc mtg_qr)" || fail "mtg_qr transport"
echo "$MTGQR" | jq .
echo "$MTGQR" | jq -e 'type == "object" and has("error")' >/dev/null \
    || fail "MTG QR unexpectedly available"
echo "MTG QR gate=OK"

echo
echo "===== 8. MANUAL FORWARD FLAG ====="
FORWARD="$(rpc set_manual_forward '{"confirmed":false}')" || fail "manual forward transport"
echo "$FORWARD" | jq .
echo "$FORWARD" | jq -e '.confirmed == false' >/dev/null || fail "manual forward response"
[ "$(uci -q get korobka.endpoint.manual_forward_confirmed)" = "0" ] \
    || fail "manual forward UCI state"
echo "manual forward remains disabled=OK"

echo
echo "===== 9. STATIC LUCI VIEWS ====="
for VIEW in overview devices telegram access; do
    OUT="/tmp/korobka-${VIEW}.js"
    CODE="$(curl -s -o "$OUT" -w '%{http_code}' \
        "http://127.0.0.1/luci-static/resources/view/korobka/${VIEW}.js")"
    SIZE="$(wc -c < "$OUT")"
    printf '%-12s HTTP=%s bytes=%s\n' "$VIEW" "$CODE" "$SIZE"
    [ "$CODE" = "200" ] || fail "$VIEW HTTP=$CODE"
    [ "$SIZE" -gt 500 ] || fail "$VIEW unexpectedly small"
done
echo "static LuCI views=OK"

echo
echo "===== 10. MENU + ACL ====="
jq . /usr/share/luci/menu.d/luci-app-korobka.json >/dev/null || fail "menu JSON"
jq . /usr/share/rpcd/acl.d/luci-app-korobka.json >/dev/null || fail "ACL JSON"
echo "menu+ACL=OK"

echo
echo "===== 11. FINAL NETWORK SAFETY ====="
ip route show default
for I in awg_warp awg_lu awg_kz wg_clients; do check_up "$I"; done
/usr/bin/korobka-wg-peer list | jq .

netstat -lntp 2>/dev/null | grep -E '127\.0\.0\.1:4534|:8888' || true
pgrep -af sing-box || true
pgrep -af 'mtg run' || true

echo
echo "===== 12. RELEVANT LOGS ====="
logread | grep -iE 'rpcd|ucode|korobka|luci' | tail -120 || true

echo
echo "=================================================="
echo " KOROBKA LUCI: FULL BACKEND VALIDATION SUCCESS"
echo "=================================================="
