#!/usr/bin/env bash
# Regression test: the generic SYN flood baseline must preserve platform TCP retry tuning.
set -eu
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
NETWORK_SCRIPT="$ROOT_DIR/network-hardening.sh"
ORCHESTRATOR="$ROOT_DIR/linux-hardening.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

for setting in \
  'net.ipv4.tcp_syncookies' \
  'net.ipv4.tcp_max_syn_backlog' \
  'net.core.somaxconn'; do
  grep -Fq "$setting" "$NETWORK_SCRIPT" || fail "network-hardening.sh perdió el control $setting"
  grep -Fq "$setting" "$ORCHESTRATOR" || fail "linux-hardening.sh perdió el control $setting"
done

if grep -Eq '^[[:space:]]*set_sysctl[[:space:]]+"net\.ipv4\.tcp_syn(ack)?_retries"' "$NETWORK_SCRIPT"; then
  fail "network-hardening.sh vuelve a forzar los reintentos TCP"
fi
if grep -Eq '^SYNFLOOD_KEYS=.*net\.ipv4\.tcp_syn(ack)?_retries' "$ORCHESTRATOR"; then
  fail "el perfil SYN flood de linux-hardening.sh vuelve a forzar los reintentos TCP"
fi

grep -Fq 'tcp_synack_retries' "$ROOT_DIR/network-hardening-README.md" || fail "falta documentar tcp_synack_retries"
grep -Fq 'tcp_syn_retries' "$ROOT_DIR/network-hardening-README.md" || fail "falta documentar tcp_syn_retries"
pass "el baseline conserva SYN cookies/backlogs y deja los reintentos TCP a la política de cada plataforma"
