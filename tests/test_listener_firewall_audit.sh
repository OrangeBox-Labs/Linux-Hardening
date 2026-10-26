#!/usr/bin/env bash
# Pruebas unitarias del auditor de cobertura INPUT: solo fixtures, sin tocar el host.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/listener-firewall-audit.sh
source "$ROOT_DIR/lib/listener-firewall-audit.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
assert_state() {
  local expected="$1" actual="$2" label="$3"
  [ "$actual" = "$expected" ] || fail "$label: esperado=$expected actual=$actual"
}

rules_drop=$(cat <<'RULES'
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
COMMIT
RULES
)
assert_state BLOCKED "$(lfa_iptables_text_state "$rules_drop" tcp 20201)" "política INPUT DROP bloquea si no hay permiso específico"

rules_accept=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p tcp -m tcp --dport 2222 -j ACCEPT
COMMIT
RULES
)
assert_state ALLOWED "$(lfa_iptables_text_state "$rules_accept" tcp 2222)" "regla ACCEPT significa acceso permitido, no protegido"
assert_state ALLOWED "$(lfa_iptables_text_state "$rules_accept" tcp 20201)" "política INPUT ACCEPT deja pasar un puerto sin bloqueo"
assert_state ALLOWED "$(lfa_iptables_text_state "$rules_accept" udp 2222)" "la política ACCEPT también permite UDP aunque no haya regla TCP"

# Rule order is significant: an earlier unconditional terminal rule wins.
rules_accept_first=$(cat <<'RULES'
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -j ACCEPT
-A INPUT -p tcp --dport 20201 -j DROP
COMMIT
RULES
)
assert_state ALLOWED "$(lfa_iptables_text_state "$rules_accept_first" tcp 20201)" "ACCEPT incondicional anterior prevalece sobre DROP posterior para el mismo puerto"

rules_drop_first=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -j DROP
-A INPUT -p tcp --dport 20202 -j ACCEPT
COMMIT
RULES
)
assert_state BLOCKED "$(lfa_iptables_text_state "$rules_drop_first" tcp 20202)" "DROP incondicional anterior prevalece sobre ACCEPT posterior para el mismo puerto"

rules_child=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:OB_FILTER - [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -j OB_FILTER
-A OB_FILTER -p tcp -m tcp --dport 11339 -j DROP
COMMIT
RULES
)
assert_state BLOCKED "$(lfa_iptables_text_state "$rules_child" tcp 11339)" "regla DROP en cadena alcanzable bloquea el puerto"
assert_state ALLOWED "$(lfa_iptables_text_state "$rules_child" tcp 9995)" "otro puerto conserva la política ACCEPT"

rules_restrictive_source=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -s 192.0.2.0/24 -p tcp --dport 3000 -j ACCEPT
COMMIT
RULES
)
assert_state ALLOWED "$(lfa_iptables_text_state "$rules_restrictive_source" tcp 3000)" "allowlist no equivale a bloqueo cuando la política general es ACCEPT"


rules_restricted=$(cat <<'RULES'
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -s 192.0.2.0/24 -p tcp --dport 3001 -j ACCEPT
COMMIT
RULES
)
assert_state RESTRICTED "$(lfa_iptables_text_state "$rules_restricted" tcp 3001)" "la regla ACCEPT con origen restringido se identifica como restringida"

rules_fallback=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -j REJECT --reject-with icmp-port-unreachable
COMMIT
RULES
)
assert_state BLOCKED "$(lfa_iptables_text_state "$rules_fallback" udp 53)" "rechazo general desde INPUT bloquea el servicio"

nft_drop=$(cat <<'RULES'
table inet filter {
 chain input {
  type filter hook input priority filter; policy drop;
 }
}
RULES
)
assert_state BLOCKED "$(lfa_nft_text_state "$nft_drop" ipv4 tcp 20201)" "política DROP en nft inet bloquea IPv4"
assert_state BLOCKED "$(lfa_nft_text_state "$nft_drop" ipv6 udp 1514)" "política DROP en nft inet bloquea IPv6"

nft_ipv4_drop=$(cat <<'RULES'
table ip filter {
 chain INPUT {
  type filter hook input priority filter; policy drop;
 }
}
RULES
)
assert_state BLOCKED "$(lfa_nft_text_state "$nft_ipv4_drop" ipv4 tcp 20201)" "política DROP en tabla nft ip bloquea IPv4"
assert_state UNKNOWN "$(lfa_nft_text_state "$nft_ipv4_drop" ipv6 tcp 20201)" "no confundir tabla ip con IPv6"

nft_ipv6_drop=$(cat <<'RULES'
table ip6 filter {
 chain INPUT {
  type filter hook input priority filter; policy drop;
 }
}
RULES
)
assert_state BLOCKED "$(lfa_nft_text_state "$nft_ipv6_drop" ipv6 tcp 20201)" "política DROP en tabla nft ip6 bloquea IPv6"

nft_port=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy accept;
  tcp dport { 2222, 20201 } accept
 }
}
RULES
)
assert_state ALLOWED "$(lfa_nft_text_state "$nft_port" ipv4 tcp 20201)" "regla accept nft para puerto en conjunto permite acceso"
assert_state ALLOWED "$(lfa_nft_text_state "$nft_port" ipv4 tcp 11339)" "política nft accept permite puerto sin regla de bloqueo"

nft_accept_first=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy drop;
  accept
  tcp dport 20201 drop
 }
}
RULES
)
assert_state ALLOWED "$(lfa_nft_text_state "$nft_accept_first" ipv4 tcp 20201)" "accept nft incondicional anterior prevalece sobre drop posterior"

nft_drop_first=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy accept;
  drop
  tcp dport 20202 accept
 }
}
RULES
)
assert_state BLOCKED "$(lfa_nft_text_state "$nft_drop_first" ipv4 tcp 20202)" "drop nft incondicional anterior prevalece sobre accept posterior"

nft_child=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy accept;
  jump services
 }
 chain services {
  tcp dport 11339 drop
 }
}
RULES
)
assert_state BLOCKED "$(lfa_nft_text_state "$nft_child" ipv4 tcp 11339)" "regla nft drop en cadena alcanzable bloquea"

nft_source_filter=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy accept;
  ip saddr 192.0.2.0/24 tcp dport 3000 accept
 }
}
RULES
)
assert_state ALLOWED "$(lfa_nft_text_state "$nft_source_filter" ipv4 tcp 3000)" "una allowlist parcial con policy accept no bloquea al resto"


nft_restricted=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy drop;
  ip saddr 192.0.2.0/24 tcp dport 3001 accept
 }
}
RULES
)
assert_state RESTRICTED "$(lfa_nft_text_state "$nft_restricted" ipv4 tcp 3001)" "el permiso nft con origen restringido queda identificado como restringido"

# Live command parser compatibility tests: synthetic fixtures only, no host firewall changes.
lfa_load_firewall_snapshots() {
  LFA_FIREWALL_SNAPSHOT_LOADED=true
  LFA_IPV4_RULES_AVAILABLE=false
  LFA_IPV6_RULES_AVAILABLE=false
  LFA_NFT_RULES_AVAILABLE=false
  LFA_IPV4_RULES=""
  LFA_IPV6_RULES=""
  LFA_NFT_RULES=""
}

ss() {
  [ "$1" = "-lntup" ] || return 2
  cat <<'SSFIXTURE'
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
tcp   LISTEN 0      128    192.0.2.10:22       0.0.0.0:*       users:(("sshd",123,3))
udp   UNCONN 0      0      192.0.2.10:53       0.0.0.0:*       users:(("named",456,7))
tcp   LISTEN 0      128    127.0.0.1:9100      0.0.0.0:*       users:(("node_exporter",789,3))
SSFIXTURE
}
audit_ss="$(lfa_audit_listener_firewall)"
case "$audit_ss" in *"sockets=3;"*) ;; *) fail "el parser ss con cabecera no contabilizó 3 sockets: $audit_ss" ;; esac
case "$audit_ss" in *"Sockets omitidos por formato no reconocido"*) fail "la cabecera ss no debe contar como socket omitido" ;; esac
case "$audit_ss" in *"familia ipv6"*) fail "las direcciones IPv4 se clasificaron incorrectamente como IPv6" ;; esac
case "$audit_ss" in *"LISTENERS TCP/UDP"*) ;; *) fail "falta cabecera de listeners: $audit_ss" ;; esac
case "$audit_ss" in *"service=sshd"*) ;; *) fail "no se identificó sshd: $audit_ss" ;; esac
case "$audit_ss" in *"service=named"*) ;; *) fail "no se identificó named: $audit_ss" ;; esac
case "$audit_ss" in *"service=node_exporter"*) ;; *) fail "no se identificó node_exporter: $audit_ss" ;; esac
case "$audit_ss" in *"listener limitado a loopback"*) ;; *) fail "no se identificó el listener local-only: $audit_ss" ;; esac

ss() { return 1; }
netstat() {
  [ "$1" = "-lntup" ] || return 2
  cat <<'NETSTATFIXTURE'
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address       Foreign Address     State       PID/Program name
tcp        0      128 192.0.2.11:22      0.0.0.0:*           LISTEN      111/sshd
udp        0      0   192.0.2.11:53      0.0.0.0:*                       222/named
NETSTATFIXTURE
}
audit_netstat="$(lfa_audit_listener_firewall)"
case "$audit_netstat" in *"sockets=2;"*) ;; *) fail "el fallback netstat no contabilizó sockets TCP/UDP: $audit_netstat" ;; esac
case "$audit_netstat" in *"Sockets omitidos por formato no reconocido"*) fail "las cabeceras de netstat no deben contar como sockets omitidos" ;; esac

pass "permiso frente a bloqueo, política INPUT, allowlists parciales, cadenas alcanzables y nftables"
