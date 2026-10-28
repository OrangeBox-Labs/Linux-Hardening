#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# A failed top-level backup preflight must abort before any module can run.
preflight_output=""
if preflight_output="$(bash -c '
  set -euo pipefail
  source "$1"
  require_root() { :; }
  detect_os() { OS_ID=centos; OS_VERSION=8; ID_LIKE=""; }
  : > "$2/blocker"
  BACKUP_DIR="$2/blocker/child"
  run_module() { printf "%s\n" "UNEXPECTED_MODULE_RUN"; }
  main --fix
' _ "$CORE" "$TMP_ROOT" 2>&1)"; then
  fail "main --fix continuó aunque el directorio de backup no se podía crear"
fi
printf '%s\n' "$preflight_output" | grep -Fq 'Preflight de backup falló' ||
  fail "el fallo de preflight no se reportó explícitamente"
if printf '%s\n' "$preflight_output" | grep -Fq 'UNEXPECTED_MODULE_RUN'; then
  fail "un módulo corrió pese al fallo del preflight de backup"
fi
pass "el baseline aborta antes de ejecutar módulos cuando falla el directorio de backup"

# A valid backup gets mode 0700, stores the original bytes, and is idempotent.
bash -c '
  set -euo pipefail
  source "$1"
  AUTO_FIX=true
  BACKUP_DIR="$2/backup"
  prepare_backup
  [ "$(stat -c "%a" "$BACKUP_DIR")" = 700 ]
  printf "%s\n" "original-content" > "$2/source.conf"
  backup_once "$2/source.conf"
  backup="$BACKUP_DIR$2/source.conf"
  [ -f "$backup" ]
  source_hash="$(sha256sum "$2/source.conf")"
  source_hash="${source_hash%% *}"
  backup_hash="$(sha256sum "$backup")"
  backup_hash="${backup_hash%% *}"
  [ "$source_hash" = "$backup_hash" ]
  printf "%s\n" "modified-content" > "$2/source.conf"
  backup_once "$2/source.conf"
  grep -Fq "original-content" "$backup"
  ! grep -Fq "modified-content" "$backup"
' _ "$CORE" "$TMP_ROOT" || fail "el helper no creó/verificó un backup idempotente"
pass "el backup se crea con modo 0700 y conserva la primera copia original"

# Simulate cp failing after the backup directories exist. The fatal helper must
# stop execution instead of returning to the caller that could modify the file.
cp_failure_output=""
if cp_failure_output="$(bash -c '
  set -euo pipefail
  source "$1"
  AUTO_FIX=true
  BACKUP_DIR="$2/backup-failure"
  prepare_backup
  printf "%s\n" "original-content" > "$2/failure.conf"
  cp() { return 1; }
  backup_once "$2/failure.conf"
  printf "%s\n" "UNEXPECTED_AFTER_BACKUP"
' _ "$CORE" "$TMP_ROOT" 2>&1)"; then
  fail "backup_once no abortó cuando cp falló"
fi
printf '%s\n' "$cp_failure_output" | grep -Fq 'se aborta --fix antes de modificarlo' ||
  fail "el fallo de copia no produjo un error fatal explícito"
if printf '%s\n' "$cp_failure_output" | grep -Fq 'UNEXPECTED_AFTER_BACKUP'; then
  fail "el flujo continuó después de que falló la copia de seguridad"
fi
pass "el fallo al copiar un archivo hace fallar --fix antes de la modificación"

printf '[PASS] todas las pruebas de backup del baseline terminaron correctamente\n'
