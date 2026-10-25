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
assert_state CONTROLLED "$(lfa_iptables_text_state "$rules_drop" tcp 20201)" "política INPUT DROP protege todos los puertos"

rules_accept=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -p tcp -m tcp --dport 2222 -j ACCEPT
COMMIT
RULES
)
assert_state CONTROLLED "$(lfa_iptables_text_state "$rules_accept" tcp 2222)" "regla INPUT explícita TCP"
assert_state UNCONTROLLED "$(lfa_iptables_text_state "$rules_accept" tcp 20201)" "puerto sin regla con INPUT ACCEPT"
assert_state UNCONTROLLED "$(lfa_iptables_text_state "$rules_accept" udp 2222)" "no confundir protocolo TCP con UDP"

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
assert_state CONTROLLED "$(lfa_iptables_text_state "$rules_child" tcp 11339)" "regla en cadena alcanzable desde INPUT"
assert_state UNCONTROLLED "$(lfa_iptables_text_state "$rules_child" tcp 9995)" "no inventar regla para otro puerto"

rules_restrictive_source=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -s 192.0.2.0/24 -p tcp --dport 3000 -j ACCEPT
COMMIT
RULES
)
assert_state UNCONTROLLED "$(lfa_iptables_text_state "$rules_restrictive_source" tcp 3000)" "allowlist parcial no protege a todos los orígenes"

rules_fallback=$(cat <<'RULES'
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -j REJECT --reject-with icmp-port-unreachable
COMMIT
RULES
)
assert_state CONTROLLED "$(lfa_iptables_text_state "$rules_fallback" udp 53)" "rechazo general desde INPUT"

nft_drop=$(cat <<'RULES'
table inet filter {
 chain input {
  type filter hook input priority filter; policy drop;
 }
}
RULES
)
assert_state CONTROLLED "$(lfa_nft_text_state "$nft_drop" ipv4 tcp 20201)" "política DROP en nft inet para IPv4"
assert_state CONTROLLED "$(lfa_nft_text_state "$nft_drop" ipv6 udp 1514)" "política DROP en nft inet para IPv6"

nft_port=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy accept;
  tcp dport { 2222, 20201 } accept
 }
}
RULES
)
assert_state CONTROLLED "$(lfa_nft_text_state "$nft_port" ipv4 tcp 20201)" "regla explícita nft para puerto en conjunto"
assert_state UNCONTROLLED "$(lfa_nft_text_state "$nft_port" ipv4 tcp 11339)" "nft INPUT accept sin regla para puerto"

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
assert_state CONTROLLED "$(lfa_nft_text_state "$nft_child" ipv4 tcp 11339)" "regla nft en cadena alcanzable"

nft_source_filter=$(cat <<'RULES'
table inet orangebox {
 chain input {
  type filter hook input priority filter; policy accept;
  ip saddr 192.0.2.0/24 tcp dport 3000 accept
 }
}
RULES
)
assert_state UNCONTROLLED "$(lfa_nft_text_state "$nft_source_filter" ipv4 tcp 3000)" "regla nft limitada a ciertos orígenes no equivale a control global"

pass "política INPUT, reglas por puerto, cadenas alcanzables, familia/protocolo y nftables"
