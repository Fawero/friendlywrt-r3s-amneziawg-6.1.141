# Сборка AmneziaWG 3.1 под FriendlyWrt kernel 6.1.141

## Найденное рабочее окружение

На сервере Ubuntu 24.04.4 LTS обнаружено прежнее окружение, использованное для успешной сборки AWG 2.0 под ту же коробку:

```text
/home/anatoliy-bormataylo/friendlywrt-awg2-6.1.141/
```

В нём присутствуют:

- `kernel-rockchip/` — подготовленное дерево FriendlyWrt kernel 6.1.141;
- `kernel-rockchip/.config`;
- `kernel-rockchip/Module.symvers`;
- `reference/kernel-6.1.141-r3s.config`;
- `reference/amneziawg.ko`;
- `amneziawg-linux-kernel-module/` — прежние исходники;
- `amneziawg-linux-kernel-module/src/Module.symvers`;
- готовые модули `output/amneziawg.ko` и `output/amneziawg-clean.ko`;
- логи предыдущих сборок;
- build scripts:
  - `~/build-friendlywrt-awg2.sh`
  - `~/rebuild-awg2-clean.sh`
  - `~/continue-awg2-build.sh`.

Это позволило повторно использовать уже подготовленный kernel build tree/toolchain вместо восстановления среды с нуля.

## Целевая версия

На 2026-09-08 выбран upstream tag AmneziaWG `v3.1.20260906`.

Причина: релиз исправляет обработку `RandomTrailers` по сравнению с предыдущими 3.1-тегами.

Важно: `modinfo` собранного модуля показывает внутреннюю версию:

```text
version: 3.1.20260812
```

При этом source tag/commit сборки:

```text
awg_tag=v3.1.20260906
awg_commit=4569c4c67f3a57414969260cafbbd04694fbaae0
```

Для идентификации нашей сборки используем source tag + commit + SHA256, а не только поле `modinfo version`.

## Ограничение FriendlyWrt

На коробке реально загружено kernel `6.1.141`, несмотря на APK metadata от OpenWrt kernel 6.12.74. Поэтому готовые `kmod-amneziawg` APK из OpenWrt feed не использовать. Kernel module собран против сохранённого FriendlyWrt `kernel-rockchip`.

## Compatibility patch для FriendlyARM 6.1.141

Upstream AWG 3.1 использует новый timer API:

```text
timer_delete()
timer_delete_sync()
```

В FriendlyARM kernel 6.1.141 доступны:

```text
del_timer()
del_timer_sync()
```

При этом upstream `src/compat/compat.h` предполагает наличие backport нового timer API в части 6.1.x, которого в данном FriendlyARM tree нет.

Поэтому применяется узкий call-site patch только к:

```text
src/device.c
src/timers.c
```

Замены:

```text
timer_delete()      -> del_timer()
timer_delete_sync() -> del_timer_sync()
```

`src/compat/compat.h` не изменяется.

## Успешная сборка kernel module

Артефакт на build server:

```text
/home/anatoliy-bormataylo/friendlywrt-awg3-6.1.141/output/amneziawg-v3.1.20260906.ko
```

Параметры:

```text
source tag:      v3.1.20260906
source commit:   4569c4c67f3a57414969260cafbbd04694fbaae0
kernelrelease:   6.1.141
module version:  3.1.20260812
vermagic:        6.1.141 SMP mod_unload modversions aarch64
SHA256:          572f4250d8bbd470a46f9dd835efa6ebd90479ab0875c840b1277c949a7844f7
```

ABI validation:

```text
imports=198
found_in_kernel=198
missing=0
crc_mismatches=0
```

## Успешная APK-упаковка

Для FriendlyWrt собран отдельный APK-пакет без стандартного OpenWrt `KernelPackage`, чтобы не получить ложную зависимость на пакетный kernel 6.12.74.

Пакет:

```text
friendlywrt-amneziawg-kmod-3.1.20260906-r1.apk
```

Артефакт:

```text
/home/anatoliy-bormataylo/friendlywrt-awg3-apk/output/friendlywrt-amneziawg-kmod-3.1.20260906-r1.apk
```

Размер: около 55 KiB.

SHA256 APK:

```text
150b13cb67b8a1fcf9764b918248fe873446feb4808e5c00058a326595ece2c3
```

В пакет входят:

```text
/lib/modules/6.1.141/amneziawg.ko
/etc/modules.d/30-amneziawg
/usr/share/korobka/amneziawg-build-info.txt
```

APK recipe:

- проверяет runtime `uname -r == 6.1.141` перед установкой;
- не объявляет стандартную зависимость на OpenWrt kernel 6.12.74;
- использует `Package/friendlywrt-amneziawg-kmod/extra_provides` для runtime-модулей `ip6_udp_tunnel.ko`, `libchacha20poly1305.ko`, `libcurve25519-generic.ko`, `udp_tunnel.ko`;
- не force-load'ит `amneziawg` во время установки;
- регистрирует модуль для будущих загрузок через `/etc/modules.d/30-amneziawg`.

В build log секция `APK METADATA` на Ubuntu SDK печатает ошибку `Unable to read database`, потому что SDK `apk` вызывается вне системной APK database. Это не помешало созданию пакета и не является ошибкой сборки; финальный статус — `SUCCESS`.

## Runtime validation на NanoPi R3S LTS

На чистой FriendlyWrt 25.12.2 / kernel `6.1.141` выполнен полный runtime-тест.

Установка локального APK прошла успешно:

```text
(1/1) Installing friendlywrt-amneziawg-kmod (3.1.20260906-r1)
Executing ...pre-install
Executing ...post-install
OK
```

После установки подтверждено:

```text
/lib/modules/6.1.141/amneziawg.ko
/etc/modules.d/30-amneziawg
/usr/share/korobka/amneziawg-build-info.txt
```

`modinfo` на самой коробке:

```text
version:    3.1.20260812
srcversion: D4E18EBFDD0D26E8105464D
depends:    libcurve25519-generic,udp_tunnel,ip6_udp_tunnel,libchacha20poly1305
vermagic:   6.1.141 SMP mod_unload modversions aarch64
```

`modules.dep` зарегистрирован:

```text
amneziawg.ko: libchacha20poly1305.ko poly1305-neon.ko libcurve25519-generic.ko ip6_udp_tunnel.ko udp_tunnel.ko
```

Первый ручной load:

```text
modprobe amneziawg
```

успешен. В `lsmod` присутствуют `amneziawg` и все зависимости.

Kernel log подтверждает инициализацию:

```text
amneziawg: AmneziaWG 3.1.20260812 loaded. See amnezia.org for information.
```

Также успешно создан и удалён тестовый netlink-интерфейс:

```text
ip link add awg-test type amneziawg
ip -details link show awg-test
ip link del awg-test
```

Интерфейс показывался как:

```text
awg-test: <POINTOPOINT,NOARP> mtu 1420 ...
amneziawg ...
```

После удаления `awg-test` отсутствует.

## Итоговый статус

AWG3 kernel module для этой FriendlyWrt-сборки считается подтверждённо рабочим на реальном железе.

Подтверждено:

- exact kernel ABI `6.1.141`;
- модуль загружается через `modprobe`;
- зависимости разрешаются;
- `amneziawg` link type зарегистрирован;
- тестовый AWG-интерфейс создаётся и удаляется;
- APK корректно устанавливает модуль и регистрирует автозагрузку.

Следующий этап:

1. `amneziawg-tools` userspace;
2. `luci-proto-amneziawg`;
3. импорт реального AWG/WG client config;
4. проверка handshake и трафика;
5. затем интеграция с Podkop/sing-box и панелью Коробки.
