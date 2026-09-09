#!/bin/sh
set -eu

WGSH="/lib/netifd/proto/wireguard.sh"

[ -f "$WGSH" ] || {
    echo "wireguard netifd helper not found: $WGSH" >&2
    exit 1
}

if grep -Fq 'ip -br link show "${config}"' "$WGSH"; then
    backup="$WGSH.bak-korobka-$(date +%Y%m%d-%H%M%S)"
    cp -a "$WGSH" "$backup"
    sed -i 's/ip -br link show "${config}"/ip -br link show dev "${config}"/' "$WGSH"
    echo "patched: $WGSH"
    echo "backup:  $backup"
else
    echo "known 25.12.2 buggy line not present; no patch needed"
fi

echo "netifd must be restarted after installing or changing protocol helpers"
