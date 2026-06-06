#!/bin/bash

# ==============================================
# Script: desintalar-paquetes-sin.usar.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Elimina paquetes innecesarios para reducir superficie de ataque
#              Basado en CIS Benchmark y buenas practicas de hardening
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

# ==============================================
# LISTA DE PAQUETES A REVISAR Y ELIMINAR
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

# Otros paquetes innecesarios
OTHER_PACKAGES=(
  "telnet:Cliente Telnet (inseguro)"
  "telnet-server:Servidor Telnet (inseguro)"
  "ftp:Cliente FTP"
  "vsftpd:Servidor FTP"
  "tftp:Cliente TFTP"
  "tftp-server:Servidor TFTP"
  "rsync:Herramienta de sincronizacion (si no se usa)"
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
# FUNCION PARA ELIMINAR PAQUETES
# ==============================================
remove_packages() {
  local package_name="$1"
  local description="$2"

  if rpm -q "$package_name" &>/dev/null; then
    local version=$(rpm -q "$package_name")
    echo -e "${RED}[!] $package_name esta instalado: $version${NC}"
    echo -e "${YELLOW}    $description${NC}"

    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Eliminando $package_name...${NC}"

      if command -v dnf &>/dev/null; then
        dnf remove "$package_name" -y 2>/dev/null
      else
        yum remove "$package_name" -y 2>/dev/null
      fi

      if ! rpm -q "$package_name" &>/dev/null; then
        echo -e "${GREEN}[✓] $package_name eliminado${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo eliminar $package_name${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: yum remove $package_name -y${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] $package_name no esta instalado${NC}"
  fi
}

# ==============================================
# MOSTRAR ADVERTENCIA
# ==============================================
show_warning() {
  echo -e "${RED}============================================${NC}"
  echo -e "${RED}  ADVERTENCIA IMPORTANTE${NC}"
  echo -e "${RED}============================================${NC}"
  echo -e "${YELLOW}"
  echo "Este script eliminara paquetes innecesarios del sistema."
  echo ""
  echo "ANTES DE EJECUTAR:"
  echo "  1. Asegurese de que NO necesita estos paquetes"
  echo "  2. Algunos paquetes (como httpd, mysql, postfix)"
  echo "     pueden ser necesarios para su aplicacion"
  echo "  3. Revise la lista de paquetes antes de ejecutar con --fix"
  echo ""
  echo "SERVICIOS QUE SE ELIMINARAN:"
  echo "  - X Window (interfaz grafica)"
  echo "  - Avahi, CUPS, DHCP, Bind (servicios de red)"
  echo "  - Sendmail, Postfix, Dovecot (servicios de correo)"
  echo "  - Herramientas de desarrollo (gcc, make, git)"
  echo "  - Herramientas de depuracion (strace, gdb)"
  echo "  - Compatibilidad, juegos y otros"
  echo -e "${RED}============================================${NC}"
  echo -e "${YELLOW}Pulse Ctrl+C ahora para cancelar, o presione Enter para continuar...${NC}"
  read -r
}

# ==============================================
# MOSTRAR INSTRUCCIONES
# ==============================================
show_instructions() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Paquetes eliminados: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias: ${YELLOW}$WARNINGS${NC}"

  if [ $FIXED -gt 0 ]; then
    echo -e "\n${YELLOW}[!] Se recomienda reiniciar el sistema${NC}"
  fi

  echo -e "\n${YELLOW}Para verificar que paquetes quedaron:${NC}"
  echo -e "  rpm -qa | grep -E \"(httpd|mysql|postfix|sendmail)\""
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Eliminacion de Paquetes Innecesarios${NC}"
  echo -e "${GREEN}============================================${NC}"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    show_warning
    echo -e "${YELLOW}[!] Modo automatico: eliminando paquetes...${NC}"
  else
    echo -e "${YELLOW}[!] Modo verificacion: no se eliminaran paquetes${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para eliminar${NC}"
  fi

  # SELinux packages
  echo -e "\n${BLUE}[*] Verificando paquetes de SELinux...${NC}"
  for pkg in "${SELINUX_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # X Window packages
  echo -e "\n${BLUE}[*] Verificando paquetes de X Window...${NC}"
  for pkg in "${XORG_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # Network services
  echo -e "\n${BLUE}[*] Verificando servicios de red...${NC}"
  for pkg in "${NETWORK_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # Mail services
  echo -e "\n${BLUE}[*] Verificando servicios de correo...${NC}"
  for pkg in "${MAIL_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # Development tools
  echo -e "\n${BLUE}[*] Verificando herramientas de desarrollo...${NC}"
  for pkg in "${DEV_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # Debug tools
  echo -e "\n${BLUE}[*] Verificando herramientas de depuracion...${NC}"
  for pkg in "${DEBUG_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # Games
  echo -e "\n${BLUE}[*] Verificando paquetes de juegos...${NC}"
  for pkg in "${GAMES_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # Compatibility
  echo -e "\n${BLUE}[*] Verificando paquetes de compatibilidad...${NC}"
  for pkg in "${COMPAT_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  # Other packages
  echo -e "\n${BLUE}[*] Verificando otros paquetes innecesarios...${NC}"
  for pkg in "${OTHER_PACKAGES[@]}"; do
    name="${pkg%%:*}"
    desc="${pkg##*:}"
    remove_packages "$name" "$desc"
  done

  show_instructions
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
