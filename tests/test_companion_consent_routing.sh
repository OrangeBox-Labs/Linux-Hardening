#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'companion_module_owns_parameter_consent()' "$CORE" ||
  fail "falta el mapa de módulos que ya piden consentimiento por control"
grep -Fq 'se omite una confirmación global duplicada' "$CORE" ||
  fail "el orquestador puede pedir confirmación duplicada antes del consentimiento por parámetro"

# The legacy flag must not bypass the terminal prompt.
grep -Fq -- '--allow-risky está obsoleto como bypass' "$CORE" ||
  fail "--allow-risky todavía permite autorizar sin confirmación"
confirm_body="$(awk '/^confirm_risky_change\(\) \{/{p=1} p{print} p && /^}/{exit}' "$CORE")"
printf '%s\n' "$confirm_body" | grep -Fq 'read -r -p "¿Quieres aplicar' ||
  fail "confirm_risky_change no conserva la aprobación interactiva"
if printf '%s\n' "$confirm_body" | grep -Eq 'ALLOW_RISKY.*return 0|return 0.*ALLOW_RISKY'; then
  fail "--allow-risky puede saltarse la confirmación"
fi
printf '%s\n' "$confirm_body" | grep -Fq 'No hay terminal disponible para confirmar' ||
  fail "si no hay terminal, el cambio sensible no se omite explícitamente"

consent_router="$(awk '/^companion_module_owns_parameter_consent\(\) \{/{p=1} p{print} p && /^}/{exit}' "$CORE")"
for module in auditd-full cron-full grub-full rsyslog-full password-full sudo-full kernel-full network-full filesystem-full package-repos crypto-policies selinux-setup usb-storage aide; do
  printf '%s\n' "$consent_router" | grep -Fq "$module" ||
    fail "el enrutador no incluye el módulo $module en el grupo con consentimiento por control"
done

# --allow-shorewall is not valid for a global baseline or read-only audit.
global_shorewall_output=""
if global_shorewall_output="$(bash -c '
  source "$1"
  require_root() { :; }
  main --fix --allow-shorewall
' _ "$CORE" 2>&1)"; then
  fail "--fix --allow-shorewall fue aceptado para el baseline global"
fi
printf '%s\n' "$global_shorewall_output" | grep -Fq -- '--allow-shorewall requiere --module network-full --fix' ||
  fail "la combinación global Shorewall no se rechazó con un mensaje explícito"
if printf '%s\n' "$global_shorewall_output" | grep -Eq 'Detectado:|Backup:|MÓDULO DEL REPOSITORIO'; then
  fail "la validación Shorewall no detuvo la ejecución antes del preflight/backup"
fi
pass "--allow-shorewall se rechaza antes de cualquier preflight salvo para network-full explícito"

# The explicit, module-scoped network override remains parseable; all side-effecting
# functions are stubbed so this only tests argument routing, not the network module.
module_shorewall_output="$(bash -c '
  source "$1"
  require_root() { :; }
  detect_os() { OS_ID=centos; OS_VERSION=8; ID_LIKE=""; }
  prepare_backup() { :; }
  internal_module_requires_risk() { return 1; }
  run_module() { printf "MOCK_MODULE=%s\n" "$1"; }
  main --module network-full --fix --allow-shorewall
' _ "$CORE" 2>&1)" || {
  printf '%s\n' "$module_shorewall_output" >&2
  fail "el módulo network-full explícito rechazó la autorización Shorewall"
}
printf '%s\n' "$module_shorewall_output" | grep -Fq 'MOCK_MODULE=network-full' ||
  fail "la combinación explícita network-full no llegó al módulo simulado"
pass "la autorización Shorewall sigue limitada al flujo explícito network-full --fix"

# EL6 supports the auditd legacy read-only path but its companion --fix is
# intentionally unsupported; the orchestrator must not prompt then invoke it.
el6_audit_output="$(bash -c '
  set -euo pipefail
  source "$1"
  AUTO_FIX=true
  AUTO_MODE=false
  MODULE=all
  OS_VERSION=6
  COMPANION_MODULES_RUN=0
  COMPANION_MODULES_FAILED=0
  run_companion_script() {
    if [ "${2:-}" = "--fix" ]; then
      printf "%s\n" "UNEXPECTED_FIX_ATTEMPT"
      return 97
    fi
    printf "%s\n" "MOCK_LEGACY_AUDIT"
    return 0
  }
  companion_module_owns_parameter_consent() { return 1; }
  confirm_risky_change() { printf "%s\n" "UNEXPECTED_RISK_CONFIRMATION"; return 0; }
  run_companion_module auditd-full
  [ "$COMPANION_MODULES_RUN" -eq 1 ]
  [ "$COMPANION_MODULES_FAILED" -eq 0 ]
' _ "$CORE" 2>&1)" || {
  printf '%s\n' "$el6_audit_output" >&2
  fail "el orquestador no omitió correctamente auditd-full --fix en EL6"
}
printf '%s\n' "$el6_audit_output" | grep -Fq 'auditd-full en EL6 queda en auditoría legacy' ||
  fail "falta el mensaje explícito que explica el modo de solo lectura de auditd en EL6"
if printf '%s\n' "$el6_audit_output" | grep -Eq 'UNEXPECTED_FIX_ATTEMPT|UNEXPECTED_RISK_CONFIRMATION'; then
  fail "EL6 intentó aplicar auditd o solicitó una confirmación inútil"
fi
pass "auditd-full en EL6 conserva la auditoría legacy y no ofrece un fix que abortaría"

pass "el orquestador evita confirmaciones duplicadas y nunca omite consentimiento interactivo"
