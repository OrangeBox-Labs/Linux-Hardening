#!/bin/bash

# ==============================================
# Script: rsyslog-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
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

RSYSLOG_CONF="/etc/rsyslog.conf"
RSYSLOG_D_DIR="/etc/rsyslog.d"
JOURNALD_CONF="/etc/systemd/journald.conf"
BACKUP_DIR="/root/rsyslog-backup-$(date +%Y%m%d-%H%M%S)"

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
  echo "  ./rsyslog-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./rsyslog-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    if [ -f "$RSYSLOG_CONF" ]; then
      cp "$RSYSLOG_CONF" "$BACKUP_DIR/"
    fi
    if [ -f "$JOURNALD_CONF" ]; then
      cp "$JOURNALD_CONF" "$BACKUP_DIR/"
    fi
    if [ -d "$RSYSLOG_D_DIR" ]; then
      cp -r "$RSYSLOG_D_DIR" "$BACKUP_DIR/"
    fi
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
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

  # Verificar o agregar directiva $FileCreateMode
  if grep -q "^\$FileCreateMode" "$RSYSLOG_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] FileCreateMode configurado${NC}"
  else
    echo -e "${RED}[!] FileCreateMode no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo "\$FileCreateMode 0640" >>"$RSYSLOG_CONF"
      echo -e "${GREEN}[✓] FileCreateMode 0640 agregado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Verificar o agregar directiva $DirCreateMode
  if grep -q "^\$DirCreateMode" "$RSYSLOG_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] DirCreateMode configurado${NC}"
  else
    echo -e "${RED}[!] DirCreateMode no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo "\$DirCreateMode 0750" >>"$RSYSLOG_CONF"
      echo -e "${GREEN}[✓] DirCreateMode 0750 agregado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Verificar umask
  if grep -q "^\$Umask" "$RSYSLOG_CONF" 2>/dev/null; then
    if grep -q "^\$Umask 0027" "$RSYSLOG_CONF" 2>/dev/null; then
      echo -e "${GREEN}[✓] Umask correcta (0027)${NC}"
    else
      echo -e "${RED}[!] Umask incorrecta${NC}"
      if [ "$AUTO_FIX" = true ]; then
        sed -i 's/^\$Umask.*/\$Umask 0027/' "$RSYSLOG_CONF"
        echo -e "${GREEN}[✓] Umask corregida a 0027${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  fi
}

# ==============================================
# 4.2.1.4 - ENSURE RSYSLOG CONFIGURED TO SEND LOGS TO REMOTE HOST
# ==============================================
check_remote_logging() {
  echo -e "\n${BLUE}[*] CIS 4.2.1.4 - Verificando envio de logs a host remoto...${NC}"

  if grep -q "^[^#].*@.*" "$RSYSLOG_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] Logs ya se envian a host remoto${NC}"
    local remote_dest=$(grep "^[^#].*@.*" "$RSYSLOG_CONF" | head -1)
    echo -e "    Destino: $remote_dest"
    return 0
  fi

  echo -e "${YELLOW}[!] No se detecta envio a host remoto${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${YELLOW}¿Desea configurar envio de logs a un servidor remoto? (s/N): ${NC}"
    read -r configure_remote

    if [[ "$configure_remote" =~ ^[Ss]$ ]]; then
      echo -e "${YELLOW}Ingrese la IP o hostname del servidor de logs remoto:${NC}"
      read -r remote_host

      if [ -n "$remote_host" ]; then
        echo -e "\n${YELLOW}¿Que puerto desea usar? (default: 514): ${NC}"
        read -r remote_port
        [ -z "$remote_port" ] && remote_port="514"

        echo -e "\n${YELLOW}¿Usar TCP o UDP? (tcp/udp default: udp): ${NC}"
        read -r remote_proto

        if [[ "$remote_proto" =~ ^[Tt][Cc][Pp]$ ]]; then
          remote_config="*.* @@$remote_host:$remote_port"
        else
          remote_config="*.* @$remote_host:$remote_port"
        fi

        echo "" >>"$RSYSLOG_CONF"
        echo "# Envio de logs a servidor remoto (CIS 4.2.1.4)" >>"$RSYSLOG_CONF"
        echo "$remote_config" >>"$RSYSLOG_CONF"

        echo -e "${GREEN}[✓] Configurado envio de logs a: $remote_host:$remote_port ($remote_proto)${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se ingreso destino remoto, omitiendo configuracion${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}[!] Configuracion remota omitida${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
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

  # 4.2.2.1 - ENSURE JOURNALD SENT TO RSYSLOG
  echo -e "\n${YELLOW}[*] 4.2.2.1 - Verificando envio de journald a rsyslog...${NC}"

  if grep -q "^[#]*\s*ForwardToSyslog=yes" "$JOURNALD_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] ForwardToSyslog=yes${NC}"
  else
    echo -e "${RED}[!] ForwardToSyslog no configurado correctamente${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if grep -q "^[#]*\s*ForwardToSyslog" "$JOURNALD_CONF"; then
        sed -i 's/^[#]*\s*ForwardToSyslog.*/ForwardToSyslog=yes/' "$JOURNALD_CONF"
      else
        echo "ForwardToSyslog=yes" >>"$JOURNALD_CONF"
      fi
      echo -e "${GREEN}[✓] ForwardToSyslog=yes configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # 4.2.2.2 - ENSURE JOURNALD COMPRESS LARGE FILES
  echo -e "\n${YELLOW}[*] 4.2.2.2 - Verificando compresion de archivos grandes...${NC}"

  if grep -q "^[#]*\s*Compress=yes" "$JOURNALD_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] Compress=yes${NC}"
  else
    echo -e "${RED}[!] Compress no configurado correctamente${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if grep -q "^[#]*\s*Compress" "$JOURNALD_CONF"; then
        sed -i 's/^[#]*\s*Compress.*/Compress=yes/' "$JOURNALD_CONF"
      else
        echo "Compress=yes" >>"$JOURNALD_CONF"
      fi
      echo -e "${GREEN}[✓] Compress=yes configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # 4.2.2.3 - ENSURE JOURNALD WRITE LOGFILES TO PERSISTENT DISK
  echo -e "\n${YELLOW}[*] 4.2.2.3 - Verificando almacenamiento persistente...${NC}"

  if grep -q "^[#]*\s*Storage=persistent" "$JOURNALD_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] Storage=persistent${NC}"
  else
    echo -e "${RED}[!] Storage no configurado como persistente${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if grep -q "^[#]*\s*Storage" "$JOURNALD_CONF"; then
        sed -i 's/^[#]*\s*Storage.*/Storage=persistent/' "$JOURNALD_CONF"
      else
        echo "Storage=persistent" >>"$JOURNALD_CONF"
      fi
      echo -e "${GREEN}[✓] Storage=persistent configurado${NC}"
      mkdir -p /var/log/journal
      systemctl restart systemd-journald
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
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
  echo -e "${GREEN}  Rsyslog Hardening - CIS 4.2.x${NC}"
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
