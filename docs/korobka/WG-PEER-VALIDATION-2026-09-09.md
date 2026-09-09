# WireGuard peer manager validation — 2026-09-09

This note records live validation of `korobka-wg-peer` on the reference FriendlyElec NanoPi R3S LTS running FriendlyWrt 25.12.2 with the real runtime kernel 6.1.141.

No private keys or generated client configs are recorded here.

## Scope

The manager provides:

```text
korobka-wg-peer list
korobka-wg-peer add [name]
korobka-wg-peer remove name
```

Design constraints:

- incoming VPN interface is `wg_clients`;
- peer addresses are allocated from `10.77.0.2/32` through `10.77.0.254/32`;
- `10.77.0.1/24` remains the router address;
- each peer receives a newly generated WireGuard key pair;
- peer private keys stay under `/etc/korobka/wireguard/peers/<name>/private.key`;
- secrets are never printed as normal command output;
- UCI is committed for reboot persistence;
- the live `wg_clients` interface is updated with `wg set` instead of restarting all networking;
- provider AWG interfaces must not be disrupted by peer changes;
- the physical WAN default route must not change.

## Existing peer before test

The existing first peer occupied:

```text
phone1 -> 10.77.0.2/32
```

`korobka-wg-peer list` correctly reported it as present in the live WireGuard runtime with zero handshake/traffic counters because no client had connected yet.

## Add test

A second peer was created with:

```text
korobka-wg-peer add phone2
```

Validated results:

- command returned `ok: true`;
- peer name was `phone2`;
- automatic address allocation selected `10.77.0.3/32`;
- a fresh public key was produced;
- the peer immediately appeared in `wg show wg_clients`;
- UCI section `network.phone2=wireguard_wg_clients` was committed;
- `allowed_ips` was `10.77.0.3/32`;
- `route_allowed_ips=1`;
- `persistent_keepalive=25`;
- generated key files had mode `0600`;
- `korobka-wg-client status phone2` resolved the new peer address and candidate endpoint correctly;
- client artifact generation remained blocked because the external endpoint was not yet marked ready.

## Remove test

The disposable second peer was removed with:

```text
korobka-wg-peer remove phone2
```

Validated results:

- command returned `ok: true`;
- `phone2` disappeared from `korobka-wg-peer list`;
- the peer disappeared from live `wg show wg_clients`;
- UCI section `network.phone2` was deleted;
- `/etc/korobka/wireguard/peers/phone2` was removed;
- the host route for `10.77.0.3/32` disappeared;
- `phone1` remained present and unchanged;
- the physical default route remained unchanged;
- `awg_warp`, `awg_lu`, and `awg_kz` all remained `up=true`.

## Re-add / key rotation test

Immediately after removal, an unnamed add was executed:

```text
korobka-wg-peer add
```

The allocator correctly selected the first free logical slot again:

```text
phone2 -> 10.77.0.3/32
```

The address and logical name were reused, but the peer public key was different from the removed peer. This proves the implementation reuses released addressing capacity while generating a fresh cryptographic identity instead of restoring deleted key material.

The new key files again had mode `0600`, the peer appeared immediately in the live `wg_clients` runtime, and the provider AWG interfaces/default route remained untouched.

## Isolation validation

Across add, remove and re-add:

```text
main default route: unchanged
awg_warp: up=true
awg_lu:   up=true
awg_kz:   up=true
```

This proves the tested peer lifecycle can modify the incoming standard WireGuard peer set without restarting netifd, replacing the main route, or interrupting provider AmneziaWG interfaces.

## Runtime list contract

`list` returns JSON objects containing:

```text
name
address
public_key
runtime
latest_handshake
rx_bytes
tx_bytes
```

Public keys are intentionally visible; private keys are not.

## Rollback behavior

The implementation backs up `/etc/config/network` before changes. On add it rolls UCI back if runtime peer installation or verification fails. On remove it removes the live peer first and commits the corresponding UCI deletion.

Successful paths now validated live:

```text
list
add named peer
add auto-named peer
remove peer
released address reuse
fresh key generation after re-add
```

One persistence edge remains explicitly untested: a peer was removed and then intentionally re-added before reboot, so there has not yet been a dedicated reboot test proving that a removed-and-not-readded peer stays absent across boot. UCI deletion was committed during the successful remove path, but this note does not claim a reboot result that was not actually performed.

## Next step

The `add/list/remove` CLI contract is ready to be used by `luci-app-korobka` for future "Add device" / "Remove device" controls. QR/client generation must continue to depend on `korobka-endpoint.ready=true`.

A later regression pass should include a disposable remove-then-reboot case before image release.
