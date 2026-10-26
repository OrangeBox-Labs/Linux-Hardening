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
  pass "enabled=$state se interpreta correctamente"
}

assert_state "1"   "auditd está habilitado (enabled 1), pero las reglas siguen siendo modificables"   "Configuración de auditd inmutable - OK"
assert_state "2"   "Configuración de auditd inmutable - OK (enabled 2)"   "no está en modo inmutable"
assert_state "0"   "auditd está deshabilitado (enabled 0)"   "Configuración de auditd inmutable - OK"
assert_state "10"   "auditd reporta enabled 10; no se confirma modo inmutable"   "Configuración de auditd inmutable - OK"
assert_state "missing"   "No se pudo determinar el estado de auditd mediante auditctl -s"   "Configuración de auditd inmutable - OK"

pass "la interpretación de enabled se prueba con auditctl simulado y sin cambios en el sistema"
