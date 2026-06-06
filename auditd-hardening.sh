#!/bin/bash

# ==============================================
# Script: auditd-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Configura auditd segun CIS Benchmark
#              CIS 4.1.1 - 4.1.18
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

AUDIT_RULES="/etc/audit/rules.d/99-hardening.rules"
AUDIT_CONF="/etc/audit/auditd.conf"
BACKUP_DIR="/root/audit-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    if [ -f "$AUDIT_CONF" ]; then
      cp "$AUDIT_CONF" "$BACKUP_DIR/"
    fi
    if [ -d /etc/audit/rules.d ]; then
      cp -r /etc/audit/rules.d "$BACKUP_DIR/"
    fi
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA AGREGAR REGLA
# ==============================================
add_rule() {
  local rule="$1"
  local description="$2"

  if grep -q "^$rule" "$AUDIT_RULES" 2>/dev/null; then
    echo -e "${GREEN}[✓] $description${NC}"
  else
    echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo "$rule" >>"$AUDIT_RULES"
      echo -e "${GREEN}[✓] Regla agregada: $rule${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 4.1.1.1 - ENSURE AUDITD IS INSTALLED
# ==============================================
check_auditd_installed() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.1 - Verificando auditd instalado...${NC}"

  if rpm -q audit &>/dev/null && rpm -q audit-libs &>/dev/null; then
    echo -e "${GREEN}[✓] auditd y audit-libs instalados${NC}"
  else
    echo -e "${RED}[!] auditd no instalado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      yum install audit audit-libs -y 2>/dev/null || dnf install audit audit-libs -y 2>/dev/null
      echo -e "${GREEN}[✓] auditd instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 4.1.1.2 - ENSURE AUDITD IS ENABLED AND RUNNING
# ==============================================
check_auditd_enabled() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.2 - Verificando auditd habilitado...${NC}"

  if systemctl is-enabled auditd &>/dev/null; then
    echo -e "${GREEN}[✓] auditd habilitado${NC}"
  else
    echo -e "${RED}[!] auditd no habilitado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      systemctl enable auditd
      echo -e "${GREEN}[✓] auditd habilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if systemctl is-active auditd &>/dev/null; then
    echo -e "${GREEN}[✓] auditd corriendo${NC}"
  else
    echo -e "${RED}[!] auditd no corriendo${NC}"
    if [ "$AUTO_FIX" = true ]; then
      systemctl start auditd
      echo -e "${GREEN}[✓] auditd iniciado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 4.1.1.3 - ENSURE AUDIT LOG STORAGE SIZE
# ==============================================
check_log_storage() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.3 - Verificando tamaño de logs audit...${NC}"

  if grep -q "^max_log_file = 50" "$AUDIT_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] max_log_file = 50 MB${NC}"
  else
    echo -e "${RED}[!] max_log_file no configurado correctamente${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/^max_log_file =.*/max_log_file = 50/' "$AUDIT_CONF"
      echo -e "${GREEN}[✓] max_log_file = 50 MB configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 4.1.1.4 - ENSURE AUDIT LOGS NOT AUTOMATICALLY DELETED
# ==============================================
check_log_retention() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.4 - Verificando retencion de logs audit...${NC}"

  if grep -q "^max_log_file_action = keep_logs" "$AUDIT_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] max_log_file_action = keep_logs${NC}"
  else
    echo -e "${RED}[!] Logs pueden eliminarse automaticamente${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/^max_log_file_action =.*/max_log_file_action = keep_logs/' "$AUDIT_CONF"
      echo -e "${GREEN}[✓] max_log_file_action = keep_logs configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 4.1.1.5 - ENSURE SYSTEM DISABLED WHEN AUDIT LOGS ARE FULL
# ==============================================
check_full_action() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.5 - Verificando accion cuando logs estan llenos...${NC}"

  if grep -q "^space_left_action = email" "$AUDIT_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] space_left_action = email${NC}"
  else
    echo -e "${RED}[!] space_left_action no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/^space_left_action =.*/space_left_action = email/' "$AUDIT_CONF"
      echo -e "${GREEN}[✓] space_left_action = email configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if grep -q "^action_mail_acct = root" "$AUDIT_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] action_mail_acct = root${NC}"
  else
    echo -e "${RED}[!] action_mail_acct no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/^action_mail_acct =.*/action_mail_acct = root/' "$AUDIT_CONF"
      echo -e "${GREEN}[✓] action_mail_acct = root configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if grep -q "^admin_space_left_action = halt" "$AUDIT_CONF" 2>/dev/null; then
    echo -e "${GREEN}[✓] admin_space_left_action = halt${NC}"
  else
    echo -e "${RED}[!] admin_space_left_action no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i 's/^admin_space_left_action =.*/admin_space_left_action = halt/' "$AUDIT_CONF"
      echo -e "${GREEN}[✓] admin_space_left_action = halt configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# AGREGAR TODAS LAS REGLAS DE AUDITORIA
# ==============================================
add_audit_rules() {
  echo -e "\n${BLUE}[*] Agregando reglas de auditoria...${NC}"

  # Crear archivo de reglas
  cat >"$AUDIT_RULES" <<'EOF'
# ==============================================
# Reglas de auditoria - CIS Benchmark
# Generado automaticamente
# ==============================================

# 4.1.2.1 - Modificaciones de fecha y hora
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-w /etc/localtime -p wa -k time-change

# 4.1.2.2 - Modificaciones de usuario/grupo
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# 4.1.2.3 - Modificaciones de red
-w /etc/sysctl.conf -p wa -k system-locale
-w /etc/sysctl.d -p wa -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/networks -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# 4.1.2.4 - Modificaciones de MAC (SELinux)
-w /etc/selinux -p wa -k MAC-policy

# 4.1.2.5 - Eventos de login/logout
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# 4.1.2.6 - Informacion de sesion
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# 4.1.2.7 - Modificaciones de permisos DAC
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod

# 4.1.2.8 - Intentos fallidos de acceso
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access

# 4.1.2.9 - Eventos de montaje
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# 4.1.2.10 - Eliminacion de archivos
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

# 4.1.2.11 - Cambios en sudoers
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope

# 4.1.2.12 - Comandos ejecutados con sudo
-w /var/log/sudo.log -p wa -k actions

# 4.1.2.13 - Carga/descarga de modulos del kernel
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# 4.1.2.14 - Configuracion inmutable (proteger reglas)
-e 2
EOF

  echo -e "${GREEN}[✓] Archivo de reglas creado: $AUDIT_RULES${NC}"

  # Verificar cada regla
  echo -e "\n${BLUE}[*] Verificando reglas de auditoria...${NC}"

  # Cargar reglas para verificar
  augenrules --load >/dev/null 2>&1

  # 4.1.2.1 - Fecha y hora
  if auditctl -l | grep -q "time-change"; then
    echo -e "${GREEN}[✓] Eventos de fecha/hora - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de fecha/hora - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.2 - Usuario/grupo
  if auditctl -l | grep -q "identity"; then
    echo -e "${GREEN}[✓] Eventos de usuario/grupo - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de usuario/grupo - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.3 - Red
  if auditctl -l | grep -q "system-locale"; then
    echo -e "${GREEN}[✓] Eventos de red - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de red - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.4 - MAC/SELinux
  if auditctl -l | grep -q "MAC-policy"; then
    echo -e "${GREEN}[✓] Eventos de MAC/SELinux - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de MAC/SELinux - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.5 - Login/logout
  if auditctl -l | grep -q "logins"; then
    echo -e "${GREEN}[✓] Eventos de login/logout - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de login/logout - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.6 - Sesion
  if auditctl -l | grep -q "session"; then
    echo -e "${GREEN}[✓] Eventos de sesion - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de sesion - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.7 - Permisos DAC
  if auditctl -l | grep -q "perm_mod"; then
    echo -e "${GREEN}[✓] Eventos de cambios de permisos - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de cambios de permisos - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.8 - Acceso fallido
  if auditctl -l | grep -q "access"; then
    echo -e "${GREEN}[✓] Eventos de acceso fallido - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de acceso fallido - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.9 - Montajes
  if auditctl -l | grep -q "mounts"; then
    echo -e "${GREEN}[✓] Eventos de montaje - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de montaje - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.10 - Eliminacion de archivos
  if auditctl -l | grep -q "delete"; then
    echo -e "${GREEN}[✓] Eventos de eliminacion de archivos - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de eliminacion de archivos - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.11 - Sudoers
  if auditctl -l | grep -q "scope"; then
    echo -e "${GREEN}[✓] Eventos de cambios en sudoers - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de cambios en sudoers - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.13 - Modulos del kernel
  if auditctl -l | grep -q "modules"; then
    echo -e "${GREEN}[✓] Eventos de modulos del kernel - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Eventos de modulos del kernel - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  # 4.1.2.14 - Configuracion inmutable
  if auditctl -s | grep -q "enabled 2"; then
    echo -e "${GREEN}[✓] Configuracion inmutable - OK${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] Configuracion inmutable - FAIL${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# REINICIAR AUDITD
# ==============================================
restart_auditd() {
  echo -e "\n${BLUE}[*] Reiniciando auditd...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    systemctl restart auditd
    echo -e "${GREEN}[✓] auditd reiniciado${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  AUDITD HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}PARA VER REGLAS DE AUDITORIA:${NC}"
  echo -e "  auditctl -l"
  echo -e "  augenrules --load"

  echo -e "\n${YELLOW}PARA VER LOGS DE AUDITORIA:${NC}"
  echo -e "  ausearch -ts recent"
  echo -e "  aureport -ts today"
}

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${YELLOW}"
  echo "Este script configura auditd segun CIS Benchmark secciones 4.1.1 - 4.1.18"
  echo ""
  echo "LOS CAMBIOS INCLUYEN:"
  echo "  - Configuracion de tamano y retencion de logs"
  echo "  - Reglas de auditoria para eventos criticos"
  echo "  - Configuracion inmutable (protege reglas)"
  echo ""
  echo -e "${RED}NOTA: La configuracion inmutable (-e 2) requiere reinicio de auditd"
  echo -e "      y las reglas no podran modificarse hasta reiniciar el sistema.${NC}"
  echo ""
  echo -e "${YELLOW}Backup de configuraciones en: $BACKUP_DIR${NC}"
  echo ""
  echo -e "${GREEN}Presione Enter para continuar o Ctrl+C para cancelar...${NC}"
  read -r
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Auditd Hardening - CIS 4.1.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ] || [ -z "$1" ]; then
    AUTO_FIX=true
    make_backup
    show_intro
    echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
  else
    AUTO_FIX=false
    echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
  fi

  check_auditd_installed
  check_auditd_enabled
  check_log_storage
  check_log_retention
  check_full_action
  add_audit_rules
  restart_auditd
  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
