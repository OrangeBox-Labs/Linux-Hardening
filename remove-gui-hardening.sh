#!/bin/bash

# ==============================================
# Script: remove-gui-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Elimina interfaz grafica y aplica hardening
#              CIS 1.8.1, 1.8.2, 1.8.3, 1.8.4
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/gui-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# BANNER PARA GDM
# ==============================================
GDM_BANNER="Autorizado por: www.orangebox.cl - Acceso controlado. Todo intento no autorizado sera reportado."

# ==============================================
# CREAR DIRECTORIO DE BACKUP
# ==============================================
create_backup_dir() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    echo -e "${GREEN}[✓] Directorio de backup creado: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# 1.8.1 - ELIMINAR GNOME DISPLAY MANAGER
# ==============================================
remove_gdm() {
  echo -e "\n${BLUE}[*] CIS 1.8.1 - Verificando GNOME Display Manager...${NC}"

  if rpm -q gdm &>/dev/null; then
    local version=$(rpm -q gdm)
    echo -e "${RED}[!] GDM esta instalado: $version${NC}"
    echo -e "${YELLOW}    GDM no es necesario en servidores sin interfaz grafica${NC}"

    # Verificar si hay otros display managers
    if rpm -q lightdm &>/dev/null; then
      echo -e "${YELLOW}[!] LightDM tambien esta instalado${NC}"
    fi
    if rpm -q sddm &>/dev/null; then
      echo -e "${YELLOW}[!] SDDM tambien esta instalado${NC}"
    fi

    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Eliminando paquetes de display manager...${NC}"

      # Detener servicio si esta corriendo
      systemctl stop gdm 2>/dev/null
      systemctl disable gdm 2>/dev/null

      # Eliminar GDM y otros display managers
      yum remove gdm lightdm sddm -y 2>/dev/null || dnf remove gdm lightdm sddm -y 2>/dev/null

      # Eliminar grupos de paquetes de GUI
      yum groupremove "GNOME Desktop" "Graphical Administration Tools" -y 2>/dev/null
      dnf groupremove "GNOME Desktop" "Graphical Administration Tools" -y 2>/dev/null

      if ! rpm -q gdm &>/dev/null; then
        echo -e "${GREEN}[✓] GDM eliminado correctamente${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo eliminar GDM${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: yum remove gdm lightdm sddm -y${NC}"
      echo -e "${YELLOW}    Luego: yum groupremove 'GNOME Desktop' -y${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] GDM no esta instalado${NC}"
  fi
}

# ==============================================
# 1.8.2 - CONFIGURAR BANNER DE GDM
# ==============================================
configure_gdm_banner() {
  echo -e "\n${BLUE}[*] CIS 1.8.2 - Configurando banner de GDM...${NC}"

  # Verificar si GDM esta instalado (si no, no es necesario)
  if ! rpm -q gdm &>/dev/null; then
    echo -e "${GREEN}[✓] GDM no instalado, no se requiere banner${NC}"
    return 0
  fi

  # Crear directorios necesarios
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p /etc/dconf/profile
    mkdir -p /etc/dconf/db/gdm.d

    # Configurar perfil de GDM
    cat >/etc/dconf/profile/gdm <<'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
    echo -e "${GREEN}[✓] Perfil GDM configurado${NC}"

    # Configurar banner
    cat >/etc/dconf/db/gdm.d/01-banner-message <<EOF
[org/gnome/login-screen]
banner-message-enable=true
banner-message-text='$GDM_BANNER'
disable-user-list=true
EOF
    echo -e "${GREEN}[✓] Banner GDM configurado${NC}"

    # Actualizar base de datos dconf
    dconf update 2>/dev/null
    echo -e "${GREEN}[✓] Base de datos dconf actualizada${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}    Recomendacion: Configurar banner en GDM${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 1.8.3 - DESHABILITAR MUESTRA DE ULTIMO USUARIO
# ==============================================
disable_last_user() {
  echo -e "\n${BLUE}[*] CIS 1.8.3 - Deshabilitando muestra de ultimo usuario...${NC}"

  if ! rpm -q gdm &>/dev/null; then
    echo -e "${GREEN}[✓] GDM no instalado, no es necesario configurar${NC}"
    return 0
  fi

  if [ "$AUTO_FIX" = true ]; then
    mkdir -p /etc/dconf/db/gdm.d

    # Agregar o actualizar configuracion
    if [ -f /etc/dconf/db/gdm.d/00-login-screen ]; then
      if ! grep -q "disable-user-list=true" /etc/dconf/db/gdm.d/00-login-screen; then
        echo "disable-user-list=true" >>/etc/dconf/db/gdm.d/00-login-screen
      fi
    else
      cat >/etc/dconf/db/gdm.d/00-login-screen <<'EOF'
[org/gnome/login-screen]
# Do not show the user list
disable-user-list=true
EOF
    fi

    dconf update 2>/dev/null
    echo -e "${GREEN}[✓] Muestra de ultimo usuario deshabilitada${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}    Recomendacion: Configurar disable-user-list=true${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 1.8.4 - DESHABILITAR XDMCP
# ==============================================
disable_xdmcp() {
  echo -e "\n${BLUE}[*] CIS 1.8.4 - Verificando XDMCP...${NC}"

  if [ -f /etc/gdm/custom.conf ]; then
    if grep -q "^Enable=true" /etc/gdm/custom.conf; then
      echo -e "${RED}[!] XDMCP esta habilitado (inseguro)${NC}"

      if [ "$AUTO_FIX" = true ]; then
        cp /etc/gdm/custom.conf "$BACKUP_DIR/custom.conf.bak"
        sed -i 's/^Enable=true/#Enable=true/' /etc/gdm/custom.conf
        echo -e "${GREEN}[✓] XDMCP deshabilitado${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${YELLOW}    Recomendacion: Deshabilitar XDMCP en /etc/gdm/custom.conf${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${GREEN}[✓] XDMCP no esta habilitado${NC}"
    fi
  else
    echo -e "${GREEN}[✓] /etc/gdm/custom.conf no existe, XDMCP deshabilitado por defecto${NC}"
  fi
}

# ==============================================
# VERIFICAR Y ELIMINAR PAQUETES DE GUI ADICIONALES
# ==============================================
remove_extra_gui_packages() {
  echo -e "\n${BLUE}[*] Verificando paquetes de GUI adicionales...${NC}"

  GUI_PACKAGES=(
    "xorg-x11-server-Xorg"
    "xorg-x11-utils"
    "xorg-x11-xauth"
    "xorg-x11-server-common"
    "xorg-x11-fonts"
    "xorg-x11-drivers"
    "gnome-desktop"
    "gnome-shell"
    "gnome-terminal"
    "nautilus"
    "gdm"
    "lightdm"
    "sddm"
    "kde-desktop"
    "plasma-desktop"
  )

  for package in "${GUI_PACKAGES[@]}"; do
    if rpm -q "$package" &>/dev/null; then
      echo -e "${RED}[!] $package esta instalado${NC}"
      if [ "$AUTO_FIX" = true ]; then
        yum remove "$package" -y 2>/dev/null || dnf remove "$package" -y 2>/dev/null
        echo -e "${GREEN}[✓] $package eliminado${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done
}

# ==============================================
# CAMBIAR A MODO TEXTO (runlevel 3)
# ==============================================
set_text_mode() {
  echo -e "\n${BLUE}[*] Configurando modo texto (runlevel 3)...${NC}"

  current_target=$(systemctl get-default)

  if [ "$current_target" = "graphical.target" ]; then
    echo -e "${YELLOW}[!] Sistema en modo grafico (graphical.target)${NC}"

    if [ "$AUTO_FIX" = true ]; then
      systemctl set-default multi-user.target
      echo -e "${GREEN}[✓] Sistema configurado a modo texto (multi-user.target)${NC}"
      echo -e "${YELLOW}[!] Se requiere reinicio para aplicar${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: systemctl set-default multi-user.target${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] Sistema ya esta en modo texto${NC}"
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
  echo "Este script eliminara la interfaz grafica del servidor."
  echo ""
  echo "SE ELIMINARAN:"
  echo "  - GNOME Display Manager (GDM)"
  echo "  - X Window System"
  echo "  - Entornos graficos (GNOME, KDE, etc.)"
  echo "  - Paquetes relacionados con GUI"
  echo ""
  echo "DESPUES DE ESTE CAMBIO:"
  echo "  - No podra usar interfaz grafica"
  echo "  - Solo acceso por consola o SSH"
  echo "  - El servidor arrancara en modo texto"
  echo ""
  echo "Backup de configuraciones en: $BACKUP_DIR"
  echo ""
  echo -e "${RED}¿Esta seguro que desea continuar? (s/N): ${NC}"
  read -r confirm

  if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}[!] Operacion cancelada por el usuario${NC}"
    exit 0
  fi
}

# ==============================================
# MOSTRAR INSTRUCCIONES FINALES
# ==============================================
show_instructions() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR:${NC}"
  echo -e "  systemctl get-default"
  echo -e "  rpm -qa | grep -E 'gdm|lightdm|xorg|gnome'"

  echo -e "\n${YELLOW}PARA RESTAURAR MODO GRAFICO:${NC}"
  echo -e "  systemctl set-default graphical.target"
  echo -e "  yum install gdm -y"
  echo -e "  systemctl start gdm"

  if [ $FIXED -gt 0 ]; then
    echo -e "\n${YELLOW}[!] SE RECOMIENDA REINICIAR EL SISTEMA${NC}"
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Hardening - Eliminacion de GUI${NC}"
  echo -e "${GREEN}  CIS 1.8.1 - 1.8.4${NC}"
  echo -e "${GREEN}============================================${NC}"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ] || [ -z "$1" ]; then
    AUTO_FIX=true
    create_backup_dir
    show_warning
    echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
  else
    AUTO_FIX=false
    echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
  fi

  remove_gdm
  remove_extra_gui_packages
  configure_gdm_banner
  disable_last_user
  disable_xdmcp
  set_text_mode

  show_instructions
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
