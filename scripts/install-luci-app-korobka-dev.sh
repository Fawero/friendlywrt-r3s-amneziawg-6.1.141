#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP="$ROOT/luci-app-korobka"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

rpc_must_succeed() {
    METHOD="$1"
    shift

    OUT="$(ubus call luci.korobka "$METHOD" "$@")" || fail "RPC $METHOD transport failed"
    echo "$OUT" | jq .

    echo "$OUT" | jq -e '
        if type == "object" and has("error")
        then false
        else true
        end
    ' >/dev/null || fail "RPC $METHOD returned an error"
}

[ -d "$APP/htdocs" ] || fail "luci-app-korobka source directory not found"
[ -d "$APP/root" ] || fail "luci-app-korobka root directory not found"
[ -f "$ROOT/rootfs/usr/bin/korobka-ui-status" ] || fail "korobka-ui-status missing"

for cmd in jq qrencode ucode ubus; do
    command -v "$cmd" >/dev/null 2>&1 || fail "required command missing: $cmd"
done

for cmd in \
    /usr/bin/korobka-public-access \
    /usr/bin/korobka-endpoint \
    /usr/bin/korobka-wg-peer \
    /usr/bin/korobka-wg-client \
    /usr/bin/korobka-mtg-access; do
    [ -x "$cmd" ] || fail "validated Korobka runtime command missing: $cmd"
done

if ! ucode -e '
    import { popen } from "fs";
    let f = popen("/bin/echo korobka-ucode-popen-ok", "r");
    if (!f) exit(1);
    print(f.read("all"));
    exit(f.close());
' 2>/dev/null | grep -q '^korobka-ucode-popen-ok$'; then
    fail "ucode fs.popen string command execution is unavailable"
fi

mkdir -p \
    /www/luci-static/resources/view/korobka \
    /usr/share/luci/menu.d \
    /usr/share/rpcd/acl.d \
    /usr/share/rpcd/ucode

cp -f "$APP/htdocs/luci-static/resources/view/korobka/overview.js" /www/luci-static/resources/view/korobka/overview.js
cp -f "$APP/htdocs/luci-static/resources/view/korobka/devices.js" /www/luci-static/resources/view/korobka/devices.js
cp -f "$APP/htdocs/luci-static/resources/view/korobka/telegram.js" /www/luci-static/resources/view/korobka/telegram.js
cp -f "$APP/htdocs/luci-static/resources/view/korobka/access.js" /www/luci-static/resources/view/korobka/access.js

cp -f "$APP/root/usr/share/luci/menu.d/luci-app-korobka.json" /usr/share/luci/menu.d/luci-app-korobka.json
cp -f "$APP/root/usr/share/rpcd/acl.d/luci-app-korobka.json" /usr/share/rpcd/acl.d/luci-app-korobka.json
cp -f "$APP/root/usr/share/rpcd/ucode/luci.korobka" /usr/share/rpcd/ucode/luci.korobka
cp -f "$ROOT/rootfs/usr/bin/korobka-ui-status" /usr/bin/korobka-ui-status

chmod 0644 \
    /www/luci-static/resources/view/korobka/*.js \
    /usr/share/luci/menu.d/luci-app-korobka.json \
    /usr/share/rpcd/acl.d/luci-app-korobka.json
chmod 0755 \
    /usr/share/rpcd/ucode/luci.korobka \
    /usr/bin/korobka-ui-status

sh -n /usr/bin/korobka-ui-status || fail "korobka-ui-status syntax error"
/usr/bin/korobka-ui-status | jq -e . >/dev/null || fail "korobka-ui-status does not return JSON"

/etc/init.d/rpcd restart
sleep 2

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache 2>/dev/null || true

if ! ubus list 'luci.korobka' 2>/dev/null | grep -q 'luci.korobka'; then
    logread | grep -iE 'rpcd|korobka|ucode' | tail -80 >&2 || true
    fail "luci.korobka RPC object did not register"
fi

echo "===== RPC OBJECT ====="
ubus -v list luci.korobka

echo
echo "===== RPC STATUS ====="
rpc_must_succeed status

echo
echo "===== RPC PEERS ====="
rpc_must_succeed peers

echo
echo "luci-app-korobka development install: OK"
echo "Refresh LuCI and open: Коробка -> Обзор"
