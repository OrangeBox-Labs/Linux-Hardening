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
info(){ echo -e "$BLUE[INFO]$NC $*"; }
warn(){ WARNINGS=$((WARNINGS+1)); echo -e "$YELLOW[WARN]$NC $*"; }
bad(){ WARNINGS=$((WARNINGS+1)); echo -e "$RED[FAIL]$NC $*"; }
die(){ echo -e "$RED[ERROR]$NC $*"; exit 1; }

require_root(){ [ "$EUID" -eq 0 ] || die "Debe ejecutarse como root."; }

get_el_major(){
  local major=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    major="${VERSION_ID%%.*}"
  elif [ -r /etc/redhat-release ]; then
    major="$(sed -n 's/.*release \([0-9][0-9]*\).*/\1/p' /etc/redhat-release | head -1)"
  fi
  printf '%s\n' "$major"
}
backup_once(){
  local src="$1" backup=""
  [ -e "$src" ] || return 0
  [ ! -L "$src" ] || { echo "[ERROR] $src es un enlace simbólico; no se respalda ni modifica automáticamente."; return 1; }
  backup="$BACKUP_DIR/$(basename "$src").before"
  [ -e "$backup" ] && return 0
  mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR" && cp -a "$src" "$backup"
}

password_parameter_description() {
  case "$1" in
    minlen) echo "Fija la longitud mínima de una contraseña nueva. Puede rechazar cambios de contraseña demasiado cortos; no modifica credenciales existentes." ;;
    minclass) echo "Exige caracteres de distintas clases (mayúsculas, minúsculas, dígitos, símbolos). Puede rechazar frases largas que no cumplan las clases requeridas." ;;
    difok) echo "Exige diferencias respecto de la contraseña anterior; un valor alto puede dificultar rotaciones legítimas." ;;
    dictcheck) echo "Activa el control contra palabras comunes/de diccionario; puede rechazar frases de contraseña predecibles." ;;
    usercheck) echo "Evita contraseñas que contengan datos del nombre del usuario; puede rechazar contraseñas que incluyan el identificador del usuario." ;;
    maxrepeat) echo "Limita caracteres idénticos consecutivos; puede rechazar contraseñas con repeticiones largas." ;;
    maxsequence) echo "Limita secuencias de caracteres consecutivos; puede rechazar patrones como abc o 123." ;;
    PASS_MIN_DAYS) echo "Define el mínimo de días entre cambios para cuentas nuevas. 1 reduce la rotación repetitiva, pero puede impedir un cambio inmediato legítimo." ;;
    PASS_WARN_AGE) echo "Define los días de aviso antes de la expiración para nuevas cuentas. No cambia la expiración de las cuentas existentes." ;;
    ENCRYPT_METHOD) echo "Define el algoritmo por defecto para nuevos hashes de contraseña; no convierte los hashes existentes y una política incompatible puede afectar herramientas de autenticación antiguas." ;;
    *) echo "Modifica un parámetro de política de contraseña; valida su efecto antes de aplicarlo." ;;
  esac
}

confirm_password_setting() {
  if [ "${ORANGEBOX_ASSUME_YES:-0}" = "1" ]; then printf "[AUTO-YES] %s=%s\n" "$2" "$4"; return 0; fi
  local file="$1" key="$2" current="$3" value="$4" effect="$5" answer=""
  printf '\n[WARN] Cambio de política de autenticación: %s -> %s=%s\n' "$file" "$key" "$value"
  printf 'Valor actual: %s\n' "${current:-no definido}"
  printf 'Qué hace/riesgo: %s\n' "$effect"
  printf '%s' "¿Aplicar este parámetro? [s/N]: "
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    printf '\n[WARN] No hay terminal interactiva; se omite el cambio por seguridad.\n'
    return 1
  fi
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in s|S|si|SI|sí|Sí|SÍ) return 0 ;; *) printf '[INFO] Se conserva el valor actual de %s.\n' "$key"; return 1 ;; esac
}

set_conf_value(){
  local file="$1" key="$2" value="$3" current="" effect="" style="space" tmp="" mode="644"
  [ ! -L "$file" ] || { warn "$file es un enlace simbólico; no se modifica."; return 1; }
  current="$(awk -v k="$key" '
    function trim(s){sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s}
    /^[ \t]*#/ || /^[ \t]*$/ {next}
    {
      line=$0; sub(/[ \t]+#.*/, "", line)
      eq=index(line, "=")
      if(eq){lhs=trim(substr(line,1,eq-1)); rhs=trim(substr(line,eq+1))}
      else {split(line, a, /[ \t]+/); lhs=a[1]; rhs=a[2]}
      if(lhs==k) v=rhs
    }
    END{print v}
  ' "$file" 2>/dev/null || true)"
  if [ "$current" = "$value" ]; then ok "$file: $key=$value"; return 0; fi
  effect="$(password_parameter_description "$key")"
  echo -e "$YELLOW[WARN]$NC $file: $key actual=$current, recomendado=$value"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS+1)); return 0; fi
  if ! confirm_password_setting "$file" "$key" "$current" "$value" "$effect"; then WARNINGS=$((WARNINGS+1)); return 0; fi
  if [ -e "$file" ]; then
    backup_once "$file" || { warn "No se pudo respaldar $file; no se modificó."; return 1; }
    mode="$(stat -c %a "$file" 2>/dev/null || echo 644)"
  else
    [ -d "$(dirname "$file")" ] || mkdir -p "$(dirname "$file")" || { warn "No se pudo crear el directorio de $file."; return 1; }
    mode=644
  fi
  [ "$file" = "$PWQUALITY_CONF" ] && style="equals"
  tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").orangebox.XXXXXX")" || { warn "No se pudo crear temporal para $file."; return 1; }
  if [ -f "$file" ]; then
    awk -v k="$key" -v v="$value" -v style="$style" '
      function trim(s){sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s}
      function out(){if(style=="equals") print k " = " v; else print k " " v}
      /^[ \t]*#/ {print; next}
      /^[ \t]*$/ {print; next}
      {
        original=$0; line=$0; sub(/[ \t]+#.*/, "", line); eq=index(line, "=")
        if(eq){lhs=trim(substr(line,1,eq-1))}
        else {split(line, a, /[ \t]+/); lhs=a[1]}
        if(lhs==k){if(!written){out(); written=1}; next}
        print original
      }
      END{if(!written) out()}
    ' "$file" > "$tmp" || { rm -f "$tmp"; warn "No se pudo preparar $file."; return 1; }
  else
    if [ "$style" = "equals" ]; then printf '%s = %s\n' "$key" "$value" > "$tmp"
    else printf '%s %s\n' "$key" "$value" > "$tmp"; fi
  fi
  chmod "$mode" "$tmp" || { rm -f "$tmp"; warn "No se pudo ajustar permisos temporales para $file."; return 1; }
  chown root:root "$tmp" 2>/dev/null || true
  if ! mv "$tmp" "$file"; then rm -f "$tmp"; warn "No se pudo instalar $file."; return 1; fi
  FIXED=$((FIXED+1)); ok "$file actualizado: $key=$value"
}

pwquality_module(){
  echo -e "\n$BLUE### PASSWORD QUALITY ###$NC"
  local os_major pam_active=false f active_line=""
  os_major="$(get_el_major)"
  if [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -le 6 ]; then
    if grep -Eq '^[[:space:]]*password[[:space:]]+[^#].*pam_cracklib\\.so' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null; then
      info "EL6 usa pam_cracklib: se audita el mecanismo legacy, no se crea una configuración pwquality que no se utilizaría."
    else
      warn "No se pudo confirmar el módulo legacy de calidad de contraseña en PAM."
    fi
    return
  fi

  for f in /etc/pam.d/system-auth /etc/pam.d/password-auth; do
    [ -r "$f" ] || continue
    active_line="$(grep -E '^[[:space:]]*password[[:space:]]+[^#].*pam_pwquality\\.so' "$f" 2>/dev/null || true)"
    [ -n "$active_line" ] && pam_active=true
  done
  if ! $pam_active; then
    warn "No hay una regla password activa pam_pwquality.so. Configurar pwquality.conf sin activar el módulo PAM no endurecería contraseñas efectivamente."
    info "PAM queda en auditoría: active el control mediante authselect o el mecanismo soportado tras validar recuperación; no se edita la pila PAM a ciegas."
    return
  fi

  if [ ! -f "$PWQUALITY_CONF" ]; then
    warn "$PWQUALITY_CONF no existe; se creará solamente si se confirma cada parámetro solicitado."
  fi
  # These settings affect password creation/change, not existing login credentials.
  set_conf_value "$PWQUALITY_CONF" minlen 14
  set_conf_value "$PWQUALITY_CONF" minclass 4
  set_conf_value "$PWQUALITY_CONF" difok 4
  set_conf_value "$PWQUALITY_CONF" dictcheck 1
  set_conf_value "$PWQUALITY_CONF" usercheck 1
  set_conf_value "$PWQUALITY_CONF" maxrepeat 3
  set_conf_value "$PWQUALITY_CONF" maxsequence 3
}

password_aging_module(){
  echo -e "\n$BLUE### PASSWORD AGING ###$NC"
  [ -f "$LOGIN_DEFS" ] || { warn "$LOGIN_DEFS no existe"; return; }
  # PASS_MAX_DAYS is intentionally preserved: changing password aging can cause operational lockouts.
  local current_max
  current_max=$(awk '$1=="PASS_MAX_DAYS"{v=$2}END{print v}' "$LOGIN_DEFS")
  info "PASS_MAX_DAYS=${current_max:-no definido} se conserva sin cambios por política operacional."
  set_conf_value "$LOGIN_DEFS" PASS_MIN_DAYS 1
  set_conf_value "$LOGIN_DEFS" PASS_WARN_AGE 7
  info "login.defs solo define defaults; no cambia el aging de cuentas existentes. Se auditan abajo y no se ejecuta chage masivo automáticamente."

  if command -v chage >/dev/null 2>&1; then
    local found=0 line user max
    while IFS=: read -r user _ uid _ _ home shell; do
      [ "$uid" -ge 1000 ] 2>/dev/null || continue
      case "$shell" in */nologin|*/false) continue;; esac
      max=$(chage -l "$user" 2>/dev/null | awk -F: '/Maximum number of days between password change/{gsub(/^[[:space:]]+/,"",$2); print $2}')
      case "$max" in "Never"|"-1"|"99999") ;; *) echo "  [AUDIT] $user: password max age=$max"; found=1;; esac
    done < /etc/passwd
    [ "$found" -eq 0 ] && ok "No se detectaron cuentas locales humanas con expiración reportable" || warn "Hay cuentas existentes con aging; no se modifican automáticamente para evitar afectar cuentas operativas/cPanel"
  fi
}

pam_audit_module(){
  # Legacy EL6 controls use pam_cracklib.so and pam_tally2.so; audit only, never edit PAM blindly.
  echo -e "\n$BLUE### PAM / AUTHSELECT ###$NC"
  local os_major
  os_major="$(get_el_major)"
  if command -v authselect >/dev/null 2>&1; then
    if authselect current >/dev/null 2>&1; then
      ok "authselect activo; PAM se considera administrado por authselect"
      authselect current 2>/dev/null | sed 's/^/  /'
    else
      warn "authselect instalado pero 'authselect current' falló"
    fi
  else
    if [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -le 7 ]; then
      info "authselect no aplica a esta generación; PAM se revisa mediante sus archivos nativos."
    else
      warn "authselect no disponible; PAM requiere revisión específica de la distribución"
    fi
  fi

  local f
  for f in /etc/pam.d/system-auth /etc/pam.d/password-auth; do
    [ -f "$f" ] || continue
    if [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -le 6 ]; then
      if grep -q 'pam_tally2.so' "$f"; then
        ok "$f: pam_tally2 legacy ya presente"
      elif grep -q 'pam_faillock.so' "$f"; then
        ok "$f: pam_faillock ya presente"
      else
        warn "$f: no se encontró pam_tally2 ni pam_faillock para control de intentos fallidos"
      fi
    elif [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -eq 7 ] && grep -Eq 'pam_(faillock|tally2)\.so' "$f"; then
      ok "$f: módulo de bloqueo de intentos fallidos presente"
    else
      grep -q 'pam_faillock.so' "$f" && ok "$f: pam_faillock ya presente" || warn "$f: pam_faillock no configurado"
    fi
  done
  info "No se inserta pam_faillock automáticamente. El orden de PAM es crítico y una modificación incorrecta puede bloquear todos los accesos."
}

su_wheel_module(){
  echo -e "\n$BLUE### SU -> WHEEL ###$NC"
  getent group wheel >/dev/null 2>&1 || { warn "Grupo wheel no existe; no se toca /etc/pam.d/su"; return; }
  local members rootok tmp effect
  members="$(getent group wheel | awk -F: '{print $4}')"
  if [ -z "$members" ]; then
    warn "wheel no tiene miembros no-root; NO se activa pam_wheel para evitar dejar sin vía de escalamiento a administradores"
    return
  fi
  if grep -Eq '^[[:space:]]*auth[[:space:]]+(required|requisite)[[:space:]].*pam_wheel\\.so' "$SU_PAM" 2>/dev/null; then
    ok "su ya restringido a wheel"
    return 0
  fi
  if [ "$AUTO_FIX" != true ] || [ ! -f "$SU_PAM" ]; then
    warn "su no está restringido a wheel"
    echo "Qué hace: limita su a miembros de wheel. Riesgo: cualquier administrador que no esté en wheel perderá la posibilidad de usar su; sudo no cambia."
    return
  fi

  rootok="$(grep -nE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_rootok\\.so' "$SU_PAM" | head -1 | cut -d: -f1)"
  if [ -z "$rootok" ]; then
    warn "No se detectó auth sufficient pam_rootok.so; no se modifica la pila PAM porque no es seguro insertar la restricción automáticamente."
    return
  fi
  effect="limita el comando su a miembros de wheel; los administradores que no estén en wheel pueden perder ese método de escalamiento. Confirma que hay otra vía administrativa probada."
  if ! confirm_password_setting "$SU_PAM" "pam_wheel.so use_uid" "no configurado" "restringir su a wheel" "$effect"; then
    WARNINGS=$((WARNINGS+1)); return
  fi
  backup_once "$SU_PAM" || { warn "No se pudo respaldar $SU_PAM; no se modifica."; return; }
  tmp="$(mktemp "$(dirname "$SU_PAM")/.su.orangebox.XXXXXX")" || { warn "No se pudo crear un temporal para PAM su."; return; }
  awk '
    {print}
    !inserted && $0 ~ /^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_rootok\\.so([[:space:]]|$)/ {
      print "auth required pam_wheel.so use_uid"
      inserted=1
    }
    END {if (!inserted) exit 1}
  ' "$SU_PAM" > "$tmp" || { rm -f "$tmp"; warn "No se pudo colocar pam_wheel después de pam_rootok; no se modifica PAM."; return; }
  chmod --reference="$SU_PAM" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  chown --reference="$SU_PAM" "$tmp" 2>/dev/null || chown root:root "$tmp"
  if ! mv "$tmp" "$SU_PAM"; then rm -f "$tmp"; warn "No se pudo instalar la regla pam_wheel."; return; fi
  if grep -Eq '^[[:space:]]*auth[[:space:]]+required[[:space:]].*pam_wheel\\.so[[:space:]]+use_uid' "$SU_PAM"; then
    ok "su restringido a wheel; regla insertada tras pam_rootok. Backup en $BACKUP_DIR"
    FIXED=$((FIXED+1))
  else
    warn "No se confirmó la regla pam_wheel tras escribirla; revise PAM inmediatamente."
  fi
  echo "  wheel members: $members"
}

file_permissions_module(){
  echo -e "\n$BLUE### FILE PERMISSIONS ###$NC"
  local f p expected effect
  for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    [ -f "$f" ] || continue
    p="$(stat -c %a "$f" 2>/dev/null || true)"
    case "$f" in
      /etc/passwd|/etc/group) expected=644; effect="permite leer el mapa de cuentas/grupos para resolución de identidades; el propietario y grupo correctos limitan quién puede modificarlo." ;;
      *) expected=600; effect="restringe la lectura de hashes y metadatos de credenciales a root; cambios incorrectos pueden afectar herramientas de identidad o autenticación." ;;
    esac
    owner="$(stat -c %U "$f" 2>/dev/null || true)"
    group="$(stat -c %G "$f" 2>/dev/null || true)"
    if [ "$p" = "$expected" ] && [ "$owner" = root ] && [ "$group" = root ]; then
      ok "$f=$p root:root"
      continue
    fi
    if { [ "$f" = /etc/shadow ] || [ "$f" = /etc/gshadow ]; } &&
       { [ "$p" = 0 ] || [ "$p" = 600 ] || [ "$p" = 640 ]; } &&
       [ "$owner" = root ] && [ "$group" = root ]; then
      ok "$f=$p root:root (más restrictivo o equivalente)"
      continue
    fi
    echo -e "$YELLOW[WARN]$NC $f actual=$p $owner:$group; objetivo=$expected root:root"
    echo "Qué hace/riesgo: $effect"
    if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS+1)); continue; fi
    if ! confirm_password_setting "$f" "mode/owner" "$p $owner:$group" "$expected root:root" "$effect"; then
      WARNINGS=$((WARNINGS+1)); continue
    fi
    backup_once "$f" || { warn "No se pudo respaldar $f; no se modifica."; continue; }
    if ! chown root:root "$f" || ! chmod "$expected" "$f"; then
      warn "No se pudieron aplicar propietario/permisos a $f."; continue
    fi
    ok "$f actualizado a $expected root:root"
    FIXED=$((FIXED+1))
  done
}

encrypt_method_module(){
  echo -e "\n$BLUE### PASSWORD HASHING ###$NC"
  local current major expected
  current="$(awk '$1=="ENCRYPT_METHOD"{v=tolower($2)} END{print v}' "$LOGIN_DEFS" 2>/dev/null || true)"
  major="$(get_el_major)"
  expected=SHA512
  if [[ "$major" =~ ^[0-9]+$ ]] && [ "$major" -ge 9 ]; then expected=yescrypt; fi
  if [ "$current" = "$expected" ]; then
    local raw_current
    raw_current="$(awk '$1=="ENCRYPT_METHOD"{v=tolower($2)} END{print v}' "$LOGIN_DEFS" 2>/dev/null || true)"
    if [ "$raw_current" != "$expected" ]; then
      set_conf_value "$LOGIN_DEFS" ENCRYPT_METHOD "$expected"
      ok "ENCRYPT_METHOD normalizado a $expected (sin cambiar hashes existentes)"
    else
      ok "ENCRYPT_METHOD=$expected"
    fi
  else
    set_conf_value "$LOGIN_DEFS" ENCRYPT_METHOD "$expected"
  fi
  info "El algoritmo elegido afecta hashes nuevos; no reescribe contraseñas existentes. PAM y herramientas externas no se modifican automáticamente."
}

main(){
  require_root
  while [ $# -gt 0 ]; do
    case "$1" in --fix|-f) AUTO_FIX=true; ORANGEBOX_ASSUME_YES=1; export ORANGEBOX_ASSUME_YES;; --help|-h) echo "Uso: $0 [--fix]"; exit 0;; *) die "Argumento desconocido: $1";; esac
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
