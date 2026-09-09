#!/bin/sh
set -eu

command -v wg >/dev/null 2>&1 || {
    echo "wireguard-tools is required" >&2
    exit 1
}

BASE="/etc/korobka/wireguard"
SERVER_DIR="$BASE/server"
PEER_DIR="$BASE/peers/phone1"

mkdir -p "$SERVER_DIR" "$PEER_DIR"
chmod 700 "$BASE" "$SERVER_DIR" "$BASE/peers" "$PEER_DIR"
umask 077

if [ ! -s "$SERVER_DIR/private.key" ]; then
    wg genkey > "$SERVER_DIR/private.key"
    wg pubkey < "$SERVER_DIR/private.key" > "$SERVER_DIR/public.key"
fi

if [ ! -s "$PEER_DIR/private.key" ]; then
    wg genkey > "$PEER_DIR/private.key"
    wg pubkey < "$PEER_DIR/private.key" > "$PEER_DIR/public.key"
fi

SERVER_PRIV="$(cat "$SERVER_DIR/private.key")"
PHONE_PUB="$(cat "$PEER_DIR/public.key")"

uci -q delete network.wg_clients
uci set network.wg_clients='interface'
uci set network.wg_clients.proto='wireguard'
uci set network.wg_clients.private_key="$SERVER_PRIV"
uci set network.wg_clients.listen_port='51821'
uci set network.wg_clients.mtu='1280'
uci add_list network.wg_clients.addresses='10.77.0.1/24'
uci set network.wg_clients.auto='1'

uci -q delete network.phone1
uci set network.phone1='wireguard_wg_clients'
uci set network.phone1.description='phone1'
uci set network.phone1.public_key="$PHONE_PUB"
uci add_list network.phone1.allowed_ips='10.77.0.2/32'
uci set network.phone1.route_allowed_ips='1'
uci set network.phone1.persistent_keepalive='25'
uci commit network
unset SERVER_PRIV PHONE_PUB

uci -q delete firewall.wgclients
uci set firewall.wgclients='zone'
uci set firewall.wgclients.name='wgclients'
uci add_list firewall.wgclients.network='wg_clients'
# Deliberate product decision: trusted phone WG peers may manage LuCI/SSH on the router.
uci set firewall.wgclients.input='ACCEPT'
uci set firewall.wgclients.output='ACCEPT'
uci set firewall.wgclients.forward='ACCEPT'
uci set firewall.wgclients.mtu_fix='1'

uci -q delete firewall.wgclients_to_lan
uci set firewall.wgclients_to_lan='forwarding'
uci set firewall.wgclients_to_lan.src='wgclients'
uci set firewall.wgclients_to_lan.dest='lan'

uci -q delete firewall.wgclients_to_wan
uci set firewall.wgclients_to_wan='forwarding'
uci set firewall.wgclients_to_wan.src='wgclients'
uci set firewall.wgclients_to_wan.dest='wan'

uci -q delete firewall.allow_wg_clients
uci set firewall.allow_wg_clients='rule'
uci set firewall.allow_wg_clients.name='Allow-WireGuard-Clients'
uci set firewall.allow_wg_clients.src='wan'
uci set firewall.allow_wg_clients.proto='udp'
uci set firewall.allow_wg_clients.dest_port='51821'
uci set firewall.allow_wg_clients.target='ACCEPT'

uci -q delete firewall.wgclients_dns
uci set firewall.wgclients_dns='redirect'
uci set firewall.wgclients_dns.name='Redirect-WG-Clients-DNS-to-Router'
uci set firewall.wgclients_dns.src='wgclients'
uci set firewall.wgclients_dns.src_dport='53'
uci set firewall.wgclients_dns.proto='tcp udp'
uci set firewall.wgclients_dns.dest='wgclients'
uci set firewall.wgclients_dns.dest_ip='10.77.0.1'
uci set firewall.wgclients_dns.dest_port='53'
uci set firewall.wgclients_dns.target='DNAT'
uci commit firewall

if uci -q get podkop.settings >/dev/null 2>&1; then
    uci -q del_list podkop.settings.source_network_interfaces='wg_clients' || true
    uci add_list podkop.settings.source_network_interfaces='wg_clients'
    uci commit podkop
fi

chmod 600 "$SERVER_DIR/private.key" "$PEER_DIR/private.key"
chmod 644 "$SERVER_DIR/public.key" "$PEER_DIR/public.key"

echo "incoming WireGuard configured; private keys were not printed"
echo "server public key: $(cat "$SERVER_DIR/public.key")"
echo "restart/reload netifd only after confirming the wireguard protocol handler is registered"
