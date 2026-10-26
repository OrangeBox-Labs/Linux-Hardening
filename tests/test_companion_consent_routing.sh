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

for module in auditd-full cron-full grub-full rsyslog-full password-full sudo-full kernel-full network-full filesystem-full package-repos crypto-policies selinux-setup; do
  grep -Fq "$module)" "$CORE" ||
    fail "el enrutador no incluye el módulo $module en el grupo con consentimiento por control"
done

pass "el orquestador evita confirmaciones duplicadas y nunca omite consentimiento interactivo"
