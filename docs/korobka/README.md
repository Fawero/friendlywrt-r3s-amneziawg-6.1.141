# Коробка — документация проекта

Дата актуализации: **9 сентября 2026 года**. Редакция требований: **1.8**.

Этот раздел — актуальная точка входа по тиражируемой Коробке на NanoPi R3S / R3S LTS. Последние проверенные решения и результаты испытаний имеют приоритет над ранними проектными предположениями.

**Статус:** базовое сетевое runtime-ядро собрано и проверено на FriendlyElec NanoPi R3S LTS с FriendlyWrt 25.12.2 и фактическим ядром 6.1.141. Подтверждены AWG 3.1, netifd-owned provider tunnels, Podkop/sing-box, входящий стандартный WireGuard, MTG через отдельный SOCKS->WARP путь, reboot/autostart, диагностика внешнего доступа, live-управление несколькими WG peers без перезапуска сети и backend LuCI-панели `luci-app-korobka`.

LuCI backend прошёл полный live smoke-test, performance-блок V5 подтвердил cached status около 1 секунды, а отдельный support/local-management milestone прошёл полный live lifecycle. Проверены transit LAN `192.168.77.1/24`, `korobka.home.arpa`, DHCP/DNS для WAN домашнего роутера, отдельный временный key-only Dropbear на случайном WAN-порту, QR support bundle, ручное отключение, 24h TTL-модель, короткий auto-expiry и полная очистка listener/firewall/ключей. V6 visual candidate остаётся на browser/UI validation. First-boot wizard ещё не реализован.

## Документы

| Документ | Содержание |
|---|---|
| [Runtime foundation 2026-09-09](RUNTIME-FOUNDATION-2026-09-09.md) | Фактически проверенная runtime-архитектура: WG, Podkop, MTG, reboot, NAT detection, endpoint/client generation и ограничения |
| [WG peer manager validation 2026-09-09](WG-PEER-VALIDATION-2026-09-09.md) | Проверка add/list/remove/re-add, автоматического адреса, fresh key rotation, live runtime update и отсутствия влияния на AWG/default route |
| [LuCI backend validation 2026-09-09](LUCI-VALIDATION-2026-09-09.md) | Проверка rpcd/ucode backend, status/peers contracts, add/remove RPC lifecycle, QR gates, menu/ACL и network safety |
| [Support + local validation 2026-09-09](SUPPORT-LOCAL-VALIDATION-2026-09-09.md) | Проверка `192.168.77.1`, `korobka.home.arpa`, временного support SSH, QR, disable/expiry cleanup и network safety |
| [Support and discovery](SUPPORT-AND-DISCOVERY.md) | Продуктовая топология Провайдер -> Коробка -> домашний роутер, локальное управление и временный сервисный доступ |
| [Требования и первый запуск](FIRST-BOOT.md) | Мастер, постоянный импорт конфигураций, назначения, белый IP, телефон и QR-коды |
| [Архитектура](ARCHITECTURE.md) | AWG, Podkop, MTG, входящий WireGuard, управление и запуск без гонок |
| [Podkop](PODKOP.md) | Установка, миграция старой политики и правила владения маршрутизацией |
| [Образ, обследование и приёмка](DELIVERY-AND-TESTS.md) | Чистый образ, персонализация, обновления, этапы и критерии готовности |
| [Журнал решений](DECISIONS.md) | Принятые требования, отменённые варианты, предложения и открытые вопросы |
| [Read-only обследование](../../scripts/korobka-audit-readonly.sh) | Инвентаризация коробки без установки и изменения сетевой конфигурации |

## Суть продукта

Один воспроизводимый образ microSD с ПО, шаблонами и проверенным пресетом. После локальной активации каждый экземпляр получает собственные ключи, секреты и загруженные владельцем provider-конфигурации. Персонализированную рабочую карту не используем как общий образ для других владельцев.

```text
Провайдер -> Коробка -> домашний роутер -> домашние устройства
Домашние устройства -> Podkop -> выбранный исходящий AWG -> интернет
Телефон -> входящий wg_clients -> Podkop -> policy routing / домашняя сеть / интернет
Telegram client -> MTG :8888 -> 127.0.0.1:4534 -> awg_warp -> Telegram
```

Проверенные исходящие интерфейсы текущего эталона: `awg_warp`, `awg_lu`, `awg_kz`. Это назначения текущей конфигурации, а не продуктовый лимит числа provider-профилей.

Входящий VPN телефона использует **стандартный WireGuard**, а не AmneziaWG. Серверный ключ и ключ каждого телефона генерируются заново на каждой коробке; ключи старого устройства не мигрируются. Доверенным WG-пирам разрешён доступ к LuCI/SSH самого роутера и к LAN — это отдельное осознанное решение. Собственная панель `luci-app-korobka` остаётся локальным интерфейсом управления и не должна публиковаться напрямую в WAN.

`korobka-wg-peer` умеет перечислять peers, добавлять peer с явным или автоматическим именем, автоматически выделять следующий свободный `10.77.0.x/32`, генерировать новую пару ключей, сохранять UCI и live-обновлять `wg_clients` через `wg set`. Удаление peer убирает его из runtime, UCI, файловой системы и маршрутов. Освобождённый адрес может использоваться снова, но удалённые ключи не восстанавливаются: повторно созданный peer получает новую криптографическую идентичность.

## Локальное управление

Базовая transit-сеть между Коробкой и WAN домашнего роутера:

```text
Коробка LAN: 192.168.77.1/24
Домашний роутер WAN: DHCP из 192.168.77.0/24
Gateway: 192.168.77.1
DNS: 192.168.77.1
```

Коробка публикует локальную DNS-запись:

```text
korobka.home.arpa -> 192.168.77.1
```

Основной адрес управления:

```text
https://korobka.home.arpa/
```

Fallback:

```text
https://192.168.77.1/
```

Live validation подтвердила DNS-разрешение и ответ LuCI по HTTPS на transit IP. Конкретная transit-подсеть должна проверяться на конфликт при first boot; `192.168.77.0/24` — product default, а не безусловно свободная сеть для любой инсталляции.

## Временная техподдержка

`korobka-support` реализует отдельную support-сессию, не меняя основной Dropbear/SSH пользователя.

Проверенная модель:

- support выключен по умолчанию;
- случайный TCP-порт `30000-59999` на каждую сессию;
- новая Ed25519 key pair на каждую сессию;
- отдельный Dropbear `authorized_keys` directory;
- password auth support-listener отключён;
- port forwarding support-listener отключён;
- временный WAN firewall rule только для выбранного порта;
- максимальный TTL 24 часа;
- QR support bundle для передачи техподдержке;
- `disable` синхронно удаляет listener/firewall/ключи;
- auto-expiry удаляет их автоматически;
- validator имеет fail-safe cleanup и не оставляет тестовые support-сессии после ошибки.

На текущем стенде WAN Коробки находится за дополнительным upstream NAT, поэтому `reachable=false` корректен. В боевой схеме с direct public WAN временный support-порт доступен непосредственно на Коробке; при provider CGNAT нужен будущий reverse support relay.

## LuCI-панель

`luci-app-korobka` реализован на современном LuCI JS/RPC стеке без legacy Lua-controller и без generic shell-exec из браузера.

Страницы:

```text
Коробка
├── Обзор
├── Устройства
├── Telegram
├── Внешний доступ
└── Техподдержка
```

Backend RPC object:

```text
luci.korobka
```

Проверенные методы:

```text
status
refresh_access
peers
add_peer
remove_peer
wg_qr
mtg_qr
support_enable
support_disable
support_qr
set_manual_forward
```

Performance architecture панели:

- обычный `status` использует cached/local state и не ждёт внешних timeout-ов;
- глубокая проверка public IPv4 / UPnP / NAT-PMP запускается отдельным `refresh_access`;
- normal page load не выполняет повторные external probes;
- страница Devices использует peers уже из `status` и не делает дополнительный RPC на загрузке;
- backend QR gate остаётся строгим: рабочие секретные конфиги выдаются только при `endpoint.ready=true`;
- UI-кнопки QR остаются кликабельными и при неготовом endpoint объясняют следующий шаг вместо немой disabled-кнопки.

V5 live validation показал cached status около 1 секунды и explicit network refresh около 6 секунд на текущем стенде. V6 visual candidate добавляет общий CSS, единые карточки, badges, callouts, responsive layout и переработанные экраны Overview / Devices / Telegram / External Access / Support. До browser validation V6 считается candidate, а не validated UI.

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

Support-service включён в автозапуск, но без активной support-сессии ничего не слушает. Для активной сессии reboot/expiry regression ещё нужно провести отдельно перед release image.

## Runtime-файлы в репозитории

В `rootfs/` сохранены безопасные шаблоны без секретов, включая:

```text
/etc/config/korobka
/etc/init.d/mtg
/etc/init.d/korobka-support
/usr/bin/korobka-public-access
/usr/bin/korobka-endpoint
/usr/bin/korobka-wg-client
/usr/bin/korobka-wg-peer
/usr/bin/korobka-mtg-access
/usr/bin/korobka-ui-status
/usr/bin/korobka-local-management
/usr/bin/korobka-support
/usr/local/sbin/korobka-mtg-run
/usr/local/sbin/korobka-support-run
```

В `luci-app-korobka/` сохранены menu JSON, ACL JSON, rpcd ucode backend, LuCI JS views и общий visual stylesheet `korobka.css`.

В `scripts/` сохранены воспроизводимые helpers и validators, включая:

- патч known WireGuard netifd bug в 25.12.2;
- установку pinned MTG 2.2.8 ARM64 с SHA256 check;
- создание нового incoming WireGuard server + первого peer;
- конфигурацию MTG через отдельный Podkop SOCKS -> `awg_warp`;
- development installer LuCI-панели;
- backend/performance/UI-asset validator LuCI-панели;
- read-only preflight support/local-management;
- installer support/local-management;
- полный support/local lifecycle validator.

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

1. Провести browser/UI validation V6, включая новую страницу `Техподдержка` и QR UX.
2. Подключить реальный домашний роутер WAN-портом к LAN Коробки и проверить DHCP/DNS/доступ к `korobka.home.arpa` уже с устройства за его NAT/Wi-Fi.
3. Перед release image провести reboot regression активной support-сессии и regression удаления disposable WG peer.
4. Сделать reverse support relay для provider CGNAT и безопасное ownership/renewal для UPnP/NAT-PMP mappings.
5. После этого оформить first-boot wizard и сборку воспроизводимого образа.

## Правило фиксации

После каждого проверенного блока обновлять runtime-файлы и документацию в GitHub сразу. Не коммитить provider PrivateKeys, WG private keys, MTG secret, generated client configs, support private keys/bundles, access links с secret, пароли, токены, персональные hostname/IP и необезличенные резервные копии.
