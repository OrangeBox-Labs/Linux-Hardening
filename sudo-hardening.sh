#!/bin/bash

# ==============================================
# Script: sudo-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de sudo segun CIS Benchmark
#              CIS 5.2.1 - 5.2.4
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

SUDOERS_FILE="/etc/sudoers"
SUDOERS_D_DIR="/etc/sudoers.d"
BACKUP_DIR="/root/sudo-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    if [ -f "$SUDOERS_FILE" ]; then
      cp "$SUDOERS_FILE" "$BACKUP_DIR/"
    fi
    if [ -d "$SUDOERS_D_DIR" ]; then
      cp -r "$SUDOERS_D_DIR" "$BACKUP_DIR/"
    fi
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR CONFIGURACION EN SUDOERS
# ==============================================
check_sudoers_config() {
  local pattern="$1"
  local description="$2"
  local fix_line="$3"

  if grep -q "$pattern" "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${GREEN}[✓] $description${NC}"
    return 0
  else
    echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ] && [ -n "$fix_line" ]; then
      # Agregar la configuracion al archivo
      echo "$fix_line" >>"$SUDOERS_FILE"
      echo -e "${GREEN}[✓] Configuracion agregada: $fix_line${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 1
  fi
}

# ==============================================
# FUNCION PARA VALIDAR SINTAXIS DE SUDOERS
# ==============================================
validate_sudoers() {
  if visudo -c &>/dev/null; then
    echo -e "${GREEN}[✓] Sintaxis de sudoers correcta${NC}"
    return 0
  else
    echo -e "${RED}[!] Error en sintaxis de sudoers${NC}"
    if [ "$AUTO_FIX" = true ] && [ -f "$BACKUP_DIR/sudoers" ]; then
      cp "$BACKUP_DIR/sudoers" "$SUDOERS_FILE"
      echo -e "${YELLOW}[!] Restaurado backup por error de sintaxis${NC}"
    fi
    return 1
  fi
}

# ==============================================
# 5.2.1 - ENSURE SUDO IS INSTALLED
# ==============================================
check_sudo_installed() {
  echo -e "\n${BLUE}[*] CIS 5.2.1 - Verificando sudo instalado...${NC}"

  if rpm -q sudo &>/dev/null; then
    echo -e "${GREEN}[✓] sudo instalado${NC}"
  else
    echo -e "${RED}[!] sudo no instalado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      yum install sudo -y 2>/dev/null || dnf install sudo -y 2>/dev/null
      echo -e "${GREEN}[✓] sudo instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: yum install sudo -y${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.2.2 - ENSURE SUDO COMMANDS USE PTY
# ==============================================
check_sudo_pty() {
  echo -e "\n${BLUE}[*] CIS 5.2.2 - Verificando uso de pseudo-terminal (pty) en sudo...${NC}"

  check_sudoers_config "Defaults.*use_pty" "sudo usa pseudo-terminal (pty)" "Defaults use_pty"
}

# ==============================================
# 5.2.3 - ENSURE SUDO LOG FILE EXISTS
# ==============================================
check_sudo_logfile() {
  echo -e "\n${BLUE}[*] CIS 5.2.3 - Verificando archivo de log de sudo...${NC}"

  check_sudoers_config "Defaults.*logfile" "sudo tiene archivo de log configurado" 'Defaults logfile="/var/log/sudo.log"'

  # Verificar que el archivo de log existe
  if grep -q "logfile" "$SUDOERS_FILE" 2>/dev/null; then
    LOGFILE=$(grep "logfile" "$SUDOERS_FILE" | grep -v "^#" | awk -F'"' '{print $2}')
    if [ -n "$LOGFILE" ]; then
      if [ ! -f "$LOGFILE" ]; then
        echo -e "${YELLOW}[!] Archivo de log $LOGFILE no existe, creando...${NC}"
        if [ "$AUTO_FIX" = true ]; then
          touch "$LOGFILE"
          chmod 600 "$LOGFILE"
          echo -e "${GREEN}[✓] Archivo de log creado: $LOGFILE${NC}"
          FIXED=$((FIXED + 1))
        fi
      else
        echo -e "${GREEN}[✓] Archivo de log existe: $LOGFILE${NC}"
      fi
      # Verificar permisos del archivo de log
      CURRENT_PERMS=$(stat -c "%a" "$LOGFILE" 2>/dev/null)
      if [ "$CURRENT_PERMS" != "600" ]; then
        echo -e "${RED}[!] Permisos incorrectos en $LOGFILE: $CURRENT_PERMS (debe ser 600)${NC}"
        if [ "$AUTO_FIX" = true ]; then
          chmod 600 "$LOGFILE"
          echo -e "${GREEN}[✓] Permisos corregidos a 600${NC}"
          FIXED=$((FIXED + 1))
        else
          WARNINGS=$((WARNINGS + 1))
        fi
      fi
    fi
  fi
}

# ==============================================
# CONFIGURACIONES ADICIONALES RECOMENDADAS
# ==============================================
check_additional_configs() {
  echo -e "\n${BLUE}[*] Verificando configuraciones adicionales de seguridad...${NC}"

  # Tiempo de espera para sudo (default 15 minutos es muy largo)
  if ! grep -q "Defaults.*timestamp_timeout" "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${YELLOW}[!] No hay timeout configurado (default 15 minutos)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo 'Defaults timestamp_timeout=5' >>"$SUDOERS_FILE"
      echo -e "${GREEN}[✓] Timeout de sudo reducido a 5 minutos${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Agregar 'Defaults timestamp_timeout=5'${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Evitar que sudo herede variables de entorno peligrosas
  if ! grep -q "Defaults.*env_reset" "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${YELLOW}[!] env_reset no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo 'Defaults env_reset' >>"$SUDOERS_FILE"
      echo -e "${GREEN}[✓] env_reset configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Agregar 'Defaults env_reset'${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Limitar grupos que pueden usar sudo
  if ! grep -q "^[^#].*ALL=(ALL)" "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${YELLOW}[!] Verificar que solo grupos autorizados tengan acceso sudo${NC}"
  fi
}

# ==============================================
# VALIDAR Y APLICAR CAMBIOS
# ==============================================
apply_changes() {
  echo -e "\n${BLUE}[*] Validando sintaxis de sudoers...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    if visudo -c &>/dev/null; then
      echo -e "${GREEN}[✓] Configuracion de sudoers valida${NC}"
    else
      echo -e "${RED}[!] Error en configuracion de sudoers, restaurando backup${NC}"
      if [ -f "$BACKUP_DIR/sudoers" ]; then
        cp "$BACKUP_DIR/sudoers" "$SUDOERS_FILE"
        echo -e "${YELLOW}[!] Backup restaurado${NC}"
      fi
      exit 1
    fi
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  SUDO HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACION:${NC}"
  echo -e "  visudo -c"
  echo -e "  sudo -l"
  echo -e "  cat /etc/sudoers | grep -E 'use_pty|logfile|timestamp_timeout'"

  echo -e "\n${YELLOW}PARA VER LOGS DE SUDO:${NC}"
  echo -e "  tail -f /var/log/sudo.log"
}

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${YELLOW}"
  echo "Este script configura hardening de sudo segun CIS Benchmark"
  echo ""
  echo "LOS CAMBIOS INCLUYEN:"
  echo "  - Uso de pseudo-terminal (pty) para evitar ataques de escape"
  echo "  - Creacion de archivo de log especifico para sudo"
  echo "  - Reduccion del timeout de autenticacion a 5 minutos"
  echo "  - Reseteo de variables de entorno"
  echo ""
  echo -e "${RED}NOTA: Se creara un backup de /etc/sudoers antes de modificar${NC}"
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
  echo -e "${GREEN}  Sudo Hardening - CIS 5.2.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ] || [ -z "$1" ]; then
    AUTO_FIX=true
    make_backup
    show_intro
    echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
  else
    AUTO_FIX=false
    echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
  fi

  check_sudo_installed
  check_sudo_pty
  check_sudo_logfile
  check_additional_configs
  apply_changes
  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
