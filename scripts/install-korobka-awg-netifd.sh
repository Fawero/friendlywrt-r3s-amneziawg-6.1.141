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

install -m 0755 "$SRC" "$DST"

mkdir -p /etc/korobka/tunnels
chmod 700 /etc/korobka /etc/korobka/tunnels

/etc/init.d/network reload

echo "Installed: $DST"
echo "Tunnel directory: /etc/korobka/tunnels"
