#!/bin/bash

# ==============================================
# Script: ssh-hardening-complete.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening completo de SSH basado en ssh-audit
#              Compatible con RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10
#              Respeta estructura de includes en RHEL 8+
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
SSHD_CONFIG_D="/etc/ssh/sshd_config.d"
HARDENING_CONF="$SSHD_CONFIG_D/00-orangebox-hardening.conf"
SSH_MODULI="/etc/ssh/moduli"
BACKUP_DIR="/root/ssh-backup-$(date +%Y%m%d-%H%M%S)"
SSH_BACKUP_READY=false
SSH_CONFIG_CHANGED=false

# ==============================================
# FUNCION PARA VERIFICAR E INSTALAR ssh-audit
# ==============================================
check_ssh_audit() {
  if command -v ssh-audit >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] ssh-audit está disponible; no se instala ni actualiza desde este script.${NC}"
  else
    echo -e "${YELLOW}[INFO] ssh-audit no está instalado; se omite análisis externo. El script no instalará paquetes ni habilitará repositorios automáticamente.${NC}"
  fi
}

# ==============================================
# FUNCION PARA DETECTAR DISTRIBUCION
# ==============================================
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
    rocky | almalinux | centos | rhel | oracle)
      distro="$ID"
      distro_version=$(echo "$VERSION_ID" | cut -d. -f1)
      ;;
    *)
      if [[ "$ID_LIKE" == *"rhel"* ]]; then
        distro="rhel"
        distro_version=$(echo "$VERSION_ID" | cut -d. -f1)
      else
        echo -e "${RED}[!] Distribucion no soportada: $ID${NC}"
        exit 1
      fi
      ;;
    esac
  else
    echo -e "${RED}[!] No se pudo detectar la distribucion${NC}"
    exit 1
  fi

  case "$distro_version" in
  7 | 8 | 9 | 10)
    rhel_version="$distro_version"
    ;;
  *)
    echo -e "${RED}[!] Version no soportada: $distro_version${NC}"
    echo -e "${YELLOW}    Versiones soportadas: 7, 8, 9, 10${NC}"
    exit 1
    ;;
  esac

  echo -e "${GREEN}[✓] Distribucion detectada: $distro $rhel_version${NC}"
}

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
  echo "  ./ssh-hardening-complete.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./ssh-hardening-complete.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA MOSTRAR ANALISIS ACTUAL DE SSH-AUDIT
# ==============================================
show_ssh_audit_analysis() {
  echo -e "\n${BLUE}[*] Analisis actual de ssh-audit:${NC}\n"

  if ! command -v ssh-audit &>/dev/null; then
    echo -e "${YELLOW}[WARN] ssh-audit no está instalado; se omite el análisis externo en modo auditoría sin instalar paquetes.${NC}"
    return 0
  fi

  local audit_output=$(ssh-audit localhost 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

  echo -e "${YELLOW}=== KEY EXCHANGE ALGORITHMS ===${NC}"
  local in_section=""

  while IFS= read -r line; do
    if echo "$line" | grep -q "^# key exchange algorithms"; then
      in_section="kex"
      continue
    fi
    if echo "$line" | grep -q "^# host-key algorithms"; then
      in_section="key"
      echo ""
      echo -e "${YELLOW}=== HOST-KEY ALGORITHMS ===${NC}"
      continue
    fi
    if echo "$line" | grep -q "^# encryption algorithms"; then
      in_section="enc"
      echo ""
      echo -e "${YELLOW}=== ENCRYPTION ALGORITHMS ===${NC}"
      continue
    fi
    if echo "$line" | grep -q "^# message authentication code algorithms"; then
      in_section="mac"
      echo ""
      echo -e "${YELLOW}=== MAC ALGORITHMS ===${NC}"
      continue
    fi
    if echo "$line" | grep -q "^# fingerprints"; then
      in_section=""
      continue
    fi

    if [ -n "$in_section" ] && echo "$line" | grep -q "^("; then
      if echo "$line" | grep -q "\[fail\]"; then
        echo -e "  ${RED}❌ FAIL:${NC} $line"
      elif echo "$line" | grep -q "\[warn\]"; then
        echo -e "  ${YELLOW}⚠️  WARN:${NC} $line"
      elif echo "$line" | grep -q "\[info\]"; then
        echo -e "  ${GREEN}✓${NC} $line"
      else
        echo -e "  ${BLUE}ℹ️${NC} $line"
      fi
    fi
  done <<<"$audit_output"

  echo -e "\n${YELLOW}=== RECOMENDACIONES ===${NC}"
  local recs=$(echo "$audit_output" | grep -E "\(rec\)")

  if [ -n "$recs" ]; then
    echo "$recs" | while read line; do
      local clean_line=$(echo "$line" | sed 's/(rec) //')
      if echo "$clean_line" | grep -q "^-"; then
        echo -e "  ${RED}➖ REMOVER:${NC} $(echo "$clean_line" | sed 's/^-//')"
      elif echo "$clean_line" | grep -q "^+"; then
        echo -e "  ${GREEN}➕ AGREGAR:${NC} $(echo "$clean_line" | sed 's/^+//')"
      else
        echo -e "  ${BLUE}→${NC} $clean_line"
      fi
    done
  else
    echo -e "  ${GREEN}✓ No hay recomendaciones pendientes${NC}"
  fi
}

confirm_ssh_complete_change() {
  local title="$1" current="$2" proposed="$3" effect="$4" answer=""
  echo -e "\n${YELLOW}[WARN] Cambio SSH avanzado pendiente: $title${NC}"
  echo "Estado actual: ${current:-no verificable}"
  echo "Propuesta: $proposed"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ] || [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "${YELLOW}[WARN] No hay autorización interactiva disponible; se omite el cambio.${NC}"
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

ssh_effective_value() {
  local key="$1"
  sshd -T 2>/dev/null | awk -v key="$key" 'tolower($1)==tolower(key) {$1=""; sub(/^[[:space:]]+/, ""); print; found=1; exit} END {if (!found) exit 1}'
}

ssh_setting_impact() {
  case "$1" in
    kexalgorithms) echo "Restringe el intercambio de claves; los clientes SSH antiguos pueden no tener un algoritmo común." ;;
    ciphers) echo "Restringe cifrados; equipos legacy pueden dejar de negociar una sesión." ;;
    macs) echo "Restringe algoritmos MAC; clientes antiguos pueden perder compatibilidad." ;;
    permitemptypasswords) echo "Impide autenticación mediante contraseñas vacías." ;;
    challenger esponseauthentication|kbdinteractiveauthentication) echo "Desactiva keyboard-interactive; puede romper MFA o módulos PAM que dependan de ese método." ;;
    kerberosauthentication|gssapiauthentication) echo "Desactiva autenticación integrada Kerberos/GSSAPI; identidades de dominio o SSO pueden verse afectadas." ;;
    x11forwarding) echo "Deshabilita aplicaciones gráficas remotas por SSH." ;;
    allowtcpforwarding) echo "Deshabilita túneles TCP/port-forwarding SSH; puede afectar bastiones, proxies y automatización." ;;
    permituserenvironment) echo "Impide variables de entorno SSH definidas por usuarios; puede cambiar comandos remotos." ;;
    clientaliveinterval|clientalivecountmax) echo "Cierra sesiones que no responden a keepalive; conexiones inestables o sesiones largas pueden desconectarse." ;;
    maxauthtries) echo "Limita intentos de login por conexión; puede afectar usuarios con varios métodos/llaves." ;;
    logingracetime) echo "Limita el tiempo para autenticarse; clientes de autenticación lenta pueden fallar." ;;
    maxsessions) echo "Limita sesiones multiplexadas por conexión." ;;
    us epam|usepam) echo "Cambia la integración con PAM y puede afectar autenticación, MFA o políticas de sesión." ;;
    *) echo "Modifica la política SSH; valida clientes y accesos administrativos desde una segunda sesión." ;;
  esac
}

# ==============================================
# FUNCION PARA MOSTRAR CONFIGURACION ACTUAL
# ==============================================
show_effective_sshd_value() {
  local key="$1" value=""
  if command -v sshd >/dev/null 2>&1; then
    value="$(sshd -T 2>/dev/null | awk -v key="$key" '$1 == key {$1=""; sub(/^[[:space:]]+/, ""); print; exit}')"
  fi
  if [ -n "$value" ]; then
    printf '  %s\n' "$value"
  else
    echo "  [WARN] Valor efectivo no disponible mediante sshd -T"
  fi
}

show_current_config() {
  echo -e "\n${BLUE}[*] Configuración efectiva global de SSH (sshd -T):${NC}\n"
  echo -e "${YELLOW}KexAlgorithms:${NC}"
  show_effective_sshd_value kexalgorithms
  echo -e "\n${YELLOW}Ciphers:${NC}"
  show_effective_sshd_value ciphers
  echo -e "\n${YELLOW}MACs:${NC}"
  show_effective_sshd_value macs
  echo -e "\n${YELLOW}HostKeyAlgorithms:${NC}"
  show_effective_sshd_value hostkeyalgorithms
  echo -e "\n${YELLOW}PermitRootLogin:${NC}"
  show_effective_sshd_value permitrootlogin
  echo -e "\n${YELLOW}[INFO] Las directivas Match pueden variar por usuario, origen y conexión; estos son los valores globales.${NC}"
}

# ==============================================
# FUNCION PARA MOSTRAR LO QUE SE VA A APLICAR
# ==============================================
show_will_apply() {
  echo -e "\n${YELLOW}LO QUE SE PROPONE APLICAR CON --fix${NC}"
  echo "Se propone escribir un drop-in gestionado, validarlo con sshd -t y verificar valores efectivos."
  echo "Cada directiva queda listada con su propósito y posible impacto:"
  echo "  KexAlgorithms: limita intercambio de claves; clientes antiguos pueden no negociar."
  echo "  Ciphers: limita cifrados; clientes con algoritmos antiguos pueden quedar sin compatibilidad."
  echo "  MACs: limita autenticación de mensajes; clientes legacy pueden no conectar."
  echo "  PermitEmptyPasswords no: rechaza contraseñas vacías."
  echo "  ChallengeResponseAuthentication no: puede afectar MFA o PAM que use keyboard-interactive."
  echo "  KerberosAuthentication no y GSSAPIAuthentication no: pueden interrumpir autenticación integrada con Kerberos/GSSAPI."
  echo "  X11Forwarding no: desactiva aplicaciones gráficas remotas por SSH."
  echo "  AllowTcpForwarding no: rompe túneles SSH, port-forwarding, algunos bastiones y herramientas."
  echo "  PermitUserEnvironment no: impide variables de entorno configuradas por usuario."
  echo "  ClientAliveInterval=300 y ClientAliveCountMax=3: pueden cerrar sesiones inactivas o conexiones inestables."
  echo "  MaxAuthTries=4 y LoginGraceTime=60: restringen intentos/tiempo de login."
  echo "  MaxSessions=10: limita sesiones multiplexadas por conexión."
  echo "  LogLevel VERBOSE: aumenta detalle y volumen de logs."
  echo "  UsePAM yes y StrictModes yes: refuerzan controles PAM y permisos; pueden exponer errores de configuración existentes."
  echo
  echo "NO se regeneran ni eliminan claves de host (se conserva la identidad SSH del servidor)."
  echo "NO se modifica /etc/ssh/moduli ni el backend de crypto-policies del proveedor."
  echo "NO se modifica ninguna regla de firewall desde este script."
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  [ "$AUTO_FIX" = true ] || return 0
  if [ ! -f "$SSHD_CONFIG" ] || [ -L "$SSHD_CONFIG" ]; then
    echo -e "${RED}[ERROR] $SSHD_CONFIG no es un archivo regular seguro; no se modifica SSH.${NC}" >&2
    return 1
  fi
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[ERROR] No se pudo preparar el backup $BACKUP_DIR; no se modifica SSH.${NC}" >&2
    return 1
  fi
  if ! cp -p "$SSHD_CONFIG" "$BACKUP_DIR/"; then
    echo -e "${RED}[ERROR] No se pudo respaldar $SSHD_CONFIG; no se modifica SSH.${NC}" >&2
    return 1
  fi
  if [ -d "$SSHD_CONFIG_D" ] && ! cp -a "$SSHD_CONFIG_D" "$BACKUP_DIR/"; then
    echo -e "${RED}[ERROR] No se pudo respaldar $SSHD_CONFIG_D; no se modifica SSH.${NC}" >&2
    return 1
  fi
  SSH_BACKUP_READY=true
  echo -e "${GREEN}[✓] Backup SSH verificado en: $BACKUP_DIR${NC}"
}

# ==============================================
# FUNCION PARA CREAR ARCHIVO DE HARDENING EN SSHD_CONFIG_D
# ==============================================
create_hardening_conf() {
  local include_ok=false target="" candidate="" prior="" key="" desired="" current="" effect=""
  local -a proposed_lines=(
    "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512,diffie-hellman-group-exchange-sha256"
    "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
    "MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com"
    "PermitEmptyPasswords no"
    "ChallengeResponseAuthentication no"
    "KerberosAuthentication no"
    "GSSAPIAuthentication no"
    "X11Forwarding no"
    "AllowTcpForwarding no"
    "PermitUserEnvironment no"
    "ClientAliveInterval 300"
    "ClientAliveCountMax 3"
    "MaxAuthTries 4"
    "MaxSessions 10"
    "LoginGraceTime 60"
    "LogLevel VERBOSE"
    "UsePAM yes"
    "Compression no"
    "PrintLastLog yes"
    "IgnoreRhosts yes"
    "StrictModes yes"
  )
  local -a selected_lines=() selected_keys=() selected_values=()

  [ "$SSH_BACKUP_READY" = true ] || { echo -e "${RED}[WARN] No hay backup SSH verificado; no se modifica el archivo.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1; }

  if grep -Eiq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]|$)' "$SSHD_CONFIG"; then
    target="$HARDENING_CONF"
    include_ok=true
  else
    # EL7 and custom EL8+ configs may not include sshd_config.d. Use a managed
    # block in the main config, still validated through an adjacent candidate.
    target="$SSHD_CONFIG"
  fi

  if [ "$target" = "$HARDENING_CONF" ] && [ -e "$target" ]; then
    if [ -L "$target" ] || ! grep -Fq '# ORANGEBOX MANAGED SSH HARDENING BEGIN' "$target"; then
      echo -e "${YELLOW}[WARN] $target already exists and is not an OrangeBox-managed drop-in; it will not be overwritten.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  fi

  for line in "${proposed_lines[@]}"; do
    key="${line%% *}"
    desired="${line#* }"
    current="$(ssh_effective_value "$key" || true)"
    if [ "$current" = "$desired" ]; then
      # Keep a previously managed compliant directive in the candidate, if present.
      if [ "$target" = "$HARDENING_CONF" ] && [ -f "$target" ] &&
         grep -Eiq "^[[:space:]]*${key}[[:space:]]+${desired//,/\\,}[[:space:]]*$" "$target"; then
        selected_lines+=("$line")
        selected_keys+=("$key")
        selected_values+=("$desired")
      fi
      continue
    fi
    effect="$(ssh_setting_impact "$key")"
    echo -e "${YELLOW}[WARN] SSH $key: actual='${current:-no verificable}', objetivo='$desired'.${NC}"
    if ! confirm_ssh_complete_change "$key" "${current:-no verificable}" "$line" "$effect"; then
      continue
    fi
    selected_lines+=("$line")
    selected_keys+=("$key")
    selected_values+=("$desired")
  done

  if [ "${#selected_lines[@]}" -eq 0 ]; then
    echo -e "${GREEN}[✓] No hay parámetros SSH aprobados pendientes; no se modifica configuración.${NC}"
    return 0
  fi

  local candidate_dir candidate_base previous_backup=""
  candidate_dir="$(dirname "$target")"
  if [ "$target" = "$HARDENING_CONF" ]; then
    candidate="$(mktemp --suffix=.conf "$SSHD_CONFIG_D/00-orangebox-candidate.XXXXXX")" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  else
    candidate="$(mktemp /etc/ssh/.sshd_config.orangebox.candidate.XXXXXX)" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  fi
  prior="$(mktemp)" || { rm -f "$candidate"; WARNINGS=$((WARNINGS + 1)); return 1; }
  candidate_base="$(mktemp)" || { rm -f "$candidate" "$prior"; WARNINGS=$((WARNINGS + 1)); return 1; }

  if [ "$target" = "$HARDENING_CONF" ]; then
    if [ -f "$target" ]; then
      previous_backup="$BACKUP_DIR/sshd_config.d/$(basename "$target")"
      [ -f "$previous_backup" ] || { echo -e "${RED}[WARN] No se verificó el backup del drop-in gestionado.${NC}"; rm -f "$candidate" "$prior" "$candidate_base"; WARNINGS=$((WARNINGS + 1)); return 1; }
      awk '
        /^# ORANGEBOX MANAGED SSH HARDENING BEGIN$/ {inside=1; next}
        /^# ORANGEBOX MANAGED SSH HARDENING END$/ {inside=0; next}
        !inside {print}
      ' "$target" > "$candidate_base" || { rm -f "$candidate" "$prior" "$candidate_base"; WARNINGS=$((WARNINGS + 1)); return 1; }
    else
      : > "$candidate_base"
    fi
  else
    previous_backup="$BACKUP_DIR/sshd_config"
    awk '
      /^# ORANGEBOX MANAGED SSH HARDENING BEGIN$/ {inside=1; next}
      /^# ORANGEBOX MANAGED SSH HARDENING END$/ {inside=0; next}
      !inside {print}
    ' "$SSHD_CONFIG" > "$candidate_base" || { rm -f "$candidate" "$prior" "$candidate_base"; WARNINGS=$((WARNINGS + 1)); return 1; }
  fi

  {
    printf '%s\n' '# ORANGEBOX MANAGED SSH HARDENING BEGIN'
    printf '%s\n' "${selected_lines[@]}"
    printf '%s\n' '# ORANGEBOX MANAGED SSH HARDENING END'
    cat "$candidate_base"
  } > "$candidate" || { rm -f "$candidate" "$prior" "$candidate_base"; WARNINGS=$((WARNINGS + 1)); return 1; }
  chmod 600 "$candidate" && chown root:root "$candidate" || { rm -f "$candidate" "$prior" "$candidate_base"; WARNINGS=$((WARNINGS + 1)); return 1; }

  if ! sshd -t -f "$SSHD_CONFIG" >/dev/null 2>&1 && [ "$target" = "$SSHD_CONFIG" ]; then
    echo -e "${RED}[WARN] La configuración SSH actual ya falla sshd -t; no se instala un candidato automático.${NC}"
    rm -f "$candidate" "$prior" "$candidate_base"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  # Validate the candidate as a complete config for the main-file path; for
  # drop-ins, stage it in the included directory and ask sshd to parse the whole config.
  if [ "$target" = "$HARDENING_CONF" ]; then
    if ! sshd -t >/dev/null 2>&1; then
      echo -e "${RED}[WARN] sshd -t failed with the staged candidate; no hardening file installed.${NC}"
      rm -f "$candidate" "$prior" "$candidate_base"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  else
    if ! sshd -t -f "$candidate" >/dev/null 2>&1; then
      echo -e "${RED}[WARN] The SSH candidate did not pass sshd -t; main config unchanged.${NC}"
      rm -f "$candidate" "$prior" "$candidate_base"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  fi

  # For drop-ins, the candidate is already loaded by Include during validation.
  # Switch it into the managed target only after the full config has passed.
  if [ "$target" = "$HARDENING_CONF" ]; then
    if ! mv "$candidate" "$target"; then
      rm -f "$candidate" "$prior" "$candidate_base"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  else
    if [ -f "$target" ] && [ -L "$target" ]; then
      echo -e "${RED}[WARN] Main sshd_config is a symlink; no automatic update.${NC}"
      rm -f "$candidate" "$prior" "$candidate_base"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
    if ! mv "$candidate" "$target"; then
      rm -f "$candidate" "$prior" "$candidate_base"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  fi
  command -v restorecon >/dev/null 2>&1 && restorecon "$target" >/dev/null 2>&1 || true

  local verify_failed=false key_idx actual
  for ((key_idx=0; key_idx<${#selected_keys[@]}; key_idx++)); do
    key="${selected_keys[$key_idx]}"
    desired="${selected_values[$key_idx]}"
    actual="$(ssh_effective_value "$key" || true)"
    if [ "$actual" != "$desired" ]; then
      echo -e "${YELLOW}[WARN] SSH $key no quedó efectivo: actual='${actual:-no verificable}', esperado='$desired'.${NC}"
      verify_failed=true
    fi
  done
  if ! sshd -t >/dev/null 2>&1; then verify_failed=true; fi

  if [ "$verify_failed" = true ]; then
    echo -e "${RED}[WARN] Validación posterior fallida; se revierte el archivo de hardening.${NC}"
    if [ "$target" = "$HARDENING_CONF" ]; then
      if [ -f "$BACKUP_DIR/sshd_config.d/$(basename "$HARDENING_CONF")" ]; then
        cp -p "$BACKUP_DIR/sshd_config.d/$(basename "$HARDENING_CONF")" "$target"
      else
        rm -f "$target"
      fi
    else
      cp -p "$BACKUP_DIR/sshd_config" "$target"
    fi
    command -v restorecon >/dev/null 2>&1 && restorecon "$target" >/dev/null 2>&1 || true
    rm -f "$prior" "$candidate_base"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  SSH_CONFIG_CHANGED=true
  FIXED=$((FIXED + 1))
  echo -e "${GREEN}[✓] Parámetros aprobados aplicados y verificados con sshd -t y sshd -T.${NC}"
  rm -f "$prior" "$candidate_base"
  return 0
}

# ==============================================
# FUNCION PARA RHEL 7
# ==============================================
apply_hardening_rhel7() {
  echo -e "\n${BLUE}[*] Hardening SSH conservador para RHEL/CentOS 7.${NC}"
  echo -e "${YELLOW}[INFO] Se mantienen las claves de host y los grupos moduli existentes.${NC}"
  create_hardening_conf
}

# ==============================================
# FUNCION PARA RHEL 8
# ==============================================
apply_hardening_rhel8() {
  echo -e "\n${BLUE}[*] Hardening SSH conservador para RHEL/CentOS 8.${NC}"
  echo -e "${YELLOW}[INFO] No se sobreescribe crypto-policies del proveedor; se valida el valor efectivo de sshd.${NC}"
  create_hardening_conf
}

# ==============================================
# FUNCION PARA RHEL 9
# ==============================================
apply_hardening_rhel9() {
  echo -e "\n${BLUE}[*] Hardening SSH conservador para RHEL/Rocky/AlmaLinux 9.${NC}"
  echo -e "${YELLOW}[INFO] No se regeneran host keys ni se sobreescribe crypto-policies del proveedor.${NC}"
  create_hardening_conf
}

# ==============================================
# FUNCION PARA RHEL 10
# ==============================================
apply_hardening_rhel10() {
  echo -e "\n${BLUE}[*] Hardening SSH conservador para RHEL/Rocky/AlmaLinux 10.${NC}"
  echo -e "${YELLOW}[INFO] No se regeneran host keys ni se sobreescribe crypto-policies del proveedor.${NC}"
  create_hardening_conf
}

# ==============================================
# FUNCION PARA CONFIGURAR THROTTLING
# ==============================================
configure_throttling() {
  echo -e "${BLUE}[INFO] El hardening SSH no modifica firewalld ni reglas de firewall. Usa audit-firewall-listeners.sh para evaluar la exposición y gestiona reglas por separado.${NC}"
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  SSH HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR:${NC}"
  echo -e "  sshd -t"
  echo -e "  ssh-audit localhost"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  SSH Hardening Complete - sshaudit.com${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  detect_distro
  case "${1:-}" in
    --help|-h) show_usage; exit 0 ;;
    "") show_ssh_audit_analysis; show_current_config; show_will_apply; exit 0 ;;
    --fix|-f) ;;
    *) echo -e "${RED}[!] Opción desconocida: $1${NC}" >&2; exit 2 ;;
  esac

  AUTO_FIX=true
  check_ssh_audit
  show_current_config
  show_will_apply
  if ! make_backup; then
    echo -e "${RED}[ERROR] Backup fallido; no se modifica SSH.${NC}" >&2
    exit 1
  fi

  local effect="Escribe una configuración SSH gestionada con cifrados, KEX y MAC limitados; desactiva X11 y TCP forwarding, endurece intentos/timeout e integración de autenticación. Puede afectar clientes legacy, túneles, MFA/PAM, SSO, aplicaciones gráficas y sesiones inactivas. No cambia host keys, moduli, crypto-policy del proveedor ni firewall."
  if ! confirm_ssh_complete_change "aplicar bloque de hardening SSH" "política SSH actual, detallada arriba" "crear/actualizar $HARDENING_CONF con confirmación por cada directiva diferente" "$effect"; then
    echo -e "${YELLOW}[INFO] No se aplicaron cambios SSH.${NC}"
    exit 0
  fi

  local apply_rc=0
  case "$rhel_version" in
    7) apply_hardening_rhel7 || apply_rc=$? ;;
    8) apply_hardening_rhel8 || apply_rc=$? ;;
    9) apply_hardening_rhel9 || apply_rc=$? ;;
    10) apply_hardening_rhel10 || apply_rc=$? ;;
  esac

  if [ "$apply_rc" -ne 0 ]; then
    echo -e "${YELLOW}[WARN] La configuración propuesta no pudo aplicarse/verificarse por completo. Revise los detalles antes de intentar otra vez.${NC}"
    show_summary
    exit "$apply_rc"
  fi

  if [ "$SSH_CONFIG_CHANGED" = true ]; then
    local reload_effect="Recarga sshd sin detener el daemon. Las sesiones establecidas normalmente se conservan, pero una configuración incompatible puede impedir nuevas conexiones. Mantén abierta la sesión actual y prueba otra conexión antes de cerrarla."
    if confirm_ssh_complete_change "recargar sshd" "configuración nueva validada" "systemctl reload sshd o service sshd reload (sin restart)" "$reload_effect"; then
      if { command -v systemctl >/dev/null 2>&1 && systemctl reload sshd 2>/dev/null; } ||
         { command -v service >/dev/null 2>&1 && service sshd reload 2>/dev/null; }; then
        echo -e "${GREEN}[✓] sshd recargado correctamente; las sesiones activas no se reinician.${NC}"
      else
        echo -e "${YELLOW}[WARN] No se pudo recargar sshd; no se fuerza restart. La configuración queda validada pero no aplicada al proceso actual.${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}[WARN] Se guardó la configuración validada, pero no se recargó sshd; los cambios quedan pendientes.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] No hubo cambios efectivos; no se recarga sshd.${NC}"
  fi
  show_summary
  echo -e "
${BLUE}Verifique con: sshd -t && sshd -T && ssh-audit localhost (si está instalado)${NC}"
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
