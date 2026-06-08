#!/bin/bash

# ==============================================
# Script: grub-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de GRUB según CIS Benchmark
#              Configura contraseña de bootloader
#              Agrega parámetros de seguridad al kernel
#              Compatible con RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

GRUB_CONFIG="/etc/default/grub"
GRUB_CFG="/boot/grub2/grub.cfg"
GRUB_USER_CFG="/boot/grub2/user.cfg"
GRUB_SCRIPT="/etc/grub.d/01_users"
BACKUP_DIR="/root/grub-backup-$(date +%Y%m%d-%H%M%S)"

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
  echo "  ./grub-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./grub-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    [ -f "$GRUB_CONFIG" ] && cp "$GRUB_CONFIG" "$BACKUP_DIR/"
    [ -f "$GRUB_CFG" ] && cp "$GRUB_CFG" "$BACKUP_DIR/"
    [ -f "$GRUB_USER_CFG" ] && cp "$GRUB_USER_CFG" "$BACKUP_DIR/"
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA AGREGAR PARAMETROS AL KERNEL
# ==============================================
add_kernel_param() {
  local param="$1"
  local description="$2"

  # Verificar si el parametro ya existe en GRUB_CMDLINE_LINUX
  if grep -q "^GRUB_CMDLINE_LINUX=.*$param" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] $description - ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"

  if [ "$AUTO_FIX" = true ]; then
    # Agregar el parametro a GRUB_CMDLINE_LINUX
    sed -i "s/^GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 $param\"/" "$GRUB_CONFIG"
    echo -e "${GREEN}[✓] $description agregado: $param${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR PERMISOS
# ==============================================
check_permissions() {
  local file="$1"
  local expected_perms="$2"
  local description="$3"

  if [ ! -f "$file" ]; then
    echo -e "${YELLOW}[!] $file no existe${NC}"
    return 1
  fi

  local current_perms=$(stat -c "%a" "$file" 2>/dev/null)
  local current_owner=$(stat -c "%U" "$file" 2>/dev/null)
  local current_group=$(stat -c "%G" "$file" 2>/dev/null)

  if [ "$current_perms" = "$expected_perms" ] && [ "$current_owner" = "root" ] && [ "$current_group" = "root" ]; then
    echo -e "${GREEN}[✓] $description permisos correctos: $expected_perms root:root${NC}"
    return 0
  fi

  echo -e "${RED}[!] $description permisos incorrectos: $current_perms $current_owner:$current_group (debe ser $expected_perms root:root)${NC}"

  if [ "$AUTO_FIX" = true ]; then
    chmod "$expected_perms" "$file"
    chown root:root "$file"
    echo -e "${GREEN}[✓] $description permisos corregidos${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR CONTRASEÑA DE GRUB
# ==============================================
check_grub_password() {
  echo -e "\n${BLUE}[*] 1.4.1 - Verificando contraseña de bootloader...${NC}"

  # Verificar si existe user.cfg con contraseña
  if [ -f "$GRUB_USER_CFG" ] && [ -s "$GRUB_USER_CFG" ]; then
    echo -e "${GREEN}[✓] Contraseña de bootloader configurada${NC}"
    return 0
  fi

  # Verificar si la contraseña está en grub.cfg
  if grep -q "^password\|^set superusers" "$GRUB_CFG" 2>/dev/null; then
    echo -e "${GREEN}[✓] Contraseña de bootloader configurada${NC}"
    return 0
  fi

  echo -e "${RED}[!] Contraseña de bootloader - NO CONFIGURADA${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${YELLOW}[!] Para establecer contraseña de GRUB, ejecute manualmente:${NC}"
    echo -e "  ${BLUE}grub2-setpassword${NC}"
    echo -e "${YELLOW}  Luego reinicie el sistema para que los cambios tomen efecto${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${YELLOW}  Recomendacion: Ejecutar 'grub2-setpassword' como root${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 1.4.2 - VERIFICAR PERMISOS DE ARCHIVOS GRUB
# ==============================================
check_grub_permissions() {
  echo -e "\n${BLUE}[*] 1.4.2 - Verificando permisos de archivos GRUB...${NC}"
  check_permissions "$GRUB_CFG" "600" "grub.cfg"
  check_permissions "$GRUB_USER_CFG" "600" "user.cfg" 2>/dev/null
}

# ==============================================
# 4.1.1.2 - AUDIT=1 EN BOOT (CORREGIDO)
# ==============================================
check_audit_boot() {
  echo -e "\n${BLUE}[*] 4.1.1.2 - Verificando auditoria de procesos previos a auditd...${NC}"

  if grep -q "audit=1" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] audit=1 configurado en GRUB_CMDLINE_LINUX${NC}"
    return 0
  fi

  echo -e "${RED}[!] audit=1 no configurado en GRUB_CMDLINE_LINUX${NC}"

  if [ "$AUTO_FIX" = true ]; then
    add_kernel_param "audit=1" "audit=1 (auditoria de procesos previos a auditd)"
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 4.1.1.3 - AUDIT_BACKLOG_LIMIT
# ==============================================
check_audit_backlog() {
  echo -e "\n${BLUE}[*] 4.1.1.3 - Verificando audit_backlog_limit...${NC}"

  if grep -q "audit_backlog_limit=8192" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] audit_backlog_limit=8192 configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] audit_backlog_limit=8192 no configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    add_kernel_param "audit_backlog_limit=8192" "audit_backlog_limit=8192 (tamaño de cola de auditoria)"
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 1.6.1.2 - ASEGURAR SELINUX NO DESHABILITADO EN BOOT
# ==============================================
check_selinux_boot() {
  echo -e "\n${BLUE}[*] 1.6.1.2 - Verificando SELinux no deshabilitado en boot...${NC}"

  if grep -q "selinux=0" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${RED}[!] selinux=0 encontrado en GRUB_CMDLINE_LINUX${NC}"
    if [ "$AUTO_FIX" = true ]; then
      # Eliminar selinux=0 de la linea
      sed -i 's/selinux=0//g' "$GRUB_CONFIG"
      sed -i 's/  / /g' "$GRUB_CONFIG"
      echo -e "${GREEN}[✓] selinux=0 eliminado de GRUB_CMDLINE_LINUX${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 1
  fi

  if grep -q "enforcing=0" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${RED}[!] enforcing=0 encontrado en GRUB_CMDLINE_LINUX${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/enforcing=0//g' "$GRUB_CONFIG"
      sed -i 's/  / /g' "$GRUB_CONFIG"
      echo -e "${GREEN}[✓] enforcing=0 eliminado de GRUB_CMDLINE_LINUX${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 1
  fi

  echo -e "${GREEN}[✓] SELinux no esta deshabilitado en boot${NC}"
  return 0
}

# ==============================================
# PARAMETROS ADICIONALES DE SEGURIDAD DEL KERNEL
# ==============================================
check_additional_params() {
  echo -e "\n${BLUE}[*] Verificando parametros adicionales de seguridad del kernel...${NC}"

  # Slab/SANITIZE (proteccion contra desbordamiento de memoria)
  if grep -q "slab_nomerge" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] slab_nomerge - proteccion contra merging de slabs${NC}"
  else
    echo -e "${RED}[!] slab_nomerge - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      add_kernel_param "slab_nomerge" "slab_nomerge (proteccion contra ataques de heap)"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Page allocator randomization
  if grep -q "page_alloc.shuffle=1" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] page_alloc.shuffle=1 - randomizacion de paginas de memoria${NC}"
  else
    echo -e "${RED}[!] page_alloc.shuffle=1 - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      add_kernel_param "page_alloc.shuffle=1" "page_alloc.shuffle=1 (randomizacion de paginas de memoria)"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Randomize kernel stack offset
  if grep -q "randomize_kstack_offset=on" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] randomize_kstack_offset=on - randomizacion de pila del kernel${NC}"
  else
    echo -e "${RED}[!] randomize_kstack_offset=on - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      add_kernel_param "randomize_kstack_offset=on" "randomize_kstack_offset=on (randomizacion de pila del kernel)"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# REGENERAR CONFIGURACION DE GRUB
# ==============================================
regenerate_grub() {
  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${BLUE}[*] Regenerando configuracion de GRUB...${NC}"

    # Regenerar grub.cfg
    if [ -d /sys/firmware/efi ]; then
      # Sistema UEFI
      grub2-mkconfig -o /boot/efi/EFI/*/grub.cfg 2>/dev/null || grub2-mkconfig -o /boot/grub2/grub.cfg
    else
      # Sistema BIOS
      grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[✓] Configuracion de GRUB regenerada${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al regenerar configuracion de GRUB${NC}"
    fi
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  GRUB HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACIONES:${NC}"
  echo -e "  cat /etc/default/grub | grep GRUB_CMDLINE_LINUX"
  echo -e "  grub2-mkconfig -o /boot/grub2/grub.cfg"

  echo -e "\n${YELLOW}PARA ESTABLECER CONTRASEÑA DE GRUB:${NC}"
  echo -e "  grub2-setpassword"

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
  echo -e "${GREEN}  GRUB Hardening - Seguridad del Bootloader${NC}"
  echo -e "${GREEN}============================================${NC}\n"

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

  # Ejecutar verificaciones/correcciones
  check_grub_password
  check_grub_permissions
  check_audit_boot
  check_audit_backlog
  check_selinux_boot
  check_additional_params

  # Regenerar configuracion de GRUB si se hicieron cambios
  if [ "$AUTO_FIX" = true ] && [ $FIXED -gt 0 ]; then
    regenerate_grub
    echo -e "\n${YELLOW}[!] Se recomienda reiniciar el sistema para aplicar los cambios${NC}"
  fi

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
