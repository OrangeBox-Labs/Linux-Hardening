#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
NETWORK="$ROOT_DIR/network-hardening.sh"
AUDITD="$ROOT_DIR/auditd-hardening.sh"
RSYSLOG="$ROOT_DIR/rsyslog-hardening.sh"
BASH_HARDENING="$ROOT_DIR/bash-hardening.sh"
CRON="$ROOT_DIR/cron-hardening.sh"
GRUB="$ROOT_DIR/grub-hardening.sh"
KERNEL="$ROOT_DIR/kernel-hardening.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

if grep -Eq '(^|[[:space:]])rmmod[[:space:]]+"?\$module' "$NETWORK"; then
  fail "network-hardening no debe descargar módulos de kernel en caliente"
fi
grep -Fq 'no se descargará en caliente' "$NETWORK" || fail "la confirmación de módulo no explica que no se descarga en caliente"
grep -Fq 'if ! make_backup; then' "$NETWORK" || fail "network-hardening puede aplicar cambios si falla el backup"
grep -Fq 'chmod 700 "$BACKUP_DIR"' "$NETWORK" || fail "backup de red no restringe permisos"
grep -Fq 'if ! make_backup; then' "$AUDITD" || fail "auditd puede aplicar cambios si falla el backup"
grep -Fq 'chmod 700 "$BACKUP_DIR"' "$AUDITD" || fail "backup auditd no restringe permisos"
grep -Fq 'if ! make_backup; then' "$RSYSLOG" || fail "rsyslog puede aplicar cambios si falla el backup"
grep -Fq 'chmod 700 "$BACKUP_DIR"' "$RSYSLOG" || fail "backup logging no restringe permisos"
grep -Fq 'if ! make_backup; then' "$BASH_HARDENING" || fail "Bash hardening puede aplicar cambios si falla el backup"
grep -Fq '"$PROFILE_D" "$PROFILE_MOTD" "$ALIASES_D"' "$BASH_HARDENING" || fail "Bash no incluye el MOTD dinámico en el backup previo"
grep -Fq 'OB_PROMPT_COMMAND="${OB_PROMPT_COMMAND//history -a; history -c; history -r;/}"' "$BASH_HARDENING" || fail "el perfil Bash no elimina el hook heredado que vacía el historial"
grep -Fq 'ORANGEBOX HISTORY PROMPT MIGRATION V1 BEGIN' "$BASH_HARDENING" || fail "root .bashrc no migra sesiones con PROMPT_COMMAND heredado"
grep -Fq 'history -a' "$BASH_HARDENING" || fail "Bash hardening no garantiza el guardado incremental del historial"
grep -Fq 'No se pudo respaldar $file' "$BASH_HARDENING" || fail "Bash no valida las copias individuales del backup"
grep -Fq 'if ! make_backup; then' "$CRON" || fail "cron/at puede aplicar cambios si falla el backup"
grep -Fq 'No se pudo respaldar $file' "$CRON" || fail "cron/at no comprueba las copias individuales"
grep -Fq 'if ! make_backup; then' "$GRUB" || fail "GRUB puede aplicar cambios si falla el backup"
grep -Fq 'No se pudo respaldar $file' "$GRUB" || fail "GRUB no comprueba las copias individuales"
grep -Fq 'KERNEL_BACKUP_DIR=' "$KERNEL" || fail "kernel hardening no define un backup de ejecución estable"
grep -Fq 'if ! cp -p "$source" "$backup"' "$KERNEL" || fail "kernel hardening no comprueba la copia de seguridad antes del cambio"
grep -Fq '[ -e "$backup" ] && return 0' "$KERNEL" || fail "kernel hardening puede sobrescribir la primera copia previa al cambio"
pass "network/auditd/rsyslog/Bash/cron/GRUB/kernel abortan si falla su respaldo; kernel conserva la copia original"
