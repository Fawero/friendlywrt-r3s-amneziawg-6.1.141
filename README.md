# AmneziaWG module for FriendlyWrt NanoPi R3S

## Проект «Коробка»: актуальная документация

С 8 сентября 2026 года здесь также ведётся проект тиражируемой коробки: AmneziaWG с LuCI, Podkop, MTG, входящий WireGuard, локальная панель с QR и чистый образ microSD с персонализацией.

**Начать с [документации Коробки](docs/korobka/README.md).** Там сохранены требования, сценарий первого запуска, архитектура, журнал решений, этапы и приёмка. Последние уточнения: импорт конфигураций доступен постоянно; дополнительного VPS и ручного ввода внешнего IP/портов нет; панель только из домашней LAN.

**Текущий этап — обследование новой коробки.** [Read-only скрипт](scripts/korobka-audit-readonly.sh) не меняет настройки и не устанавливает пакеты. Мастер, панель и новый образ ещё не реализованы. Существующий модуль не объявляется сборкой AWG 3.1.

> Ниже сохранена историческая инструкция для прежнего стенда. Она не является установщиком нового продукта. Упоминаемый `setup-awg-podkop-boot.sh` отсутствует в просмотренном дереве репозитория на 08.09.2026: блок его скачивания и запуска не выполнять как готовую инструкцию. Первую рабочую коробку и MikroTik при обследовании второй не менять. Не загружать в публичный репозиторий личные конфиги, ключи и необезличенную диагностику.

---

Готовый kernel-модуль `amneziawg.ko` для NanoPi R3S / R3S LTS на FriendlyWrt 25.12.2 с ядром `6.1.141`.

## 1. Окружение

| Параметр | Значение |
|---|---|
| Устройство | NanoPi R3S / R3S LTS |
| ОС | FriendlyWrt 25.12.2 |
| Target | rockchip / armv8 |
| Архитектура | aarch64 |
| Kernel | 6.1.141 |
| Module vermagic | `6.1.141 SMP mod_unload modversions aarch64` |

## 2. Состав репозитория

| Файл | Назначение |
|---|---|
| `amneziawg.ko` | kernel-модуль AmneziaWG |
| `install-amneziawg.sh` | установка и регистрация модуля на роутере |
| `setup-awg-podkop-boot.sh` | настройка корректного порядка запуска WAN → AWG → Podkop → sing-box |
| `device-kernel-info.txt` | информация об устройстве и ядре |
| `kernel-6.1.141-r3s.config` | reference-конфиг ядра |
| `build-info.txt` | информация о сборке |

## 3. Важная особенность FriendlyWrt 25.12.2

Простого копирования модуля в каталог:

```sh
/lib/modules/6.1.141/extra/amneziawg.ko
```

недостаточно для стабильной работы после перезагрузки.

На этой сборке `modprobe amneziawg` не находит модуль, если он не зарегистрирован в `modules.dep`. Поэтому установщик делает три вещи:

1. копирует модуль в `extra`:

```sh
/lib/modules/6.1.141/extra/amneziawg.ko
```

2. дополнительно копирует модуль в корень каталога модулей:

```sh
/lib/modules/6.1.141/amneziawg.ko
```

3. добавляет запись в:

```sh
/lib/modules/6.1.141/modules.dep
```

Ожидаемая строка:

```text
amneziawg.ko: libchacha20poly1305.ko poly1305-neon.ko libcurve25519-generic.ko ip6_udp_tunnel.ko udp_tunnel.ko
```

После этого `modprobe amneziawg` работает и модуль поднимается после reboot.

## 4. Установка модуля на роутер

Выполнить на NanoPi R3S:

```sh
cd /tmp

wget -O amneziawg.ko https://raw.githubusercontent.com/Fawero/friendlywrt-r3s-amneziawg-6.1.141/main/amneziawg.ko
wget -O install-amneziawg.sh https://raw.githubusercontent.com/Fawero/friendlywrt-r3s-amneziawg-6.1.141/main/install-amneziawg.sh

chmod +x install-amneziawg.sh
./install-amneziawg.sh
```

Проверка:

```sh
modprobe amneziawg
lsmod | grep -Ei 'amneziawg|wireguard|chacha|curve|udp_tunnel'
```

Ожидаемый результат:

```text
amneziawg
libchacha20poly1305
libcurve25519_generic
udp_tunnel
ip6_udp_tunnel
```

## 5. Настройка корректного запуска AWG + Podkop

Проблема: Podkop и sing-box могут стартовать раньше, чем WAN и AWG готовы. Это приводит к циклам DNS, ошибкам загрузки rule-set и падению sing-box.

Рабочая схема запуска:

```text
WAN up → временный чистый DNS → загрузка amneziawg → ifup AWG → запуск Podkop → запуск sing-box
```

Для этого штатный ранний автозапуск Podkop/sing-box отключается, а запуск выполняется через hotplug-скрипт после поднятия WAN.

Установка:

```sh
cd /tmp

wget -O setup-awg-podkop-boot.sh https://raw.githubusercontent.com/Fawero/friendlywrt-r3s-amneziawg-6.1.141/main/setup-awg-podkop-boot.sh

chmod +x setup-awg-podkop-boot.sh
AWG_ENDPOINT_HOST=217.9.250.101 ./setup-awg-podkop-boot.sh
```

`AWG_ENDPOINT_HOST` лучше указывать IP-адресом, чтобы AWG не зависел от DNS на этапе старта.

## 6. Что не нужно включать обратно

После установки controlled startup не включать ранний автозапуск:

```sh
/etc/init.d/podkop enable
/etc/init.d/sing-box enable
uci set network.AWG.auto='1'
```

Подъём стека должен идти через:

```sh
/etc/hotplug.d/iface/99-awg-after-wan
```

## 7. Проверка AWG

```sh
echo "=== AWG interface ==="
ip -br addr | grep -Ei 'AWG|awg|tun' || true

echo "=== AWG state ==="
awg show AWG 2>/dev/null || true
```

Успешный результат:

```text
AWG UNKNOWN 10.14.0.2/16
latest handshake
transfer
```

Если есть `latest handshake` и растёт `transfer`, туннель работает.

## 8. Проверка Podkop и sing-box

```sh
echo "=== sing-box ==="
/etc/init.d/sing-box status || true
ps w | grep -i sing-box | grep -v grep || true

echo "=== Podkop nft rules ==="
nft list ruleset | grep -Ei 'PodkopTable|tproxy|podkop_subnets|mark' | head -120
```

Успешный результат:

```text
sing-box: running
PodkopTable exists
tproxy counters grow
```

Важно: `/etc/init.d/podkop status` может показывать `not running`. Это не всегда ошибка. Podkop в этой схеме в основном генерирует конфигурацию nft/sing-box и может не висеть как постоянный daemon. Реальные признаки работы:

- `sing-box` запущен;
- есть таблица `PodkopTable`;
- растут счётчики TPROXY;
- DNS работает через роутер;
- AWG имеет handshake.

## 9. Проверка DNS

```sh
nslookup github.com 127.0.0.1
nslookup google.com 127.0.0.1
```

Если DNS не работает, сначала проверить:

```sh
logread | grep -Ei 'DNS is unavailable|sing-box|podkop|awg-after-wan|FATAL' | tail -120
```

## 10. Проверка внешнего IP

```sh
wget -qO- https://ifconfig.me/ip 2>/dev/null || true
echo
```

Если сервис вернул HTML вместо IP, использовать:

```sh
wget -qO- https://api.ipify.org 2>/dev/null || true
echo
```

## 11. Финальная проверка после reboot

```sh
reboot
```

После перезагрузки:

```sh
echo "=== module ==="
modprobe amneziawg 2>&1 || true
lsmod | grep -Ei 'amneziawg|wireguard|chacha|curve|udp_tunnel' || true

echo "=== AWG ==="
ip -br addr | grep -Ei 'AWG|awg|tun' || true
awg show AWG 2>/dev/null || true

echo "=== sing-box ==="
/etc/init.d/sing-box status || true
ps w | grep -i sing-box | grep -v grep || true

echo "=== podkop counters ==="
nft list ruleset | grep -Ei 'tproxy|podkop_subnets|counter packets' | head -160

echo "=== critical logs ==="
logread | grep -Ei 'awg-after-wan|FATAL|DNS is unavailable|modprobe failed|ifup AWG failed|podkop start failed' | tail -120
```

## 12. Признаки успешной работы

| Проверка | Ожидаемый результат |
|---|---|
| `lsmod` | есть `amneziawg` |
| `awg show AWG` | есть `latest handshake` |
| `ip -br addr` | у `AWG` есть `10.14.0.2/16` |
| `sing-box status` | `running` |
| `nft list ruleset` | есть `PodkopTable` |
| TPROXY counters | растут пакеты/байты |
| DNS | `nslookup` через `127.0.0.1` работает |

## 13. Ограничения

Модуль собран строго под ядро:

```text
6.1.141
```

Если FriendlyWrt обновит ядро, модуль нужно пересобрать. Проверить текущую версию ядра:

```sh
uname -r
```

Если версия отличается от `6.1.141`, использовать этот модуль нельзя.
