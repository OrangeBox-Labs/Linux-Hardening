#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
# Force every test path to use the fake auditctl from PATH, never the host binary.
auditctl() { bash "$TMP_DIR/bin/auditctl" "$@"; }
get_auditctl_path() { printf 'auditctl\n'; }

assert_state() {
  local state="$1" expected="$2" forbidden="$3" output=""
  export AUDITCTL_TEST_ENABLED="$state"
  WARNINGS=0
  output="$(legacy_audit_rules_check 2>&1)" || fail "la comprobación falló con enabled=$state"
  printf '%s\n' "$output" | grep -Fq -- "$expected" ||
    fail "enabled=$state no mostró el mensaje esperado: $expected. Salida capturada: $output"
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
    fail "la ruta moderna no mostró el estado esperado para enabled=$state: $expected. Salida capturada: $modern_output"
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
get_auditctl_path() { printf '%s\n' "$TMP_DIR/bin/auditctl"; }
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
# El segundo source restaura la función productiva; reimponer el stub para no consultar el auditctl real.
get_auditctl_path() { printf '%s\n' "$TMP_DIR/bin/auditctl"; }

# En modo verificación debe avisar si el baseline OrangeBox existente está obsoleto,
# sin modificarlo ni intentar cargar reglas en el kernel.
AUTO_FIX=false
FIXED=0
WARNINGS=0
AUDIT_RULES_DIR="$TMP_DIR/verify-rules"
AUDIT_RULES="$AUDIT_RULES_DIR/98-orangebox-baseline.rules"
mkdir -p "$AUDIT_RULES_DIR"
printf '%s\n' '# OrangeBox hardening audit rules' '-a always,exit -F arch=b32 -S stime -k time-change' > "$AUDIT_RULES"
add_audit_rules >"$TMP_DIR/verify-output" 2>&1 ||
  fail "la verificación del baseline obsoleto no debe fallar"
grep -Fq 'El baseline OrangeBox requiere reparación' "$TMP_DIR/verify-output" ||
  fail "el modo verificación debe advertir que el baseline contiene reglas obsoletas"
grep -Eq '(^|[[:space:]])-S[[:space:]]+stime([[:space:]]|$)' "$AUDIT_RULES" ||
  fail "el modo verificación no debe modificar el baseline"
[ "$WARNINGS" -gt 0 ] || fail "el baseline obsoleto debe incrementar las advertencias"
pass "modo verificación detecta baseline obsoleto sin modificarlo"

# Prueba real de staging con rutas aisladas: no modifica /etc/audit ni carga reglas al kernel.
AUTO_FIX=true
FIXED=0
WARNINGS=0
AUDIT_RULES_DIR="$TMP_DIR/staged-rules"
AUDIT_RULES="$AUDIT_RULES_DIR/98-orangebox-baseline.rules"
export ORANGEBOX_ASSUME_YES=1
# CI runners may be unprivileged; ownership changes are outside this isolated staging test.
chown() { return 0; }
export AUDITCTL_TEST_ENABLED=2
export AUDITCTL_TEST_NO_RULES=1
add_audit_rules >"$TMP_DIR/staging-output" 2>&1 || {
  cat "$TMP_DIR/staging-output" >&2
  fail "add_audit_rules debe preparar reglas persistentes cuando enabled=2"
}
[ -s "$AUDIT_RULES" ] || { cat "$TMP_DIR/staging-output" >&2; fail "no se creó el archivo persistente de reglas OrangeBox"; }
grep -Fq '# OrangeBox hardening audit rules' "$AUDIT_RULES" ||
  fail "el archivo persistente no tiene el marcador de propiedad OrangeBox"
for key in time-change identity system-locale logins session perm_mod access mounts delete scope modules; do
  if grep -Fq -- "-k $key" "$AUDIT_RULES"; then
    continue
  fi
  case "$key" in
    logins)
      if [ ! -e /var/log/faillog ] && [ ! -e /var/log/lastlog ] && [ ! -e /var/log/tallylog ]; then
        pass "se omite logins porque no existe ninguna ruta de login auditable en este host"
        continue
      fi
      ;;
    session)
      if [ ! -e /var/run/utmp ] && [ ! -e /var/log/wtmp ] && [ ! -e /var/log/btmp ]; then
        pass "se omite session porque no existe ninguna ruta de sesión auditable en este host"
        continue
      fi
      ;;
    scope)
      if [ ! -e /etc/sudoers ] && [ ! -e /etc/sudoers.d ]; then
        pass "se omite scope porque sudoers no está instalado en este entorno de prueba"
        continue
      fi
      ;;
  esac
  fail "faltan reglas persistentes para $key"
done
persistent_audit_rules_ready || fail "el baseline filtrado debe seguir considerándose listo cuando las rutas opcionales de login/sesión no existen"
if grep -Eq '^[[:space:]]*-e[[:space:]]+2' "$AUDIT_RULES"; then
  fail "la inmutabilidad no debe mezclarse con el archivo de reglas baseline"
fi
[ "$(stat -c %a "$AUDIT_RULES")" = "640" ] || fail "el archivo persistente debe tener modo 640"
if grep -Eq '(^|[[:space:]])-S[[:space:]]+stime([[:space:]]|$)' "$AUDIT_RULES"; then
  fail "el baseline no debe generar el syscall stime"
fi
if [ ! -e /etc/network ] && grep -Eq '^[[:space:]]*-w[[:space:]]+/etc/network([[:space:]]|$)' "$AUDIT_RULES"; then
  fail "el baseline no debe incluir watches de rutas ausentes"
fi
pass "reglas completas staged en ruta aislada sin tocar reglas en memoria ni generar stime"

# El validador estático acepta el baseline generado y rechaza reglas peligrosas/malformadas.
validate_staged_audit_rules "$AUDIT_RULES" ||
  fail "el validador debe aceptar el baseline staged correcto"
printf '%s\n' '# OrangeBox hardening audit rules' '-a always,exit -F arch=b32 -S stime -k time-change' > "$TMP_DIR/invalid-stime.rules"
if validate_staged_audit_rules "$TMP_DIR/invalid-stime.rules" >"$TMP_DIR/invalid-stime-output" 2>&1; then
  fail "el validador debe rechazar stime"
fi
printf '%s\n' '# OrangeBox hardening audit rules' '-w /ob-test-missing-path-xyz -p wa -k identity' > "$TMP_DIR/invalid-watch.rules"
if validate_staged_audit_rules "$TMP_DIR/invalid-watch.rules" >"$TMP_DIR/invalid-watch-output" 2>&1; then
  fail "el validador debe rechazar watches a rutas inexistentes"
fi
cp "$AUDIT_RULES" "$TMP_DIR/invalid-immutable.rules"
printf '%s\n' '-e 2' >> "$TMP_DIR/invalid-immutable.rules"
if validate_staged_audit_rules "$TMP_DIR/invalid-immutable.rules" >"$TMP_DIR/invalid-immutable-output" 2>&1; then
  fail "el validador debe rechazar -e 2 dentro del baseline"
fi
cp "$AUDIT_RULES" "$TMP_DIR/invalid-directive.rules"
printf '%s\n' '-z this-is-not-an-audit-rule' >> "$TMP_DIR/invalid-directive.rules"
if validate_staged_audit_rules "$TMP_DIR/invalid-directive.rules" >"$TMP_DIR/invalid-directive-output" 2>&1; then
  fail "el validador debe rechazar directivas desconocidas"
fi
pass "el validador estático acepta reglas válidas y rechaza stime, watches ausentes, -e 2 y directivas inválidas"

# Un fallo de escritura del heredoc debe conservar el baseline anterior.
write_failure_dir="$TMP_DIR/write-failure-rules"
mkdir -p "$write_failure_dir"
AUDIT_RULES_DIR="$write_failure_dir"
AUDIT_RULES="$write_failure_dir/98-orangebox-baseline.rules"
printf '%s\n' '# OrangeBox hardening audit rules' '-a always,exit -F arch=b32 -S stime -k time-change' > "$AUDIT_RULES"
cp "$AUDIT_RULES" "$TMP_DIR/baseline-before-write-failure"
cat() { return 1; }
if add_audit_rules >"$TMP_DIR/write-failure-output" 2>&1; then
  fail "add_audit_rules debe fallar si falla la escritura del staging"
fi
unset -f cat
cmp -s "$AUDIT_RULES" "$TMP_DIR/baseline-before-write-failure" ||
  fail "un fallo de escritura no debe modificar el baseline anterior"
grep -Fq 'No se pudo escribir el staging de reglas' "$TMP_DIR/write-failure-output" ||
  fail "el fallo de escritura debe generar un diagnóstico explícito"
pass "fallo de escritura en staging conserva el baseline previo"

# Un archivo OrangeBox existente con reglas obsoletas debe repararse en staging,
# incluso si las categorías requeridas ya están presentes. No se carga al kernel.
printf '%s\n' '-a always,exit -F arch=b32 -S stime -k time-change' '-w /ob-test-nonexistent-audit-watch-path -p wa -k logins' >> "$AUDIT_RULES"
add_audit_rules >"$TMP_DIR/repair-output" 2>&1 || {
  cat "$TMP_DIR/repair-output" >&2
  fail "el script debe reparar el baseline OrangeBox obsoleto"
}
if grep -Eq '(^|[[:space:]])-S[[:space:]]+stime([[:space:]]|$)' "$AUDIT_RULES"; then
  fail "la reparación dejó stime en el archivo persistente"
fi
if grep -Fq '/ob-test-nonexistent-audit-watch-path' "$AUDIT_RULES"; then
  fail "la reparación dejó un watch sobre una ruta inexistente"
fi
grep -Fq 'Reglas persistentes escritas y filtradas' "$TMP_DIR/repair-output" ||
  fail "la reparación debe informar que regeneró el archivo OrangeBox"
pass "un baseline OrangeBox obsoleto se repara atómicamente sin cargar reglas al kernel"

pass "la interpretación de enabled se prueba con auditctl simulado y sin cambios en el sistema"
