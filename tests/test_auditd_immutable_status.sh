#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
AUDITD="$ROOT_DIR/auditd-hardening.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/auditctl" <<'FAKE_AUDITCTL'
#!/usr/bin/env bash
set -eu
case "${1:-}" in
  -l)
    if [ "${AUDITCTL_TEST_NO_RULES:-0}" = "1" ]; then
      printf '%s\\n' 'No rules'
      exit 0
    fi
    printf '%s\n' \
      '-a always,exit -S adjtimex -k time-change' \
      '-w /etc/group -p wa -k identity' \
      '-w /etc/hosts -p wa -k system-locale' \
      '-w /etc/selinux -p wa -k MAC-policy' \
      '-w /var/log/faillog -p wa -k logins' \
      '-w /var/run/utmp -p wa -k session' \
      '-a always,exit -S chmod -k perm_mod' \
      '-a always,exit -S open -k access' \
      '-a always,exit -S mount -k mounts' \
      '-a always,exit -S unlink -k delete' \
      '-w /etc/sudoers -p wa -k scope' \
      '-w /sbin/insmod -p x -k modules'
    ;;
  -s)
    if [ "${AUDITCTL_TEST_ENABLED:-}" = "missing" ]; then
      printf '%s\n' 'failure 1' 'lost 0' 'backlog 0'
    else
      printf 'enabled %s\n' "${AUDITCTL_TEST_ENABLED:-1}"
      printf '%s\n' 'failure 1' 'lost 0' 'backlog 0'
    fi
    ;;
  *)
    printf 'Unexpected fake auditctl arguments: %s\n' "$*" >&2
    exit 2
    ;;
esac
FAKE_AUDITCTL
chmod +x "$TMP_DIR/bin/auditctl"
PATH="$TMP_DIR/bin:$PATH"
export PATH

# Sourcing defines the functions but must not run main() or modify auditd.
# shellcheck source=../auditd-hardening.sh
source "$AUDITD"

assert_state() {
  local state="$1" expected="$2" forbidden="$3" output=""
  export AUDITCTL_TEST_ENABLED="$state"
  WARNINGS=0
  output="$(legacy_audit_rules_check 2>&1)" || fail "la comprobación falló con enabled=$state"
  printf '%s\n' "$output" | grep -Fq -- "$expected" ||
    fail "enabled=$state no mostró el mensaje esperado: $expected"
  if [ -n "$forbidden" ] && printf '%s\n' "$output" | grep -Fq -- "$forbidden"; then
    fail "enabled=$state mostró un estado incompatible: $forbidden"
  fi
  pass "ruta legacy: enabled=$state se interpreta correctamente"

  # Reproduce el orden moderno: add_audit_rules informa el estado y luego
  # configure_audit_immutable ejecuta su preflight. La segunda función debe
  # estar silenciosa en modo auditoría para no duplicar ni sumar la advertencia.
  AUTO_FIX=false
  WARNINGS=0
  : > "$TMP_DIR/modern-output"
  add_audit_rules > "$TMP_DIR/modern-output" 2>&1 ||
    fail "add_audit_rules falló con enabled=$state"
  warnings_after_report="$WARNINGS"
  configure_audit_immutable >> "$TMP_DIR/modern-output" 2>&1 ||
    fail "configure_audit_immutable falló con enabled=$state"
  [ "$WARNINGS" -eq "$warnings_after_report" ] ||
    fail "configure_audit_immutable sumó una advertencia duplicada con enabled=$state"
  modern_output="$(cat "$TMP_DIR/modern-output")"
  printf '%s\n' "$modern_output" | grep -Fq -- "$expected" ||
    fail "la ruta moderna no mostró el estado esperado para enabled=$state: $expected"
  if printf '%s\n' "$modern_output" | grep -Eq 'auditd no está en modo inmutable|auditd ya está en modo inmutable'; then
    fail "la ruta moderna duplicó el estado auditd para enabled=$state"
  fi
  pass "ruta moderna: enabled=$state se reporta una vez y no duplica advertencias"
}

assert_state "1"   "auditd está habilitado (enabled 1), pero las reglas siguen siendo modificables"   "Configuración de auditd inmutable - OK"
assert_state "2"   "auditd inmutable (enabled 2) y reglas requeridas cargadas en memoria"   "no está en modo inmutable"
assert_state "0"   "auditd está deshabilitado (enabled 0)"   "Configuración de auditd inmutable - OK"
assert_state "10"   "auditd reporta enabled 10; no se confirma modo inmutable"   "Configuración de auditd inmutable - OK"
assert_state "missing"   "No se pudo determinar el estado de auditd mediante auditctl -s"   "Configuración de auditd inmutable - OK"

# enabled=2 is not a healthy result when no required rules are loaded.
export AUDITCTL_TEST_ENABLED=2
export AUDITCTL_TEST_NO_RULES=1
WARNINGS=0
output="$(report_auditd_immutable_status auditctl 2>&1)" || fail "el reporte immutable sin reglas falló"
printf '%s\\n' "$output" | grep -Fq "auditd está inmutable (enabled 2), pero faltan reglas requeridas en memoria" ||
  fail "enabled=2 con No rules debe generar una advertencia explícita"
[ "$WARNINGS" -gt 0 ] || fail "enabled=2 con No rules debe incrementar advertencias"
pass "enabled=2 con No rules no se reporta como configuración correcta"

# --fix must stop before creating backups or editing persistent files in this state.
backup_called="$TMP_DIR/backup-called"
get_os_version() { printf '10\\n'; }
get_auditctl_path() { printf 'auditctl\\n'; }
get_auditd_enabled_state() { printf '2\\n'; }
audit_rules_ready() { return 1; }
make_backup() { : > "$backup_called"; return 0; }
show_summary() { :; }
set +e
main --fix >"$TMP_DIR/fix-output" 2>&1
fix_rc=$?
set -e
[ "$fix_rc" -eq 3 ] || fail "--fix debería abortar con código 3 si enabled=2 y faltan reglas"
[ ! -e "$backup_called" ] || fail "--fix no debió continuar hasta el backup en un estado irreparable en caliente"
grep -Fq "No se modificó la configuración" "$TMP_DIR/fix-output" ||
  fail "--fix debe informar que no modificó la configuración"
pass "--fix se detiene sin modificar archivos si auditd es inmutable y no hay reglas"

pass "la interpretación de enabled se prueba con auditctl simulado y sin cambios en el sistema"
