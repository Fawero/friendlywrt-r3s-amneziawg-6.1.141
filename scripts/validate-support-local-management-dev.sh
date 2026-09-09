#!/bin/sh
set -eu

fail() {
    echo
    echo "=================================================="
    echo " FAILED: $*"
    echo "=================================================="
    exit 1
}

check_up() {
    IFACE="$1"
    UP="$(ifstatus "$IFACE" 2>/dev/null | jsonfilter -e '@.up')"
    printf '%-12s %s\n' "$IFACE" "$UP"
    [ "$UP" = true ] || fail "$IFACE is down"
}

echo "=================================================="
echo " KOROBKA SUPPORT + LOCAL MANAGEMENT VALIDATION"
echo "=================================================="

echo
echo "===== 1. LOCAL MANAGEMENT ====="
LOCAL="$(/usr/bin/korobka-local-management status)" || fail "local status"
echo "$LOCAL" | jq .
echo "$LOCAL" | jq -e '
    .configured == true and
    .lan_ipv4 == "192.168.77.1" and
    .fqdn == "korobka.home.arpa" and
    .dns_record == true and
    .dhcp_dns == true
' >/dev/null || fail "local contract"

uci -q get network.lan.ipaddr | grep -Fxq '192.168.77.1/24' || fail "LAN UCI address"
uci -q show dhcp.lan.dhcp_option | grep -Fq '6,192.168.77.1' || fail "DHCP DNS option"
uci -q show dhcp.@dnsmasq[0].address | grep -Fq '/korobka.home.arpa/192.168.77.1' || fail "dnsmasq local address"

DNS_RESULT="$(dig +short @127.0.0.1 korobka.home.arpa A 2>/dev/null | tail -1 || true)"
echo "korobka.home.arpa=$DNS_RESULT"
[ "$DNS_RESULT" = '192.168.77.1' ] || fail "local DNS resolution"

HTTP_CODE="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 5 https://192.168.77.1/ || true)"
echo "local LuCI HTTPS=$HTTP_CODE"
case "$HTTP_CODE" in 200|301|302|403) ;; *) fail "local LuCI HTTPS unreachable" ;; esac

echo
echo "===== 2. SUPPORT DEFAULT ====="
/usr/bin/korobka-support disable >/dev/null 2>&1 || true
SUPPORT="$(/usr/bin/korobka-support status)" || fail "support default status"
echo "$SUPPORT" | jq .
echo "$SUPPORT" | jq -e '.enabled == false' >/dev/null || fail "support default disabled"

uci -q get firewall.korobka_support >/dev/null 2>&1 && fail "support firewall exists while disabled" || true

echo
echo "===== 3. SUPPORT RPC ENABLE ====="
ENABLE="$(ubus call luci.korobka support_enable)" || fail "support_enable transport"
echo "$ENABLE" | jq .
echo "$ENABLE" | jq -e '
    .enabled == true and
    (.port >= 30000) and
    (.port < 60000) and
    (.seconds_left > 86000) and
    .listener == true and
    .bundle_ready == true
' >/dev/null || fail "support enable contract"

PORT="$(echo "$ENABLE" | jq -r '.port')"
SESSION="$(echo "$ENABLE" | jq -r '.session_id')"
echo "session=$SESSION port=$PORT"

netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${PORT}$" || fail "support listener missing"
[ "$(uci -q get firewall.korobka_support.dest_port)" = "$PORT" ] || fail "support firewall port mismatch"
[ "$(uci -q get firewall.korobka_support.src)" = wan ] || fail "support firewall source"

[ -s /etc/korobka/support/id_ed25519 ] || fail "support private key missing"
[ "$(stat -c '%a' /etc/korobka/support/id_ed25519)" = 600 ] || fail "support private key permissions"
[ -s /etc/korobka/support/auth/authorized_keys ] || fail "support authorized_keys missing"

if grep -q 'BEGIN OPENSSH PRIVATE KEY' /etc/korobka/support/state.json 2>/dev/null; then
    fail "private key leaked into safe status state"
fi

echo
echo "===== 4. SUPPORT QR ====="
ubus call luci.korobka support_qr > /tmp/korobka-support-qr-test.json || fail "support_qr transport"
QR_LEN="$(jq -r '.svg // "" | length' /tmp/korobka-support-qr-test.json)"
echo "support QR SVG bytes=$QR_LEN"
[ "$QR_LEN" -gt 500 ] || fail "support QR missing"
rm -f /tmp/korobka-support-qr-test.json

echo
echo "===== 5. SUPPORT RPC DISABLE ====="
DISABLE="$(ubus call luci.korobka support_disable)" || fail "support_disable transport"
echo "$DISABLE" | jq .
echo "$DISABLE" | jq -e '.enabled == false and .ok == true' >/dev/null || fail "support disable response"

sleep 1
netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${PORT}$" && fail "support listener remains after disable" || true
uci -q get firewall.korobka_support >/dev/null 2>&1 && fail "support firewall remains after disable" || true
[ ! -e /etc/korobka/support ] || fail "support secret directory remains after disable"

echo "support disable cleanup=OK"

echo
echo "===== 6. AUTO EXPIRY ====="
/usr/bin/korobka-support enable 3 > /tmp/korobka-support-expiry-enable.json || fail "short support enable"
EXP_PORT="$(jq -r '.port' /tmp/korobka-support-expiry-enable.json)"
echo "short-lived test port=$EXP_PORT"
sleep 6
EXPIRED="$(/usr/bin/korobka-support status)" || fail "expired status"
echo "$EXPIRED" | jq .
echo "$EXPIRED" | jq -e '.enabled == false' >/dev/null || fail "support did not auto-expire"
netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${EXP_PORT}$" && fail "expired listener remains" || true
uci -q get firewall.korobka_support >/dev/null 2>&1 && fail "expired firewall remains" || true
[ ! -e /etc/korobka/support ] || fail "expired secret directory remains"
rm -f /tmp/korobka-support-expiry-enable.json
echo "support auto-expiry=OK"

echo
echo "===== 7. LUCI ASSETS / RPC ====="
ubus -v list luci.korobka | grep -E 'support_enable|support_disable|support_qr' || fail "support RPC methods missing"
CODE="$(curl -s -o /tmp/korobka-support.js -w '%{http_code}' http://127.0.0.1/luci-static/resources/view/korobka/support.js)"
SIZE="$(wc -c < /tmp/korobka-support.js)"
echo "support.js HTTP=$CODE bytes=$SIZE"
[ "$CODE" = 200 ] && [ "$SIZE" -gt 1000 ] || fail "support view missing"
jq -e 'has("admin/korobka/support")' /usr/share/luci/menu.d/luci-app-korobka.json >/dev/null || fail "support menu missing"
rm -f /tmp/korobka-support.js

echo
echo "===== 8. FINAL STATUS / NETWORK SAFETY ====="
STATUS="$(ubus call luci.korobka status)" || fail "final status transport"
echo "$STATUS" | jq '{local_management,support,wireguard,mtg,podkop}'
echo "$STATUS" | jq -e '
    .local_management.configured == true and
    .support.enabled == false and
    .wireguard.running == true and
    .mtg.running == true and
    .podkop.sing_box_running == true
' >/dev/null || fail "final status contract"

ip route show default
ip route show 192.168.77.0/24
for I in awg_warp awg_lu awg_kz wg_clients; do check_up "$I"; done

echo
echo "=================================================="
echo " KOROBKA SUPPORT + LOCAL MANAGEMENT: SUCCESS"
echo "=================================================="
