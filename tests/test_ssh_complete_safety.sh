#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
SSH="$ROOT_DIR/ssh-hardening-complete.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'confirm_ssh_complete_change()' "$SSH" || fail "SSH avanzado no exige consentimiento"
grep -Fq 'sshd -t' "$SSH" || fail "no valida la configuración SSH"
grep -Fq 'sshd -T' "$SSH" || fail "no valida los valores efectivos de sshd"
grep -Fq 'NO se regeneran ni eliminan claves de host' "$SSH" || fail "el informe no informa que conserva host keys"
grep -Fq 'NO se modifica ninguna regla de firewall' "$SSH" || fail "el informe no informa que no toca el firewall"
grep -Fq 'no se instala ni actualiza desde este script' "$SSH" || fail "ssh-audit puede instalar paquetes automáticamente"
grep -Fq 'systemctl reload sshd' "$SSH" || fail "SSH avanzado debe usar reload"
grep -Fq 'challengeresponseauthentication|kbdinteractiveauthentication)' "$SSH" || fail "SSH avanzado debe describir el riesgo de keyboard-interactive/MFA"
grep -Fq 'usepam)' "$SSH" || fail "SSH avanzado debe describir el riesgo de UsePAM"
if grep -Eq 'challenger[[:space:]]+esponseauthentication|us[[:space:]]+epam' "$SSH"; then
  fail "SSH avanzado conserva etiquetas de impacto con espacios que rompen la sintaxis Bash"
fi
if grep -Eq 'rm -f /etc/ssh/ssh_host_|ssh-keygen -t|firewall-cmd --permanent|systemctl restart sshd|service sshd restart|>/etc/crypto-policies/back-ends/opensshserver.config|sed -i .*HostKey' "$SSH"; then
  fail "ssh-hardening-complete conserva una modificación destructiva de hostkeys, crypto-policy o firewall"
fi
if grep -Fq 'PasswordAuthentication yes' "$SSH"; then
  fail "ssh-hardening-complete no debe habilitar autenticación por password como parte del baseline"
fi
grep -Fq 'if ! make_backup; then' "$SSH" || fail "SSH avanzado continúa si falla el backup"

pass "SSH avanzado conserva host keys, crypto-policy y firewall; aplica config tras consentimiento, validación y reload"
