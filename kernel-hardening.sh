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
NC='\033[0m'

# Contadores
FIXED=0
WARNINGS=0
AUTO_FIX=false

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  local file="$1"
  if [ -f "$file" ] && [ ! -f "${file}.bak.$(date +%Y%m%d)" ]; then
    cp "$file" "${file}.bak.$(date +%Y%m%d)"
    echo -e "${GREEN}[✓] Backup creado: ${file}.bak.$(date +%Y%m%d)${NC}"
  fi
}

# ==============================================
# FUNCION PARA AGREGAR A LIMITS.CONF
# ==============================================
add_to_limits_conf() {
  local entry="$1"
  local limits_file="/etc/security/limits.conf"

  # Verificar si ya existe la entrada
  if grep -q "^$entry" "$limits_file" 2>/dev/null; then
    return 0
  fi

  # Verificar si existe la linea # End of file
  if grep -q "# End of file" "$limits_file" 2>/dev/null; then
    sed -i "/# End of file/i $entry" "$limits_file"
  else
    echo "$entry" >>"$limits_file"
  fi
  return 1
}

# ==============================================
# 1. RESTRINGIR CORE DUMPS (CIS 1.5.1)
# ==============================================
restrict_core_dumps() {
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  echo -e "\n${YELLOW}[*] CIS 1.5.1 - Restringiendo core dumps...${NC}"

  # Backup de sysctl.conf si existe
  if [ -f /etc/sysctl.conf ]; then
    make_backup "/etc/sysctl.conf"
  fi

  # Crear archivo de sysctl si no existe
  if [ ! -f "$SYSCTL_FILE" ]; then
    make_backup "$SYSCTL_FILE" 2>/dev/null
    echo "# Kernel Hardening - $(date)" >"$SYSCTL_FILE"
  fi

  # Configurar fs.suid_dumpable
  if ! grep -q "fs.suid_dumpable" "$SYSCTL_FILE" 2>/dev/null; then
    echo "fs.suid_dumpable = 0" >>"$SYSCTL_FILE"
    sysctl -w fs.suid_dumpable=0
    echo -e "${GREEN}[✓] fs.suid_dumpable = 0${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] fs.suid_dumpable ya configurado${NC}"
  fi

  # Configurar limits.conf
  make_backup "/etc/security/limits.conf"
  if add_to_limits_conf "* hard core 0"; then
    echo -e "${GREEN}[✓] Core dump limit ya configurado${NC}"
  else
    echo -e "${GREEN}[✓] Core dump limit configurado${NC}"
    FIXED=$((FIXED + 1))
  fi

  # Configurar systemd-coredump si existe
  if command -v systemd-coredump &>/dev/null && [ -f /etc/systemd/coredump.conf ]; then
    make_backup "/etc/systemd/coredump.conf"
    if ! grep -q "Storage=none" /etc/systemd/coredump.conf; then
      sed -i 's/^Storage=.*/Storage=none/' /etc/systemd/coredump.conf
      systemctl daemon-reload
      echo -e "${GREEN}[✓] systemd-coredump configurado${NC}"
      FIXED=$((FIXED + 1))
    fi
  fi
}

# ==============================================
# 2. LIMITAR NUMERO DE PROCESOS (nproc)
# ==============================================
limit_nproc() {
  local LIMITS_FILE="/etc/security/limits.d/90-nproc.conf"

  echo -e "\n${YELLOW}[*] Limitando numero de procesos...${NC}"

  make_backup "$LIMITS_FILE" 2>/dev/null

  if [ ! -f "$LIMITS_FILE" ] || ! grep -q "hard nproc" "$LIMITS_FILE" 2>/dev/null; then
    echo "* hard nproc 1024" >"$LIMITS_FILE"
    echo -e "${GREEN}[✓] Limite de procesos configurado (1024)${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] Limite de procesos ya configurado${NC}"
  fi
}

# ==============================================
# 3. LIMITAR NUMERO DE ARCHIVOS ABIERTOS (nofile)
# ==============================================
limit_nofile() {
  echo -e "\n${YELLOW}[*] Limitando archivos abiertos...${NC}"

  make_backup "/etc/security/limits.conf"

  if add_to_limits_conf "* hard nofile 65536"; then
    echo -e "${GREEN}[✓] Limite de archivos ya configurado${NC}"
  else
    echo -e "${GREEN}[✓] Limite de archivos configurado (65536)${NC}"
    FIXED=$((FIXED + 1))
  fi
}

# ==============================================
# 4. LIMITAR SESIONES SIMULTANEAS (maxlogins)
# ==============================================
limit_maxlogins() {
  echo -e "\n${YELLOW}[*] Limitando sesiones simultaneas...${NC}"

  make_backup "/etc/security/limits.conf"

  if add_to_limits_conf "* hard maxlogins 10"; then
    echo -e "${GREEN}[✓] Limite de sesiones ya configurado${NC}"
  else
    echo -e "${GREEN}[✓] Limite de sesiones configurado (10)${NC}"
    FIXED=$((FIXED + 1))
  fi
}

# ==============================================
# 5. RESTRINGIR ACCESO A DMESG
# ==============================================
restrict_dmesg() {
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  echo -e "\n${YELLOW}[*] Restringiendo acceso a dmesg...${NC}"

  if ! grep -q "kernel.dmesg_restrict" "$SYSCTL_FILE" 2>/dev/null; then
    echo "kernel.dmesg_restrict = 1" >>"$SYSCTL_FILE"
    sysctl -w kernel.dmesg_restrict=1
    echo -e "${GREEN}[✓] kernel.dmesg_restrict = 1${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] kernel.dmesg_restrict ya configurado${NC}"
  fi
}

# ==============================================
# 6. RESTRINGIR PTRACE
# ==============================================
restrict_ptrace() {
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  echo -e "\n${YELLOW}[*] Restringiendo ptrace...${NC}"

  if ! grep -q "kernel.yama.ptrace_scope" "$SYSCTL_FILE" 2>/dev/null; then
    echo "kernel.yama.ptrace_scope = 1" >>"$SYSCTL_FILE"
    sysctl -w kernel.yama.ptrace_scope=1
    echo -e "${GREEN}[✓] kernel.yama.ptrace_scope = 1${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] kernel.yama.ptrace_scope ya configurado${NC}"
  fi
}

# ==============================================
# 7. OCULTAR DIRECCIONES DEL KERNEL
# ==============================================
hide_kernel_addresses() {
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  echo -e "\n${YELLOW}[*] Ocultando direcciones del kernel...${NC}"

  if ! grep -q "kernel.kptr_restrict" "$SYSCTL_FILE" 2>/dev/null; then
    echo "kernel.kptr_restrict = 2" >>"$SYSCTL_FILE"
    sysctl -w kernel.kptr_restrict=2
    echo -e "${GREEN}[✓] kernel.kptr_restrict = 2${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] kernel.kptr_restrict ya configurado${NC}"
  fi
}

# ==============================================
# 8. PROTECCION DE FIFOS Y HARDLINKS
# ==============================================
protect_filesystem() {
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  echo -e "\n${YELLOW}[*] Protegiendo filesystem...${NC}"

  if ! grep -q "fs.protected_fifos" "$SYSCTL_FILE" 2>/dev/null; then
    echo "fs.protected_fifos = 1" >>"$SYSCTL_FILE"
    sysctl -w fs.protected_fifos=1
    echo -e "${GREEN}[✓] fs.protected_fifos = 1${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] fs.protected_fifos ya configurado${NC}"
  fi

  if ! grep -q "fs.protected_hardlinks" "$SYSCTL_FILE" 2>/dev/null; then
    echo "fs.protected_hardlinks = 1" >>"$SYSCTL_FILE"
    sysctl -w fs.protected_hardlinks=1
    echo -e "${GREEN}[✓] fs.protected_hardlinks = 1${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] fs.protected_hardlinks ya configurado${NC}"
  fi

  if ! grep -q "fs.protected_symlinks" "$SYSCTL_FILE" 2>/dev/null; then
    echo "fs.protected_symlinks = 1" >>"$SYSCTL_FILE"
    sysctl -w fs.protected_symlinks=1
    echo -e "${GREEN}[✓] fs.protected_symlinks = 1${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] fs.protected_symlinks ya configurado${NC}"
  fi
}

# ==============================================
# 9. HARDENING DE RED
# ==============================================
network_hardening() {
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  echo -e "\n${YELLOW}[*] Aplicando hardening de red...${NC}"

  if ! grep -q "net.ipv4.conf.all.accept_redirects" "$SYSCTL_FILE" 2>/dev/null; then
    echo "net.ipv4.conf.all.accept_redirects = 0" >>"$SYSCTL_FILE"
    echo "net.ipv4.conf.default.accept_redirects = 0" >>"$SYSCTL_FILE"
    sysctl -w net.ipv4.conf.all.accept_redirects=0
    echo -e "${GREEN}[✓] Redirecciones ICMP deshabilitadas${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] net.ipv4.accept_redirects ya configurado${NC}"
  fi

  if ! grep -q "net.ipv4.conf.all.send_redirects" "$SYSCTL_FILE" 2>/dev/null; then
    echo "net.ipv4.conf.all.send_redirects = 0" >>"$SYSCTL_FILE"
    echo "net.ipv4.conf.default.send_redirects = 0" >>"$SYSCTL_FILE"
    sysctl -w net.ipv4.conf.all.send_redirects=0
    echo -e "${GREEN}[✓] Envio de redirecciones deshabilitado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] net.ipv4.send_redirects ya configurado${NC}"
  fi

  if ! grep -q "net.ipv4.tcp_syncookies" "$SYSCTL_FILE" 2>/dev/null; then
    echo "net.ipv4.tcp_syncookies = 1" >>"$SYSCTL_FILE"
    sysctl -w net.ipv4.tcp_syncookies=1
    echo -e "${GREEN}[✓] SYN cookies activadas${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] net.ipv4.tcp_syncookies ya configurado${NC}"
  fi
}

# ==============================================
# 10. SEGURIDAD DE MEMORIA
# ==============================================
memory_security() {
  local SYSCTL_FILE="/etc/sysctl.d/99-cis-hardening.conf"

  echo -e "\n${YELLOW}[*] Configurando seguridad de memoria...${NC}"

  if ! grep -q "kernel.randomize_va_space" "$SYSCTL_FILE" 2>/dev/null; then
    echo "kernel.randomize_va_space = 2" >>"$SYSCTL_FILE"
    sysctl -w kernel.randomize_va_space=2
    echo -e "${GREEN}[✓] ASLR activado (randomize_va_space = 2)${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] kernel.randomize_va_space ya configurado${NC}"
  fi

  if ! grep -q "vm.mmap_min_addr" "$SYSCTL_FILE" 2>/dev/null; then
    echo "vm.mmap_min_addr = 65536" >>"$SYSCTL_FILE"
    sysctl -w vm.mmap_min_addr=65536
    echo -e "${GREEN}[✓] vm.mmap_min_addr = 65536${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${GREEN}[✓] vm.mmap_min_addr ya configurado${NC}"
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Kernel Hardening y Limites del Sistema${NC}"
  echo -e "${GREEN}============================================${NC}"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    echo -e "${YELLOW}[!] Modo automatico: se aplicaran correcciones sin preguntar${NC}"
    echo -e "${YELLOW}[!] 3 segundos para cancelar (Ctrl+C)...${NC}"
    sleep 3

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
  fi

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  RESUMEN${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "  • Configuraciones corregidas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "${YELLOW}[!] Se recomienda reiniciar el sistema para asegurar los cambios${NC}"
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
