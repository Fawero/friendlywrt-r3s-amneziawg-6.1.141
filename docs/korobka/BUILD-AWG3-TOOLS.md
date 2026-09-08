# AmneziaWG 3.1 userspace tools for FriendlyWrt

## Status

On 2026-09-08 a reproducible `amneziawg-tools` package was built for OpenWrt/FriendlyWrt userspace:

```text
package: amneziawg-tools-3.1.20260812-r1.apk
arch: aarch64_generic
libc: musl
binary: /usr/bin/awg
upstream commit: ee0f0a9aa34ff0a0da4b3433b9512781cfe02843
upstream subject: feat: add awg 3.1 params
APK SHA256: 428953ed20eeacf6fd7c9cf361a4b51eb33e8200249be0038d2ab3ee512736cf
awg binary SHA256: 36f4159a56cc9ec6390cd1f05a64bb9fa0e426e6fd2352b93c45bc4a5a9f82e5
```

The package intentionally contains only `/usr/bin/awg`; `awg-quick` and the upstream netifd helper are excluded because Korobka/netifd/Podkop will own interface lifecycle and routing.

The packed executable was verified as:

```text
ELF 64-bit LSB executable, ARM aarch64
interpreter /lib/ld-musl-aarch64.so.1
NEEDED: libgcc_s.so.1
NEEDED: libc.so
```

The pinned AWG 3.1 userspace source contains CLI support for:

```text
header-protection-key
content-padding-addition
rekey-after-time
rekey_timeout
reject_after_time
keepalive_timeout
max_handshake_attempts
random-trailers
disable-cookies
advanced-security
```

## Important build detail

The upstream `src/Makefile` must be allowed to append its own Linux UAPI include and runtime-state define:

```text
-I uapi/linux
-DRUNSTATEDIR=\"/var/run\"
```

Do not pass `CFLAGS` as a make command-line variable to the nested upstream make, otherwise GNU make prevents the upstream Makefile from appending these flags. Without them the build incorrectly uses the SDK's ordinary WireGuard UAPI and fails on AWG-specific netlink attributes such as `WGDEVICE_A_JC`, `WGDEVICE_A_I1`, `WGDEVICE_A_HEADER_PROTECTION_KEY`, and `WGPEER_A_AWG`.

The working package recipe therefore exports `CFLAGS`/`LDFLAGS` in the environment and invokes upstream make with `PLATFORM=linux` and `RUNSTATEDIR=/var/run`.

## Verifier pipefail bug

An initial post-build verifier used:

```sh
strings "$AWG_BIN" | grep -Fq "$marker"
```

while the script runs with `set -Eeuo pipefail`.

This can report a false failure: `grep -q` exits immediately after finding a marker, `strings` receives SIGPIPE, and `pipefail` marks the pipeline as failed even though the marker exists.

The verifier was fixed to write `strings` output to a file first and then run `grep -Fq` against that file.

## Runtime validation on NanoPi R3S LTS — SUCCESS

The package was installed on the real NanoPi R3S LTS running FriendlyWrt 25.12.2 with runtime kernel `6.1.141` and the already-tested custom `amneziawg.ko` module loaded.

Pre-install checks confirmed:

```text
kernel: 6.1.141
/lib/ld-musl-aarch64.so.1 -> libc.so
/lib/libgcc_s.so.1 present
amneziawg module loaded
APK SHA256: 428953ed20eeacf6fd7c9cf361a4b51eb33e8200249be0038d2ab3ee512736cf
```

Installation completed successfully:

```text
(1/1) Installing amneziawg-tools (3.1.20260812-r1)
Executing amneziawg-tools-3.1.20260812-r1.post-install
OK
```

Installed runtime binary:

```text
/usr/bin/awg
amneziawg-tools v3.1.20260812 - https://amnezia.org
```

The packaged build information on-device correctly reports:

```text
package=amneziawg-tools
package_version=3.1.20260812-r1
upstream_commit=ee0f0a9aa34ff0a0da4b3433b9512781cfe02843
target=openwrt-25.12.2-rockchip-armv8
target_arch=aarch64_generic
libc=musl
awg_quick_included=no
netifd_helper_included=no
```

Userspace-to-kernel netlink communication was then validated end-to-end:

1. Created an `amneziawg` interface with `ip link add awg-test type amneziawg`.
2. `awg show awg-test` successfully read the empty interface and reported AWG 3.1 fields (`random trailers`, `disable cookies`).
3. `awg genkey` generated a private key.
4. `awg set awg-test private-key /tmp/awg-test.key` successfully configured the kernel interface through netlink.
5. `awg show awg-test` read the configured public key back from the kernel.
6. `awg pubkey < /tmp/awg-test.key` produced the same public key, confirming correct key handling.
7. The test interface was deleted cleanly.

Observed public key in this disposable runtime test:

```text
Lzu/+Su8GM7XjMTWsf5AHbs8ZIBoMLkNe68feLgzED8=
```

This test key was generated only for the disposable `awg-test` interface and removed during cleanup; it is not a production or provider key.

## Confirmed compatibility baseline

The following combination is now confirmed working on real hardware:

```text
FriendlyWrt: 25.12.2 r32802-f505120278
runtime kernel: 6.1.141
AWG kernel source tag: v3.1.20260906
AWG kernel internal version: 3.1.20260812
AWG kernel module APK: friendlywrt-amneziawg-kmod-3.1.20260906-r1
AWG userspace tools: amneziawg-tools-3.1.20260812-r1
userspace arch: aarch64_generic
userspace libc: musl
```

Confirmed on the NanoPi R3S LTS:

- kernel module loads;
- `amneziawg` link type works;
- `awg` binary runs;
- `awg` reads AWG 3.1 interface state;
- `awg` writes configuration to the AWG kernel module through generic netlink;
- private/public key operations work;
- test interface create/configure/read/delete lifecycle works.

## Real provider tunnel validation — SUCCESS

On 2026-09-09 three real client profiles were tested one by one with a safe `/32` host route for test traffic only. The system default route remained unchanged through the entire test.

### Cloudflare WARP / full AWG3 profile

Confirmed working with the full AWG3 parameter set, including:

```text
Jc=4
Jmin=40
Jmax=70
I1=<large binary descriptor>
ContentPaddingAddition=27-97
RekeyAfterTime=116-131
RekeyTimeout=6-9
RejectAfterTime=171-196
KeepaliveTimeout=9-16
MaxHandshakeAttempts=18-26
RandomTrailers=on
DisableCookies=on
```

Runtime result:

```text
endpoint: 162.159.195.1:500
ping: 3/3 received, 0% loss
latest handshake: 3 seconds ago
transfer: 440 B received, 2.37 KiB sent
```

### Surfshark Kazakhstan

The provider hostname could not be resolved by the local/system resolver, so the endpoint was resolved externally and tested as `217.9.250.83:51820`.

Runtime result:

```text
Jc=120
Jmin=23
Jmax=911
ping: 3/3 received, 0% loss
latest handshake: 3 seconds ago
transfer: 476 B received, 56.09 KiB sent
```

### Surfshark Luxembourg

The provider hostname could not be resolved by the local/system resolver, so the endpoint was resolved externally and tested as `185.153.151.149:51820`.

Runtime result:

```text
Jc=120
Jmin=23
Jmax=911
ping: 3/3 received, 0% loss
latest handshake: 3 seconds ago
transfer: 476 B received, 51.83 KiB sent
```

For provider testing the harness forces `AdvancedSecurity = on` in the temporary sanitized peer configuration. Provider source files are not modified and are never committed to Git because they contain private keys.

Safety result:

```text
default via 192.168.88.10 dev eth0 proto static src 192.168.88.15
```

was unchanged before, during and after all three tests, and all disposable test interfaces were removed successfully.

## netifd integration — SUCCESS

A custom shell protocol handler `korobka_awg` is now registered by netifd and owns interface lifecycle for the three provider profiles.

The first attempt failed because the handler was copied and only `network reload` was used. netifd therefore did not register the new protocol and reported the interfaces as `proto: none` / `NO_DEVICE`. The handler also originally used the option name `ifname`, which was renamed to `awg_ifname` to avoid ambiguity with netifd device handling.

After installing the corrected helper, recreating UCI sections, committing, and restarting the network service, `ubus call network get_proto_handlers` showed:

```text
korobka_awg
```

with validation fields:

```text
config
awg_ifname
endpoint_ip
tunlink
advanced_security
```

Before `ifup`, all three interfaces were correctly recognized as available custom protocol interfaces:

```text
proto: korobka_awg
available: true
up: false
```

After `ifup awg_warp`, `ifup awg_kz`, and `ifup awg_lu`, all three were simultaneously present and `up`:

```text
awg_warp  172.16.0.2/32  2606:4700:110:8e93:9f56:5e56:4540:311e/128
awg_kz    10.14.0.2/32
awg_lu    10.14.0.2/32
```

The `/32` normalization for the two Surfshark profiles intentionally avoids installing duplicate connected `/16` routes even though both provider configs contain `10.14.0.2/16`.

`ifstatus` confirmed for all three:

```text
up: true
available: true
l3_device: awg_*
proto: korobka_awg
route: []
```

The main default route remained unchanged:

```text
default via 192.168.88.10 dev eth0 proto static src 192.168.88.15
```

This confirms that provider `AllowedIPs = 0.0.0.0/0` is kept inside the AWG peer configuration and is not injected into the main routing table by netifd.

## Simultaneous three-tunnel traffic — SUCCESS

All three netifd-managed AWG interfaces were exercised concurrently while remaining up.

Endpoint host dependencies were present in the main table and all resolved through the physical WAN:

```text
162.159.195.1 via 192.168.88.10 dev eth0
217.9.250.83 via 192.168.88.10 dev eth0
185.153.151.149 via 192.168.88.10 dev eth0
```

Parallel ICMP results to `1.1.1.1`:

```text
awg_warp: 5 transmitted, 5 received, 0% loss
awg_kz:   5 transmitted, 5 received, 0% loss
awg_lu:   5 transmitted, 4 received, 20% loss
```

The Luxembourg profile still had a valid concurrent handshake and bidirectional transfer counters. The single lost ICMP packet is treated as transient path quality, not tunnel failure, because the interface remained up and exchanged traffic.

Concurrent transfer state:

```text
awg_warp: RX 672 B, TX 2623 B
awg_kz:   RX 732 B, TX 54090 B
awg_lu:   RX 604 B, TX 57454 B
```

All three had current handshake timestamps and the expected provider endpoints. The system default route remained unchanged before and after the parallel test:

```text
default via 192.168.88.10 dev eth0 proto static src 192.168.88.15
```

This confirms that the three provider tunnels can coexist and carry traffic concurrently without taking ownership of the system default route.

## Next step

The ABI/userspace/provider/netifd/concurrent-traffic integration phase is complete. Next:

1. enable UCI `auto=1` for `awg_warp`, `awg_kz`, and `awg_lu`;
2. reboot the NanoPi;
3. validate that all three interfaces return automatically with correct addresses and endpoint host routes;
4. confirm fresh handshakes/traffic after reboot while the WAN/default route stays intact;
5. then install and integrate Podkop/sing-box policy routing.
