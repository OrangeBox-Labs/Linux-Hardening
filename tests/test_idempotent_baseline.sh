#!/usr/bin/env bash
# Regression guards for per-control idempotence, MOTD branding, and shell timeout.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
SYSCTL="$ROOT_DIR/lib/sysctl-safe.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Kernel/SYN flood must rely on per-parameter sysctl checks, not a blanket module prompt.
grep -Fq '      kernel)' "$CORE" || fail "kernel no tiene tratamiento de confirmación por parámetro"
grep -Fq '      synflood)' "$CORE" || fail "SYN flood no tiene tratamiento de confirmación por parámetro"
grep -Fq 'solo los que falten o difieran solicitarán confirmación' "$CORE" || fail "falta la política de confirmación por parámetro"
grep -Fq 'sysctl_safe_apply ' "$CORE" || fail "baseline dejó de usar el helper seguro de sysctl"

# sudo owns its specific prompt and is explicitly exempt from a redundant generic prompt.
grep -Fq '      sudo)' "$CORE" || fail "sudo no tiene una rama de confirmación específica"
grep -Fq 'solo su control específico puede solicitar confirmación' "$CORE" || fail "sudo aún depende de confirmación genérica"
grep -Fq 'cPanel detectado: por política OrangeBox no se activa use_pty' "$CORE" || fail "se perdió la exclusión de use_pty en cPanel"

# Journald should not ask/restart when already persistent; unavailable config stays read-only.
grep -Fq 'rsyslog_state_status()' "$CORE" || fail "falta preflight de journald"
grep -Fq 'Journald ya tiene Storage=persistent y /var/log/journal' "$CORE" || fail "falta omitir la confirmación de journald conforme"
grep -Fq 'journal_status=$?' "$CORE" || fail "el resultado del preflight de journald no se utiliza"
grep -Fq 'if ! confirm_risky_change "$name"; then' "$CORE" || fail "se perdió confirmación cuando rsyslog requiere cambios"

# Persistence-only changes are pending changes and must receive their own consent.
grep -Fq 'falta persistencia' "$SYSCTL" || fail "sysctl no distingue runtime correcto de persistencia ausente"
grep -Fq '¿Confirmas persistir %s=%s en %s? [s/N]' "$SYSCTL" || fail "no hay confirmación para cambios solo de persistencia"

# Session-aware MOTD: /etc/motd stays empty to avoid duplicate output.
MOTD_LIB="$ROOT_DIR/lib/orangebox-motd.sh"
[ -r "$MOTD_LIB" ] || fail "falta la librería de MOTD dinámico"
grep -Fq 'orangebox_motd_ensure_figlet "$AUTO_FIX"' "$CORE" || fail "el módulo no verifica/instala FIGlet según el modo"
grep -Fq 'orangebox_motd_write_profile "$session_motd_tmp"' "$CORE" || fail "el módulo no genera el perfil dinámico"
grep -Fq ': > "$motd_tmp"' "$CORE" || fail "/etc/motd estático debe quedar vacío para evitar duplicados"
grep -Fq 'figlet -f small OrangeBox' "$MOTD_LIB" || fail "falta FIGlet con la fuente small"
grep -Fq 'yum -y install figlet' "$MOTD_LIB" || fail "falta el intento de instalación con yum"
grep -Fq 'dnf -y install figlet' "$MOTD_LIB" || fail "falta el intento de instalación con dnf"
grep -Fq 'SSH_CONNECTION' "$MOTD_LIB" || fail "el MOTD no detecta la IP local de la sesión SSH"
grep -Fq '/proc/uptime' "$MOTD_LIB" || fail "uptime no es compatible con sistemas antiguos"
grep -Fq '/proc/loadavg' "$MOTD_LIB" || fail "el MOTD no incluye load average"
grep -Fq 'IP interna:' "$MOTD_LIB" || fail "el MOTD no rotula la IP interna"
if grep -Eq 'IP remota:|OB_REMOTE_IP|AVISO DE SEGURIDAD|Todas las conexiones y los comandos ejecutados quedan|reportado a las autoridades' "$MOTD_LIB"; then
  fail "el MOTD de shell todavía contiene la IP remota o el aviso pre-login"
fi
grep -Fq 'SISTEMA DE ACCESO RESTRINGIDO' "$CORE" || fail "falta el título del banner previo a autenticación"
grep -Fq 'Todas las conexiones y los comandos ejecutados quedan' "$CORE" || fail "el aviso de auditoría no está en el banner pre-login"
grep -Fq 'reportado a las autoridades competentes.' "$CORE" || fail "falta el aviso de reporte de actividad no autorizada"
grep -Fq 'IP remota' "$CORE" && fail "la IP remota no debe mostrarse en el MOTD de shell"
login_banner_tmp="$(mktemp)"
trap 'rm -f "$login_banner_tmp"' EXIT
awk '
  index($0, "cat > \\"$login_tmp\\" <<\\047ORANGEBOX_LOGIN_BANNER\\047") { in_banner=1; next }
  in_banner && $0 == "ORANGEBOX_LOGIN_BANNER" { exit }
  in_banner { print }
' "$CORE" > "$login_banner_tmp"
[ -s "$login_banner_tmp" ] || fail "no se pudo extraer el banner pre-login"
if grep -Eq '\\| \\(_\\) \\||ORANGEBOX_ASCII|figlet' "$login_banner_tmp"; then
  fail "el banner pre-login no debe repetir el logotipo ASCII/FIGlet"
fi

# Idle timeout is two minutes for interactive non-root sessions; root clears inherited TMOUT.
grep -Fq 'TMOUT=120' "$CORE" || fail "falta timeout interactivo de 120 segundos"
grep -Fq 'unset TMOUT 2>/dev/null || true' "$CORE" || fail "la shell root no elimina TMOUT heredado"
grep -Fq 'readonly TMOUT' "$CORE" || fail "TMOUT no está protegido contra cambios por el usuario"
grep -Fq 'solo aplica a shells interactivos' "$CORE" || fail "no se limita el resto del perfil a shells interactivos"
profile_tmp="$(mktemp)"
motd_profile_tmp="$(mktemp)"
trap 'rm -f "$profile_tmp" "$motd_profile_tmp" "$login_banner_tmp"' EXIT
awk '
  index($0, "cat >") && index($0, "ORANGEBOX_BASH") { in_profile=1; next }
  in_profile && $0 == "ORANGEBOX_BASH" { exit }
  in_profile { print }
' "$CORE" > "$profile_tmp"
[ -s "$profile_tmp" ] || fail "no se pudo extraer el perfil Bash administrado"
bash -n "$profile_tmp" || fail "el perfil Bash generado tiene errores de sintaxis"

# Generate and validate the dynamic MOTD without touching system files or installing packages.
# shellcheck source=lib/orangebox-motd.sh
source "$MOTD_LIB"
orangebox_motd_write_profile "$motd_profile_tmp" || fail "no se pudo generar el perfil MOTD"
[ -s "$motd_profile_tmp" ] || fail "el perfil MOTD dinámico está vacío"
sh -n "$motd_profile_tmp" || fail "el perfil MOTD no es compatible con sintaxis sh"
grep -Fq 'SSH_CONNECTION' "$motd_profile_tmp" || fail "el perfil MOTD generado no muestra la IP remota"
grep -Fq '/proc/uptime' "$motd_profile_tmp" || fail "el perfil MOTD generado no calcula uptime"
grep -Fq '/proc/loadavg' "$motd_profile_tmp" || fail "el perfil MOTD generado no muestra load"

pass "confirmaciones idempotentes, MOTD de marca y TMOUT=120 exclusivo para sesiones interactivas no-root"
