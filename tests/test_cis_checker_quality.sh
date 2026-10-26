#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
CIS="$ROOT_DIR/cis-benchmark-check.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'CIS Red Hat Enterprise Linux 9 Benchmark' "$CIS" || fail "no hay catálogo de perfil RHEL 9"
grep -Fq 'CIS AlmaLinux OS 9 Benchmark' "$CIS" || fail "no hay catálogo de perfil AlmaLinux 9"
grep -Fq 'CIS Rocky Linux 10 Benchmark' "$CIS" || fail "no hay catálogo de perfil Rocky 10"
grep -Fq 'no se afirma cobertura total ni certificación CIS' "$CIS" || fail "el verificador no advierte que su cobertura es parcial"
grep -Fq 'referencias locales históricas; no se ha validado una equivalencia uno a uno' "$CIS" || fail "el reporte debe advertir que sus IDs no son un mapping oficial validado"
grep -Fq 'chronyd activo; fuente seleccionada' "$CIS" || fail "chrony aún tiene PASS por solo paquete instalado"
grep -Fq 'systemctl is-active --quiet aidecheck.timer' "$CIS" || fail "AIDE timer solo valida enabled"
grep -Fq 'ClientAliveCountMax entre 1 y 3 en EL8+' "$CIS" || fail "SSH idle timeout no valida límites ni versión OpenSSH"
grep -Fq 'authfail' "$CIS" || fail "PAM faillock no revisa authfail"
grep -Fq 'pam_pwquality activo; minlen=' "$CIS" || fail "pwquality debe validar PAM activo y valores explícitos"
grep -Fq 'pam_pwhistory.so' "$CIS" || fail "reuso debe validar módulos PAM activos"
grep -Fq 'fail_interval=900' "$CIS" || fail "lockout no verifica fail_interval/unlock_time"
grep -Fq 'crontab -u root -l' "$CIS" || fail "AIDE checker no acepta cron del instalador OrangeBox"
grep -Fq 'netstat' "$CIS" || fail "el chequeo MTA no tiene fallback para sistemas sin ss"
grep -Fq 'ENCRYPT_METHOD' "$CIS" || fail "hashing de contraseñas no se comprueba"
grep -Fq 'gpgcheck=1 activo en' "$CIS" || fail "gpgcheck debe comprobar la configuración activa y los overrides de repositorio"
grep -Fq 'disk_full_action' "$CIS" || fail "auditd debe comprobar las acciones al llenarse el disco"
grep -Fq 'check_audit_low_space_warning' "$CIS" || fail "falta comprobar umbrales y acciones cuando el espacio audit es bajo"
grep -Fq 'systemctl is-enabled rpcbind.socket' "$CIS" || fail "rpcbind debe comprobar servicio y socket"
grep -Fq 'max_log_file activo no existe o no es un entero positivo' "$CIS" || fail "max_log_file debe validar un valor activo numérico";


[ -f "$ROOT_DIR/cis-profile-versions.md" ] || fail "no existe el mapa versionado CIS"
grep -Fq '2026-10-26' "$ROOT_DIR/cis-profile-versions.md" || fail "el mapa CIS no declara fecha de revisión"
grep -Fq 'cis_grub_param_check audit 1 exact' "$CIS" || fail "audit=1 must check generated GRUB kernel entries"
grep -Fq 'runtime="yes"' "$CIS" || fail "audit=1 must verify the running kernel"
grep -Fq 'audit=1 está activo en /proc/cmdline' "$CIS" || fail "audit=1 PASS must include active kernel evidence"
grep -Fq 'cis_grub_param_check audit_backlog_limit 8192 min' "$CIS" || fail "audit backlog must check generated GRUB kernel entries"
grep -Fq 'auditctl -s' "$CIS" || fail "audit backlog must check active kernel status"
grep -Fq 'No se concede PASS sin ambas evidencias' "$CIS" || fail "audit backlog PASS must require active and persisted evidence"

grep -Fq 'cis_mount_is_exact()' "$CIS" || fail "los checks de filesystem deben exigir el mountpoint exacto"
grep -Fq 'cis_mount_option_enabled()' "$CIS" || fail "las opciones deben obtenerse del mountpoint exacto"
grep -Fq 'cis_file_has_kernel_argument /proc/cmdline "selinux=0"' "$CIS" || fail "SELinux boot check debe validar el kernel activo"
grep -Fq '/boot/loader/entries/*.conf' "$CIS" || fail "SELinux boot check debe inspeccionar entradas BLS"
grep -Fq 'cis_systemd_config_value systemd/coredump.conf' "$CIS" || fail "core dump checks deben evaluar la configuración efectiva"
grep -Fq 'systemd-analyze cat-config' "$CIS" || fail "core dump checks deben considerar drop-ins systemd"

if grep -Eq 'findmnt --kernel /(tmp|var|var/tmp|var/log|var/log/audit|home|dev/shm)' "$CIS"; then
  fail "quedan checks de montaje que pueden heredar el estado del filesystem padre"
fi

pass "perfil CIS versionado y falsos PASS principales corregidos"
