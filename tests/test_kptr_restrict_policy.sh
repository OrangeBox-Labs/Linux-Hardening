#!/usr/bin/env bash
# Tests the OrangeBox policy for kernel.kptr_restrict without changing host sysctls.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/sysctl-safe.sh
source "$ROOT_DIR/lib/sysctl-safe.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SYSCTL_WRITES="$TMP_DIR/sysctl-writes"
: > "$SYSCTL_WRITES"
MOCK_KPTR=""

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# The shared sysctl status tags must use the same color palette as other modules.
unset GREEN RED BLUE YELLOW NC
ok_message="$(sysctl_safe_log OK "color-test")"
warn_message="$(sysctl_safe_log WARN "color-test")"
case "$ok_message" in *
# The helper must never alter the host while this test is running.
sysctl() {
  if [ "${1:-}" = "-n" ] && [ "${2:-}" = "kernel.kptr_restrict" ]; then
    printf '%s\n' "$MOCK_KPTR"
    return 0
  fi
  if [ "${1:-}" = "-w" ]; then
    printf '%s\n' "$*" >> "$SYSCTL_WRITES"
    return 0
  fi
  command sysctl "$@"
}

for value in 1 2; do
  MOCK_KPTR="$value"
  target="$TMP_DIR/preserve-$value.conf"
  output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" true 2>&1)" || fail "valor $value debería conservarse sin error"
  printf '%s\n' "$output" | grep -Fq "kernel.kptr_restrict=$value" || fail "no se informó que el valor $value se conserva"
  [ ! -e "$target" ] || fail "se modificó persistencia con kptr_restrict=$value"
  [ ! -s "$SYSCTL_WRITES" ] || fail "se escribió sysctl con kptr_restrict=$value"
done
pass "kernel.kptr_restrict=1 o 2 se conserva sin tocar runtime ni persistencia"

# At 0, audit mode should recommend 1 but must not write either runtime or persistence.
MOCK_KPTR=0
target="$TMP_DIR/audit-zero.conf"
set +e
output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" false 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "valor 0 debería permanecer pendiente en modo auditoría"
printf '%s\n' "$output" | grep -Eq 'recomendado=1|Valor propuesto: 1' || fail "valor 0 no propuso correctamente el objetivo 1"
[ ! -e "$target" ] || fail "modo auditoría escribió persistencia para el valor 0"
[ ! -s "$SYSCTL_WRITES" ] || fail "modo auditoría escribió en runtime para el valor 0"
pass "kernel.kptr_restrict=0 detecta la necesidad de 1 sin modificar en auditoría"

MOCK_KPTR=3
target="$TMP_DIR/unsupported.conf"
set +e
output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" true 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "valor no soportado debería generar advertencia"
printf '%s\n' "$output" | grep -Fq 'no es un valor contemplado por la política' || fail "valor no soportado no se informó"
[ ! -e "$target" ] || fail "valor no soportado modificó persistencia"
[ ! -s "$SYSCTL_WRITES" ] || fail "valor no soportado modificó runtime"
pass "valores no contemplados se advierten y permanecen intactos"
\\033[0;32m[SYSCTL][OK]\\033[0m'*) ;; *) fail "[SYSCTL][OK] no se muestra en verde" ;; esac
case "$warn_message" in *
# The helper must never alter the host while this test is running.
sysctl() {
  if [ "${1:-}" = "-n" ] && [ "${2:-}" = "kernel.kptr_restrict" ]; then
    printf '%s\n' "$MOCK_KPTR"
    return 0
  fi
  if [ "${1:-}" = "-w" ]; then
    printf '%s\n' "$*" >> "$SYSCTL_WRITES"
    return 0
  fi
  command sysctl "$@"
}

for value in 1 2; do
  MOCK_KPTR="$value"
  target="$TMP_DIR/preserve-$value.conf"
  output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" true 2>&1)" || fail "valor $value debería conservarse sin error"
  printf '%s\n' "$output" | grep -Fq "kernel.kptr_restrict=$value" || fail "no se informó que el valor $value se conserva"
  [ ! -e "$target" ] || fail "se modificó persistencia con kptr_restrict=$value"
  [ ! -s "$SYSCTL_WRITES" ] || fail "se escribió sysctl con kptr_restrict=$value"
done
pass "kernel.kptr_restrict=1 o 2 se conserva sin tocar runtime ni persistencia"

# At 0, audit mode should recommend 1 but must not write either runtime or persistence.
MOCK_KPTR=0
target="$TMP_DIR/audit-zero.conf"
set +e
output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" false 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "valor 0 debería permanecer pendiente en modo auditoría"
printf '%s\n' "$output" | grep -Eq 'recomendado=1|Valor propuesto: 1' || fail "valor 0 no propuso correctamente el objetivo 1"
[ ! -e "$target" ] || fail "modo auditoría escribió persistencia para el valor 0"
[ ! -s "$SYSCTL_WRITES" ] || fail "modo auditoría escribió en runtime para el valor 0"
pass "kernel.kptr_restrict=0 detecta la necesidad de 1 sin modificar en auditoría"

MOCK_KPTR=3
target="$TMP_DIR/unsupported.conf"
set +e
output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" true 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "valor no soportado debería generar advertencia"
printf '%s\n' "$output" | grep -Fq 'no es un valor contemplado por la política' || fail "valor no soportado no se informó"
[ ! -e "$target" ] || fail "valor no soportado modificó persistencia"
[ ! -s "$SYSCTL_WRITES" ] || fail "valor no soportado modificó runtime"
pass "valores no contemplados se advierten y permanecen intactos"
\\033[0;33m[SYSCTL][WARN]\\033[0m'*) ;; *) fail "[SYSCTL][WARN] no se muestra en amarillo" ;; esac
pass "etiquetas SYSCTL OK/WARN usan colores coherentes"


# The helper must never alter the host while this test is running.
sysctl() {
  if [ "${1:-}" = "-n" ] && [ "${2:-}" = "kernel.kptr_restrict" ]; then
    printf '%s\n' "$MOCK_KPTR"
    return 0
  fi
  if [ "${1:-}" = "-w" ]; then
    printf '%s\n' "$*" >> "$SYSCTL_WRITES"
    return 0
  fi
  command sysctl "$@"
}

for value in 1 2; do
  MOCK_KPTR="$value"
  target="$TMP_DIR/preserve-$value.conf"
  output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" true 2>&1)" || fail "valor $value debería conservarse sin error"
  printf '%s\n' "$output" | grep -Fq "kernel.kptr_restrict=$value" || fail "no se informó que el valor $value se conserva"
  [ ! -e "$target" ] || fail "se modificó persistencia con kptr_restrict=$value"
  [ ! -s "$SYSCTL_WRITES" ] || fail "se escribió sysctl con kptr_restrict=$value"
done
pass "kernel.kptr_restrict=1 o 2 se conserva sin tocar runtime ni persistencia"

# At 0, audit mode should recommend 1 but must not write either runtime or persistence.
MOCK_KPTR=0
target="$TMP_DIR/audit-zero.conf"
set +e
output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" false 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "valor 0 debería permanecer pendiente en modo auditoría"
printf '%s\n' "$output" | grep -Eq 'recomendado=1|Valor propuesto: 1' || fail "valor 0 no propuso correctamente el objetivo 1"
[ ! -e "$target" ] || fail "modo auditoría escribió persistencia para el valor 0"
[ ! -s "$SYSCTL_WRITES" ] || fail "modo auditoría escribió en runtime para el valor 0"
pass "kernel.kptr_restrict=0 detecta la necesidad de 1 sin modificar en auditoría"

MOCK_KPTR=3
target="$TMP_DIR/unsupported.conf"
set +e
output="$(sysctl_safe_apply_kptr_restrict_policy "$target" "$TMP_DIR/backup" true 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "valor no soportado debería generar advertencia"
printf '%s\n' "$output" | grep -Fq 'no es un valor contemplado por la política' || fail "valor no soportado no se informó"
[ ! -e "$target" ] || fail "valor no soportado modificó persistencia"
[ ! -s "$SYSCTL_WRITES" ] || fail "valor no soportado modificó runtime"
pass "valores no contemplados se advierten y permanecen intactos"
