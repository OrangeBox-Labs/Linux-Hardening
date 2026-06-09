#!/bin/bash

# ==============================================
# Script: configure-time-sync.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Configura sincronizacion de tiempo
#              CIS 2.2.1.1, 2.2.1.2
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/time-backup-$(date +%Y%m%d-%H%M%S)"

# Servidores NTP (pool sudamericano)
NTP_SERVERS=(
  "time.google.com"
  "pool.ntp.org"
  "south-america.pool.ntp.org"
  "cl.pool.ntp.org"
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
  echo "  ./configure-time-sync.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./configure-time-sync.sh --fix"
  echo ""
}

# ==============================================
# CREAR BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"

    if [ -f /etc/chrony.conf ]; then
      cp /etc/chrony.conf "$BACKUP_DIR/"
    fi
    if [ -f /etc/sysconfig/chronyd ]; then
      cp /etc/sysconfig/chronyd "$BACKUP_DIR/"
    fi
    if [ -f /etc/ntp.conf ]; then
      cp /etc/ntp.conf "$BACKUP_DIR/"
    fi
    if [ -f /etc/sysconfig/ntpd ]; then
      cp /etc/sysconfig/ntpd "$BACKUP_DIR/"
    fi

    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# MOSTRAR ADVERTENCIA CON CUENTA REGRESIVA
# ==============================================
show_warning() {
  echo -e "${RED}============================================${NC}"
  echo -e "${RED}  ADVERTENCIA IMPORTANTE${NC}"
  echo -e "${RED}============================================${NC}"
  echo -e "${YELLOW}"
  echo "Este script configurara la sincronizacion de tiempo."
  echo ""
  echo "SE CONFIGURARA:"
  echo "  - Instalacion de chrony o NTP"
  echo "  - Servidores NTP: time.google.com, pool.ntp.org"
  echo "  - Sincronizacion automatica"
  echo ""
  echo "Backup de configuraciones en: $BACKUP_DIR"
  echo ""
  echo -e "${RED}============================================${NC}"
  echo -e "${YELLOW}El script comenzara en 3 segundos...${NC}"
  echo -e "${YELLOW}Presione Ctrl+C para cancelar${NC}"
  echo -e "${RED}============================================${NC}"

  for i in 3 2 1; do
    echo -ne "${YELLOW}  $i...${NC}\r"
    sleep 1
  done
  echo -e "${GREEN}  Ejecutando...${NC}\n"
}

# ==============================================
# 2.2.1.1 - INSTALAR CHRONY O NTP
# ==============================================
install_time_sync() {
  echo -e "\n${BLUE}[*] CIS 2.2.1.1 - Verificando sincronizacion de tiempo...${NC}"

  local chrony_installed=false
  local ntp_installed=false

  if rpm -q chrony &>/dev/null; then
    chrony_installed=true
    echo -e "${GREEN}[✓] chrony esta instalado${NC}"
  fi

  if rpm -q ntp &>/dev/null; then
    ntp_installed=true
    echo -e "${GREEN}[✓] ntp esta instalado${NC}"
  fi

  if [ "$chrony_installed" = true ] && [ "$ntp_installed" = true ]; then
    echo -e "${YELLOW}[!] Ambos paquetes estan instalados (solo debe haber uno)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Eliminando ntp para quedarse con chrony...${NC}"
      yum remove ntp -y 2>/dev/null || dnf remove ntp -y 2>/dev/null
      echo -e "${GREEN}[✓] ntp eliminado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Eliminar ntp o chrony${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$chrony_installed" = false ] && [ "$ntp_installed" = false ]; then
    echo -e "${RED}[!] No hay sistema de sincronizacion de tiempo instalado${NC}"

    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Instalando chrony...${NC}"
      yum install chrony -y 2>/dev/null || dnf install chrony -y 2>/dev/null
      if rpm -q chrony &>/dev/null; then
        echo -e "${GREEN}[✓] chrony instalado correctamente${NC}"
        chrony_installed=true
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo instalar chrony${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: yum install chrony -y${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Retornar que servicio esta instalado
  if [ "$chrony_installed" = true ]; then
    return 0
  elif [ "$ntp_installed" = true ]; then
    return 1
  else
    return 2
  fi
}

# ==============================================
# 2.2.1.2 - CONFIGURAR CHRONY
# ==============================================
configure_chrony() {
  echo -e "\n${BLUE}[*] CIS 2.2.1.2 - Configurando chrony...${NC}"

  if ! rpm -q chrony &>/dev/null; then
    echo -e "${YELLOW}[!] chrony no instalado, omitiendo configuracion${NC}"
    return
  fi

  local needs_fix=0

  # Verificar /etc/chrony.conf
  if [ -f /etc/chrony.conf ]; then
    if grep -q "^server" /etc/chrony.conf || grep -q "^pool" /etc/chrony.conf; then
      echo -e "${GREEN}[✓] chrony.conf tiene servidores configurados${NC}"
    else
      echo -e "${RED}[!] chrony.conf no tiene servidores configurados${NC}"
      needs_fix=1
    fi
  else
    echo -e "${RED}[!] /etc/chrony.conf no existe${NC}"
    needs_fix=1
  fi

  # Verificar /etc/sysconfig/chronyd
  if [ -f /etc/sysconfig/chronyd ]; then
    if grep -q "OPTIONS.*-u chrony" /etc/sysconfig/chronyd; then
      echo -e "${GREEN}[✓] chronyd configurado para ejecutar como usuario chrony${NC}"
    else
      echo -e "${RED}[!] chronyd no tiene la opcion -u chrony${NC}"
      needs_fix=1
    fi
  else
    echo -e "${RED}[!] /etc/sysconfig/chronyd no existe${NC}"
    needs_fix=1
  fi

  if [ $needs_fix -eq 1 ] && [ "$AUTO_FIX" = true ]; then
    echo -e "${YELLOW}[*] Configurando chrony...${NC}"

    cat >/etc/chrony.conf <<EOF
# Servidores NTP configurados por hardening
server time.google.com iburst
server pool.ntp.org iburst
server south-america.pool.ntp.org iburst
server cl.pool.ntp.org iburst

# Permitir solo ajustes locales
allow 127.0.0.1

# Registrar estadisticas
logdir /var/log/chrony
log measurements statistics tracking

# Configuraciones adicionales
makestep 1 3
rtcsync
EOF
    echo -e "${GREEN}[✓] chrony.conf configurado${NC}"

    echo 'OPTIONS="-u chrony"' >/etc/sysconfig/chronyd
    echo -e "${GREEN}[✓] chronyd configurado${NC}"

    chown root:root /etc/chrony.conf
    chmod 644 /etc/chrony.conf
    chown root:root /etc/sysconfig/chronyd
    chmod 644 /etc/sysconfig/chronyd

    FIXED=$((FIXED + 1))
  elif [ $needs_fix -eq 1 ]; then
    echo -e "${YELLOW}    Recomendacion: Configurar /etc/chrony.conf y /etc/sysconfig/chronyd${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR NTP (alternativa)
# ==============================================
configure_ntp() {
  echo -e "\n${BLUE}[*] Configurando ntp...${NC}"

  if ! rpm -q ntp &>/dev/null; then
    echo -e "${YELLOW}[!] ntp no instalado, omitiendo configuracion${NC}"
    return
  fi

  local needs_fix=0

  if [ -f /etc/ntp.conf ]; then
    if grep -q "^server" /etc/ntp.conf; then
      echo -e "${GREEN}[✓] ntp.conf tiene servidores configurados${NC}"
    else
      echo -e "${RED}[!] ntp.conf no tiene servidores configurados${NC}"
      needs_fix=1
    fi
  else
    echo -e "${RED}[!] /etc/ntp.conf no existe${NC}"
    needs_fix=1
  fi

  if [ $needs_fix -eq 1 ] && [ "$AUTO_FIX" = true ]; then
    cat >/etc/ntp.conf <<EOF
# Servidores NTP configurados por hardening
server time.google.com iburst
server pool.ntp.org iburst
server south-america.pool.ntp.org iburst
server cl.pool.ntp.org iburst

# Restringir acceso
restrict -4 default kod nomodify notrap nopeer noquery
restrict -6 default kod nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1

# Configuraciones adicionales
driftfile /var/lib/ntp/drift
logfile /var/log/ntp.log
EOF

    echo 'OPTIONS="-u ntp:ntp -p /var/run/ntpd.pid"' >/etc/sysconfig/ntpd

    echo -e "${GREEN}[✓] ntp configurado${NC}"
    FIXED=$((FIXED + 1))
  elif [ $needs_fix -eq 1 ]; then
    echo -e "${YELLOW}    Recomendacion: Configurar /etc/ntp.conf${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# INICIAR Y HABILITAR SERVICIO
# ==============================================
start_service() {
  echo -e "\n${BLUE}[*] Iniciando servicio de sincronizacion...${NC}"

  if rpm -q chrony &>/dev/null; then
    if systemctl is-enabled chronyd &>/dev/null; then
      echo -e "${GREEN}[✓] chronyd ya esta habilitado${NC}"
    else
      echo -e "${RED}[!] chronyd no esta habilitado${NC}"
      if [ "$AUTO_FIX" = true ]; then
        systemctl enable chronyd
        echo -e "${GREEN}[✓] chronyd habilitado${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi

    if systemctl is-active chronyd &>/dev/null; then
      echo -e "${GREEN}[✓] chronyd esta corriendo${NC}"
    else
      echo -e "${RED}[!] chronyd no esta corriendo${NC}"
      if [ "$AUTO_FIX" = true ]; then
        systemctl restart chronyd
        echo -e "${GREEN}[✓] chronyd iniciado${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  elif rpm -q ntp &>/dev/null; then
    if systemctl is-enabled ntpd &>/dev/null; then
      echo -e "${GREEN}[✓] ntpd ya esta habilitado${NC}"
    else
      echo -e "${RED}[!] ntpd no esta habilitado${NC}"
      if [ "$AUTO_FIX" = true ]; then
        systemctl enable ntpd
        echo -e "${GREEN}[✓] ntpd habilitado${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi

    if systemctl is-active ntpd &>/dev/null; then
      echo -e "${GREEN}[✓] ntpd esta corriendo${NC}"
    else
      echo -e "${RED}[!] ntpd no esta corriendo${NC}"
      if [ "$AUTO_FIX" = true ]; then
        systemctl restart ntpd
        echo -e "${GREEN}[✓] ntpd iniciado${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  fi
}

# ==============================================
# FORZAR SINCRONIZACION INMEDIATA
# ==============================================
force_sync() {
  echo -e "\n${BLUE}[*] Forzando sincronizacion de tiempo...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    if command -v chronyc &>/dev/null; then
      chronyc makestep 2>/dev/null
      echo -e "${GREEN}[✓] Sincronizacion forzada con chrony${NC}"
    elif command -v ntpdate &>/dev/null; then
      ntpdate -u time.google.com 2>/dev/null
      echo -e "${GREEN}[✓] Sincronizacion forzada con ntpdate${NC}"
    else
      echo -e "${YELLOW}[!] No se encontro herramienta de sincronizacion${NC}"
      echo -e "${YELLOW}[*] Instalando ntpdate...${NC}"
      yum install ntpdate -y 2>/dev/null || dnf install ntpdate -y 2>/dev/null
      ntpdate -u time.google.com 2>/dev/null
      echo -e "${GREEN}[✓] Sincronizacion forzada${NC}"
    fi
  else
    echo -e "${YELLOW}    Recomendacion: chronyc makestep o ntpdate -u time.google.com${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# VERIFICAR ESTADO
# ==============================================
check_status() {
  echo -e "\n${BLUE}[*] Verificando estado de sincronizacion...${NC}"

  if command -v chronyc &>/dev/null; then
    if chronyc tracking 2>/dev/null | grep -E "Reference time|Stratum" >/dev/null; then
      chronyc tracking 2>/dev/null | grep -E "Reference time|Stratum"
      echo -e "${GREEN}[✓] chrony sincronizado correctamente${NC}"
    else
      echo -e "${YELLOW}[!] chrony no esta sincronizado aun (puede tomar unos minutos)${NC}"
    fi
  elif command -v ntpq &>/dev/null; then
    if ntpq -p 2>/dev/null | grep -E "^\*" >/dev/null; then
      ntpq -p 2>/dev/null | head -5
      echo -e "${GREEN}[✓] ntp sincronizado correctamente${NC}"
    else
      echo -e "${YELLOW}[!] ntp no esta sincronizado aun (puede tomar unos minutos)${NC}"
    fi
  fi
}

# ==============================================
# MOSTRAR RESUMEN FINAL
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  CONFIGURACION DE TIEMPO COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR ESTADO:${NC}"
  echo -e "  chronyc tracking"
  echo -e "  ntpq -p"
  echo -e "  timedatectl status"

  echo -e "\n${YELLOW}PARA FORZAR SINCRONIZACION:${NC}"
  echo -e "  chronyc makestep"
  echo -e "  ntpdate -u time.google.com"

  echo -e "\n${YELLOW}PARA VER LOGS:${NC}"
  echo -e "  journalctl -u chronyd -f"
  echo -e "  journalctl -u ntpd -f"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${YELLOW}PARA RESTAURAR BACKUP:${NC}"
    echo -e "  cp $BACKUP_DIR/* /etc/"
  fi

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Configuracion de Sincronizacion de Tiempo${NC}"
  echo -e "${GREEN}  CIS 2.2.1.1 - 2.2.1.2${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
    make_backup
    show_warning
  else
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"
    AUTO_FIX=false
  fi

  install_time_sync
  local time_service=$?

  if [ $time_service -eq 0 ]; then
    configure_chrony
  elif [ $time_service -eq 1 ]; then
    configure_ntp
  fi

  start_service
  force_sync
  check_status

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
