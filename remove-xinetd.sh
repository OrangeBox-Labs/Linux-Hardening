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

      # Detener servicio
      systemctl stop xinetd 2>/dev/null
      systemctl disable xinetd 2>/dev/null

      # Eliminar paquete
      yum remove xinetd -y 2>/dev/null || dnf remove xinetd -y 2>/dev/null

      if ! rpm -q xinetd &>/dev/null; then
        echo -e "${GREEN}[✓] xinetd eliminado correctamente${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo eliminar xinetd${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: yum remove xinetd -y${NC}"
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
      yum remove inetd -y 2>/dev/null || dnf remove inetd -y 2>/dev/null
      echo -e "${GREEN}[✓] inetd eliminado${NC}"
      FIXED=$((FIXED + 1))
    else
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

      if [ "$AUTO_FIX" = true ]; then
        echo -e "${YELLOW}[*] Cerrando puerto $port...${NC}"
        # Nota: Cerrar el puerto requiere detener el servicio correspondiente
        WARNINGS=$((WARNINGS + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done
}

# ==============================================
# MOSTRAR ADVERTENCIA
# ==============================================
show_warning() {
  echo -e "${RED}============================================${NC}"
  echo -e "${RED}  ADVERTENCIA IMPORTANTE${NC}"
  echo -e "${RED}============================================${NC}"
  echo -e "${YELLOW}"
  echo "Este script eliminara xinetd y servicios innecesarios."
  echo ""
  echo "SE ELIMINARAN:"
  echo "  - xinetd (superdaemon)"
  echo "  - Servicios legacy: telnet, rsh, rlogin, tftp"
  echo "  - Servicios de xinetd: chargen, daytime, discard, echo, time"
  echo ""
  echo "SI NECESITA ALGUNO DE ESTOS SERVICIOS:"
  echo "  - No ejecute este script"
  echo "  - O comente la eliminacion especifica en el script"
  echo ""
  echo "Backup de configuraciones en: $BACKUP_DIR"
  echo ""
  echo -e "${RED}¿Desea continuar? (s/N): ${NC}"
  read -r confirm

  if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}[!] Operacion cancelada por el usuario${NC}"
    exit 0
  fi
}

# ==============================================
# MOSTRAR INSTRUCCIONES FINALES
# ==============================================
show_instructions() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR:${NC}"
  echo -e "  rpm -qa | grep xinetd"
  echo -e "  systemctl status xinetd"
  echo -e "  ss -tlnp | grep -E ':(23|513|514|69|79)'"

  echo -e "\n${YELLOW}PARA RESTAURAR XINETD:${NC}"
  echo -e "  yum install xinetd -y"
  echo -e "  cp $BACKUP_DIR/xinetd.conf /etc/"
  echo -e "  cp -r $BACKUP_DIR/xinetd.d/* /etc/xinetd.d/"
  echo -e "  systemctl start xinetd"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Hardening - Eliminacion de xinetd${NC}"
  echo -e "${GREEN}  CIS 2.1.1${NC}"
  echo -e "${GREEN}============================================${NC}"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ] || [ -z "$1" ]; then
    AUTO_FIX=true
    make_backup
    show_warning
    echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
  else
    AUTO_FIX=false
    echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
  fi

  remove_xinetd
  remove_inetd
  check_legacy_services
  check_insecure_ports

  show_instructions
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
