#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
LOGROTATE="$ROOT_DIR/logrotate-hardening.sh"
CORE="$ROOT_DIR/linux-hardening.sh"
fail(){ echo "[FAIL] $*" >&2; exit 1; }
pass(){ echo "[PASS] $*"; }
grep -Fq 'LOGROTATE_CONF="/etc/logrotate.conf"' "$LOGROTATE" || fail "falta el logrotate.conf principal"
grep -Fq 'LOGROTATE_DIR="/etc/logrotate.d"' "$LOGROTATE" || fail "falta logrotate.d"
grep -Fq 'print "compress"' "$LOGROTATE" || fail "falta compress"
grep -Fq 'print "rotate 5"' "$LOGROTATE" || fail "falta rotate 5"
grep -Fq 'find "$LOGROTATE_DIR" -type f -print0' "$LOGROTATE" || fail "debe recorrer archivos regulares de logrotate.d"
grep -Fq 'backup_one' "$LOGROTATE" || fail "debe respaldar antes de editar"
grep -Fq 'logrotate -d' "$LOGROTATE" || fail "debe validar sintaxis"
grep -Fq 'restore_changed_files' "$LOGROTATE" || fail "debe poder revertir"
grep -Fq 'logrotate-full' "$CORE" || fail "el baseline debe invocar logrotate"
! grep -Fq '¿Aplicar' "$LOGROTATE" || fail "logrotate no debe pedir confirmación"
pass "logrotate aplica compress + rotate 5 con backup y validación"
