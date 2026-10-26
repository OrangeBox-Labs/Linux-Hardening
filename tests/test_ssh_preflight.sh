#!/usr/bin/env bash
# Regression tests for SSH preflight, visible audit state, and safe remediation.
set -eu
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
ORCHESTRATOR="$ROOT_DIR/linux-hardening.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'SSH_EXPECTED_SETTINGS=(' "$ORCHESTRATOR" || fail "falta la lista de parámetros SSH esperados"
for setting in \
  'ignorerhosts|yes|IgnoreRhosts' \
  'hostbasedauthentication|no|HostbasedAuthentication' \
  'permituserenvironment|no|PermitUserEnvironment' \
  'permitemptypasswords|no|PermitEmptyPasswords' \
  'maxauthtries|6|MaxAuthTries' \
  'logingracetime|60|LoginGraceTime' \
  'clientaliveinterval|300|ClientAliveInterval' \
  'clientalivecountmax|2|ClientAliveCountMax' \
  'loglevel|INFO|LogLevel'; do
  grep -Fq "\"$setting\"" "$ORCHESTRATOR" || fail "falta validar el objetivo SSH: $setting"
done

grep -Fq 'ssh_state_status preflight' "$ORCHESTRATOR" || fail "no se comprueba SSH antes de preguntar"
grep -Fq 'ssh_report_unverifiable_settings()' "$ORCHESTRATOR" || fail "el audit no desglosa SSH cuando sshd no puede consultarse"
grep -Fq '      --audit) AUDIT_MODE=true ;;' "$ORCHESTRATOR" || fail "falta opción explícita de auditoría"
grep -Fq '      --audit) AUDIT_MODE=true ;;' "$ORCHESTRATOR" || fail "falta opción explícita de auditoría"
grep -Fq 'elif [ "$ssh_status" -eq 1 ] && ssh_module_can_apply; then' "$ORCHESTRATOR" || fail "la confirmación no está limitada a diferencias verificadas y aplicables"
grep -Fq 'Los nueve controles SSH ya cumplen los objetivos efectivos' "$ORCHESTRATOR" || fail "falta omitir la pregunta cuando SSH ya cumple"
grep -Fq 'Los controles SSH ya cumplen los objetivos efectivos; no se modifica la configuración' "$ORCHESTRATOR" || fail "falta confirmar que no se reescribe SSH conforme"
grep -Fq 'SSH_PENDING_DIRECTIVES+=("$directive $desired")' "$ORCHESTRATOR" || fail "no se registra cada directiva pendiente"
grep -Fq 'for directive in "${SSH_PENDING_DIRECTIVES[@]}"' "$ORCHESTRATOR" || fail "la remediación no muestra las directivas pendientes"
grep -Fq 'ok "SSH $directive=$actual"' "$ORCHESTRATOR" || fail "no se informa cuando un parámetro SSH ya está conforme"
grep -Fq 'ssh_module_apply_block_reason' "$ORCHESTRATOR" || fail "no se explica por qué se bloquea la aplicación de SSH"
grep -Fq 'ssh_apply_pending_settings' "$ORCHESTRATOR" || fail "falta el flujo de aplicación segura SSH"
grep -Fq 'sshd -t -f "$main"' "$ORCHESTRATOR" || fail "no se valida la configuración completa de SSH antes de recargar"
grep -Fq 'ssh_state_status quiet' "$ORCHESTRATOR" || fail "no se verifican los valores efectivos antes de recargar"
grep -Fq 'ssh_reload_service' "$ORCHESTRATOR" || fail "no se recarga sshd después de validar cambios"
grep -Fq '[ ! -L "$SSH_DROPIN" ]' "$ORCHESTRATOR" || fail "no se protege frente a un drop-in SSH que sea un enlace simbólico"
if grep -Fq 'ssh_module_can_apply || return 0' "$ORCHESTRATOR"; then
  fail "la auditoría compacta todavía oculta SSH si el drop-in no es aplicable"
fi
if grep -Fq 'no se puede aplicar sin sobrescribir configuración o fuera de las condiciones admitidas' "$ORCHESTRATOR"; then
  fail "el preflight aún usa un mensaje genérico sin motivo ni remediación"
fi

pass "SSH visible en auditoría, aplicación validada con rollback e instrucciones cuando no puede corregirse automáticamente"
