#!/bin/bash

# ==============================================
# Script: ssh-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de SSH segun CIS Benchmark y mejores practicas
#              Compatible con OpenSSH 7.4+ (RHEL 7,8,9,10)
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
BACKUP_DIR="/root/ssh-backup-$(date +%Y%m%d-%H%M%S)"
SSH_MANAGED_BEGIN="# ORANGEBOX SSH HARDENING BEGIN"
SSH_MANAGED_END="# ORANGEBOX SSH HARDENING END"
SSH_BACKUP_READY=false
SSH_CONFIG_CHANGED=false

# ==============================================
# FUNCION PARA OBTENER VERSION DE OPENSSH
# ==============================================
get_ssh_version() {
  ssh -V 2>&1 | grep -oE 'OpenSSH_[0-9]+\.[0-9]+' | cut -d'_' -f2 | cut -d'.' -f1
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  [ "$AUTO_FIX" = true ] || return 0
  [ -f "$SSHD_CONFIG" ] && [ ! -L "$SSHD_CONFIG" ] || {
    echo -e "${RED}[ERROR] $SSHD_CONFIG no es un archivo regular seguro; no se modifica SSH.${NC}" >&2
    return 1
  }
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[ERROR] No se pudo preparar el backup $BACKUP_DIR; no se modifica SSH.${NC}" >&2
    return 1
  fi
  if ! cp -p "$SSHD_CONFIG" "$BACKUP_DIR/sshd_config"; then
    echo -e "${RED}[ERROR] No se pudo respaldar $SSHD_CONFIG; no se modifica SSH.${NC}" >&2
    return 1
  fi
  if [ -d "$SSHD_CONFIG_DIR" ] && ! cp -a "$SSHD_CONFIG_DIR" "$BACKUP_DIR/"; then
    echo -e "${RED}[ERROR] No se pudo respaldar $SSHD_CONFIG_DIR; no se modifica SSH.${NC}" >&2
    return 1
  fi
  SSH_BACKUP_READY=true
  echo -e "${GREEN}[✓] Backup de SSH verificado en: $BACKUP_DIR${NC}"
}

confirm_ssh_change() {
  local title="$1" current="$2" proposed="$3" effect="$4" answer=""
  echo -e "\n${YELLOW}[WARN] Cambio de SSH pendiente: $title${NC}"
  echo "Estado efectivo actual: ${current:-no verificable}"
  echo "Propuesta: $proposed"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 1; fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "${YELLOW}[WARN] No hay terminal interactiva; no se modifica SSH.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  printf '¿Aplicar este cambio? [s/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) echo -e "${YELLOW}[INFO] Cambio rechazado; se conserva la configuración actual.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1 ;;
  esac
}

ssh_parameter_impact() {
  case "$1" in
    permitrootlogin) echo "Deshabilita el login SSH directo de root; puede dejar fuera a administradores que solo acceden como root. Confirma antes que existe un usuario alternativo probado." ;;
    allowtcpforwarding) echo "Bloquea túneles SSH usados por port-forwarding, VPNs y herramientas de administración; puede romper flujos que dependan de ellos." ;;
    clientaliveinterval|clientalivecountmax) echo "Cierra conexiones que no responden al keepalive según los límites configurados; puede desconectar sesiones inactivas y tareas interactivas largas." ;;
    ciphers|macs|kexalgorithms|pubkeyacceptedalgorithms|pubkeyacceptedkeytypes) echo "Restringe algoritmos de negociación SSH; clientes antiguos, dispositivos integrados o herramientas heredadas podrían dejar de conectar." ;;
    x11forwarding) echo "Deshabilita forwarding de X11; las aplicaciones gráficas remotas que dependan de él dejarán de funcionar." ;;
    usepam) echo "Cambia el uso de PAM para SSH; puede afectar autenticación, MFA, límites de sesión y políticas de acceso." ;;
    banner) echo "Muestra un aviso antes de autenticar. No cambia credenciales, pero requiere archivo legible y configuración SSH válida." ;;
    maxauthtries) echo "Limita intentos de autenticación por conexión; usuarios legítimos con varias llaves o métodos pueden necesitar ajustar el proceso de login." ;;
    logingracetime) echo "Reduce el tiempo permitido para autenticarse; clientes con autenticación lenta pueden fallar." ;;
    maxstartups) echo "Controla conexiones sin autenticar concurrentes; límites muy bajos pueden rechazar conexiones legítimas durante picos." ;;
    maxsessions) echo "Limita sesiones multiplexadas por conexión; puede afectar usos de ControlMaster o automatización SSH." ;;
    *) echo "Cambia la política de SSH; puede afectar compatibilidad de clientes y acceso remoto. Valida desde una segunda sesión antes de cerrar la actual." ;;
  esac
}

ssh_effective_value() {
  local key="$1" config="${2:-$SSHD_CONFIG}"
  sshd -T -f "$config" 2>/dev/null |
    awk -v wanted="$key" 'tolower($1)==tolower(wanted) {$1=""; sub(/^[[:space:]]+/, ""); print; found=1; exit} END{if(!found) exit 1}'
}

ssh_install_parameter() {
  local param="$1" expected="$2" fix_line="$3"
  local tmp="" base="" previous_block="" current_copy="" candidate=""
  local actual="" impact="" mode="600"
  [ "$SSH_BACKUP_READY" = true ] || { echo -e "${RED}[ERROR] No hay backup verificado; no se modifica SSH.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1; }
  [ ! -L "$SSHD_CONFIG" ] && [ -f "$SSHD_CONFIG" ] || { echo -e "${RED}[ERROR] $SSHD_CONFIG no es un archivo regular seguro.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1; }

  base="$(mktemp /etc/ssh/.sshd_config.orangebox.base.XXXXXX)" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  previous_block="$(mktemp /etc/ssh/.sshd_config.orangebox.block.XXXXXX)" || { rm -f "$base"; WARNINGS=$((WARNINGS + 1)); return 1; }
  tmp="$(mktemp /etc/ssh/.sshd_config.orangebox.candidate.XXXXXX)" || { rm -f "$base" "$previous_block"; WARNINGS=$((WARNINGS + 1)); return 1; }
  current_copy="$(mktemp /etc/ssh/.sshd_config.orangebox.current.XXXXXX)" || { rm -f "$base" "$previous_block" "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }

  if ! cp -p "$SSHD_CONFIG" "$current_copy"; then
    rm -f "$base" "$previous_block" "$tmp" "$current_copy"
    echo -e "${RED}[WARN] No se pudo conservar el sshd_config actual para rollback.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  awk -v begin="$SSH_MANAGED_BEGIN" -v end="$SSH_MANAGED_END" '
    $0==begin {inside=1; next}
    $0==end {inside=0; next}
    !inside {print}
  ' "$SSHD_CONFIG" > "$base" || { rm -f "$base" "$previous_block" "$tmp" "$current_copy"; WARNINGS=$((WARNINGS + 1)); return 1; }

  awk -v begin="$SSH_MANAGED_BEGIN" -v end="$SSH_MANAGED_END" -v wanted="$param" '
    $0==begin {inside=1; next}
    $0==end {inside=0; next}
    inside && tolower($1)!=tolower(wanted) {print}
  ' "$SSHD_CONFIG" > "$previous_block" || { rm -f "$base" "$previous_block" "$tmp" "$current_copy"; WARNINGS=$((WARNINGS + 1)); return 1; }

  {
    printf '%s\n' "$SSH_MANAGED_BEGIN"
    printf '%s\n' "$fix_line"
    cat "$previous_block"
    printf '%s\n' "$SSH_MANAGED_END"
    cat "$base"
  } > "$tmp" || { rm -f "$base" "$previous_block" "$tmp" "$current_copy"; WARNINGS=$((WARNINGS + 1)); return 1; }

  mode="$(stat -c '%a' "$SSHD_CONFIG" 2>/dev/null || echo 600)"
  chmod "$mode" "$tmp" && chown root:root "$tmp" || { rm -f "$base" "$previous_block" "$tmp" "$current_copy"; WARNINGS=$((WARNINGS + 1)); return 1; }

  if ! sshd -t -f "$tmp" >/dev/null 2>&1; then
    echo -e "${RED}[WARN] El candidato con '$fix_line' no pasó sshd -t; no se instala.${NC}"
    sshd -t -f "$tmp" 2>&1
    rm -f "$base" "$previous_block" "$tmp" "$current_copy"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  candidate="$(ssh_effective_value "$param" "$tmp" || true)"
  if [ "$candidate" != "$expected" ]; then
    echo -e "${YELLOW}[WARN] El candidato no produce el valor efectivo esperado para $param. Efectivo candidato='${candidate:-no verificable}', esperado='$expected'; no se instala.${NC}"
    rm -f "$base" "$previous_block" "$tmp" "$current_copy"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if ! mv "$tmp" "$SSHD_CONFIG"; then
    rm -f "$base" "$previous_block" "$tmp" "$current_copy"
    echo -e "${RED}[WARN] No se pudo instalar el candidato de SSH.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  command -v restorecon >/dev/null 2>&1 && restorecon "$SSHD_CONFIG" >/dev/null 2>&1 || true

  actual="$(ssh_effective_value "$param" "$SSHD_CONFIG" || true)"
  if sshd -t >/dev/null 2>&1 && [ "$actual" = "$expected" ]; then
    echo -e "${GREEN}[✓] $param aplicado y verificado: $actual${NC}"
    SSH_CONFIG_CHANGED=true
    FIXED=$((FIXED + 1))
    rm -f "$base" "$previous_block" "$current_copy"
    return 0
  fi

  echo -e "${RED}[WARN] La configuración instalada no cumplió la validación posterior; restaurando el archivo previo a este cambio.${NC}"
  if cp -p "$current_copy" "$SSHD_CONFIG"; then
    command -v restorecon >/dev/null 2>&1 && restorecon "$SSHD_CONFIG" >/dev/null 2>&1 || true
    if sshd -t >/dev/null 2>&1; then
      echo -e "${YELLOW}[INFO] Rollback de sshd_config verificado.${NC}"
    else
      echo -e "${RED}[ERROR] El rollback no valida; mantenga abierta la sesión y recupere desde $BACKUP_DIR/sshd_config.${NC}"
    fi
  else
    echo -e "${RED}[ERROR] No se pudo restaurar sshd_config; recupere desde $BACKUP_DIR/sshd_config.${NC}"
  fi
  rm -f "$base" "$previous_block" "$tmp" "$current_copy"
  WARNINGS=$((WARNINGS + 1))
  return 1
}

# ==============================================
# FUNCION PARA VERIFICAR Y CONFIGURAR PARAMETRO
# ==============================================
check_sshd_param() {
  local param="$1" expected="$2" description="$3" fix_line="$4"
  local current="" effect=""
  current="$(ssh_effective_value "$param" "$SSHD_CONFIG" || true)"
  if [ -z "$current" ]; then
    echo -e "${YELLOW}[WARN] $description: sshd -T no devuelve un valor verificable para $param; no se cambia.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ "$current" = "$expected" ]; then
    echo -e "${GREEN}[✓] $description=$current (valor efectivo)${NC}"
    return 0
  fi
  effect="$(ssh_parameter_impact "$param")"
  echo -e "${YELLOW}[WARN] $description: valor actual='$current'; recomendado='$expected'.${NC}"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 1; fi
  if ! confirm_ssh_change "$description" "$current" "$fix_line" "$effect"; then return 1; fi
  ssh_install_parameter "$param" "$expected" "$fix_line"
}

# ==============================================
# FUNCION PARA VERIFICAR PERMISOS
# ==============================================
check_permissions() {
  local file="$1" perms="$2" owner="$3" group="$4" description="$5"
  local current_perms="" current_owner="" current_group="" effect="" answer=""
  if [ ! -f "$file" ] || [ -L "$file" ]; then
    echo -e "${YELLOW}[WARN] $file no existe o no es un archivo regular seguro.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  current_perms="$(stat -c '%a' "$file" 2>/dev/null || true)"
  current_owner="$(stat -c '%U' "$file" 2>/dev/null || true)"
  current_group="$(stat -c '%G' "$file" 2>/dev/null || true)"
  if [ "$current_perms" = "$perms" ] && [ "$current_owner" = "$owner" ] && [ "$current_group" = "$group" ]; then
    echo -e "${GREEN}[✓] $description: $current_perms $current_owner:$current_group${NC}"
    return 0
  fi
  effect="Restringe la escritura del archivo de configuración SSH a root. Si la propiedad o permisos se fijan de forma incorrecta, sshd puede rechazar la configuración; se requiere backup y validación antes de la recarga."
  echo -e "${YELLOW}[WARN] $description: actual=$current_perms $current_owner:$current_group; recomendado=$perms $owner:$group${NC}"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ] || ! confirm_ssh_change "$description" "$current_perms $current_owner:$current_group" "chmod $perms; chown $owner:$group $file" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ "$SSH_BACKUP_READY" != true ]; then
    echo -e "${RED}[WARN] No hay backup SSH verificado; no se cambian permisos.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if chmod "$perms" "$file" && chown "$owner:$group" "$file" &&
     [ "$(stat -c '%a' "$file" 2>/dev/null)" = "$perms" ] &&
     [ "$(stat -c '%U:%G' "$file" 2>/dev/null)" = "$owner:$group" ] &&
     sshd -t >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] $description ajustado y validado${NC}"
    FIXED=$((FIXED + 1))
    SSH_CONFIG_CHANGED=true
  else
    echo -e "${RED}[WARN] No se pudo validar la corrección de permisos de $file. Restaure manualmente desde $BACKUP_DIR/sshd_config si es necesario.${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# VERIFICAR PERMISOS DE SSHD_CONFIG
# ==============================================
check_config_permissions() {
  echo -e "\n${BLUE}[*] Verificando permisos de $SSHD_CONFIG...${NC}"
  check_permissions "$SSHD_CONFIG" "600" "root" "root" "Permisos de sshd_config"
}

# ==============================================
# 5.3.2 - LIMITAR ACCESO SSH
# ==============================================
check_access_limit() {
  echo -e "\n${BLUE}[*] CIS 5.3.2 - Limitando acceso SSH...${NC}"

  local allow_users=$(sshd -T 2>/dev/null | grep -i "allowusers" | awk '{print $2}')
  local allow_groups=$(sshd -T 2>/dev/null | grep -i "allowgroups" | awk '{print $2}')

  if [ -n "$allow_users" ] || [ -n "$allow_groups" ]; then
    echo -e "${GREEN}[✓] Acceso limitado a usuarios/grupos especificos${NC}"
  else
    echo -e "${RED}[!] No hay restriccion de acceso SSH${NC}"
    echo -e "${YELLOW}    Recomendacion: Agregar 'AllowUsers usuario1 usuario2' o 'AllowGroups grupo'${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 5.3.3 - LOGLEVEL
# ==============================================
check_loglevel() {
  echo -e "\n${BLUE}[*] CIS 5.3.3 - Configurando LogLevel...${NC}"
  check_sshd_param "loglevel" "INFO" "Nivel de log" "LogLevel INFO"
}

# ==============================================
# 5.3.4 - X11 FORWARDING
# ==============================================
check_x11() {
  echo -e "\n${BLUE}[*] CIS 5.3.4 - Deshabilitando X11 Forwarding...${NC}"
  check_sshd_param "x11forwarding" "no" "X11 Forwarding" "X11Forwarding no"
}

# ==============================================
# 5.3.5 - MAXAUTHRIES
# ==============================================
check_maxauth() {
  echo -e "\n${BLUE}[*] CIS 5.3.5 - Configurando MaxAuthTries...${NC}"
  check_sshd_param "maxauthtries" "4" "Maximo intentos de autenticacion" "MaxAuthTries 4"
}

# ==============================================
# 5.3.6 - IGNORERHOSTS
# ==============================================
check_ignorerhosts() {
  echo -e "\n${BLUE}[*] CIS 5.3.6 - Deshabilitando IgnoreRhosts...${NC}"
  check_sshd_param "ignorerhosts" "yes" "Ignore Rhosts" "IgnoreRhosts yes"
}

# ==============================================
# 5.3.7 - HOSTBASEDAUTHENTICATION
# ==============================================
check_hostbased() {
  echo -e "\n${BLUE}[*] CIS 5.3.7 - Deshabilitando HostbasedAuthentication...${NC}"
  check_sshd_param "hostbasedauthentication" "no" "Hostbased Authentication" "HostbasedAuthentication no"
}

# ==============================================
# 5.3.8 - PERMITROOTLOGIN
# ==============================================
check_root_login() {
  echo -e "\n${BLUE}[*] CIS 5.3.8 - Deshabilitando login root...${NC}"
  check_sshd_param "permitrootlogin" "no" "Permitir login root" "PermitRootLogin no"
}

# ==============================================
# 5.3.9 - PERMITEMPTYPASSWORDS
# ==============================================
check_empty_passwords() {
  echo -e "\n${BLUE}[*] CIS 5.3.9 - Deshabilitando contraseñas vacias...${NC}"
  check_sshd_param "permitemptypasswords" "no" "Permitir contraseñas vacias" "PermitEmptyPasswords no"
}

# ==============================================
# 5.3.10 - PERMITUSERENVIRONMENT
# ==============================================
check_user_env() {
  echo -e "\n${BLUE}[*] CIS 5.3.10 - Deshabilitando PermitUserEnvironment...${NC}"
  check_sshd_param "permituserenvironment" "no" "Permitir entorno de usuario" "PermitUserEnvironment no"
}

# ==============================================
# 5.3.11 - CIPHERS
# ==============================================
check_ciphers() {
  echo -e "\n${BLUE}[*] CIS 5.3.11 - Verificando algoritmos de cifrado...${NC}"
  check_sshd_param "ciphers" "aes256-ctr,aes192-ctr,aes128-ctr" "Ciphers" "Ciphers aes256-ctr,aes192-ctr,aes128-ctr"
}

# ==============================================
# 5.3.12 - MESSAGE AUTHENTICATION CODES
# ==============================================
check_macs() {
  echo -e "\n${BLUE}[*] CIS 5.3.12 - Verificando algoritmos MAC...${NC}"
  check_sshd_param "macs" "hmac-sha2-512,hmac-sha2-256" "MACs" "MACs hmac-sha2-512,hmac-sha2-256"
}

# ==============================================
# 5.3.13 - KEY EXCHANGE
# ==============================================
check_kex() {
  echo -e "\n${BLUE}[*] CIS 5.3.13 - Verificando algoritmos de intercambio de claves...${NC}"
  check_sshd_param "kexalgorithms" "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256" "KexAlgorithms" "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256"
}

# ==============================================
# 5.3.14 - IDLE TIMEOUT
# ==============================================
check_idle_timeout() {
  echo -e "\n${BLUE}[*] CIS 5.3.14 - Configurando timeout de inactividad SSH...${NC}"
  check_sshd_param "clientaliveinterval" "300" "ClientAliveInterval" "ClientAliveInterval 300"
  check_sshd_param "clientalivecountmax" "3" "ClientAliveCountMax" "ClientAliveCountMax 3"
}

# ==============================================
# 5.3.15 - LOGINGRACETIME
# ==============================================
check_grace_time() {
  echo -e "\n${BLUE}[*] CIS 5.3.15 - Configurando LoginGraceTime...${NC}"
  check_sshd_param "logingracetime" "60" "Tiempo de gracia para login" "LoginGraceTime 60"
}

# ==============================================
# 5.3.16 - WARNING BANNER
# ==============================================
check_banner() {
  echo -e "\n${BLUE}[*] CIS 5.3.16 - Configurando banner de advertencia...${NC}"
  local current="" effect="" tmp=""
  current="$(ssh_effective_value banner "$SSHD_CONFIG" || true)"
  if [ "$current" = "/etc/issue.net" ] && [ -s /etc/issue.net ]; then
    echo -e "${GREEN}[✓] Banner SSH efectivo: $current${NC}"
    return 0
  fi

  if [ ! -s /etc/issue.net ]; then
    effect="Crea un aviso previo a autenticación, sin enumerar servicios ni credenciales. Puede cambiar el texto legal que los usuarios ven al conectarse."
    echo -e "${YELLOW}[WARN] /etc/issue.net no contiene un banner no vacío.${NC}"
    if [ "$AUTO_FIX" != true ] || ! confirm_ssh_change "crear banner /etc/issue.net" "${current:-no banner}" "texto de uso autorizado" "$effect"; then
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
    if [ "$SSH_BACKUP_READY" != true ]; then WARNINGS=$((WARNINGS + 1)); return 1; fi
    if [ -e /etc/issue.net ]; then
      if [ -L /etc/issue.net ] || ! cp -p /etc/issue.net "$BACKUP_DIR/issue.net"; then
        echo -e "${RED}[WARN] No se pudo respaldar /etc/issue.net o es un symlink; no se modifica.${NC}"
        WARNINGS=$((WARNINGS + 1))
        return 1
      fi
    fi
    tmp="$(mktemp /etc/.issue.net.orangebox.XXXXXX)" || { WARNINGS=$((WARNINGS + 1)); return 1; }
    printf '%s\n' 'SISTEMA DE USO AUTORIZADO. El acceso no autorizado está prohibido.' > "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
    chmod 644 "$tmp" && chown root:root "$tmp" && mv "$tmp" /etc/issue.net || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
    echo -e "${GREEN}[✓] Banner /etc/issue.net creado.${NC}"
    FIXED=$((FIXED + 1))
  fi
  check_sshd_param "banner" "/etc/issue.net" "Banner SSH" "Banner /etc/issue.net"
}

# ==============================================
# 5.3.17 - PAM
# ==============================================
check_pam() {
  echo -e "\n${BLUE}[*] CIS 5.3.17 - Verificando PAM...${NC}"
  check_sshd_param "usepam" "yes" "Uso de PAM" "UsePAM yes"
}

# ==============================================
# 5.3.18 - ALLOWTCPFORWARDING
# ==============================================
check_tcp_forwarding() {
  echo -e "\n${BLUE}[*] CIS 5.3.18 - Deshabilitando TCP forwarding...${NC}"
  check_sshd_param "allowtcpforwarding" "no" "Allow TCP Forwarding" "AllowTcpForwarding no"
}

# ==============================================
# 5.3.19 - MAXSTARTUPS
# ==============================================
check_maxstartups() {
  echo -e "\n${BLUE}[*] CIS 5.3.19 - Configurando MaxStartups...${NC}"
  check_sshd_param "maxstartups" "10:30:60" "Maximo de conexiones simultaneas" "MaxStartups 10:30:60"
}

# ==============================================
# 5.3.20 - MAXSESSIONS
# ==============================================
check_maxsessions() {
  echo -e "\n${BLUE}[*] CIS 5.3.20 - Configurando MaxSessions...${NC}"
  check_sshd_param "maxsessions" "10" "Maximo de sesiones por conexion" "MaxSessions 10"
}

# ==============================================
# CONFIGURACIONES ADICIONALES DE SEGURIDAD
# COMPATIBLE CON OPENSSH 7.4+ (RHEL 7 A 10)
# ==============================================
check_extra_security() {
  echo -e "\n${BLUE}[*] Configurando medidas de seguridad adicionales...${NC}"

  local ssh_version=$(get_ssh_version)
  echo -e "${BLUE}[*] Version detectada: OpenSSH $ssh_version${NC}"

  # El valor esperado debe coincidir con el conjunto que aplica --fix;
  # dejarlo vacío generaba el absurdo "(debe ser )" y no permitía auditarlo.
  local accepted_key_algorithms="ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256"
  if [ "$ssh_version" -ge 9 ] 2>/dev/null; then
    check_sshd_param "pubkeyacceptedalgorithms" "$accepted_key_algorithms" "Algoritmos de clave publica" "PubkeyAcceptedAlgorithms $accepted_key_algorithms"
  elif [ "$ssh_version" -ge 7 ] 2>/dev/null; then
    check_sshd_param "pubkeyacceptedkeytypes" "$accepted_key_algorithms" "Algoritmos de clave publica" "PubkeyAcceptedKeyTypes $accepted_key_algorithms"
  else
    echo -e "${YELLOW}[!] OpenSSH antiguo detectado (versión < 7 o no identificada); los algoritmos modernos no se evalúan ni aplican aquí. Requiere revisión específica.${NC}"
  fi

  check_sshd_param "compression" "no" "Compresion" "Compression no"
  check_sshd_param "gssapiauthentication" "no" "GSSAPI Authentication" "GSSAPIAuthentication no"
  check_sshd_param "kerberosauthentication" "no" "Kerberos Authentication" "KerberosAuthentication no"
}

# ==============================================
# REINICIAR SSH
# ==============================================
restart_ssh() {
  [ "$AUTO_FIX" = true ] || {
    echo -e "\n${BLUE}[*] Auditoría SSH: no se reiniciará ni modificará el servicio.${NC}"
    return 0
  }
  [ "$SSH_CONFIG_CHANGED" = true ] || {
    echo -e "\n${GREEN}[✓] No se cambió la configuración SSH; no se recarga el servicio.${NC}"
    return 0
  }

  local effect="Recarga la configuración validada de sshd. Las sesiones establecidas normalmente permanecen activas, pero nuevas conexiones usarán la política nueva; una política inadecuada puede impedir nuevos logins. Mantén abierta esta sesión y prueba una segunda conexión antes de cerrarla."
  if ! sshd -t; then
    echo -e "${RED}[ERROR] sshd -t falló; no se recarga el servicio. Backup: $BACKUP_DIR/sshd_config${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if ! confirm_ssh_change "recargar sshd" "configuración SSH modificada y sshd -t válido" "systemctl reload sshd / service sshd reload" "$effect"; then
    echo -e "${YELLOW}[WARN] La configuración está guardada pero no activa; el servicio no fue recargado.${NC}"
    return 1
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl reload sshd 2>/dev/null; then
    echo -e "${GREEN}[✓] sshd recargado sin reiniciar sesiones existentes${NC}"
    return 0
  fi
  if command -v service >/dev/null 2>&1 && service sshd reload 2>/dev/null; then
    echo -e "${GREEN}[✓] sshd recargado sin reiniciar sesiones existentes${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] No se pudo recargar sshd. No se fuerza un restart; la configuración queda pendiente de aplicar. Backup: $BACKUP_DIR/sshd_config${NC}"
  WARNINGS=$((WARNINGS + 1))
  return 1
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  REPORTE SSH HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  else
    echo -e "  • Backup: no creado (modo auditoría)"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACION:${NC}"
  echo -e "  sshd -T"
  echo -e "  sshd -t"
  echo -e "  cat $SSHD_CONFIG | grep -E '^(PermitRootLogin|PasswordAuthentication|Port|Protocol)'"

  echo -e "\n${YELLOW}PARA VER LOGS DE SSH:${NC}"
  echo -e "  tail -f /var/log/secure | grep sshd"
  echo -e "\n${YELLOW}PARA APLICAR LAS CORRECCIONES EJECUTA:${NC}"
  echo -e "  ./ssh-hardening.sh --fix\n"
}

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${YELLOW}"
  echo "Este script audita y configura controles SSH basados en el CIS Benchmark."
  echo "Cada cambio de parámetro requiere confirmación, backup y validación con sshd -t."
  echo "Se mantiene abierta la sesión actual y se recarga sshd (no se fuerza restart)."
  echo "Backup en: $BACKUP_DIR"
  echo -e "${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  SSH Hardening - CIS 5.3.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    if ! make_backup; then
      echo -e "${RED}[ERROR] Backup SSH falló; no se aplicarán cambios.${NC}" >&2
      exit 1
    fi
    show_intro
    echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
    echo ""
  else
    AUTO_FIX=false
    echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
    echo ""
  fi

  check_config_permissions
  check_access_limit
  check_loglevel
  check_x11
  check_maxauth
  check_ignorerhosts
  check_hostbased
  check_root_login
  check_empty_passwords
  check_user_env
  check_ciphers
  check_macs
  check_kex
  check_idle_timeout
  check_grace_time
  check_banner
  check_pam
  check_tcp_forwarding
  check_maxstartups
  check_maxsessions
  check_extra_security
  restart_ssh
  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
