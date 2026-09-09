# Коробка — сервисный доступ и локальное обнаружение

Дата: 9 сентября 2026 года.

Документ фиксирует следующий крупный продуктовый блок после базового `luci-app-korobka`: временный доступ техподдержки и локальный адрес Коробки в домашней сети.

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
7. firewall открывает только случайный support-порт;
8. создаётся TTL 24 часа;
9. запускается watchdog, который автоматически отключит доступ после expiry;
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

Support manager должен учитывать существующую диагностику `korobka-public-access`.

#### Direct public WAN

Можно открыть случайный TCP-порт непосредственно на Коробке.

#### Upstream NAT + безопасный automap

После реализации ownership/lease renewal support manager сможет временно создать UPnP/NAT-PMP mapping на срок support-сессии.

#### Upstream NAT без automap

Прямой входящий support SSH сам по себе не заработает без port-forward на домашнем маршрутизаторе. В этом режиме UI не должен создавать ложное ощущение доступности.

Для универсальной поддержки за NAT отдельным следующим этапом нужен reverse-support relay: Коробка инициирует исходящее соединение на наш relay/VPS, а техподдержка подключается к случайному relay-порту. Это предпочтительная production-архитектура для коробок за домашним NAT.

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

### Решение

Основное zero-config имя продукта:

```text
korobka.local
```

Не использовать `.zbs` как product default. `.local` имеет стандартную mDNS-семантику и поддерживается OpenWrt `umdns`.

### Что делаем

1. product hostname Коробки — `korobka`;
2. WAN DHCP client сообщает hostname `korobka` upstream-маршрутизатору как дополнительный best-effort механизм;
3. `umdns` объявляет `korobka.local`;
4. объявляются HTTP/HTTPS management services;
5. LuCI открывается по `http://korobka.local/` / `https://korobka.local/`;
6. локальный management firewall разрешается на WAN только когда WAN является private/shared local network, а не прямым public WAN;
7. при переходе WAN в public mode local-WAN management и mDNS advertisement на WAN автоматически отключаются.

### Почему не `korobka.home.arpa`

`home.arpa` подходит для локального unicast DNS, но требует участия DNS-сервера домашней сети. Коробка не управляет произвольным домашним маршрутизатором, поэтому zero-config доступ без настройки upstream DNS лучше реализовать через mDNS `korobka.local`.

В будущем `korobka.home.arpa` можно поддержать как дополнительный alias при наличии интеграции с локальным DNS.

### Firewall

На private WAN разрешать только необходимые management-порты из фактической on-link WAN подсети:

```text
TCP 80
TCP 443
UDP 5353 (mDNS)
```

Не разрешать их автоматически на public WAN.

Обычный SSH/22 в локальный management block не входит; SSH остаётся отдельной политикой. Временная техподдержка использует свой случайный порт и собственный lifecycle.

### UI

В `Коробка -> Обзор` или отдельном `Управление` показывать:

```text
Локальный адрес: https://korobka.local/
Локальное управление: доступно
Сеть: private WAN
```

Если mDNS недоступен на клиенте, показывать fallback WAN IPv4.

## 3. Этапы реализации

### Milestone A — Local Discovery

- safe package preflight для `umdns`;
- hostname `korobka`;
- advertise на private WAN;
- conditional management firewall;
- service discovery HTTP/HTTPS;
- LuCI status card;
- desktop/mobile browser test;
- test WAN private -> public transition.

### Milestone B — Support Access Direct

- `korobka-support` manager;
- second key-only Dropbear listener;
- random port;
- ephemeral key bundle;
- 24h expiry/watchdog;
- firewall lifecycle;
- LuCI toggle/countdown/QR;
- disable/expiry/reboot tests;
- direct-public network test.

### Milestone C — Support Relay

Для production support за обычным домашним NAT:

- outbound reverse tunnel from Korobka;
- our relay/VPS;
- random external relay port;
- 24h session TTL;
- one-time support bundle;
- no manual router port-forward required.

## 4. Неприкосновенные правила

- не выполнять `apk upgrade`;
- новые packages сначала `apk add --simulate` и abort на любой kernel/kmod dependency;
- не хранить support private keys в GitHub;
- не коммитить live IP/session secrets;
- не превращать временный WAN LuCI rule текущего стенда в production default без private-WAN guard;
- любой support access должен иметь автоматический expiry.
