#!/bin/bash

# ==============================================
# Script: cron-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de cron y at segun CIS Benchmark
#              CIS 5.1.1 - 5.1.8
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/cron-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA MOSTRAR AYUDA
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 --fix      - Modo automático (aplica las correcciones)"
  echo "  $0 -f         - Modo automático (versión corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./cron-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./cron-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCIONES DE VERIFICACION (solo chequean, no modifican)
# ==============================================

check_cron_enabled() {
  echo -e "\n${BLUE}[*] CIS 5.1.1 - Verificando servicio cron...${NC}"

  if systemctl is-enabled crond &>/dev/null; then
    echo -e "${GREEN}[✓] crond habilitado${NC}"
  else
    echo -e "${RED}[!] crond no habilitado${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  if systemctl is-active crond &>/dev/null; then
    echo -e "${GREEN}[✓] crond corriendo${NC}"
  else
    echo -e "${RED}[!] crond no corriendo${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_permissions() {
  local file="$1"
  local perms="$2"
  local owner="$3"
  local group="$4"
  local description="$5"

  if [ ! -e "$file" ]; then
    echo -e "${YELLOW}[!] $file no existe${NC}"
    return 1
  fi

  local current_perms=$(stat -c "%a" "$file" 2>/dev/null)
  local current_owner=$(stat -c "%U" "$file" 2>/dev/null)
  local current_group=$(stat -c "%G" "$file" 2>/dev/null)

  local ok=true

  if [ "$current_perms" != "$perms" ]; then
    echo -e "${RED}[!] $description permisos: $current_perms (debe ser $perms)${NC}"
    ok=false
  else
    echo -e "${GREEN}[✓] $description permisos correctos: $current_perms${NC}"
  fi

  if [ "$current_owner" != "$owner" ]; then
    echo -e "${RED}[!] $description propietario: $current_owner (debe ser $owner)${NC}"
    ok=false
  else
    echo -e "${GREEN}[✓] $description propietario correcto: $current_owner${NC}"
  fi

  if [ "$current_group" != "$group" ]; then
    echo -e "${RED}[!] $description grupo: $current_group (debe ser $group)${NC}"
    ok=false
  else
    echo -e "${GREEN}[✓] $description grupo correcto: $current_group${NC}"
  fi

  if [ "$ok" = false ]; then
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_user_restriction() {
  local allow_file="$1"
  local deny_file="$2"
  local service="$3"

  echo -e "\n${BLUE}[*] Verificando restriccion de usuarios para $service...${NC}"

  if [ -f "$deny_file" ]; then
    echo -e "${RED}[!] $deny_file existe - debe eliminarse${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] $deny_file no existe${NC}"
  fi

  if [ ! -f "$allow_file" ]; then
    echo -e "${RED}[!] $allow_file no existe - debe crearse${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] $allow_file existe${NC}"
    if ! grep -q "^root$" "$allow_file"; then
      echo -e "${RED}[!] root no esta en $allow_file${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    check_permissions "$allow_file" "600" "root" "root" "Archivo $allow_file"
  fi
}

# ==============================================
# FUNCIONES DE APLICACION (modifican el sistema)
# ==============================================

apply_cron_enabled() {
  echo -e "\n${BLUE}[*] Aplicando: Habilitar e iniciar cron...${NC}"

  if ! systemctl is-enabled crond &>/dev/null; then
    systemctl enable crond
    echo -e "${GREEN}[✓] crond habilitado${NC}"
    FIXED=$((FIXED + 1))
  fi

  if ! systemctl is-active crond &>/dev/null; then
    systemctl start crond
    echo -e "${GREEN}[✓] crond iniciado${NC}"
    FIXED=$((FIXED + 1))
  fi
}

apply_permissions() {
  local file="$1"
  local perms="$2"
  local owner="$3"
  local group="$4"
  local description="$5"

  if [ ! -e "$file" ]; then
    return 1
  fi

  local current_perms=$(stat -c "%a" "$file" 2>/dev/null)
  local current_owner=$(stat -c "%U" "$file" 2>/dev/null)
  local current_group=$(stat -c "%G" "$file" 2>/dev/null)

  local changed=false

  if [ "$current_perms" != "$perms" ]; then
    chmod "$perms" "$file" 2>/dev/null
    echo -e "${GREEN}[✓] $description permisos corregido: $perms${NC}"
    changed=true
  fi

  if [ "$current_owner" != "$owner" ]; then
    chown "$owner:$group" "$file" 2>/dev/null
    echo -e "${GREEN}[✓] $description propietario corregido: $owner${NC}"
    changed=true
  fi

  if [ "$changed" = true ]; then
    FIXED=$((FIXED + 1))
  fi
}

apply_user_restriction() {
  local allow_file="$1"
  local deny_file="$2"
  local service="$3"

  echo -e "\n${BLUE}[*] Aplicando restriccion de usuarios para $service...${NC}"

  if [ -f "$deny_file" ]; then
    rm -f "$deny_file"
    echo -e "${GREEN}[✓] $deny_file eliminado${NC}"
    FIXED=$((FIXED + 1))
  fi

  if [ ! -f "$allow_file" ]; then
    echo "root" >"$allow_file"
    chmod 600 "$allow_file"
    chown root:root "$allow_file"
    echo -e "${GREEN}[✓] $allow_file creado con usuario root${NC}"
    FIXED=$((FIXED + 1))
  else
    if ! grep -q "^root$" "$allow_file"; then
      echo "root" >>"$allow_file"
      echo -e "${GREEN}[✓] root agregado a $allow_file${NC}"
      FIXED=$((FIXED + 1))
    fi
    apply_permissions "$allow_file" "600" "root" "root" "Archivo $allow_file"
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Cron Hardening - CIS 5.1.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Modo ayuda
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  # Modo verificación (sin --fix)
  if [ "$1" != "--fix" ] && [ "$1" != "-f" ]; then
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"

    check_cron_enabled
    check_cron_permissions
    check_cron_restriction
    check_at_restriction

    echo -e "\n${GREEN}============================================${NC}"
    echo -e "${GREEN}  VERIFICACIÓN COMPLETADA${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "${YELLOW}Advertencias encontradas: $WARNINGS${NC}"
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
    exit 0
  fi

  # Modo automático (--fix o -f)
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Backup
    mkdir -p "$BACKUP_DIR"
    for file in /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny; do
      [ -f "$file" ] && cp "$file" "$BACKUP_DIR/" 2>/dev/null
      [ -d "$file" ] && cp -r "$file" "$BACKUP_DIR/" 2>/dev/null
    done
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}\n"

    # Aplicar cambios
    apply_cron_enabled
    apply_cron_permissions
    apply_user_restriction "/etc/cron.allow" "/etc/cron.deny" "cron"
    apply_user_restriction "/etc/at.allow" "/etc/at.deny" "at"

    # Reiniciar servicio
    systemctl restart crond
    echo -e "\n${GREEN}[✓] crond reiniciado${NC}"

    # Resumen
    echo -e "\n${GREEN}============================================${NC}"
    echo -e "${GREEN}  CRON HARDENING COMPLETADO${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "${YELLOW}Correcciones aplicadas: $FIXED${NC}"
    echo -e "${YELLOW}Backup disponible en: $BACKUP_DIR${NC}"
    exit 0
  fi
}

# ==============================================
# DECLARACION DE FUNCIONES ADICIONALES
# ==============================================

check_cron_permissions() {
  echo -e "\n${BLUE}[*] Verificando permisos de archivos cron...${NC}"
  check_permissions "/etc/crontab" "600" "root" "root" "/etc/crontab"
  check_permissions "/etc/cron.hourly" "700" "root" "root" "/etc/cron.hourly"
  check_permissions "/etc/cron.daily" "700" "root" "root" "/etc/cron.daily"
  check_permissions "/etc/cron.weekly" "700" "root" "root" "/etc/cron.weekly"
  check_permissions "/etc/cron.monthly" "700" "root" "root" "/etc/cron.monthly"
  check_permissions "/etc/cron.d" "700" "root" "root" "/etc/cron.d"
}

check_cron_restriction() {
  check_user_restriction "/etc/cron.allow" "/etc/cron.deny" "cron"
}

check_at_restriction() {
  check_user_restriction "/etc/at.allow" "/etc/at.deny" "at"
}

apply_cron_permissions() {
  echo -e "\n${BLUE}[*] Aplicando permisos de archivos cron...${NC}"
  apply_permissions "/etc/crontab" "600" "root" "root" "/etc/crontab"
  apply_permissions "/etc/cron.hourly" "700" "root" "root" "/etc/cron.hourly"
  apply_permissions "/etc/cron.daily" "700" "root" "root" "/etc/cron.daily"
  apply_permissions "/etc/cron.weekly" "700" "root" "root" "/etc/cron.weekly"
  apply_permissions "/etc/cron.monthly" "700" "root" "root" "/etc/cron.monthly"
  apply_permissions "/etc/cron.d" "700" "root" "root" "/etc/cron.d"
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
