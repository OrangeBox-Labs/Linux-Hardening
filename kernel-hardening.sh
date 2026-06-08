#!/bin/bash

# ==============================================
# Script: kernel-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening del kernel y limites del sistema
# ==============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
FIXED=0
WARNINGS=0
AUTO_FIX=false

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
  echo "  ./kernel-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./kernel-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA VERIFICAR O AGREGAR PARAMETRO SYSCTL
# ==============================================
check_sysctl_param() {
  local param="$1"
  local expected="$2"
  local description="$3"
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  local current=$(sysctl -n "$param" 2>/dev/null)

  if [ -z "$current" ]; then
    echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      [ ! -f "$SYSCTL_FILE" ] && echo "# Kernel Hardening - $(date)" >"$SYSCTL_FILE"
      echo "$param = $expected" >>"$SYSCTL_FILE"
      sysctl -w "$param=$expected" >/dev/null
      echo -e "${GREEN}[✓] $description configurado: $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$current" = "$expected" ]; then
    echo -e "${GREEN}[✓] $description: $current${NC}"
  else
    echo -e "${RED}[!] $description: $current (debe ser $expected)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^$param.*/$param = $expected/" "$SYSCTL_FILE" 2>/dev/null
      echo "$param = $expected" >>"$SYSCTL_FILE"
      sysctl -w "$param=$expected" >/dev/null
      echo -e "${GREEN}[✓] $description corregido: $expected${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR O AGREGAR A LIMITS.CONF
# ==============================================
check_limits_param() {
  local entry="$1"
  local description="$2"
  local limits_file="/etc/security/limits.conf"

  if grep -q "^$entry" "$limits_file" 2>/dev/null; then
    echo -e "${GREEN}[✓] $description ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
  if [ "$AUTO_FIX" = true ]; then
    if grep -q "# End of file" "$limits_file" 2>/dev/null; then
      sed -i "/# End of file/i $entry" "$limits_file"
    else
      echo "$entry" >>"$limits_file"
    fi
    echo -e "${GREEN}[✓] $description configurado: $entry${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR O CONFIGURAR SYSTEMD-COREDUMP
# ==============================================
check_systemd_coredump() {
  if ! command -v systemd-coredump &>/dev/null || [ ! -f /etc/systemd/coredump.conf ]; then
    return 0
  fi

  echo -e "\n${YELLOW}[*] Verificando systemd-coredump...${NC}"

  if grep -q "^Storage=none" /etc/systemd/coredump.conf; then
    echo -e "${GREEN}[✓] systemd-coredump ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] systemd-coredump Storage no esta en 'none'${NC}"
  if [ "$AUTO_FIX" = true ]; then
    sed -i 's/^Storage=.*/Storage=none/' /etc/systemd/coredump.conf
    systemctl daemon-reload
    echo -e "${GREEN}[✓] systemd-coredump configurado${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 1. RESTRINGIR CORE DUMPS (CIS 1.5.1)
# ==============================================
restrict_core_dumps() {
  echo -e "\n${BLUE}[*] CIS 1.5.1 - Restringiendo core dumps...${NC}"
  check_sysctl_param "fs.suid_dumpable" "0" "fs.suid_dumpable"
  check_limits_param "* hard core 0" "Limite de core dump"
  check_systemd_coredump
}

# ==============================================
# 2. LIMITAR NUMERO DE PROCESOS (nproc)
# ==============================================
limit_nproc() {
  echo -e "\n${BLUE}[*] Limitando numero de procesos...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    local LIMITS_FILE="/etc/security/limits.d/90-nproc.conf"
    if [ ! -f "$LIMITS_FILE" ] || ! grep -q "hard nproc" "$LIMITS_FILE" 2>/dev/null; then
      echo "* hard nproc 1024" >"$LIMITS_FILE"
      echo -e "${GREEN}[✓] Limite de procesos configurado (1024)${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${GREEN}[✓] Limite de procesos ya configurado${NC}"
    fi
  else
    if [ -f /etc/security/limits.d/90-nproc.conf ] && grep -q "hard nproc" /etc/security/limits.d/90-nproc.conf 2>/dev/null; then
      echo -e "${GREEN}[✓] Limite de procesos configurado${NC}"
    else
      echo -e "${RED}[!] Limite de procesos NO CONFIGURADO${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 3. LIMITAR NUMERO DE ARCHIVOS ABIERTOS (nofile)
# ==============================================
limit_nofile() {
  echo -e "\n${BLUE}[*] Limitando archivos abiertos...${NC}"
  check_limits_param "* hard nofile 65536" "Limite de archivos abiertos"
}

# ==============================================
# 4. LIMITAR SESIONES SIMULTANEAS (maxlogins)
# ==============================================
limit_maxlogins() {
  echo -e "\n${BLUE}[*] Limitando sesiones simultaneas...${NC}"
  check_limits_param "* hard maxlogins 10" "Limite de sesiones simultaneas"
}

# ==============================================
# 5. RESTRINGIR ACCESO A DMESG
# ==============================================
restrict_dmesg() {
  echo -e "\n${BLUE}[*] Restringiendo acceso a dmesg...${NC}"
  check_sysctl_param "kernel.dmesg_restrict" "1" "kernel.dmesg_restrict"
}

# ==============================================
# 6. RESTRINGIR PTRACE
# ==============================================
restrict_ptrace() {
  echo -e "\n${BLUE}[*] Restringiendo ptrace...${NC}"
  check_sysctl_param "kernel.yama.ptrace_scope" "1" "kernel.yama.ptrace_scope"
}

# ==============================================
# 7. OCULTAR DIRECCIONES DEL KERNEL
# ==============================================
hide_kernel_addresses() {
  echo -e "\n${BLUE}[*] Ocultando direcciones del kernel...${NC}"
  check_sysctl_param "kernel.kptr_restrict" "2" "kernel.kptr_restrict"
}

# ==============================================
# 8. PROTECCION DE FIFOS Y HARDLINKS
# ==============================================
protect_filesystem() {
  echo -e "\n${BLUE}[*] Protegiendo filesystem...${NC}"
  check_sysctl_param "fs.protected_fifos" "1" "fs.protected_fifos"
  check_sysctl_param "fs.protected_hardlinks" "1" "fs.protected_hardlinks"
  check_sysctl_param "fs.protected_symlinks" "1" "fs.protected_symlinks"
}

# ==============================================
# 9. HARDENING DE RED
# ==============================================
network_hardening() {
  echo -e "\n${BLUE}[*] Aplicando hardening de red...${NC}"
  check_sysctl_param "net.ipv4.conf.all.accept_redirects" "0" "net.ipv4.conf.all.accept_redirects"
  check_sysctl_param "net.ipv4.conf.default.accept_redirects" "0" "net.ipv4.conf.default.accept_redirects"
  check_sysctl_param "net.ipv4.conf.all.send_redirects" "0" "net.ipv4.conf.all.send_redirects"
  check_sysctl_param "net.ipv4.conf.default.send_redirects" "0" "net.ipv4.conf.default.send_redirects"
  check_sysctl_param "net.ipv4.tcp_syncookies" "1" "net.ipv4.tcp_syncookies"
}

# ==============================================
# 10. SEGURIDAD DE MEMORIA
# ==============================================
memory_security() {
  echo -e "\n${BLUE}[*] Configurando seguridad de memoria...${NC}"
  check_sysctl_param "kernel.randomize_va_space" "2" "ASLR (kernel.randomize_va_space)"
  check_sysctl_param "vm.mmap_min_addr" "65536" "vm.mmap_min_addr"
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  KERNEL HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${YELLOW}[!] Se recomienda reiniciar el sistema para asegurar los cambios${NC}"
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Kernel Hardening y Limites del Sistema${NC}"
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
  fi

  # Ejecutar todas las verificaciones/correcciones
  restrict_core_dumps
  limit_nproc
  limit_nofile
  limit_maxlogins
  restrict_dmesg
  restrict_ptrace
  hide_kernel_addresses
  protect_filesystem
  network_hardening
  memory_security

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
