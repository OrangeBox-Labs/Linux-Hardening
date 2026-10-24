#!/bin/bash

# ==============================================
# Script: network-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de red - CIS 3.1.x, 3.2.x, 3.3.x, 3.4.x
#              Aplica sysctl, deshabilita modulos peligrosos
#              NO cambia reglas de firewall existentes
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false
ALLOW_SHOREWALL=false

SYSCTL_FILE="/etc/sysctl.d/99zz-orangebox-network-hardening.conf"
SYSCTL_LEGACY_FILE="/etc/sysctl.d/99-network-hardening.conf"
BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# LISTA DE MODULOS A DESHABILITAR
# ==============================================
MODULES_TO_DISABLE=(
  "tipc:Transparent Inter-Process Communication (cluster communication)"
  "dccp:Datagram Congestion Control Protocol (streaming multimedia)"
  "sctp:Stream Control Transmission Protocol (telefonia IP)"
  "rds:Reliable Datagram Sockets (Oracle RDS)"
  "atm:Asynchronous Transfer Mode"
  "decnet:Digital Equipment Corporation DECnet"
  "llc2:Logical Link Control type 2"
  "psnap:SubNetwork Attachment Point"
  "appletalk:AppleTalk"
  "ipx:Internetwork Packet Exchange"
  "ax25:Amateur Radio X.25"
  "netrom:NET/ROM (amateur radio)"
  "rose:Rose (amateur radio)"
)

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Auditoría (solo muestra lo que hay que corregir)"
  echo "  $0 --check    - Solo auditoría, no aplica cambios"
  echo "  $0 --fix      - Modo automático (aplica las correcciones)"
  echo "  $0 -f         - Modo automático (versión corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./network-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./network-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    [ -f /etc/sysctl.conf ] && cp -a /etc/sysctl.conf "$BACKUP_DIR/"
    [ -f "$SYSCTL_FILE" ] && cp -a "$SYSCTL_FILE" "$BACKUP_DIR/"
    [ -f "$SYSCTL_LEGACY_FILE" ] && cp -a "$SYSCTL_LEGACY_FILE" "$BACKUP_DIR/"
    [ -d /etc/modprobe.d ] && cp -r /etc/modprobe.d "$BACKUP_DIR/"
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA CONFIGURAR SYSCTL (maneja comentados)
# ==============================================
set_sysctl() {
  local param="$1"
  local value="$2"
  local description="${3:-$param}"
  local current configured tmp

  current=$(sysctl -n "$param" 2>/dev/null || true)
  if [ -z "$current" ]; then
    echo -e "${YELLOW}[!] $description no existe en este kernel${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  configured=$(awk -v key="$param" '
    {
      line=$0
      if (line ~ /^[[:space:]]*#/) next
      if (index(line, "=")) {
        lhs=line
        sub(/=.*/, "", lhs)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
        if (lhs == key) {
          val=line
          sub(/^[^=]*=/, "", val)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
          found=val
        }
      }
    }
    END { print found }
  ' "$SYSCTL_FILE" 2>/dev/null || true)

  if [ "$current" = "$value" ] && [ "$configured" = "$value" ]; then
    echo -e "${GREEN}[✓] $description = $value (runtime y persistente)${NC}"
    return 0
  fi

  if [ "$AUTO_FIX" != true ]; then
    echo -e "${RED}[!] $description: runtime=$current persistencia=${configured:-no definida}; recomendado=$value${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  echo -e "${BLUE}[i] $description: runtime=$current persistencia=${configured:-no definida}; se aplicará=$value${NC}"

  mkdir -p /etc/sysctl.d || {
    echo -e "${YELLOW}[!] No se pudo crear /etc/sysctl.d${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  tmp=$(mktemp "${SYSCTL_FILE}.XXXXXX") || {
    echo -e "${YELLOW}[!] No se pudo crear temporal para $param${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  if [ -f "$SYSCTL_FILE" ]; then
    awk -v key="$param" '
      {
        line=$0
        sub(/^[[:space:]]*#[[:space:]]*/, "", line)
        if (index(line, "=")) {
          lhs=line
          sub(/=.*/, "", lhs)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
          if (lhs == key) next
        }
        print
      }
    ' "$SYSCTL_FILE" > "$tmp" || {
      rm -f "$tmp"
      echo -e "${YELLOW}[!] No se pudo leer $SYSCTL_FILE${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    }
  fi
  printf '%s = %s\n' "$param" "$value" >> "$tmp" || {
    rm -f "$tmp"
    echo -e "${YELLOW}[!] No se pudo escribir $param${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  chmod 644 "$tmp" && chown root:root "$tmp" 2>/dev/null || true
  if ! mv "$tmp" "$SYSCTL_FILE"; then
    rm -f "$tmp"
    echo -e "${YELLOW}[!] No se pudo instalar persistencia de $param${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if sysctl -w "$param=$value" >/dev/null 2>&1 && [ "$(sysctl -n "$param" 2>/dev/null || true)" = "$value" ]; then
    echo -e "${GREEN}[✓] $description aplicado y persistido: $value${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}[!] No se pudo aplicar/verificar $param; revisar $SYSCTL_FILE${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}


# ==============================================
# FUNCION PARA DESHABILITAR MODULO (maneja comentados)
# ==============================================
disable_module() {
  local module=$1
  local description=$2
  local conf_file="/etc/modprobe.d/99-disable-${module}.conf"

  echo -e "\n${BLUE}[*] Verificando modulo: $module - $description${NC}"

  # Verificar si el modulo existe en el sistema
  if modprobe -n -v "$module" 2>&1 | grep -q "not found"; then
    echo -e "${GREEN}[✓] $module no existe en el sistema${NC}"
    return 0
  fi

  # Verificar si ya esta deshabilitado
  if [ -f "$conf_file" ] && grep -q "^install $module /bin/false" "$conf_file" 2>/dev/null; then
    echo -e "${GREEN}[✓] $module ya estaba deshabilitado${NC}"
    return 0
  fi

  # Verificar si existe configuracion comentada
  if [ -f "$conf_file" ] && grep -q "^#\s*install $module /bin/false" "$conf_file" 2>/dev/null; then
    echo -e "${YELLOW}[!] $module configuracion comentada${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^#\s*install $module \/bin\/false/install $module \/bin\/false/" "$conf_file"
      sed -i "s/^#\s*blacklist $module/blacklist $module/" "$conf_file"
      echo -e "${GREEN}[✓] $module configuracion descomentada${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 0
  fi

  echo -e "${RED}[!] $module existe - debe deshabilitarse${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo "install $module /bin/false" >"$conf_file"
    echo "blacklist $module" >>"$conf_file"

    if lsmod | grep -q "^$module"; then
      rmmod "$module" 2>/dev/null
      echo -e "${GREEN}[✓] $module descargado${NC}"
    fi

    echo -e "${GREEN}[✓] $module deshabilitado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}    Recomendacion: Deshabilitar $module${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR CONFLICTOS DE FIREWALL
# ==============================================
shorewall_is_active() {
  command -v shorewall >/dev/null 2>&1 || return 1
  systemctl is-active --quiet shorewall 2>/dev/null && return 0
  local status
  status="$(shorewall status 2>&1 || true)"
  printf '%s\n' "$status" | grep -Eiq 'stopped|not running|inactive|is down' && return 1
  printf '%s\n' "$status" | grep -Eiq 'running|started|active'
}

check_firewall_conflicts() {
  echo -e "\n${BLUE}[*] Verificando gestores y backend de firewall...${NC}"

  local shorewall_installed=false shorewall_active=false
  local firewalld_installed=false firewalld_active=false
  local nftables_installed=false nftables_active=false
  local iptables_installed=false iptables_active=false

  command -v shorewall >/dev/null 2>&1 && shorewall_installed=true
  shorewall_is_active && shorewall_active=true

  if rpm -q firewalld &>/dev/null; then
    firewalld_installed=true
    systemctl is-active --quiet firewalld 2>/dev/null && firewalld_active=true
  fi
  if rpm -q nftables &>/dev/null; then
    nftables_installed=true
    systemctl is-active --quiet nftables 2>/dev/null && nftables_active=true
  fi
  if rpm -q iptables-services &>/dev/null; then
    iptables_installed=true
    systemctl is-active --quiet iptables 2>/dev/null && iptables_active=true
  fi

  echo -e "  shorewall: instalado=$shorewall_installed activo=$shorewall_active"
  echo -e "  firewalld: instalado=$firewalld_installed activo=$firewalld_active"
  echo -e "  nftables: instalado=$nftables_installed activo=$nftables_active"
  echo -e "  iptables-services: instalado=$iptables_installed activo=$iptables_active"

  if [ "$shorewall_active" = true ]; then
    echo -e "${GREEN}[✓] Shorewall está activo y se reconoce como gestor principal del firewall${NC}"
    if [ "$firewalld_active" = true ]; then
      echo -e "${RED}[!] Shorewall y firewalld aparecen activos; revisar posible doble gestión${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    if [ "$AUTO_FIX" = true ] && [ "$ALLOW_SHOREWALL" != true ]; then
      echo -e "${RED}[!] Aplicación bloqueada: Shorewall está activo. Se requiere --allow-shorewall explícitamente.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    return 0
  fi

  local active_managers=0
  [ "$firewalld_active" = true ] && active_managers=$((active_managers + 1))
  [ "$nftables_active" = true ] && active_managers=$((active_managers + 1))
  [ "$iptables_active" = true ] && active_managers=$((active_managers + 1))

  if [ "$active_managers" -gt 1 ]; then
    echo -e "${RED}[!] Varios servicios de firewall aparecen activos ($active_managers); revisar backend y reglas antes de cambiar configuración${NC}"
    WARNINGS=$((WARNINGS + 1))
  elif [ "$active_managers" -eq 0 ]; then
    echo -e "${YELLOW}[!] No se pudo confirmar un gestor de firewall activo (incluido Shorewall)${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] Un gestor/backend de firewall está activo${NC}"
  fi
}
# ==============================================
# FUNCION PARA FLUSH ROUTES
# ==============================================
flush_routes() {
  sysctl -w net.ipv4.route.flush=1 >/dev/null 2>&1
  if [ -d /proc/sys/net/ipv6 ]; then
    sysctl -w net.ipv6.route.flush=1 >/dev/null 2>&1
  fi
}

# ==============================================
# MOSTRAR CABECERA
# ==============================================
show_header() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Network Hardening - CIS 3.1.x - 3.4.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"
}

# ==============================================
# 3.1.2 - DISABLE DCCP
# ==============================================
disable_dccp() {
  echo -e "\n${BLUE}[*] CIS 3.1.2 - Deshabilitando DCCP${NC}"
  echo -e "${YELLOW}    Datagram Congestion Control Protocol (streaming multimedia)${NC}"
  disable_module "dccp" "DCCP"
}

# ==============================================
# 3.1.3 - DISABLE TIPC
# ==============================================
disable_tipc() {
  echo -e "\n${BLUE}[*] CIS 3.1.3 - Deshabilitando TIPC${NC}"
  echo -e "${YELLOW}    Transparent Inter-Process Communication (cluster communication)${NC}"
  disable_module "tipc" "TIPC"
}

# ==============================================
# 3.1.4 - DISABLE SCTP
# ==============================================
disable_sctp() {
  echo -e "\n${BLUE}[*] CIS 3.1.4 - Deshabilitando SCTP${NC}"
  echo -e "${YELLOW}    Stream Control Transmission Protocol (telefonia IP)${NC}"
  disable_module "sctp" "SCTP"
}

# ==============================================
# 3.1.5 - DISABLE RDS
# ==============================================
disable_rds() {
  echo -e "\n${BLUE}[*] CIS 3.1.5 - Deshabilitando RDS${NC}"
  echo -e "${YELLOW}    Reliable Datagram Sockets (Oracle RDS)${NC}"
  disable_module "rds" "RDS"
}

# ==============================================
# 3.2.2 - DISABLE SEND_REDIRECTS
# ==============================================
disable_send_redirects() {
  echo -e "\n${BLUE}[*] CIS 3.2.2 - Deshabilitando envio de redirecciones ICMP${NC}"
  echo -e "${YELLOW}    Previene que el sistema sea usado para ataques MITM${NC}"

  set_sysctl "net.ipv4.conf.all.send_redirects" "0" "net.ipv4.conf.all.send_redirects"
  set_sysctl "net.ipv4.conf.default.send_redirects" "0" "net.ipv4.conf.default.send_redirects"
  flush_routes
}

# ==============================================
# 3.3.1 - DISABLE SOURCE ROUTED PACKETS
# ==============================================
disable_source_route() {
  echo -e "\n${BLUE}[*] CIS 3.3.1 - Deshabilitando paquetes con enrutamiento origen${NC}"
  echo -e "${YELLOW}    Previene ataques de spoofing y redireccion de trafico${NC}"

  set_sysctl "net.ipv4.conf.all.accept_source_route" "0" "net.ipv4.conf.all.accept_source_route"
  set_sysctl "net.ipv4.conf.default.accept_source_route" "0" "net.ipv4.conf.default.accept_source_route"

  if [ -d /proc/sys/net/ipv6 ]; then
    set_sysctl "net.ipv6.conf.all.accept_source_route" "0" "net.ipv6.conf.all.accept_source_route"
    set_sysctl "net.ipv6.conf.default.accept_source_route" "0" "net.ipv6.conf.default.accept_source_route"
  fi
  flush_routes
}

# ==============================================
# 3.3.3 - DISABLE SECURE ICMP REDIRECTS
# ==============================================
disable_secure_redirects() {
  echo -e "\n${BLUE}[*] CIS 3.3.3 - Deshabilitando redirecciones ICMP seguras${NC}"
  echo -e "${YELLOW}    Previene actualizacion de tabla de enrutamiento por gateways comprometidos${NC}"

  set_sysctl "net.ipv4.conf.all.secure_redirects" "0" "net.ipv4.conf.all.secure_redirects"
  set_sysctl "net.ipv4.conf.default.secure_redirects" "0" "net.ipv4.conf.default.secure_redirects"
  flush_routes
}

# ==============================================
# 3.3.4 - LOG SUSPICIOUS PACKETS (MARTIANS)
# ==============================================
log_martians() {
  echo -e "\n${BLUE}[*] CIS 3.3.4 - Habilitando logging de paquetes sospechosos${NC}"
  echo -e "${YELLOW}    Registra paquetes con direcciones origen no enrutables (martians)${NC}"
  echo -e "${RED}    NOTA: Esto puede llenar logs rapidamente en entornos con mucho trafico${NC}"

  set_sysctl "net.ipv4.conf.all.log_martians" "1" "net.ipv4.conf.all.log_martians"
  set_sysctl "net.ipv4.conf.default.log_martians" "1" "net.ipv4.conf.default.log_martians"
  flush_routes
}

# ==============================================
# 3.3.5 - IGNORE BROADCAST ICMP REQUESTS
# ==============================================
ignore_broadcast_icmp() {
  echo -e "\n${BLUE}[*] CIS 3.3.5 - Ignorando peticiones ICMP broadcast${NC}"
  echo -e "${YELLOW}    Previene ataques Smurf (amplificacion de trafico)${NC}"

  set_sysctl "net.ipv4.icmp_echo_ignore_broadcasts" "1" "net.ipv4.icmp_echo_ignore_broadcasts"
  flush_routes
}

# ==============================================
# 3.3.6 - IGNORE BOGUS ICMP RESPONSES
# ==============================================
ignore_bogus_icmp() {
  echo -e "\n${BLUE}[*] CIS 3.3.6 - Ignorando respuestas ICMP falsas${NC}"
  echo -e "${YELLOW}    Previene llenado de logs con respuestas no conformes a RFC-1122${NC}"

  set_sysctl "net.ipv4.icmp_ignore_bogus_error_responses" "1" "net.ipv4.icmp_ignore_bogus_error_responses"
  flush_routes
}

# ==============================================
# 3.3.7 - ENABLE REVERSE PATH FILTERING
# ==============================================
enable_rp_filter() {
  echo -e "\n${BLUE}[*] CIS 3.3.7 - Habilitando filtrado de ruta inversa${NC}"
  echo -e "${YELLOW}    Previene ataques de spoofing verificando que el paquete venga por la interfaz correcta${NC}"
  echo -e "${RED}    NOTA: Puede causar problemas si se utiliza enrutamiento asimetrico (BGP, OSPF)${NC}"

  local forwarding rp_filter
  forwarding=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)
  rp_filter=1
  if [ "$forwarding" = 1 ]; then
    # En routers/firewalls, strict mode puede descartar rutas asimétricas válidas.
    rp_filter=2
    echo -e "${GREEN}[✓] IP forwarding=1: usando rp_filter=2 (loose) para evitar descartar tráfico asimétrico${NC}"
  fi
  set_sysctl "net.ipv4.conf.all.rp_filter" "$rp_filter" "net.ipv4.conf.all.rp_filter"
  set_sysctl "net.ipv4.conf.default.rp_filter" "$rp_filter" "net.ipv4.conf.default.rp_filter"
  flush_routes
}

# ==============================================
# 3.3.8 - ENABLE TCP SYN COOKIES
# ==============================================
enable_syncookies() {
  echo -e "\n${BLUE}[*] CIS 3.3.8 - Habilitando SYN Cookies${NC}"
  echo -e "${YELLOW}    Previene ataques de denial of service por inundacion SYN${NC}"

  set_sysctl "net.ipv4.tcp_syncookies" "1" "net.ipv4.tcp_syncookies"
  set_sysctl "net.ipv4.tcp_max_syn_backlog" "4096" "net.ipv4.tcp_max_syn_backlog"
  set_sysctl "net.core.somaxconn" "4096" "net.core.somaxconn"
  set_sysctl "net.ipv4.tcp_synack_retries" "3" "net.ipv4.tcp_synack_retries"
  set_sysctl "net.ipv4.tcp_syn_retries" "5" "net.ipv4.tcp_syn_retries"
  flush_routes
}

# ==============================================
# 3.3.9 - DISABLE IPV6 ROUTER ADVERTISEMENTS
# ==============================================
disable_ipv6_ra() {
  echo -e "\n${BLUE}[*] CIS 3.3.9 - Deshabilitando anuncios de router IPv6${NC}"
  echo -e "${YELLOW}    Previene que el sistema acepte rutas maliciosas via RA${NC}"

  if [ -d /proc/sys/net/ipv6 ]; then
    local ipv6_forward
    ipv6_forward=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo 0)
    if [ "$ipv6_forward" = 1 ]; then
      echo -e "${YELLOW}[!] IPv6 forwarding está activo; se preserva accept_ra para no romper rutas del uplink${NC}"
      return 0
    fi
    set_sysctl "net.ipv6.conf.all.accept_ra" "0" "net.ipv6.conf.all.accept_ra"
    set_sysctl "net.ipv6.conf.default.accept_ra" "0" "net.ipv6.conf.default.accept_ra"
    flush_routes
  else
    echo -e "${YELLOW}[!] IPv6 no habilitado en este sistema${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN FINAL
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  NETWORK HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACIONES:${NC}"
  echo -e "  sysctl net.ipv4.conf.all.send_redirects"
  echo -e "  sysctl net.ipv4.conf.all.accept_source_route"
  echo -e "  sysctl net.ipv4.conf.all.secure_redirects"
  echo -e "  sysctl net.ipv4.conf.all.log_martians"
  echo -e "  sysctl net.ipv4.tcp_syncookies"
  echo -e "  sysctl net.ipv4.conf.all.rp_filter"

  echo -e "\n${YELLOW}MODULOS DESHABILITADOS:${NC}"
  echo -e "  lsmod | grep -E 'tipc|dccp|sctp|rds|atm'"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  show_header

  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h) show_usage; exit 0 ;;
      --fix|-f) AUTO_FIX=true ;;
      --check) AUTO_FIX=false ;;
      --allow-shorewall) ALLOW_SHOREWALL=true ;;
      *) echo -e "${RED}[!] Opción desconocida: $1${NC}"; show_usage; exit 2 ;;
    esac
    shift
  done

  if [ "$AUTO_FIX" = true ]; then
    if shorewall_is_active && [ "$ALLOW_SHOREWALL" != true ]; then
      echo -e "${RED}[ERROR] Shorewall está activo; no se aplicarán cambios de red sin --allow-shorewall.${NC}"
      echo "No se han modificado sysctl ni módulos del kernel."
      exit 2
    fi
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    make_backup
  else
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"
  fi

  disable_dccp
  disable_tipc
  disable_sctp
  disable_rds

  for item in "${MODULES_TO_DISABLE[@]}"; do
    module="${item%%:*}"
    desc="${item##*:}"
    disable_module "$module" "$desc"
  done

  disable_send_redirects
  disable_source_route
  disable_secure_redirects
  log_martians
  ignore_broadcast_icmp
  ignore_bogus_icmp
  enable_rp_filter
  enable_syncookies
  disable_ipv6_ra
  check_firewall_conflicts
  show_summary

  if [ "$AUTO_FIX" = false ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar cambios en sistemas con Shorewall, use --fix --allow-shorewall solo tras revisar el impacto.${NC}"
  fi
}
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
