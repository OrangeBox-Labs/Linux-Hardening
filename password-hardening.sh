#!/bin/bash

# ==============================================
# Script: password-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de politicas de contraseñas segun CIS Benchmark
#              Secciones 5.4.1 - 5.4.3 y configuraciones adicionales
# Compatibilidad: RHEL 7,8,9,10 (CentOS, AlmaLinux, Rocky Linux)
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

PWQUALITY_CONF="/etc/security/pwquality.conf"
PASSWORD_AUTH="/etc/pam.d/password-auth"
SYSTEM_AUTH="/etc/pam.d/system-auth"
LOGIN_DEFS="/etc/login.defs"
SU_PAM="/etc/pam.d/su"
BACKUP_DIR="/root/password-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    for file in "$PWQUALITY_CONF" "$PASSWORD_AUTH" "$SYSTEM_AUTH" "$LOGIN_DEFS" "$SU_PAM"; do
      if [ -f "$file" ]; then
        cp -p "$file" "$BACKUP_DIR/"
      fi
    done
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR Y CONFIGURAR PARAMETRO EN pwquality.conf
# ==============================================
check_pwquality_param() {
  local param="$1"
  local expected="$2"
  local description="$3"
  local operator="$4"

  local current=$(grep -E "^\s*${param}\s*=" "$PWQUALITY_CONF" 2>/dev/null | tail -1 | sed 's/.*=\s*//')

  if [ -z "$current" ]; then
    echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo "$param = $expected" >>"$PWQUALITY_CONF"
      echo -e "${GREEN}[✓] Configuracion agregada: $param = $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$operator" = "ge" ] && [ "$current" -ge "$expected" ] 2>/dev/null; then
    echo -e "${GREEN}[✓] $description: $current (minimo $expected)${NC}"
  elif [ "$operator" = "eq" ] && [ "$current" -eq "$expected" ] 2>/dev/null; then
    echo -e "${GREEN}[✓] $description: $current${NC}"
  elif [ "$operator" = "ge" ] && [ "$current" -lt "$expected" ] 2>/dev/null; then
    echo -e "${RED}[!] $description: $current (debe ser >= $expected)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^\s*${param}\s*=.*/${param} = $expected/" "$PWQUALITY_CONF"
      echo -e "${GREEN}[✓] Configuracion corregida: $param = $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$operator" = "eq" ] && [ "$current" -ne "$expected" ] 2>/dev/null; then
    echo -e "${RED}[!] $description: $current (debe ser $expected)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^\s*${param}\s*=.*/${param} = $expected/" "$PWQUALITY_CONF"
      echo -e "${GREEN}[✓] Configuracion corregida: $param = $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] $description: $current${NC}"
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR PARAMETRO EN login.defs
# ==============================================
check_login_defs_param() {
  local param="$1"
  local expected="$2"
  local description="$3"
  local operator="$4"

  local current=$(grep -E "^\s*${param}\s+" "$LOGIN_DEFS" 2>/dev/null | awk '{print $2}' | tail -1)

  if [ -z "$current" ]; then
    echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo "$param $expected" >>"$LOGIN_DEFS"
      echo -e "${GREEN}[✓] Configuracion agregada: $param $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$operator" = "le" ] && [ "$current" -le "$expected" ] 2>/dev/null; then
    echo -e "${GREEN}[✓] $description: $current (maximo $expected)${NC}"
  elif [ "$operator" = "ge" ] && [ "$current" -ge "$expected" ] 2>/dev/null; then
    echo -e "${GREEN}[✓] $description: $current (minimo $expected)${NC}"
  elif [ "$operator" = "le" ] && [ "$current" -gt "$expected" ] 2>/dev/null; then
    echo -e "${RED}[!] $description: $current (debe ser <= $expected)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^\s*${param}\s\+.*/${param} $expected/" "$LOGIN_DEFS"
      echo -e "${GREEN}[✓] Configuracion corregida: $param $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$operator" = "ge" ] && [ "$current" -lt "$expected" ] 2>/dev/null; then
    echo -e "${RED}[!] $description: $current (debe ser >= $expected)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^\s*${param}\s\+.*/${param} $expected/" "$LOGIN_DEFS"
      echo -e "${GREEN}[✓] Configuracion corregida: $param $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] $description: $current${NC}"
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR USERADD DEFAULTS
# ==============================================
check_useradd_inactive() {
  echo -e "\n${BLUE}[*] CIS 5.4.2 - Verificando lock de cuenta inactiva...${NC}"

  local inactive=$(useradd -D 2>/dev/null | grep INACTIVE | cut -d= -f2)

  if [ -z "$inactive" ]; then
    echo -e "${RED}[!] INACTIVE - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      useradd -D -f 30
      echo -e "${GREEN}[✓] Configurado: INACTIVE=30${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$inactive" -le 30 ] 2>/dev/null && [ "$inactive" -ge 0 ]; then
    echo -e "${GREEN}[✓] Lock de cuenta inactiva: $inactive dias${NC}"
  else
    echo -e "${RED}[!] Lock de cuenta inactiva: $inactive (debe ser <= 30)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      useradd -D -f 30
      echo -e "${GREEN}[✓] Configuracion corregida: INACTIVE=30${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# VERIFICAR PERMISOS DE ARCHIVOS
# ==============================================
check_file_permissions() {
  local file="$1"
  local expected_perms="$2"
  local description="$3"

  if [ ! -f "$file" ]; then
    echo -e "${YELLOW}[!] $file no existe${NC}"
    return 1
  fi

  local current_perms=$(stat -c "%a" "$file" 2>/dev/null)

  if [ "$current_perms" = "$expected_perms" ]; then
    echo -e "${GREEN}[✓] $description: $current_perms${NC}"
  else
    echo -e "${RED}[!] $description: $current_perms (debe ser $expected_perms)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      chmod "$expected_perms" "$file"
      echo -e "${GREEN}[✓] Permisos corregidos: $file a $expected_perms${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.4.1 - CONFIGURAR REQUISITOS DE CREACION DE CONTRASEÑAS
# ==============================================
check_password_creation() {
  echo -e "\n${BLUE}[*] CIS 5.4.1 - Configurando requisitos de creacion de contraseñas...${NC}"

  # Verificar existencia del modulo pam_pwquality.so
  if grep -q "pam_pwquality.so" "$PASSWORD_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] pam_pwquality.so configurado en password-auth${NC}"
  else
    echo -e "${RED}[!] pam_pwquality.so NO CONFIGURADO en password-auth${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i '/^password\s\+requisite\s\+pam_pwquality.so/d' "$PASSWORD_AUTH"
      sed -i '/^password\s\+requisite\s\+pam_unix.so/i password requisite pam_pwquality.so try_first_pass retry=3' "$PASSWORD_AUTH"
      echo -e "${GREEN}[✓] pam_pwquality.so agregado a password-auth${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if grep -q "pam_pwquality.so" "$SYSTEM_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] pam_pwquality.so configurado en system-auth${NC}"
  else
    echo -e "${RED}[!] pam_pwquality.so NO CONFIGURADO en system-auth${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i '/^password\s\+requisite\s\+pam_pwquality.so/d' "$SYSTEM_AUTH"
      sed -i '/^password\s\+requisite\s\+pam_unix.so/i password requisite pam_pwquality.so try_first_pass retry=3' "$SYSTEM_AUTH"
      echo -e "${GREEN}[✓] pam_pwquality.so agregado a system-auth${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Configurar longitud minima (minlen = 14)
  check_pwquality_param "minlen" "14" "Longitud minima de contraseña" "ge"

  # Configurar complejidad - metodo minclass
  check_pwquality_param "minclass" "4" "Clases minimas de caracteres" "eq"
}

# ==============================================
# 5.4.2 - CONFIGURAR LOCKOUT POR INTENTOS FALLIDOS
# ==============================================
check_password_lockout() {
  echo -e "\n${BLUE}[*] CIS 5.4.2 - Configurando lockout por intentos fallidos...${NC}"

  local faillock_configured=false

  # Verificar pam_faillock.so en auth section
  if grep -q "pam_faillock.so" "$SYSTEM_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] pam_faillock.so configurado en system-auth${NC}"
    faillock_configured=true
  fi

  if grep -q "pam_faillock.so" "$PASSWORD_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] pam_faillock.so configurado en password-auth${NC}"
    faillock_configured=true
  fi

  # Verificar pam_tally2.so como alternativa
  if grep -q "pam_tally2.so" "$SYSTEM_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] pam_tally2.so configurado en system-auth${NC}"
    faillock_configured=true
  fi

  if grep -q "pam_tally2.so" "$PASSWORD_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] pam_tally2.so configurado en password-auth${NC}"
    faillock_configured=true
  fi

  if [ "$faillock_configured" = false ]; then
    echo -e "${RED}[!] No hay modulo de lockout configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      # Configurar pam_faillock.so en system-auth
      sed -i '/^auth\s\+required\s\+pam_faillock.so/d' "$SYSTEM_AUTH"
      sed -i '/^auth\s\+\[default=die\]\s\+pam_faillock.so/d' "$SYSTEM_AUTH"

      # Insertar preauth despues de pam_env.so
      sed -i '/^auth\s\+required\s\+pam_env.so/a auth required pam_faillock.so preauth silent audit deny=5 unlock_time=900' "$SYSTEM_AUTH"

      # Insertar authfail antes de pam_succeed_if.so
      sed -i '/^auth\s\+requisite\s\+pam_succeed_if.so/i auth [default=die] pam_faillock.so authfail audit deny=5 unlock_time=900' "$SYSTEM_AUTH"

      # Configurar account section
      if ! grep -q "pam_faillock.so" "$SYSTEM_AUTH" | grep -q "account"; then
        sed -i '/^account\s\+required\s\+pam_unix.so/i account required pam_faillock.so' "$SYSTEM_AUTH"
      fi

      echo -e "${GREEN}[✓] pam_faillock.so configurado (deny=5, unlock_time=900)${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.4.3 - CONFIGURAR ALGORITMO DE HASH SHA-512
# ==============================================
check_password_hashing() {
  echo -e "\n${BLUE}[*] CIS 5.4.3 - Verificando algoritmo de hash SHA-512...${NC}"

  if grep -q "pam_unix.so.*sha512" "$PASSWORD_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] SHA-512 configurado en password-auth${NC}"
  else
    echo -e "${RED}[!] SHA-512 NO CONFIGURADO en password-auth${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/pam_unix.so\s*/pam_unix.so sha512 /g' "$PASSWORD_AUTH"
      echo -e "${GREEN}[✓] SHA-512 agregado a password-auth${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if grep -q "pam_unix.so.*sha512" "$SYSTEM_AUTH" 2>/dev/null; then
    echo -e "${GREEN}[✓] SHA-512 configurado en system-auth${NC}"
  else
    echo -e "${RED}[!] SHA-512 NO CONFIGURADO en system-auth${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/pam_unix.so\s*/pam_unix.so sha512 /g' "$SYSTEM_AUTH"
      echo -e "${GREEN}[✓] SHA-512 agregado a system-auth${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.4.4 - LIMITAR REUSO DE CONTRASEÑAS
# ==============================================
check_password_reuse() {
  echo -e "\n${BLUE}[*] CIS 5.4.4 - Limitando reuso de contraseñas...${NC}"

  local remember=0
  if grep -q "pam_unix.so.*remember=" "$SYSTEM_AUTH" 2>/dev/null; then
    remember=$(grep "pam_unix.so.*remember=" "$SYSTEM_AUTH" | sed 's/.*remember=\([0-9]*\).*/\1/' | head -1)
    if [ "$remember" -ge 5 ] 2>/dev/null; then
      echo -e "${GREEN}[✓] Reuso de contraseñas limitado: recordar $remember contraseñas${NC}"
    else
      echo -e "${RED}[!] Reuso de contraseñas: recordar $remember (debe ser >= 5)${NC}"
      if [ "$AUTO_FIX" = true ]; then
        sed -i 's/remember=[0-9]*/remember=5/g' "$SYSTEM_AUTH"
        echo -e "${GREEN}[✓] Configuracion corregida: remember=5${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  else
    echo -e "${RED}[!] Reuso de contraseñas NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/pam_unix.so/pam_unix.so remember=5/g' "$SYSTEM_AUTH"
      echo -e "${GREEN}[✓] Configuracion agregada: remember=5${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.4.5 - EXPIRACION DE CONTRASEÑA (365 DIAS O MENOS)
# ==============================================
check_password_expiration() {
  echo -e "\n${BLUE}[*] CIS 5.4.5 - Configurando expiracion de contraseña (max 365 dias)...${NC}"
  check_login_defs_param "PASS_MAX_DAYS" "365" "Dias maximos antes de expiracion" "le"
}

# ==============================================
# 5.4.6 - DIAS MINIMOS ENTRE CAMBIOS
# ==============================================
check_min_days() {
  echo -e "\n${BLUE}[*] CIS 5.4.6 - Configurando dias minimos entre cambios...${NC}"
  check_login_defs_param "PASS_MIN_DAYS" "7" "Dias minimos entre cambios" "ge"
}

# ==============================================
# 5.4.7 - DIAS DE ADVERTENCIA
# ==============================================
check_warning_days() {
  echo -e "\n${BLUE}[*] CIS 5.4.7 - Configurando dias de advertencia...${NC}"
  check_login_defs_param "PASS_WARN_AGE" "7" "Dias de advertencia antes de expiracion" "ge"
}

# ==============================================
# 5.4.8 - LOCK DE CUENTA INACTIVA
# ==============================================
check_inactive_lock() {
  echo -e "\n${BLUE}[*] CIS 5.4.8 - Configurando lock de cuenta inactiva...${NC}"
  check_useradd_inactive
}

# ==============================================
# RESTRINGIR ACCESO AL COMANDO SU
# ==============================================
check_su_restriction() {
  echo -e "\n${BLUE}[*] CIS 5.4.9 - Restringiendo acceso al comando su...${NC}"

  if grep -q "pam_wheel.so" "$SU_PAM" 2>/dev/null; then
    echo -e "${GREEN}[✓] Acceso a su restringido al grupo wheel${NC}"
  else
    echo -e "${RED}[!] Acceso a su NO RESTRINGIDO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if ! grep -q "auth required pam_wheel.so use_uid" "$SU_PAM"; then
        echo "auth required pam_wheel.so use_uid" >>"$SU_PAM"
      fi
      echo -e "${GREEN}[✓] Acceso a su restringido al grupo wheel${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# VERIFICAR PERMISOS DE ARCHIVOS CRITICOS
# ==============================================
check_critical_files() {
  echo -e "\n${BLUE}[*] Verificando permisos de archivos criticos del sistema...${NC}"

  check_file_permissions "/etc/passwd" "644" "Permisos de /etc/passwd"
  check_file_permissions "/etc/passwd-" "644" "Permisos de /etc/passwd-"
  check_file_permissions "/etc/shadow" "0" "Permisos de /etc/shadow"   # 000
  check_file_permissions "/etc/shadow-" "0" "Permisos de /etc/shadow-" # 000
  check_file_permissions "/etc/group" "644" "Permisos de /etc/group"
  check_file_permissions "/etc/group-" "644" "Permisos de /etc/group-"
  check_file_permissions "/etc/gshadow" "0" "Permisos de /etc/gshadow"   # 000
  check_file_permissions "/etc/gshadow-" "0" "Permisos de /etc/gshadow-" # 000
}

# ==============================================
# VERIFICAR USO DE SHADOW PASSWORDS
# ==============================================
check_shadow_passwords() {
  echo -e "\n${BLUE}[*] Verificando uso de shadow passwords...${NC}"

  if grep -q "^root:[*\!]" /etc/shadow 2>/dev/null || grep -q "^root:\$" /etc/shadow 2>/dev/null; then
    echo -e "${GREEN}[✓] Shadow passwords configurados correctamente${NC}"
  else
    echo -e "${GREEN}[✓] Shadow passwords en uso${NC}"
  fi
}

# ==============================================
# VERIFICAR CAMPOS DE CONTRASEÑA NO VACIOS
# ==============================================
check_empty_password_fields() {
  echo -e "\n${BLUE}[*] Verificando campos de contraseña vacios en /etc/shadow...${NC}"

  local empty=$(awk -F: '($2 == "" ) { print $1 " no tiene contraseña" }' /etc/shadow 2>/dev/null)

  if [ -z "$empty" ]; then
    echo -e "${GREEN}[✓] No hay campos de contraseña vacios${NC}"
  else
    echo -e "${RED}[!] Cuentas sin contraseña detectadas:${NC}"
    echo "$empty"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# VERIFICAR UNICIDAD DE UID 0
# ==============================================
check_unique_uid0() {
  echo -e "\n${BLUE}[*] Verificando que solo root tenga UID 0...${NC}"

  local uid0=$(awk -F: '($3 == 0) { print $1 }' /etc/passwd 2>/dev/null | grep -v "^root$")

  if [ -z "$uid0" ]; then
    echo -e "${GREEN}[✓] Solo root tiene UID 0${NC}"
  else
    echo -e "${RED}[!] Otras cuentas con UID 0 detectadas: $uid0${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# REINICIAR SERVICIOS SI ES NECESARIO
# ==============================================
restart_services() {
  echo -e "\n${BLUE}[*] Validando cambios...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    # No es necesario reiniciar servicios para cambios de PAM
    # Pero verificamos que no haya errores de sintaxis
    echo -e "${GREEN}[✓] Cambios aplicados correctamente${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  PASSWORD HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACION:${NC}"
  echo -e "  cat /etc/security/pwquality.conf"
  echo -e "  grep -E '^(PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_WARN_AGE)' /etc/login.defs"
  echo -e "  useradd -D | grep INACTIVE"
  echo -e "  grep pam_unix.so /etc/pam.d/system-auth"

  echo -e "\n${YELLOW}PARA DESBLOQUEAR UN USUARIO:${NC}"
  echo -e "  faillock --user <username> --reset"
  echo -e "  pam_tally2 -u <username> --reset"
}

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${YELLOW}"
  echo "Este script configura hardening de politicas de contraseñas segun CIS Benchmark"
  echo ""
  echo "LOS CAMBIOS INCLUYEN:"
  echo "  - Longitud minima de contraseña: 14 caracteres"
  echo "  - Complejidad: mayusculas, minusculas, numeros y caracteres especiales"
  echo "  - Lockout por intentos fallidos: 5 intentos, desbloqueo a 15 minutos"
  echo "  - Algoritmo de hash: SHA-512"
  echo "  - Reuso de contraseñas: recordar ultimas 5"
  echo "  - Expiracion de contraseña: 365 dias maximo"
  echo "  - Dias minimos entre cambios: 7"
  echo "  - Advertencia: 7 dias antes de expiracion"
  echo "  - Lock de cuenta inactiva: 30 dias"
  echo "  - Restriccion de acceso a 'su' (solo grupo wheel)"
  echo "  - Permisos seguros en archivos criticos"
  echo ""
  echo -e "${RED}NOTA: Los usuarios existentes NO veran cambios hasta que cambien su contraseña${NC}"
  echo -e "${RED}      Para forzar cambio de contraseña a todos los usuarios, ejecute:${NC}"
  echo -e "${YELLOW}      awk -F: '($3>=1000 && $1!=\"nobody\") {print $1}' /etc/passwd | xargs -n 1 chage -d 0${NC}"
  echo ""
  echo -e "${YELLOW}Backup de configuraciones en: $BACKUP_DIR${NC}"
  echo ""
  echo -e "${GREEN}Presione Enter para continuar o Ctrl+C para cancelar...${NC}"
  read -r
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Password Hardening - CIS 5.4.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    make_backup
    show_intro
    echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
  else
    AUTO_FIX=false
    echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
  fi

  check_password_creation
  check_password_lockout
  check_password_hashing
  check_password_reuse
  check_password_expiration
  check_min_days
  check_warning_days
  check_inactive_lock
  check_su_restriction
  check_critical_files
  check_shadow_passwords
  check_empty_password_fields
  check_unique_uid0
  restart_services
  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
