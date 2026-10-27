#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
KERNEL="$ROOT_DIR/kernel-hardening.sh"
AUDITD="$ROOT_DIR/auditd-hardening.sh"
GRUB="$ROOT_DIR/grub-hardening.sh"
SELINUX="$ROOT_DIR/selinux-secure-setup.sh"
fail(){ echo "[FAIL] $*" >&2; exit 1; }
pass(){ echo "[PASS] $*"; }
grep -Fq '[AUTO-YES] use_pty aprobado por --fix' "$CORE" || fail "sudo use_pty debe aceptar --fix automático"
grep -Fq '¿Deseas habilitar Defaults use_pty en este servidor?' "$CORE" || fail "modo interactivo pierde el prompt de use_pty"
grep -Fq 'kernel_param_effect()' "$GRUB" || fail "GRUB debe describir el efecto de parámetros"
grep -Fq 'grub2-script-check' "$GRUB" || fail "GRUB debe validar el archivo cuando la herramienta exista"
! grep -Eiq 'selinux=0|enforcing=0|selinux' "$GRUB" || fail "GRUB no debe inspeccionar SELinux"
grep -Fq 'configure_auditd_param "max_log_file_action" "ROTATE"' "$AUDITD" || fail "auditd debe rotar logs"
grep -Fq 'configure_auditd_param "space_left_action" "SYSLOG"' "$AUDITD" || fail "auditd debe registrar aviso en SYSLOG"
grep -Fq 'configure_auditd_param "admin_space_left_action" "SUSPEND"' "$AUDITD" || fail "auditd no debe detener el host por espacio"
! grep -Eq 'MAC-policy|/etc/selinux' "$AUDITD" || fail "auditd no debe incluir reglas SELinux"
grep -Fq 'confirm_change()' "$SELINUX" || fail "la utilidad SELinux independiente debe confirmar cambios"
grep -Fq 'sysctl_safe_apply_bpf_policy' "$CORE" || fail "el baseline debe preservar la política BPF 1/2"
grep -Fq 'sysctl_safe_apply_bpf_policy' "$KERNEL" || fail "kernel-hardening debe preservar la política BPF 1/2"
pass "políticas de auditd, GRUB, SELinux, sudo y BPF verificadas"
