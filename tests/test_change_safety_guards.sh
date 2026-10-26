#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
NETWORK="$ROOT_DIR/network-hardening.sh"
AUDITD="$ROOT_DIR/auditd-hardening.sh"
RSYSLOG="$ROOT_DIR/rsyslog-hardening.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

if grep -Eq '(^|[[:space:]])rmmod[[:space:]]+"?\$module' "$NETWORK"; then
  fail "network-hardening no debe descargar módulos de kernel en caliente"
fi
grep -Fq 'no se descargará en caliente' "$NETWORK" || fail "la confirmación de módulo no explica que no se descarga en caliente"
grep -Fq 'if ! make_backup; then' "$NETWORK" || fail "network-hardening puede aplicar cambios si falla el backup"
grep -Fq 'chmod 700 "$BACKUP_DIR"' "$NETWORK" || fail "backup de red no restringe permisos"
grep -Fq 'if ! make_backup; then' "$AUDITD" || fail "auditd puede aplicar cambios si falla el backup"
grep -Fq 'chmod 700 "$BACKUP_DIR"' "$AUDITD" || fail "backup auditd no restringe permisos"
grep -Fq 'if ! make_backup; then' "$RSYSLOG" || fail "rsyslog puede aplicar cambios si falla el backup"
grep -Fq 'chmod 700 "$BACKUP_DIR"' "$RSYSLOG" || fail "backup logging no restringe permisos"
pass "network: sin hot-unload; auditd/network/rsyslog abortan si no pueden respaldar"
