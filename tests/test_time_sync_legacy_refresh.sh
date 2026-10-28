#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
TIME_SYNC="$ROOT_DIR/configure-time-sync.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'NTP_REFRESH_CRON="/etc/cron.d/orangebox-ntp-refresh"' "$TIME_SYNC" ||
  fail "no se define el archivo cron dedicado para EL6"
grep -Fq 'ntpd_restart_job_source()' "$TIME_SYNC" ||
  fail "no se valida si ya existe una tarea cron para reiniciar ntpd"
grep -Fq 'crontab -l -u root' "$TIME_SYNC" ||
  fail "no se comprueba el crontab de root"
grep -Fq 'if [ "$os_major" != "6" ] || ! rpm -q ntp' "$TIME_SYNC" ||
  fail "el refresco programado no está limitado a EL6 con el paquete ntp"
grep -Fq '17 */6 * * * root if /sbin/service ntpd restart' "$TIME_SYNC" ||
  fail "no se programa el reinicio de ntpd cada seis horas"
grep -Fq 'configure_legacy_ntp_refresh' "$TIME_SYNC" ||
  fail "no se invoca el control de refresco desde el flujo principal"
grep -Fq 'if [ "$1" = "--refresh-only" ]; then' "$TIME_SYNC" ||
  fail "falta el modo aislado que instala solo el refresco cron"
grep -Fq 'No se detectó un reinicio periódico de ntpd en cron' "$TIME_SYNC" ||
  fail "el modo de auditoría no alerta cuando falta la tarea"

pass "EL6 valida tareas existentes y permite instalar solo el refresco con --refresh-only"
