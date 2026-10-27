#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/sysctl-safe.sh
source "$ROOT_DIR/lib/sysctl-safe.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
MOCK_BPF=""
MOCK_DEFS=""
SYSCTL_WRITES="$TMP_DIR/sysctl-writes"
: > "$SYSCTL_WRITES"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Mock only the BPF key and keep all tests isolated from host sysctls.
sysctl() {
  if [ "${1:-}" = "-n" ] && [ "${2:-}" = "kernel.unprivileged_bpf_disabled" ]; then
    printf '%s\n' "$MOCK_BPF"
    return 0
  fi
  if [ "${1:-}" = "-w" ] && [[ "${2:-}" == kernel.unprivileged_bpf_disabled=* ]]; then
    printf '%s\n' "$*" >> "$SYSCTL_WRITES"
    MOCK_BPF="${2#*=}"
    return 0
  fi
  command sysctl "$@"
}
sysctl_safe_inventory() {
  [ "${1:-}" = "kernel.unprivileged_bpf_disabled" ] || return 1
  printf '%s\n' "$MOCK_DEFS"
}

# Both 1 (cannot be re-enabled at runtime) and 2 (can be changed by root)
# disable unprivileged BPF. Neither valid current value should be downgraded.
for value in 1 2; do
  MOCK_BPF="$value"
  MOCK_DEFS="/etc/sysctl.d/10-policy.conf|1|$value"
  target="$TMP_DIR/preserve-$value.conf"
  output="$(sysctl_safe_apply_bpf_policy "$target" "$TMP_DIR/backup" true 2>&1)" ||
    fail "valor actual $value debe aceptarse"
  printf '%s\n' "$output" | grep -Fq "la política acepta 1 o 2" ||
    fail "no se informó que el valor $value está permitido"
  [ ! -s "$SYSCTL_WRITES" ] || fail "se alteró sysctl con el valor válido $value"
  [ ! -e "$target" ] || fail "se escribió persistencia innecesaria con valor válido $value"
done
pass "kernel.unprivileged_bpf_disabled=1 y =2 se conservan sin degradación"

# Mixed persistence is acceptable because both values satisfy the policy.
MOCK_BPF=1
MOCK_DEFS=$'/etc/sysctl.d/10-policy.conf|1|1\n/etc/sysctl.d/90-local.conf|3|2'
output="$(sysctl_safe_apply_bpf_policy "$TMP_DIR/mixed.conf" "$TMP_DIR/backup" true 2>&1)" ||
  fail "definiciones persistentes 1 y 2 deben aceptarse"
printf '%s\n' "$output" | grep -Fq "la política acepta 1 o 2" ||
  fail "no se aceptó persistencia que solo contiene valores 1 y 2"
[ ! -s "$SYSCTL_WRITES" ] || fail "la combinación válida alteró el sysctl activo"
pass "definiciones persistentes 1/2 no causan una degradación"

# An insecure runtime value is still detected in audit mode without writes.
MOCK_BPF=0
MOCK_DEFS="/etc/sysctl.d/10-policy.conf|1|0"
set +e
output="$(sysctl_safe_apply_bpf_policy "$TMP_DIR/audit-zero.conf" "$TMP_DIR/backup" false 2>&1)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "runtime 0 debe permanecer pendiente en auditoría"
printf '%s\n' "$output" | grep -Fq "kernel.unprivileged_bpf_disabled" ||
  fail "runtime 0 no fue identificado"
[ ! -s "$SYSCTL_WRITES" ] || fail "modo auditoría alteró el sysctl activo"
[ ! -e "$TMP_DIR/audit-zero.conf" ] || fail "modo auditoría escribió persistencia"
pass "runtime 0 se informa sin cambios en auditoría"
