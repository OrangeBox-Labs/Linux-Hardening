#!/usr/bin/env bash
# Regression test: the shared SYN/TCP baseline includes all five requested sysctls.
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
NETWORK_SCRIPT="$ROOT_DIR/network-hardening.sh"
ORCHESTRATOR="$ROOT_DIR/linux-hardening.sh"
NETWORK_DOC="$ROOT_DIR/network-hardening-README.md"
MAIN_DOC="$ROOT_DIR/README.md"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

for setting in \
  'net.ipv4.tcp_syncookies' \
  'net.ipv4.tcp_max_syn_backlog' \
  'net.core.somaxconn' \
  'net.ipv4.tcp_synack_retries' \
  'net.ipv4.tcp_syn_retries'; do
  grep -Fq "$setting" "$NETWORK_SCRIPT" || fail "network-hardening.sh perdió el control $setting"
  grep -Fq "$setting" "$ORCHESTRATOR" || fail "linux-hardening.sh perdió el control $setting"
done

grep -Fq 'set_sysctl "net.ipv4.tcp_syncookies" "1"' "$NETWORK_SCRIPT" || fail "tcp_syncookies no tiene valor 1"
grep -Fq 'set_sysctl "net.ipv4.tcp_max_syn_backlog" "4096"' "$NETWORK_SCRIPT" || fail "tcp_max_syn_backlog no tiene valor 4096"
grep -Fq 'set_sysctl "net.core.somaxconn" "4096"' "$NETWORK_SCRIPT" || fail "somaxconn no tiene valor 4096"
grep -Fq 'set_sysctl "net.ipv4.tcp_synack_retries" "2"' "$NETWORK_SCRIPT" || fail "tcp_synack_retries no tiene valor 2"
grep -Fq 'set_sysctl "net.ipv4.tcp_syn_retries" "2"' "$NETWORK_SCRIPT" || fail "tcp_syn_retries no tiene valor 2"

grep -Fq 'SYNFLOOD_VALUES=(1 4096 4096 2 2)' "$ORCHESTRATOR" || fail "el baseline global no tiene los cinco valores esperados"
grep -Fq 'tcp_synack_retries' "$NETWORK_DOC" || fail "falta documentar tcp_synack_retries"
grep -Fq 'tcp_syn_retries' "$NETWORK_DOC" || fail "falta documentar tcp_syn_retries"
grep -Fq 'tcp_synack_retries' "$MAIN_DOC" || fail "falta documentar tcp_synack_retries en README principal"
grep -Fq 'tcp_syn_retries' "$MAIN_DOC" || fail "falta documentar tcp_syn_retries en README principal"

grep -Fq 'synflood_state_compliant()' "$ORCHESTRATOR" || fail "falta preflight de cumplimiento SYN flood"
grep -Fq 'synflood_state_compliant; then' "$ORCHESTRATOR" || fail "el flujo no evita confirmaciones redundantes de SYN flood"
grep -Fq 'orangebox_sysctl_persistence_target()' "$ORCHESTRATOR" || fail "falta selector de persistencia sysctl por generación"
grep -Fq '/etc/sysctl.conf' "$ORCHESTRATOR" || fail "CentOS/RHEL 6 no tiene fallback persistente a /etc/sysctl.conf"
grep -Fq 'synflood_select_persistence_target' "$ORCHESTRATOR" || fail "SYN flood no selecciona persistencia en sistemas legacy"
if grep -Fq '[ -d /etc/sysctl.d ] || { warn "/etc/sysctl.d no existe"; return; }' "$ORCHESTRATOR"; then
  fail "SYN flood abandona la auditoría en CentOS 6 por falta de /etc/sysctl.d"
fi

pass "los cinco parámetros SYN/TCP están en el baseline global y en network-hardening.sh"
