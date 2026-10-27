#!/bin/bash

OB_COMPAT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$OB_COMPAT_DIR/lib/service-compat.sh" ]; then
  # shellcheck source=lib/service-compat.sh
  . "$OB_COMPAT_DIR/lib/service-compat.sh"
else
  echo "[ERROR] Falta lib/service-compat.sh; actualice el repositorio completo." >&2
  exit 1
fi
if [ -r "$OB_COMPAT_DIR/lib/hardening-confirm.sh" ]; then
  # shellcheck source=lib/hardening-confirm.sh
  . "$OB_COMPAT_DIR/lib/hardening-confirm.sh"
else
  echo "[ERROR] Falta lib/hardening-confirm.sh; actualice el repositorio completo." >&2
  exit 1
fi

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
  local version=""
  if [ -r /etc/redhat-release ]; then
    version="$(sed -nE 's/.*release[[:space:]]+([0-9]+).*/\1/p' /etc/redhat-release | head -1)"
  fi
  if [ -z "$version" ] && rpm -q --whatprovides redhat-release >/dev/null 2>&1; then
    version="$(rpm -q --qf '%{VERSION}\n' "$(rpm -q --whatprovides redhat-release)" 2>/dev/null | cut -d. -f1 | head -1)"
  fi
  printf '%s\n' "$version"
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

# Devuelve exactamente el valor de "enabled" expuesto por auditctl -s.
# Retorna error si auditctl no está disponible, falla o no incluye ese campo.
get_auditd_enabled_state() {
  local auditctl="${1:-}" status=""
  [ -n "$auditctl" ] || auditctl="$(get_auditctl_path)"
  [ -n "$auditctl" ] || return 1

  status="$("$auditctl" -s 2>/dev/null)" || return 1
  printf '%s\n' "$status" | awk '
    $1 == "enabled" { print $2; found = 1; exit }
    END { if (!found) exit 1 }
  '
}

# Presenta el estado real sin confundir auditoría habilitada con reglas inmutables.
report_auditd_immutable_status() {
  local auditctl="${1:-}" enabled_state=""
  enabled_state="$(get_auditd_enabled_state "$auditctl" 2>/dev/null)" || enabled_state=""

  case "$enabled_state" in
    2)
      echo -e "${GREEN}[✓] Configuración de auditd inmutable - OK (enabled 2)${NC}"
      return 0
      ;;
    1)
      echo -e "${YELLOW}[!] auditd está habilitado (enabled 1), pero las reglas siguen siendo modificables; no está en modo inmutable.${NC}"
      ;;
    0)
      echo -e "${YELLOW}[!] auditd está deshabilitado (enabled 0); no está activo ni en modo inmutable.${NC}"
      ;;
    "")
      echo -e "${YELLOW}[!] No se pudo determinar el estado de auditd mediante auditctl -s; revise la salida y el servicio.${NC}"
      ;;
    *)
      echo -e "${YELLOW}[!] auditd reporta enabled ${enabled_state}; no se confirma modo inmutable (solo enabled 2 lo demuestra).${NC}"
      ;;
  esac

  [ "$AUTO_FIX" = true ] || WARNINGS=$((WARNINGS + 1))
  return 0
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  [ "$AUTO_FIX" = true ] || return 0
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[ERROR] No se pudo preparar el backup $BACKUP_DIR; no se modificará auditd.${NC}" >&2
    return 1
  fi
  if [ -f "$AUDIT_CONF" ] && ! cp -p "$AUDIT_CONF" "$BACKUP_DIR/"; then
    echo -e "${RED}[ERROR] No se pudo respaldar $AUDIT_CONF; no se modificará auditd.${NC}" >&2
    return 1
  fi
  if [ -d /etc/audit/rules.d ] && ! cp -a /etc/audit/rules.d "$BACKUP_DIR/"; then
    echo -e "${RED}[ERROR] No se pudo respaldar /etc/audit/rules.d; no se modificarán las reglas.${NC}" >&2
    return 1
  fi
  if [ -f /etc/audit/audit.rules ] && ! cp -p /etc/audit/audit.rules "$BACKUP_DIR/"; then
    echo -e "${RED}[ERROR] No se pudo respaldar /etc/audit/audit.rules; no se modificará auditd.${NC}" >&2
    return 1
  fi
  echo -e "${GREEN}[✓] Backup de auditd verificado en: $BACKUP_DIR${NC}"
}

# ==============================================
# FUNCION GENERICA PARA CONFIGURAR PARAMETROS DE AUDITD.CONF
# ==============================================
configure_auditd_param() {
  local param="$1" expected="$2" description="$3" current="" effect="" tmp="" mode="640"
  [ -f "$AUDIT_CONF" ] || {
    echo -e "${RED}[!] $AUDIT_CONF no existe; no se puede auditar ni editar parámetros.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  current="$(awk -F= -v wanted="$param" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
    {
      key=$1; gsub(/[[:space:]]/, "", key)
      if (key==wanted) {
        value=$2
        sub(/[[:space:]]*#.*/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        current=value
      }
    }
    END {print current}
  ' "$AUDIT_CONF")"

  if [ "$current" = "$expected" ]; then
    echo -e "${GREEN}[✓] $description = $expected (directiva activa)${NC}"
    return 0
  fi

  case "$param" in
    max_log_file)
      effect="Define el tamaño máximo de cada archivo de log de auditd en MB. Un valor bajo genera rotación frecuente; uno alto consume más espacio por archivo. No cambia por sí solo la retención total." ;;
    max_log_file_action)
      effect="Define qué hacer al llegar al tamaño máximo del log. keep_logs evita eliminar automáticamente logs antiguos y puede llenar /var/log/audit o el filesystem, lo que puede afectar servicios y el propio sistema." ;;
    space_left_action)
      effect="Define la acción de aviso cuando queda poco espacio. email intenta notificar; depende de la configuración de correo y no garantiza por sí sola que llegue una alerta." ;;
    action_mail_acct)
      effect="Define el destinatario de avisos de auditd. Si root no recibe correo local o no hay MTA/forwarding, el aviso puede no llegar." ;;
    admin_space_left_action)
      effect="Se ejecutaría al alcanzar el umbral crítico de espacio para auditd. halt detiene el host y puede dejar inaccesible un servidor remoto; hay que validar monitorización de disco, alertas y vía de consola/recuperación antes de habilitarlo." ;;
    *)
      effect="Cambia una directiva del servicio de auditoría y debe validarse contra la configuración operativa del servidor." ;;
  esac

  echo -e "${YELLOW}[!] $description: actual=${current:-no definido}, recomendado=$expected${NC}"
  if [ "$AUTO_FIX" != true ]; then
    echo "Qué hace/riesgo: $effect"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if ! ob_confirm_hardening_change "auditd.conf: $param" "${current:-no definido}" "$expected" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  tmp="$(mktemp "$(dirname "$AUDIT_CONF")/.auditd.conf.orangebox.XXXXXX")" || {
    echo -e "${RED}[!] No se pudo crear archivo temporal; no se cambia $param.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  awk -v wanted="$param" -v value="$expected" '
    function trim(s){sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s}
    /^[ \t]*#/ || /^[ \t]*$/ {print; next}
    {
      line=$0
      sub(/[ \t]+#.*/, "", line)
      equal=index(line, "=")
      key=equal ? trim(substr(line,1,equal-1)) : ""
      if (key==wanted) {
        if (!written) print wanted " = " value
        written=1
        next
      }
      print
    }
    END {if (!written) print wanted " = " value}
  ' "$AUDIT_CONF" > "$tmp" || {
    rm -f "$tmp"
    echo -e "${RED}[!] No se pudo preparar $AUDIT_CONF; no se cambia $param.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  mode="$(stat -c %a "$AUDIT_CONF" 2>/dev/null || echo 640)"
  chmod "$mode" "$tmp" && chown root:root "$tmp" || {
    rm -f "$tmp"
    echo -e "${RED}[!] No se pudieron preservar permisos de $AUDIT_CONF.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  if ! mv "$tmp" "$AUDIT_CONF"; then
    rm -f "$tmp"
    echo -e "${RED}[!] No se pudo instalar la configuración actualizada.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  echo -e "${GREEN}[✓] $param actualizado a $expected${NC}"
  FIXED=$((FIXED + 1))
}

# ==============================================
# 4.1.1.1 - ENSURE AUDITD IS INSTALLED
# ==============================================
check_auditd_installed() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.1 - Verificando auditd y las herramientas de reglas... ${NC}"
  local package="" reason="" os_version="" package_installed=false tool_installed=false install_cmd=""

  # audit-rules es un paquete requerido en EL10. No basta con que auditd
  # esté activo: el administrador necesita auditctl/augenrules para validar
  # y cargar reglas. En EL7-9 se conserva el paquete histórico audit-tools.
  os_version="$(get_os_version)"
  if [[ "$os_version" =~ ^[0-9]+$ ]] && [ "$os_version" -ge 10 ]; then
    package="audit-rules"
  else
    package="audit-tools"
  fi

  if rpm -q audit >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] audit instalado${NC}"
  else
    reason="Instala el demonio de auditoría; puede aumentar eventos registrados y consumo de disco/CPU. Se instalará desde los repositorios configurados."
    if [ "$AUTO_FIX" != true ] || ! ob_confirm_hardening_change "instalar audit" "no instalado" "dnf/yum install audit" "$reason"; then
      WARNINGS=$((WARNINGS + 1))
    else
      if command -v dnf >/dev/null 2>&1; then dnf install audit -y
      else yum install audit -y; fi
      if rpm -q audit >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] audit instalado${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se confirmó la instalación de audit${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  fi

  if rpm -q audit-libs >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] audit-libs instalado${NC}"
  else
    reason="Instala bibliotecas usadas por herramientas de auditoría. Puede incorporar dependencias; no habilita auditd por sí solo."
    if [ "$AUTO_FIX" = true ] && ob_confirm_hardening_change "instalar audit-libs" "no instalado" "dnf/yum install audit-libs" "$reason"; then
      if command -v dnf >/dev/null 2>&1; then dnf install audit-libs -y
      else yum install audit-libs -y; fi
      if rpm -q audit-libs >/dev/null 2>&1; then FIXED=$((FIXED + 1)); else WARNINGS=$((WARNINGS + 1)); fi
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if command -v auditctl >/dev/null 2>&1 || [ -x /usr/sbin/auditctl ]; then tool_installed=true; fi
  if [ "$package" = "audit-rules" ]; then
    rpm -q audit-rules >/dev/null 2>&1 && package_installed=true
    if [ "$package_installed" = true ] && [ "$tool_installed" = true ] &&
       { command -v augenrules >/dev/null 2>&1 || [ -x /usr/sbin/augenrules ]; }; then
      echo -e "${GREEN}[✓] audit-rules instalado; auditctl y augenrules disponibles${NC}"
      return 0
    fi
  else
    # Preserve EL7-9 behavior: use audit-tools only when auditctl is absent.
    if [ "$tool_installed" = true ]; then
      echo -e "${GREEN}[✓] auditctl disponible${NC}"
      return 0
    fi
    rpm -q "$package" >/dev/null 2>&1 && package_installed=true
  fi

  if [ "$package" = "audit-rules" ]; then
    reason="Instala audit-rules, el paquete de AlmaLinux/RHEL 10 que proporciona auditctl y augenrules. Sin estas herramientas, el hardening no puede comprobar ni cargar las reglas persistentes de auditd."
  else
    reason="Instala audit-tools para administrar las reglas de auditd; sin auditctl no se pueden comprobar ni cargar las reglas persistentes."
  fi
  echo -e "${YELLOW}[WARN] Falta el paquete requerido '$package' o auditctl no está disponible.${NC}"
  echo "Qué hace/riesgo: $reason"
  if [ "$AUTO_FIX" != true ]; then
    echo "[INFO] En modo --fix se solicitará confirmación individual para instalar $package."
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if ! ob_confirm_hardening_change "instalar $package" "paquete ausente o herramientas no disponibles" "dnf/yum install $package" "$reason"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    if [ "$package_installed" = true ]; then
      dnf reinstall "$package" -y
    else
      dnf install "$package" -y
    fi
  else
    if [ "$package_installed" = true ]; then
      yum reinstall "$package" -y
    else
      yum install "$package" -y
    fi
  fi

  package_installed=false
  tool_installed=false
  if rpm -q "$package" >/dev/null 2>&1; then package_installed=true; fi
  if command -v auditctl >/dev/null 2>&1 || [ -x /usr/sbin/auditctl ]; then tool_installed=true; fi
  if [ "$package_installed" = true ] && [ "$tool_installed" = true ]; then
    if [ "$package" = "audit-rules" ] &&
       ! { command -v augenrules >/dev/null 2>&1 || [ -x /usr/sbin/augenrules ]; }; then
      echo -e "${RED}[!] audit-rules figura instalado, pero augenrules sigue ausente; revisar el paquete antes de cargar reglas.${NC}"
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "${GREEN}[✓] $package instalado y las herramientas de reglas están disponibles${NC}"
      FIXED=$((FIXED + 1))
    fi
  else
    echo -e "${RED}[!] No se pudo verificar la instalación de $package y auditctl; no se cargarán reglas a ciegas.${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 4.1.1.2 - ENSURE AUDITD IS ENABLED AND RUNNING
# ==============================================
check_auditd_enabled() {
  echo -e "\n${BLUE}[*] CIS 4.1.1.2 - Verificando auditd habilitado y activo... ${NC}"
  local effect="" state=""

  if ob_service_is_enabled auditd; then
    echo -e "${GREEN}[✓] auditd habilitado al arranque${NC}"
  else
    effect="Configura auditd para iniciar en cada arranque. Aumenta la cobertura de auditoría, pero cambia el comportamiento de inicio y debe validarse con la política local."
    if [ "$AUTO_FIX" = true ] && ob_confirm_hardening_change "habilitar auditd al arranque" "deshabilitado/no confirmado" "habilitar auditd" "$effect"; then
      if ob_service_enable auditd; then FIXED=$((FIXED + 1)); else WARNINGS=$((WARNINGS + 1)); fi
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  if ob_service_is_active auditd; then
    echo -e "${GREEN}[✓] auditd activo${NC}"
  else
    effect="Inicia el demonio de auditoría ahora; aumentará los eventos registrados, el uso de CPU/disco y puede cambiar los registros disponibles para soporte/seguridad."
    if [ "$AUTO_FIX" = true ] && ob_confirm_hardening_change "iniciar auditd ahora" "inactivo/no confirmado" "iniciar auditd" "$effect"; then
      if ob_service_start auditd; then FIXED=$((FIXED + 1)); else WARNINGS=$((WARNINGS + 1)); fi
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
  echo -e "\n${BLUE}[*] Verificando reglas persistentes de auditoría... ${NC}"
  local effect="" auditctl="" check key desc
  local rules_checks=(
    "time-change:Eventos de fecha/hora"
    "identity:Eventos de usuario/grupo"
    "system-locale:Eventos de red"
    "MAC-policy:Eventos de MAC/SELinux"
    "logins:Eventos de login/logout"
    "session:Eventos de sesión"
    "perm_mod:Eventos de cambios de permisos"
    "access:Eventos de acceso fallido"
    "mounts:Eventos de montaje"
    "delete:Eventos de eliminación de archivos"
    "scope:Eventos de cambios en sudoers"
    "modules:Eventos de módulos del kernel"
  )

  if [ ! -d /etc/audit/rules.d ] || [ ! -s "$AUDIT_RULES" ]; then
    effect="Crea un conjunto de reglas persistentes para registrar cambios de identidad, tiempo, red, permisos, accesos fallidos, montajes, borrado de archivos, sudo y módulos del kernel. Puede aumentar el volumen de /var/log/audit y la carga de I/O; no se sobrescribirá un archivo de reglas existente que tenga contenido."
    if [ "$AUTO_FIX" = true ] && ob_confirm_hardening_change "crear conjunto de reglas auditd" "directorio/archivo ausente o vacío" "$AUDIT_RULES" "$effect"; then
      mkdir -p /etc/audit/rules.d || { WARNINGS=$((WARNINGS + 1)); return 1; }
      [ ! -L "$AUDIT_RULES" ] || { echo "[ERROR] $AUDIT_RULES es un enlace simbólico; no se modifica."; WARNINGS=$((WARNINGS+1)); return 1; }
      cat > "$AUDIT_RULES" <<'EOF'
# OrangeBox hardening audit rules (review volume and workload before deployment)
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-w /etc/localtime -p wa -k time-change
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/sysctl.conf -p wa -k system-locale
-w /etc/sysctl.d -p wa -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/networks -p wa -k system-locale
-w /etc/network -p wa -k system-locale
-w /etc/selinux -p wa -k MAC-policy
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope
-w /var/log/sudo.log -p wa -k actions
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules
EOF
      chmod 640 "$AUDIT_RULES" && chown root:root "$AUDIT_RULES" || { WARNINGS=$((WARNINGS+1)); return 1; }
      FIXED=$((FIXED + 1))
      echo -e "${GREEN}[✓] Reglas persistentes escritas (sin activar inmutabilidad automáticamente)${NC}"
    else
      WARNINGS=$((WARNINGS+1))
    fi
  elif [ -s "$AUDIT_RULES" ]; then
    echo -e "${GREEN}[✓] Archivo de reglas existente conservado: $AUDIT_RULES${NC}"
  fi

  echo -e "\n${BLUE}[*] Verificando reglas cargadas en memoria... ${NC}"
  auditctl="$(get_auditctl_path)"
  for check in "${rules_checks[@]}"; do
    key="${check%%:*}"
    desc="${check#*:}"
    if [ -n "$auditctl" ] && "$auditctl" -l 2>/dev/null | grep -q -- "$key"; then
      echo -e "${GREEN}[✓] $desc - OK${NC}"
    else
      echo -e "${RED}[!] $desc - NO CONFIGURADO EN MEMORIA${NC}"
      [ "$AUTO_FIX" = true ] || WARNINGS=$((WARNINGS + 1))
    fi
  done

  # En modo auditoría este es el reporte autoritativo. En --fix,
  # configure_audit_immutable() informa el estado antes del consentimiento.
  if [ "$AUTO_FIX" != true ]; then
    report_auditd_immutable_status "$auditctl"
  fi
}

# ==============================================
# REINICIAR AUDITD Y CARGAR REGLAS
# ==============================================
restart_auditd() {
  [ "$AUTO_FIX" = true ] || return 0
  if [ "$FIXED" -eq 0 ]; then
    echo -e "${GREEN}[✓] No hay cambios aceptados; no se recarga ni reinicia auditd.${NC}"
    return 0
  fi

  local effect auditctl=""
  effect="Carga las reglas persistentes y reinicia auditd para aplicar parámetros. Puede cambiar el volumen de eventos, y si las reglas existentes son inmutables (-e 2) algunas operaciones de carga pueden ser rechazadas. La configuración se respalda en $BACKUP_DIR."
  if ! ob_confirm_hardening_change "recargar reglas/reiniciar auditd" "servicio/configuración actual" "augenrules --load y reinicio de auditd" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  AUDITCTL="$(get_auditctl_path)"
  if [ -n "$AUDITCTL" ] && [ -f "$AUDIT_RULES" ]; then
    if "$AUDITCTL" -R "$AUDIT_RULES" 2>/dev/null; then
      echo -e "${GREEN}[✓] Reglas cargadas con auditctl -R${NC}"
    else
      echo -e "${YELLOW}[WARN] auditctl -R rechazó reglas; revisar sintaxis/compatibilidad antes de continuar.${NC}"
      WARNINGS=$((WARNINGS+1))
    fi
  fi

  if command -v augenrules >/dev/null 2>&1; then
    if ! augenrules --load; then
      echo -e "${YELLOW}[WARN] augenrules --load no pudo cargar reglas; no se fuerza un reinicio.${NC}"
      WARNINGS=$((WARNINGS+1))
      return 1
    fi
  elif [ -x /usr/sbin/augenrules ]; then
    if ! /usr/sbin/augenrules --load; then
      echo -e "${YELLOW}[WARN] augenrules --load no pudo cargar reglas; no se fuerza un reinicio.${NC}"
      WARNINGS=$((WARNINGS+1))
      return 1
    fi
  fi

  if ob_service_is_active auditd; then
    echo -e "${BLUE}[INFO] auditd está activo; la recarga de reglas ya se intentó. No se reinicia el demonio a la fuerza para evitar interrumpir la auditoría.${NC}"
  elif ob_service_start auditd; then
    echo -e "${GREEN}[✓] auditd iniciado${NC}"
  else
    echo -e "${YELLOW}[WARN] No se pudo iniciar auditd; revisar el servicio antes de continuar.${NC}"
    WARNINGS=$((WARNINGS+1))
  fi
}

configure_audit_immutable() {
  local auditctl="" rule_file="/etc/audit/rules.d/zzzzzzzz-orangebox-immutable.rules"
  local effect="" state="" enabled_state=""
  auditctl="$(get_auditctl_path)"
  enabled_state="$(get_auditd_enabled_state "$auditctl" 2>/dev/null)" || enabled_state=""

  # add_audit_rules() ya reportó el estado completo en modo auditoría.
  # No volver a imprimir ni contabilizar la misma condición.
  if [ "$AUTO_FIX" != true ]; then
    return 0
  fi

  if [ "$enabled_state" = "2" ]; then
    echo -e "${GREEN}[✓] auditd ya está en modo inmutable (enabled 2)${NC}"
    return 0
  fi
  echo -e "${YELLOW}[!] auditd no está en modo inmutable (enabled ${enabled_state:-desconocido})${NC}"

  effect="La opción -e 2 bloquea cambios posteriores a las reglas de auditd hasta reiniciar el sistema. Refuerza la integridad, pero puede impedir corregir errores de reglas sin reinicio y complicar la recuperación remota. Solo se aplica después de las demás modificaciones y con una vía de consola/recuperación probada."
  if ! ob_confirm_hardening_change "activar inmutabilidad de reglas auditd (-e 2)" "auditctl enabled distinto de 2" "persistir -e 2 y cargar reglas" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  [ ! -L "$rule_file" ] || { echo "[ERROR] $rule_file es enlace simbólico; no se modifica."; WARNINGS=$((WARNINGS+1)); return 1; }
  if [ -e "$rule_file" ]; then
    echo -e "${YELLOW}[WARN] $rule_file ya existe; no se sobrescribe. Revise su contenido manualmente.${NC}"
    WARNINGS=$((WARNINGS+1))
    return 0
  fi
  printf '%s\n' '-e 2' > "$rule_file" || { WARNINGS=$((WARNINGS+1)); return 1; }
  chmod 640 "$rule_file" && chown root:root "$rule_file" || { rm -f "$rule_file"; WARNINGS=$((WARNINGS+1)); return 1; }
  FIXED=$((FIXED+1))

  if command -v augenrules >/dev/null 2>&1; then
    if augenrules --load; then
      echo -e "${GREEN}[✓] Reglas cargadas; auditd queda inmutable hasta reinicio${NC}"
    else
      echo -e "${YELLOW}[WARN] La regla -e 2 quedó persistente, pero no se pudo cargar ahora. Se aplicará al próximo boot si las reglas son válidas.${NC}"
      WARNINGS=$((WARNINGS+1))
    fi
  else
    echo -e "${YELLOW}[WARN] La regla -e 2 quedó persistente para el próximo boot; augenrules no está disponible.${NC}"
    WARNINGS=$((WARNINGS+1))
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
# AUDITORÍA LEGACY CENTOS/RHEL 6 (SOLO LECTURA)
# ==============================================
legacy_audit_rules_check() {
  echo -e "\n${BLUE}[*] Reglas persistentes legacy de auditd (/etc/audit/audit.rules)...${NC}"
  if [ -s /etc/audit/audit.rules ]; then
    echo -e "${GREEN}[✓] /etc/audit/audit.rules existe y no está vacío${NC}"
  else
    echo -e "${RED}[!] /etc/audit/audit.rules no existe o está vacío${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  local AUDITCTL check key desc
  AUDITCTL="$(get_auditctl_path)"
  if [ -z "$AUDITCTL" ]; then
    echo -e "${RED}[!] auditctl no está disponible; no se pueden verificar las reglas cargadas${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  echo -e "\n${BLUE}[*] Reglas legacy cargadas en memoria...${NC}"
  local rules_checks=(
    "time-change:Eventos de fecha/hora"
    "identity:Eventos de usuario/grupo"
    "system-locale:Eventos de red"
    "MAC-policy:Eventos de MAC/SELinux"
    "logins:Eventos de login/logout"
    "session:Eventos de sesión"
    "perm_mod:Eventos de cambios de permisos"
    "access:Eventos de acceso fallido"
    "mounts:Eventos de montaje"
    "delete:Eventos de eliminación de archivos"
    "scope:Eventos de cambios en sudoers"
    "modules:Eventos de módulos del kernel"
  )
  for check in "${rules_checks[@]}"; do
    key="${check%%:*}"
    desc="${check#*:}"
    if "$AUDITCTL" -l 2>/dev/null | grep -q -- "$key"; then
      echo -e "${GREEN}[✓] $desc - OK${NC}"
    else
      echo -e "${RED}[!] $desc - NO CONFIGURADO${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  done

  report_auditd_immutable_status "$AUDITCTL"
}

legacy_auditd_readonly() {
  echo -e "${BLUE}[INFO] CentOS/RHEL 6 usa SysV init y /etc/audit/audit.rules; se ejecutan comprobaciones legacy de solo lectura.${NC}"
  check_auditd_installed
  check_auditd_enabled
  check_log_storage
  check_log_retention
  check_full_action
  legacy_audit_rules_check
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

  local os_major
  os_major="$(get_os_version)"
  if [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -lt 7 ]; then
    if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
      echo -e "${RED}[ERROR] --fix no está soportado en EL6 por este módulo; no se aplicaron cambios. Use la auditoría de solo lectura y planifique una migración.${NC}" >&2
      exit 2
    fi
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN LEGACY - no se aplicarán cambios${NC}"
    legacy_auditd_readonly
    show_summary
    return 0
  fi

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
    if ! make_backup; then
      echo -e "${RED}[ERROR] Backup fallido; se aborta antes de modificar auditd.${NC}" >&2
      exit 1
    fi
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
  configure_audit_immutable
  show_summary

  if [ "$AUTO_FIX" = false ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
  fi
}

# Permite cargar funciones desde pruebas unitarias sin ejecutar el flujo principal.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
    exit 1
  fi
  main "$@"
fi
