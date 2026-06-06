#!/bin/bash

# ==============================================
# Script: configure-login-banners.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Configura banners de advertencia de login
#              CIS 1.7.1, 1.7.2, 1.7.3, 1.7.5, 1.7.6, 1.7.7
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/banners-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# BANNER PREDETERMINADO
# ==============================================
BANNER_TEXT="
*******************************************************************************
                         SISTEMA DE ACCESO CONTROLADO
                        Hardening por: www.orangebox.cl
*******************************************************************************

Este servidor ha sido endurecido siguiendo estandares de seguridad CIS Benchmark.
El acceso no autorizado esta estrictamente prohibido.

CUALQUIER INTENTO DE ACCESO NO AUTORIZADO SERA:
- Registrado y monitoreado
- Reportado a las autoridades competentes
- Utilizado con fines legales

AL INGRESAR ACEPTA:
- Las condiciones de uso del sistema
- Que su actividad puede ser monitoreada las 24/7
- Que la informacion obtenida es confidencial
- Que los intentos no autorizados seran penalizados

Este sistema utiliza:
- SELinux en modo enforcing
- Firewall perimetral
- Monitoreo de integridad de archivos
- Deteccion de intrusiones

*******************************************************************************
"

# ==============================================
# FUNCION PARA HACER BACKUP Y CONFIGURAR ARCHIVO
# ==============================================
configure_banner_file() {
  local file="$1"
  local description="$2"

  echo -e "\n${BLUE}[*] Configurando $description: $file${NC}"

  if [ -f "$file" ]; then
    if [ ! -f "${BACKUP_DIR}/$(basename $file).bak" ]; then
      cp "$file" "${BACKUP_DIR}/$(basename $file).bak"
      echo -e "${GREEN}[✓] Backup creado: ${BACKUP_DIR}/$(basename $file).bak${NC}"
    fi
    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[!] $file existia, se ha respaldado y sera reemplazado${NC}"
    fi
  fi

  if [ "$AUTO_FIX" = true ]; then
    echo "$BANNER_TEXT" >"$file"
    echo -e "${GREEN}[✓] Banner configurado en $file${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}[!] Se requiere configurar $file${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA CONFIGURAR PERMISOS
# ==============================================
configure_permissions() {
  local file="$1"
  local perms="$2"
  local owner="$3"
  local group="$4"

  echo -e "\n${BLUE}[*] Configurando permisos de $file${NC}"

  local needs_fix=0

  if [ -f "$file" ]; then
    current_perms=$(stat -c "%a" "$file" 2>/dev/null)
    current_owner=$(stat -c "%U" "$file" 2>/dev/null)
    current_group=$(stat -c "%G" "$file" 2>/dev/null)

    if [ "$current_perms" != "$perms" ]; then
      echo -e "${RED}[!] Permisos incorrectos: $current_perms (debe ser $perms)${NC}"
      needs_fix=1
    else
      echo -e "${GREEN}[✓] Permisos correctos: $current_perms${NC}"
    fi

    if [ "$current_owner" != "$owner" ]; then
      echo -e "${RED}[!] Propietario incorrecto: $current_owner (debe ser $owner)${NC}"
      needs_fix=1
    else
      echo -e "${GREEN}[✓] Propietario correcto: $current_owner${NC}"
    fi

    if [ "$current_group" != "$group" ]; then
      echo -e "${RED}[!] Grupo incorrecto: $current_group (debe ser $group)${NC}"
      needs_fix=1
    else
      echo -e "${GREEN}[✓] Grupo correcto: $current_group${NC}"
    fi
  else
    echo -e "${YELLOW}[!] $file no existe, se creara${NC}"
    needs_fix=1
  fi

  if [ $needs_fix -eq 1 ] && [ "$AUTO_FIX" = true ]; then
    if [ -f "$file" ]; then
      chmod "$perms" "$file"
      chown "$owner:$group" "$file"
      echo -e "${GREEN}[✓] Permisos y propietario corregidos en $file${NC}"
      FIXED=$((FIXED + 1))
    fi
  elif [ $needs_fix -eq 1 ]; then
    echo -e "${YELLOW}    Recomendacion: chmod $perms $file && chown $owner:$group $file${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

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
# CONFIGURAR ETC/MOTD (CIS 1.7.1, 1.7.5)
# ==============================================
configure_motd() {
  echo -e "\n${BLUE}[*] CIS 1.7.1, 1.7.5 - Configurando /etc/motd${NC}"
  configure_banner_file "/etc/motd" "Message of the Day"
  configure_permissions "/etc/motd" "644" "root" "root"
}

# ==============================================
# CONFIGURAR ETC/ISSUE (CIS 1.7.2, 1.7.6)
# ==============================================
configure_issue() {
  echo -e "\n${BLUE}[*] CIS 1.7.2, 1.7.6 - Configurando /etc/issue${NC}"
  configure_banner_file "/etc/issue" "Local login banner"
  configure_permissions "/etc/issue" "644" "root" "root"
}

# ==============================================
# CONFIGURAR ETC/ISSUE.NET (CIS 1.7.3, 1.7.7)
# ==============================================
configure_issue_net() {
  echo -e "\n${BLUE}[*] CIS 1.7.3, 1.7.7 - Configurando /etc/issue.net${NC}"
  configure_banner_file "/etc/issue.net" "Remote login banner"
  configure_permissions "/etc/issue.net" "644" "root" "root"
}

# ==============================================
# CONFIGURAR SSH BANNER (opcional)
# ==============================================
configure_ssh_banner() {
  echo -e "\n${BLUE}[*] Configurando banner en SSH...${NC}"

  if [ -f /etc/ssh/sshd_config ]; then
    if grep -q "^Banner" /etc/ssh/sshd_config; then
      current_banner=$(grep "^Banner" /etc/ssh/sshd_config | awk '{print $2}')
      if [ "$current_banner" = "/etc/issue.net" ]; then
        echo -e "${GREEN}[✓] Banner ya configurado en SSH${NC}"
      else
        echo -e "${YELLOW}[!] Banner apunta a $current_banner, no a /etc/issue.net${NC}"
        if [ "$AUTO_FIX" = true ]; then
          sed -i 's|^Banner.*|Banner /etc/issue.net|' /etc/ssh/sshd_config
          systemctl restart sshd
          echo -e "${GREEN}[✓] Banner corregido en SSH${NC}"
          FIXED=$((FIXED + 1))
        fi
      fi
    else
      echo -e "${YELLOW}[!] Banner no configurado en SSH${NC}"
      if [ "$AUTO_FIX" = true ]; then
        echo "Banner /etc/issue.net" >>/etc/ssh/sshd_config
        systemctl restart sshd
        echo -e "${GREEN}[✓] Banner configurado en SSH${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${YELLOW}    Recomendacion: Agregar 'Banner /etc/issue.net' a /etc/ssh/sshd_config${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
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
  echo "Este script configurara los banners de advertencia de login."
  echo ""
  echo "Los banners se mostraran a los usuarios al iniciar sesion."
  echo ""
  echo "El banner incluye:"
  echo "  - Aviso de acceso controlado"
  echo "  - Hardening realizado por www.orangebox.cl"
  echo "  - Advertencia sobre monitoreo y reporte"
  echo ""
  echo "Los archivos existentes seran respaldados en:"
  echo "  $BACKUP_DIR"
  echo ""
  echo -e "${RED}============================================${NC}"
  echo -e "${YELLOW}Pulse Ctrl+C ahora para cancelar, o presione Enter para continuar...${NC}"
  read -r
}

# ==============================================
# MOSTRAR INSTRUCCIONES
# ==============================================
show_instructions() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  CONFIGURACION COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}ARCHIVOS CONFIGURADOS:${NC}"
  echo -e "  /etc/motd - Mensaje del dia (se muestra despues del login)"
  echo -e "  /etc/issue - Banner de login local (consola fisica)"
  echo -e "  /etc/issue.net - Banner de login remoto (SSH)"

  echo -e "\n${YELLOW}PARA VERIFICAR:${NC}"
  echo -e "  cat /etc/motd"
  echo -e "  cat /etc/issue"
  echo -e "  cat /etc/issue.net"
  echo -e "  stat /etc/motd /etc/issue /etc/issue.net"
  echo -e "  grep Banner /etc/ssh/sshd_config"

  echo -e "\n${YELLOW}PARA RESTAURAR BACKUP:${NC}"
  echo -e "  cp $BACKUP_DIR/motd.bak /etc/motd"
  echo -e "  cp $BACKUP_DIR/issue.bak /etc/issue"
  echo -e "  cp $BACKUP_DIR/issue.net.bak /etc/issue.net"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Configuracion de Banners de Login${NC}"
  echo -e "${GREEN}  CIS 1.7.1 - 1.7.7${NC}"
  echo -e "${GREEN}============================================${NC}"

  #if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
  AUTO_FIX=true
  show_warning
  create_backup_dir
  echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
  #else
  echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
  echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
  #fi

  configure_motd
  configure_issue
  configure_issue_net
  configure_ssh_banner

  show_instructions
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
