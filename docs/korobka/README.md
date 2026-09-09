# Коробка — документация проекта

Дата актуализации: **9 сентября 2026 года**. Редакция требований: **1.3**.

Этот раздел — актуальная точка входа по тиражируемой Коробке на NanoPi R3S / R3S LTS. Последние проверенные решения и результаты испытаний имеют приоритет над ранними проектными предположениями.

**Статус:** базовое сетевое runtime-ядро уже собрано и проверено на FriendlyElec NanoPi R3S LTS с FriendlyWrt 25.12.2 и фактическим ядром 6.1.141. Подтверждены AWG 3.1, netifd-owned provider tunnels, Podkop/sing-box, входящий стандартный WireGuard, MTG через отдельный SOCKS->WARP путь, reboot/autostart и диагностика внешнего доступа. LuCI-панель `luci-app-korobka`, first-boot wizard и менеджер множества WG peers ещё не реализованы.

## Документы

| Документ | Содержание |
|---|---|
| [Runtime foundation 2026-09-09](RUNTIME-FOUNDATION-2026-09-09.md) | Фактически проверенная runtime-архитектура: WG, Podkop, MTG, reboot, NAT detection, endpoint/client generation и ограничения |
| [Требования и первый запуск](FIRST-BOOT.md) | Мастер, постоянный импорт конфигураций, назначения, белый IP, телефон и QR-коды |
| [Архитектура](ARCHITECTURE.md) | AWG, Podkop, MTG, входящий WireGuard, управление и запуск без гонок |
| [Podkop](PODKOP.md) | Установка, миграция старой политики и правила владения маршрутизацией |
| [Образ, обследование и приёмка](DELIVERY-AND-TESTS.md) | Чистый образ, персонализация, обновления, этапы и критерии готовности |
| [Журнал решений](DECISIONS.md) | Принятые требования, отменённые варианты, предложения и открытые вопросы |
| [Read-only обследование](../../scripts/korobka-audit-readonly.sh) | Инвентаризация коробки без установки и изменения сетевой конфигурации |

## Суть продукта

Один воспроизводимый образ microSD с ПО, шаблонами и проверенным пресетом. После локальной активации каждый экземпляр получает собственные ключи, секреты и загруженные владельцем provider-конфигурации. Персонализированную рабочую карту не используем как общий образ для других владельцев.

```text
Домашние устройства -> Podkop -> выбранный исходящий AWG -> интернет
Телефон -> входящий wg_clients -> Podkop -> policy routing / домашняя сеть / интернет
Telegram client -> MTG :8888 -> 127.0.0.1:4534 -> awg_warp -> Telegram
```

Проверенные исходящие интерфейсы текущего эталона: `awg_warp`, `awg_lu`, `awg_kz`. Это назначения текущей конфигурации, а не продуктовый лимит числа provider-профилей.

Входящий VPN телефона использует **стандартный WireGuard**, а не AmneziaWG. Серверный ключ и ключ каждого телефона генерируются заново на каждой коробке; ключи старого устройства не мигрируются. Доверенным WG-пирам разрешён доступ к LuCI/SSH самого роутера и к LAN — это отдельное осознанное решение. Будущая собственная панель `luci-app-korobka` остаётся локальным интерфейсом управления и не должна публиковаться напрямую в WAN.

## Внешний доступ

DDNS в продукт не входит. Endpoint строится только из текущего public IPv4.

Предпочтительный сценарий — белый статический IPv4. Если public IPv4 динамический и меняется, ранее созданные WG client configs и MTG access links требуют обновления.

`korobka-public-access` различает прямой public WAN, upstream NAT с UPnP/NAT-PMP, upstream NAT без automap и предполагаемый CGNAT/nested NAT. Private WAN сам по себе не считается доказанным CGNAT.

Для ручного upstream NAT используются только необходимые входящие порты:

```text
UDP 51821 -> WireGuard
TCP 8888  -> MTG
```

Вендор upstream-роутера продукту не известен и не должен быть зашит в логику.

## Проверенный запуск без гонок

Жизненный цикл provider AWG принадлежит netifd. Жизненный цикл Podkop/sing-box принадлежит Podkop. MTG запускается через readiness wrapper и ждёт появления локального SOCKS `127.0.0.1:4534`.

После полного reboot проверено автоматическое восстановление:

```text
WAN -> AWG interfaces -> Podkop/sing-box -> SOCKS ready -> MTG
```

Старые hotplug-скрипты, ручные stop/start гонки и временная подмена DNS не мигрируются.

## Runtime-файлы в репозитории

В `rootfs/` уже сохранены безопасные шаблоны без секретов:

```text
/etc/config/korobka
/etc/init.d/mtg
/usr/bin/korobka-public-access
/usr/bin/korobka-endpoint
/usr/bin/korobka-wg-client
/usr/bin/korobka-mtg-access
/usr/local/sbin/korobka-mtg-run
```

В `scripts/` сохранены воспроизводимые helpers для:

- патча known WireGuard netifd bug в 25.12.2;
- установки pinned MTG 2.2.8 ARM64 с SHA256 check;
- создания нового incoming WireGuard server + первого peer;
- конфигурации MTG через отдельный Podkop SOCKS -> `awg_warp`.

## Критическое ограничение FriendlyWrt

Эталонная коробка — hybrid runtime:

```text
фактическое ядро: 6.1.141
APK metadata kernel: 6.12.74
```

Поэтому:

- **никогда не выполнять `apk upgrade`;**
- не устанавливать вслепую official `kmod-*`;
- каждый новый пакет сначала проверять через `apk add --simulate` и прекращать установку при ошибке simulation;
- runtime kernel modules использовать только с точным ABI 6.1.141.

## Следующая точка продолжения

1. Реализовать `korobka-wg-peer` с `add/list/remove`, свежими ключами и автоматическим выделением `10.77.0.x/32`.
2. Сделать безопасное ownership/renewal для автоматических UPnP/NAT-PMP mappings перед включением `apply/remove` в production runtime.
3. Собрать `luci-app-korobka` поверх уже существующих CLI contracts.
4. После этого оформить first-boot wizard и сборку воспроизводимого образа.

## Правило фиксации

После каждого проверенного блока обновлять runtime-файлы и документацию в GitHub сразу. Не коммитить provider PrivateKeys, WG private keys, MTG secret, generated client configs, access links с secret, пароли, токены, персональные hostname/IP и необезличенные резервные копии.
