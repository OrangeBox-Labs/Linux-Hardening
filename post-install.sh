#!/bin/bash

# ==============================================
# Script: post-install.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Configuracion base para servidores Linux recien instalados
#              Compatible con RHEL/CentOS/Rocky/AlmaLinux/Oracle 8,9,10
#              - Repositorios EPEL
#              - SELinux permisivo
#              - Deshabilitar IPv6
#              - Herramientas esenciales
#              - VMware Tools
#              - Configuracion de red y hostname
#              - Verificacion pre-vuelo (LVM y particiones)
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false
OVERRIDE=false

BACKUP_DIR="/root/base-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0                     - Modo interactivo (pregunta todo)"
  echo "  $0 --fix               - Modo automatico (responde si a todo, sin preguntar)"
  echo "  $0 --override          - Ignora advertencias de LVM y particiones"
  echo "  $0 --fix --override    - Modo automatico + ignorar advertencias"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ejecutar de forma interactiva"
  echo "  ./post-install.sh"
  echo ""
  echo "  # Ejecutar de forma automatica (sin preguntar)"
  echo "  ./post-install.sh --fix"
  echo ""
  echo "  # Ejecutar ignorando advertencias de LVM/particiones"
  echo "  ./post-install.sh --override"
  echo ""
}

# ==============================================
# FUNCION PARA PREGUNTAR SI/NO (EN LA MISMA LINEA)
# ==============================================
ask_yes_no() {
  local question="$1"

  if [ "$AUTO_FIX" = true ]; then
    return 0
  fi

  while true; do
    echo -e -n "${YELLOW}$question (s/n): ${NC}"
    read -r answer
    case "$answer" in
    s | S | si | Si | SI | yes | Yes | YES) return 0 ;;
    n | N | no | No | NO) return 1 ;;
    *) echo -e "${RED}Responda s o n${NC}" ;;
    esac
  done
}

# ==============================================
# VERIFICAR LVM (PRE-VUELO)
# ==============================================
check_lvm() {
  echo -e "\n${BLUE}[*] Verificando si el sistema usa LVM...${NC}"

  if command -v lvm &>/dev/null && pvs &>/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Sistema usa LVM${NC}"
    return 0
  else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  ⚠️  ALERTA CRITICA  ⚠️${NC}"
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}[✗] El sistema NO utiliza LVM${NC}"
    echo -e "${YELLOW}Recomendacion: Reinstalar el sistema usando LVM para poder:${NC}"
    echo -e "  - Redimensionar particiones en caliente"
    echo -e "  - Agregar discos sin detener servicios"
    echo -e "  - Hacer snapshots antes de actualizaciones"
    echo -e "  - Migrar datos entre discos sin downtime"
    echo -e ""

    if [ "$OVERRIDE" = true ]; then
      echo -e "${YELLOW}[!] Modo override activado. Continuando a pesar de la advertencia...${NC}"
      return 0
    else
      echo -e -n "${YELLOW}¿Quieres continuar igualmente? (s/N): ${NC}"
      read -r answer
      if [[ ! "$answer" =~ ^[Ss]$ ]]; then
        echo -e "${RED}[!] Script cancelado. Reinstale el sistema con LVM.${NC}"
        exit 1
      fi
    fi
    return 1
  fi
}

# ==============================================
# VERIFICAR PARTICIONES SEPARADAS (PRE-VUELO)
# ==============================================
check_separated_partitions() {
  echo -e "\n${BLUE}[*] Verificando particiones separadas...${NC}"

  local required_partitions=("/home" "/var" "/var/log" "/tmp" "/opt")
  local missing_partitions=()
  local root_device=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/\[.*\]//' | xargs)
  local root_device_real=$(readlink -f "$root_device" 2>/dev/null)

  for partition in "${required_partitions[@]}"; do
    if findmnt -n "$partition" &>/dev/null; then
      local mount_device=$(findmnt -n -o SOURCE "$partition" 2>/dev/null | sed 's/\[.*\]//' | xargs)
      local mount_device_real=$(readlink -f "$mount_device" 2>/dev/null)
      if [ "$mount_device_real" != "$root_device_real" ] && [ "$mount_device" != "$root_device" ]; then
        echo -e "${GREEN}[✓] $partition es una particion separada${NC}"
      else
        echo -e "${RED}[✗] $partition NO es una particion separada${NC}"
        missing_partitions+=("$partition")
      fi
    else
      echo -e "${RED}[✗] $partition no existe o no esta montado${NC}"
      missing_partitions+=("$partition")
    fi
  done

  if [ ${#missing_partitions[@]} -gt 0 ]; then
    echo -e "\n${RED}============================================${NC}"
    echo -e "${RED}  ⚠️  ALERTA CRITICA  ⚠️${NC}"
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}Las siguientes particiones NO estan separadas de la raiz:${NC}"
    for mp in "${missing_partitions[@]}"; do
      echo -e "  • ${mp}"
    done

    echo -e "\n${YELLOW}Riesgos de seguridad:${NC}"
    echo -e "  • /home: Usuarios pueden llenar la particion root"
    echo -e "  • /var: Logs pueden llenar la particion root (DoS)"
    echo -e "  • /var/log: Logs de auditoria pueden llenar la particion root"
    echo -e "  • /tmp: Archivos temporales pueden llenar la particion root"
    echo -e "  • /opt: Aplicaciones grandes pueden llenar la particion root"

    if [ "$OVERRIDE" = true ]; then
      echo -e "\n${YELLOW}[!] Modo override activado. Continuando a pesar de la advertencia...${NC}"
    else
      echo -e -n "\n${YELLOW}¿Quieres continuar igualmente? (s/N): ${NC}"
      read -r answer
      if [[ ! "$answer" =~ ^[Ss]$ ]]; then
        echo -e "${RED}[!] Script cancelado. Reinstale el sistema con las particiones separadas.${NC}"
        exit 1
      fi
    fi
  else
    echo -e "\n${GREEN}[✓] EXCELENTE: Todas las particiones criticas estan separadas${NC}"
  fi
}

# ==============================================
# DETECTAR DISTRIBUCION Y VERSION
# ==============================================
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
    rocky | almalinux | centos | rhel | oracle | ol)
      distro="$ID"
      distro_version=$(echo "$VERSION_ID" | cut -d. -f1)
      ;;
    *)
      if [[ "$ID_LIKE" == *"rhel"* ]]; then
        distro="rhel"
        distro_version=$(echo "$VERSION_ID" | cut -d. -f1)
      else
        echo -e "${RED}[!] Distribucion no soportada: $ID${NC}"
        exit 1
      fi
      ;;
    esac
  else
    echo -e "${RED}[!] No se pudo detectar la distribucion${NC}"
    exit 1
  fi

  echo -e "${GREEN}[✓] Distribucion detectada: $distro $distro_version${NC}"
}

# ==============================================
# INSTALAR REPOSITORIOS
# ==============================================
install_repos() {
  echo -e "\n${BLUE}[*] Instalando repositorios adicionales...${NC}"

  if [ "$distro_version" -ge 9 ]; then
    if ! rpm -q epel-release &>/dev/null; then
      echo -e "${YELLOW}[*] Instalando EPEL release...${NC}"
      dnf install -y epel-release
      echo -e "${GREEN}[✓] EPEL release instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${GREEN}[✓] EPEL release ya instalado${NC}"
    fi
  else
    if ! rpm -q epel-release &>/dev/null; then
      echo -e "${YELLOW}[*] Instalando EPEL release...${NC}"
      yum install -y epel-release
      echo -e "${GREEN}[✓] EPEL release instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${GREEN}[✓] EPEL release ya instalado${NC}"
    fi
  fi
}

# ==============================================
# CONFIGURAR SELINUX A PERMISIVO
# ==============================================
configure_selinux() {
  echo -e "\n${BLUE}[*] Configurando SELinux a modo permisivo...${NC}"

  if getenforce 2>/dev/null | grep -q "Permissive"; then
    echo -e "${GREEN}[✓] SELinux ya esta en modo permisivo${NC}"
  else
    setenforce 0
    echo -e "${GREEN}[✓] SELinux cambiado a permisivo en caliente${NC}"
    FIXED=$((FIXED + 1))
  fi

  if grep -q "^SELINUX=enforcing" /etc/selinux/config 2>/dev/null; then
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    echo -e "${GREEN}[✓] SELinux configurado como permisivo en /etc/selinux/config${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] SELinux ya esta configurado como permisivo en disco${NC}"
  fi
}

# ==============================================
# DESHABILITAR IPV6 DESDE GRUB
# ==============================================
disable_ipv6() {
  echo -e "\n${BLUE}[*] Deshabilitando IPv6 desde GRUB...${NC}"

  if grep -q "ipv6.disable=1" /etc/default/grub 2>/dev/null; then
    echo -e "${GREEN}[✓] IPv6 ya esta deshabilitado en GRUB${NC}"
    return 0
  fi

  sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
  echo -e "${GREEN}[✓] ipv6.disable=1 agregado a GRUB_CMDLINE_LINUX${NC}"

  if [ -d /sys/firmware/efi ]; then
    grub2-mkconfig -o /boot/efi/EFI/*/grub.cfg 2>/dev/null || grub2-mkconfig -o /boot/grub2/grub.cfg
  else
    grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
  echo -e "${GREEN}[✓] Configuracion de GRUB regenerada${NC}"
  FIXED=$((FIXED + 1))
}

# ==============================================
# DETECTAR SI ES VMWARE
# ==============================================
is_vmware() {
  if dmidecode -s system-manufacturer 2>/dev/null | grep -qi "vmware"; then
    return 0
  fi
  if lspci 2>/dev/null | grep -qi "vmware"; then
    return 0
  fi
  return 1
}

# ==============================================
# INSTALAR OPEN-VM-TOOLS
# ==============================================
install_vmware_tools() {
  if is_vmware; then
    echo -e "\n${BLUE}[*] Detectado entorno VMware. Instalando open-vm-tools...${NC}"

    if command -v dnf &>/dev/null; then
      dnf install -y open-vm-tools
    else
      yum install -y open-vm-tools
    fi

    systemctl enable --now vmtoolsd
    echo -e "${GREEN}[✓] open-vm-tools instalado y habilitado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "\n${GREEN}[✓] No es entorno VMware, omitiendo open-vm-tools${NC}"
  fi
}

# ==============================================
# INSTALAR HERRAMIENTAS VITALES
# ==============================================
install_essentials() {
  echo -e "\n${BLUE}[*] Instalando herramientas esenciales...${NC}"

  local tools="vim rsync net-tools"
  local extra_tools=""

  echo -e "${YELLOW}Herramientas base a instalar: vim, rsync, net-tools${NC}\n"

  if ask_yes_no "¿Quieres instalar GIT también? (requisito para clonar el repo de scripts de hardening)"; then
    extra_tools="$extra_tools git"
    echo -e "${GREEN}[✓] Instalando tambien: git${NC}"
  fi

  if ask_yes_no "¿Quieres además instalar herramientas de red y diagnóstico (tcpdump, nmap, nmap-ncat, iftop, iptraf-ng, dig, traceroute, whois, arping)?"; then
    extra_tools="$extra_tools tcpdump iputils nmap nmap-ncat iftop iptraf-ng bind-utils traceroute whois"
    echo -e "${GREEN}[✓] Instalando tambien: tcpdump, arping, nmap, nmap-ncat, iftop, iptraf-ng, dig, traceroute, whois${NC}"
  fi

  if ask_yes_no "¿Quieres instalar herramientas de monitoreo (htop, btop, iotop, sysstat, ncdu, glances, nethogs)?"; then
    extra_tools="$extra_tools htop btop iotop sysstat ncdu glances nethogs"
    echo -e "${GREEN}[✓] Instalando tambien: htop, btop, iotop, sysstat, ncdu, glances, nethogs${NC}"
  fi

  local all_tools="$tools $extra_tools"

  if command -v dnf &>/dev/null; then
    dnf install -y $all_tools
  else
    yum install -y $all_tools
  fi

  echo -e "${GREEN}[✓] Herramientas instaladas${NC}"
  FIXED=$((FIXED + 1))
}

# ==============================================
# CONFIGURAR HOSTNAME
# ==============================================
configure_hostname() {
  echo -e "\n${BLUE}[*] Configurando hostname...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    return 0
  fi

  local current_hostname=$(hostname)
  echo -e "${YELLOW}Hostname actual: $current_hostname${NC}"

  if ask_yes_no "¿Quieres cambiar el hostname?"; then
    echo -e -n "${YELLOW}Ingrese el nuevo hostname: ${NC}"
    read -r new_hostname
    if [ -n "$new_hostname" ]; then
      hostnamectl set-hostname "$new_hostname"
      echo -e "${GREEN}[✓] Hostname cambiado a: $new_hostname${NC}"
      FIXED=$((FIXED + 1))
    fi
  fi
}

# ==============================================
# CONFIGURAR RED
# ==============================================
configure_network() {
  echo -e "\n${BLUE}[*] Configurando red...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    return 0
  fi

  if ! ask_yes_no "¿Quieres configurar la red?"; then
    return 0
  fi

  local interfaces=$(nmcli device status | grep ethernet | awk '{print $1}')

  if [ -z "$interfaces" ]; then
    echo -e "${YELLOW}[!] No se detectaron interfaces ethernet${NC}"
    return 1
  fi

  echo -e "${YELLOW}Interfaces disponibles: $interfaces${NC}"
  echo -e -n "${YELLOW}Seleccione la interfaz a configurar (default: $(echo $interfaces | awk '{print $1}')): ${NC}"
  read -r iface
  if [ -z "$iface" ]; then
    iface=$(echo $interfaces | awk '{print $1}')
  fi

  if ask_yes_no "¿Usar DHCP?"; then
    nmcli con mod "$iface" ipv4.method auto
    nmcli con up "$iface"
    echo -e "${GREEN}[✓] Configuracion DHCP aplicada en $iface${NC}"
  else
    echo -e -n "${YELLOW}Ingrese IP (ej: 192.168.1.100/24): ${NC}"
    read -r ip_address
    echo -e -n "${YELLOW}Ingrese gateway (ej: 192.168.1.1): ${NC}"
    read -r gateway
    echo -e -n "${YELLOW}Ingrese DNS (ej: 8.8.8.8,8.8.4.4): ${NC}"
    read -r dns

    if [ -n "$ip_address" ] && [ -n "$gateway" ]; then
      nmcli con mod "$iface" ipv4.method manual
      nmcli con mod "$iface" ipv4.addresses "$ip_address"
      nmcli con mod "$iface" ipv4.gateway "$gateway"
      if [ -n "$dns" ]; then
        nmcli con mod "$iface" ipv4.dns "$dns"
      fi
      nmcli con up "$iface"
      echo -e "${GREEN}[✓] Configuracion manual aplicada en $iface${NC}"
      FIXED=$((FIXED + 1))
    fi
  fi
}

# ==============================================
# ACTUALIZAR SISTEMA
# ==============================================
update_system() {
  echo -e "\n${BLUE}[*] Actualizando sistema...${NC}"

  if ! ask_yes_no "¿Quieres actualizar todos los paquetes del sistema?"; then
    echo -e "${YELLOW}[!] Actualizacion omitida${NC}"
    return 0
  fi

  echo -e "${YELLOW}[*] Actualizando paquetes...${NC}"

  if command -v dnf &>/dev/null; then
    dnf update -y
  else
    yum update -y
  fi

  echo -e "${GREEN}[✓] Sistema actualizado${NC}"
  FIXED=$((FIXED + 1))

  echo -e "\n${YELLOW}[!] Se recomienda reiniciar el sistema para aplicar todos los cambios${NC}"
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  POST-INSTALL COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Configuraciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias encontradas: ${YELLOW}$WARNINGS${NC}"

  echo -e "\n${YELLOW}VERIFICAR CONFIGURACIONES:${NC}"
  echo -e "  getenforce  # Debe mostrar Permissive"
  echo -e "  grep ipv6.disable=1 /etc/default/grub"
  echo -e "  hostname"
  echo -e "  nmcli device status"

  echo -e "\n${YELLOW}REINICIO PENDIENTE:${NC}"
  echo -e "  Ejecute 'reboot' para aplicar todos los cambios (especialmente GRUB e IPv6)"

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
  echo -e "${GREEN}  Post-Install - Configuracion Inicial${NC}"
  echo -e "${GREEN}  Para RHEL/Rocky/AlmaLinux/Oracle 8,9,10${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Procesar argumentos
  for arg in "$@"; do
    case "$arg" in
    --fix | -f) AUTO_FIX=true ;;
    --override | -o) OVERRIDE=true ;;
    --help | -h)
      show_usage
      exit 0
      ;;
    esac
  done

  if [ "$AUTO_FIX" = true ]; then
    echo -e "${YELLOW}[!] Modo automatico activado - se aplicaran cambios sin preguntar${NC}"
  fi

  if [ "$OVERRIDE" = true ]; then
    echo -e "${YELLOW}[!] Modo override activado - se ignoraran advertencias criticas${NC}"
  fi

  # DETECCION INICIAL
  detect_distro

  # PRE-VUELO: Verificaciones criticas
  check_lvm
  check_separated_partitions

  # CONFIGURACIONES BASE
  install_repos
  configure_selinux
  disable_ipv6

  # HERRAMIENTAS Y SERVICIOS
  install_vmware_tools
  install_essentials
  configure_hostname
  configure_network

  # ACTUALIZACION FINAL (sin reinicio automatico)
  update_system

  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
