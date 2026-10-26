#!/bin/bash
# OrangeBox Linux Hardening - Safe Enterprise Baseline
# Version 1.4.26 - RHEL/CentOS/Rocky/AlmaLinux 6-10
# Audit by default. Interactive --fix asks separately before delicate modules; --fix --auto only applies banners/Bash and audits the delicate controls.
# Core baseline never changes SELinux or creates cron.allow/at.allow.
# High-risk companion modules require explicit selection and --allow-risky.
# System-wide crypto-policies are never changed by the core baseline.

set -u
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$SCRIPT_DIR/lib/sysctl-safe.sh" ]; then
  # shellcheck source=lib/sysctl-safe.sh
  source "$SCRIPT_DIR/lib/sysctl-safe.sh"
else
  echo "[ERROR] Falta lib/sysctl-safe.sh; actualice el repositorio completo." >&2
  exit 1
fi
if [ -r "$SCRIPT_DIR/lib/orangebox-motd.sh" ]; then
  # Generador portable del MOTD dinámico y lógica opcional de FIGlet.
  # shellcheck source=lib/orangebox-motd.sh
  source "$SCRIPT_DIR/lib/orangebox-motd.sh"
else
  echo "[ERROR] Falta lib/orangebox-motd.sh; actualice el repositorio completo." >&2
  exit 1
fi
SCRIPT_VERSION=1.4.26
AUTO_FIX=false
AUDIT_MODE=false
AUTO_MODE=false
ALLOW_RISKY=false
ALLOW_SHOREWALL=false
MODULE=all
RUN_ID=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/var/backups/orangebox-linux-hardening/$RUN_ID
FIXED=0
OK_COUNT=0
NOT_APPLICABLE_COUNT=0
WARNINGS=0
ERRORS=0
COMPANION_MODULES_RUN=0
COMPANION_MODULES_FAILED=0
PENDING_ONLY_AUDIT=false
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
section(){ echo -e "\n$BLUE### $1 ###$NC"; }
ok(){
  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    OK_COUNT=$((OK_COUNT+1))
  fi
  echo -e "$GREEN[OK]$NC $*"
}
info(){ if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then return 0; fi; echo -e "$BLUE[INFO]$NC $*"; }
warn(){ WARNINGS=$((WARNINGS+1)); echo -e "$YELLOW[WARN]$NC $*"; }; bad(){ WARNINGS=$((WARNINGS+1)); echo -e "$RED[FAIL]$NC $*"; }; die(){ ERRORS=$((ERRORS+1)); echo -e "$RED[ERROR]$NC $*"; exit 1; }
na(){ if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then NOT_APPLICABLE_COUNT=$((${NOT_APPLICABLE_COUNT:-0}+1)); fi; echo -e "$BLUE[N/A]$NC $*"; }
require_root(){ [ "$EUID" -eq 0 ] || die "Debe ejecutarse como root."; }
detect_os(){
  local os_release_file="${ORANGEBOX_OS_RELEASE_FILE:-/etc/os-release}"
  local redhat_release_file="${ORANGEBOX_REDHAT_RELEASE_FILE:-/etc/redhat-release}"
  local release_line release_version

  OS_ID=""
  OS_VERSION=""
  ID_LIKE=""

  if [ -r "$os_release_file" ]; then
    . "$os_release_file"
    OS_ID=${ID:-}
    OS_VERSION=$(echo "${VERSION_ID:-}" | cut -d. -f1)
    ID_LIKE=${ID_LIKE:-}
  fi

  # CentOS/RHEL 6 can lack /etc/os-release; use the legacy release marker.
  if [ -z "$OS_ID" ] || [ -z "$OS_VERSION" ]; then
    [ -r "$redhat_release_file" ] || die "No se encontró una identificación válida: $os_release_file ni $redhat_release_file"
    release_line=$(cat "$redhat_release_file" 2>/dev/null)
    release_version=$(printf '%s\n' "$release_line" | awk '
      { for (i=1; i<=NF; i++) if ($i == "release") {
          split($(i+1), version_parts, ".");
          print version_parts[1];
          exit
        }
      }')
    case "$release_line" in
      *CentOS*|*centos*) OS_ID=centos ;;
      *"Red Hat Enterprise Linux"*|*"Red Hat Linux"*) OS_ID=rhel ;;
      *"Oracle Linux"*|*"Oracle Linux Server"*) OS_ID=ol ;;
      *Rocky*|*rocky*) OS_ID=rocky ;;
      *AlmaLinux*|*almalinux*) OS_ID=almalinux ;;
      *) die "No se pudo identificar una distribución compatible desde $redhat_release_file: $release_line" ;;
    esac
    [ -n "$release_version" ] || die "No se pudo extraer la versión desde $redhat_release_file: $release_line"
    OS_VERSION="$release_version"
  fi

  case "$OS_ID" in rhel|centos|rocky|almalinux|ol|oracle) ;; *) [[ "$ID_LIKE" == *rhel* ]] || die "Distribución no soportada: $OS_ID";; esac
  case "$OS_VERSION" in 6|7|8|9|10) ;; *) die "Versión no soportada: $OS_VERSION";; esac
  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    echo -e "$BLUE[INFO]$NC Detectado: $OS_ID $OS_VERSION"
  else
    ok "Detectado: $OS_ID $OS_VERSION"
  fi
}
prepare_backup(){ mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"; }
backup_once(){ local src="$1"; [ -e "$src" ] || return 0; local dst="$BACKUP_DIR$(dirname "$src")"; mkdir -p "$dst"; cp -a "$src" "$BACKUP_DIR$src"; }
orangebox_sysctl_persistence_target() {
  if [ "${OS_VERSION:-}" = 6 ]; then
    printf '%s\n' /etc/sysctl.conf
  else
    printf '%s\n' /etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf
  fi
}
sysctl_baseline_target_writable() {
  local target
  target="$(orangebox_sysctl_persistence_target)"
  [ "$target" = /etc/sysctl.conf ] && return 0
  [ ! -L "$target" ] || return 1
  [ ! -e "$target" ] || grep -Fqx "# OrangeBox managed sysctl overrides" "$target"
}

set_sysctl(){
  local key="$1" value="$2" file
  if ! command -v sysctl >/dev/null 2>&1; then
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
      sysctl_safe_log "N/A" "sysctl no está disponible; no se puede consultar $key."
    else
      info "SYSCTL $key no disponible (falta el comando sysctl); no se modifica."
    fi
    return 0
  fi
  if ! sysctl -n "$key" >/dev/null 2>&1; then
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
      sysctl_safe_log "N/A" "$key no está expuesto por este kernel; el control no aplica."
    else
      info "SYSCTL $key no disponible en este kernel; no aplica y no se modifica."
    fi
    return 0
  fi
  file="$(orangebox_sysctl_persistence_target)"
  if sysctl_safe_apply "$key" "$value" "$(sysctl_safe_description "$key")" "$file" "$BACKUP_DIR" "$AUTO_FIX" "" ""; then
    [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED+1))
  else
    WARNINGS=$((WARNINGS+1))
  fi
}

set_kptr_restrict_policy(){
  local file
  file="$(orangebox_sysctl_persistence_target)"
  if sysctl_safe_apply_kptr_restrict_policy "$file" "$BACKUP_DIR" "$AUTO_FIX"; then
    [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED+1))
  else
    WARNINGS=$((WARNINGS+1))
  fi
}

SYNFLOOD_FILE=/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf
SYNFLOOD_KEYS="net.ipv4.tcp_syncookies net.ipv4.tcp_max_syn_backlog net.core.somaxconn"
SYNFLOOD_VALUES=(1 4096 4096)
synflood_select_persistence_target() {
  SYNFLOOD_FILE="$(orangebox_sysctl_persistence_target)"
}
synflood_module(){
  section "SYN FLOOD / TCP BACKLOG"
  synflood_select_persistence_target
  if [ "$SYNFLOOD_FILE" = /etc/sysctl.conf ]; then
    info "CentOS/RHEL 6: se usa /etc/sysctl.conf; no se crea /etc/sysctl.d."
  fi
  local idx=0 key desired
  for key in $SYNFLOOD_KEYS; do
    desired="${SYNFLOOD_VALUES[$idx]}"
    set_sysctl "$key" "$desired"
    idx=$((idx+1))
  done
  info "Los valores externos de sysctl se conservan. Los valores distintos solo se imponen con confirmación individual."
}

synflood_state_compliant() {
  synflood_select_persistence_target
  local idx=0 key desired check_output
  for key in $SYNFLOOD_KEYS; do
    desired="${SYNFLOOD_VALUES[$idx]}"
    if ! check_output="$(sysctl_safe_apply "$key" "$desired" "$(sysctl_safe_description "$key")" "$SYNFLOOD_FILE" "$BACKUP_DIR" false "" "" 2>&1)"; then
      return 1
    fi
    idx=$((idx+1))
  done
  return 0
}
ssh_effective(){ sshd -T 2>/dev/null|awk -v k="$1" '$1==k{$1="";sub(/^ /,"");print;exit}'; }

# SSH settings that the generic baseline is allowed to enforce.
# sshd -T parses the effective configuration from disk; no daemon reload is done.
SSH_DROPIN=/etc/ssh/sshd_config.d/49-orangebox-hardening.conf
SSH_EXPECTED_SETTINGS=(
  "ignorerhosts|yes|IgnoreRhosts"
  "hostbasedauthentication|no|HostbasedAuthentication"
  "permituserenvironment|no|PermitUserEnvironment"
  "permitemptypasswords|no|PermitEmptyPasswords"
  "permitrootlogin|no|PermitRootLogin"
  "x11forwarding|no|X11Forwarding"
  "allowtcpforwarding|no|AllowTcpForwarding"
  "allowagentforwarding|no|AllowAgentForwarding"
  "maxauthtries|6|MaxAuthTries"
  "logingracetime|60|LoginGraceTime"
  "clientaliveinterval|300|ClientAliveInterval"
  "clientalivecountmax|2|ClientAliveCountMax"
  "loglevel|INFO|LogLevel"
)

ssh_setting_description() {
  case "$1" in
    ignorerhosts) echo "Ignora archivos .rhosts, que pueden permitir autenticación insegura basada en host." ;;
    hostbasedauthentication) echo "Desactiva autenticación SSH basada solo en la identidad del host; puede afectar integraciones antiguas." ;;
    permituserenvironment) echo "Evita que usuarios inyecten variables de entorno al iniciar sesión; puede romper entornos SSH que dependan de ellas." ;;
    permitemptypasswords) echo "Impide contraseñas vacías en SSH." ;;
    permitrootlogin) echo "Bloquea el inicio SSH directo como root; confirma que exista una cuenta administrativa funcional y sudo antes de aplicarlo." ;;
    x11forwarding) echo "Deshabilita túneles gráficos X11 por SSH; aplicaciones GUI remotas dejarán de funcionar." ;;
    allowtcpforwarding) echo "Deshabilita túneles TCP/puertos SSH; puede romper port-forwarding, bastiones y accesos a servicios internos." ;;
    allowagentforwarding) echo "Deshabilita reenvío de SSH agent; puede afectar saltos SSH entre servidores." ;;
    maxauthtries) echo "Limita intentos de autenticación por conexión; valores bajos pueden afectar automatizaciones con varios métodos." ;;
    logingracetime) echo "Limita el tiempo para completar autenticación; clientes extremadamente lentos pueden no alcanzarlo." ;;
    clientaliveinterval) echo "Envía pruebas a sesiones inactivas; junto con ClientAliveCountMax puede cerrar conexiones desconectadas o inactivas." ;;
    clientalivecountmax) echo "Define cuántas pruebas SSH sin respuesta se toleran; valores bajos pueden cerrar conexiones en redes inestables." ;;
    loglevel) echo "Registra eventos de autenticación con detalle INFO; elevarlo aumenta el volumen de logs." ;;
    *) echo "Control de configuración SSH; revisar el valor efectivo antes de modificarlo." ;;
  esac
}
SSH_PENDING_DIRECTIVES=()

# Return codes: 0 = compliant; 1 = settings differ; 2 = cannot verify safely.
# Optional report mode prints pending values before the confirmation prompt or during audit.
ssh_report_unverifiable_settings() {
  local reason="$1" setting rest desired directive key
  SSH_PENDING_DIRECTIVES=()
  for setting in "${SSH_EXPECTED_SETTINGS[@]}"; do
    key="${setting%%|*}"
    rest="${setting#*|}"
    desired="${rest%%|*}"
    directive="${rest#*|}"
    SSH_PENDING_DIRECTIVES+=("$directive $desired")
    warn "SSH $directive: no se pudo verificar; objetivo='$desired'; motivo: $reason. Qué hace: $(ssh_setting_description "$key")."
  done
}

ssh_state_status() {
  local report="${1:-quiet}" output setting key desired directive actual status=0 rest reason
  SSH_PENDING_DIRECTIVES=()
  if [ ! -f /etc/ssh/sshd_config ]; then
    reason="sshd_config no existe"
  elif ! command -v sshd >/dev/null 2>&1; then
    reason="el binario sshd no está disponible"
  else
    reason=""
  fi
  if [ -n "$reason" ]; then
    case "$report" in
      audit) ssh_report_unverifiable_settings "$reason" ;;
      preflight) info "No se puede verificar SSH ($reason); se omite aplicación automática." ;;
      apply) info "No se puede verificar SSH ($reason); no se modificará." ;;
    esac
    return 2
  fi
  output="$(sshd -T 2>/dev/null)" || output=""
  if [ -z "$output" ]; then
    reason="sshd -T no pudo interpretar/devolver la configuración"
    case "$report" in
      audit) ssh_report_unverifiable_settings "$reason" ;;
      preflight) info "$reason; no se aplicará SSH automáticamente." ;;
      apply) info "$reason; no se modificará SSH." ;;
    esac
    return 2
  fi
  for setting in "${SSH_EXPECTED_SETTINGS[@]}"; do
    key="${setting%%|*}"
    rest="${setting#*|}"
    desired="${rest%%|*}"
    directive="${rest#*|}"
    actual="$(awk -v k="$key" '$1==k{$1="";sub(/^ /,"");print;exit}' <<< "$output")"
    if [ -z "$actual" ] || [ "$actual" != "$desired" ]; then
      status=1
      SSH_PENDING_DIRECTIVES+=("$directive $desired")
      case "$report" in
        preflight) info "SSH pendiente: $directive actual='${actual:-no definido}'; objetivo='$desired'. Qué hace: $(ssh_setting_description "$key")." ;;
        audit) warn "SSH pendiente: $directive actual='${actual:-no definido}'; objetivo='$desired'. Qué hace: $(ssh_setting_description "$key")." ;;
        apply) info "SSH pendiente: $directive actual='${actual:-no definido}'; objetivo='$desired'. Qué hace: $(ssh_setting_description "$key")." ;;
      esac
    elif [ "$report" = "audit" ] || [ "$report" = "apply" ]; then
      ok "SSH $directive=$actual. Qué hace: $(ssh_setting_description "$key")."
    fi
  done
  return "$status"
}

# Markers for the owned section inserted into sshd_config when no safe drop-in is available.
SSH_MANAGED_BEGIN="# BEGIN ORANGEBOX SSH HARDENING MANAGED BLOCK"
SSH_MANAGED_END="# END ORANGEBOX SSH HARDENING MANAGED BLOCK"

ssh_dropin_include_enabled() {
  [ "${OS_VERSION:-0}" -ge 8 ] || return 1
  [ -d /etc/ssh/sshd_config.d ] && [ -f /etc/ssh/sshd_config ] || return 1
  awk '
    /^[[:space:]]*#/ { next }
    tolower($1) == "match" { seen_match=1 }
    tolower($1) == "include" && $2 == "/etc/ssh/sshd_config.d/*.conf" && !seen_match { found=1 }
    END { exit(found ? 0 : 1) }
  ' /etc/ssh/sshd_config
}

# Prints a reason only when no safe application path is available.
ssh_module_apply_block_reason() {
  local main=/etc/ssh/sshd_config begin_count end_count
  [ -f "$main" ] || { echo "$main no existe"; return 0; }
  [ -r "$main" ] || { echo "$main no se puede leer"; return 0; }
  command -v sshd >/dev/null 2>&1 || { echo "el binario sshd no está disponible"; return 0; }
  sshd -t -f "$main" >/dev/null 2>&1 || { echo "sshd -t falla con la configuración actual; primero hay que corregir ese error"; return 0; }

  if ssh_dropin_include_enabled &&
     [ ! -e "$SSH_DROPIN" ] && [ ! -L "$SSH_DROPIN" ] &&
     [ -w /etc/ssh/sshd_config.d ]; then
    return 1
  fi
  [ ! -L "$main" ] || { echo "$main es un enlace simbólico y no se usará para insertar un bloque gestionado"; return 0; }
  [ -w "$main" ] && [ -w "$(dirname "$main")" ] || { echo "$main o su directorio no permiten una actualización atómica"; return 0; }
  begin_count="$(grep -Fc "$SSH_MANAGED_BEGIN" "$main" 2>/dev/null || true)"
  end_count="$(grep -Fc "$SSH_MANAGED_END" "$main" 2>/dev/null || true)"
  [ "$begin_count" -eq "$end_count" ] && [ "$begin_count" -le 1 ] ||
    { echo "los marcadores del bloque gestionado OrangeBox en $main están incompletos o duplicados"; return 0; }
  return 1
}

ssh_module_can_apply() {
  local reason
  reason="$(ssh_module_apply_block_reason || true)"
  [ -z "$reason" ]
}

ssh_print_manual_remediation() {
  local directive
  if [ "${#SSH_PENDING_DIRECTIVES[@]}" -eq 0 ]; then
    info "Revisión manual SSH: comprueba la causa indicada y valida con 'sshd -t' antes de recargar el servicio."
    return 0
  fi
  echo -e "$BLUE[INFO]$NC Remediación manual de los parámetros SSH pendientes:"
  echo "  1. Mantén abierta esta sesión SSH y crea un respaldo:"
  echo '     cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S)'
  echo "  2. Edita /etc/ssh/sshd_config con vi y coloca estas directivas en la sección global,"
  echo "     al inicio y antes del primer Include o Match. No las agregues simplemente al final:"
  for directive in "${SSH_PENDING_DIRECTIVES[@]}"; do printf '     %s\n' "$directive"; done
  echo "  3. Valida y recarga sin cerrar esta sesión:"
  echo "     sshd -t && (systemctl reload sshd || service sshd reload)"
  echo "  4. Prueba una segunda conexión antes de cerrar la sesión actual."
}

ssh_reload_service() {
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl reload sshd >/dev/null 2>&1 && return 0
  fi
  if command -v service >/dev/null 2>&1; then
    service sshd reload >/dev/null 2>&1 && return 0
  fi
  return 1
}

ssh_restore_failed_change() {
  local mode="$1" backup="${2:-}"
  case "$mode" in
    dropin) rm -f "$SSH_DROPIN" ;;
    main)
      [ -n "$backup" ] && [ -f "$backup" ] || return 1
      cp -a "$backup" /etc/ssh/sshd_config
      ;;
    *) return 1 ;;
  esac
}

ssh_apply_pending_settings() {
  local main=/etc/ssh/sshd_config tmp="" clean="" backup="" mode="" pending_count
  local begin_count end_count directive
  local -a directives=()
  directives=("${SSH_PENDING_DIRECTIVES[@]}")
  pending_count="${#directives[@]}"
  [ "$pending_count" -gt 0 ] || return 0

  if ssh_dropin_include_enabled &&
     [ ! -e "$SSH_DROPIN" ] && [ ! -L "$SSH_DROPIN" ] &&
     [ -w /etc/ssh/sshd_config.d ]; then
    mode=dropin
    tmp="$(mktemp "${SSH_DROPIN}.XXXXXX")" || { warn "No se pudo crear el drop-in SSH temporal"; return 1; }
    {
      printf '# OrangeBox Linux Hardening %s\n' "$SCRIPT_VERSION"
      for directive in "${directives[@]}"; do printf '%s\n' "$directive"; done
    } > "$tmp" || { rm -f "$tmp"; warn "No se pudo preparar el drop-in SSH"; return 1; }
    if ! chmod 600 "$tmp" || ! chown root:root "$tmp" 2>/dev/null; then
      rm -f "$tmp"
      warn "No se pudieron fijar propietario/permisos del drop-in SSH; no se instaló"
      return 1
    fi
    if [ -e "$SSH_DROPIN" ] || [ -L "$SSH_DROPIN" ] || ! mv "$tmp" "$SSH_DROPIN"; then
      rm -f "$tmp"
      warn "El drop-in SSH apareció o no pudo instalarse; no se sobrescribió ningún archivo existente"
      return 1
    fi
  else
    mode=main
    if [ -L "$main" ] || [ ! -w "$main" ] || [ ! -w "$(dirname "$main")" ]; then
      warn "No es seguro editar $main automáticamente; no se modificó SSH"
      SSH_PENDING_DIRECTIVES=("${directives[@]}")
      ssh_print_manual_remediation
      return 1
    fi
    begin_count="$(grep -Fc "$SSH_MANAGED_BEGIN" "$main" 2>/dev/null || true)"
    end_count="$(grep -Fc "$SSH_MANAGED_END" "$main" 2>/dev/null || true)"
    if [ "$begin_count" -ne "$end_count" ] || [ "$begin_count" -gt 1 ]; then
      warn "Los marcadores OrangeBox de $main están incompletos o duplicados; no se modificó SSH"
      SSH_PENDING_DIRECTIVES=("${directives[@]}")
      ssh_print_manual_remediation
      return 1
    fi

    backup_once "$main" || { warn "No se pudo respaldar $main; no se modificó SSH"; return 1; }
    backup="$BACKUP_DIR$main"
    [ -f "$backup" ] || { warn "No se verificó el backup de $main; no se modificó SSH"; return 1; }
    clean="$(mktemp)" || { warn "No se pudo crear temporal para filtrar el bloque SSH"; return 1; }
    if ! awk -v begin="$SSH_MANAGED_BEGIN" -v end="$SSH_MANAGED_END" '
      $0 == begin { if (inside || seen) { bad=1; exit }; inside=1; seen=1; next }
      $0 == end { if (!inside) { bad=1; exit }; inside=0; next }
      !inside { print }
      END { if (inside || bad) exit 1 }
    ' "$main" > "$clean"; then
      rm -f "$clean"
      warn "No se pudo interpretar el bloque gestionado existente; no se modificó SSH"
      return 1
    fi
    tmp="$(mktemp "${main}.XXXXXX")" || { rm -f "$clean"; warn "No se pudo crear temporal para $main"; return 1; }
    {
      printf '%s\n' "$SSH_MANAGED_BEGIN"
      for directive in "${directives[@]}"; do printf '%s\n' "$directive"; done
      printf '%s\n\n' "$SSH_MANAGED_END"
      cat "$clean"
    } > "$tmp" || {
      rm -f "$clean" "$tmp"
      warn "No se pudo preparar $main; no se modificó SSH"
      return 1
    }
    rm -f "$clean"
    chmod --reference="$main" "$tmp" 2>/dev/null || chmod 600 "$tmp"
    chown --reference="$main" "$tmp" 2>/dev/null || chown root:root "$tmp"
    if ! mv "$tmp" "$main"; then
      rm -f "$tmp"
      warn "No se pudo instalar el bloque gestionado en $main"
      return 1
    fi
  fi

  if ! sshd -t -f "$main" >/dev/null 2>&1 || ! ssh_state_status quiet; then
    if ! ssh_restore_failed_change "$mode" "$backup"; then
      warn "CRÍTICO: SSH no validó y no se pudo restaurar automáticamente el archivo anterior; revisar $main y el backup"
    else
      warn "La configuración SSH no validó los valores objetivo; se revirtió el cambio"
    fi
    SSH_PENDING_DIRECTIVES=("${directives[@]}")
    ssh_print_manual_remediation
    return 1
  fi
  if ! ssh_reload_service; then
    if ! ssh_restore_failed_change "$mode" "$backup"; then
      warn "CRÍTICO: no se pudo recargar sshd ni restaurar la configuración anterior; revisar manualmente"
    else
      ssh_reload_service >/dev/null 2>&1 || true
      warn "No se pudo recargar sshd; se revirtió el cambio para conservar el servicio en su estado anterior"
    fi
    SSH_PENDING_DIRECTIVES=("${directives[@]}")
    ssh_print_manual_remediation
    return 1
  fi
  if ssh_state_status quiet; then
    ssh_state_status apply || true
    FIXED=$((FIXED+pending_count))
    ok "SSH: $pending_count parámetro(s) corregido(s); sshd -t validó la configuración y el servicio fue recargado"
    return 0
  fi
  if ! ssh_restore_failed_change "$mode" "$backup"; then
    warn "CRÍTICO: los valores SSH siguen pendientes tras recargar y falló la restauración automática"
  else
    ssh_reload_service >/dev/null 2>&1 || true
    warn "Los valores SSH siguen pendientes tras recargar; se revirtió el cambio"
  fi
  SSH_PENDING_DIRECTIVES=("${directives[@]}")
  ssh_print_manual_remediation
  return 1
}

ssh_module() {
  local perms policy ssh_status reason
  section "SSH"
  if [ ! -f /etc/ssh/sshd_config ] || ! command -v sshd >/dev/null 2>&1; then
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
      ssh_state_status audit
    elif [ ! -f /etc/ssh/sshd_config ]; then
      warn "sshd_config no existe"
    else
      warn "sshd no disponible"
    fi
    return
  fi
  if [ "${PENDING_ONLY_AUDIT:-false}" != true ]; then
    perms=$(stat -c %a /etc/ssh/sshd_config 2>/dev/null||true)
    [ "$perms" = 600 ] || warn "sshd_config permisos=$perms; no se cambia automáticamente"
    if command -v update-crypto-policies >/dev/null 2>&1; then
      policy="$(update-crypto-policies --show 2>/dev/null || echo unknown)"
      case "$policy" in
        LEGACY*) warn "Crypto policy=$policy: revisar migración" ;;
        unknown) warn "No se pudo determinar crypto policy" ;;
        *) ok "Crypto policy=$policy" ;;
      esac
    else
      case "${OS_VERSION:-0}" in
        6|7) info "update-crypto-policies no aplica a CentOS/RHEL 6/7; se auditan los algoritmos efectivos de SSH." ;;
        *) warn "No se pudo determinar crypto policy" ;;
      esac
    fi
    [ -n "$(ssh_effective ciphers)" ] && ok "Ciphers efectivos auditados" || warn "No se pudieron leer ciphers efectivos"
    [ -n "$(ssh_effective kexalgorithms)" ] && ok "KEX efectivos auditados" || warn "No se pudieron leer KEX efectivos"
    [ -n "$(ssh_effective macs)" ] && ok "MACs efectivos auditados" || warn "No se pudieron leer MACs efectivos"
  fi

  # Never hide SSH in the compact baseline audit just because the preferred
  # drop-in path is unavailable: report every baseline directive as [OK]/[WARN].
  if $AUTO_FIX; then
    ssh_state_status apply
  else
    ssh_state_status audit
  fi
  ssh_status=$?

  if $AUTO_FIX; then
    case "$ssh_status" in
      0) ok "Los controles SSH ya cumplen los objetivos efectivos; no se modifica la configuración" ;;
      1) ssh_apply_pending_settings ;;
      2)
        reason="$(ssh_module_apply_block_reason || true)"
        warn "No se modificó SSH porque no se pudo verificar la configuración efectiva: ${reason:-motivo no identificado}"
        ssh_print_manual_remediation
        ;;
    esac
  elif [ "$ssh_status" -eq 1 ] && [ "${PENDING_ONLY_AUDIT:-false}" != true ]; then
    ssh_print_manual_remediation
  elif [ "$ssh_status" -eq 2 ] && [ "${PENDING_ONLY_AUDIT:-false}" != true ]; then
    reason="$(ssh_module_apply_block_reason || true)"
    info "Motivo por el que no puede aplicarse SSH automáticamente: ${reason:-no se pudo determinar}"
    ssh_print_manual_remediation
  fi
  info "No se fuerzan PasswordAuthentication, PubkeyAuthentication, PermitRootLogin, AllowUsers/AllowGroups, forwarding, GSSAPI/Kerberos ni algoritmos criptográficos sin inventario de clientes e integraciones."
}

cpanel_host_detected() {
  [ -d /usr/local/cpanel ] || [ -f /etc/cpanel/cpanel.config ] || command -v whmapi1 >/dev/null 2>&1
}

sudo_module() {
  section "SUDO"
  local sudoers_valid=false answer f=/etc/sudoers.d/99-orangebox-hardening
  if command -v visudo >/dev/null 2>&1; then
    if visudo -cf /etc/sudoers >/dev/null 2>&1; then
      ok "sudoers válido"
      sudoers_valid=true
    else
      bad "sudoers inválido; no se aplicarán cambios hasta corregir su sintaxis"
    fi
  else
    warn "visudo no disponible; no se puede validar sudoers ni aplicar use_pty con seguridad"
  fi
  if cpanel_host_detected; then
    if grep -RqsE '^[[:space:]]*Defaults[[:space:]]+use_pty([[:space:]]|$)' /etc/sudoers /etc/sudoers.d 2>/dev/null; then
      warn "cPanel detectado y use_pty ya está configurado; puede afectar funcionalidades/automatizaciones. No se modifica automáticamente."
    else
      na "cPanel detectado: por política OrangeBox no se activa use_pty; este control está excluido del baseline por compatibilidad."
    fi
    return
  fi
  if grep -RqsE '^[[:space:]]*Defaults[[:space:]]+use_pty([[:space:]]|$)' /etc/sudoers /etc/sudoers.d 2>/dev/null; then
    ok "use_pty habilitado"
    return
  fi
  if [ -e "$f" ] || [ -L "$f" ]; then
    warn "use_pty no configurado; $f ya existe y no se sobrescribe. Revisa el archivo manualmente antes de aplicar."
    return
  fi
  if [ ! -d /etc/sudoers.d ] || [ ! -w /etc/sudoers.d ]; then
    warn "use_pty no configurado y /etc/sudoers.d no existe/no es escribible; el baseline no puede crear el override de forma segura."
    return
  fi
  warn "use_pty no configurado; el cambio requiere confirmación y validación de sudoers"
  $AUTO_FIX || return
  if [ "$sudoers_valid" != true ]; then
    warn "No se aplicará use_pty mientras sudoers no pueda validarse."
    return
  fi
  if [ ! -r /dev/tty ]; then
    warn "No hay terminal interactiva para confirmar use_pty; no se modifica sudoers"
    return
  fi
  echo "Qué cambia: obliga a sudo a utilizar un pseudo-terminal; puede afectar automatizaciones que dependen de una sesión sin TTY."
  read -r -p "¿Deseas habilitar Defaults use_pty en este servidor? [s/N]: " answer </dev/tty
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) ;;
    *) info "use_pty rechazado/no confirmado; se conserva la configuración actual"; return ;;
  esac
  printf '%s\n' 'Defaults use_pty' > "$f" || { warn "No se pudo preparar $f"; return; }
  chmod 440 "$f" && chown root:root "$f" || { rm -f "$f"; warn "No se pudieron fijar los permisos de $f"; return; }
  if visudo -cf /etc/sudoers >/dev/null 2>&1; then
    ok "use_pty habilitado y sudoers validado"
    FIXED=$((FIXED+1))
  else
    rm -f "$f"
    bad "sudoers no validó; se retiró el drop-in recién creado"
  fi
}

password_module() {
  echo -e "\n$BLUE### PASSWORD / PAM ###$NC"
  [ -f /etc/login.defs ] || return
  local max
  max=$(awk '$1=="PASS_MAX_DAYS"{v=$2}END{print v}' /etc/login.defs)
  info "PASS_MAX_DAYS=${max:-no definido}; se conserva sin cambios por política operacional para evitar expiraciones que puedan bloquear accesos."
  if command -v authselect >/dev/null 2>&1 && authselect current >/dev/null 2>&1; then
    ok "authselect operativo; PAM no se edita a ciegas"
  elif [ "${OS_VERSION:-0}" = 6 ] || [ "${OS_VERSION:-0}" = 7 ]; then
    info "authselect no aplica al stack PAM legacy de CentOS/RHEL 6/7; no se modifican reglas PAM automáticamente"
  else
    warn "PAM requiere revisión; no se insertan reglas automáticamente"
  fi
  if [ "${OS_VERSION:-0}" = 6 ]; then
    grep -Rqs 'pam_tally2.so' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null &&
      ok "pam_tally2 presente (mecanismo legacy de bloqueo)" ||
      warn "pam_tally2 no presente; revisar bloqueo de intentos fallidos en PAM legacy"
  else
    grep -Rqs 'pam_faillock.so' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null &&
      ok "pam_faillock presente" ||
      warn "pam_faillock no presente; se deja en auditoría"
  fi
  getent group wheel >/dev/null 2>&1 && ok "wheel existe" || warn "wheel no existe"
}
confirm_baseline_parameter() {
  local prompt="$1" answer=""
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    warn "No hay terminal interactiva; se omite el cambio: $prompt"
    return 1
  fi
  printf '%s [s/N]: ' "$prompt" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) info "Cambio rechazado; se conserva la configuración actual."; return 1 ;;
  esac
}

package_global_gpgcheck() {
  local file="$1"
  [ -r "$file" ] || return 0
  awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[ \t]*[#;]/ { next }
    /^[ \t]*\[/ { section=tolower(trim($0)); next }
    section == "[main]" {
      line=$0; eq=index(line, "="); if (!eq) next
      key=tolower(trim(substr(line,1,eq-1)))
      if (key != "gpgcheck") next
      value=trim(substr(line,eq+1)); sub(/[ \t]*[#;].*$/, "", value); gsub(/[ \t]/, "", value)
      result=tolower(value)
    }
    END { if (result != "") print result }
  ' "$file" 2>/dev/null
}

package_repo_gpgcheck_issues() {
  local file
  for file in /etc/yum.repos.d/*.repo /etc/dnf/repos.d/*.repo; do
    [ -f "$file" ] || continue
    awk -v path="$file" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      function flush() { if (section != "" && section != "main" && enabled != "0" && gpgcheck == "0") printf "%s|%s\n", path, section }
      /^[ \t]*[#;]/ { next }
      /^[ \t]*\[/ {
        flush()
        section=tolower(trim($0)); sub(/^\[/, "", section); sub(/\]$/, "", section)
        enabled="1"; gpgcheck=""
        next
      }
      {
        line=$0; eq=index(line, "="); if (!eq || section == "") next
        key=tolower(trim(substr(line,1,eq-1)))
        value=trim(substr(line,eq+1)); sub(/[ \t]*[#;].*$/, "", value); gsub(/[ \t]/, "", value); value=tolower(value)
        if (key == "enabled") enabled=value
        else if (key == "gpgcheck") gpgcheck=value
      }
      END { flush() }
    ' "$file" 2>/dev/null
  done
}

package_set_global_gpgcheck() {
  local file="$1" tmp mode
  [ ! -L "$file" ] || { warn "$file es un enlace simbólico; no se modifica automáticamente."; return 1; }
  backup_once "$file" || return 1
  tmp="$(mktemp "$file.orangebox.XXXXXX")" || return 1
  if [ -f "$file" ]; then
    awk '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      function ensure_value() { if (section == "[main]" && !written) { print "gpgcheck=1"; written=1 } }
      /^[ \t]*\[/ {
        ensure_value()
        section=tolower(trim($0))
        if (section == "[main]") { main_seen=1; written=0 }
        print
        next
      }
      section == "[main]" && $0 !~ /^[ \t]*[#;]/ {
        line=$0; eq=index(line, "=")
        if (eq) {
          key=tolower(trim(substr(line,1,eq-1)))
          if (key == "gpgcheck") {
            if (!written) { print "gpgcheck=1"; written=1 }
            next
          }
        }
      }
      { print }
      END {
        ensure_value()
        if (!main_seen) { print "[main]"; print "gpgcheck=1" }
      }
    ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    mode="$(stat -c "%a" "$file" 2>/dev/null || echo 644)"
    chmod "$mode" "$tmp" || { rm -f "$tmp"; return 1; }
    chown --reference="$file" "$tmp" 2>/dev/null || chown root:root "$tmp" 2>/dev/null || true
  else
    printf '[main]\ngpgcheck=1\n' > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp" && chown root:root "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  fi
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  [ "$(package_global_gpgcheck "$file")" = "1" ]
}

package_set_repo_gpgcheck() {
  local file="$1" target="$2" tmp mode
  [ -f "$file" ] && [ ! -L "$file" ] || { warn "No se puede modificar $file de forma segura."; return 1; }
  backup_once "$file" || return 1
  tmp="$(mktemp "$file.orangebox.XXXXXX")" || return 1
  awk -v target="$target" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[ \t]*\[/ {
      section=tolower(trim($0)); sub(/^\[/, "", section); sub(/\]$/, "", section)
      print
      next
    }
    section == target && $0 !~ /^[ \t]*[#;]/ {
      line=$0; eq=index(line, "=")
      if (eq) {
        key=tolower(trim(substr(line,1,eq-1)))
        value=trim(substr(line,eq+1)); sub(/[ \t]*[#;].*$/, "", value); gsub(/[ \t]/, "", value)
        if (key == "gpgcheck" && tolower(value) == "0") {
          if (!changed) { sub(/=[ \t]*[^#;]*/, "=1", line); print line; changed=1; next }
          next
        }
      }
    }
    { print }
    END { if (!changed) exit 1 }
  ' "$file" > "$tmp" || { rm -f "$tmp"; warn "No se encontró una directiva gpgcheck=0 modificable en [$target] ($file)."; return 1; }
  mode="$(stat -c "%a" "$file" 2>/dev/null || echo 644)"
  chmod "$mode" "$tmp" || { rm -f "$tmp"; return 1; }
  chown --reference="$file" "$tmp" 2>/dev/null || chown root:root "$tmp" 2>/dev/null || true
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  return 0
}

package_repo_module() {
  section "PACKAGE REPOSITORY SIGNATURE VERIFICATION"
  local conf="" global="" issues="" file repo total_files=0
  if command -v dnf >/dev/null 2>&1; then conf=/etc/dnf/dnf.conf; else conf=/etc/yum.conf; fi
  global="$(package_global_gpgcheck "$conf")"
  issues="$(package_repo_gpgcheck_issues)"
  for file in /etc/yum.repos.d/*.repo /etc/dnf/repos.d/*.repo; do [ -f "$file" ] && total_files=$((total_files+1)); done

  if [ "$global" = "1" ]; then
    ok "gpgcheck=1 explícito en [main] de $conf"
  else
    warn "gpgcheck global en [main] de $conf no es 1 (actual: $global)."
    info "Qué hace: verifica la firma GPG antes de instalar paquetes. Riesgo: actualizaciones pueden fallar si faltan firmas o la clave GPG legítima del proveedor."
    if [ "$AUTO_FIX" = true ] && confirm_baseline_parameter "¿Activar gpgcheck=1 en $conf?"; then
      if package_set_global_gpgcheck "$conf"; then FIXED=$((FIXED + 1)); ok "gpgcheck global=1 aplicado y verificado."; else warn "No se pudo validar gpgcheck global."; fi
    fi
  fi

  if [ -n "$issues" ]; then
    while IFS='|' read -r file repo; do
      [ -n "$file" ] || continue
      warn "Repositorio [$repo] en $file tiene gpgcheck=0 mientras está habilitado."
      info "Qué hace: verifica la firma del paquete de ese repositorio. Riesgo: sus paquetes pueden dejar de instalarse si faltan firmas o su clave legítima."
      if [ "$AUTO_FIX" = true ] && confirm_baseline_parameter "¿Activar gpgcheck=1 para [$repo] en $file?"; then
        if package_set_repo_gpgcheck "$file" "$repo"; then FIXED=$((FIXED + 1)); ok "gpgcheck=1 aplicado a [$repo]."; else warn "No se pudo validar el cambio para [$repo]."; fi
      fi
    done <<< "$issues"
  fi

  global="$(package_global_gpgcheck "$conf")"
  issues="$(package_repo_gpgcheck_issues)"
  if [ "$total_files" -eq 0 ]; then
    warn "No se encontraron archivos de repositorio; el inventario de excepciones es incompleto."
  elif [ "$global" = "1" ] && [ -z "$issues" ]; then
    ok "gpgcheck global y overrides de repositorios habilitados cumplen."
  else
    warn "La política GPG sigue pendiente; revise los mensajes anteriores."
  fi
}

crypto_policies_module() {
  section "SYSTEM-WIDE CRYPTOGRAPHIC POLICY"
  local current="" verified=""
  if [[ "$OS_VERSION" =~ ^[0-9]+$ ]] && [ "$OS_VERSION" -lt 8 ]; then
    na "update-crypto-policies no aplica a RHEL/CentOS 6/7."
    return 0
  fi
  if ! command -v update-crypto-policies >/dev/null 2>&1; then
    na "update-crypto-policies no está disponible; no se pudo consultar una política criptográfica global."
    return 0
  fi
  current="$(update-crypto-policies --show 2>/dev/null || true)"
  if [ -z "$current" ]; then
    warn "No se pudo determinar la política criptográfica global; no se modifica."
    return 0
  fi
  case "$current" in
    DEFAULT|DEFAULT:*)
      ok "Política criptográfica global=$current."
      info "DEFAULT controla los algoritmos base permitidos por servicios compatibles."
      return 0
      ;;
    FIPS|FIPS:*|FUTURE|FUTURE:*)
      ok "Política criptográfica global=$current; el baseline no la debilita."
      return 0
      ;;
    LEGACY|LEGACY:*)
      warn "Política LEGACY activa: permite algoritmos criptográficos antiguos."
      ;;
    *)
      warn "Política personalizada/no reconocida ($current); se conserva sin cambios."
      return 0
      ;;
  esac
  info "Qué hace DEFAULT: restringe algoritmos criptográficos antiguos. Cambiar de LEGACY puede cortar conexiones con clientes TLS/SSH, LDAP, Kerberos y aplicaciones legacy."
  if [ "$AUTO_FIX" != true ]; then return 0; fi
  if ! confirm_baseline_parameter "¿Cambiar la política criptográfica global de $current a DEFAULT?"; then return 0; fi
  if [ -f /etc/crypto-policies/config ]; then
    backup_once /etc/crypto-policies/config || { warn "No se pudo respaldar /etc/crypto-policies/config; no se cambia."; return 1; }
  fi
  if update-crypto-policies --set DEFAULT; then
    verified="$(update-crypto-policies --show 2>/dev/null || true)"
    if [ "$verified" = "DEFAULT" ]; then
      FIXED=$((FIXED + 1))
      ok "Política criptográfica DEFAULT aplicada y verificada."
      info "Valide SSH/TLS/Kerberos y reinicie los servicios que necesiten recargar la política durante una ventana autorizada."
    else
      warn "No se pudo verificar DEFAULT después del cambio; estado actual=$verified."
    fi
  else
    warn "update-crypto-policies --set DEFAULT falló."
  fi
}

kernel_module(){
  section "KERNEL / SYSCTL"
  local forwarding rp_filter ipv6_forward
  if [ "${PENDING_ONLY_AUDIT:-false}" = true ] && ! sysctl_baseline_target_writable; then
    echo -e "$BLUE[INFO]$NC El destino persistente sysctl está enlazado/no gestionado por OrangeBox; se auditan igualmente todos los valores y no se sobrescribe ese archivo."
  fi
  # CIS RHEL 9 v3.0.0 recommendation 3.3.1 covers IPv4 and IPv6 forwarding;
  # exact cross-version/profile mapping is tracked in CIS-COVERAGE-MAP.md.
  # Routing/NAT/VPN/container gateways are legitimate exceptions, so sysctl-safe
  # explains the effect and requires individual [s/N] consent before any change.
  set_sysctl net.ipv4.ip_forward 0
  forwarding=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)
  rp_filter=1
  if [ "$forwarding" = 1 ]; then
    rp_filter=2
    ok "IP forwarding=1: se usa rp_filter=2 (modo loose) para preservar el enrutamiento"
  fi
  set_sysctl fs.suid_dumpable 0
  set_sysctl kernel.dmesg_restrict 1
  set_kptr_restrict_policy
  set_sysctl kernel.randomize_va_space 2
  set_sysctl kernel.yama.ptrace_scope 1
  set_sysctl vm.mmap_min_addr 65536
  set_sysctl kernel.unprivileged_bpf_disabled 1
  set_sysctl user.max_user_namespaces 0
  set_sysctl fs.protected_fifos 2
  set_sysctl fs.protected_regular 2
  set_sysctl fs.protected_hardlinks 1
  set_sysctl fs.protected_symlinks 1
  set_sysctl net.ipv4.conf.all.accept_redirects 0
  set_sysctl net.ipv4.conf.default.accept_redirects 0
  set_sysctl net.ipv6.conf.all.accept_redirects 0
  set_sysctl net.ipv6.conf.default.accept_redirects 0
  set_sysctl net.ipv4.conf.all.send_redirects 0
  set_sysctl net.ipv4.conf.default.send_redirects 0
  set_sysctl net.ipv4.conf.all.accept_source_route 0
  set_sysctl net.ipv4.conf.default.accept_source_route 0
  set_sysctl net.ipv4.conf.all.secure_redirects 0
  set_sysctl net.ipv4.conf.default.secure_redirects 0
  set_sysctl net.ipv4.conf.all.log_martians 1
  set_sysctl net.ipv4.conf.default.log_martians 1
  set_sysctl net.ipv4.icmp_echo_ignore_broadcasts 1
  set_sysctl net.ipv4.icmp_ignore_bogus_error_responses 1
  set_sysctl net.ipv4.conf.all.rp_filter "$rp_filter"
  set_sysctl net.ipv4.conf.default.rp_filter "$rp_filter"

  if [ -d /proc/sys/net/ipv6 ]; then
    # IPv6 forwarding is also a routing role setting; never switch it without consent.
    set_sysctl net.ipv6.conf.all.forwarding 0
    set_sysctl net.ipv6.conf.all.accept_source_route 0
    set_sysctl net.ipv6.conf.default.accept_source_route 0
    ipv6_forward=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo 0)
    if [ "$ipv6_forward" = 1 ]; then
      if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
        sysctl_safe_log "N/A" "net.ipv6.conf.all.accept_ra se conserva porque IPv6 forwarding está activo; cambiarlo puede afectar rutas del uplink."
        sysctl_safe_log "N/A" "net.ipv6.conf.default.accept_ra se conserva porque IPv6 forwarding está activo; cambiarlo puede afectar rutas del uplink."
      else
        warn "IPv6 forwarding está activo: se preserva accept_ra para no cortar el descubrimiento de rutas del uplink"
      fi
    else
      set_sysctl net.ipv6.conf.all.accept_ra 0
      set_sysctl net.ipv6.conf.default.accept_ra 0
    fi
  elif [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    sysctl_safe_log "N/A" "net.ipv6.conf.all.accept_source_route: este kernel no expone /proc/sys/net/ipv6."
    sysctl_safe_log "N/A" "net.ipv6.conf.default.accept_source_route: este kernel no expone /proc/sys/net/ipv6."
    sysctl_safe_log "N/A" "net.ipv6.conf.all.accept_ra: este kernel no expone /proc/sys/net/ipv6."
    sysctl_safe_log "N/A" "net.ipv6.conf.default.accept_ra: este kernel no expone /proc/sys/net/ipv6."
  fi
}

filesystem_module(){
  echo -e "\n$BLUE### FILESYSTEM ###$NC"
  local f p
  for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    [ -f "$f" ] || continue
    p=$(stat -c %a "$f" 2>/dev/null || true)
    case "$f" in
      /etc/passwd|/etc/group)
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -le 644 ]; then
          ok "$f=$p"
        else
          warn "$f=$p"
        fi
        ;;
      *)
        # GNU stat prints mode 000 as "0", not "000".
        if [ "$p" = 600 ] || [ "$p" = 640 ] || [ "$p" = 0 ] || [ "$p" = 000 ]; then
          ok "$f=$p"
        else
          warn "$f=$p; no se fuerza"
        fi
        ;;
    esac
  done
}
auditd_is_active() {
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active auditd >/dev/null 2>&1; then
    return 0
  fi
  if command -v service >/dev/null 2>&1 && service auditd status >/dev/null 2>&1; then
    return 0
  fi
  if command -v pgrep >/dev/null 2>&1 && pgrep -x auditd >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
auditd_module(){
  echo -e "\n$BLUE### AUDITD ###$NC"
  if auditd_is_active; then
    if command -v auditctl >/dev/null 2>&1; then
      ok "auditd activo"
    else
      warn "auditd parece activo, pero auditctl no está disponible"
    fi
  else
    warn "auditd ausente/inactivo"
  fi
  [ -d /etc/audit/rules.d ] && ok "rules.d disponible" || info "rules.d no existe; esta versión puede usar /etc/audit/audit.rules"
}
rsyslog_legacy_is_active() {
  if command -v service >/dev/null 2>&1 && service rsyslog status >/dev/null 2>&1; then
    return 0
  fi
  if command -v pgrep >/dev/null 2>&1 && pgrep -x rsyslogd >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

audit_logging_stack_selection() {
  local journal_active=false rsyslog_active=false
  if [ "${OS_VERSION:-0}" = 6 ] || ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi
  if [ "${OS_VERSION:-0}" -lt 9 ] 2>/dev/null; then
    info "No se evalúa exclusividad journald/rsyslog para esta generación en el baseline genérico."
    return 0
  fi

  systemctl is-active --quiet systemd-journald 2>/dev/null && journal_active=true
  systemctl is-active --quiet rsyslog 2>/dev/null && rsyslog_active=true

  if [ "$journal_active" = true ] && [ "$rsyslog_active" = true ]; then
    warn "systemd-journald y rsyslog están activos simultáneamente. Los perfiles CIS RHEL 9/10 separan las rutas journald/rsyslog; el uso dual debe ser una decisión consciente/tailoring."
    echo "Qué hace/riesgo: deshabilitar cualquiera puede cortar persistencia, forwarding remoto, ingestión de Wazuh o procesos que leen logs. No se detiene ni deshabilita ningún servicio desde esta auditoría."
  elif [ "$journal_active" = true ]; then
    ok "Stack de logging activo: systemd-journald; rsyslog no está activo."
  elif [ "$rsyslog_active" = true ]; then
    info "Stack de logging activo: rsyslog sin systemd-journald; validar que coincide con el perfil operativo/CIS seleccionado."
  else
    warn "No se verificó un stack journald/rsyslog activo; no se habilita ni instala ningún servicio automáticamente."
  fi
}

rsyslog_module(){
  local conf=/etc/systemd/journald.conf
  section "JOURNAL / SYSLOG"
  audit_logging_stack_selection
  if [ "${OS_VERSION:-}" = 6 ]; then
    na "journald no aplica a CentOS/RHEL 6; Storage=persistent está excluido porque se usa el stack legacy."
    na "/var/log/journal como persistencia de journald no aplica a CentOS/RHEL 6."
    if rsyslog_legacy_is_active; then
      ok "rsyslog activo en el stack legacy"
    else
      warn "rsyslog ausente/inactivo en CentOS/RHEL 6; este baseline no instala ni habilita servicios legacy"
    fi
    return
  fi
  if [ "$AUTO_FIX" != true ]; then
    if [ ! -f "$conf" ]; then
      warn "$conf no existe; No se puede confirmar Storage=persistent y el baseline no crea ese archivo automáticamente."
    elif grep -Eq '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent([[:space:]]*(#.*)?)?$' "$conf"; then
      ok "journald Storage=persistent configurado explícitamente"
    else
      warn "journald Storage no está configurado explícitamente como persistent en $conf"
    fi
    if [ -d /var/log/journal ]; then
      ok "/var/log/journal existe para persistencia de logs"
    else
      warn "/var/log/journal no existe; debe crearse para conservar logs entre reinicios"
    fi
    return
  fi
  if [ ! -f "$conf" ]; then
    warn "$conf no existe; no se modifica journald automáticamente"
    return
  fi
  if [ -d /var/log/journal ] && grep -Eq '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent([[:space:]]*(#.*)?)?$' "$conf"; then
    ok "journald Storage=persistent configurado explícitamente"
    ok "/var/log/journal existe para persistencia de logs"
    return
  fi
  backup_once "$conf"
  if grep -Eq '^[[:space:]]*Storage[[:space:]]*=' "$conf"; then
    if ! sed -ri 's/^[[:space:]]*Storage[[:space:]]*=.*/Storage=persistent/' "$conf"; then
      warn "No se pudo configurar Storage=persistent en $conf"
      return
    fi
  else
    printf '\nStorage=persistent\n' >> "$conf" || { warn "No se pudo añadir Storage=persistent a $conf"; return; }
  fi
  if ! mkdir -p /var/log/journal; then warn "No se pudo crear /var/log/journal"; return; fi
  if command -v systemd-tmpfiles >/dev/null 2>&1; then
    systemd-tmpfiles --create --prefix=/var/log/journal >/dev/null 2>&1 || warn "systemd-tmpfiles no pudo normalizar /var/log/journal"
  fi
  if ! systemctl restart systemd-journald >/dev/null 2>&1; then
    warn "journald no reinició; revisar $conf y el estado del servicio"
    return
  fi
  if [ -d /var/log/journal ] && grep -Eq '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent([[:space:]]*(#.*)?)?$' "$conf" && systemctl is-active --quiet systemd-journald; then
    ok "journald Storage=persistent configurado y verificado"
    ok "/var/log/journal existe para persistencia de logs"
    FIXED=$((FIXED+1))
  else
    warn "No se pudo verificar la persistencia de journald después del cambio"
  fi
}

rsyslog_state_status() {
  local conf=/etc/systemd/journald.conf
  if [ "${OS_VERSION:-}" = 6 ]; then
    rsyslog_legacy_is_active && return 0
    return 1
  fi
  [ -f "$conf" ] || return 2
  if [ -d /var/log/journal ] &&
     grep -Eq '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent([[:space:]]*(#.*)?)?$' "$conf"; then
    return 0
  fi
  return 1
}

selinux_module(){ echo -e "\n$BLUE### SELINUX ###$NC"; command -v getenforce >/dev/null 2>&1||{ warn "SELinux no disponible"; return; }; local mode; mode=$(getenforce); [ "$mode" = Enforcing ]&&ok "SELinux Enforcing"||warn "SELinux=$mode; NO se modifica por política OrangeBox"; }
cron_module(){ echo -e "\n$BLUE### CRON / AT ###$NC"; [ -e /etc/cron.allow ]&&ok "cron.allow existe"||warn "cron.allow no existe; se deja intacto para no romper cPanel"; [ -e /etc/at.allow ]&&ok "at.allow existe"||warn "at.allow no existe; se deja intacto"; }
usb_module(){ echo -e "\n$BLUE### USB ###$NC"; lsmod 2>/dev/null|grep -q '^usb_storage'&&warn "usb_storage cargado"||ok "usb_storage no cargado"; info "USB no se bloquea automáticamente; requiere decisión explícita de política"; }
services_module(){ echo -e "\n$BLUE### LEGACY SERVICES ###$NC"; for s in telnet.socket xinetd tftp.socket rsh.socket rlogin.socket rexec.socket; do systemctl list-unit-files "$s" 2>/dev/null|grep -q "$s"&&warn "Servicio legacy presente: $s"; done; for p in telnet-server xinetd rsh-server tftp-server; do rpm -q "$p" >/dev/null 2>&1&&warn "Paquete legacy instalado: $p"; done; info "No se eliminan servicios automáticamente; revisar los servicios legacy detectados si los hubiera"; }
configure_ssh_banner() {
  local main=/etc/ssh/sshd_config current tmp backup reload_ok=0
  section "SSH LOGIN BANNER"
  [ -f "$main" ] || { warn "$main no existe; no se puede auditar ni configurar el banner SSH"; return; }
  command -v sshd >/dev/null 2>&1 || { warn "sshd no disponible; no se puede validar ni configurar el banner SSH"; return; }
  if ! sshd -t -f "$main" >/dev/null 2>&1; then
    warn "sshd -t falla para $main; no se puede verificar ni cambiar el banner hasta corregir la sintaxis."
    return
  fi
  current="$(sshd -T -f "$main" 2>/dev/null | awk '$1=="banner"{print $2; exit}')"
  if [ -z "$current" ]; then
    warn "sshd -T no devolvió el valor efectivo de Banner; no se puede confirmar /etc/issue.net."
    return
  fi
  if [ "$current" = "/etc/issue.net" ]; then
    ok "Banner SSH efectivo apunta a /etc/issue.net"
    return
  fi
  if ! $AUTO_FIX; then
    warn "Banner SSH efectivo=${current:-no verificable}; recomendado /etc/issue.net"
    return
  fi

  backup_once "$main"
  backup="$BACKUP_DIR$main"
  tmp="$(mktemp)" || { warn "No se pudo crear temporal para sshd_config"; return; }

  # OpenSSH suele procesar Include al inicio. El primer valor efectivo gana;
  # por eso Banner debe ir antes del primer Include y antes de cualquier Match.
  # Se eliminan Banner previos del archivo principal para evitar valores
  # posteriores o específicos de Match que contradigan el banner corporativo.
  awk '
    BEGIN { done=0 }
    {
      keyword=tolower($1)
      if (keyword == "banner") next
      if (keyword == "include" && !done) {
        print "Banner /etc/issue.net"
        done=1
      }
      if (keyword == "match" && !done) {
        print "Banner /etc/issue.net"
        done=1
      }
      print
    }
    END { if (!done) print "Banner /etc/issue.net" }
  ' "$main" > "$tmp" || { rm -f "$tmp"; warn "No se pudo preparar sshd_config"; return; }
  chmod --reference="$main" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  chown --reference="$main" "$tmp" 2>/dev/null || chown root:root "$tmp"
  mv "$tmp" "$main" || { rm -f "$tmp"; warn "No se pudo instalar sshd_config"; return; }

  current="$(sshd -T -f "$main" 2>/dev/null | awk '$1=="banner"{print $2; exit}')"
  if sshd -t -f "$main" >/dev/null 2>&1 && [ "$current" = "/etc/issue.net" ]; then
    if command -v systemctl >/dev/null 2>&1 && systemctl reload sshd >/dev/null 2>&1; then
      reload_ok=1
    elif command -v service >/dev/null 2>&1 && service sshd reload >/dev/null 2>&1; then
      reload_ok=1
    fi
    if [ "$reload_ok" -eq 1 ]; then
      ok "Banner SSH aplicado, validado y sshd recargado sin cortar sesiones"
      FIXED=$((FIXED+1))
    else
      warn "Banner SSH configurado y validado; no se pudo recargar sshd, revisar servicio"
    fi
  else
    if [ -f "$backup" ]; then cp -a "$backup" "$main"; fi
    bad "La configuración SSH no validó el banner; se restauró sshd_config desde el backup"
  fi
}

banners_audit_unverifiable() {
  local reason="$1" target
  for target in /etc/motd /etc/profile.d/99-orangebox-motd.sh /etc/issue /etc/issue.net; do
    warn "$target: no se pudo verificar contenido/permisos porque $reason"
  done
}

banners_module() {
  section "BANNERS / MOTD"
  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then configure_ssh_banner; fi
  local login_tmp motd_tmp session_motd_tmp target content_tmp mode owner group

  if ! login_tmp="$(mktemp)"; then
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then banners_audit_unverifiable "falló mktemp"; else warn "No se pudo crear el banner previo al login"; fi
    return
  fi
  if ! motd_tmp="$(mktemp)"; then
    rm -f "$login_tmp"
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then banners_audit_unverifiable "falló mktemp"; else warn "No se pudo crear el MOTD"; fi
    return
  fi
  if ! session_motd_tmp="$(mktemp)"; then
    rm -f "$login_tmp" "$motd_tmp"
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then banners_audit_unverifiable "falló mktemp"; else warn "No se pudo crear el MOTD dinámico"; fi
    return
  fi

  # FIGlet sólo se necesita en el banner previo a la autenticación.
  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    orangebox_motd_ensure_figlet false >/dev/null 2>&1 || true
  else
    orangebox_motd_ensure_figlet "$AUTO_FIX" || true
  fi
  if ! orangebox_motd_write_login_banner "$login_tmp"; then
    rm -f "$login_tmp" "$motd_tmp" "$session_motd_tmp"
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then banners_audit_unverifiable "no se pudo generar el banner de login"; else warn "No se pudo generar el banner previo al login"; fi
    return
  fi

  # La IP remota cambia por sesión: un /etc/motd estático no puede conocerla.
  # El banner posterior al login se genera desde /etc/profile.d en shells interactivas.
  : > "$motd_tmp"
  if ! orangebox_motd_write_profile "$session_motd_tmp"; then
    rm -f "$login_tmp" "$motd_tmp" "$session_motd_tmp"
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then banners_audit_unverifiable "no se pudo generar el MOTD dinámico"; else warn "No se pudo generar el MOTD dinámico"; fi
    return
  fi

  for target in /etc/motd /etc/profile.d/99-orangebox-motd.sh /etc/issue /etc/issue.net; do
    case "$target" in
      /etc/motd) content_tmp="$motd_tmp" ;;
      /etc/profile.d/99-orangebox-motd.sh) content_tmp="$session_motd_tmp" ;;
      *) content_tmp="$login_tmp" ;;
    esac

    mode="$(stat -c '%a' "$target" 2>/dev/null || true)"
    owner="$(stat -c '%U' "$target" 2>/dev/null || true)"
    group="$(stat -c '%G' "$target" 2>/dev/null || true)"
    if [ -f "$target" ] && cmp -s "$content_tmp" "$target" && [ "$mode" = 644 ] && [ "$owner" = root ] && [ "$group" = root ]; then
      ok "$target ya contiene el mensaje OrangeBox correcto"
      continue
    fi
    if $AUTO_FIX; then
      [ ! -e "$target" ] || backup_once "$target"
      if install -o root -g root -m 644 "$content_tmp" "$target"; then
        if [ -f "$target" ] && cmp -s "$content_tmp" "$target" && [ "$(stat -c '%a' "$target" 2>/dev/null)" = 644 ] && [ "$(stat -c '%U' "$target" 2>/dev/null)" = root ] && [ "$(stat -c '%G' "$target" 2>/dev/null)" = root ]; then
          ok "$target actualizado (root:root 0644)"
          FIXED=$((FIXED+1))
        else
          warn "No se pudo verificar completamente $target"
        fi
      else
        warn "No se pudo escribir $target"
      fi
    else
      warn "$target requiere actualizar el contenido o los permisos"
    fi
  done

  rm -f "$login_tmp" "$motd_tmp" "$session_motd_tmp"
  if [ "${PENDING_ONLY_AUDIT:-false}" != true ]; then configure_ssh_banner; fi
}
time_module(){
  echo -e "\n$BLUE### TIME SYNC ###$NC"
  if command -v chronyc >/dev/null 2>&1; then
    if chronyc tracking >/dev/null 2>&1; then
      ok "chrony operativo"
    else
      warn "chronyc existe, pero no se pudo verificar la sincronización"
    fi
    return
  fi

  if command -v ntpq >/dev/null 2>&1; then
    if ntpq -pn 2>/dev/null | awk 'NR > 2 && $1 ~ /^\*/ {found=1} END {exit(found ? 0 : 1)}'; then
      ok "ntpd sincronizado; ntpq identifica un peer de sistema (*)"
    elif { command -v service >/dev/null 2>&1 && service ntpd status >/dev/null 2>&1; } ||
         { command -v pgrep >/dev/null 2>&1 && pgrep -x ntpd >/dev/null 2>&1; }; then
      warn "ntpd activo, pero ntpq no confirma un peer sincronizado"
    else
      warn "ntpd/chrony ausente o sincronización no verificada"
    fi
    return
  fi

  if { command -v service >/dev/null 2>&1 && service ntpd status >/dev/null 2>&1; } ||
     { command -v pgrep >/dev/null 2>&1 && pgrep -x ntpd >/dev/null 2>&1; }; then
    info "ntpd está activo, pero ntpq no está disponible; sincronización no confirmada"
  else
    warn "NTP/chrony no verificado"
  fi
}
grub_module(){
  echo -e "\n$BLUE### GRUB ###$NC"
  if [ "${OS_VERSION:-0}" = 6 ]; then
    if [ -e /boot/grub/grub.conf ] || [ -e /etc/grub.conf ]; then
      ok "GRUB legacy grub.conf localizado"
    else
      warn "GRUB legacy: no se encontró /boot/grub/grub.conf ni /etc/grub.conf"
    fi
  elif find /boot /etc -maxdepth 5 \( -type f -o -type l \) -name grub.cfg 2>/dev/null | grep -q .; then
    ok "grub.cfg localizado"
  else
    warn "grub.cfg no localizado"
  fi
  info "GRUB no se modifica automáticamente; los parámetros de arranque requieren revisión específica"
}
aide_audit_module() {
  section "AIDE / INTEGRIDAD (OPCIONAL)"
  local root_crontab
  if ! command -v rpm >/dev/null 2>&1; then
    warn "rpm no está disponible; no se puede comprobar si AIDE está instalado"
    na "Base de referencia AIDE: no verificable porque rpm no está disponible."
    na "Verificación periódica AIDE: no verificable porque rpm no está disponible."
    return
  fi
  if ! rpm -q aide >/dev/null 2>&1; then
    warn "AIDE no está instalado; es opcional y --fix interactivo solicitará autorización antes de instalarlo"
    na "Base de referencia AIDE: no aplica mientras el paquete no esté instalado."
    na "Verificación periódica AIDE: no aplica mientras el paquete no esté instalado."
    return
  fi
  ok "AIDE instalado: $(rpm -q aide 2>/dev/null)"
  if [ -f /var/lib/aide/aide.db.gz ]; then
    ok "Base de referencia AIDE inicializada (/var/lib/aide/aide.db.gz)"
  elif [ -f /var/lib/aide/aide.db.new.gz ]; then
    warn "Existe aide.db.new.gz, pero no la base activa aide.db.gz; revisar la finalización de la inicialización"
  else
    warn "AIDE instalado pero falta /var/lib/aide/aide.db.gz; inicializar y promover la base requiere --fix con consentimiento"
  fi
  if ! command -v crontab >/dev/null 2>&1; then
    warn "crontab no está disponible; no se puede verificar la comprobación periódica de AIDE"
  else
    root_crontab="$(crontab -u root -l 2>/dev/null || true)"
    if printf '%s\n' "$root_crontab" | grep -Fqx '0 5 * * * /usr/sbin/aide --check'; then
      ok "Verificación periódica de AIDE configurada diariamente a las 05:00"
    elif printf '%s\n' "$root_crontab" | grep -q 'aide --check'; then
      warn "La tarea AIDE existe, pero no coincide exactamente con la frecuencia/comando objetivo: 0 5 * * * /usr/sbin/aide --check"
    else
      warn "No hay comprobación periódica objetivo de AIDE en el crontab de root; --fix puede configurarla tras consentimiento"
    fi
  fi
}

fapolicyd_module() {
  echo -e "\n$BLUE### FAPOLICYD ###$NC"
  local installed=false active=false
  if [ -x /var/ossec/bin/wazuh-control ] || rpm -q wazuh-agent >/dev/null 2>&1 || rpm -q wazuh-manager >/dev/null 2>&1; then
    info "Wazuh detectado: FIM ayuda a detectar cambios, pero no sustituye el control de ejecución de fapolicyd. No se activa automáticamente: una política genérica sin inventario y pruebas permisivas puede bloquear aplicaciones, scripts y runtimes legítimos."
  fi
  rpm -q fapolicyd >/dev/null 2>&1 && installed=true
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet fapolicyd 2>/dev/null; then
    active=true
  fi
  if $installed && $active; then
    info "fapolicyd ya está activo; el baseline no lo modifica ni lo detiene."
  elif $installed; then
    info "fapolicyd está instalado pero inactivo; por política no se activa ni modifica."
  else
    info "fapolicyd no está instalado. Puede restringir ejecución no autorizada, pero el baseline no instalará ni activará fapolicyd automáticamente; requiere inventario de software y validación en modo permisivo para evitar bloquear cargas legítimas."
  fi
}
normalize_history_dotfile() {
  local file="$1" tmp
  if [ -L "$file" ]; then
    warn "$file es un enlace simbólico; --fix no lo reemplaza automáticamente."
    if [ "${PENDING_ONLY_AUDIT:-false}" != true ]; then
      return 1
    fi
  fi

  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    if [ ! -f "$file" ]; then
      warn "$file no existe; no hay historial ilimitado configurado para ese usuario/modelo"
      return 0
    fi
    if grep -Fq '# ORANGEBOX UNLIMITED HISTORY BEGIN' "$file"; then
      ok "$file: bloque OrangeBox de historial identificado"
    else
      warn "$file: falta el bloque administrado OrangeBox de historial"
    fi
    if grep -Eq '^[[:space:]]*export[[:space:]]+HISTSIZE=-1[[:space:]]*$' "$file"; then
      ok "$file: HISTSIZE=-1"
    else
      warn "$file: HISTSIZE no está fijado a -1"
    fi
    if grep -Eq '^[[:space:]]*export[[:space:]]+HISTFILESIZE=-1[[:space:]]*$' "$file"; then
      ok "$file: HISTFILESIZE=-1"
    else
      warn "$file: HISTFILESIZE no está fijado a -1"
    fi
    if grep -Eq '^[[:space:]]*set[[:space:]]+-o[[:space:]]+history([[:space:]]|$)' "$file"; then
      ok "$file: historial interactivo habilitado"
    else
      warn "$file: falta set -o history"
    fi
    if grep -Eq '^[[:space:]]*export[[:space:]]+HISTCONTROL=[[:space:]]*$' "$file"; then
      ok "$file: HISTCONTROL vacío (no se omiten comandos)"
    else
      warn "$file: HISTCONTROL no está vacío"
    fi
    if grep -Eq '^[[:space:]]*unset[[:space:]]+HISTIGNORE([[:space:]]|$)' "$file"; then
      ok "$file: HISTIGNORE eliminado"
    else
      warn "$file: HISTIGNORE puede omitir comandos del historial"
    fi
    if grep -Fq 'shopt -s histappend' "$file"; then
      ok "$file: histappend habilitado"
    else
      warn "$file: falta shopt -s histappend"
    fi
    if grep -Fq '""|/dev/null|/dev/zero|/var/log/bash_history/*)' "$file" &&
       grep -Fq 'export HISTFILE="$HOME/.bash_history"' "$file"; then
      ok "$file: HISTFILE no persistente se redirige a ~/.bash_history"
    else
      warn "$file: falta protección para HISTFILE vacío/no persistente"
    fi
    if grep -Eq '^[[:space:]]*readonly[[:space:]]+HISTFILE([[:space:]]|$)' "$file"; then
      warn "$file: HISTFILE está readonly y puede impedir la política de historial; --fix lo normalizará"
    else
      ok "$file: HISTFILE no está bloqueado como readonly"
    fi
    if grep -Eq 'PROMPT_COMMAND=.*history -c; history -r|^[[:space:]]*PROMPT_COMMAND="orangebox_history_guard;' "$file"; then
      warn "$file: PROMPT_COMMAND contiene una regla que limpia/recarga el historial en cada prompt"
    else
      ok "$file: no se detectó el patrón de limpieza de historial en PROMPT_COMMAND"
    fi
    return 0
  fi

  if [ -f "$file" ] &&
     grep -Fq '# ORANGEBOX UNLIMITED HISTORY BEGIN' "$file" &&
     grep -Eq '^[[:space:]]*export[[:space:]]+HISTSIZE=-1[[:space:]]*$' "$file" &&
     grep -Eq '^[[:space:]]*export[[:space:]]+HISTFILESIZE=-1[[:space:]]*$' "$file" &&
     ! grep -Eq '^[[:space:]]*readonly[[:space:]]+HISTFILE([[:space:]]|$)' "$file" &&
     ! grep -Eq 'PROMPT_COMMAND=.*history -c; history -r|^[[:space:]]*PROMPT_COMMAND="orangebox_history_guard;' "$file"; then
    ok "$file: historial habilitado y sin límite"
    return 0
  fi
  if [ ! -f "$file" ]; then
    if ! $AUTO_FIX; then warn "$file no existe; --fix puede crearlo con historial ilimitado."; return 0; fi
  elif ! $AUTO_FIX; then
    warn "$file: historial no cumple la política; --fix lo normalizará a ilimitado"
    return 0
  fi
  [ ! -e "$file" ] || backup_once "$file"
  tmp="$(mktemp)" || { warn "No se pudo crear temporal para $file"; return 1; }
  if [ -f "$file" ]; then
    awk '
      $0 == "# ORANGEBOX UNLIMITED HISTORY BEGIN" { skip=1; next }
      $0 == "# ORANGEBOX UNLIMITED HISTORY END" { skip=0; next }
      skip { next }
      /^export PROMPT_COMMAND="history -a; history -c; history -r;/ { next }
      /^PROMPT_COMMAND="orangebox_history_guard; / { next }
      /^orangebox_history_guard\(\) \{$/ { skip_guard=1; next }
      skip_guard && /^\}$/ { skip_guard=0; next }
      skip_guard { next }
      /^[[:space:]]*readonly[[:space:]]+HISTFILE([[:space:]]|$)/ { next }
      { print }
    ' "$file" > "$tmp" || { rm -f "$tmp"; warn "No se pudo leer $file"; return 1; }
  else
    : > "$tmp"
  fi
  cat >> "$tmp" <<'ORANGEBOX_UNLIMITED_HISTORY'
# ORANGEBOX UNLIMITED HISTORY BEGIN
# El historial interactivo se conserva completo, sin límite de líneas.
set -o history
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTCONTROL=
unset HISTIGNORE
case "${HISTFILE:-}" in
  ""|/dev/null|/dev/zero|/var/log/bash_history/*) export HISTFILE="$HOME/.bash_history" ;;
esac
shopt -s histappend
# ORANGEBOX UNLIMITED HISTORY END
ORANGEBOX_UNLIMITED_HISTORY
  chmod --reference="$file" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  chown --reference="$file" "$tmp" 2>/dev/null || chown root:root "$tmp"
  if mv "$tmp" "$file"; then
    ok "$file: historial habilitado y sin límite"
    FIXED=$((FIXED+1))
  else
    rm -f "$tmp"
    warn "No se pudo instalar configuración de historial en $file"
    return 1
  fi
}

bash_profile_check() {
  local file="$1" label="$2" needle="$3" detail="${4:-}" detail2="${5:-}"
  if [ ! -f "$file" ]; then
    warn "$label: no verificable; falta $file"
    return 0
  fi
  if grep -Fq -- "$needle" "$file" &&
     { [ -z "$detail" ] || grep -Fq -- "$detail" "$file"; } &&
     { [ -z "$detail2" ] || grep -Fq -- "$detail2" "$file"; }; then
    ok "$label"
  else
    warn "$label: falta o difiere en $file"
  fi
}

bash_audit_profile_controls() {
  local file="$1" mode owner group
  bash_profile_check "$file" "Bash timeout de usuario: TMOUT=120 y readonly" 'TMOUT=120 2>/dev/null || true' 'readonly TMOUT'
  bash_profile_check "$file" "Bash root: elimina TMOUT heredado" 'unset TMOUT 2>/dev/null || true'
  bash_profile_check "$file" "Bash: historial habilitado" 'set -o history'
  bash_profile_check "$file" "Bash: HISTSIZE=-1 (sin límite de líneas en memoria)" 'orangebox_history_guard() {' 'HISTSIZE=-1' 'export HISTSIZE HISTFILESIZE HISTFILE'
  bash_profile_check "$file" "Bash: HISTFILESIZE=-1 (sin límite de líneas persistentes)" 'orangebox_history_guard() {' 'HISTFILESIZE=-1' 'export HISTSIZE HISTFILESIZE HISTFILE'
  bash_profile_check "$file" "Bash: HISTCONTROL vacío (no se omiten comandos)" 'orangebox_history_guard() {' 'HISTCONTROL=' 'export HISTCONTROL'
  bash_profile_check "$file" "Bash: HISTIGNORE eliminado" 'orangebox_history_guard() {' 'unset HISTIGNORE'
  bash_profile_check "$file" "Bash: historial acumulativo entre sesiones" 'shopt -s histappend'
  bash_profile_check "$file" "Bash: historial con fecha y hora" "export HISTTIMEFORMAT='%F %T '"
  bash_profile_check "$file" "Bash: bloquea history -c/-d/-w desde el wrapper" 'history() {' '*c*|*d*|*w*)'
  bash_profile_check "$file" "Bash: redirige HISTFILE no persistente a ~/.bash_history" 'HISTFILE="${HOME}/.bash_history"'
  bash_profile_check "$file" "Bash: protege el archivo de historial con modo 0600" 'chmod 600 "$HISTFILE"'
  bash_profile_check "$file" "Bash: modo de edición Emacs" 'set -o emacs'
  bash_profile_check "$file" "Readline: Ctrl+A va al inicio de línea" 'beginning-of-line' '\C-a'
  bash_profile_check "$file" "Readline: Ctrl+E va al final de línea" 'end-of-line' '\C-e'
  bash_profile_check "$file" "Bash: obtiene FQDN mediante hostname -f" 'hostname -f'
  bash_profile_check "$file" "Bash: prompt por rol root/no-root y color diferenciado" 'orangebox_set_prompt() {' '\e[1;31m'
  bash_profile_check "$file" "Bash: prompt de usuario no-root usa color diferenciado" 'orangebox_set_prompt() {' '\e[1;32m'
  bash_profile_check "$file" "Bash: reaplica prompt e historial en cada prompt" 'orangebox_pre_prompt() {' 'history -a'
  bash_profile_check "$file" "Bash: registra orangebox_pre_prompt en PROMPT_COMMAND" 'orangebox_pre_prompt' 'PROMPT_COMMAND='
  bash_profile_check "$file" "Bash: el resto del perfil solo afecta shells interactivas" '# El resto de esta configuracion solo aplica a shells interactivos.'
  if [ -f "$file" ]; then
    mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
    owner="$(stat -c '%U' "$file" 2>/dev/null || true)"
    group="$(stat -c '%G' "$file" 2>/dev/null || true)"
    if [ "$mode" = 644 ] && [ "$owner" = root ] && [ "$group" = root ]; then
      ok "Perfil Bash OrangeBox: propietario root:root y permisos 0644"
    else
      warn "Perfil Bash OrangeBox: propietario/permisos actuales ${owner:-?}:${group:-?} ${mode:-?}; objetivo root:root 0644"
    fi
  fi
}

bash_audit_system_bashrc_include() {
  local system_bashrc=/etc/bashrc marker='# OrangeBox Linux Hardening managed shell config'
  local include='[ -r /etc/profile.d/99-orangebox-linux-hardening.sh ] && . /etc/profile.d/99-orangebox-linux-hardening.sh'
  if [ ! -f "$system_bashrc" ]; then
    warn "$system_bashrc no existe; no se puede validar el include del perfil OrangeBox."
  elif grep -Fq "$marker" "$system_bashrc" && grep -Fq "$include" "$system_bashrc"; then
    ok "$system_bashrc carga el perfil OrangeBox para shells interactivos no-login"
  else
    warn "$system_bashrc no incluye completamente el perfil OrangeBox para shells no-login; falta o está incompleto el marcador/include administrado"
  fi
}

bash_audit_external_history_overrides() {
  local f checked=0 found=0
  local disable_pattern='(^|[[:space:]])(export[[:space:]]+)?(HISTSIZE|HISTFILESIZE)[[:space:]]*=[[:space:]]*0([[:space:]]|$)|(^|[[:space:]])(export[[:space:]]+)?HISTFILE[[:space:]]*=[[:space:]]*"?(/dev/null|/dev/zero)"?([[:space:]]|$)|^[[:space:]]*unset[[:space:]]+HISTFILE([[:space:]]|$)|^[[:space:]]*set[[:space:]]+\+[[:space:]]*o[[:space:]]+history([[:space:]]|$)'
  for f in /etc/profile /etc/bashrc /etc/profile.d/*.sh /root/.bash_profile /root/.bashrc /etc/skel/.bashrc; do
    [ -f "$f" ] || continue
    checked=$((checked+1))
    if grep -Eiq "$disable_pattern" "$f"; then
      found=$((found+1))
      warn "Posible override de hardening del historial en $f; revisar las directivas HISTSIZE/HISTFILESIZE/HISTFILE/history."
    fi
  done
  if [ "$checked" -eq 0 ]; then
    warn "No se pudieron inspeccionar archivos de perfiles Bash para detectar overrides del historial."
  elif [ "$found" -eq 0 ]; then
    ok "No se detectaron overrides conocidos que deshabiliten Bash History en los perfiles inspeccionados"
  fi
}

bash_module() {
  section "BASH / HISTORIAL / PROMPT"
  local target=/etc/profile.d/99-orangebox-linux-hardening.sh tmp f
  if [ ! -d /etc/profile.d ]; then
    if $AUTO_FIX; then
      if ! install -d -o root -g root -m 755 /etc/profile.d; then
        warn "/etc/profile.d no existe y no se pudo crear"
        return
      fi
      ok "/etc/profile.d creado con root:root 0755"
      FIXED=$((FIXED+1))
    else
      warn "/etc/profile.d no existe; se requiere crearlo para instalar el perfil Bash OrangeBox"
    fi
  fi

  # The compact baseline audit must not depend on temporary-file creation.
  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    bash_audit_profile_controls "$target"
    normalize_history_dotfile /root/.bashrc
    normalize_history_dotfile /etc/skel/.bashrc
    bash_audit_system_bashrc_include
    bash_audit_external_history_overrides
    return
  fi

  # La configuración externa ajena al baseline se revisa en el modo detallado.
  if [ "${PENDING_ONLY_AUDIT:-false}" != true ]; then
    for f in /etc/profile /etc/bashrc /etc/profile.d/*.sh /root/.bash_profile /root/.bashrc; do
      [ -f "$f" ] || continue
      if grep -Eiq '(^|[[:space:]])(export[[:space:]]+)?(HISTSIZE|HISTFILESIZE)[[:space:]]*=[[:space:]]*0([[:space:]]|$)|(^|[[:space:]])(export[[:space:]]+)?HISTFILE[[:space:]]*=[[:space:]]*"?(/dev/null|/dev/zero)"?([[:space:]]|$)|^[[:space:]]*unset[[:space:]]+HISTFILE([[:space:]]|$)|^[[:space:]]*set[[:space:]]+\+[[:space:]]*o[[:space:]]+history([[:space:]]|$)' "$f"; then
        warn "Posible deshabilitación de Bash History detectada en $f; se revisará la configuración efectiva"
      fi
    done
  fi

  tmp="$(mktemp)" || { warn "No se pudo crear temporal para Bash"; return; }
  cat > "$tmp" <<'ORANGEBOX_BASH'
# OrangeBox Linux Hardening - historial ilimitado, prompt por rol y timeout
# Timeout por inactividad: 120 segundos en shells interactivos de usuarios no-root.
# Limpiar TMOUT heredado evita que una shell root reciba el timeout del usuario.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  unset TMOUT 2>/dev/null || true
else
  case $- in
    *i*)
      if [ "${TMOUT:-}" != 120 ]; then
        TMOUT=120 2>/dev/null || true
      fi
      if [ "${TMOUT:-}" = 120 ]; then
        export TMOUT
        readonly TMOUT 2>/dev/null || true
      else
        printf '%s\n' 'OrangeBox: no fue posible fijar TMOUT=120; revise si ya estaba definido como readonly.' >&2
      fi
      ;;
  esac
fi

# El resto de esta configuracion solo aplica a shells interactivos.
case $- in
  *i*) ;;
  *) return 0 ;;
esac

# Protección de mejor esfuerzo: impedir borrado/sobrescritura accidental por
# los comandos comunes "history -c", "history -d" y "history -w".
# No es una frontera de seguridad: "builtin history", edición del archivo o
# modificación de la shell pueden eludir este wrapper.
history() {
  local arg opts
  for arg in "$@"; do
    case "$arg" in
      --) break ;;
      -?*)
        opts="${arg#-}"
        case "$opts" in
          *c*|*d*|*w*)
            printf '%s\n' 'OrangeBox: bloqueado history -c/-d/-w para proteger el historial de esta sesión.' >&2
            return 2
            ;;
        esac
        case "$opts" in
          *p*|*s*) break ;;
        esac
        ;;
      *) break ;;
    esac
  done
  builtin history "$@"
}

orangebox_history_guard() {
  set -o history 2>/dev/null || true
  HISTSIZE=-1
  HISTFILESIZE=-1
  case "${HISTFILE:-}" in
    ""|/dev/null|/dev/zero|/var/log/bash_history/*) HISTFILE="${HOME}/.bash_history" ;;
  esac
  export HISTSIZE HISTFILESIZE HISTFILE
  HISTCONTROL=
  export HISTCONTROL
  unset HISTIGNORE
  shopt -s histappend
}

export HISTTIMEFORMAT='%F %T '
orangebox_history_guard

orangebox_secure_history_file() {
  [ -n "${HOME:-}" ] && [ -d "$HOME" ] || return 0
  [ "$HISTFILE" = "$HOME/.bash_history" ] || return 0
  if [ ! -e "$HISTFILE" ]; then (umask 077; : > "$HISTFILE") 2>/dev/null || true; fi
  if [ -f "$HISTFILE" ] && [ -O "$HISTFILE" ]; then chmod 600 "$HISTFILE" 2>/dev/null || true; fi
}
orangebox_secure_history_file

# Normalizar la edición de línea en Bash para administración.
# Ctrl+A = inicio de línea; Ctrl+E = final de línea.
# No depender de un ~/.inputrc o /etc/inputrc personalizado.
set -o emacs 2>/dev/null || true
bind '"\C-a": beginning-of-line' 2>/dev/null || true
bind '"\C-e": end-of-line' 2>/dev/null || true

# Resolver hostname FQDN una vez por shell; evitar consultas en cada prompt.
ORANGEBOX_PROMPT_HOST="$(hostname -f 2>/dev/null || true)"
case "$ORANGEBOX_PROMPT_HOST" in
  ""|localhost|localhost.localdomain) ORANGEBOX_PROMPT_HOST="$(hostname 2>/dev/null || true)" ;;
esac
[ -n "$ORANGEBOX_PROMPT_HOST" ] || ORANGEBOX_PROMPT_HOST=unknown

# Fijar el prompt antes de cada indicador; otros perfiles pueden redefinir PS1.
orangebox_set_prompt() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    PS1='\[\e[2m\]\D{%H:%M:%S}\[\e[0m\] \[\e[1;31m\]\u@'"$ORANGEBOX_PROMPT_HOST"' \w #\[\e[0m\] '
  else
    PS1='\[\e[2m\]\D{%H:%M:%S}\[\e[0m\] \[\e[1;32m\]\u@'"$ORANGEBOX_PROMPT_HOST"' \w $\[\e[0m\] '
  fi
}

orangebox_pre_prompt() {
  # /root/.bashrc puede activar "set -o vi" después de cargar este perfil.
  # Reafirmar el modo Emacs y las teclas antes de presentar cada prompt.
  set -o emacs 2>/dev/null || true
  bind '"\C-a": beginning-of-line' 2>/dev/null || true
  bind '"\C-e": end-of-line' 2>/dev/null || true
  orangebox_history_guard
  history -a
  orangebox_set_prompt
}
case ";${PROMPT_COMMAND:-};" in
  *";orangebox_pre_prompt;"*|*"; orangebox_pre_prompt;"*) ;;
  *)
    if [ -n "${PROMPT_COMMAND:-}" ]; then
      PROMPT_COMMAND="${PROMPT_COMMAND}; orangebox_pre_prompt"
    else
      PROMPT_COMMAND="orangebox_pre_prompt"
    fi
    ;;
esac
export PROMPT_COMMAND
orangebox_set_prompt
ORANGEBOX_BASH

  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    bash_audit_profile_controls "$target"
  elif [ -f "$target" ] && cmp -s "$tmp" "$target" &&
     [ "$(stat -c '%a' "$target" 2>/dev/null)" = 644 ] &&
     [ "$(stat -c '%U' "$target" 2>/dev/null)" = root ] &&
     [ "$(stat -c '%G' "$target" 2>/dev/null)" = root ]; then
    ok "Bash History habilitado e ilimitado; prompt OrangeBox ya configurado"
  elif $AUTO_FIX; then
    [ ! -e "$target" ] || backup_once "$target"
    if install -o root -g root -m 644 "$tmp" "$target" && cmp -s "$tmp" "$target"; then
      ok "Bash History habilitado sin límite y prompt por rol aplicado en $target"
      FIXED=$((FIXED+1))
    else
      warn "No se pudo instalar/verificar $target"
    fi
  else
    warn "$target requiere habilitar Bash History y establecer HISTSIZE/HISTFILESIZE=-1"
  fi
  rm -f "$tmp"

  # Normalizar también los dotfiles administrados más sensibles sin tocar
  # aliases, umask, timeout ni el resto de las preferencias existentes.
  normalize_history_dotfile /root/.bashrc
  normalize_history_dotfile /etc/skel/.bashrc

  # CentOS/RHEL inicia shells interactivos no-login desde /etc/bashrc.
  local system_bashrc=/etc/bashrc marker='# OrangeBox Linux Hardening managed shell config'
  local include='[ -r /etc/profile.d/99-orangebox-linux-hardening.sh ] && . /etc/profile.d/99-orangebox-linux-hardening.sh'
  local bashrc_changed=false
  if [ ! -f "$system_bashrc" ]; then
    warn "$system_bashrc no existe; no se puede validar ni añadir el include del perfil OrangeBox."
  elif grep -Fq "$marker" "$system_bashrc" && grep -Fq "$include" "$system_bashrc"; then
    ok "$system_bashrc carga el perfil OrangeBox para shells interactivos no-login"
  elif ! $AUTO_FIX; then
    warn "$system_bashrc no incluye completamente el perfil OrangeBox para shells no-login; falta o está incompleto el marcador/include administrado"
  else
    backup_once "$system_bashrc"
    if ! grep -Fq "$marker" "$system_bashrc"; then printf '\n%s\n' "$marker" >> "$system_bashrc" && bashrc_changed=true; fi
    if ! grep -Fq "$include" "$system_bashrc"; then printf '%s\n' "$include" >> "$system_bashrc" && bashrc_changed=true; fi
    if grep -Fq "$marker" "$system_bashrc" && grep -Fq "$include" "$system_bashrc"; then
      ok "Include idempotente verificado en /etc/bashrc para shells interactivos no-login"
      [ "$bashrc_changed" = true ] && FIXED=$((FIXED+1))
    else
      warn "No se pudo añadir/verificar el include en /etc/bashrc"
    fi
  fi
}

usage() {
  cat <<EOF
OrangeBox Linux Hardening $SCRIPT_VERSION

Uso:
  $0                                Auditoría del baseline interno
  $0 --fix                          Modo interactivo: explica los riesgos y pregunta
  $0 --fix --auto                   Aplica banners; audita el resto sin cambios
  ./linux-hardening-audit.sh         Auditoría agregada, separada y de solo lectura
  $0 --fix --module banners         Fuerza MOTD, /etc/issue, /etc/issue.net y banner SSH
  $0 --fix --module bash-full       Audita y aplica hardening de Bash con confirmación
  $0 --fix --module synflood        Aplica SYN cookies, backlog y reintentos TCP persistentes
  $0 --fix --module network-full --allow-shorewall
                                    Autoriza explícitamente cambios de red con Shorewall
  $0 --module <modulo> [--fix] [--auto] [--allow-risky]

Baseline genérico incluido en all:
  ssh banners bash-full password-full sudo-full kernel-full network-full package-repos crypto-policies
  auditd-full cron-full usb-storage grub-full filesystem-full rsyslog-full
  selinux-setup time-sync services fapolicyd aide

Módulos adicionales:
  aide audit-listeners auditd-full bash-full time-sync cpu-full cron-full
  packages-remove services-remove usb-storage grub-full kernel-full lpe-2026
  network-full package-repos crypto-policies password-full gui-remove xinetd-remove rsyslog-full
  selinux-setup ssh-cis ssh-complete sudo-full filesystem-full

Evaluaciones independientes:
  ./audit-firewall-listeners.sh Auditoría de firewall/listeners (solo lectura).
  ./audit-listening-services.sh Inventario independiente de sockets.
  ./linux-hardening-audit.sh    Audita módulos sin calcular cumplimiento CIS.
  ./cis-benchmark-check.sh       Evalúa exclusivamente el benchmark CIS.

Seguridad:
  --fix primero audita cada módulo complementario y muestra sus parámetros pendientes; después explica el riesgo y pide confirmación antes de modificar.
  --fix --auto no hace preguntas: aplica únicamente banners/MOTD; el resto queda en auditoría.
  El baseline global audita sincronización horaria pero no cambia ntpd/chronyd. Para ello usa explícitamente --module time-sync --fix.
  --allow-risky está obsoleto como bypass: ningún control sensible se aplica sin confirmación interactiva.
  --allow-shorewall es una autorización separada para ejecutar network-full con Shorewall.
  --module firewall-rules está bloqueado: el generador de iptables vacía reglas y
  aplica INPUT DROP, incompatible con la administración actual mediante Shorewall.
  post-install se omite: no tiene una ruta de auditoría de solo lectura.
  El benchmark CIS no se ejecuta como módulo; utiliza el comando independiente indicado arriba.
EOF
}

internal_module_requires_risk() {
  case "$1" in
    ssh|sudo|kernel|synflood|rsyslog|bash) return 0 ;;
    *) return 1 ;;
  esac
}

risk_description() {
  case "$1" in
    ssh) echo "aplica controles SSH pendientes, incluyendo PermitRootLogin=no, X11Forwarding=no y desactivación de TCP/agent forwarding. Puede impedir el acceso directo como root, cortar túneles o GUI remotas; confirma una cuenta admin/sudo funcional, conserva esta sesión abierta y prueba una segunda conexión." ;;
    bash-full) echo "configura perfiles, timeout de shells, historial y logging de comandos; TMOUT puede cerrar shells inactivas y el logging puede registrar argumentos sensibles. Puede afectar scripts/automatizaciones." ;;
    cpu-full) echo "comprueba mitigaciones de CPU y parámetros de memoria; algunos ajustes pueden afectar depuración o aplicaciones antiguas." ;;
    auditd-full) echo "configura reglas y límites de auditd; puede incrementar el uso de disco/logs y las reglas inmutables pueden requerir reinicio para cambiarlas." ;;
    cron-full) echo "restringe permisos y usuarios de cron/at; puede impedir tareas de usuarios, scripts de hosting o automatizaciones que no sean de root." ;;
    filesystem-full) echo "aplica flags de montajes, hidepid y bloqueo de módulos; noexec/nodev/nosuid puede romper aplicaciones y hidepid puede afectar agentes que inspeccionan procesos." ;;
    kernel-full) echo "endurece sysctl, límites de recursos y core dumps; límites bajos pueden cortar procesos/archivos abiertos y desactivar core dumps limita el análisis post-mortem." ;;
    network-full) echo "cambia sysctl de red y bloquea módulos de kernel; puede afectar routing asimétrico, VPN, protocolos especializados y conectividad. Con Shorewall, el módulo se abstiene de aplicar sin autorización expresa." ;;
    password-full) echo "ajusta parámetros de calidad de contraseñas y algunos defaults; puede impedir nuevas contraseñas que no cumplan la política. La pila PAM/lockout no se edita automáticamente." ;;
    sudo-full) echo "endurece sudo; use_pty requiere confirmación específica y puede afectar automatizaciones sin terminal, mientras que cambios de timeout modifican la duración de credenciales cacheadas." ;;
    grub-full) echo "modifica parámetros de arranque y regenera grub.cfg; un error puede impedir arrancar y varios cambios requieren reinicio. Garantiza consola de recuperación/backup antes de aceptar." ;;
    usb-storage) echo "bloquea módulos de almacenamiento USB; puede afectar discos USB, medios de recuperación y backups conectados por USB." ;;
    selinux-setup) echo "solo cambia SELinux a Enforcing y/o persiste ese modo tras una confirmación específica; aplicaciones sin políticas/contextos adecuados pueden quedar bloqueadas. No habilita SELinux si está Disabled." ;;
    time-sync) echo "puede modificar ntpd/chronyd o ajustar el reloj; puede afectar Kerberos/Samba AD, certificados y correlación de logs. El baseline general lo audita, pero no cambia NTP automáticamente." ;;
    sudo) echo "revisa controles de sudo; use_pty solo se considera en servidores sin cPanel y requiere una confirmación específica." ;;
    kernel) echo "audita y propone deshabilitar forwarding IPv4/IPv6 solo con confirmación individual. Puede interrumpir routing, NAT, VPN y redes de contenedores; si se conserva IPv4 forwarding, usa rp_filter=2 (loose) para reducir el riesgo de descartar tráfico asimétrico." ;;
    synflood) echo "comprueba SYN cookies y backlog TCP; solo propone cambios si falta algún valor activo o persistente. No cambia net.ipv4.ip_forward." ;;
    rsyslog|rsyslog-full) echo "activa almacenamiento persistente de journald y reinicia journald; revisa espacio, retención y logging existente." ;;
    network-full) echo "cambia sysctl de red y bloquea módulos de kernel (por ejemplo SCTP/RDS/DCCP/TIPC); puede afectar VPN, routing o aplicaciones que usen esos protocolos." ;;
    firewall) echo "identifica el gestor/backend, inventaría listeners y contrasta su acceso con reglas INPUT; es estrictamente de solo lectura incluso con --fix." ;;
    firewall-rules) echo "el generador de iptables vacía reglas y establece INPUT DROP; está bloqueado para evitar cortar accesos o interferir con Shorewall." ;;
    ssh-cis|ssh-complete) echo "modifica parámetros de SSH y/o algoritmos criptográficos. Puede dejar fuera clientes antiguos, automatizaciones o el acceso administrativo." ;;
    password|password-full) echo "cambia política de contraseñas o valores por defecto. No se editará PAM a ciegas, pero podría afectar autenticación o futuras contraseñas." ;;
    filesystem|filesystem-full) echo "puede restringir montajes, ocultar procesos con hidepid, bloquear módulos o deshabilitar autofs; podría afectar monitoreo y aplicaciones." ;;
    cron|cron-full) echo "puede cambiar permisos de cron/at y crear listas allow limitadas a root, impidiendo tareas de usuarios o de hosting/cPanel." ;;
    selinux|selinux-setup) echo "solo informa el estado actual; SELinux no se modifica desde este repositorio." ;;
    grub|grub-full) echo "cambia parámetros del arranque y regenera grub.cfg; el efecto pleno requiere reinicio y un error puede impedir arrancar." ;;
    kernel-full|lpe-2026) echo "cambia mitigaciones de kernel/sysctl o bloquea módulos/namespaces; puede afectar contenedores, VPN y requiere reinicio para algunos efectos." ;;
    auditd|auditd-full) echo "modifica reglas y servicio de auditoría; puede incrementar volumen de eventos y afectar configuración de auditd existente." ;;
    time|time-sync) echo "puede cambiar el servicio de sincronización o dar un salto de hora; puede afectar certificados, autenticación y correlación de logs." ;;
    usb|usb-storage) echo "bloquea almacenamiento USB mediante modprobe; puede afectar dispositivos o flujos de recuperación que dependan de USB." ;;
    services|services-remove|packages-remove|xinetd-remove|gui-remove) echo "puede detener/deshabilitar servicios o eliminar paquetes y dependencias; podría afectar aplicaciones instaladas." ;;
    aide) echo "instala AIDE y crea una base de integridad; puede solaparse con Wazuh FIM y consumir espacio/CPU. El instalador explicará ese solapamiento y pedirá consentimiento explícito." ;;
    bash-full) echo "instala auditoría amplia de comandos mediante trap DEBUG/syslog; puede aumentar volumen y registrar argumentos sensibles." ;;
    post-install) echo "script de preparación inicial que puede cambiar GRUB, instalar paquetes y habilitar servicios; SELinux solo se audita." ;;
    *) echo "este módulo puede modificar configuración o servicios; revisa el alcance y conserva una vía de recuperación." ;;
  esac
}

confirm_risky_change() {
  local name="$1" answer description
  description="$(risk_description "$name")"
  echo
  echo -e "$YELLOW[ATENCIÓN] Control con riesgo operacional: $name$NC"
  echo "Qué hará: $description"
  if [ "$AUTO_MODE" = true ]; then
    warn "Modo --auto: cambio omitido; no se aplican controles críticos."
    return 1
  fi
  if [ "$ALLOW_RISKY" = true ]; then
    echo -e "$YELLOW[INFO] --allow-risky está obsoleto como bypass: este control sigue requiriendo confirmación interactiva.$NC"
  fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    warn "No hay terminal disponible para confirmar; el cambio se omitirá por seguridad."
    return 1
  fi
  read -r -p "¿Quieres aplicar '$name'? [s/N]: " answer </dev/tty
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) warn "Control '$name' rechazado por el usuario; se mantiene en auditoría."; return 1 ;;
  esac
}

run_internal_module_with_confirmation() {
  local name="$1" previous_fix="$AUTO_FIX" ssh_status=0 journal_status=0
  if [ "$AUTO_FIX" = true ] && internal_module_requires_risk "$name"; then
    case "$name" in
      ssh)
        # Show every SSH control and its impact before asking for authorization.
        ssh_state_status audit
        ssh_state_status preflight
        ssh_status=$?
        if [ "$ssh_status" -eq 0 ]; then
          info "Los controles SSH ya cumplen los objetivos efectivos; se omite la confirmación porque no hay cambios pendientes."
        elif [ "$ssh_status" -eq 1 ] && ssh_module_can_apply; then
          if ! confirm_risky_change "$name"; then
            AUTO_FIX=false
            run_module "$name"
            AUTO_FIX="$previous_fix"
            return 0
          fi
        else
          reason="$(ssh_module_apply_block_reason || true)"
          if [ "$ssh_status" -eq 1 ]; then
            info "Hay controles SSH pendientes, pero no se aplicarán automáticamente: ${reason:-no se encontró una vía segura}; se conserva la configuración actual y se muestra la remediación manual."
          else
            info "No se pudo verificar el estado efectivo de SSH: ${reason:-sshd -T no entregó valores}. No se modificará."
          fi
          AUTO_FIX=false
          run_module "$name"
          AUTO_FIX="$previous_fix"
          return 0
        fi
        ;;
      sudo)
        # sudo_module owns its parameter-specific confirmation and intentionally
        # skips use_pty on cPanel hosts. A generic prompt here is redundant.
        info "Sudo se comprueba primero; solo su control específico puede solicitar confirmación."
        ;;
      kernel)
        # sysctl_safe_apply verifies each live and persistent value before it
        # asks. A module-wide prompt is redundant and must never precede checks.
        info "Se comprobarán los parámetros del kernel uno por uno; solo los que falten o difieran solicitarán confirmación."
        ;;
      synflood)
        # The same rule applies to SYN cookies/backlog: ask per setting only.
        if synflood_state_compliant; then
          info "SYN cookies/backlog ya cumplen los objetivos activos y persistentes; no hay cambios pendientes."
        else
          info "SYN cookies/backlog: se revisará cada parámetro; solo los que falten o difieran solicitarán confirmación."
        fi
        ;;
      rsyslog)
        rsyslog_state_status
        journal_status=$?
        if [ "$journal_status" -eq 0 ]; then
          info "Journald ya tiene Storage=persistent y /var/log/journal; no se solicitará confirmación ni se reiniciará."
        elif [ "$journal_status" -eq 1 ]; then
          if ! confirm_risky_change "$name"; then
            AUTO_FIX=false
            run_module "$name"
            AUTO_FIX="$previous_fix"
            return 0
          fi
        else
          info "No se puede verificar journald con seguridad; se omite aplicación automática."
          AUTO_FIX=false
          run_module "$name"
          AUTO_FIX="$previous_fix"
          return 0
        fi
        ;;
      *)
        if ! confirm_risky_change "$name"; then
          AUTO_FIX=false
          run_module "$name"
          AUTO_FIX="$previous_fix"
          return 0
        fi
        ;;
    esac
  fi
  run_module "$name"
}

companion_module_owns_parameter_consent() {
  # These modules explain each changed value and ask at the parameter/action
  # level themselves. A second generic module prompt would duplicate consent.
  case "$1" in
    auditd-full|cron-full|grub-full|rsyslog-full|password-full|sudo-full|kernel-full|network-full|filesystem-full|package-repos|crypto-policies|selinux-setup|usb-storage|aide)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_companion_module() {
  local name="$1" script="" fix_arg="--fix" audit_arg="" risky=false audit_only=false block_fix=false interactive=false
  local apply_fix="$AUTO_FIX" child_rc=0
  local -a audit_args=() fix_args=()

  if [ "$name" = "cis" ]; then
    die "El benchmark CIS es independiente de los módulos de hardening. Ejecuta: ./cis-benchmark-check.sh"
  fi
  case "$name" in
    aide) script="aide-install.sh"; risky=true ;;
    audit-listeners) script="audit-listening-services.sh"; audit_only=true; fix_arg="" ;;
    auditd-full) script="auditd-hardening.sh"; risky=true ;;
    bash-full) script="bash-hardening.sh"; risky=true ;;
    time-sync) script="configure-time-sync.sh"; risky=true ;;
    cpu-full) script="cpu-hardening.sh"; risky=true ;;
    cron-full) script="cron-hardening.sh"; risky=true ;;
    packages-remove) script="desintalar-paquetes-sin-usar.sh"; risky=true; interactive=true; fix_arg="" ;;
    services-remove) script="desintalar-servicios-sin-usar.sh"; risky=true; interactive=true; fix_arg="" ;;
    usb-storage) script="disable-usb-storage.sh"; risky=true ;;
    firewall-rules)
      die "Módulo bloqueado: generate-iptables-rules.sh vacía reglas, establece INPUT DROP y podría cortar SSH. No se aplicará un segundo firewall destructivo."
      ;;
    grub-full) script="grub-hardening.sh"; risky=true ;;
    kernel-full) script="kernel-hardening.sh"; risky=true ;;
    lpe-2026) script="kernel-lpe-2026-mitigation.sh"; risky=true; audit_arg="--check" ;;
    network-full) script="network-hardening.sh"; risky=true; audit_arg="--check" ;;
    password-full) script="password-hardening.sh"; risky=true ;;
    post-install)
      if [ "$AUTO_FIX" = true ]; then
        die "post-install no se ejecuta desde el orquestador: no dispone de una ruta segura de auditoría de solo lectura."
      fi
      warn "Se omite post-install: puede instalar paquetes, cambiar GRUB y habilitar servicios incluso sin --fix."
      return 0
      ;;
    gui-remove) script="remove-gui-hardening.sh"; risky=true; audit_arg="--check" ;;
    xinetd-remove) script="remove-xinetd.sh"; risky=true ;;
    rsyslog-full) script="rsyslog-hardening.sh"; risky=true ;;
    selinux-setup) script="selinux-secure-setup.sh"; fix_arg="--fix"; risky=false ;;
    ssh-cis) script="ssh-hardening.sh"; risky=true ;;
    ssh-complete) script="ssh-hardening-complete.sh"; risky=true ;;
    sudo-full) script="sudo-hardening.sh"; risky=true ;;
    filesystem-full) script="FS-hardening.sh"; risky=true; audit_arg="--check"; fix_arg="--fix" ;;
    *) die "Módulo desconocido: $name" ;;
  esac

  if [ ! -f "$SCRIPT_DIR/$script" ]; then
    die "No existe $SCRIPT_DIR/$script. Ejecuta este módulo desde el checkout completo del repositorio."
  fi
  [ -n "$audit_arg" ] && audit_args=("$audit_arg")
  [ -n "$fix_arg" ] && fix_args=("$fix_arg")

  # Time sync is audit-only during global --fix. For intentional NTP changes, select
  # --module time-sync --fix; clock changes can affect Kerberos/Samba AD and log correlation.
  if [ "$AUTO_FIX" = true ] && [ "$MODULE" = "all" ] && [ "$name" = "time-sync" ]; then
    echo
    echo "[INFO] time-sync se audita en el baseline global, pero --fix no cambiará ntpd/chronyd. Para tratarlo explícitamente: --module time-sync --fix."
    apply_fix=false
  fi

  if [ "$AUTO_FIX" = true ] && [ "$AUTO_MODE" = true ] && [ "$risky" = true ]; then
    echo
    echo -e "$YELLOW[--auto] Se omite la aplicación de '$name'. Qué haría: $(risk_description "$name")$NC"
    apply_fix=false
  fi

  # Audit first, then ask for consent. Do not mutate when audit cannot be performed safely.
  echo
  echo "========== MÓDULO DEL REPOSITORIO: $name ($script) =========="
  if bash "$SCRIPT_DIR/$script" "${audit_args[@]}"; then
    child_rc=0
  else
    child_rc=$?
  fi

  if [ "$apply_fix" != true ] || [ "$audit_only" = true ]; then
    COMPANION_MODULES_RUN=$((COMPANION_MODULES_RUN + 1))
    [ "$child_rc" -eq 0 ] || COMPANION_MODULES_FAILED=$((COMPANION_MODULES_FAILED + 1))
    if [ "$audit_only" = true ]; then echo "[INFO] '$name' es de solo auditoría; no se aplicaron cambios."; fi
    return 0
  fi

  if [ "$interactive" = true ]; then
    warn "$name no ofrece auditoría no interactiva; se omite."
    COMPANION_MODULES_RUN=$((COMPANION_MODULES_RUN + 1))
    return 0
  fi

  # AIDE has its own explicit installation consent when package/base is missing.
  if [ "$risky" = true ] && ! { [ "$name" = "aide" ] && ! rpm -q aide >/dev/null 2>&1; }; then
    if companion_module_owns_parameter_consent "$name"; then
      echo "[INFO] '$name' pide confirmación por parámetro/acción; se omite una confirmación global duplicada."
    elif ! confirm_risky_change "$name"; then
      echo "[INFO] Se conserva la configuración actual de '$name'. La auditoría anterior muestra los pendientes."
      COMPANION_MODULES_RUN=$((COMPANION_MODULES_RUN + 1))
      return 0
    fi
  fi

  # Shorewall has an additional explicit safety gate; global --fix won't bypass it.
  if [ "$name" = "network-full" ] && shorewall_is_active && [ "$ALLOW_SHOREWALL" != true ]; then
    echo "[WARN] Shorewall está activo. Se auditó la red, pero no se aplican cambios desde el baseline global; usa --module network-full --fix --allow-shorewall tras revisar el impacto."
    COMPANION_MODULES_RUN=$((COMPANION_MODULES_RUN + 1))
    return 0
  fi

  echo
  echo "[INFO] Aplicando '$name' después del preflight y la autorización."
  if [ "$name" = "network-full" ]; then
    fix_args=(--fix)
    [ "$ALLOW_SHOREWALL" = true ] && fix_args+=(--allow-shorewall)
  fi
  if bash "$SCRIPT_DIR/$script" "${fix_args[@]}"; then
    COMPANION_MODULES_RUN=$((COMPANION_MODULES_RUN + 1))
    echo "[OK] Módulo $name finalizado."
  else
    child_rc=$?
    COMPANION_MODULES_RUN=$((COMPANION_MODULES_RUN + 1))
    COMPANION_MODULES_FAILED=$((COMPANION_MODULES_FAILED + 1))
    echo "[WARN] Módulo $name finalizó con código $child_rc; revisar su salida."
  fi
}

run_module() {
  case "$1" in
    ssh) ssh_module ;;
    sudo) sudo_module ;;
    password) password_module ;;
    package-repos) package_repo_module ;;
    crypto-policies) crypto_policies_module ;;
    kernel) kernel_module ;;
    synflood) synflood_module ;;
    filesystem) filesystem_module ;;
    auditd) auditd_module ;;
    rsyslog) rsyslog_module ;;
    selinux) selinux_module ;;
    cron) cron_module ;;
    usb) usb_module ;;
    services) services_module ;;
    banners) banners_module ;;
    time) time_module ;;
    grub) grub_module ;;
    firewall) die "La auditoría de firewall es independiente: ejecuta ./audit-firewall-listeners.sh." ;;
    fapolicyd) fapolicyd_module ;;
    listening) die "El inventario de sockets es independiente: ejecuta ./audit-listening-services.sh." ;;
    bash) bash_module ;;
    *) run_companion_module "$1" ;;
  esac
}

main() {
  require_root
  while [ $# -gt 0 ]; do
    case "$1" in
      --audit) AUDIT_MODE=true ;;
      --fix|-f) AUTO_FIX=true ;;
      --auto) AUTO_MODE=true ;;
      --allow-risky) ALLOW_RISKY=true ;;
      --allow-shorewall) ALLOW_SHOREWALL=true ;;
      --module|-m) shift; [ $# -gt 0 ] || die "--module requiere nombre"; MODULE="$1" ;;
      --help|-h) usage; exit 0 ;;
      --list-modules) usage; exit 0 ;;
      *) die "Argumento desconocido: $1" ;;
    esac
    shift
  done

  if [ "$AUDIT_MODE" = true ] && [ "$AUTO_FIX" = true ]; then
    die "--audit y --fix son modos excluyentes."
  fi
  if [ "$AUDIT_MODE" = true ] && [ "$MODULE" != "all" ]; then
    die "--audit ejecuta el informe completo del baseline; no se combina con --module."
  fi
  if [ "$AUTO_MODE" = true ] && [ "$AUTO_FIX" != true ]; then
    die "--auto requiere --fix. Usa --fix --auto para aplicar únicamente controles seguros."
  fi
  if [ "$AUTO_MODE" = true ] && [ "$ALLOW_RISKY" = true ]; then
    die "--auto y --allow-risky son incompatibles: --auto siempre omite controles críticos."
  fi
  if [ "$ALLOW_SHOREWALL" = true ] && [ "$MODULE" != "network-full" ]; then
    warn "--allow-shorewall solo se utiliza con --module network-full."
  fi

  if [ "$MODULE" = "repo-audit" ]; then
    die "La auditoría agregada se separó del orquestador de hardening. Ejecuta: ./linux-hardening-audit.sh"
  fi

  if [ "$AUDIT_MODE" = true ] || { [ "$MODULE" = "all" ] && [ "$AUTO_FIX" != true ]; }; then PENDING_ONLY_AUDIT=true; fi
  detect_os
  if $PENDING_ONLY_AUDIT; then
    echo "OrangeBox Linux Hardening $SCRIPT_VERSION — auditoría del baseline genérico ($OS_ID $OS_VERSION)"
  fi
  if [ "$AUTO_FIX" = true ]; then prepare_backup; fi

  local m
  if [ "$MODULE" = "all" ] && [ "$AUTO_FIX" = true ] && [ "$AUTO_MODE" = true ]; then
    warn "MODO --FIX --AUTO: solo se aplican banners/MOTD. Bash, SSH, kernel, red, auditd, filesystem y servicios quedan en auditoría."
    run_module banners
    local previous_fix="$AUTO_FIX"
    AUTO_FIX=false
    for m in ssh bash-full password-full sudo-full kernel-full network-full package-repos crypto-policies auditd-full cron-full usb-storage grub-full filesystem-full rsyslog-full selinux-setup time-sync services fapolicyd; do
      run_module "$m"
    done
    AUTO_FIX="$previous_fix"
    aide_audit_module
    echo
    echo "Modo --auto terminado: se aplicaron solo banners/MOTD; los demás módulos fueron auditados sin modificaciones."
  elif [ "$MODULE" = "all" ] && [ "$AUTO_FIX" = true ]; then
    echo -e "$BLUE[INFO]$NC MODO --FIX INTERACTIVO: cada módulo complementario muestra primero su auditoría; después solicita autorización antes de cambios con riesgo."
    echo -e "$BLUE[INFO]$NC Algunos controles kernel/red/montajes piden una confirmación por parámetro. El baseline global no modifica NTP; solo lo audita."
    run_module banners
    run_internal_module_with_confirmation ssh
    for m in bash-full password-full sudo-full kernel-full network-full package-repos crypto-policies auditd-full cron-full usb-storage grub-full filesystem-full rsyslog-full selinux-setup; do
      run_module "$m"
    done
    # Explicitly preserve time-sync settings during a global baseline --fix.
    run_module time-sync
    run_module services
    run_module fapolicyd
    run_module aide
  elif [ "$MODULE" = "all" ]; then
    info "MODO AUDITORÍA: solo lectura"
    for m in ssh banners bash-full password-full sudo-full kernel-full network-full package-repos crypto-policies auditd-full cron-full usb-storage grub-full filesystem-full rsyslog-full selinux-setup time-sync services fapolicyd; do
      run_module "$m"
    done
    aide_audit_module
  else
    if [ "$AUTO_FIX" = true ]; then
      echo -e "$BLUE[INFO]$NC MODO FIX: módulo seleccionado=$MODULE"
    else
      ok "MODO AUDITORÍA: módulo seleccionado=$MODULE"
    fi
    if [ "$AUTO_FIX" = true ] && internal_module_requires_risk "$MODULE"; then
      if [ "$AUTO_MODE" = true ]; then
        echo
        echo -e "$YELLOW[--auto] Se omitirá la aplicación del módulo '$MODULE'.$NC"
        echo "Qué haría: $(risk_description "$MODULE")"
        local previous_fix="$AUTO_FIX"
        AUTO_FIX=false
        run_module "$MODULE"
        AUTO_FIX="$previous_fix"
      else
        run_internal_module_with_confirmation "$MODULE"
      fi
    else
      run_module "$MODULE"
    fi
  fi

  echo -e "\n$GREEN============================================================$NC"
  echo -e "$GREEN OrangeBox Linux Hardening $SCRIPT_VERSION - FIN $NC"
  if [ "$PENDING_ONLY_AUDIT" = true ]; then
    echo "Controles correctos (módulos internos): $OK_COUNT"
    echo "No aplicables (módulos internos): $NOT_APPLICABLE_COUNT"
    echo "Pendientes (módulos internos): $WARNINGS"
    echo "Módulos complementarios ejecutados: $COMPANION_MODULES_RUN"
    echo "Errores de ejecución de módulos complementarios: $COMPANION_MODULES_FAILED"
    echo "Los módulos complementarios imprimen sus propios estados y resúmenes; sus contadores no se mezclan con los del baseline interno."
    if [ "$WARNINGS" -eq 0 ] && [ "$COMPANION_MODULES_FAILED" -eq 0 ]; then
      echo "No se detectaron correcciones pendientes en los módulos internos."
    else
      echo "Ejecuta ./linux-hardening.sh --fix para revisar auditorías y confirmar los cambios deseados."
    fi
  else
    echo "Correcciones: $FIXED"
    echo "Advertencias: $WARNINGS"
    echo "Errores: $ERRORS"
    echo "Módulos complementarios ejecutados: $COMPANION_MODULES_RUN"
    echo "Módulos complementarios con error: $COMPANION_MODULES_FAILED"
    if [ "$AUTO_FIX" = true ]; then echo "Backup: $BACKUP_DIR"; else echo "Backup: no creado (modo auditoría)"; fi
  fi
  echo -e "$GREEN============================================================$NC"
}

