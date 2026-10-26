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

# The pre-authentication banner owns the warning; the shell MOTD owns the unified session display.
MOTD_LIB="$ROOT_DIR/lib/orangebox-motd.sh"
[ -r "$MOTD_LIB" ] || fail "falta la librería del banner OrangeBox"
grep -Fq 'orangebox_motd_ensure_figlet "$AUTO_FIX"' "$CORE" || fail "el módulo no verifica/instala FIGlet según el modo"
grep -Fq 'orangebox_motd_write_login_banner "$login_tmp"' "$CORE" || fail "el logo/aviso no se genera para el banner pre-login"
grep -Fq 'orangebox_motd_write_profile "$session_motd_tmp"' "$CORE" || fail "el módulo no genera el perfil de métricas"
grep -Fq ': > "$motd_tmp"' "$CORE" || fail "/etc/motd estático debe quedar vacío para evitar duplicados"
grep -Fq 'figlet -f small OrangeBox' "$MOTD_LIB" || fail "falta FIGlet con la fuente small"
grep -Fq 'yum -y install figlet' "$MOTD_LIB" || fail "falta el intento de instalación con yum"
grep -Fq 'dnf -y install figlet' "$MOTD_LIB" || fail "falta el intento de instalación con dnf"

login_banner_tmp="$(mktemp)"
motd_profile_tmp="$(mktemp)"
trap 'rm -f "$login_banner_tmp" "$motd_profile_tmp"' EXIT
# Force the built-in ASCII fallback so the banner is tested even on runners with FIGlet installed.
# shellcheck source=lib/orangebox-motd.sh
source "$MOTD_LIB"
orangebox_motd_write_login_banner "$login_banner_tmp" true || fail "no se pudo generar el banner pre-login"
[ -s "$login_banner_tmp" ] || fail "el banner pre-login quedó vacío"
grep -Fq 'SISTEMA DE ACCESO RESTRINGIDO' "$login_banner_tmp" || fail "falta título en el banner pre-login"
grep -Fq 'Todas las conexiones y los comandos ejecutados quedan' "$login_banner_tmp" || fail "el aviso de auditoría no está en el banner pre-login"
grep -Fq 'reportado a las autoridades competentes.' "$login_banner_tmp" || fail "falta el aviso sobre actividades no autorizadas"
grep -Fq "| | | | '__/ _|" "$login_banner_tmp" || fail "falta el logo ASCII de fallback en el banner pre-login"
awk '
  length($0) == 79 && $0 ~ /^\*+$/ { dividers++ }
  /SISTEMA DE ACCESO RESTRINGIDO/ {
    expected = int((79 - length("SISTEMA DE ACCESO RESTRINGIDO")) / 2) + 1
    if (index($0, "SISTEMA DE ACCESO RESTRINGIDO") != expected) exit 1
    title_ok = 1
  }
  /www.orangebox.cl/ {
    expected = int((79 - length("www.orangebox.cl")) / 2) + 1
    if (index($0, "www.orangebox.cl") != expected) exit 1
    url_ok = 1
  }
  /    Todas las conexiones/ { if (substr($0, 1, 4) != "    ") exit 1; body_ok = 1 }
  END { if (dividers != 3 || !title_ok || !url_ok || !body_ok) exit 1 }
' "$login_banner_tmp" || fail "el banner pre-login debe tener logo/título centrados y el texto con sangría uniforme"

orangebox_motd_write_profile "$motd_profile_tmp" || fail "no se pudo generar el perfil con métricas"
[ -s "$motd_profile_tmp" ] || fail "el perfil de métricas está vacío"
sh -n "$motd_profile_tmp" || fail "el perfil dinámico no es compatible con sintaxis sh"
grep -Fq 'IP interna:' "$motd_profile_tmp" || fail "el perfil no muestra la IP interna"
grep -Fq 'Uptime:' "$motd_profile_tmp" || fail "el perfil no muestra uptime"
grep -Fq '"Load:"' "$motd_profile_tmp" || fail "el perfil no muestra Load con etiqueta limpia"
if grep -Fq 'Load (1/5/15m):' "$motd_profile_tmp"; then
  fail "la etiqueta Load no debe mostrar intervalos internos"
fi
grep -Fq 'IP del cliente:' "$motd_profile_tmp" || fail "el perfil no muestra la IP del cliente"
grep -Fq '"Usuario:"' "$motd_profile_tmp" || fail "el perfil no muestra al usuario efectivo"
grep -Fq 'Fecha/hora:' "$motd_profile_tmp" || fail "el perfil no muestra fecha y hora"
[ "$(grep -Fc 'Fecha/hora:' "$motd_profile_tmp")" -eq 1 ] || fail "la fecha/hora debe aparecer una sola vez"
grep -Fq "date '+%Y-%m-%d %H:%M:%S %Z'" "$motd_profile_tmp" || fail "falta el formato de fecha/hora"
grep -Fq 'figlet -f small OrangeBox' "$motd_profile_tmp" || fail "el logo FIGlet no aparece primero en el MOTD de shell"
grep -Fq 'ORANGEBOX_ASCII' "$motd_profile_tmp" || fail "falta el fallback ASCII del logo de shell"
if grep -Eq 'AVISO DE SEGURIDAD|SISTEMA DE ACCESO RESTRINGIDO|Todas las conexiones y los comandos ejecutados quedan|tput' "$motd_profile_tmp"; then
  fail "el MOTD de shell no debe duplicar el aviso pre-login ni depender de tput para colorear"
fi
grep -Fq "OB_CYAN=\$(printf" "$motd_profile_tmp" || fail "el MOTD no define la paleta ANSI común"
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

pass "banner pre-login, logo FIGlet y ficha de sesión unificada, etiqueta Load limpia, fecha única y TMOUT no-root"
