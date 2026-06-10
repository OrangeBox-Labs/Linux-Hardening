#!/bin/bash

# ==============================================
# Script: rsyslog-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Configura rsyslog segun CIS Benchmark
#              CIS 4.2.1 - 4.2.3
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false
REMOTE_CONFIG=false

RSYSLOG_CONF="/etc/rsyslog.conf"
RSYSLOG_D_DIR="/etc/rsyslog.d"
JOURNALD_CONF="/etc/systemd/journald.conf"
BACKUP_DIR="/root/rsyslog-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0                     - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 --fix               - Modo automático (aplica las correcciones)"
  echo "  $0 -f                  - Modo automático (versión corta)"
  echo "  $0 --remote <IP>       - Configura envio de logs a servidor remoto"
  echo "  $0 --remote <IP> <PORT> - Configura envio con puerto personalizado"
  echo "  $0 --remote <IP> tcp   - Configura envio por TCP (default UDP)"
  echo ""
  echo -e "${GREEN}EJEMPLOS:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./rsyslog-hardening.sh"
  echo ""
  echo "  # Aplicar todas las correcciones"
  echo "  ./rsyslog-hardening.sh --fix"
  echo ""
  echo "  # Configurar envio a servidor remoto por UDP"
  echo "  ./rsyslog-hardening.sh --remote 192.168.1.100"
  echo ""
  echo "  # Configurar envio a servidor remoto por TCP con puerto personalizado"
  echo "  ./rsyslog-hardening.sh --remote 192.168.1.100 5514 tcp"
  echo ""
  echo "  # Primero aplicar hardening y luego configurar remoto"
  echo "  ./rsyslog-hardening.sh --fix && ./rsyslog-hardening.sh --remote 192.168.1.100"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    [ -f "$RSYSLOG_CONF" ] && cp "$RSYSLOG_CONF" "$BACKUP_DIR/"
    [ -f "$JOURNALD_CONF" ] && cp "$JOURNALD_CONF" "$BACKUP_DIR/"
    [ -d "$RSYSLOG_D_DIR" ] && cp -r "$RSYSLOG_D_DIR" "$BACKUP_DIR/"
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION GENERICA PARA CONFIGURAR PARAMETROS DE JOURNALD
# ==============================================
configure_journald_param() {
  local param="$1"
  local expected="$2"
  local description="$3"

  if grep -q "^[#]*\s*${param}=${expected}" "$JOURNALD_CONF" 2>/dev/null; then
    if grep -q "^#\s*${param}=${expected}" "$JOURNALD_CONF" 2>/dev/null; then
      echo -e "${YELLOW}[!] $description esta comentado${NC}"
      if [ "$AUTO_FIX" = true ]; then
        sed -i "s/^#\s*${param}=${expected}/${param}=${expected}/" "$JOURNALD_CONF"
        echo -e "${GREEN}[✓] $description descomentado${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${GREEN}[✓] $description${NC}"
    fi
    return 0
  fi

  if grep -q "^[#]*\s*${param}=" "$JOURNALD_CONF" 2>/dev/null; then
    echo -e "${RED}[!] $description tiene valor incorrecto${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^[#]*\s*${param}=.*/${param}=${expected}/" "$JOURNALD_CONF"
      echo -e "${GREEN}[✓] $description corregido a ${expected}${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 0
  fi

  echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
  if [ "$AUTO_FIX" = true ]; then
    echo "${param}=${expected}" >>"$JOURNALD_CONF"
    echo -e "${GREEN}[✓] $description configurado como ${expected}${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA CONFIGURAR REMOTE LOGGING
# ==============================================
configure_remote_logging() {
  local remote_host="$1"
  local remote_port="${2:-514}"
  local remote_proto="${3:-udp}"

  echo -e "\n${BLUE}[*] Configurando envio de logs a servidor remoto...${NC}"

  if [[ "$remote_proto" =~ ^[Tt][Cc][Pp]$ ]]; then
    remote_config="*.* @@$remote_host:$remote_port"
    proto_display="TCP"
  else
    remote_config="*.* @$remote_host:$remote_port"
    proto_display="UDP"
  fi

  # Verificar si ya existe configuracion remota
  if grep -q "^[^#].*@.*" "$RSYSLOG_CONF" 2>/dev/null; then
    echo -e "${YELLOW}[!] Ya existe configuracion remota en /etc/rsyslog.conf${NC}"
    echo -e "${YELLOW}    Se agregara igualmente (puede haber duplicados)${NC}"
  fi

  # Backup antes de modificar
  if [ ! -f "${BACKUP_DIR}/rsyslog.conf.bak" ]; then
    cp "$RSYSLOG_CONF" "${BACKUP_DIR}/rsyslog.conf.bak"
    echo -e "${GREEN}[✓] Backup creado: ${BACKUP_DIR}/rsyslog.conf.bak${NC}"
  fi

  # Agregar configuracion remota
  echo "" >>"$RSYSLOG_CONF"
  echo "# ==============================================" >>"$RSYSLOG_CONF"
  echo "# Envio de logs a servidor remoto (CIS 4.2.1.4)" >>"$RSYSLOG_CONF"
  echo "# Configurado: $(date)" >>"$RSYSLOG_CONF"
  echo "# Destino: $remote_host:$remote_port ($proto_display)" >>"$RSYSLOG_CONF"
  echo "$remote_config" >>"$RSYSLOG_CONF"
  echo "# ==============================================" >>"$RSYSLOG_CONF"

  echo -e "${GREEN}[✓] Configurado envio de logs a: $remote_host:$remote_port ($proto_display)${NC}"

  # Reiniciar rsyslog
  systemctl restart rsyslog 2>/dev/null
  echo -e "${GREEN}[✓] Rsyslog reiniciado${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR:${NC}"
  echo -e "  tail -f /var/log/messages | grep -i syslog"
  echo -e "  tcpdump -n port $remote_port"
}

# ==============================================
# 4.2.1.1 - ENSURE RSYSLOG IS INSTALLED
# ==============================================
check_rsyslog_installed() {
  echo -e "\n${BLUE}[*] CIS 4.2.1.1 - Verificando rsyslog instalado...${NC}"

  if rpm -q rsyslog &>/dev/null; then
    echo -e "${GREEN}[✓] rsyslog instalado${NC}"
  else
    echo -e "${RED}[!] rsyslog no instalado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if command -v dnf &>/dev/null; then
        dnf install rsyslog -y 2>/dev/null
      else
        yum install rsyslog -y 2>/dev/null
      fi
      echo -e "${GREEN}[✓] rsyslog instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Instalar rsyslog${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 4.2.1.2 - ENSURE RSYSLOG SERVICE IS ENABLED AND RUNNING
# ==============================================
check_rsyslog_enabled() {
  echo -e "\n${BLUE}[*] CIS 4.2.1.2 - Verificando rsyslog habilitado...${NC}"

  if systemctl is-enabled rsyslog &>/dev/null; then
    echo -e "${GREEN}[✓] rsyslog habilitado${NC}"
  else
    echo -e "${RED}[!] rsyslog no habilitado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      systemctl enable rsyslog
      echo -e "${GREEN}[✓] rsyslog habilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if systemctl is-active rsyslog &>/dev/null; then
    echo -e "${GREEN}[✓] rsyslog corriendo${NC}"
  else
    echo -e "${RED}[!] rsyslog no corriendo${NC}"
    if [ "$AUTO_FIX" = true ]; then
      systemctl start rsyslog
      echo -e "${GREEN}[✓] rsyslog iniciado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 4.2.1.3 - ENSURE RSYSLOG DEFAULT FILE PERMISSIONS
# ==============================================
check_file_permissions() {
  echo -e "\n${BLUE}[*] CIS 4.2.1.3 - Verificando permisos de archivos de log...${NC}"

  if grep -q "^\$FileCreateMode" "$RSYSLOG_CONF" 2>/dev/null; then
    if grep -q "^\$FileCreateMode 0640" "$RSYSLOG_CONF" 2>/dev/null; then
      echo -e "${GREEN}[✓] FileCreateMode 0640${NC}"
    else
      echo -e "${RED}[!] FileCreateMode valor incorrecto${NC}"
      if [ "$AUTO_FIX" = true ]; then
        sed -i 's/^\$FileCreateMode.*/$FileCreateMode 0640/' "$RSYSLOG_CONF"
        echo -e "${GREEN}[✓] FileCreateMode corregido a 0640${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  else
    echo -e "${RED}[!] FileCreateMode no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo '$FileCreateMode 0640' >>"$RSYSLOG_CONF"
      echo -e "${GREEN}[✓] FileCreateMode 0640 agregado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if grep -q "^\$DirCreateMode" "$RSYSLOG_CONF" 2>/dev/null; then
    if grep -q "^\$DirCreateMode 0750" "$RSYSLOG_CONF" 2>/dev/null; then
      echo -e "${GREEN}[✓] DirCreateMode 0750${NC}"
    else
      echo -e "${RED}[!] DirCreateMode valor incorrecto${NC}"
      if [ "$AUTO_FIX" = true ]; then
        sed -i 's/^\$DirCreateMode.*/$DirCreateMode 0750/' "$RSYSLOG_CONF"
        echo -e "${GREEN}[✓] DirCreateMode corregido a 0750${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  else
    echo -e "${RED}[!] DirCreateMode no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo '$DirCreateMode 0750' >>"$RSYSLOG_CONF"
      echo -e "${GREEN}[✓] DirCreateMode 0750 agregado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if grep -q "^\$Umask" "$RSYSLOG_CONF" 2>/dev/null; then
    if grep -q "^\$Umask 0027" "$RSYSLOG_CONF" 2>/dev/null; then
      echo -e "${GREEN}[✓] Umask 0027${NC}"
    else
      echo -e "${RED}[!] Umask valor incorrecto${NC}"
      if [ "$AUTO_FIX" = true ]; then
        sed -i 's/^\$Umask.*/$Umask 0027/' "$RSYSLOG_CONF"
        echo -e "${GREEN}[✓] Umask corregido a 0027${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  else
    echo -e "${YELLOW}[!] Umask no configurado (opcional)${NC}"
  fi
}

# ==============================================
# 4.2.1.4 - VERIFICAR ENVIO A REMOTO (sin configurar)
# ==============================================
check_remote_logging() {
  echo -e "\n${BLUE}[*] CIS 4.2.1.4 - Verificando envio de logs a host remoto...${NC}"

  if grep -q "^[^#].*@.*" "$RSYSLOG_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] Logs ya se envian a host remoto${NC}"
    local remote_dest=$(grep "^[^#].*@.*" "$RSYSLOG_CONF" | head -1)
    echo -e "    Destino: $remote_dest"
  else
    echo -e "${YELLOW}[!] No se detecta envio a host remoto${NC}"
    echo -e "${YELLOW}    Para configurar, ejecute: $0 --remote <IP>${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 4.2.1.5 - ENSURE REMOTE RSYSLOG MESSAGES ONLY ACCEPTED ON DESIGNATED HOSTS
# ==============================================
check_remote_accept() {
  echo -e "\n${BLUE}[*] CIS 4.2.1.5 - Verificando aceptacion de logs remotos...${NC}"

  if grep -q "^[^#].*:514" "$RSYSLOG_CONF" 2>/dev/null || grep -q "^[^#].*modload.*imtcp" "$RSYSLOG_CONF" 2>/dev/null; then
    echo -e "${YELLOW}[!] Este sistema ACEPTA logs remotos (es servidor de logs)${NC}"
    echo -e "${YELLOW}    Verificar que solo acepte de fuentes autorizadas${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] Este sistema NO acepta logs remotos (modo cliente)${NC}"
  fi
}

# ==============================================
# CONFIGURAR JOURNALD
# ==============================================
configure_journald() {
  echo -e "\n${BLUE}[*] Configurando journald...${NC}"
  echo -e "\n${YELLOW}[*] 4.2.2.1 - Verificando envio de journald a rsyslog...${NC}"
  configure_journald_param "ForwardToSyslog" "yes" "ForwardToSyslog"

  echo -e "\n${YELLOW}[*] 4.2.2.2 - Verificando compresion de archivos grandes...${NC}"
  configure_journald_param "Compress" "yes" "Compress"

  echo -e "\n${YELLOW}[*] 4.2.2.3 - Verificando almacenamiento persistente...${NC}"
  configure_journald_param "Storage" "persistent" "Storage"

  if [ "$AUTO_FIX" = true ] && [ ! -d /var/log/journal ]; then
    mkdir -p /var/log/journal
    systemctl restart systemd-journald
    echo -e "${GREEN}[✓] Directorio /var/log/journal creado${NC}"
    FIXED=$((FIXED + 1))
  fi
}

# ==============================================
# VERIFICAR PERMISOS DE LOGS (4.2.3)
# ==============================================
check_log_permissions() {
  echo -e "\n${BLUE}[*] CIS 4.2.3 - Verificando permisos de archivos de log...${NC}"

  local log_files=$(find /var/log -type f -name "*.log" 2>/dev/null | head -10)
  local issues=0

  for log in $log_files; do
    local perms=$(stat -c "%a" "$log" 2>/dev/null)
    if [ "$perms" != "640" ] && [ "$perms" != "600" ] && [ "$perms" != "644" ]; then
      echo -e "${RED}[!] Permisos incorrectos: $log ($perms)${NC}"
      issues=$((issues + 1))
    fi
  done

  if [ $issues -eq 0 ]; then
    echo -e "${GREEN}[✓] Permisos de logs correctos${NC}"
  else
    echo -e "${YELLOW}[!] Se encontraron $issues archivos con permisos incorrectos${NC}"
    if [ "$AUTO_FIX" = true ]; then
      find /var/log -type f -name "*.log" -exec chmod 640 {} \; 2>/dev/null
      echo -e "${GREEN}[✓] Permisos corregidos a 640${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# REINICIAR SERVICIOS
# ==============================================
restart_services() {
  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${BLUE}[*] Reiniciando servicios...${NC}"
    systemctl restart rsyslog
    systemctl restart systemd-journald
    echo -e "${GREEN}[✓] Servicios reiniciados${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  RSYSLOG HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VER LOGS:${NC}"
  echo -e "  tail -f /var/log/messages"
  echo -e "  journalctl -xe"

  echo -e "\n${YELLOW}PARA VER ESTADO:${NC}"
  echo -e "  systemctl status rsyslog"
  echo -e "  systemctl status systemd-journald"

  echo -e "\n${YELLOW}PARA CONFIGURAR ENVIO REMOTO:${NC}"
  echo -e "  $0 --remote <IP_HOST>"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  # Procesar opcion --remote primero (no requiere AUTO_FIX)
  if [ "$1" = "--remote" ]; then
    if [ -z "$2" ]; then
      echo -e "${RED}[!] Error: Debe especificar IP del servidor remoto${NC}"
      show_usage
      exit 1
    fi
    configure_remote_logging "$2" "$3" "$4"
    exit 0
  fi

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Rsyslog Hardening - CIS 4.2.x${NC}"
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
  else
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"
    AUTO_FIX=false
  fi

  check_rsyslog_installed
  check_rsyslog_enabled
  check_file_permissions
  check_remote_logging
  check_remote_accept
  configure_journald
  check_log_permissions
  restart_services
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
