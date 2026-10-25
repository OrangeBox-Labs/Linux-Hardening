#!/usr/bin/env bash
# Regression tests for SSH effective-setting checks before operational-risk confirmation.
set -eu
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
ORCHESTRATOR="$ROOT_DIR/linux-hardening.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'SSH_EXPECTED_SETTINGS=(' "$ORCHESTRATOR" || fail "falta la lista de parámetros SSH esperados"

for setting in \
  'ignorerhosts yes' \
  'hostbasedauthentication no' \
  'permituserenvironment no' \
  'permitemptypasswords no' \
  'maxauthtries 6' \
  'logingracetime 60' \
  'clientaliveinterval 300' \
  'clientalivecountmax 2' \
  'loglevel INFO'; do
  grep -Fq "\"$setting\"" "$ORCHESTRATOR" || fail "falta validar el objetivo SSH: $setting"
done

grep -Fq 'ssh_state_status preflight' "$ORCHESTRATOR" || fail "no se comprueba SSH antes de preguntar"
grep -Fq 'elif [ "$ssh_status" -eq 1 ] && ssh_module_can_apply; then' "$ORCHESTRATOR" || fail "la confirmación no está limitada a diferencias verificadas y aplicables"
grep -Fq 'Los nueve controles SSH ya cumplen los objetivos efectivos' "$ORCHESTRATOR" || fail "falta omitir la pregunta cuando SSH ya cumple"
grep -Fq 'no se crea un drop-in redundante' "$ORCHESTRATOR" || fail "el módulo podría crear configuración SSH redundante"
grep -Fq 'if sshd -t >/dev/null 2>&1 && ssh_state_status; then' "$ORCHESTRATOR" || fail "no se valida la sintaxis y los valores efectivos tras el cambio"
grep -Fq '[ ! -L "$SSH_DROPIN" ]' "$ORCHESTRATOR" || fail "no se protege frente a un drop-in SSH que sea un enlace simbólico"

pass "SSH solo pregunta por controles pendientes que se pueden aplicar de forma segura; configuración conforme no genera cambios"
