#!/bin/bash

# ==============================================
# Script: auditd-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Configura auditd segun CIS Benchmark
#              CIS 4.1.1 - 4.1.18
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

AUDIT_RULES="/etc/audit/rules.d/99-hardening.rules"
AUDIT_CONF="/etc/audit/auditd.conf"
BACKUP_DIR="/root/audit-backup-$(date +%Y%m%d-%H%M%S)"

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
  echo "  ./auditd-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./auditd-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA OBTENER VERSION DEL SISTEMA
# ==============================================
get_os_version() {
  if [ -f /etc/redhat-release ]; then
    VERSION=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) 2>/dev/null | cut -d: -f1 | cut -d. -f1)
    echo "$VERSION"
  else
    echo ""
  fi
}

# ==============================================
# FUNCION PARA OBTENER RUTA DE AUDITCTL
# ==============================================
get_auditctl_path() {
  if command -v auditctl &>/dev/null; then
    echo "auditctl"
  elif [ -x /usr/sbin/auditctl ]; then
    echo "/usr/sbin/auditctl"
  else
    echo ""
  fi
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    [ -f "$AUDIT_CONF" ] && cp "$AUDIT_CONF" "$BACKUP_DIR/"
    if [ -d /etc/audit/rules.d ]; then
      cp -r /etc/audit/rules.d "$BACKUP_DIR/"
    else
      echo -e "${YELLOW}[!] Directorio /etc/audit/rules.d no existe, no se respalda${NC}"
    fi
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION GENERICA PARA CONFIGURAR PARAMETROS DE AUDITD.CONF
# ==============================================
configure_auditd_param() {
  local param="$1"
  local expected="$2"
  local description="$3"

  if grep -q "^[#]*\s*${param}\s*=\s*${expected}" "$AUDIT_CONF" 2>/dev/null; then
    if grep -q "^#\s*${param}\s*=\s*${expected}" "$AUDIT_CONF" 2>/dev/null; then
      echo -e "${YELLOW}[!] $description esta comentado${NC}"
      if [ "$AUTO_FIX" = true ]; then
        sed -i "s/^#\s*${param}\s*=\s*${expected}/${param} = ${expected}/" "$AUDIT_CONF"
        echo -e "${GREEN}[✓] $description descomentado${NC}"
        FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${GREEN}[✓] $description = ${expected}${NC}"
    fi
    return 0
  fi

  if grep -q "^[#]*\s*${param}\s*=" "$AUDIT_CONF" 2>/dev/null; then
    echo -e "${RED}[!] $description valor incorrecto${NC}"
    if [ "$AUTO_FIX" = true ]; then
      sed -i "s/^[#]*\s*${param}\s*=.*/${param} = ${expected}/" "$AUDIT_CONF"
      echo -e "${GREEN}[✓] $description corregido a ${expected}${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 0
  fi

  echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
  if [ "$AUTO_FIX" = true ]; then
    echo "${param} = ${expected}" >>"$AUDIT_CONF"
    echo -e "${GREEN}[✓] $description configurado como ${expected}${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 4.1.1.1 - ENSURE AUDITD IS INSTALLED
# ==============================================
check_auditd_installed() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.1 - Verificando auditd instalado...${NC}"

  # Instalar paquete principal audit
  if rpm -q audit &>/dev/null; then
    echo -e "${GREEN}[✓] audit instalado${NC}"
  else
    echo -e "${RED}[!] audit no instalado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if command -v dnf &>/dev/null; then
        dnf install audit -y 2>/dev/null
      else
        yum install audit -y 2>/dev/null
      fi
      echo -e "${GREEN}[✓] audit instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Instalar audit${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Instalar audit-libs (generalmente viene como dependencia, pero por las dudas)
  if rpm -q audit-libs &>/dev/null; then
    echo -e "${GREEN}[✓] audit-libs instalado${NC}"
  else
    echo -e "${RED}[!] audit-libs no instalado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if command -v dnf &>/dev/null; then
        dnf install audit-libs -y 2>/dev/null
      else
        yum install audit-libs -y 2>/dev/null
      fi
      echo -e "${GREEN}[✓] audit-libs instalado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Instalar audit-libs${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Verificar e instalar auditctl (nombre del paquete varia segun version)
  if command -v auditctl &>/dev/null || [ -x /usr/sbin/auditctl ]; then
    echo -e "${GREEN}[✓] auditctl disponible${NC}"
  else
    echo -e "${RED}[!] auditctl no disponible${NC}"

    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Instalando auditctl...${NC}"

      OS_VERSION=$(get_os_version)
      INSTALLED=false

      # Para RHEL 7, 8, 9 (audit-tools)
      if [ -n "$OS_VERSION" ] && [ "$OS_VERSION" -le 9 ] 2>/dev/null; then
        if command -v dnf &>/dev/null; then
          dnf install audit-tools -y 2>/dev/null && INSTALLED=true
        else
          yum install audit-tools -y 2>/dev/null && INSTALLED=true
        fi
      fi

      # Para RHEL 10 (audit-rules)
      if [ "$INSTALLED" = false ] && [ -n "$OS_VERSION" ] && [ "$OS_VERSION" -ge 10 ] 2>/dev/null; then
        if command -v dnf &>/dev/null; then
          dnf install audit-rules -y 2>/dev/null && INSTALLED=true
        else
          yum install audit-rules -y 2>/dev/null && INSTALLED=true
        fi
      fi

      # Fallback: intentar con audit-tools (para sistemas sin version detectada)
      if [ "$INSTALLED" = false ]; then
        if command -v dnf &>/dev/null; then
          dnf install audit-tools -y 2>/dev/null && INSTALLED=true
        else
          yum install audit-tools -y 2>/dev/null && INSTALLED=true
        fi
      fi

      # Segundo fallback: audit-rules
      if [ "$INSTALLED" = false ]; then
        if command -v dnf &>/dev/null; then
          dnf install audit-rules -y 2>/dev/null && INSTALLED=true
        else
          yum install audit-rules -y 2>/dev/null && INSTALLED=true
        fi
      fi

      if [ "$INSTALLED" = true ]; then
        echo -e "${GREEN}[✓] auditctl instalado correctamente${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo instalar auditctl automaticamente${NC}"
        echo -e "${YELLOW}    Instalacion manual: dnf install audit-tools o audit-rules${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: Instalar audit-tools (RHEL 7-9) o audit-rules (RHEL 10)${NC}"
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
      systemctl enable auditd 2>/dev/null
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
      systemctl start auditd 2>/dev/null
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
  configure_auditd_param "max_log_file" "50" "max_log_file"
}

# ==============================================
# 4.1.1.4 - ENSURE AUDIT LOGS NOT AUTOMATICALLY DELETED
# ==============================================
check_log_retention() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.4 - Verificando retencion de logs audit...${NC}"
  configure_auditd_param "max_log_file_action" "keep_logs" "max_log_file_action"
}

# ==============================================
# 4.1.1.5 - ENSURE SYSTEM DISABLED WHEN AUDIT LOGS ARE FULL
# ==============================================
check_full_action() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.5 - Verificando accion cuando logs estan llenos...${NC}"
  configure_auditd_param "space_left_action" "email" "space_left_action"
  configure_auditd_param "action_mail_acct" "root" "action_mail_acct"
  configure_auditd_param "admin_space_left_action" "halt" "admin_space_left_action"
}

# ==============================================
# AGREGAR TODAS LAS REGLAS DE AUDITORIA
# ==============================================
add_audit_rules() {
  echo -e "\n${BLUE}[*] Verificando reglas de auditoria...${NC}"

  # Crear directorio si no existe
  if [ ! -d /etc/audit/rules.d ]; then
    if [ "$AUTO_FIX" = true ]; then
      mkdir -p /etc/audit/rules.d
      echo -e "${GREEN}[✓] Directorio /etc/audit/rules.d creado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}[!] Directorio /etc/audit/rules.d no existe${NC}"
    fi
  fi

  # Crear archivo de reglas en modo fix
  if [ "$AUTO_FIX" = true ] && [ -d /etc/audit/rules.d ]; then
    if [ -f "$AUDIT_RULES" ] && [ -s "$AUDIT_RULES" ]; then
      echo -e "${GREEN}[✓] Archivo de reglas ya existe: $AUDIT_RULES${NC}"
    else
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
      FIXED=$((FIXED + 1))
    fi
  fi

  # Verificar reglas existentes
  echo -e "\n${BLUE}[*] Verificando reglas cargadas en memoria...${NC}"

  local rules_checks=(
    "time-change:Eventos de fecha/hora"
    "identity:Eventos de usuario/grupo"
    "system-locale:Eventos de red"
    "MAC-policy:Eventos de MAC/SELinux"
    "logins:Eventos de login/logout"
    "session:Eventos de sesion"
    "perm_mod:Eventos de cambios de permisos"
    "access:Eventos de acceso fallido"
    "mounts:Eventos de montaje"
    "delete:Eventos de eliminacion de archivos"
    "scope:Eventos de cambios en sudoers"
    "modules:Eventos de modulos del kernel"
  )

  AUDITCTL=$(get_auditctl_path)

  for check in "${rules_checks[@]}"; do
    key="${check%%:*}"
    desc="${check##*:}"
    if [ -n "$AUDITCTL" ] && $AUDITCTL -l 2>/dev/null | grep -q "$key"; then
      echo -e "${GREEN}[✓] $desc - OK${NC}"
    else
      echo -e "${RED}[!] $desc - NO CONFIGURADO${NC}"
      if [ "$AUTO_FIX" = false ]; then
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done

  # Verificar configuracion inmutable
  if [ -n "$AUDITCTL" ]; then
    if $AUDITCTL -s 2>/dev/null | grep -q "enabled 2"; then
      echo -e "${GREEN}[✓] Configuracion inmutable - OK${NC}"
    else
      echo -e "${RED}[!] Configuracion inmutable - NO CONFIGURADO${NC}"
      if [ "$AUTO_FIX" = false ]; then
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  fi
}

# ==============================================
# REINICIAR AUDITD Y CARGAR REGLAS
# ==============================================
restart_auditd() {
  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${BLUE}[*] Aplicando cambios...${NC}"

    if [ ! -d /etc/audit/rules.d ]; then
      mkdir -p /etc/audit/rules.d
      echo -e "${GREEN}[✓] Directorio /etc/audit/rules.d creado${NC}"
    fi

    AUDITCTL=$(get_auditctl_path)

    # Cargar reglas con auditctl -R
    if [ -n "$AUDITCTL" ] && [ -f "$AUDIT_RULES" ]; then
      $AUDITCTL -R "$AUDIT_RULES" 2>/dev/null
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] Reglas cargadas correctamente${NC}"
      else
        echo -e "${YELLOW}[!] Error al cargar reglas, se cargaran al reiniciar auditd${NC}"
      fi
    fi

    # Usar augenrules si existe
    if command -v augenrules &>/dev/null; then
      augenrules --load 2>/dev/null
      echo -e "${GREEN}[✓] Reglas cargadas con augenrules${NC}"
    elif [ -x /usr/sbin/augenrules ]; then
      /usr/sbin/augenrules --load 2>/dev/null
      echo -e "${GREEN}[✓] Reglas cargadas con augenrules${NC}"
    fi

    # Reiniciar auditd
    systemctl restart auditd 2>/dev/null
    echo -e "${GREEN}[✓] Auditd reiniciado${NC}"
    echo -e "${YELLOW}[!] NOTA: La configuracion inmutable (-e 2) requiere reinicio del sistema${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  AUDITD HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VER REGLAS DE AUDITORIA:${NC}"
  echo -e "  auditctl -l"
  echo -e "  /usr/sbin/auditctl -l"

  echo -e "\n${YELLOW}PARA VER LOGS DE AUDITORIA:${NC}"
  echo -e "  ausearch -ts recent"
  echo -e "  aureport -ts today"

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
  echo -e "${GREEN}  Auditd Hardening - CIS 4.1.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
    make_backup
  else
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"
    AUTO_FIX=false
  fi

  check_auditd_installed
  check_auditd_enabled
  check_log_storage
  check_log_retention
  check_full_action
  add_audit_rules
  restart_auditd
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
