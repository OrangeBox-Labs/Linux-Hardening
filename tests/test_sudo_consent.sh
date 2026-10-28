#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
SUDO="$ROOT_DIR/sudo-hardening.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
grep -Fq 'confirm_sudo_change()' "$SUDO" || fail "sudo no tiene confirmación interactiva común"
grep -Fq 'sudoers_config_contains()' "$SUDO" || fail "no comprueba Defaults activos e includes admitidos"
grep -Fq 'append_sudoers_line_safely()' "$SUDO" || fail "no escribe sudoers mediante temporal/validación"
grep -Fq 'visudo -c -f "$tmp"' "$SUDO" || fail "no valida el candidato antes de instalarlo"
grep -Fq 'visudo -c >/dev/null 2>&1' "$SUDO" || fail "no valida configuración global posterior"
grep -Fq 'sudoers_option_value' "$SUDO" || fail "no inspecciona valores de Defaults"
grep -Fq 'timestamp_timeout' "$SUDO" || fail "falta control del tiempo de credenciales"
grep -Fq 'env_reset' "$SUDO" || fail "falta control de env_reset"
grep -Fq 'confirm_sudo_change "crear $LOGFILE"' "$SUDO" || fail "crear el log no pide consentimiento"
grep -Fq 'confirm_sudo_change "proteger permisos/propiedad de $LOGFILE"' "$SUDO" || fail "cambiar permisos del log no pide consentimiento"
grep -Fq '¿Habilitar Defaults use_pty?' "$SUDO" || fail "use_pty perdió confirmación"
grep -Fq 'cPanel detectado: se omite use_pty' "$SUDO" || fail "cPanel no queda protegido frente a use_pty"
if grep -Fq 'echo "$fix_line" >>"$SUDOERS_FILE"' "$SUDO"; then fail "quedan escrituras directas a sudoers sin validar"; fi
if grep -Fq "echo 'Defaults timestamp_timeout=5' >>" "$SUDO"; then fail "timestamp_timeout se escribe sin consentimiento"; fi
pass "sudo exige consentimiento, inspecciona Defaults y valida cambios con visudo antes y después"
