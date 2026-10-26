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
POST_INSTALL_SCRIPT="$ROOT_DIR/post-install.sh"
grep -Fq '[s/N]' "$SYSCTL_SAFE" || fail "sysctl-safe no usa la confirmación estándar [s/N]"
grep -Fq '[s/N]' "$NETWORK" || fail "network-hardening no usa la confirmación estándar [s/N]"
grep -Fq '[s/N]' "$POST_INSTALL_SCRIPT" || fail "post-install no usa la confirmación estándar [s/N]"
grep -Fq 'sysctl_safe_log()' "$SYSCTL_SAFE" || fail "sysctl-safe no centraliza los colores de estado"
legacy_prompts="$(find "$ROOT_DIR" -type f -name '*.sh' ! -path "$ROOT_DIR/tests/*" -print0 | xargs -0 grep -n -F -e '[y/N]' -e '[Y/n]' -e '[Y/N]' -e '[y/n]' -e '(s/n)' -e '(s/N)' 2>/dev/null || true)"
if [ -n "$legacy_prompts" ]; then
  printf '%s\n' "$legacy_prompts" >&2
  fail "quedan prompts con formatos antiguos; usar [s/N]"
fi
pass "confirmaciones estandarizadas en español y estados SYSCTL coloreados"

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

# Kernel LPE mitigation must not overstate the user-namespace control or infer patch state from changelog text.
LPE="$ROOT_DIR/kernel-lpe-2026-mitigation.sh"
grep -Fq 'no mitiga DiagSpill (CVE-2026-74469)' "$LPE" || fail "user namespaces se presenta como mitigación de las cuatro CVE"
grep -Fq 'NO prueba que falte el parche' "$LPE" || fail "la ausencia de una CVE en changelog se presenta como prueba de falta de parche"
pass "el módulo LPE distingue la mitigación por user namespaces y el estado no concluyente del changelog"

# fapolicyd is never installed or activated by the baseline; Wazuh is reported when found.
grep -Fq 'Wazuh detectado:' "$CORE" || fail "no se informa cuando Wazuh está instalado"
grep -Fq 'no instalará ni activará fapolicyd' "$CORE" || fail "falta la política de no instalación/activación de fapolicyd"
if grep -Eq '(dnf|yum)[[:space:]]+install.*fapolicyd|systemctl[[:space:]]+(enable|start|restart).*fapolicyd' "$CORE"; then
  fail "el baseline intenta instalar o activar fapolicyd"
fi
# CentOS/RHEL 6 uses the legacy syslog stack; do not require journald.
grep -Fq 'rsyslog_legacy_is_active()' "$CORE" || fail "falta comprobar rsyslog en CentOS/RHEL 6"
grep -Fq 'journald no aplica a CentOS/RHEL 6' "$CORE" || fail "el baseline sigue tratando journald como obligatorio en CentOS 6"
grep -Fq 'if [ "${OS_VERSION:-}" = 6 ]; then' "$CORE" || fail "no se detecta la generación legacy para la auditoría de logs"
pass "syslog/journald se distingue correctamente en CentOS/RHEL 6"

# Older RHEL-family hosts must use their native auditd, ntpd and GRUB interfaces.
grep -Fq 'auditd_is_active()' "$CORE" || fail "falta detección auditd compatible con SysV"
grep -Fq 'service auditd status' "$CORE" || fail "CentOS 6 no comprueba auditd mediante service"
grep -Fq 'ntpq -pn' "$CORE" || fail "falta comprobación del peer de ntpd legacy"
grep -Fq '/boot/grub/grub.conf' "$CORE" || fail "CentOS 6 no comprueba grub.conf"
grep -Fq 'if [ "${OS_VERSION:-0}" = 6 ]; then' "$CORE" || fail "el control GRUB legacy no depende de la versión detectada"
if grep -Fq '\${OS_VERSION:-0}' "$CORE"; then
  fail "grub_module contiene una expansión OS_VERSION escapada que impide detectar CentOS 6"
fi
grep -Fq 'update-crypto-policies no aplica a CentOS/RHEL 6/7' "$CORE" || fail "crypto policies ausentes en EL6/7 se siguen marcando como fallo"
grep -Fq 'sysctl -n "$key"' "$CORE" || fail "los sysctl ausentes siguen contándose como controles fallidos"

grub_fn_tmp="$(mktemp)"
trap 'rm -f "$grub_fn_tmp"' EXIT
awk '/^grub_module\(\)\{/ {in_fn=1} in_fn {print} in_fn && /^}$/ {exit}' "$CORE" > "$grub_fn_tmp"
[ -s "$grub_fn_tmp" ] || fail "no se pudo extraer grub_module"
grub_output="$(
  BLUE="" NC=""
  OS_VERSION=6
  ok() { printf '[OK] %s\\n' "$*"; }
  warn() { printf '[WARN] %s\\n' "$*"; }
  info() { printf '[INFO] %s\\n' "$*"; }
  . "$grub_fn_tmp"
  grub_module
)"
case "$grub_output" in *"GRUB legacy"*) ;; *) fail "OS_VERSION=6 no entra a la rama GRUB legacy: $grub_output" ;; esac
case "$grub_output" in *"grub.cfg no localizado"*) fail "CentOS 6 cae incorrectamente en la rama moderna de grub.cfg" ;; esac
pass "auditorías de auditd, NTP, GRUB, crypto-policy y sysctl distinguen EL6"

# PAM tooling differs on older CentOS/RHEL; it remains read-only.
grep -Fq 'pam_tally2.so' "$CORE" || fail "CentOS 6 no contempla el mecanismo legacy pam_tally2"
grep -Fq 'pam_faillock.so' "$CORE" || fail "las versiones modernas deben conservar la comprobación pam_faillock"
grep -Fq 'authselect no aplica al stack PAM legacy de CentOS/RHEL 6/7' "$CORE" || fail "authselect ausente en CentOS 6 sigue generando un falso positivo"
pass "PAM se comprueba según la generación sin modificar la pila de autenticación"

pass "fapolicyd no se instala ni activa y se informa la detección de Wazuh"
