# LuCI panel implementation candidate — 2026-09-09

This document describes the first complete implementation candidate for `luci-app-korobka`. It is committed before live UI validation and must not be described as production-validated until the reference appliance passes the install and browser smoke tests.

## Architecture

The panel uses the current LuCI JavaScript/RPC pattern:

```text
browser JS view
   -> authenticated LuCI RPC
      -> luci.korobka rpcd ucode object
         -> narrow Korobka runtime commands
```

No legacy Lua controller is used. The browser is not granted generic command execution.

## Screens

### Overview

Shows:

- WAN IPv4 and observed public IPv4;
- endpoint readiness and access mode;
- Podkop/sing-box status;
- Telegram SOCKS readiness;
- incoming `wg_clients` state and peer count;
- MTG runtime/listener/outbound state;
- `awg_warp`, `awg_lu`, `awg_kz` up state and transfer/handshake counters.

### Devices

Backed by the validated `korobka-wg-peer` contract:

- list peers;
- add named peer or auto-select `phoneN`;
- remove peer;
- show peer address and public key;
- generate/show WireGuard QR only when `korobka-endpoint` marks WireGuard ready.

Private keys are not displayed as text in the UI.

### Telegram

Shows:

```text
Telegram client
  -> MTG TCP/8888
  -> 127.0.0.1:4534
  -> Podkop TelegramProxy-out
  -> awg_warp
  -> Telegram
```

The UI can request a QR when the MTG endpoint is ready. The MTG secret and access URL are not displayed as ordinary text.

### External access

Shows:

- WAN/public IPv4;
- access classification;
- UPnP and NAT-PMP discovery state;
- WireGuard and MTG endpoint/candidate endpoint;
- manual mapping instructions for `upstream_nat_no_automap`;
- explicit operator confirmation that manual forwarding has been configured.

Required manual mappings remain:

```text
UDP 51821 -> Korobka WAN:51821
TCP 8888  -> Korobka WAN:8888
```

The confirmation is intentionally an operator assertion, not a claim that the port was automatically probed from the public Internet.

## RPC methods

The dedicated object is:

```text
luci.korobka
```

Methods:

```text
status
peers
add_peer(name)
remove_peer(name)
wg_qr(name)
mtg_qr
set_manual_forward(confirmed)
```

The ACL grants only these methods. QR methods are write-class operations because they generate protected runtime artifacts before rendering QR SVG.

## Runtime aggregator

`/usr/bin/korobka-ui-status` combines the existing validated CLI contracts into one JSON snapshot for the overview UI. It does not contain appliance-specific IPs or secrets.

## Development installation

`scripts/install-luci-app-korobka-dev.sh` performs a direct live-device install for validation:

1. validates required commands and existing Korobka runtime contracts;
2. validates ucode `fs` module availability;
3. installs the JS views, menu, ACL and rpcd ucode plugin;
4. installs `korobka-ui-status`;
5. restarts rpcd;
6. clears LuCI index/module caches;
7. verifies `luci.korobka` registration;
8. calls `status` and `peers` through ubus and requires valid JSON.

This direct-copy installer is not the final distribution mechanism. Production should build the LuCI package into the reproducible Korobka image/feed.

## Live validation checklist

Before marking this milestone validated:

- installer completes without package or ucode errors;
- `ubus -v list luci.korobka` shows all expected methods;
- `ubus call luci.korobka status` returns the expected current runtime state;
- `ubus call luci.korobka peers` lists existing peers without private keys;
- LuCI menu `Коробка` appears after refresh/login;
- Overview renders without browser-console JS errors;
- Devices lists `phone1` / current disposable peers;
- Add device creates a new peer and refreshes UI;
- Remove device removes only the selected peer;
- QR controls remain disabled while endpoint readiness is false;
- External access page displays manual-forward instructions for a no-automap upstream NAT;
- toggling manual-forward confirmation changes endpoint readiness as designed;
- Telegram page reflects MTG -> SOCKS -> WARP state;
- AWG provider interfaces and the physical default route remain unchanged during UI peer operations.

After those checks, record a separate validation commit rather than silently changing this implementation note to claim success.
