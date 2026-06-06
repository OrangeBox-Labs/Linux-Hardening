#!/bin/bash

# ==============================================
# Script: remove-unnecessary-services.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Elimina servicios innecesarios de forma interactiva
#              Muestra las dependencias desde el archivo de transaccion
#              CIS 2.2.2 - 2.3.5
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0

# ==============================================
# FUNCION PARA SIMULAR ELIMINACION Y CAPTURAR DEPENDENCIAS
# ==============================================
simulate_and_capture_deps() {
  local package="$1"
  local tx_file=""
  local deps=""

  # Ejecutar remove con --assumeno para generar archivo de transaccion
  if command -v yum &>/dev/null; then
    yum remove "$package" -y --assumeno 2>&1 >/dev/null
    # Buscar el archivo de transaccion mas reciente
    tx_file=$(ls -t /tmp/yum_save_tx.*.yumtx 2>/dev/null | head -1)
  elif command -v dnf &>/dev/null; then
    dnf remove "$package" -y --assumeno 2>&1 >/dev/null
    tx_file=$(ls -t /tmp/dnf_save_tx.*.dnftx 2>/dev/null | head -1)
  fi

  # Parsear el archivo de transaccion
  if [ -f "$tx_file" ]; then
    # Extraer lineas que comienzan con "mbr:" y tomar el nombre hasta la primera coma
    deps=$(grep "^mbr:" "$tx_file" | cut -d',' -f1 | sed 's/^mbr: //' | sort -u)
    rm -f "$tx_file"
  fi

  echo "$deps"
}

# ==============================================
# LISTA DE SERVICIOS A VERIFICAR
# ==============================================
SERVICES=(
  "xorg-x11-server-Xorg:X11:Interfaz grafica X Window:2.2.2:X11"
  "avahi-autoipd:avahi-daemon:Descubrimiento de servicios mDNS:2.2.3:avahi-daemon"
  "cups:cups:Servidor de impresion:2.2.4:cups"
  "dhcp:dhcpd:Servidor DHCP:2.2.5:dhcpd"
  "openldap-servers:slapd:Servidor LDAP:2.2.6:slapd"
  "bind:named:Servidor DNS:2.2.7:named"
  "vsftpd:vsftpd:Servidor FTP:2.2.8:vsftpd"
  "httpd:httpd:Servidor web HTTP:2.2.9:httpd"
  "dovecot:dovecot:Servidor IMAP/POP3:2.2.10:dovecot"
  "samba:smb:Servidor Samba/CIFS:2.2.11:smb"
  "squid:squid:Proxy HTTP:2.2.12:squid"
  "net-snmp:snmpd:SNMP:2.2.13:snmpd"
  "ypserv:ypserv:Servidor NIS:2.2.14:ypserv"
  "telnet-server:telnet:Servidor Telnet (inseguro):2.2.15:telnet"
  "nfs-utils:nfs-server:Servidor NFS:2.2.16:nfs-server"
  "rpcbind:rpcbind:RPC bind:2.2.17:rpcbind"
  "ypbind:ypbind:Cliente NIS:2.3.1:ypbind"
  "rsh:rsh:Cliente RSH (inseguro):2.3.2:rsh"
  "talk:talk:Cliente Talk:2.3.3:talk"
  "telnet:telnet:Cliente Telnet (inseguro):2.3.4:telnet"
  "openldap-clients:ldap:Cliente LDAP:2.3.5:ldap"
)

# ==============================================
# FUNCION PARA MOSTRAR SPINNER
# ==============================================
show_spinner() {
  local pid=$1
  local msg="$2"
  local spin='-\|/'
  local i=0
  while kill -0 $pid 2>/dev/null; do
    i=$(((i + 1) % 4))
    printf "\r${YELLOW}[%c]${NC} %s" "${spin:$i:1}" "$msg"
    sleep 0.2
  done
  printf "\r${GREEN}[✓]${NC} %s${NC}\n" "$msg"
}

# ==============================================
# FUNCION PARA PREGUNTAR Y ELIMINAR
# ==============================================
ask_and_remove() {
  local package="$1"
  local service="$2"
  local description="$3"
  local cis_id="$4"
  local systemd_service="$5"

  # Verificar si el paquete esta instalado
  if ! rpm -q "$package" &>/dev/null; then
    return 0
  fi

  local version=$(rpm -q "$package")

  echo -e "\n${YELLOW}========================================${NC}"
  echo -e "${YELLOW}Paquete: $package${NC}"
  echo -e "${YELLOW}Version: $version${NC}"
  echo -e "${YELLOW}CIS ID: $cis_id${NC}"
  echo -e "${YELLOW}Descripcion: $description${NC}"
  echo -e "${YELLOW}========================================${NC}"

  # Mostrar estado del servicio
  echo -e "${BLUE}[i] Estado del servicio:${NC}"
  if systemctl is-active --quiet "$systemd_service" 2>/dev/null; then
    echo -e "${RED}  - Servicio ACTIVO${NC}"
  elif systemctl is-enabled --quiet "$systemd_service" 2>/dev/null; then
    echo -e "${YELLOW}  - Servicio HABILITADO (inactivo)${NC}"
  else
    echo -e "${GREEN}  - Servicio NO ACTIVO${NC}"
  fi

  # Preguntar si quiere eliminar
  echo -e "\n${YELLOW}¿Desea eliminar $package? (s/N): ${NC}"
  read -r confirm

  if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}[!] $package conservado${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  # Simular eliminacion para capturar dependencias
  echo -e "${BLUE}[i] Analizando dependencias (puede tomar unos segundos)...${NC}"

  # Ejecutar simulacion en background para mostrar spinner
  (simulate_and_capture_deps "$package" >/tmp/deps_$$) &
  show_spinner $! "Consultando dependencias de $package"

  local deps=$(cat /tmp/deps_$$ 2>/dev/null)
  rm -f /tmp/deps_$$

  if [ -n "$deps" ]; then
    local dep_count=$(echo "$deps" | wc -l)
    echo -e "${YELLOW}[!] Se eliminaran $dep_count paquetes en total:${NC}"
    echo "$deps" | sed 's/^/  - /'
  else
    echo -e "${YELLOW}[!] No se detectaron dependencias adicionales${NC}"
    echo -e "${YELLOW}    Se eliminara solo $package${NC}"
  fi

  # Preguntar confirmacion final
  echo -e "\n${RED}¿Confirma la eliminacion de $package y todas sus dependencias? (s/N): ${NC}"
  read -r confirm_final

  if [[ ! "$confirm_final" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}[!] Eliminacion cancelada, $package conservado${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  # Ejecutar eliminacion real
  echo -e "${YELLOW}[*] Eliminando $package...${NC}"

  # Detener servicio
  systemctl stop "$systemd_service" 2>/dev/null
  systemctl disable "$systemd_service" 2>/dev/null

  # Ejecutar remove
  if command -v yum &>/dev/null; then
    yum remove "$package" -y
  elif command -v dnf &>/dev/null; then
    dnf remove "$package" -y
  fi

  if ! rpm -q "$package" &>/dev/null; then
    echo -e "${GREEN}[✓] $package eliminado correctamente${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] No se pudo eliminar $package${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# VERIFICAR X11 (usa comodin)
# ==============================================
ask_x11() {
  X11_PACKAGES=$(rpm -qa xorg-x11-server\* 2>/dev/null)

  if [ -z "$X11_PACKAGES" ]; then
    return 0
  fi

  echo -e "\n${YELLOW}========================================${NC}"
  echo -e "${YELLOW}Paquete: xorg-x11-server* (X11)${NC}"
  echo -e "${YELLOW}CIS ID: 2.2.2${NC}"
  echo -e "${YELLOW}Descripcion: Interfaz grafica X Window (innecesaria en servidores)${NC}"
  echo -e "${YELLOW}========================================${NC}"

  echo -e "${RED}[!] Paquetes encontrados:${NC}"
  echo "$X11_PACKAGES" | sed 's/^/  - /'

  echo -e "\n${YELLOW}¿Desea eliminar todos los paquetes X11? (s/N): ${NC}"
  read -r confirm

  if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}[!] Paquetes X11 conservados${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  # Simular eliminacion de un paquete representativo
  local first_pkg=$(echo "$X11_PACKAGES" | head -1)
  echo -e "${BLUE}[i] Analizando dependencias (puede tomar unos segundos)...${NC}"

  (simulate_and_capture_deps "$first_pkg" >/tmp/x11_deps_$$) &
  show_spinner $! "Consultando dependencias de X11"

  local deps=$(cat /tmp/x11_deps_$$ 2>/dev/null)
  rm -f /tmp/x11_deps_$$

  if [ -n "$deps" ]; then
    local dep_count=$(echo "$deps" | wc -l)
    echo -e "${YELLOW}[!] Se eliminaran $dep_count paquetes en total:${NC}"
    echo "$deps" | head -20 | sed 's/^/  - /'
    if [ $dep_count -gt 20 ]; then
      echo "  - ... y $((dep_count - 20)) mas"
    fi
  else
    echo -e "${YELLOW}[!] No se detectaron dependencias adicionales${NC}"
  fi

  echo -e "\n${RED}¿Confirma la eliminacion de todos los paquetes X11? (s/N): ${NC}"
  read -r confirm_final

  if [[ ! "$confirm_final" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}[!] Eliminacion cancelada, X11 conservado${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  echo -e "${YELLOW}[*] Eliminando paquetes X11...${NC}"
  yum remove xorg-x11-server\* -y 2>/dev/null || dnf remove xorg-x11-server\* -y 2>/dev/null

  echo -e "${GREEN}[✓] Paquetes X11 eliminados${NC}"
  FIXED=$((FIXED + 1))
}

# ==============================================
# VERIFICAR MTA EN MODO LOCAL
# ==============================================
check_mta_local() {
  echo -e "\n${BLUE}[*] CIS 2.2.15 - Verificando MTA en modo local...${NC}"

  if ss -lntu 2>/dev/null | grep -qE ":(25|465|587)"; then
    echo -e "${RED}[!] MTA esta escuchando en puertos de red (25,465,587)${NC}"

    if rpm -q postfix &>/dev/null; then
      echo -e "${YELLOW}¿Desea configurar Postfix para solo localhost? (s/N): ${NC}"
      read -r confirm
      if [[ "$confirm" =~ ^[Ss]$ ]]; then
        cp /etc/postfix/main.cf /etc/postfix/main.cf.bak
        sed -i 's/^inet_interfaces =.*/inet_interfaces = localhost/' /etc/postfix/main.cf
        systemctl restart postfix
        echo -e "${GREEN}[✓] Postfix configurado para solo localhost${NC}"
        FIXED=$((FIXED + 1))
      fi
    elif rpm -q sendmail &>/dev/null; then
      echo -e "${YELLOW}Sendmail requiere configuracion manual${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] MTA no escucha en red o esta correctamente configurado${NC}"
  fi
}

# ==============================================
# MOSTRAR RESULTADO FINAL
# ==============================================
show_instructions() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Paquetes eliminados: ${GREEN}$FIXED${NC}"
  echo -e "  • Paquetes conservados: ${YELLOW}$WARNINGS${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR SERVICIOS ACTIVOS:${NC}"
  echo -e "  systemctl list-units --type=service | grep running"
  echo -e "  ss -tlnp"
}

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Hardening - Eliminacion de Servicios${NC}"
  echo -e "${GREEN}  CIS 2.2.2 - 2.3.5${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "${YELLOW}"
  echo "Este script revisara servicios innecesarios."
  echo ""
  echo "Para cada servicio encontrado:"
  echo "  1. Preguntara si desea eliminarlo"
  echo "  2. Simulara la eliminacion para mostrar dependencias"
  echo "  3. Mostrara que paquetes se eliminaran"
  echo "  4. Pedira confirmacion final"
  echo ""
  echo "NO se eliminara Rsync (se asume que es necesario)"
  echo ""
  echo -e "${GREEN}Presione Enter para comenzar...${NC}"
  read -r
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  show_intro

  for service_info in "${SERVICES[@]}"; do
    IFS=':' read -r package service desc cis_id systemd_service <<<"$service_info"
    ask_and_remove "$package" "$service" "$desc" "$cis_id" "$systemd_service"
  done

  ask_x11
  check_mta_local
  show_instructions
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
