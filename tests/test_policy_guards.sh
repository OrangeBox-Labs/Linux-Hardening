#!/usr/bin/env bash
# Regression tests for OrangeBox operational guardrails.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
PASSWORD="$ROOT_DIR/password-hardening.sh"
SUDO="$ROOT_DIR/sudo-hardening.sh"
SELINUX="$ROOT_DIR/selinux-secure-setup.sh"
POST_INSTALL="$ROOT_DIR/post-install.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Password aging must be observed but never rewritten by either baseline.
grep -Fq 'PASS_MAX_DAYS=' "$CORE" || fail "baseline no informa PASS_MAX_DAYS"
grep -Fq 'PASS_MAX_DAYS=' "$PASSWORD" || fail "password-hardening no documenta/conserva PASS_MAX_DAYS"
if grep -Eq 'set_conf_value[[:space:]].*PASS_MAX_DAYS' "$PASSWORD"; then
  fail "password-hardening vuelve a modificar PASS_MAX_DAYS"
fi
pass "PASS_MAX_DAYS se informa pero no se modifica"

# sudo use_pty must not be automatic: cPanel is excluded and non-cPanel changes prompt.
grep -Fq 'cPanel detectado: por política OrangeBox no se activa use_pty' "$CORE" || fail "baseline no excluye use_pty en cPanel"
grep -Fq '¿Deseas habilitar Defaults use_pty en este servidor?' "$CORE" || fail "baseline no pregunta antes de habilitar use_pty"
grep -Fq 'cPanel detectado: se omite use_pty' "$SUDO" || fail "sudo-hardening no excluye use_pty en cPanel"
grep -Fq '¿Habilitar Defaults use_pty?' "$SUDO" || fail "sudo-hardening no pregunta antes de habilitar use_pty"
pass "use_pty requiere confirmación y se omite en cPanel"

# SELinux must only be read. Prevent known state/configuration/context-changing commands.
grep -Fq 'selinux-setup bloqueado por política OrangeBox' "$CORE" || fail "el orquestador no bloquea selinux-setup"
for script in "$SELINUX" "$POST_INSTALL"; do
  if grep -Eq '^[[:space:]]*(setenforce|restorecon|semanage|reboot)[[:space:]]|sed[[:space:]]+-i.*SELINUX' "$script"; then
    fail "$(basename "$script") contiene una acción que modifica SELinux o reinicia"
  fi
done
pass "SELinux solo se audita; no hay acciones de cambio en los módulos SELinux"

# fapolicyd is never installed or activated by the baseline; Wazuh is reported when found.
grep -Fq 'Wazuh detectado:' "$CORE" || fail "no se informa cuando Wazuh está instalado"
grep -Fq 'no instalará ni activará fapolicyd' "$CORE" || fail "falta la política de no instalación/activación de fapolicyd"
if grep -Eq '(dnf|yum)[[:space:]]+install.*fapolicyd|systemctl[[:space:]]+(enable|start|restart).*fapolicyd' "$CORE"; then
  fail "el baseline intenta instalar o activar fapolicyd"
fi
pass "fapolicyd no se instala ni activa y se informa la detección de Wazuh"
