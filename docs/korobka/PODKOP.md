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

## First pilot

Use `awg_warp` as a single VPN section and route only one explicit test domain. Remove the default `russia_inside` list before first start so the blast radius remains minimal. Source traffic is limited to `br-lan` initially.

After the pilot succeeds, add separate sections for KZ/LU and later dedicate one section to Telegram/MTG traffic.
