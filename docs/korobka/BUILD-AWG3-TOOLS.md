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

## Next step

The next functional test is no longer basic ABI/userspace compatibility. It is importing a real provider AWG/WG client configuration and validating an actual handshake and tunneled traffic. After that, integrate the interface lifecycle with netifd/Korobka and then Podkop/sing-box policy routing.
