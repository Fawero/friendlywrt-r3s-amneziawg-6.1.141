# Коробка — документация проекта

Дата актуализации: **9 сентября 2026 года**. Редакция требований: **1.6**.

Этот раздел — актуальная точка входа по тиражируемой Коробке на NanoPi R3S / R3S LTS. Последние проверенные решения и результаты испытаний имеют приоритет над ранними проектными предположениями.

**Статус:** базовое сетевое runtime-ядро собрано и проверено на FriendlyElec NanoPi R3S LTS с FriendlyWrt 25.12.2 и фактическим ядром 6.1.141. Подтверждены AWG 3.1, netifd-owned provider tunnels, Podkop/sing-box, входящий стандартный WireGuard, MTG через отдельный SOCKS->WARP путь, reboot/autostart, диагностика внешнего доступа, live-управление несколькими WG peers без перезапуска сети и backend LuCI-панели `luci-app-korobka`. Backend панели прошёл полный live smoke-test: status, peers, add/remove, input validation, QR readiness gates, manual-forward state, menu/ACL и network safety. First-boot wizard ещё не реализован; визуальный UX самой панели ещё нужно проверить в браузере.

## Документы

| Документ | Содержание |
|---|---|
| [Runtime foundation 2026-09-09](RUNTIME-FOUNDATION-2026-09-09.md) | Фактически проверенная runtime-архитектура: WG, Podkop, MTG, reboot, NAT detection, endpoint/client generation и ограничения |
| [WG peer manager validation 2026-09-09](WG-PEER-VALIDATION-2026-09-09.md) | Проверка add/list/remove/re-add, автоматического адреса, fresh key rotation, live runtime update и отсутствия влияния на AWG/default route |
| [LuCI backend validation 2026-09-09](LUCI-VALIDATION-2026-09-09.md) | Проверка rpcd/ucode backend, status/peers contracts, add/remove RPC lifecycle, QR gates, menu/ACL и network safety |
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

Входящий VPN телефона использует **стандартный WireGuard**, а не AmneziaWG. Серверный ключ и ключ каждого телефона генерируются заново на каждой коробке; ключи старого устройства не мигрируются. Доверенным WG-пирам разрешён доступ к LuCI/SSH самого роутера и к LAN — это отдельное осознанное решение. Собственная панель `luci-app-korobka` остаётся локальным интерфейсом управления и не должна публиковаться напрямую в WAN.

`korobka-wg-peer` умеет перечислять peers, добавлять peer с явным или автоматическим именем, автоматически выделять следующий свободный `10.77.0.x/32`, генерировать новую пару ключей, сохранять UCI и live-обновлять `wg_clients` через `wg set`. Удаление peer убирает его из runtime, UCI, файловой системы и маршрутов. Освобождённый адрес может использоваться снова, но удалённые ключи не восстанавливаются: повторно созданный peer получает новую криптографическую идентичность.

## LuCI-панель

`luci-app-korobka` реализован на современном LuCI JS/RPC стеке без legacy Lua-controller и без generic shell-exec из браузера.

Проверенные страницы:

```text
Коробка
├── Обзор
├── Устройства
├── Telegram
└── Внешний доступ
```

Backend RPC object:

```text
luci.korobka
```

Проверенные методы:

```text
status
peers
add_peer
remove_peer
wg_qr
mtg_qr
set_manual_forward
```

Полный live smoke-test подтвердил корректность status/peers contracts, input validation, disposable peer add/remove lifecycle, QR readiness gates и сохранение network safety. Текущий следующий шаг по панели — открыть четыре страницы в браузере и провести визуальный/UI/UX аудит уже работающего интерфейса.

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

В `rootfs/` сохранены безопасные шаблоны без секретов, включая:

```text
/etc/config/korobka
/etc/init.d/mtg
/usr/bin/korobka-public-access
/usr/bin/korobka-endpoint
/usr/bin/korobka-wg-client
/usr/bin/korobka-wg-peer
/usr/bin/korobka-mtg-access
/usr/bin/korobka-ui-status
/usr/local/sbin/korobka-mtg-run
```

В `luci-app-korobka/` сохранены menu JSON, ACL JSON, rpcd ucode backend и четыре LuCI JS views.

В `scripts/` сохранены воспроизводимые helpers и validators, включая:

- патч known WireGuard netifd bug в 25.12.2;
- установку pinned MTG 2.2.8 ARM64 с SHA256 check;
- создание нового incoming WireGuard server + первого peer;
- конфигурацию MTG через отдельный Podkop SOCKS -> `awg_warp`;
- development installer LuCI-панели;
- полный backend validator LuCI-панели.

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

1. Провести browser/UI/UX validation четырёх страниц `luci-app-korobka` и одним крупным блоком довести внешний вид, понятность статусов, действия и mobile layout.
2. Сделать безопасное ownership/renewal для автоматических UPnP/NAT-PMP mappings перед включением `apply/remove` в production runtime.
3. Перед release image провести отдельный regression: удалить disposable peer, перезагрузить коробку и подтвердить, что удалённый и не пере-добавленный peer не возвращается.
4. После этого оформить first-boot wizard и сборку воспроизводимого образа.

## Правило фиксации

После каждого проверенного блока обновлять runtime-файлы и документацию в GitHub сразу. Не коммитить provider PrivateKeys, WG private keys, MTG secret, generated client configs, access links с secret, пароли, токены, персональные hostname/IP и необезличенные резервные копии.
