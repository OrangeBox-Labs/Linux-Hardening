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

[ -f "$ROOT_DIR/cis-profile-versions.md" ] || fail "no existe el mapa versionado CIS"
grep -Fq '2026-10-26' "$ROOT_DIR/cis-profile-versions.md" || fail "el mapa CIS no declara fecha de revisión"
pass "perfil CIS versionado y falsos PASS principales corregidos"
