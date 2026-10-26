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
for key in 'kernel.yama.ptrace_scope' 'vm.mmap_min_addr' 'kernel.unprivileged_bpf_disabled' 'user.max_user_namespaces'; do
  grep -Fq "set_sysctl $key " "$CORE" || fail "el baseline principal no evalúa $key"
done
grep -Fq 'set_kptr_restrict_policy' "$CORE" || fail "baseline no utiliza la política condicional de kptr_restrict"
grep -Fq 'check_kptr_restrict_policy' "$KERNEL" || fail "kernel-hardening no utiliza la política condicional de kptr_restrict"
if grep -Eq 'set_sysctl kernel\.kptr_restrict 2|check_sysctl_param "kernel\.kptr_restrict" "2"' "$CORE" "$KERNEL"; then
  fail "un módulo sigue imponiendo kernel.kptr_restrict=2"
fi

CRON="$ROOT_DIR/cron-hardening.sh"
grep -Fq 'confirm_cron_change()' "$CRON" || fail "cron/at hardening must confirm each impactful change"
grep -Fq 'crear $allow_file con root como único usuario permitido' "$CRON" || fail "cron allow-list change does not explain impact on application/hosting accounts"
grep -Fq 'No hay terminal interactiva; se omite el cambio por seguridad.' "$CRON" || fail "cron fix must skip changes without a TTY"
grep -Fq 'No se reinicia crond' "$CRON" || fail "cron fix should not unconditionally restart the daemon after permission changes"
if grep -Fq 'ob_service_restart crond' "$CRON"; then fail "cron hardening should not unconditionally restart crond"; fi

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

# Process limits must be audited through the per-parameter consent helper, never direct-written.
grep -Fq 'check_limits_param "* hard nproc 4096"' "$KERNEL" || fail "nproc debe utilizar el chequeo/confirmación por parámetro"
if sed -n '/^limit_nproc() {/,/^}/p' "$KERNEL" | grep -Eq 'echo.*hard nproc|cat >.*nproc'; then
  fail "nproc todavía se escribe sin backup/confirmación"
fi
pass "nproc usa auditoría y consentimiento por parámetro"

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

# SELinux may transition from Permissive to Enforcing only after explicit consent.
grep -Fq 'confirm_selinux_change' "$SELINUX" || fail "SELinux --fix no requiere confirmación"
grep -Fq 'setenforce 1' "$SELINUX" || fail "SELinux --fix no implementa la transición desde Permissive"
grep -Fq 'SELINUX=enforcing' "$SELINUX" || fail "SELinux --fix no corrige el estado persistente"
grep -Fq 'mode" = "Disabled"' "$SELINUX" || fail "SELinux Disabled no está protegido frente a habilitación automática"
grep -Fq 'No se habilita automáticamente' "$SELINUX" || fail "SELinux Disabled no explica el plan requerido"
if grep -Eq '^[[:space:]]*(restorecon|semanage|reboot)[[:space:]]' "$SELINUX"; then
  fail "SELinux module no debe relabelar, modificar contextos ni reiniciar"
fi
pass "SELinux Enforcing requiere consentimiento y no habilita estado Disabled automáticamente"

# Kernel LPE mitigation must not overstate the user-namespace control or infer patch state from changelog text.
LPE="$ROOT_DIR/kernel-lpe-2026-mitigation.sh"
grep -Fq 'no mitiga DiagSpill (CVE-2026-74469)' "$LPE" || fail "user namespaces se presenta como mitigación de las cuatro CVE"
grep -Fq 'NO prueba que falte el parche' "$LPE" || fail "la ausencia de una CVE en changelog se presenta como prueba de falta de parche"
pass "el módulo LPE distingue la mitigación por user namespaces y el estado no concluyente del changelog"

# Legacy EL6 PAM uses pam_cracklib/pam_tally2 rather than modern pwquality/authselect/faillock.
grep -Fq 'pam_cracklib.so' "$PASSWORD" || fail "password-hardening no reconoce el control legacy pam_cracklib"
grep -Fq 'pam_tally2.so' "$PASSWORD" || fail "password-hardening no reconoce el control legacy pam_tally2"
grep -Fq '"99999")' "$PASSWORD" || fail "password-hardening sigue marcando PASS_MAX_DAYS=99999 como aging que requiere corrección"
pass "PAM/password checks distinguish EL6 legacy modules and preserve the operational 99999-day policy"

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
