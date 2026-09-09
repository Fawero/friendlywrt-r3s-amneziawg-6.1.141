# Korobka runtime foundation — validated 2026-09-09

This document records the runtime foundation that was built and validated on a FriendlyElec NanoPi R3S LTS running FriendlyWrt 25.12.2 with the real runtime kernel 6.1.141.

No private keys, provider credentials, MTG secrets, DDNS credentials, personal hostnames, or appliance-specific public IP addresses belong in this repository.

## Validated architecture

```text
WAN
 |
 +-- netifd-owned AWG provider tunnels
 |    +-- awg_warp
 |    +-- awg_lu
 |    +-- awg_kz
 |
 +-- Podkop / sing-box policy routing
 |    +-- source: br-lan
 |    +-- source: wg_clients
 |    +-- TelegramProxy mixed SOCKS 127.0.0.1:4534
 |         `-- TelegramProxy-out -> bind_interface=awg_warp
 |
 +-- incoming standard WireGuard
 |    `-- wg_clients 10.77.0.1/24, UDP/51821
 |
 `-- MTG
      `-- TCP/8888 -> SOCKS 127.0.0.1:4534 -> awg_warp -> Telegram
```

The main IPv4 default route remains owned by the physical WAN. Imported provider `AllowedIPs = 0.0.0.0/0` must never replace the main default route. Podkop owns policy routing/TPROXY selection.

## Incoming WireGuard decisions

The incoming phone VPN uses standard WireGuard, not AmneziaWG.

- server keys are generated fresh on every new Korobka installation;
- every phone receives its own fresh key pair;
- keys from the previous appliance are not migrated;
- server network is `10.77.0.1/24`;
- first peer uses `10.77.0.2/32`;
- UDP port is `51821`;
- MTU is currently `1280`;
- phone client DNS is the router at `10.77.0.1`;
- the intended client route is `AllowedIPs = 0.0.0.0/0` for full IPv4 tunnel through the Korobka;
- IPv6 client routing is intentionally not enabled yet to avoid accidental IPv6 leaks before it is designed and tested.

Trusted WireGuard phone peers are intentionally allowed to reach LuCI/SSH on the router (`wgclients` zone input is `ACCEPT`). They are also forwarded to LAN and WAN.

Podkop source interfaces include both `br-lan` and `wg_clients`, so phone traffic follows the same policy engine as LAN traffic.

## FriendlyWrt/OpenWrt 25.12.2 WireGuard netifd issue

The installed `wireguard-tools` package contains `/lib/netifd/proto/wireguard.sh`, but a 25.12.2 helper bug was reproduced on the appliance:

```sh
ip -br link show "${config}" >/dev/null 2>&1 || ip link add dev "${config}" type wireguard
```

The tested correction is:

```sh
ip -br link show dev "${config}" >/dev/null 2>&1 || ip link add dev "${config}" type wireguard
```

`wireguard` originally appeared in UCI but `ifstatus wg_clients` reported `proto: none` and `NO_DEVICE` because the protocol helper was not registered in the running netifd process. After patching the helper and restarting netifd, the protocol registered and `wg_clients` came up successfully.

Use `scripts/patch-wireguard-netifd-25.12.2.sh`; it only patches the known line when present and creates a backup first.

## Podkop validated state

Podkop 0.7.22 with sing-box 1.13.21 was validated after migration.

Global DNS state:

- `dns_type=doh`;
- `dns_server=1.1.1.1`;
- bootstrap resolver must be the currently reachable upstream resolver, not a hardcoded public UDP/53 resolver when the provider intercepts/blocks it;
- generated sing-box DoH server uses numeric `1.1.1.1:443`;
- fake-IP DNS is working.

Validated policy examples:

- main policy -> `awg_warp`;
- GeoBlock -> `awg_lu`;
- Yandex -> direct;
- MTG has its own dedicated `TelegramProxy` section -> `awg_warp`.

The internal MTG SOCKS listener is deliberately loopback-only:

```text
127.0.0.1:4534
```

Do not expose this mixed inbound to LAN or WAN.

The Podkop option used to force this is:

```text
podkop.settings.service_listen_address='127.0.0.1'
```

The validated SOCKS egress returned the WARP public address, proving:

```text
SOCKS 127.0.0.1:4534 -> TelegramProxy-out -> awg_warp
```

## MTG

Validated release:

```text
MTG 2.2.8
linux-arm64 artifact SHA256:
562a94dd4cafcb8f179b76cfeafb76da12747c8e230bc76235bf8746cc189644
```

MTG listens on TCP/8888 and chains exclusively through the Podkop SOCKS listener.

The validated config shape is:

```toml
bind-to = "0.0.0.0:8888"
prefer-ip = "only-ipv4"
auto-update = false

[network]
dns = "https://1.1.1.1/dns-query"
proxies = ["socks5://127.0.0.1:4534"]
```

`mtg doctor` successfully validated all known Telegram DCs both natively and through the SOCKS proxy.

The validation fronting hostname was `storage.googleapis.com`, but MTG correctly reported an SNI-DNS mismatch when the appliance public IP did not belong to that hostname. This is not a transport failure. Production must choose a fronting hostname appropriate to the deployed public address/network. Do not silently treat the validation hostname as a production default.

MTG is launched by `/usr/local/sbin/korobka-mtg-run`, which waits up to 60 seconds for `127.0.0.1:4534` before executing MTG. This deliberately replaces the old service-race hacks.

Autostart ownership:

```text
Podkop: enabled
standalone sing-box: disabled
MTG: enabled
```

## Reboot validation

A full appliance reboot was completed successfully after all components were enabled.

Validated after reboot:

- WAN DHCP restored;
- physical default route remained unchanged;
- `awg_warp`, `awg_lu`, `awg_kz` all returned to `up=true`;
- `wg_clients` returned to `up=true` at `10.77.0.1/24`;
- UDP/51821 was listening;
- Podkop started automatically;
- sing-box listeners returned at `127.0.0.42:53`, `127.0.0.1:1602`, `127.0.0.1:4534`;
- fake-IP DNS worked;
- SOCKS egress through WARP worked;
- MTG started automatically and listened on TCP/8888;
- start order was effectively AWG/netifd -> Podkop/sing-box -> MTG readiness -> MTG.

Zero handshake counters on idle provider tunnels after reboot are not failures; a provider handshake appears when traffic actually uses that tunnel.

## Public access model

Korobka does not use DDNS. The only endpoint source is the observed public IPv4 address.

This intentionally makes a static public IPv4 the preferred deployment model. If a dynamic public address changes, generated WireGuard and Telegram client access data must be regenerated/updated.

`korobka-public-access` distinguishes these states:

```text
direct_public
public_wan_address_mismatch
upstream_nat_upnp
upstream_nat_natpmp
upstream_nat_no_automap
cgnat_suspected_no_automap
```

A private WAN address by itself must never be labeled as proven CGNAT. It may simply mean another customer router is upstream.

Validated NAT discovery behavior on the test topology:

- WAN was private;
- observed Internet IPv4 differed from WAN;
- no upstream UPnP IGD was discovered;
- NAT-PMP gateway returned connection refused;
- therefore the correct classification was `upstream_nat_no_automap`.

For this state, the UI should instruct the operator to forward:

```text
UDP 51821 -> Korobka WAN:51821
TCP 8888  -> Korobka WAN:8888
```

No vendor-specific upstream router assumptions belong in the product.

The repository runtime intentionally ships `status` and `plan` only. Automatic UPnP/NAT-PMP `apply/remove` is not production-ready until Korobka owns and tracks its mappings and renews NAT-PMP leases safely.

## Endpoint and client generation

`korobka-endpoint` is the single source of truth for client endpoints.

It only marks an endpoint ready when:

- WAN is directly public; or
- manual forwarding has explicitly been confirmed for a no-automap upstream NAT scenario; or
- future managed mapping logic can prove that automatic mappings are installed.

Before readiness, it may expose a `candidate_endpoint`, but WireGuard and MTG generators must refuse to produce a working client artifact.

`korobka-wg-client`:

- never prints the phone private key as normal output;
- writes `client.conf` with mode 0600;
- emits an ANSI QR only from an already generated client config.

`korobka-mtg-access`:

- uses the endpoint manager's public IPv4;
- uses `mtg access` with a temporary config containing `public-ipv4`;
- stores only the access object required for QR generation;
- does not print the MTG secret in normal status/generate output.

## Security and secrets

Never commit:

- provider PrivateKeys;
- incoming WG server private key;
- phone private keys;
- MTG secret;
- generated WG client configs;
- generated MTG access links containing the secret;
- historical DDNS credentials.

Runtime secret directories should be mode 0700 and secret files mode 0600.

## FriendlyWrt package safety

The appliance is a hybrid runtime:

```text
actual kernel: 6.1.141
APK database kernel metadata: 6.12.74
```

Therefore:

- never run `apk upgrade`;
- never blindly install official kernel `kmod-*` packages;
- always simulate package installation first and fail closed if simulation itself fails;
- userspace-only packages validated during this milestone include `wireguard-tools`, `miniupnpc`, `natpmpc`, and `qrencode`;
- the standard `wireguard.ko` already exists for the real 6.1.141 runtime and must not be replaced with a foreign kmod package.

## Next runtime milestone

Build `korobka-wg-peer` with:

- `add` / `list` / `remove`;
- fresh key pair per peer;
- automatic `10.77.0.x/32` allocation;
- no reuse of removed private keys;
- atomic UCI update;
- runtime peer refresh without disrupting AWG/provider tunnels;
- optional QR generation only when `korobka-endpoint` is ready.

After that, expose the same operations through the LAN management UI (`luci-app-korobka`).
