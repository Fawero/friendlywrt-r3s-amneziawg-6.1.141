# Podkop + sing-box on Korobka

## Installation status

Validated on NanoPi R3S LTS / FriendlyWrt 25.12.2 with runtime kernel 6.1.141.

Installed userspace stack:

```text
jq 1.8.1
sing-box 1.13.21
podkop 0.7.22
luci-app-podkop 0.7.22
luci-i18n-podkop-ru 0.7.22
```

Because the FriendlyWrt runtime kernel is 6.1.141 while APK metadata tracks OpenWrt 6.12.74, the official `kmod-inet-diag` package must not be installed.

The runtime image already contains working 6.1.141 modules:

```text
inet_diag.ko
tcp_diag.ko
udp_diag.ko
raw_diag.ko
```

All four were validated with `modprobe` successfully. A local compatibility package `friendlywrt-kmod-inet-diag-runtime` provides the virtual `kmod-inet-diag` dependency without shipping any `.ko` files. Its pre-install guard validates kernel 6.1.141 and module presence.

After installing the shim, APK simulation for Podkop showed only userspace packages and no foreign `kmod-*` dependencies.

## Safety state after installation

Podkop and standalone sing-box were deliberately left stopped and disabled before policy configuration.

Verified:

```text
No podkop/sing-box processes
No podkop/sing-box autostart links
No podkop nft tables
No podkop ip rules
No foreign kmod-inet-diag package
```

The AWG provider interfaces remain up:

```text
awg_warp = up
awg_kz   = up
awg_lu   = up
```

The system default route remains owned by the physical WAN.

## Podkop VPN integration model

Podkop 0.7.22 supports `connection_type='vpn'` with an `interface` field. Korobka will use the existing netifd-managed AWG devices directly:

```text
awg_warp
awg_kz
awg_lu
```

Podkop will not import or own AWG credentials. netifd continues to own tunnel lifecycle; Podkop only owns policy routing / TPROXY state.

## Migration from the old Korobka

The old appliance used Podkop 0.7.14 with the following functional policy:

- `main` was a VPN section through the old `Cloudflare_WARP` interface;
- `Yandex` was an exclusion section using the existing remote Yandex lists;
- `GeoBlock` was a VPN section through the old `SurfShark_LUx` interface;
- source traffic included both `br-lan` and the incoming phone interface `wg_ios`;
- the old `SurfShark_Kz` interface was not referenced by Podkop and therefore remains available for a future independent role;
- the old appliance used a custom `/etc/hotplug.d/iface/99-awg-after-wan` script to stop/start Podkop, manipulate temporary DNS, load AmneziaWG, and bring up AWG after WAN. This script must not be migrated because the new appliance uses netifd-owned AWG lifecycle and has already passed reboot/autostart validation;
- the old cron contained a daily `podkop list_update` entry;
- the old global Podkop DNS configuration was DoH to `1.1.1.1` with bootstrap `9.9.9.9`, but old sing-box logs repeatedly showed `dial tcp 1.1.1.1:443: i/o timeout`. That DNS transport must be revalidated rather than copied blindly.

Interface migration:

```text
old Cloudflare_WARP -> new awg_warp
old SurfShark_LUx  -> new awg_lu
old SurfShark_Kz   -> new awg_kz (currently unused by migrated Podkop policy)
old wg_ios         -> do not migrate yet; add the future incoming WG interface later
```

The old `main` community lists remain valid in Podkop 0.7.22:

```text
news
youtube
meta
twitter
hdrezka
telegram
google_play
hodca
anime
```

The old `GeoBlock` community lists also remain valid:

```text
geoblock
google_ai
porn
```

User and remote lists to preserve:

```text
main user domain:
a6470af52578.sn.mynetname.net

Yandex remote subnet list:
https://raw.githubusercontent.com/turikhay/geoip-yandex/release/srs/yandex.srs

Yandex remote domain list:
https://raw.githubusercontent.com/v2fly/domain-list-community/master/data/yandex

GeoBlock user domains:
termius.com
openevidence.com

GeoBlock remote domain lists:
https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-google-gemini.srs
https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-anthropic.srs
https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-openai.srs
```

Migration should preserve the policy data but not the old AWG UCI sections, hotplug startup orchestration, endpoint-DNS workarounds, or old service-race hacks.

## First migrated validation

Recreate the old policy on Podkop 0.7.22 using `awg_warp` and `awg_lu`, keep `awg_kz` unused, and initially set `source_network_interfaces` only to `br-lan`. Keep Podkop disabled from autostart until generated sing-box configuration, nftables state, DNS behavior, and actual client routing have been validated. Add the future incoming WireGuard interface to Podkop sources only after that separate feature is built and tested.
