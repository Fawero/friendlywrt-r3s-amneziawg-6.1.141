# Korobka support + local management validation — 2026-09-09

## Result

Full live validation passed on FriendlyElec NanoPi R3S LTS / FriendlyWrt 25.12.2 with runtime kernel 6.1.141.

Validated local management:

- LAN transit address `192.168.77.1/24`;
- `korobka.home.arpa -> 192.168.77.1` via dnsmasq;
- downstream DHCP advertises DNS `192.168.77.1`;
- LuCI reachable on `https://192.168.77.1/`;
- local-management state reports configured=true.

Validated temporary support access:

- default state disabled;
- random TCP port in 30000-59999;
- new Ed25519 key pair per session;
- isolated Dropbear authorized_keys directory;
- separate Dropbear listener, password auth disabled;
- WAN firewall rule only for the temporary port;
- JSON-only CLI contract;
- 24h RPC session lifecycle;
- support QR generation;
- synchronous disable removes listener, firewall rule and key material;
- short-TTL session auto-expires and removes listener, firewall and secrets;
- fail-safe validator cleanup prevents orphaned support sessions on failed tests.

Observed validation examples are intentionally not treated as product constants: random ports, session IDs and current public/WAN IP addresses are runtime data and are not copied here.

Network safety remained intact after validation:

- physical default route unchanged;
- `awg_warp`, `awg_lu`, `awg_kz`, `wg_clients` remained up;
- Podkop/sing-box remained running;
- MTG remained running;
- primary SSH on TCP/22 remained available;
- final temporary support state was disabled with no listener, firewall rule or support secret directory left behind.

## Performance notes

Enabling support currently takes about five seconds on the reference box because it performs a full firewall reload and starts the dedicated Dropbear instance. TTL starts after the firewall preparation, so the support lifetime is not consumed by this setup time.

Synchronous disable can take several seconds because the implementation waits for the isolated support Dropbear to terminate before deleting session state. Correct cleanup is preferred over returning before the listener has actually disappeared.

## Product topology

Validated topology remains:

```text
Provider
   |
 [WAN]
 Korobka
 [LAN 192.168.77.1/24]
   |
 [WAN]
 Home router
 [LAN / Wi-Fi]
   |
 home devices
```

The home router NAT is downstream of Korobka and does not block provider-facing temporary support SSH. If the provider places Korobka behind CGNAT/upstream NAT, direct support reachability is not guaranteed; a reverse support relay remains the production fallback for that case.

## Security rules retained

- support disabled by default;
- maximum support TTL 24h;
- new random port and key pair per session;
- no reuse of support secrets;
- no password authentication on the support listener;
- no modification of the primary Dropbear instance;
- no LuCI publication as part of support access;
- private key is never returned by safe status;
- final disable/expiry removes temporary key material, listener and firewall rule;
- no provider/private keys or live support bundle are committed to GitHub.
