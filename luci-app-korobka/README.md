# luci-app-korobka

LuCI JS/RPC management panel for the Korobka runtime.

Current screens:

- Overview — public access, endpoint, Podkop/sing-box, incoming WireGuard, MTG and AWG exits;
- Devices — list/add/remove WireGuard phone peers and show QR when endpoint is ready;
- Telegram — MTG status, fixed SOCKS->WARP route and Telegram proxy QR;
- External access — WAN/public IPv4 diagnostics and manual port-forward confirmation.

The browser never receives arbitrary shell execution privileges. UI actions are exposed through the dedicated `luci.korobka` rpcd ucode object and ACL.

The panel depends on the already validated Korobka runtime commands under `/usr/bin/korobka-*` and `/usr/local/sbin/korobka-mtg-run`.

## Development install on the reference appliance

From an extracted copy of this repository:

```sh
./scripts/install-luci-app-korobka-dev.sh
```

Then open LuCI and use the top-level **Коробка** menu.

This direct-copy installer is for live validation only. Production delivery should build `luci-app-korobka` as part of the reproducible image/package feed.
