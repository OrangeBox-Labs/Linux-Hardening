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

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$SCRIPT_DIR/lib/sysctl-safe.sh" ]; then
  # shellcheck source=lib/sysctl-safe.sh
  source "$SCRIPT_DIR/lib/sysctl-safe.sh"
else
  echo "[ERROR] Falta lib/sysctl-safe.sh; actualice el repositorio completo." >&2
  exit 1
fi
if [ -r "$SCRIPT_DIR/lib/firewall-detect.sh" ]; then
  # shellcheck source=lib/firewall-detect.sh
  source "$SCRIPT_DIR/lib/firewall-detect.sh"
else
  echo "[ERROR] Falta lib/firewall-detect.sh; actualice el repositorio completo." >&2
  exit 1
fi
if [ -r "$SCRIPT_DIR/lib/listener-firewall-audit.sh" ]; then
  # Auditoría de sockets vs cobertura INPUT, sin cambios de firewall.
  # shellcheck source=lib/listener-firewall-audit.sh
  source "$SCRIPT_DIR/lib/listener-firewall-audit.sh"
else
  echo "[ERROR] Falta lib/listener-firewall-audit.sh; actualice el repositorio completo." >&2
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false
ALLOW_SHOREWALL=false

SYSCTL_FILE="/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf"
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
  local param="$1" value="$2" description="${3:-}"
  if [ -z "$description" ] || [ "$description" = "$param" ]; then
    description="$(sysctl_safe_description "$param")"
  fi
  if sysctl_safe_apply "$param" "$value" "$description" "$SYSCTL_FILE" "$BACKUP_DIR" "$AUTO_FIX" "" ""; then
    [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA DESHABILITAR MODULO (maneja comentados)
# ==============================================
confirm_module_disable() {
  local module="$1" description="$2" answer
  [ "$AUTO_FIX" = true ] || return 1

  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "${YELLOW}[WARN] Sin terminal interactiva: se omite el bloqueo de $module.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  echo -e "${YELLOW}[!] Se propone impedir la carga futura del módulo $module ($description).${NC}"
  echo "    Si una aplicación o función de red lo requiere, podría dejar de funcionar."
  if lsmod | awk -v m="$module" '$1 == m {found=1} END {exit !found}'; then
    echo "    El módulo está cargado; también se intentará descargarlo durante esta ejecución."
  else
    echo "    El módulo no está cargado actualmente."
  fi
  printf '¿Confirmas deshabilitar %s? [s/N] ' "$module" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    y|Y|yes|YES|s|S|si|SI|sí|Sí|SÍ) return 0 ;;
    *)
      echo -e "${YELLOW}[OMITIDO] No se modificará la configuración de $module.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
      ;;
  esac
}

disable_module() {
  local module="$1"
  local description="$2"
  local conf_file="/etc/modprobe.d/99-disable-"$module".conf"
  local config_changed=false

  echo -e "\n${BLUE}[*] Verificando modulo: $module - $description${NC}"

  # Verificar si el modulo existe en el sistema.
  if modprobe -n -v "$module" 2>&1 | grep -q "not found"; then
    echo -e "${GREEN}[✓] $module no existe en el sistema${NC}"
    return 0
  fi

  if [ -L "$conf_file" ]; then
    echo -e "${RED}[ERROR] $conf_file es un enlace simbólico; no se modifica.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  # Si ya hay una regla install activa, no reemplazar silenciosamente una política distinta.
  if [ -f "$conf_file" ] && grep -Eq "^[[:space:]]*install[[:space:]]+$module[[:space:]]+" "$conf_file" &&
      ! grep -Eq "^[[:space:]]*install[[:space:]]+$module[[:space:]]+/bin/false([[:space:]]|$)" "$conf_file"; then
    echo -e "${RED}[WARN] $conf_file ya contiene otra regla install para $module; se conserva sin cambios.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if [ -f "$conf_file" ] &&
     grep -Eq "^[[:space:]]*install[[:space:]]+$module[[:space:]]+/bin/false([[:space:]]|$)" "$conf_file" &&
     grep -Eq "^[[:space:]]*blacklist[[:space:]]+$module([[:space:]]|$)" "$conf_file"; then
    echo -e "${GREEN}[✓] $module ya está deshabilitado en $conf_file${NC}"
    return 0
  fi

  if [ "$AUTO_FIX" != true ]; then
    echo -e "${RED}[!] $module está disponible; revisar si debe deshabilitarse.${NC}"
    echo -e "${YELLOW}    Recomendación: deshabilitar $module solo si ningún servicio lo requiere.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  confirm_module_disable "$module" "$description" || return 0

  # Mantener cualquier contenido previo; solo agregar las directivas que faltan.
  mkdir -p /etc/modprobe.d || {
    echo -e "${RED}[ERROR] No se pudo acceder a /etc/modprobe.d.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  touch "$conf_file" || {
    echo -e "${RED}[ERROR] No se pudo crear $conf_file.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  if ! grep -Eq "^[[:space:]]*install[[:space:]]+$module[[:space:]]+/bin/false([[:space:]]|$)" "$conf_file"; then
    printf 'install %s /bin/false\n' "$module" >> "$conf_file" || return 1
    config_changed=true
  fi
  if ! grep -Eq "^[[:space:]]*blacklist[[:space:]]+$module([[:space:]]|$)" "$conf_file"; then
    printf 'blacklist %s\n' "$module" >> "$conf_file" || return 1
    config_changed=true
  fi

  if lsmod | awk -v m="$module" '$1 == m {found=1} END {exit !found}'; then
    if rmmod "$module" 2>/dev/null; then
      echo -e "${GREEN}[✓] $module descargado${NC}"
    else
      echo -e "${YELLOW}[WARN] No se pudo descargar $module (posiblemente en uso); el bloqueo persistente ya está configurado.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if [ "$config_changed" = true ]; then
    echo -e "${GREEN}[✓] Regla persistente de $module actualizada en $conf_file${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] Las reglas de $module ya estaban presentes${NC}"
  fi
  return 0
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

# CSF administra reglas iptables directamente; no requiere una unidad systemd propia.
# Se considera operativo cuando csf -l puede mostrar las cadenas activas del kernel.
csf_rules_active() {
  command -v csf >/dev/null 2>&1 || return 1
  local listing
  listing="$(csf -l 2>&1)" || return 1
  printf '%s\n' "$listing" | grep -Eq 'iptables .* table|Chain INPUT[[:space:]]+\('
}

check_firewall_conflicts() {
  echo -e "\n${BLUE}[*] Auditoría de solo lectura: firewall y sockets en escucha...${NC}"

  local shorewall_installed=false shorewall_active=false
  local csf_installed=false csf_active=false
  local imunify360_rules=false
  local firewalld_installed=false firewalld_active=false
  local nftables_installed=false nftables_active=false
  local iptables_installed=false iptables_active=false

  command -v shorewall >/dev/null 2>&1 && shorewall_installed=true
  shorewall_is_active && shorewall_active=true
  command -v csf >/dev/null 2>&1 && csf_installed=true
  csf_rules_active && csf_active=true
  firewall_print_backend_diagnostics
  firewall_has_imunify360_rules && imunify360_rules=true
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

  echo "  shorewall: instalado=$shorewall_installed activo=$shorewall_active"
  echo "  csf: instalado=$csf_installed reglas_activas=$csf_active"
  echo "  firewalld: instalado=$firewalld_installed activo=$firewalld_active"
  echo "  nftables: instalado=$nftables_installed activo=$nftables_active"
  echo "  iptables-services: instalado=$iptables_installed activo=$iptables_active"
  [ "$imunify360_rules" = true ] && echo "  [INFO] Se detectan cadenas de integración de Imunify360 en iptables."

  # Coexistencia o ausencia de gestores no genera WARN por sí sola. En
  # producción solo alertamos por listeners remotos sin control INPUT probado.
  if [ "$shorewall_active" = true ] && { [ "$firewalld_active" = true ] || [ "$csf_active" = true ] || [ "$nftables_active" = true ] || [ "$iptables_active" = true ]; }; then
    echo "[INFO] Hay otros gestores/backend instalados o activos junto a Shorewall; se conserva toda la configuración."
  fi

  lfa_audit_listener_firewall
  WARNINGS=$((WARNINGS + LFA_WARNINGS))
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
  # TCP retry counts are workload/provider tuning, not universal SYN-cookie controls.
  # Preserve existing OS, cPanel and CloudLinux policy; tune these separately if needed.
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
    if shorewall_is_active; then
      echo -e "\n${BLUE}Shorewall está activo. Para aplicar cambios, revise primero el impacto y use --fix --allow-shorewall.${NC}"
    else
      echo -e "\n${BLUE}Para aplicar correcciones revisadas, ejecute --fix. La auditoría actual no modificó el sistema.${NC}"
    fi
  fi
}
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
