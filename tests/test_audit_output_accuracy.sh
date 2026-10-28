#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
NETWORK="$ROOT_DIR/network-hardening.sh"
RSYSLOG="$ROOT_DIR/rsyslog-hardening.sh"
SSH="$ROOT_DIR/ssh-hardening.sh"
SSH_COMPLETE="$ROOT_DIR/ssh-hardening-complete.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

modules="$(awk '/^MODULES_TO_DISABLE=\(/,/^\)/' "$NETWORK")"
for m in 'tipc:' 'dccp:' 'sctp:' 'rds:'; do
  if printf '%s\n' "$modules" | grep -Fq "$m"; then
    fail "MODULES_TO_DISABLE repite $m, ya cubierto por un control CIS específico"
  fi
done
grep -Fq 'Compress=yes (valor predeterminado; no requiere descomentar)' "$RSYSLOG" || fail "journald Compress=yes default todavía genera falso positivo"
grep -Fq 'Auditoría SSH: no se reiniciará ni modificará el servicio' "$SSH" || fail "el mensaje de auditoría SSH implica reinicio en modo read-only"
grep -Fq 'show_effective_sshd_value kexalgorithms' "$SSH_COMPLETE" || fail "ssh-hardening-complete no muestra el KEX efectivo"
grep -Fq 'show_effective_sshd_value hostkeyalgorithms' "$SSH_COMPLETE" || fail "ssh-hardening-complete no muestra HostKeyAlgorithms efectivos"
pass "se reducen verificaciones duplicadas y falsos positivos de journald; SSH reporta valores efectivos"
