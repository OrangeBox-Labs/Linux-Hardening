#!/bin/bash

OB_COMPAT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$OB_COMPAT_DIR/lib/service-compat.sh" ]; then
  # shellcheck source=lib/service-compat.sh
  . "$OB_COMPAT_DIR/lib/service-compat.sh"
else
  echo "[ERROR] Falta lib/service-compat.sh; actualice el repositorio completo." >&2
  exit 1
fi

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

# Mitigación operativa para ntpd legacy en EL6: refresco periódico del servicio.
NTP_REFRESH_CRON="/etc/cron.d/orangebox-ntp-refresh"
NTPD_RESTART_PATTERN='(service[[:space:]]+ntpd[[:space:]]+restart|/etc/init[.]d/ntpd[[:space:]]+restart|systemctl[[:space:]]+restart[[:space:]]+ntpd)'
NTPD_REFRESH_CRON_LINE='17 */6 * * * root if /sbin/service ntpd restart >/dev/null 2>&1; then /bin/logger -t orangebox-ntp-refresh "ntpd restart OK"; else /bin/logger -p daemon.err -t orangebox-ntp-refresh "ntpd restart FAILED"; fi'

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
  echo "  $0 --refresh-only - Solo valida/instala el cron de refresco ntpd de EL6"
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
    if [ -f "$NTP_REFRESH_CRON" ]; then
      cp "$NTP_REFRESH_CRON" "$BACKUP_DIR/"
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

  # EL8+ uses the vendor's systemd unit and does not require a literal -u chrony in sysconfig.
  local os_major=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    os_major="${VERSION_ID%%.*}"
  fi
  if [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -ge 8 ]; then
    echo -e "${GREEN}[✓] EL8+: se conserva la gestión de privilegios de la unidad chronyd del proveedor${NC}"
  elif [ -f /etc/sysconfig/chronyd ]; then
    if grep -Eq '^[[:space:]]*OPTIONS=.*-u[[:space:]]+chrony' /etc/sysconfig/chronyd; then
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
# REFRESCO PERIODICO DE NTP PARA EL LEGACY EL6
# ==============================================
detect_os_major_for_ntp_refresh() {
  local major=""

  if [ -r /etc/os-release ]; then
    major="$(sed -nE 's/^VERSION_ID="?([0-9]+)(\.[^"]*)?"?$/\1/p' /etc/os-release | head -n 1)"
  fi

  if [ -z "$major" ] && [ -r /etc/redhat-release ]; then
    major="$(sed -n 's/.*release[[:space:]]\([0-9][0-9]*\).*/\1/p' /etc/redhat-release | head -n 1)"
  fi

  printf '%s\n' "$major"
}

ntpd_restart_job_source() {
  local source=""

  # Revisar los cron.d, el crontab del sistema y los spool de usuarios.
  for source in /etc/crontab /etc/cron.d/* /var/spool/cron/*; do
    [ -f "$source" ] || continue
    if grep -Eiv '^[[:space:]]*#' "$source" 2>/dev/null | grep -Eiq "$NTPD_RESTART_PATTERN"; then
      printf '%s\n' "$source"
      return 0
    fi
  done

  if command -v crontab >/dev/null 2>&1 &&
     crontab -l -u root 2>/dev/null | grep -Eiv '^[[:space:]]*#' | grep -Eiq "$NTPD_RESTART_PATTERN"; then
    printf '%s\n' "crontab de root"
    return 0
  fi

  return 1
}

configure_legacy_ntp_refresh() {
  local os_major="" job_source=""

  os_major="$(detect_os_major_for_ntp_refresh)"
  # Aplicar solo al sistema legacy EL6 que usa el paquete ntp/ntpd.
  if [ "$os_major" != "6" ] || ! rpm -q ntp &>/dev/null; then
    return 0
  fi

  echo -e "\n${BLUE}[*] Verificando refresco periódico de ntpd para EL6...${NC}"

  if job_source="$(ntpd_restart_job_source)"; then
    echo -e "${GREEN}[✓] Ya existe una tarea de reinicio de ntpd: $job_source${NC}"
    return 0
  fi

  if [ "$AUTO_FIX" != true ]; then
    echo -e "${YELLOW}[!] No se detectó un reinicio periódico de ntpd en cron; --fix agregará uno cada 6 horas.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if [ -L "$NTP_REFRESH_CRON" ] || { [ -e "$NTP_REFRESH_CRON" ] && [ ! -f "$NTP_REFRESH_CRON" ]; }; then
    echo -e "${RED}[!] No se puede instalar el cron de ntpd: $NTP_REFRESH_CRON no es un archivo regular.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if ! mkdir -p /etc/cron.d; then
    echo -e "${RED}[!] No se pudo preparar /etc/cron.d para el refresco de ntpd.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if [ -f "$NTP_REFRESH_CRON" ] && [ ! -f "$BACKUP_DIR/$(basename "$NTP_REFRESH_CRON")" ]; then
    if ! mkdir -p "$BACKUP_DIR" || ! cp -p "$NTP_REFRESH_CRON" "$BACKUP_DIR/"; then
      echo -e "${RED}[!] No se pudo respaldar $NTP_REFRESH_CRON; se cancela el cambio.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  fi

  if [ -f "$NTP_REFRESH_CRON" ]; then
    {
      printf '\n# OrangeBox: refresco periódico de ntpd legacy cada 6 horas\n'
      printf '%s\n' "$NTPD_REFRESH_CRON_LINE"
    } >> "$NTP_REFRESH_CRON"
  else
    cat > "$NTP_REFRESH_CRON" <<EOF
# OrangeBox: refresco periódico de ntpd legacy cada 6 horas
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
$NTPD_REFRESH_CRON_LINE
EOF
  fi

  if chown root:root "$NTP_REFRESH_CRON" && chmod 644 "$NTP_REFRESH_CRON" &&
     job_source="$(ntpd_restart_job_source)"; then
    echo -e "${GREEN}[✓] Refresco periódico configurado en $NTP_REFRESH_CRON (cada 6 horas).${NC}"
    echo -e "${YELLOW}[INFO] El resultado se registra en syslog con la etiqueta orangebox-ntp-refresh.${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] No se pudo validar la tarea periódica de ntpd tras configurarla.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
}

# ==============================================
# INICIAR Y HABILITAR SERVICIO
# ==============================================
start_service() {
  echo -e "\n${BLUE}[*] Iniciando servicio de sincronizacion...${NC}"

  local svc="" rc
  if rpm -q chrony &>/dev/null; then
    svc=chronyd
  elif rpm -q ntp &>/dev/null; then
    svc=ntpd
  else
    echo -e "${YELLOW}[!] No hay paquete chrony/ntp para comprobar servicio${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if ob_service_is_enabled "$svc"; then
    echo -e "${GREEN}[✓] $svc habilitado${NC}"
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then
      echo -e "${YELLOW}[!] No se pudo determinar si $svc está habilitado (sin gestor compatible)${NC}"
      WARNINGS=$((WARNINGS + 1))
    elif [ "$AUTO_FIX" = true ]; then
      if ob_service_enable "$svc"; then
        echo -e "${GREEN}[✓] $svc habilitado${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo habilitar $svc${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${RED}[!] $svc no está habilitado${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if ob_service_is_active "$svc"; then
    echo -e "${GREEN}[✓] $svc está corriendo${NC}"
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then
      echo -e "${YELLOW}[!] No se pudo determinar si $svc está corriendo${NC}"
      WARNINGS=$((WARNINGS + 1))
    elif [ "$AUTO_FIX" = true ]; then
      if ob_service_start "$svc"; then
        echo -e "${GREEN}[✓] $svc iniciado${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo iniciar $svc${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${RED}[!] $svc no está corriendo${NC}"
      WARNINGS=$((WARNINGS + 1))
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
    echo -e "${YELLOW}[INFO] Modo auditoría: no se fuerza un ajuste inmediato del reloj; se comprueba el estado a continuación.${NC}"
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

  if [ "$1" = "--refresh-only" ]; then
    local refresh_os_major=""
    AUTO_FIX=true
    refresh_os_major="$(detect_os_major_for_ntp_refresh)"
    if [ "$refresh_os_major" != "6" ] || ! rpm -q ntp &>/dev/null; then
      echo -e "${YELLOW}[INFO] --refresh-only aplica solo a EL6 con el paquete ntp; no se realizaron cambios.${NC}"
      exit 0
    fi
    configure_legacy_ntp_refresh
    exit $?
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
  configure_legacy_ntp_refresh
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
