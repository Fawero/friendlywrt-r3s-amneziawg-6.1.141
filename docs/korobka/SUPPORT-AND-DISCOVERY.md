# Коробка — сервисный доступ и локальное обнаружение

Дата: 9 сентября 2026 года.

Документ фиксирует следующий крупный продуктовый блок после базового `luci-app-korobka`: временный доступ техподдержки и стабильный локальный адрес Коробки.

## 0. Фактическая топология продукта

Базовая схема Коробки:

```text
Провайдер
   |
 [WAN]
 Коробка
 [LAN]
   |
 [WAN]
 Домашний роутер
 [LAN / Wi-Fi]
   |
 домашние устройства
```

Это принципиально важно для обоих сценариев ниже.

- Коробка стоит **до** домашнего роутера и является его upstream gateway.
- Домашний NAT находится **после** Коробки и не мешает входящему support SSH на WAN Коробки.
- Домашние клиенты находятся за отдельным routed/NAT сегментом, поэтому mDNS `.local` через домашний роутер по умолчанию не является надёжным zero-config механизмом.

## 1. Техподдержка

### Цель

Пользователь должен иметь возможность явно включить временный удалённый доступ для техподдержки из панели Коробки. Доступ не должен существовать постоянно и не должен менять основной SSH-доступ пользователя.

### UX

В LuCI появляется блок `Техподдержка`.

По умолчанию:

- доступ выключен;
- входящий support SSH отсутствует;
- временные ключи и firewall rules отсутствуют.

При нажатии `Включить техподдержку`:

1. создаётся новая support-сессия;
2. генерируется случайный TCP-порт из высокого диапазона;
3. генерируется отдельная временная SSH key pair;
4. поднимается отдельный Dropbear listener только для support-сессии;
5. password authentication для support listener отключён;
6. временный public key добавляется к разрешённым root keys с уникальным session marker;
7. firewall открывает только случайный support-порт на WAN;
8. создаётся TTL 24 часа;
9. watchdog автоматически отключает доступ после expiry;
10. пользователь может отключить доступ вручную в любой момент.

Панель показывает:

- статус `Поддержка включена`;
- оставшееся время;
- время автоматического отключения;
- public IPv4 / relay hostname;
- случайный порт;
- session ID;
- QR `Support bundle`;
- кнопку `Отключить сейчас`.

QR support bundle содержит секретный комплект подключения, достаточный для техподдержки. Обычным текстом private key не показывается. В интерфейсе отдельно объясняется: QR/фото содержит временный секрет и его следует передавать только сотруднику поддержки.

### Почему key-only, а не временный root password

Не менять root password и не включать password auth на основном SSH. Support-сессия получает отдельный одноразовый key и отдельный listener. После завершения сессии private/public key, listener и firewall rule удаляются.

### Сетевые режимы

Support manager использует существующую диагностику `korobka-public-access`.

#### Direct public WAN

Если WAN Коробки имеет реальный public IPv4, случайный support-порт открывается непосредственно на Коробке.

Домашний роутер и его NAT в этом сценарии не участвуют: он расположен ниже Коробки.

#### Provider CGNAT / upstream provider NAT

Если провайдер не даёт входящий public IPv4, случайный WAN-порт Коробки из Интернета недоступен независимо от домашнего роутера.

Для production-поддержки в таком режиме нужен reverse-support relay:

```text
Коробка -> исходящее соединение -> Support Relay / VPS <- техподдержка
```

Это отдельный следующий этап и универсальный fallback для CGNAT.

#### Upstream NAT перед Коробкой

Если в конкретной инсталляции всё же существует отдельный ONT/router перед WAN Коробки, применяются существующие режимы `korobka-public-access`: UPnP/NAT-PMP при безопасном ownership либо ручной port-forward. Но это не базовая продуктовая схема.

### Безопасность

- default deny;
- support disabled by default;
- TTL не более 24 часов;
- пользователь может выключить раньше;
- новый порт и новая key pair на каждую сессию;
- никакого повторного использования support secret;
- password auth support listener запрещён;
- не менять основной Dropbear instance;
- не публиковать LuCI вместе с support SSH;
- private support bundle не логировать;
- после disable/expiry удалить ключ, firewall rule, listener, state и временные файлы;
- reboot должен либо восстановить только неистёкшую сессию с прежним expiry, либо безопасно отключить её; поведение должно быть явно протестировано.

### Предлагаемый runtime contract

```text
korobka-support status
korobka-support enable
korobka-support disable
korobka-support bundle
```

`status` не возвращает private key.

Пример безопасного status JSON:

```json
{
  "enabled": true,
  "session_id": "KRBX-AB12CD34",
  "port": 43127,
  "expires_at": 1789050000,
  "seconds_left": 81234,
  "network_mode": "direct_public",
  "reachable": true
}
```

## 2. Локальный адрес Коробки

### Почему `korobka.local` больше не основной вариант

Домашние устройства находятся за WAN домашнего роутера, то есть не в одном L2 broadcast domain с LAN Коробки.

Обычный mDNS `.local` через routed/NAT границу домашнего роутера не обязан проходить. Мы не должны требовать от произвольного домашнего роутера mDNS reflector/repeater.

Поэтому основной product hostname для этой топологии:

```text
korobka.home.arpa
```

`home.arpa` используется для локального unicast DNS и подходит именно для routed домашней сети.

### Стабильный management IP

Коробка сама является gateway для WAN домашнего роутера. Поэтому основной fallback — стабильный IP LAN-интерфейса Коробки в transit-сети между Коробкой и домашним роутером.

Предлагаемый product default:

```text
Korobka LAN / management: 192.168.77.1/24
Home-router WAN:          DHCP из 192.168.77.0/24
```

Тогда устройства за домашним роутером обычно могут открыть:

```text
http://192.168.77.1/
https://192.168.77.1/
```

Трафик идёт через WAN домашнего роутера к его upstream gateway — Коробке.

Конкретная transit-подсеть должна быть конфигурируемой и проверяться на конфликт с домашней LAN-сетью. Нельзя безусловно считать `192.168.77.0/24` свободной во всех инсталляциях.

### DNS-схема

Коробка является upstream DHCP/DNS для WAN домашнего роутера.

Базовая схема:

1. DHCP Коробки выдаёт WAN домашнего роутера:
   - gateway = LAN IP Коробки;
   - DNS = LAN IP Коробки;
2. dnsmasq Коробки содержит локальную запись:

```text
korobka.home.arpa -> LAN management IP Коробки
```

3. обычный домашний роутер, работающий как DNS proxy/forwarder, передаёт запрос клиента upstream DNS Коробки;
4. пользователь открывает:

```text
https://korobka.home.arpa/
```

Для остальных DNS-запросов Коробка продолжает использовать свою штатную DNS/Podkop-схему.

### Compatibility fallback

Не все домашние роутеры обязаны использовать DNS, полученный по WAN DHCP. Некоторые могут использовать собственный DoH/DoT или жёстко заданный resolver.

Поэтому UI всегда показывает оба адреса:

```text
Основной: https://korobka.home.arpa/
Fallback: https://192.168.77.1/
```

На первом этапе не перехватывать весь DNS downstream-роутера принудительно. DNS interception можно добавить позднее как отдельную opt-in функцию после проверки совместимости с Podkop и пользовательскими DNS-сценариями.

### Firewall

Management LuCI разрешается на LAN-интерфейсе Коробки, который смотрит в WAN домашнего роутера:

```text
TCP 80
TCP 443
```

Это **не WAN провайдера** и не публикация LuCI в Интернет.

На provider-facing WAN LuCI по умолчанию закрыт.

Обычный SSH/22 в локальный management block не входит; SSH остаётся отдельной политикой. Временная техподдержка использует случайный WAN support-порт и собственный lifecycle.

### UI

В `Коробка -> Обзор` или отдельном `Управление` показывать:

```text
Локальное управление
Основной адрес: https://korobka.home.arpa/
Fallback IP:    https://192.168.77.1/
Домашний роутер: подключён к LAN Коробки
```

## 3. Этапы реализации

### Milestone A — Local Management & DNS

- выбрать/настроить transit subnet Коробка -> WAN домашнего роутера;
- стабильный LAN management IP;
- DHCP для WAN домашнего роутера;
- DNS Коробки как WAN DNS downstream-роутера;
- `korobka.home.arpa` в dnsmasq;
- LuCI HTTP/HTTPS на LAN Коробки;
- fallback по management IP;
- conflict detection для transit subnet;
- browser test из LAN/Wi-Fi за домашним роутером.

### Milestone B — Support Access Direct

- `korobka-support` manager;
- second key-only Dropbear listener;
- random WAN port;
- ephemeral key bundle;
- 24h expiry/watchdog;
- firewall lifecycle;
- LuCI toggle/countdown/QR;
- disable/expiry/reboot tests;
- direct-public WAN test.

### Milestone C — Support Relay

Для провайдерского CGNAT / отсутствия входящего public IPv4:

- outbound reverse tunnel from Korobka;
- our relay/VPS;
- random external relay port;
- 24h session TTL;
- one-time support bundle;
- no manual port-forward required.

## 4. Неприкосновенные правила

- не выполнять `apk upgrade`;
- новые packages сначала `apk add --simulate` и abort на любой kernel/kmod dependency;
- не хранить support private keys в GitHub;
- не коммитить live IP/session secrets;
- provider-facing WAN LuCI не открывать по умолчанию;
- downstream/home management открывать только на LAN Коробки;
- любой support access должен иметь автоматический expiry.
