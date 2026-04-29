#!/bin/sh
set -eu

KVER="$(uname -r)"
EXPECTED_KVER="6.1.141"

echo "Current kernel: $KVER"

if [ "$KVER" != "$EXPECTED_KVER" ]; then
  echo "ERROR: This module was built for kernel $EXPECTED_KVER, but router has $KVER"
  exit 1
fi

cd /tmp

if [ ! -f /tmp/amneziawg.ko ]; then
  echo "ERROR: /tmp/amneziawg.ko not found"
  exit 1
fi

mkdir -p /lib/modules/$KVER/extra
cp /tmp/amneziawg.ko /lib/modules/$KVER/extra/amneziawg.ko

modprobe libchacha20poly1305 2>/dev/null || true
modprobe libcurve25519-generic 2>/dev/null || true
modprobe udp_tunnel 2>/dev/null || true
modprobe ip6_udp_tunnel 2>/dev/null || true

insmod /lib/modules/$KVER/extra/amneziawg.ko 2>/dev/null || true

mkdir -p /etc/modules.d
echo amneziawg > /etc/modules.d/99-amneziawg

echo "=== loaded modules ==="
lsmod | grep -E 'amneziawg|wireguard|chacha|curve|udp_tunnel' || true

echo "OK: amneziawg installed"
