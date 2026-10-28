#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
SSH="$ROOT_DIR/ssh-hardening.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'confirm_ssh_change()' "$SSH" || fail "SSH no tiene confirmación por parámetro/acción"
grep -Fq 'ssh_install_parameter()' "$SSH" || fail "SSH no tiene ruta única de instalación segura"
grep -Fq 'sshd -t -f "$tmp"' "$SSH" || fail "SSH no valida el candidato antes de escribir"
grep -Fq 'ssh_effective_value "$param" "$tmp"' "$SSH" || fail "SSH no comprueba valor efectivo del candidato"
grep -Fq 'if ! make_backup; then' "$SSH" || fail "SSH continúa si falla el backup"
grep -Fq 'systemctl reload sshd' "$SSH" || fail "SSH no recarga de manera conservadora"
if grep -Eq 'sed -i .*"$SSHD_CONFIG"|echo .*>>"$SSHD_CONFIG"|systemctl restart sshd|service sshd restart' "$SSH"; then
  fail "SSH aún escribe en caliente o fuerza reinicio sin validación/confirmación"
fi
for param in 'ciphers' 'macs' 'kexalgorithms' 'clientaliveinterval' 'clientalivecountmax'; do
  grep -Fq "check_sshd_param \"$param\"" "$SSH" || fail "SSH no verifica con precisión $param"
done
pass "ssh-hardening: backup, consentimiento, candidato sshd -t, verificación efectiva y reload"
