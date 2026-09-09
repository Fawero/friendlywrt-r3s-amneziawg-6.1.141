#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -x "$ROOT/scripts/install-luci-app-korobka-dev.sh" ] || chmod 755 "$ROOT/scripts/install-luci-app-korobka-dev.sh"

# Install the full current runtime/UI first. This does not change LAN addressing.
/bin/sh "$ROOT/scripts/install-luci-app-korobka-dev.sh"

# Development upgrades must never inherit an orphaned support Dropbear from a
# previously interrupted validation. The freshly installed manager performs a
# synchronous listener/firewall/secret cleanup.
/usr/bin/korobka-support disable >/dev/null 2>&1 \
    || fail "unable to clean previous support session"

STATUS="$(/usr/bin/korobka-local-management status)" || fail "local management status failed"
echo "===== LOCAL MANAGEMENT BEFORE ====="
echo "$STATUS" | jq .

if ! echo "$STATUS" | jq -e '.configured == true' >/dev/null; then
    echo
    echo "===== APPLY LOCAL MANAGEMENT ====="
    /usr/bin/korobka-local-management apply | jq .
fi

LOCAL="$(/usr/bin/korobka-local-management status)" || fail "local management verification failed"
echo
echo "===== LOCAL MANAGEMENT AFTER ====="
echo "$LOCAL" | jq .
echo "$LOCAL" | jq -e '
    .configured == true and
    .lan_ipv4 == "192.168.77.1" and
    .fqdn == "korobka.home.arpa" and
    .dns_record == true and
    .dhcp_dns == true
' >/dev/null || fail "local management contract failed"

/etc/init.d/korobka-support enable

SUPPORT="$(/usr/bin/korobka-support status)" || fail "support status failed"
echo
echo "===== SUPPORT DEFAULT ====="
echo "$SUPPORT" | jq .
echo "$SUPPORT" | jq -e '.enabled == false' >/dev/null \
    || fail "support must be disabled after install"

echo
echo "support + local management installation: OK"
