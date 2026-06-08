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
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 --fix      - Modo automático (aplica las correcciones)"
  echo "  $0 -f         - Modo automático (versión corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./sudo-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./sudo-hardening.sh --fix"
  echo ""
}

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
      if command -v dnf &>/dev/null; then
        dnf install sudo -y 2>/dev/null
      else
        yum install sudo -y 2>/dev/null
      fi
      echo -e "${GREEN}[✓] sudo instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Instalar sudo${NC}"
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

  if grep -q "logfile" "$SUDOERS_FILE" 2>/dev/null; then
    LOGFILE=$(grep "logfile" "$SUDOERS_FILE" | grep -v "^#" | awk -F'"' '{print $2}')
    if [ -n "$LOGFILE" ]; then
      if [ ! -f "$LOGFILE" ]; then
        echo -e "${YELLOW}[!] Archivo de log $LOGFILE no existe${NC}"
        if [ "$AUTO_FIX" = true ]; then
          touch "$LOGFILE"
          chmod 600 "$LOGFILE"
          echo -e "${GREEN}[✓] Archivo de log creado: $LOGFILE${NC}"
          FIXED=$((FIXED + 1))
        else
          WARNINGS=$((WARNINGS + 1))
        fi
      else
        echo -e "${GREEN}[✓] Archivo de log existe: $LOGFILE${NC}"
      fi

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

  # Tiempo de espera para sudo
  if ! grep -q "Defaults.*timestamp_timeout" "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${RED}[!] timeout de sudo NO CONFIGURADO (default 15 minutos)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo 'Defaults timestamp_timeout=5' >>"$SUDOERS_FILE"
      echo -e "${GREEN}[✓] Timeout de sudo reducido a 5 minutos${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Agregar 'Defaults timestamp_timeout=5'${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] Timeout de sudo configurado${NC}"
  fi

  # env_reset
  if ! grep -q "Defaults.*env_reset" "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${RED}[!] env_reset NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo 'Defaults env_reset' >>"$SUDOERS_FILE"
      echo -e "${GREEN}[✓] env_reset configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Agregar 'Defaults env_reset'${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] env_reset configurado${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  SUDO HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACION:${NC}"
  echo -e "  visudo -c"
  echo -e "  sudo -l"
  echo -e "  grep -E 'use_pty|logfile|timestamp_timeout|env_reset' /etc/sudoers"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Sudo Hardening - CIS 5.2.x${NC}"
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
    AUTO_FIX=false
  fi

  # Modo automático (--fix o -f)
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
    make_backup
  fi

  # Ejecutar verificaciones/correcciones
  check_sudo_installed
  check_sudo_pty
  check_sudo_logfile
  check_additional_configs
  validate_sudoers

  show_summary

  if [ "$AUTO_FIX" = false ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
