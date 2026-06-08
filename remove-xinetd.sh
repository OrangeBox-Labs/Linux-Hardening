#!/bin/bash

# ==============================================
# Script: remove-xinetd.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Elimina xinetd y servicios innecesarios
#              CIS 2.1.1
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/xinetd-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# LISTA DE SERVICIOS COMUNES DE XINETD
# ==============================================
XINETD_SERVICES=(
  "chargen"
  "daytime"
  "discard"
  "echo"
  "time"
  "tcpmux-server"
  "rsync"
  "swat"
  "cups-lpd"
  "tftp"
  "telnet"
)

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
  echo "  ./remove-xinetd.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./remove-xinetd.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"

    if [ -f /etc/xinetd.conf ]; then
      cp /etc/xinetd.conf "$BACKUP_DIR/"
    fi

    if [ -d /etc/xinetd.d ]; then
      cp -r /etc/xinetd.d "$BACKUP_DIR/"
    fi

    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# 2.1.1 - ELIMINAR XINETD
# ==============================================
remove_xinetd() {
  echo -e "\n${BLUE}[*] CIS 2.1.1 - Verificando xinetd...${NC}"

  if rpm -q xinetd &>/dev/null; then
    local version=$(rpm -q xinetd)
    echo -e "${RED}[!] xinetd esta instalado: $version${NC}"
    echo -e "${YELLOW}    xinetd es un superdaemon que gestiona servicios innecesarios${NC}"

    # Verificar servicios activos en xinetd
    if systemctl is-active --quiet xinetd 2>/dev/null; then
      echo -e "${RED}[!] xinetd esta activo${NC}"

      # Listar servicios de xinetd activos
      if [ -d /etc/xinetd.d ]; then
        echo -e "${YELLOW}    Servicios gestionados por xinetd:${NC}"
        for service in "${XINETD_SERVICES[@]}"; do
          if [ -f /etc/xinetd.d/"$service" ]; then
            if grep -q "disable[[:space:]]*=[[:space:]]*no" /etc/xinetd.d/"$service" 2>/dev/null; then
              echo -e "      - $service (activo)"
            fi
          fi
        done
      fi
    fi

    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Eliminando xinetd...${NC}"

      systemctl stop xinetd 2>/dev/null
      systemctl disable xinetd 2>/dev/null

      if command -v dnf &>/dev/null; then
        dnf remove xinetd -y 2>/dev/null
      else
        yum remove xinetd -y 2>/dev/null
      fi

      if ! rpm -q xinetd &>/dev/null; then
        echo -e "${GREEN}[✓] xinetd eliminado correctamente${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo eliminar xinetd${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: Eliminar xinetd${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] xinetd no esta instalado${NC}"
  fi
}

# ==============================================
# VERIFICAR Y ELIMINAR INETD (alternativa antigua)
# ==============================================
remove_inetd() {
  echo -e "\n${BLUE}[*] Verificando inetd (alternativa antigua)...${NC}"

  if rpm -q inetd &>/dev/null; then
    echo -e "${RED}[!] inetd esta instalado${NC}"

    if [ "$AUTO_FIX" = true ]; then
      if command -v dnf &>/dev/null; then
        dnf remove inetd -y 2>/dev/null
      else
        yum remove inetd -y 2>/dev/null
      fi
      echo -e "${GREEN}[✓] inetd eliminado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Eliminar inetd${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] inetd no esta instalado${NC}"
  fi
}

# ==============================================
# VERIFICAR SERVICIOS XINETD RESIDUALES
# ==============================================
check_legacy_services() {
  echo -e "\n${BLUE}[*] Verificando servicios legacy...${NC}"

  local legacy_services=(
    "telnet"
    "rsh"
    "rlogin"
    "rexec"
    "tftp"
    "finger"
    "talk"
    "ntalk"
  )

  for service in "${legacy_services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      echo -e "${RED}[!] Servicio legacy activo: $service${NC}"

      if [ "$AUTO_FIX" = true ]; then
        systemctl stop "$service" 2>/dev/null
        systemctl disable "$service" 2>/dev/null
        echo -e "${GREEN}[✓] $service detenido y deshabilitado${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${YELLOW}    Recomendacion: Detener $service${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done
}

# ==============================================
# VERIFICAR PUERTOS INSEGUROS
# ==============================================
check_insecure_ports() {
  echo -e "\n${BLUE}[*] Verificando puertos inseguros...${NC}"

  local insecure_ports=(
    "23:telnet"
    "513:rlogin"
    "514:rsh"
    "69:tftp"
    "79:finger"
  )

  for port_info in "${insecure_ports[@]}"; do
    port="${port_info%%:*}"
    service="${port_info##*:}"

    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
      echo -e "${RED}[!] Puerto inseguro abierto: $port ($service)${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
}

# ==============================================
# MOSTRAR RESUMEN FINAL
# ==============================================
show_instructions() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR:${NC}"
  echo -e "  rpm -qa | grep xinetd"
  echo -e "  systemctl status xinetd"
  echo -e "  ss -tlnp | grep -E ':(23|513|514|69|79)'"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Hardening - Eliminacion de xinetd${NC}"
  echo -e "${GREEN}  CIS 2.1.1${NC}"
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
  remove_xinetd
  remove_inetd
  check_legacy_services
  check_insecure_ports

  show_instructions

  if [ "$AUTO_FIX" = false ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
