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

## Next runtime validation

Before installing on the NanoPi R3S LTS, verify that the existing FriendlyWrt userspace provides:

```text
/lib/libgcc_s.so.1
/lib/ld-musl-aarch64.so.1
```

Then install the local APK with `apk --allow-untrusted add`, confirm `awg` runs, and validate userspace/kernel communication against the already-tested `amneziawg.ko` on kernel 6.1.141.
