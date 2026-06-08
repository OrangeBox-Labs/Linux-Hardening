#!/bin/bash

# ==============================================
# Script: desintalar-paquetes-sin-usar.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Elimina paquetes innecesarios de forma interactiva
#              Muestra las dependencias antes de eliminar
#              Basado en CIS Benchmark y buenas practicas de hardening
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
  local deps=""

  if command -v dnf &>/dev/null; then
    # Para dnf, usar --assumeno y parsear la salida completa
    local output=$(dnf remove "$package" -y --assumeno 2>&1)

    # Buscar la seccion "Removing:" o "Removing unused dependencies:"
    # Formato: "  httpd                                      x86_64"
    deps=$(echo "$output" | grep -E "^(Removing|Erasing|  [a-z])" | grep -v "^Removing:" | awk '{print $1}' | sort -u)

    # Si no se encontraron, buscar lineas indentadas con dos espacios
    if [ -z "$deps" ]; then
      deps=$(echo "$output" | grep -E "^  [a-z]" | awk '{print $1}' | sort -u)
    fi

  elif command -v yum &>/dev/null; then
    # Para yum, usar --assumeno y parsear la salida
    local output=$(yum remove "$package" -y --assumeno 2>&1)
    deps=$(echo "$output" | grep -E "^  [a-z]" | awk '{print $1}' | sort -u)
  fi

  echo "$deps"
}

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
  local description="$2"

  # Verificar si el paquete esta instalado
  if ! rpm -q "$package" &>/dev/null; then
    return 0
  fi

  local version=$(rpm -q "$package")

  echo -e "\n${YELLOW}========================================${NC}"
  echo -e "${YELLOW}Paquete: $package${NC}"
  echo -e "${YELLOW}Version: $version${NC}"
  echo -e "${YELLOW}Descripcion: $description${NC}"
  echo -e "${YELLOW}========================================${NC}"

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

  if command -v dnf &>/dev/null; then
    dnf remove "$package" -y
  elif command -v yum &>/dev/null; then
    yum remove "$package" -y
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
# LISTA DE PAQUETES A VERIFICAR (SIN RSYNC)
# ==============================================

# Paquetes de SELinux (no necesarios si no se usa)
SELINUX_PACKAGES=(
  "setroubleshoot:Herramienta de notificaciones SELinux"
  "setroubleshoot-server:Servidor de notificaciones SELinux"
  "setroubleshoot-plugins:Plugins de setroubleshoot"
  "mcstrans:Traduccion de etiquetas SELinux"
)

# Paquetes de X Window (interfaz grafica - innecesarios en servidor)
XORG_PACKAGES=(
  "xorg-x11-server-Xorg:Servidor X Window"
  "xorg-x11-utils:Utilidades de X Window"
  "xorg-x11-xauth:Autenticacion X Window"
  "xorg-x11-server-common:Componentes comunes de X Window"
  "xorg-x11-fonts:Fuentes de X Window"
  "xorg-x11-drivers:Controladores de X Window"
)

# Paquetes de servicios de red innecesarios
NETWORK_PACKAGES=(
  "avahi:Descubrimiento de servicios mDNS/DNS-SD"
  "avahi-autoipd:AutoIP para Avahi"
  "cups:Servidor de impresion"
  "cups-client:Cliente de impresion"
  "cups-libs:Librerias de CUPS"
  "dhcp:Servidor DHCP"
  "dhcp-common:Componentes comunes de DHCP"
  "bind:Servidor DNS"
  "bind-chroot:Bind enjaulado"
  "rpcbind:RPC bind"
  "ypbind:Yellow Pages client"
  "ypserv:Yellow Pages server"
)

# Paquetes de servicios de correo innecesarios
MAIL_PACKAGES=(
  "sendmail:Servidor de correo Sendmail"
  "postfix:Servidor de correo Postfix"
  "dovecot:Servidor IMAP/POP3"
)

# Paquetes de compilacion y desarrollo (innecesarios en produccion)
DEV_PACKAGES=(
  "gcc:Compilador GCC"
  "gcc-c++:Compilador C++"
  "make:Herramienta make"
  "automake:Herramienta automake"
  "autoconf:Herramienta autoconf"
  "cmake:Herramienta cmake"
  "git:Sistema de control de versiones"
  "subversion:Sistema de control de versiones SVN"
  "kernel-devel:Archivos de desarrollo del kernel"
  "kernel-headers:Cabeceras del kernel"
  "elfutils-libelf-devel:Archivos de desarrollo"
)

# Paquetes de herramientas de depuracion
DEBUG_PACKAGES=(
  "strace:Herramienta de seguimiento de llamadas al sistema"
  "ltrace:Herramienta de seguimiento de llamadas a librerias"
  "gdb:Depurador GNU"
  "valgrind:Herramienta de deteccion de memoria"
  "systemtap:Herramienta de instrumentacion del sistema"
  "crash:Analizador de volcados de memoria"
)

# Paquetes de juegos y entretenimiento (innecesarios)
GAMES_PACKAGES=(
  "gnome-games:Juegos de GNOME"
  "kdegames:Juegos de KDE"
  "fortune-mod:Frase del dia"
)

# Paquetes de compatibilidad (versiones antiguas)
COMPAT_PACKAGES=(
  "compat-libstdc++-33:Librerias compatibilidad C++"
  "compat-db:Librerias compatibilidad base de datos"
  "compat-libcap1:Librerias compatibilidad capabilities"
)

# Otros paquetes innecesarios (SIN RSYNC)
OTHER_PACKAGES=(
  "telnet:Cliente Telnet (inseguro)"
  "telnet-server:Servidor Telnet (inseguro)"
  "ftp:Cliente FTP"
  "vsftpd:Servidor FTP"
  "tftp:Cliente TFTP"
  "tftp-server:Servidor TFTP"
  "nfs-utils:Cliente NFS (si no se usa)"
  "nfs-server:Servidor NFS"
  "samba:Cliente SMB/CIFS"
  "samba-server:Servidor Samba"
  "squid:Proxy cache (si no se usa)"
  "httpd:Servidor web (si no se usa)"
  "nginx:Servidor web (si no se usa)"
  "mariadb:Base de datos (si no se usa)"
  "mysql:Base de datos (si no se usa)"
  "postgresql:Base de datos (si no se usa)"
  "redis:Base de datos en memoria (si no se usa)"
  "mongodb:Base de datos NoSQL (si no se usa)"
)

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Hardening - Eliminacion de Paquetes${NC}"
  echo -e "${GREEN}  Basado en CIS Benchmark${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "${YELLOW}"
  echo "Este script revisara paquetes innecesarios en el sistema."
  echo ""
  echo "Para cada paquete encontrado:"
  echo "  1. Preguntara si desea eliminarlo"
  echo "  2. Simulara la eliminacion para mostrar dependencias"
  echo "  3. Mostrara que paquetes se eliminaran"
  echo "  4. Pedira confirmacion final"
  echo ""
  echo -e "${GREEN}Presione Enter para comenzar...${NC}"
  read -r
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

  echo -e "\n${YELLOW}PARA VERIFICAR PAQUETES INSTALADOS:${NC}"
  echo -e "  rpm -qa | grep -E \"(httpd|mysql|postfix|sendmail)\""
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  show_intro

  echo -e "${BLUE}[*] Verificando paquetes de SELinux...${NC}"
  for pkg in "${SELINUX_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando paquetes de X Window...${NC}"
  for pkg in "${XORG_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando servicios de red...${NC}"
  for pkg in "${NETWORK_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando servicios de correo...${NC}"
  for pkg in "${MAIL_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando herramientas de desarrollo...${NC}"
  for pkg in "${DEV_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando herramientas de depuracion...${NC}"
  for pkg in "${DEBUG_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando paquetes de juegos...${NC}"
  for pkg in "${GAMES_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando paquetes de compatibilidad...${NC}"
  for pkg in "${COMPAT_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  echo -e "\n${BLUE}[*] Verificando otros paquetes innecesarios...${NC}"
  for pkg in "${OTHER_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    ask_and_remove "$name" "$desc"
  done

  show_instructions
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
