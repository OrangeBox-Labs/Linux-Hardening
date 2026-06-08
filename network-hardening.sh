#!/bin/bash

# ==============================================
# Script: network-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de red - CIS 3.2.x, 3.3.x, 3.4.x
#              Solo aplica sysctl y deshabilita modulos
#              NO cambia reglas de firewall
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

SYSCTL_FILE="/etc/sysctl.d/99-network-hardening.conf"
BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"

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
    if [ -f /etc/sysctl.conf ]; then
      cp /etc/sysctl.conf "$BACKUP_DIR/"
    fi
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA CONFIGURAR SYSCTL
# ==============================================
set_sysctl() {
  local param=$1
  local value=$2
  local description="${3:-$param}"
  local current=$(sysctl -n "$param" 2>/dev/null)

  if [ "$current" = "$value" ]; then
    echo -e "${GREEN}[✓] $description = $value${NC}"
    return 0
  fi

  echo -e "${RED}[!] $description: $current (debe ser $value)${NC}"

  if [ "$AUTO_FIX" = true ]; then
    if grep -q "^$param" "$SYSCTL_FILE" 2>/dev/null; then
      sed -i "s/^$param.*/$param = $value/" "$SYSCTL_FILE"
    else
      echo "$param = $value" >>"$SYSCTL_FILE"
    fi
    sysctl -w "$param=$value" >/dev/null 2>&1
    echo -e "${GREEN}[✓] $description corregido: $value${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR MODULO
# ==============================================
check_module() {
  local module=$1
  local description=$2

  echo -e "\n${BLUE}[*] Verificando modulo: $module - $description${NC}"

  if lsmod | grep -q "^$module"; then
    echo -e "${RED}[!] $module esta CARGADO${NC}"

    if [ "$AUTO_FIX" = true ]; then
      rmmod "$module" 2>/dev/null
      echo "install $module /bin/true" >"/etc/modprobe.d/${module}.conf"
      echo -e "${GREEN}[✓] $module deshabilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Deshabilitar $module${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] $module no esta cargado${NC}"
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR CONFLICTOS DE FIREWALL
# ==============================================
check_firewall_conflicts() {
  echo -e "\n${BLUE}[*] Verificando conflictos de firewall...${NC}"

  local firewalld_installed=false
  local firewalld_active=false
  local nftables_installed=false
  local nftables_active=false
  local iptables_installed=false
  local iptables_active=false

  if rpm -q firewalld &>/dev/null; then
    firewalld_installed=true
    if systemctl is-active --quiet firewalld 2>/dev/null; then
      firewalld_active=true
    fi
  fi

  if rpm -q nftables &>/dev/null; then
    nftables_installed=true
    if systemctl is-active --quiet nftables 2>/dev/null; then
      nftables_active=true
    fi
  fi

  if rpm -q iptables-services &>/dev/null; then
    iptables_installed=true
    if systemctl is-active --quiet iptables 2>/dev/null; then
      iptables_active=true
    fi
  fi

  echo -e "  firewalld: instalado=$firewalld_installed activo=$firewalld_active"
  echo -e "  nftables: instalado=$nftables_installed activo=$nftables_active"
  echo -e "  iptables: instalado=$iptables_installed activo=$iptables_active"

  local active_count=0
  [ "$firewalld_active" = true ] && active_count=$((active_count + 1))
  [ "$nftables_active" = true ] && active_count=$((active_count + 1))
  [ "$iptables_active" = true ] && active_count=$((active_count + 1))

  if [ $active_count -gt 1 ]; then
    echo -e "${RED}[!] ADVERTENCIA: Multiples firewalls activos ($active_count)${NC}"
    echo -e "${YELLOW}    Recomendacion: Tener solo un firewall activo${NC}"
    WARNINGS=$((WARNINGS + 1))
  elif [ $active_count -eq 0 ]; then
    echo -e "${YELLOW}[!] No hay firewall activo${NC}"
    echo -e "${YELLOW}    Recomendacion: Activar iptables${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] Solo un firewall activo${NC}"
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
  echo -e "${GREEN}  Network Hardening - CIS 3.2.x - 3.4.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"
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

  set_sysctl "net.ipv4.conf.all.rp_filter" "1" "net.ipv4.conf.all.rp_filter"
  set_sysctl "net.ipv4.conf.default.rp_filter" "1" "net.ipv4.conf.default.rp_filter"
  flush_routes
}

# ==============================================
# 3.3.8 - ENABLE TCP SYN COOKIES
# ==============================================
enable_syncookies() {
  echo -e "\n${BLUE}[*] CIS 3.3.8 - Habilitando SYN Cookies${NC}"
  echo -e "${YELLOW}    Previene ataques de denial of service por inundacion SYN${NC}"

  set_sysctl "net.ipv4.tcp_syncookies" "1" "net.ipv4.tcp_syncookies"
  flush_routes
}

# ==============================================
# 3.3.9 - DISABLE IPV6 ROUTER ADVERTISEMENTS
# ==============================================
disable_ipv6_ra() {
  echo -e "\n${BLUE}[*] CIS 3.3.9 - Deshabilitando anuncios de router IPv6${NC}"
  echo -e "${YELLOW}    Previene que el sistema acepte rutas maliciosas via RA${NC}"

  if [ -d /proc/sys/net/ipv6 ]; then
    set_sysctl "net.ipv6.conf.all.accept_ra" "0" "net.ipv6.conf.all.accept_ra"
    set_sysctl "net.ipv6.conf.default.accept_ra" "0" "net.ipv6.conf.default.accept_ra"
    flush_routes
  else
    echo -e "${YELLOW}[!] IPv6 no habilitado en este sistema${NC}"
  fi
}

# ==============================================
# 3.4.1 - DISABLE DCCP
# ==============================================
check_dccp() {
  check_module "dccp" "Datagram Congestion Control Protocol (streaming multimedia)"
}

# ==============================================
# 3.4.2 - DISABLE SCTP
# ==============================================
check_sctp() {
  check_module "sctp" "Stream Control Transmission Protocol (telefonia IP)"
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
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  show_header

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

  # Ejecutar todas las verificaciones/correcciones
  disable_send_redirects
  disable_source_route
  disable_secure_redirects
  log_martians
  ignore_broadcast_icmp
  ignore_bogus_icmp
  enable_rp_filter
  enable_syncookies
  disable_ipv6_ra

  # Verificar modulos
  check_dccp
  check_sctp
  check_firewall_conflicts

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
