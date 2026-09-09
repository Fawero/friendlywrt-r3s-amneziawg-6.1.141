# Korobka LuCI backend validation — 2026-09-09

This note records successful live validation of `luci-app-korobka` on the reference FriendlyElec NanoPi R3S LTS running FriendlyWrt 25.12.2 with actual runtime kernel 6.1.141.

Validated source commit:

```text
8a8ae3cedfd3240e74d4556563b7b13246385f2c
```

No private keys, MTG secrets, generated client configs or appliance-specific public IP addresses are recorded here.

## Scope

The panel is implemented with the modern LuCI architecture:

```text
menu JSON
ACL JSON
rpcd ucode backend: luci.korobka
LuCI JavaScript views
```

Validated menu pages:

```text
Коробка
├── Обзор
├── Устройства
├── Telegram
└── Внешний доступ
```

The browser does not receive generic shell execution privileges. It calls the explicit `luci.korobka` RPC object.

## RPC object

Validated methods:

```text
status
peers
add_peer
remove_peer
wg_qr
mtg_qr
set_manual_forward
```

`status` returns the aggregated Korobka runtime state. `peers` returns an object with a `peers` array because rpcd ucode methods must return a dictionary/object at the top level.

## Status contract

The live RPC status call successfully returned and validated:

- all three provider AWG interfaces up;
- incoming standard WireGuard running;
- Podkop enabled;
- sing-box running;
- Telegram SOCKS listener ready at loopback;
- MTG enabled, running and listening;
- current public-access/endpoint state;
- current WireGuard peer count and peer data.

The tested topology remained `upstream_nat_no_automap` with manual forwarding not confirmed, therefore endpoint readiness remained false as designed.

## Peer RPC lifecycle

A disposable peer named `luci_test` was created through RPC.

Validated behavior:

- invalid input containing spaces/shell punctuation was rejected before execution;
- `add_peer` returned `ok=true`;
- the disposable peer received the next free `10.77.0.x/32` address;
- it appeared in UCI;
- it appeared immediately in live `wg_clients` runtime;
- its private/public key files existed with the expected security permissions;
- the wrapped `peers` RPC response immediately included the new peer;
- `remove_peer` returned `ok=true`;
- the peer disappeared from UCI;
- the peer disappeared from live WireGuard runtime;
- its key directory was removed.

The permanent peers present before the validation remained unchanged.

## QR readiness gates

Both QR paths were validated in the not-ready topology.

WireGuard QR correctly refused generation because the external endpoint was not ready.

MTG QR correctly refused generation for the same reason.

This confirms that the LuCI layer does not bypass the existing `korobka-endpoint` safety contract.

## Manual forwarding state

`set_manual_forward(false)` was called through RPC and persisted the expected false state. The validation did not falsely mark the current nested-NAT test topology as externally reachable.

## Static LuCI assets

All four JS views were served successfully over the local HTTP server with HTTP 200:

```text
overview.js
devices.js
telegram.js
access.js
```

Menu JSON and ACL JSON both parsed successfully.

## Network safety

Before and after the full LuCI/RPC validation:

```text
physical default route: unchanged
awg_warp: up=true
awg_lu:   up=true
awg_kz:   up=true
wg_clients: up=true
```

The Podkop SOCKS listener and MTG listener remained available. sing-box and MTG remained running.

The validation completed with:

```text
KOROBKA LUCI: FULL BACKEND VALIDATION SUCCESS
KOROBKA LUCI V4 SUCCESS
script_rc=0
```

## Important implementation fixes discovered during validation

Several rpcd/ucode integration details were discovered and fixed before the successful run:

1. `fs.popen()` must receive a command string rather than the argv array used in the first draft.
2. command stdout must be read first and then parsed as JSON.
3. ucode `join()` uses `join(separator, array)`.
4. rpcd ucode method callbacks must return a top-level object/dictionary. A raw array result causes UBUS no-data behavior; therefore the peer list contract is `{ peers: [...] }`.
5. installer smoke tests must treat an RPC object containing `error` as a failed installation, not a successful transport call.

These constraints are now encoded in the repository implementation and validation scripts.

## Current status

The `luci-app-korobka` backend and static delivery are now considered live-validated on the reference appliance.

The next milestone is browser/UI validation and visual refinement of the four pages. Backend contracts should remain stable unless the UI review exposes a genuine functional gap.
