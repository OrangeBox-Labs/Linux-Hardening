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
      printf '%s\n' 'No rules'
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
report_auditd_immutable_status auditctl >"$TMP_DIR/no-rules-output" 2>&1 ||
  fail "el reporte immutable sin reglas falló"
output="$(cat "$TMP_DIR/no-rules-output")"
printf '%s\n' "$output" | grep -Fq "auditd está inmutable (enabled 2), pero faltan reglas requeridas en memoria" ||
  fail "enabled=2 con No rules debe generar una advertencia explícita"
[ "$WARNINGS" -gt 0 ] || fail "enabled=2 con No rules debe incrementar advertencias"
pass "enabled=2 con No rules no se reporta como configuración correcta"

# enabled=2 + reglas ausentes debe activar la ruta de recuperación planificada.
# Se sustituyen las funciones de sistema para que la prueba no toque /etc ni servicios.
backup_called="$TMP_DIR/backup-called"
get_os_version() { printf '10\n'; }
get_auditctl_path() { printf 'auditctl\n'; }
get_auditd_enabled_state() { printf '2\n'; }
audit_rules_ready() { return 1; }
make_backup() { : > "$backup_called"; return 0; }
check_auditd_installed() { :; }
check_auditd_enabled() { :; }
check_log_storage() { :; }
check_log_retention() { :; }
check_full_action() { :; }
add_audit_rules() { :; }
restart_auditd() { :; }
configure_audit_immutable() { :; }
show_summary() { :; }
AUDITD_REBOOT_REQUIRED=false
set +e
main --fix >"$TMP_DIR/fix-output" 2>&1
fix_rc=$?
set -e
[ "$fix_rc" -eq 3 ] || fail "--fix debe devolver código 3 si queda pendiente el reinicio controlado"
[ -e "$backup_called" ] || fail "--fix debe respaldar antes de preparar la recuperación"
grep -Fq "preparará la configuración persistente para el siguiente arranque" "$TMP_DIR/fix-output" ||
  fail "--fix debe explicar que prepara reglas persistentes para el siguiente arranque"
grep -Fq "No se ejecutó reboot automáticamente" "$TMP_DIR/fix-output" ||
  fail "--fix no debe reiniciar el host automáticamente"
pass "--fix respalda y prepara la recuperación cuando enabled=2 y faltan reglas"

# Recuperar las funciones reales después de las sustituciones usadas para probar main().
# El source no ejecuta main(); PATH conserva el auditctl simulado.
source "$AUDITD"

# Prueba real de staging con rutas aisladas: no modifica /etc/audit ni carga reglas al kernel.
AUTO_FIX=true
FIXED=0
WARNINGS=0
AUDIT_RULES_DIR="$TMP_DIR/staged-rules"
AUDIT_RULES="$AUDIT_RULES_DIR/98-orangebox-baseline.rules"
export ORANGEBOX_ASSUME_YES=1
export AUDITCTL_TEST_ENABLED=2
export AUDITCTL_TEST_NO_RULES=1
add_audit_rules >"$TMP_DIR/staging-output" 2>&1 ||
  fail "add_audit_rules debe preparar reglas persistentes cuando enabled=2"
[ -s "$AUDIT_RULES" ] || { cat "$TMP_DIR/staging-output" >&2; fail "no se creó el archivo persistente de reglas OrangeBox"; }
grep -Fq '# OrangeBox hardening audit rules' "$AUDIT_RULES" ||
  fail "el archivo persistente no tiene el marcador de propiedad OrangeBox"
for key in time-change identity system-locale logins session perm_mod access mounts delete scope modules; do
  grep -Fq -- "-k $key" "$AUDIT_RULES" || fail "faltan reglas persistentes para $key"
done
if grep -Eq '^[[:space:]]*-e[[:space:]]+2' "$AUDIT_RULES"; then
  fail "la inmutabilidad no debe mezclarse con el archivo de reglas baseline"
fi
[ "$(stat -c %a "$AUDIT_RULES")" = "640" ] || fail "el archivo persistente debe tener modo 640"
pass "reglas completas staged en ruta aislada sin tocar reglas en memoria"

pass "la interpretación de enabled se prueba con auditctl simulado y sin cambios en el sistema"
