#!/bin/sh
set -eu

SRC="${1:-rootfs/lib/netifd/proto/korobka_awg.sh}"
DST="/lib/netifd/proto/korobka_awg.sh"

[ "$(id -u)" = "0" ] || {
    echo "Run as root" >&2
    exit 1
}

[ -r "$SRC" ] || {
    echo "Missing helper: $SRC" >&2
    exit 1
}

cp "$SRC" "$DST"
chmod 0755 "$DST"

mkdir -p /etc/korobka/tunnels
chmod 700 /etc/korobka /etc/korobka/tunnels

# netifd discovers shell protocol handlers during process startup, not a config-only reload.
/etc/init.d/network restart

echo "Installed: $DST"
echo "Tunnel directory: /etc/korobka/tunnels"
echo "Network restarted so korobka_awg is registered by netifd"
