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
RSYSLOG_CONFIG_CHANGED=false
JOURNALD_CONFIG_CHANGED=false

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
confirm_rsyslog_change() {
  local control="$1" effect="$2" answer=""
  echo -e "\n$YELLOW[CONFIRMACIÓN REQUERIDA]$NC $control"
  echo "Qué hace/riesgo: $effect"
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "$YELLOW[WARN] No hay terminal interactiva; se omite el cambio por seguridad.$NC"
    return 1
  fi
  printf '¿Confirmas este cambio? [s/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) echo -e "$BLUE[INFO] Cambio rechazado; se conserva el estado actual.$NC"; return 1 ;;
  esac
}

journald_param_inventory() {
  local param="$1" file
  for file in "$JOURNALD_CONF" /usr/lib/systemd/journald.conf.d/*.conf /usr/local/lib/systemd/journald.conf.d/*.conf /run/systemd/journald.conf.d/*.conf /etc/systemd/journald.conf.d/*.conf; do
    [ -f "$file" ] || continue
    awk -v path="$file" -v param="$param" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      /^[ \t]*[#;]/ { next }
      /^[ \t]*\[/ {
        section=tolower(trim($0))
        gsub(/[\[\] \t]/, "", section)
        next
      }
      section == "journal" {
        line=$0
        eq=index(line, "=")
        if (!eq) next
        key=trim(substr(line,1,eq-1))
        if (key != param) next
        value=trim(substr(line,eq+1))
        sub(/[ \t]*[#;].*$/, "", value)
        current=trim(value)
      }
      END { if (current != "") printf "%s|%s\n", path, current }
    ' "$file" 2>/dev/null
  done
}

journald_set_main_param() {
  local param="$1" expected="$2" tmp mode
  [ ! -L "$JOURNALD_CONF" ] || { echo -e "$RED[!] $JOURNALD_CONF es symlink; no se modifica automáticamente.$NC"; return 1; }
  tmp="$(mktemp "$JOURNALD_CONF.orangebox.XXXXXX")" || return 1
  if [ -f "$JOURNALD_CONF" ]; then
    awk -v param="$param" -v expected="$expected" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      function ensure_value() { if (section == "journal" && !written) { print param "=" expected; written=1 } }
      /^[ \t]*\[/ {
        ensure_value()
        section=tolower(trim($0))
        gsub(/[\[\] \t]/, "", section)
        if (section == "journal") journal_seen=1
        print
        next
      }
      section == "journal" && $0 !~ /^[ \t]*[#;]/ {
        line=$0
        eq=index(line, "=")
        if (eq) {
          key=trim(substr(line,1,eq-1))
          if (key == param) {
            if (!written) { print param "=" expected; written=1 }
            next
          }
        }
      }
      { print }
      END {
        ensure_value()
        if (!journal_seen) { print ""; print "[Journal]"; print param "=" expected }
      }
    ' "$JOURNALD_CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
    mode="$(stat -c "%a" "$JOURNALD_CONF" 2>/dev/null || echo 644)"
    chmod "$mode" "$tmp" || { rm -f "$tmp"; return 1; }
    chown --reference="$JOURNALD_CONF" "$tmp" 2>/dev/null || chown root:root "$tmp" 2>/dev/null || true
  else
    printf '[Journal]\n%s=%s\n' "$param" "$expected" > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp" && chown root:root "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  fi
  mv "$tmp" "$JOURNALD_CONF" || { rm -f "$tmp"; return 1; }
  return 0
}

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
  local param="$1" expected="$2" description="$3"
  local inventory="" mismatch="" dropins="" file actual="" effect=""

  inventory="$(journald_param_inventory "$param")"
  if [ -n "$inventory" ]; then
    mismatch="$(printf '%s\n' "$inventory" | awk -F'|' -v expected="$expected" '$2 != expected {print}')"
    if [ -z "$mismatch" ]; then
      echo -e "$GREEN[✓] $description coincide con las directivas explícitas detectadas$NC"
      return 0
    fi
  elif [ "$param" = "Compress" ] && [ "$expected" = "yes" ]; then
    echo -e "$GREEN[✓] Compress=yes es el valor predeterminado; no se requiere editarlo$NC"
    return 0
  fi

  echo -e "$RED[!] $description no cumple el objetivo $expected o falta una configuración explícita$NC"
  if [ -n "$inventory" ]; then
    printf '%s\n' "$inventory" | while IFS='|' read -r file actual; do
      [ -n "$file" ] && echo "  - Configurado: $file = $actual"
    done
  fi
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 1; fi

  dropins="$(printf '%s\n' "$inventory" | awk -F'|' -v main="$JOURNALD_CONF" '$1 != main && $1 != "" {print}')"
  if [ -n "$dropins" ]; then
    echo -e "$YELLOW[WARN] Hay un override en un drop-in; no se edita el archivo principal porque podría no tener efecto.$NC"
    echo "$dropins"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  case "$param" in
    ForwardToSyslog) effect="Reenvía eventos del journal a rsyslog. Puede duplicar logs, aumentar I/O y cambia el flujo de recolección; compruebe que rsyslog se utiliza." ;;
    Compress) effect="Comprime archivos de journal grandes para ahorrar disco a costa de CPU. Solo se cambia cuando una configuración explícita contradice el valor esperado." ;;
    Storage) effect="Mantiene logs tras reinicios y consume espacio en /var. Compruebe capacidad y retención antes de activar persistencia." ;;
    *) effect="Cambia la política de journald; puede afectar retención, consumo de disco y flujo de logs." ;;
  esac
  if ! confirm_rsyslog_change "$description -> $expected" "$effect"; then WARNINGS=$((WARNINGS + 1)); return 1; fi
  if ! journald_set_main_param "$param" "$expected"; then
    echo -e "$RED[!] No se pudo modificar $JOURNALD_CONF de forma segura$NC"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  JOURNALD_CONFIG_CHANGED=true
  FIXED=$((FIXED + 1))
  echo -e "$GREEN[✓] $description configurado en $JOURNALD_CONF$NC"
}

# ==============================================
# FUNCION PARA CONFIGURAR REMOTE LOGGING
# ==============================================
configure_remote_logging() {
  local remote_host="$1" remote_port="$2" remote_proto="$3" remote_config="" proto_display="" effect="" prior_auto="$AUTO_FIX"
  [ -n "$remote_port" ] || remote_port=514
  [ -n "$remote_proto" ] || remote_proto=udp
  case "$remote_port" in *[!0-9]*|"") echo -e "$RED[!] Puerto remoto inválido: $remote_port$NC"; return 1 ;; esac
  if [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ]; then echo -e "$RED[!] Puerto remoto fuera de rango: $remote_port$NC"; return 1; fi
  case "$remote_proto" in
    TCP|tcp|Tcp) remote_proto=tcp ;;
    UDP|udp|Udp) remote_proto=udp ;;
    *) echo -e "$RED[!] Protocolo inválido: use udp o tcp$NC"; return 1 ;;
  esac

  if [ ! -f "$RSYSLOG_CONF" ] || [ -L "$RSYSLOG_CONF" ]; then
    echo -e "$RED[!] $RSYSLOG_CONF no es un archivo regular; no se modifica.$NC"
    return 1
  fi
  if grep -Eq '^[[:space:]]*[^#[:space:]].*@[^[:space:]]+' "$RSYSLOG_CONF" 2>/dev/null; then
    echo -e "$YELLOW[!] Ya existe forwarding remoto. No se agrega una regla duplicada; revise primero el destino actual.$NC"
    grep -E '^[[:space:]]*[^#[:space:]].*@[^[:space:]]+' "$RSYSLOG_CONF" | sed 's/^/  - /'
    return 1
  fi

  if [ "$remote_proto" = "tcp" ]; then
    remote_config="*.* @@$remote_host:$remote_port"
    proto_display=TCP
  else
    remote_config="*.* @$remote_host:$remote_port"
    proto_display=UDP
  fi

  effect="Envía todos los logs que maneja rsyslog (*.*) a $remote_host:$remote_port por $proto_display. Puede exponer datos sensibles, consumir ancho de banda y hacer depender la retención del host remoto; valide autorización, transporte y capacidad del destino."
  if ! confirm_rsyslog_change "configurar forwarding a $remote_host:$remote_port ($proto_display)" "$effect"; then
    return 1
  fi

  mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR" || { echo -e "$RED[!] No se pudo crear el backup$NC"; return 1; }
  if [ ! -f "$BACKUP_DIR/rsyslog.conf.bak" ]; then
    cp -p "$RSYSLOG_CONF" "$BACKUP_DIR/rsyslog.conf.bak" || { echo -e "$RED[!] No se pudo respaldar $RSYSLOG_CONF$NC"; return 1; }
  fi
  {
    printf '\n# OrangeBox remote log forwarding\n'
    printf '# Destination: %s:%s (%s)\n' "$remote_host" "$remote_port" "$proto_display"
    printf '%s\n' "$remote_config"
  } >> "$RSYSLOG_CONF" || { echo -e "$RED[!] No se pudo escribir la configuración$NC"; return 1; }

  RSYSLOG_CONFIG_CHANGED=true
  echo -e "$GREEN[✓] Regla de forwarding agregada; pendiente validar rsyslog y confirmar el reinicio.$NC"
  AUTO_FIX=true
  restart_services
  AUTO_FIX="$prior_auto"
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

  if ob_service_is_enabled rsyslog; then
    echo -e "${GREEN}[✓] rsyslog habilitado${NC}"
  else
    echo -e "${RED}[!] rsyslog no habilitado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      ob_service_enable rsyslog
      echo -e "${GREEN}[✓] rsyslog habilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if ob_service_is_active rsyslog; then
    echo -e "${GREEN}[✓] rsyslog corriendo${NC}"
  else
    echo -e "${RED}[!] rsyslog no corriendo${NC}"
    if [ "$AUTO_FIX" = true ]; then
      ob_service_start rsyslog
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
  if ! command -v systemctl >/dev/null 2>&1; then
    echo -e "${YELLOW}[N/A] systemd-journald no está disponible en esta plataforma; se omiten controles específicos de journald.${NC}"
    return 0
  fi
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
    if ob_service_restart rsyslog; then
      echo -e "${GREEN}[✓] Rsyslog reiniciado${NC}"
    else
      echo -e "${RED}[!] No se pudo reiniciar rsyslog${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl restart systemd-journald; then
      echo -e "${GREEN}[✓] systemd-journald reiniciado${NC}"
    fi
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
  if command -v journalctl >/dev/null 2>&1; then
    echo -e "  journalctl -xe"
  fi

  echo -e "\n${YELLOW}PARA VER ESTADO:${NC}"
  if command -v systemctl >/dev/null 2>&1; then
    echo -e "  systemctl status rsyslog"
    echo -e "  systemctl status systemd-journald"
  else
    echo -e "  service rsyslog status"
  fi

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
