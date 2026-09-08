#!/bin/sh
# Read-only inventory for the NEW OpenWrt/FriendlyWrt box.
# No installs, config writes, reloads, module loading or outbound probes.
# Output includes local addresses, MACs and possibly the board serial number.
# Do not replace the allowlists with full configuration dumps.
export LC_ALL=C
section() { printf '\n===== %s =====\n' "$1"; }
has() { command -v "$1" >/dev/null 2>&1; }

section 'SYSTEM'
uname -a
if has ubus; then ubus call system board 2>/dev/null; fi
[ ! -r /etc/openwrt_release ] || cat /etc/openwrt_release

section 'MEMORY / STORAGE'
awk '/^(MemTotal|MemAvailable):/ {print}' /proc/meminfo 2>/dev/null
df -h / /tmp /overlay 2>/dev/null
cat /proc/partitions 2>/dev/null
awk '$2 == "/" || $2 == "/rom" || $2 == "/overlay" || $2 == "/boot" {print}' /proc/mounts 2>/dev/null

section 'ADDRESSES / DEFAULT ROUTES ONLY'
if has ip; then
    ip -br addr 2>/dev/null || ip addr show 2>/dev/null
    ip -4 route show table main default 2>/dev/null
    ip -6 route show table main default 2>/dev/null
    ip -4 rule show 2>/dev/null | head -40
fi

section 'NETWORK / DHCP: ALLOWLISTED FIELDS ONLY'
if has uci; then
    uci -q show network 2>/dev/null | awk '
        /^network\.[^.]+\.(proto|device|ifname|type|ipaddr|netmask|gateway|auto|route_allowed_ips)=/ {print}
    '
    uci -q show dhcp 2>/dev/null | awk '
        /^dhcp\.[^.]+\.(interface|ignore|start|limit|leasetime)=/ {print}
    '
fi

section 'INSTALLED PACKAGES'
PATTERN='^(kernel|kmod-(amneziawg|wireguard|tun|nft-tproxy)|amneziawg|wireguard-tools|luci-(proto|app)-(amneziawg|wireguard|podkop)|podkop|sing-box|mtg|qrencode|rpcd|uhttpd)'
if has apk; then
    apk --version 2>/dev/null
    apk info -v 2>/dev/null | grep -E "$PATTERN"
elif has opkg; then
    opkg list-installed 2>/dev/null | grep -E "$PATTERN"
fi

section 'BINARY VERSIONS, NOT CONFIGURATION'
for binary in awg wg mtg; do
    if has "$binary"; then "$binary" --version 2>&1 | head -4; fi
done
if ! has mtg && [ -x /usr/local/bin/mtg ]; then
    /usr/local/bin/mtg --version 2>&1 | head -4
fi
if has sing-box; then sing-box version 2>&1 | head -6; fi

section 'LOADED MODULES / EXISTING AWG MODULE FILES'
if has lsmod; then lsmod | grep -Ei '(^Module|amnezia|wireguard|tun|tproxy)'; fi
KERNEL="$(uname -r)"
for file in "/lib/modules/$KERNEL/amneziawg.ko" "/lib/modules/$KERNEL/extra/amneziawg.ko"; do
    [ -f "$file" ] || continue
    ls -l "$file"
    if has sha256sum; then sha256sum "$file"; fi
    if has modinfo; then modinfo -F vermagic "$file" 2>/dev/null; fi
done
[ ! -r /sys/module/amneziawg/version ] || cat /sys/module/amneziawg/version

section 'RELEVANT SERVICE / HOTPLUG FILE NAMES ONLY'
for file in /etc/init.d/* /etc/hotplug.d/iface/*; do
    [ -f "$file" ] || continue
    case "$file" in
        *amnezia*|*awg*|*wireguard*|*podkop*|*sing-box*|*mtg*|*korobka*) ls -l "$file" ;;
    esac
done

section 'LISTENING PORTS'
if has ss; then
    ss -lntu 2>/dev/null | head -45
elif has netstat; then
    netstat -lntu 2>/dev/null | head -45
fi
section 'END'
exit 0
