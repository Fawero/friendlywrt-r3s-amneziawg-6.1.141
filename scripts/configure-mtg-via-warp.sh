#!/bin/sh
set -eu

FRONTING_HOST="${FRONTING_HOST:-storage.googleapis.com}"
MTG_PORT="${MTG_PORT:-8888}"
SOCKS_PORT="${SOCKS_PORT:-4534}"

command -v /usr/local/bin/mtg >/dev/null 2>&1 || {
    echo "install MTG first (scripts/install-mtg-2.2.8.sh)" >&2
    exit 1
}

uci set podkop.settings.service_listen_address='127.0.0.1'
uci -q delete podkop.TelegramProxy
uci set podkop.TelegramProxy='section'
uci set podkop.TelegramProxy.connection_type='vpn'
uci set podkop.TelegramProxy.interface='awg_warp'
uci set podkop.TelegramProxy.user_domain_list_type='disabled'
uci set podkop.TelegramProxy.user_subnet_list_type='disabled'
uci set podkop.TelegramProxy.domain_resolver_enabled='0'
uci set podkop.TelegramProxy.mixed_proxy_enabled='1'
uci set podkop.TelegramProxy.mixed_proxy_port="$SOCKS_PORT"
uci commit podkop

mkdir -p /etc/korobka/mtg
chmod 700 /etc/korobka/mtg
umask 077

if [ ! -s /etc/korobka/mtg/secret ]; then
    /usr/local/bin/mtg generate-secret --hex "$FRONTING_HOST" > /etc/korobka/mtg/secret
fi
chmod 600 /etc/korobka/mtg/secret
SECRET="$(cat /etc/korobka/mtg/secret)"

cat > /etc/mtg.toml <<EOF
secret = "$SECRET"
bind-to = "0.0.0.0:${MTG_PORT}"
prefer-ip = "only-ipv4"
auto-update = false

[network]
dns = "https://1.1.1.1/dns-query"
proxies = ["socks5://127.0.0.1:${SOCKS_PORT}"]

[network.timeout]
tcp = "5s"
http = "10s"
idle = "5m"
handshake = "10s"

[network.keep-alive]
disabled = false
idle = "15s"
interval = "15s"
count = 9

[defense.anti-replay]
enabled = true

[defense.blocklist]
enabled = false
EOF
unset SECRET
chmod 600 /etc/mtg.toml

uci -q delete firewall.allow_mtg
uci set firewall.allow_mtg='rule'
uci set firewall.allow_mtg.name='Allow-Telegram-MTProxy'
uci set firewall.allow_mtg.src='wan'
uci set firewall.allow_mtg.proto='tcp'
uci set firewall.allow_mtg.dest_port="$MTG_PORT"
uci set firewall.allow_mtg.target='ACCEPT'
uci commit firewall

/etc/init.d/sing-box disable 2>/dev/null || true
/etc/init.d/podkop enable
/etc/init.d/mtg enable

echo "MTG configured: TCP/${MTG_PORT} -> SOCKS 127.0.0.1:${SOCKS_PORT} -> awg_warp"
echo "The secret was not printed. Validate FRONTING_HOST/SNI suitability before production deployment."
