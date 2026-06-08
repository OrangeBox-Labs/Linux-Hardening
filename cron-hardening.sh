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
  echo -e "${YELLOW}NOTA:${NC} Se requiere acceso root para ejecutar este script"
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    for file in /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny; do
      [ -f "$file" ] && cp "$file" "$BACKUP_DIR/" 2>/dev/null
      [ -d "$file" ] && cp -r "$file" "$BACKUP_DIR/" 2>/dev/null
    done
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA CORREGIR PERMISOS
# ==============================================
fix_permissions() {
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

  local needs_fix=0

  if [ "$current_perms" != "$perms" ]; then
    echo -e "${RED}[!] $description permisos: $current_perms (debe ser $perms)${NC}"
    needs_fix=1
  else
    echo -e "${GREEN}[✓] $description permisos correctos: $current_perms${NC}"
  fi

  if [ "$current_owner" != "$owner" ]; then
    echo -e "${RED}[!] $description propietario: $current_owner (debe ser $owner)${NC}"
    needs_fix=1
  else
    echo -e "${GREEN}[✓] $description propietario correcto: $current_owner${NC}"
  fi

  if [ "$current_group" != "$group" ]; then
    echo -e "${RED}[!] $description grupo: $current_group (debe ser $group)${NC}"
    needs_fix=1
  else
    echo -e "${GREEN}[✓] $description grupo correcto: $current_group${NC}"
  fi

  if [ $needs_fix -eq 1 ] && [ "$AUTO_FIX" = true ]; then
    chmod "$perms" "$file" 2>/dev/null
    chown "$owner:$group" "$file" 2>/dev/null
    echo -e "${GREEN}[✓] $description corregido${NC}"
    FIXED=$((FIXED + 1))
  elif [ $needs_fix -eq 1 ]; then
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA CONFIGURAR RESTRICCION DE USUARIOS
# ==============================================
configure_user_restriction() {
  local allow_file="$1"
  local deny_file="$2"
  local service="$3"

  echo -e "\n${BLUE}[*] Configurando restriccion de usuarios para $service...${NC}"

  # Eliminar archivo .deny si existe
  if [ -f "$deny_file" ]; then
    echo -e "${YELLOW}[!] $deny_file existe - debe eliminarse${NC}"
    if [ "$AUTO_FIX" = true ]; then
      rm -f "$deny_file"
      echo -e "${GREEN}[✓] $deny_file eliminado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] $deny_file no existe${NC}"
  fi

  # Crear archivo .allow con root si no existe
  if [ ! -f "$allow_file" ]; then
    echo -e "${RED}[!] $allow_file no existe${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo "root" >"$allow_file"
      chmod 600 "$allow_file"
      chown root:root "$allow_file"
      echo -e "${GREEN}[✓] $allow_file creado con usuario root${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] $allow_file existe${NC}"
    # Verificar que root este en el archivo
    if ! grep -q "^root$" "$allow_file"; then
      echo -e "${RED}[!] root no esta en $allow_file${NC}"
      if [ "$AUTO_FIX" = true ]; then
        echo "root" >>"$allow_file"
        echo -e "${GREEN}[✓] root agregado a $allow_file${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
    fix_permissions "$allow_file" "600" "root" "root" "Archivo $allow_file"
  fi
}

# ==============================================
# 5.1.1 - ENSURE CRON DAEMON IS ENABLED AND RUNNING
# ==============================================
check_cron_enabled() {
  echo -e "\n${BLUE}[*] CIS 5.1.1 - Verificando servicio cron...${NC}"

  if systemctl is-enabled crond &>/dev/null; then
    echo -e "${GREEN}[✓] crond habilitado${NC}"
  else
    echo -e "${RED}[!] crond no habilitado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      systemctl enable crond
      echo -e "${GREEN}[✓] crond habilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if systemctl is-active crond &>/dev/null; then
    echo -e "${GREEN}[✓] crond corriendo${NC}"
  else
    echo -e "${RED}[!] crond no corriendo${NC}"
    if [ "$AUTO_FIX" = true ]; then
      systemctl start crond
      echo -e "${GREEN}[✓] crond iniciado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.1.2 - 5.1.7 - PERMISOS DE ARCHIVOS CRON
# ==============================================
check_cron_permissions() {
  echo -e "\n${BLUE}[*] Verificando permisos de archivos cron...${NC}"

  fix_permissions "/etc/crontab" "600" "root" "root" "/etc/crontab"
  fix_permissions "/etc/cron.hourly" "700" "root" "root" "/etc/cron.hourly"
  fix_permissions "/etc/cron.daily" "700" "root" "root" "/etc/cron.daily"
  fix_permissions "/etc/cron.weekly" "700" "root" "root" "/etc/cron.weekly"
  fix_permissions "/etc/cron.monthly" "700" "root" "root" "/etc/cron.monthly"
  fix_permissions "/etc/cron.d" "700" "root" "root" "/etc/cron.d"
}

# ==============================================
# 5.1.8 - ENSURE CRON IS RESTRICTED TO AUTHORIZED USERS
# ==============================================
check_cron_restriction() {
  configure_user_restriction "/etc/cron.allow" "/etc/cron.deny" "cron"
}

# ==============================================
# 5.1.9 - ENSURE AT IS RESTRICTED TO AUTHORIZED USERS
# ==============================================
check_at_restriction() {
  configure_user_restriction "/etc/at.allow" "/etc/at.deny" "at"
}

# ==============================================
# REINICIAR SERVICIO
# ==============================================
restart_cron() {
  echo -e "\n${BLUE}[*] Reiniciando servicio cron...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    systemctl restart crond
    echo -e "${GREEN}[✓] crond reiniciado${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  CRON HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR CRON:${NC}"
  echo -e "  systemctl status crond"
  echo -e "  ls -la /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d"
  echo -e "  cat /etc/cron.allow"
  echo -e "  cat /etc/at.allow"
}

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${YELLOW}"
  echo "Este script configura hardening de cron y at segun CIS Benchmark"
  echo ""
  echo "LOS CAMBIOS INCLUYEN:"
  echo "  - Habilitar e iniciar servicio cron"
  echo "  - Permisos 600 para /etc/crontab"
  echo "  - Permisos 700 para directorios cron (hourly, daily, weekly, monthly, d)"
  echo "  - Eliminar cron.deny y crear cron.allow con solo root"
  echo "  - Eliminar at.deny y crear at.allow con solo root"
  echo ""
  echo -e "${RED}NOTA: Solo el usuario root podra programar tareas con cron y at${NC}"
  echo ""
  echo -e "${YELLOW}Backup de configuraciones en: $BACKUP_DIR${NC}"
  echo ""
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Cron Hardening - CIS 5.1.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Modo verificación (sin --fix)
  if [ -z "$1" ]; then
    AUTO_FIX=false
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo ""
    echo -e "${YELLOW}Los siguientes problemas fueron detectados:${NC}\n"
  fi

  # Modo automático con --fix
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    make_backup
    show_intro
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}\n"
    show_usage
  fi

  # Modo ayuda (--help)
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  check_cron_enabled
  check_cron_permissions
  check_cron_restriction
  check_at_restriction
  restart_cron
  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
