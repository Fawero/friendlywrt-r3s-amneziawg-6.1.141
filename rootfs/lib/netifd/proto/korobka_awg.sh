#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
    . /lib/functions.sh
    . ../netifd-proto.sh
    init_proto "$@"
}

korobka_awg_fail() {
    local cfg="$1"
    local code="$2"
    proto_notify_error "$cfg" "$code"
    proto_block_restart "$cfg"
}

proto_korobka_awg_init_config() {
    no_device=1
    available=1

    proto_config_add_string "config"
    proto_config_add_string "ifname"
    proto_config_add_string "endpoint_ip"
    proto_config_add_string "tunlink"
    proto_config_add_boolean "advanced_security"
}

proto_korobka_awg_setup() {
    local cfg="$1"
    local config ifname endpoint_ip tunlink advanced_security
    local addrs mtu endpoint port endpoint_route san dir host
    local raw addr src4 src6 oldifs

    json_get_vars config ifname endpoint_ip tunlink advanced_security

    [ -n "$config" ] || {
        korobka_awg_fail "$cfg" "MISSING_CONFIG"
        return 1
    }
    [ -r "$config" ] || {
        korobka_awg_fail "$cfg" "CONFIG_NOT_READABLE"
        return 1
    }
    command -v awg >/dev/null 2>&1 || {
        korobka_awg_fail "$cfg" "AWG_NOT_INSTALLED"
        return 1
    }

    [ -n "$ifname" ] || ifname="$cfg"
    [ -n "$tunlink" ] || tunlink="wan"
    [ -n "$advanced_security" ] || advanced_security=1

    addrs="$(sed -n 's/^[[:space:]]*Address[[:space:]]*=[[:space:]]*//p' "$config" | head -n1)"
    mtu="$(sed -n 's/^[[:space:]]*MTU[[:space:]]*=[[:space:]]*//p' "$config" | head -n1)"
    endpoint="$(sed -n 's/^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*//p' "$config" | head -n1)"

    [ -n "$addrs" ] || {
        korobka_awg_fail "$cfg" "MISSING_ADDRESS"
        return 1
    }
    [ -n "$endpoint" ] || {
        korobka_awg_fail "$cfg" "MISSING_ENDPOINT"
        return 1
    }
    [ -n "$mtu" ] || mtu=1420

    port="${endpoint##*:}"
    endpoint_route="$endpoint_ip"
    if [ -z "$endpoint_route" ]; then
        case "$endpoint" in
            \[*\]:*) endpoint_route="" ;;
            *:*)
                host="${endpoint%:*}"
                case "$host" in
                    *[!0-9.]*|'') endpoint_route="" ;;
                    *) endpoint_route="$host" ;;
                esac
                ;;
        esac
    fi

    dir="/var/run/korobka-awg"
    san="$dir/$cfg.conf"
    mkdir -p "$dir"
    chmod 700 "$dir"
    umask 077

    awk -v endpoint_ip="$endpoint_ip" -v endpoint_port="$port" -v adv="$advanced_security" '
    function emit_peer_security() {
        if (in_peer && adv != "0" && !security_emitted)
            print "AdvancedSecurity = on"
        security_emitted = 1
    }
    {
        l = tolower($0)
        if (l ~ /^[ \t]*(address|dns|mtu|table|preup|postup|predown|postdown)[ \t]*=/)
            next
        if (l ~ /^[ \t]*advancedsecurity[ \t]*=/)
            next
        if ($0 ~ /^[[:space:]]*\[Peer\][[:space:]]*$/) {
            emit_peer_security()
            print
            in_peer = 1
            security_emitted = 0
            next
        }
        if ($0 ~ /^[[:space:]]*\[Interface\][[:space:]]*$/) {
            emit_peer_security()
            in_peer = 0
            security_emitted = 0
            print
            next
        }
        if (endpoint_ip != "" && l ~ /^[ \t]*endpoint[ \t]*=/) {
            print "Endpoint = " endpoint_ip ":" endpoint_port
            next
        }
        print
    }
    END {
        emit_peer_security()
    }
    ' "$config" > "$san" || {
        rm -f "$san"
        korobka_awg_fail "$cfg" "CONFIG_SANITIZE_FAILED"
        return 1
    }

    ip link del "$ifname" 2>/dev/null || true
    if ! ip link add "$ifname" type amneziawg; then
        rm -f "$san"
        korobka_awg_fail "$cfg" "LINK_CREATE_FAILED"
        return 1
    fi

    if ! awg setconf "$ifname" "$san"; then
        ip link del "$ifname" 2>/dev/null || true
        rm -f "$san"
        korobka_awg_fail "$cfg" "AWG_SETCONF_FAILED"
        return 1
    fi

    ip link set mtu "$mtu" dev "$ifname"

    [ -n "$endpoint_route" ] && ( proto_add_host_dependency "$cfg" "$endpoint_route" "$tunlink" )

    proto_init_update "$ifname" 1

    src4=""
    src6=""
    oldifs="$IFS"
    IFS=','
    for raw in $addrs; do
        addr="$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -n "$addr" ] || continue
        addr="${addr%%/*}"
        case "$addr" in
            *:*)
                [ -n "$src6" ] || src6="$addr"
                proto_add_ipv6_address "$addr" 128
                ;;
            *)
                [ -n "$src4" ] || src4="$addr"
                proto_add_ipv4_address "$addr" 32
                ;;
        esac
    done
    IFS="$oldifs"

    proto_add_data
    json_add_string "config" "$config"
    json_add_string "tunlink" "$tunlink"
    [ -n "$endpoint_route" ] && json_add_string "endpoint_ip" "$endpoint_route"
    [ -n "$src4" ] && json_add_string "source_ipv4" "$src4"
    [ -n "$src6" ] && json_add_string "source_ipv6" "$src6"
    proto_close_data
    proto_send_update "$cfg"
}

proto_korobka_awg_teardown() {
    local cfg="$1"
    local ifname

    json_get_vars ifname
    [ -n "$ifname" ] || ifname="$cfg"
    ip link del "$ifname" 2>/dev/null || true
    rm -f "/var/run/korobka-awg/$cfg.conf"
}

[ -n "$INCLUDE_ONLY" ] || add_protocol korobka_awg
