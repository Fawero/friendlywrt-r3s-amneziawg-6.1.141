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

Это позволяет повторно использовать уже подготовленный kernel build tree/toolchain вместо восстановления среды с нуля.

## Целевая версия

На 2026-09-08 целимся в kernel module AmneziaWG `v3.1.20260906`.

Причина: релиз 2026-09-07 обновил модуль с `v3.1.20260828` до `v3.1.20260906` и исправил обработку `RandomTrailers` (они больше не добавляются к I1-I5 и junk-пакетам). Предыдущие теги 3.1.20260812–3.1.20260828 имеют подтверждённые проблемы вокруг RandomTrailers/классификации пакетов.

Userspace/LuCI должны быть согласованы с AWG 3.1; целевой LuCI — `luci-proto-amneziawg 3.1.1` либо более свежий совместимый вариант после проверки.

## Ограничение FriendlyWrt

На коробке реально загружено kernel `6.1.141`, несмотря на APK metadata от OpenWrt kernel 6.12.74. Поэтому готовые `kmod-amneziawg` APK из OpenWrt feed не использовать. Kernel module должен быть собран против сохранённого FriendlyWrt `kernel-rockchip` и иметь:

```text
vermagic: 6.1.141 SMP mod_unload modversions aarch64
```

## Следующий шаг

Перед изменением старого build tree снять точные параметры прежней сборки:

- содержимое трёх build scripts;
- git remote / branch / commit старых исходников AWG;
- git remote / branch / commit `kernel-rockchip`;
- cross-compiler/toolchain, используемый скриптами;
- `make kernelrelease`, `ARCH`, `CROSS_COMPILE`;
- `modinfo` старого успешно собранного `output/amneziawg.ko`.

После этого создать отдельный каталог для AWG 3.1, не ломая рабочую AWG 2.0 среду, checkout `v3.1.20260906`, собрать внешний модуль против существующего `kernel-rockchip`, проверить `modinfo` и только затем переносить модуль на тестовую коробку.
