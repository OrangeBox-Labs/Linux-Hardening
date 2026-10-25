#!/usr/bin/env bash
# Regression tests for OrangeBox operational guardrails.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
KERNEL="$ROOT_DIR/kernel-hardening.sh"
PASSWORD="$ROOT_DIR/password-hardening.sh"
SUDO="$ROOT_DIR/sudo-hardening.sh"
SELINUX="$ROOT_DIR/selinux-secure-setup.sh"
POST_INSTALL="$ROOT_DIR/post-install.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Sysctl policy: fixed target for suid_dumpable/dmesg_restrict and conditional kptr policy.
grep -Fq 'set_sysctl fs.suid_dumpable 0' "$CORE" || fail "baseline no fuerza fs.suid_dumpable=0 como objetivo"
grep -Fq 'set_sysctl kernel.dmesg_restrict 1' "$CORE" || fail "baseline no fuerza kernel.dmesg_restrict=1 como objetivo"
grep -Fq 'check_sysctl_param "fs.suid_dumpable" "0"' "$KERNEL" || fail "kernel-hardening no contempla fs.suid_dumpable=0"
grep -Fq 'check_sysctl_param "kernel.dmesg_restrict" "1"' "$KERNEL" || fail "kernel-hardening no contempla kernel.dmesg_restrict=1"
grep -Fq 'set_kptr_restrict_policy' "$CORE" || fail "baseline no utiliza la política condicional de kptr_restrict"
grep -Fq 'check_kptr_restrict_policy' "$KERNEL" || fail "kernel-hardening no utiliza la política condicional de kptr_restrict"
if grep -Eq 'set_sysctl kernel\.kptr_restrict 2|check_sysctl_param "kernel\.kptr_restrict" "2"' "$CORE" "$KERNEL"; then
  fail "un módulo sigue imponiendo kernel.kptr_restrict=2"
fi
pass "sysctl: suid_dumpable=0, dmesg_restrict=1 y kptr_restrict conserva 1/2 o propone 0->1"

# All interactive confirmations use the Spanish [s/N] convention, with No as default.
SYSCTL_SAFE="$ROOT_DIR/lib/sysctl-safe.sh"
NETWORK="$ROOT_DIR/network-hardening.sh"
grep -Fq '[s/N]' "$SYSCTL_SAFE" || fail "sysctl-safe no usa la confirmación estándar [s/N]"
grep -Fq '[s/N]' "$NETWORK" || fail "network-hardening no usa la confirmación estándar [s/N]"
grep -Fq 'sysctl_safe_log()' "$SYSCTL_SAFE" || fail "sysctl-safe no centraliza los colores de estado"
if grep -R -n -E '\\[(y/N|Y/n|Y/N|y/n)\\]|\\(s/n\\)' --include='*.sh' "$ROOT_DIR" --exclude-dir=.git --exclude-dir=tests; then
  fail "queda una confirmación con formato antiguo; usar [s/N]"
fi
pass "confirmaciones estandarizadas en español y valores SYSCTL con salida coloreada"

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
