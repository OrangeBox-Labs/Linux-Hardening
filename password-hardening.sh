#!/bin/bash
# OrangeBox Password Hardening - Safe Enterprise Baseline
# Version 2.0.0
# IMPORTANT: passwords never expire under the OrangeBox baseline.
# IMPORTANT: PAM stacks are NEVER edited with sed. authselect-managed systems are never bypassed.
# IMPORTANT: faillock is audited only; automatic lockout insertion can lock administrators out.
# IMPORTANT: su remains restricted to wheel, but the change is applied only when wheel has a non-root member.

set -u
VERSION=2.0.0
AUTO_FIX=false
FIXED=0
WARNINGS=0
BACKUP_DIR="/root/password-backup-$(date +%Y%m%d-%H%M%S)"
PWQUALITY_CONF=/etc/security/pwquality.conf
LOGIN_DEFS=/etc/login.defs
SU_PAM=/etc/pam.d/su

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok(){ echo -e "$GREEN[OK]$NC $*"; }
warn(){ WARNINGS=$((WARNINGS+1)); echo -e "$YELLOW[WARN]$NC $*"; }
bad(){ WARNINGS=$((WARNINGS+1)); echo -e "$RED[FAIL]$NC $*"; }
die(){ echo -e "$RED[ERROR]$NC $*"; exit 1; }

require_root(){ [ "$EUID" -eq 0 ] || die "Debe ejecutarse como root."; }
backup_once(){ local src="$1"; [ -e "$src" ] || return 0; mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"; cp -a "$src" "$BACKUP_DIR/$(basename "$src").before"; }

set_conf_value(){
  local file="$1" key="$2" value="$3" current
  current=$(awk -v k="$key" '$1==k{v=$2} END{print v}' "$file" 2>/dev/null || true)
  if [ "$current" = "$value" ]; then ok "$file: $key=$value"; return 0; fi
  warn "$file: $key actual=${current:-no configurado}, recomendado=$value"
  $AUTO_FIX || return 0
  backup_once "$file"
  if grep -Eq "^[[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -ri "s|^[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$file"
  else
    printf '%s %s\n' "$key" "$value" >> "$file"
  fi
  FIXED=$((FIXED+1)); ok "$file actualizado: $key=$value"
}

pwquality_module(){
  echo -e "\n$BLUE### PASSWORD QUALITY ###$NC"
  [ -f "$PWQUALITY_CONF" ] || { warn "$PWQUALITY_CONF no existe; no se crea PAM a ciegas"; return; }
  # These settings affect password creation/change, not existing login credentials.
  set_conf_value "$PWQUALITY_CONF" minlen 14
  set_conf_value "$PWQUALITY_CONF" minclass 4
  set_conf_value "$PWQUALITY_CONF" difok 4
  set_conf_value "$PWQUALITY_CONF" dictcheck 1
  set_conf_value "$PWQUALITY_CONF" usercheck 1
  set_conf_value "$PWQUALITY_CONF" maxrepeat 3
  set_conf_value "$PWQUALITY_CONF" maxsequence 3
  warn "No se agrega pam_pwquality.so a password-auth/system-auth: RHEL recomienda gestionar PAM mediante authselect y la edición manual puede romper autenticación."
}

password_aging_module(){
  echo -e "\n$BLUE### PASSWORD AGING ###$NC"
  [ -f "$LOGIN_DEFS" ] || { warn "$LOGIN_DEFS no existe"; return; }
  # -1 disables the maximum-age restriction in login.defs. This affects defaults for new accounts.
  set_conf_value "$LOGIN_DEFS" PASS_MAX_DAYS -1
  set_conf_value "$LOGIN_DEFS" PASS_MIN_DAYS 0
  set_conf_value "$LOGIN_DEFS" PASS_WARN_AGE -1
  warn "IMPORTANTE: login.defs solo define defaults; no cambia el aging ya grabado en cuentas existentes. Se auditan abajo y NO se ejecuta chage masivo automáticamente."

  if command -v chage >/dev/null 2>&1; then
    local found=0 line user max
    while IFS=: read -r user _ uid _ _ home shell; do
      [ "$uid" -ge 1000 ] 2>/dev/null || continue
      case "$shell" in */nologin|*/false) continue;; esac
      max=$(chage -l "$user" 2>/dev/null | awk -F: '/Maximum number of days between password change/{gsub(/^[[:space:]]+/,"",$2); print $2}')
      case "$max" in "Never"|"-1") ;; *) echo "  [AUDIT] $user: password max age=$max"; found=1;; esac
    done < /etc/passwd
    [ "$found" -eq 0 ] && ok "No se detectaron cuentas locales humanas con expiración reportable" || warn "Hay cuentas existentes con aging; no se modifican automáticamente para evitar afectar cuentas operativas/cPanel"
  fi
}

pam_audit_module(){
  echo -e "\n$BLUE### PAM / AUTHSELECT ###$NC"
  if command -v authselect >/dev/null 2>&1; then
    if authselect current >/dev/null 2>&1; then
      ok "authselect activo; PAM se considera administrado por authselect"
      authselect current 2>/dev/null | sed 's/^/  /'
    else
      warn "authselect instalado pero 'authselect current' falló"
    fi
  else
    warn "authselect no disponible; PAM requiere revisión específica de la distribución"
  fi

  local f
  for f in /etc/pam.d/system-auth /etc/pam.d/password-auth; do
    [ -f "$f" ] || continue
    grep -q 'pam_faillock.so' "$f" && ok "$f: pam_faillock ya presente" || warn "$f: pam_faillock no configurado"
  done
  warn "No se inserta pam_faillock automáticamente. El orden de PAM es crítico y una modificación incorrecta puede bloquear todos los accesos."
}

su_wheel_module(){
  echo -e "\n$BLUE### SU -> WHEEL ###$NC"
  getent group wheel >/dev/null 2>&1 || { warn "Grupo wheel no existe; no se toca /etc/pam.d/su"; return; }
  local members; members=$(getent group wheel | awk -F: '{print $4}')
  if [ -z "$members" ]; then
    warn "wheel no tiene miembros no-root; NO se activa pam_wheel para evitar dejar sin vía de escalamiento a administradores"
    return
  fi
  if grep -Eq '^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_wheel.so([[:space:]]|$)' "$SU_PAM" 2>/dev/null; then
    ok "su ya restringido a wheel"
  elif [ "$AUTO_FIX" = true ] && [ -f "$SU_PAM" ]; then
    backup_once "$SU_PAM"
    printf '\n# OrangeBox: only wheel members may use su\nauth required pam_wheel.so use_uid\n' >> "$SU_PAM"
    ok "su restringido a wheel"; FIXED=$((FIXED+1))
  else
    warn "su no está restringido a wheel"
  fi
  echo "  wheel members: $members"
}

file_permissions_module(){
  echo -e "\n$BLUE### FILE PERMISSIONS ###$NC"
  for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    [ -f "$f" ] || continue
    local p; p=$(stat -c %a "$f" 2>/dev/null || true)
    case "$f" in
      /etc/passwd|/etc/group) [ "$p" -le 644 ] 2>/dev/null && ok "$f=$p" || warn "$f=$p";;
      *) [ "$p" = 600 ] || [ "$p" = 640 ] || [ "$p" = 000 ] && ok "$f=$p" || warn "$f=$p; no se fuerza a 000 porque puede romper herramientas/backup";;
    esac
  done
}

encrypt_method_module(){
  echo -e "\n$BLUE### PASSWORD HASHING ###$NC"
  local current; current=$(awk '$1=="ENCRYPT_METHOD"{v=$2} END{print v}' "$LOGIN_DEFS" 2>/dev/null || true)
  if [ "$current" = SHA512 ]; then ok "ENCRYPT_METHOD=SHA512"; elif [ -z "$current" ]; then
    warn "ENCRYPT_METHOD no configurado; SHA-512 es preferible para nuevos hashes"
    $AUTO_FIX && { backup_once "$LOGIN_DEFS"; printf '\nENCRYPT_METHOD SHA512\n' >> "$LOGIN_DEFS"; FIXED=$((FIXED+1)); }
  else warn "ENCRYPT_METHOD=$current; no se modifica automáticamente si la plataforma/autenticación externa puede depender de otra configuración"; fi
  warn "No se modifica pam_unix.so mediante sed y no se reescribe system-auth/password-auth."
}

main(){
  require_root
  while [ $# -gt 0 ]; do
    case "$1" in --fix|-f) AUTO_FIX=true;; --help|-h) echo "Uso: $0 [--fix]"; exit 0;; *) die "Argumento desconocido: $1";; esac
    shift
  done
  $AUTO_FIX && echo -e "$YELLOW[WARN] MODO FIX: solo cambios operativamente seguros; PAM authselect/lockout queda en auditoría.$NC" || echo -e "$GREEN[OK] MODO AUDITORÍA: sin cambios$NC"
  if $AUTO_FIX; then mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"; fi
  pwquality_module
  password_aging_module
  pam_audit_module
  su_wheel_module
  file_permissions_module
  encrypt_method_module
  echo -e "\n$GREEN============================================================$NC"
  echo -e "$GREEN OrangeBox Password Hardening $VERSION - FIN $NC"
  echo "Correcciones: $FIXED"; echo "Advertencias: $WARNINGS"
  $AUTO_FIX && echo "Backup: $BACKUP_DIR"
  echo -e "$GREEN============================================================$NC"
}
main "$@"
