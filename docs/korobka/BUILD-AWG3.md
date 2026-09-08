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

## Успешная сборка

Сборка AWG 3.1 под FriendlyWrt kernel 6.1.141 завершена успешно.

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

Это означает, что все импортируемые модулем kernel symbols найдены в сохранённом `Module.symvers`, и CRC совпадают.

## Текущий статус

Модуль считается кандидатом для runtime-теста на чистой коробке, но пока не устанавливается постоянно и не добавляется в автозагрузку.

Следующий шаг:

1. перенести `.ko` на коробку во `/tmp`;
2. проверить SHA256 и `modinfo` уже на коробке;
3. выполнить временный `insmod`;
4. проверить `lsmod` и kernel log;
5. создать и удалить тестовый link типа `amneziawg` без настройки ключей;
6. только после успешного runtime-теста регистрировать модуль постоянно;
7. затем переходить к `amneziawg-tools` и `luci-proto-amneziawg`.
