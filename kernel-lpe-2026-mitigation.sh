#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# OrangeBox - Mitigacion del quartet de vulnerabilidades LPE de kernel 2026
# ============================================================================
#
# CVE-2026-80844  DirtyAH6
# CVE-2026-81000  TUNderflow
# CVE-2026-68121  PPPoEject
# CVE-2026-74469  DiagSpill
#
# Objetivo:
#   Reducir la superficie explotable mientras el kernel del proveedor no
#   incorpora los cuatro fixes.
#
# Mitigaciones:
#   - user.max_user_namespaces=0 bloquea la via local normal de las tres
#     primeras vulnerabilidades.
#   - ah6, pppoe, sctp y sctp_diag se bloquean persistentemente.
#   - tun/tap queda fuera del modo conservador porque puede ser necesario para
#     VPN, OpenVPN/WireGuard, contenedores y networking de usuariospace.
#     Use --block-tun o --strict cuando corresponda.
#
# Importante:
#   - No reemplaza el kernel del proveedor.
#   - No usa la version upstream como criterio de parche para EL.
#   - No descarga ni desinstala modulos automaticamente.
#   - Un modulo ya cargado requiere reinicio para que el bloqueo persistente
#     tenga efecto.
#   - No modifica crypto policies.
# ============================================================================

SCRIPT_NAME="$(basename "$0")"
STATE_DIR="/var/lib/orangebox/kernel-lpe-2026"
SYSCTL_FILE="/etc/sysctl.d/99-orangebox-kernel-lpe-2026.conf"
MODPROBE_FILE="/etc/modprobe.d/orangebox-kernel-lpe-2026.conf"
BACKUP_DIR="$STATE_DIR/backups"

AUTO_FIX=false
BLOCK_TUN=false
STRICT=false
WARNINGS=0
CHANGES=0
ERRORS=0
NEEDS_REBOOT=false
VENDOR_PATCHED=false
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OS_EOL=false
OS_EOL_REASON=""
OPENVPN_DETECTED=false
OPENVPN_DETECTION_METHODS=""
TUN_BLOCK_SKIPPED=false

CVES="CVE-2026-80844 CVE-2026-81000 CVE-2026-68121 CVE-2026-74469"
MODULES="ah6 pppoe sctp sctp_diag"

info() {
  printf '\033[0;34m[*]\033[0m %s\n' "$1"
}

ok() {
  printf '\033[0;32m[✓]\033[0m %s\n' "$1"
}

warn() {
  printf '\033[0;33m[!]\033[0m %s\n' "$1"
  WARNINGS=$((WARNINGS + 1))
}

error() {
  printf '\033[0;31m[X]\033[0m %s\n' "$1"
  ERRORS=$((ERRORS + 1))
}

usage() {
  cat <<EOF
OrangeBox - Mitigacion del quartet LPE de kernel 2026

Uso:
  $SCRIPT_NAME --check
  $SCRIPT_NAME --fix
  $SCRIPT_NAME --fix --block-tun
  $SCRIPT_NAME --strict

Opciones:
  --check       Solo audita. No modifica el sistema.
  --fix         Aplica mitigacion conservadora.
  --block-tun   Con --fix, bloquea tambien TUN/TAP.
  --strict      Equivale a --fix --block-tun.
  --help        Muestra esta ayuda.

Mitigacion conservadora:
  user.max_user_namespaces = 0
  bloquea ah6, pppoe, sctp y sctp_diag
  tun/tap solo se bloquea con --block-tun o --strict
EOF
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Este script debe ejecutarse como root."
    exit 1
  fi
}

detect_os() {
  local pretty=unknown
  local id=unknown
  local version=unknown

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    pretty="$PRETTY_NAME"
    id="$ID"
    version="$VERSION_ID"
  elif [[ -r /etc/redhat-release ]]; then
    pretty="$(cat /etc/redhat-release)"
    # CentOS 6 no suele disponer de /etc/os-release. Detectamos la familia
    # legacy directamente desde /etc/redhat-release para no perder el estado EOL.
    if grep -qi '^CentOS' /etc/redhat-release; then
      id="centos"
      version="$(sed -n 's/.*[Rr]elease[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' /etc/redhat-release | head -n1)"
    elif grep -qi 'CloudLinux' /etc/redhat-release; then
      id="cloudlinux"
      version="$(sed -n 's/.*[Rr]elease[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' /etc/redhat-release | head -n1)"
    else
      id="rhel-family"
      version="$(sed -n 's/.*[Rr]elease[[:space:]]\+\([0-9][0-9.]*\).*/\1/p' /etc/redhat-release | head -n1)"
    fi
  fi

  echo "OS      : $pretty"
  echo "ID      : $id"
  echo "Version : $version"
  echo "Kernel  : $(uname -r)"
  echo "Arch    : $(uname -m)"

  case "$id" in
    rhel|rocky|almalinux|centos|centos-stream|ol|cloudlinux)
      ok "Familia Enterprise Linux detectada."
      ;;
    *)
      warn "Distribucion no reconocida como Enterprise Linux."
      ;;
  esac

  # --------------------------------------------------------------------------
  # Plataformas EOL:
  #   CentOS Linux 6  -> EOL 2020-11-30
  #   CentOS Linux 7  -> EOL 2024-06-30
  #   CentOS Linux 8  -> EOL 2021-12-31
  #   CentOS Stream 8 -> EOL 2024-05-31
  #
  # Estos hosts no deben depender de futuros kernels corregidos por CentOS.
  # La deteccion es informativa; el script no instala ni compila kernels.
  # --------------------------------------------------------------------------
  local major
  major="$(printf '%s
' "$version" | cut -d. -f1)"

  if [[ "$id" == "centos" || "$id" == "centos-stream" ]]; then
    case "$major" in
      6)
        OS_EOL=true
        OS_EOL_REASON="CentOS 6"
        warn "CentOS 6 esta fuera de soporte; no recibe nuevas actualizaciones."
        ;;
      7)
        OS_EOL=true
        OS_EOL_REASON="CentOS 7"
        warn "CentOS 7 esta fuera de soporte; no recibe nuevas actualizaciones."
        ;;
      8)
        OS_EOL=true
        if [[ "$pretty" == *"Stream"* || "$id" == "centos-stream" ]]; then
          OS_EOL_REASON="CentOS Stream 8"
          warn "CentOS Stream 8 esta fuera de soporte; no recibe nuevas actualizaciones."
        else
          OS_EOL_REASON="CentOS Linux 8"
          warn "CentOS Linux 8 esta fuera de soporte; no recibe nuevas actualizaciones."
        fi
        ;;
    esac
  fi
}

add_openvpn_detection() {
  local method="$1"

  if [[ -z "$OPENVPN_DETECTION_METHODS" ]]; then
    OPENVPN_DETECTION_METHODS="$method"
  else
    OPENVPN_DETECTION_METHODS="$OPENVPN_DETECTION_METHODS, $method"
  fi
}

detect_openvpn() {
  info "Verificando si OpenVPN esta activo..."

  local detected=false

  # No se usa systemctl: CentOS 6/7 pueden usar SysV init y este script debe
  # funcionar tambien en hosts legacy sin systemd.
  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -x openvpn >/dev/null 2>&1; then
      detected=true
      add_openvpn_detection "proceso openvpn"
    fi
  fi

  # Fallback para sistemas donde pgrep no esta disponible o usa una vista
  # distinta de procesos.
  if ps axww 2>/dev/null | grep -E '[[:space:]/]openvpn([[:space:]]|$)' | grep -v '[[]openvpn[]]' >/dev/null 2>&1; then
    detected=true
    add_openvpn_detection "ps/proceso"
  fi

  # netstat -p muestra PID/programa en sockets activos. Esto permite detectar
  # tanto servidores como clientes OpenVPN sin asumir systemd.
  if command -v netstat >/dev/null 2>&1; then
    if netstat -anp 2>/dev/null | grep -E '[0-9]+/openvpn([[:space:]]|$)' >/dev/null 2>&1; then
      detected=true
      add_openvpn_detection "netstat/socket openvpn"
    fi
  fi

  # ss es el fallback moderno cuando netstat no existe.
  if command -v ss >/dev/null 2>&1; then
    if ss -anp 2>/dev/null | grep -E 'openvpn' >/dev/null 2>&1; then
      detected=true
      add_openvpn_detection "ss/socket openvpn"
    fi
  fi

  OPENVPN_DETECTED="$detected"

  if "$OPENVPN_DETECTED"; then
    ok "OpenVPN detectado ($OPENVPN_DETECTION_METHODS). El modulo tun/tap quedara protegido contra bloqueos automaticos."
  else
    ok "OpenVPN no detectado por proceso ni sockets."
  fi
}

running_kernel_pkg() {
  command -v rpm >/dev/null 2>&1 || return 1
  local running
  running="$(uname -r)"

  rpm -q "kernel-core-$running" 2>/dev/null && return 0
  rpm -q "kernel-$running" 2>/dev/null && return 0
  return 1
}

check_vendor_fix_status() {
  info "Verificando fixes del vendor en el kernel actualmente ejecutado..."

  local pkg
  local changelog
  local found=0
  local cve

  if ! pkg="$(running_kernel_pkg)"; then
    warn "No se encontro el paquete RPM exacto del kernel en ejecucion."
    warn "Estado del parche vendor: DESCONOCIDO."
    return 2
  fi

  changelog="$(rpm -q --changelog "$pkg" 2>/dev/null || true)"
  if [[ -z "$changelog" ]]; then
    warn "No se pudo leer el changelog de $pkg."
    warn "Estado del parche vendor: DESCONOCIDO."
    return 2
  fi

  for cve in $CVES; do
    if grep -qF "$cve" <<<"$changelog"; then
      ok "$cve aparece en el changelog del kernel en ejecucion."
      found=$((found + 1))
    else
      warn "$cve no aparece en el changelog del kernel en ejecucion."
    fi
  done

  if [[ $found -eq 4 ]]; then
    VENDOR_PATCHED=true
    ok "Los cuatro CVE aparecen en el changelog del kernel en ejecucion."
    return 0
  fi

  return 1
}

current_userns() {
  sysctl -n user.max_user_namespaces 2>/dev/null || true
}

check_userns() {
  local v
  v="$(current_userns)"

  if [[ -z "$v" ]]; then
    # CentOS 6 usa kernel 2.6.x y no dispone de user namespaces modernos.
    # No forzamos un sysctl que el kernel no conoce.
    if [[ "$(uname -r)" == 2.6.* ]]; then
      ok "Este kernel 2.6.x no expone user.max_user_namespaces; el mecanismo de user namespaces requerido por estas vias de explotacion no esta disponible."
    else
      warn "user.max_user_namespaces no esta disponible en este kernel; no se puede verificar ni aplicar esta mitigacion mediante sysctl."
    fi
    return 2
  fi

  if [[ "$v" == "0" ]]; then
    ok "user.max_user_namespaces = 0"
  else
    warn "user.max_user_namespaces = $v"
  fi
}

backup_file() {
  local file="$1"

  [[ -e "$file" ]] || return 0

  mkdir -p "$BACKUP_DIR"
  cp -a "$file" "$BACKUP_DIR/$(basename "$file").$TIMESTAMP.bak"
}

apply_userns() {
  local current
  current="$(current_userns)"

  if [[ -z "$current" ]]; then
    if [[ "$(uname -r)" == 2.6.* ]]; then
      # En kernels 2.6.x antiguos (p.ej. CentOS 6) no existe el control
      # user.max_user_namespaces porque el soporte de user namespaces no esta
      # presente como en kernels modernos. No escribimos un sysctl inexistente.
      ok "No se aplica user.max_user_namespaces: el kernel 2.6.x no expone user namespaces modernos."
      return 0
    fi

    error "No es posible aplicar user.max_user_namespaces=0 en este kernel."
    return 1
  fi

  if [[ "$current" == "0" ]]; then
    ok "user.max_user_namespaces ya estaba en 0."
    return 0
  fi

  backup_file "$SYSCTL_FILE"

  cat >"$SYSCTL_FILE" <<'EOF'
# ============================================================================
# OrangeBox - Mitigacion DirtyAH6 / TUNderflow / PPPoEject
# ============================================================================
#
# Bloquea user namespaces sin privilegios.
#
# Cubre la via local normal de:
#   CVE-2026-80844
#   CVE-2026-81000
#   CVE-2026-68121
#
# NO mitiga CVE-2026-74469 (DiagSpill).
#
# Revisar compatibilidad en hosts con contenedores, sandboxes o aplicaciones
# que dependan de user namespaces.
# ============================================================================

user.max_user_namespaces = 0
EOF

  sysctl -w user.max_user_namespaces=0 >/dev/null
  ok "user.max_user_namespaces=0 aplicado y persistente."
  CHANGES=$((CHANGES + 1))
}

module_available() {
  command -v modinfo >/dev/null 2>&1 || return 1
  modinfo "$1" >/dev/null 2>&1
}

module_loaded() {
  [[ -d "/sys/module/$1" ]]
}

module_builtin() {
  local module="$1"
  local builtin="/lib/modules/$(uname -r)/modules.builtin"

  [[ -r "$builtin" ]] || return 1
  grep -Eq "(^|/)$module\.ko([.]xz|[.]gz|[.]zst)?$" "$builtin"
}

check_module() {
  local m="$1"

  if module_builtin "$m"; then
    warn "$m esta integrado (builtin); modprobe.d no puede bloquearlo."
    return
  fi

  if ! module_available "$m"; then
    ok "$m no esta disponible como modulo."
    return
  fi

  if module_loaded "$m"; then
    warn "$m esta CARGADO actualmente."
  else
    ok "$m esta disponible y no esta cargado."
  fi
}

block_module() {
  local m="$1"

  if module_builtin "$m"; then
    error "$m es builtin; requiere kernel corregido."
    return 1
  fi

  if ! module_available "$m"; then
    ok "$m no existe como modulo en este kernel."
    return 0
  fi

  if module_loaded "$m"; then
    warn "$m ya esta cargado. Se requiere reinicio para que el bloqueo sea efectivo."
    NEEDS_REBOOT=true
  fi

  if grep -qE "^install[[:space:]]+$m[[:space:]]+/bin/true([[:space:]]|$)" "$MODPROBE_FILE" 2>/dev/null; then
    ok "Bloqueo de $m ya configurado."
    return 0
  fi

  backup_file "$MODPROBE_FILE"
  touch "$MODPROBE_FILE"
  chmod 0644 "$MODPROBE_FILE"

  cat >>"$MODPROBE_FILE" <<EOF

# OrangeBox 2026 - Mitigacion del quartet LPE de kernel.
# Impide cargar $m. No descarga un modulo ya cargado.
install $m /bin/true
blacklist $m
EOF

  ok "Bloqueo persistente configurado para $m."
  CHANGES=$((CHANGES + 1))
}

audit_modules() {
  info "Auditoria de modulos afectados..."

  local m

  for m in $MODULES; do
    check_module "$m"
  done

  if "$OPENVPN_DETECTED"; then
    warn "tun/tap: OpenVPN esta activo; NO se recomienda bloquear este modulo."
  elif "$BLOCK_TUN" || "$STRICT"; then
    check_module tun
  else
    warn "tun/tap queda en auditoria. Usa --block-tun si no es requerido."
  fi
}

apply_modules() {
  info "Aplicando bloqueos persistentes..."

  local m

  for m in $MODULES; do
    block_module "$m" || true
  done

  if "$BLOCK_TUN" || "$STRICT"; then
    if "$OPENVPN_DETECTED"; then
      TUN_BLOCK_SKIPPED=true
      warn "Se solicito bloquear tun/tap, pero OpenVPN fue detectado. Se omite el bloqueo para no interrumpir la VPN."
    else
      block_module tun || true
    fi
  fi
}

summary() {
  echo
  echo "============================================================"
  echo " OrangeBox - Kernel LPE Quartet Mitigation 2026"
  echo "============================================================"
  echo "Kernel            : $(uname -r)"
  echo "Plataforma EOL    : $OS_EOL"
  [[ "$OS_EOL" == "true" && -n "$OS_EOL_REASON" ]] && echo "Motivo EOL        : $OS_EOL_REASON"
  echo "OpenVPN detectado : $OPENVPN_DETECTED"
  [[ "$OPENVPN_DETECTED" == "true" ]] && echo "Metodo(s)         : $OPENVPN_DETECTION_METHODS"
  [[ "$TUN_BLOCK_SKIPPED" == "true" ]] && echo "Bloqueo tun       : OMITIDO por OpenVPN activo"
  echo "Cambios aplicados : $CHANGES"
  echo "Advertencias      : $WARNINGS"
  echo "Errores           : $ERRORS"

  if "$AUTO_FIX" && "$NEEDS_REBOOT"; then
    echo
    echo "ATENCION: hay modulos afectados cargados."
    echo "El reinicio es necesario para que el bloqueo persistente sea efectivo."
  fi
  echo "============================================================"
}

main() {
  if [[ $# -eq 0 ]]; then
    set -- --check
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) AUTO_FIX=false ;;
      --fix) AUTO_FIX=true ;;
      --block-tun) BLOCK_TUN=true ;;
      --strict) AUTO_FIX=true; STRICT=true; BLOCK_TUN=true ;;
      --help|-h) usage; exit 0 ;;
      *) error "Opcion desconocida: $1"; usage; exit 2 ;;
    esac
    shift
  done

  require_root

  echo -e '\033[0;32m============================================================\033[0m'
  echo -e '\033[0;32m OrangeBox - Kernel LPE Quartet Mitigation 2026\033[0m'
  echo -e '\033[0;32m============================================================\033[0m'
  echo

  detect_os
  echo

  detect_openvpn
  echo

  info "CVE cubiertos:"
  for cve in $CVES; do
    echo "  - $cve"
  done
  echo

  check_vendor_fix_status || true
  check_userns
  audit_modules

  if "$AUTO_FIX"; then
    echo
    info "Aplicando mitigacion conservadora..."
    apply_userns
    apply_modules
  else
    echo
    info "Modo auditoria: no se modifico ningun archivo."
    echo
    echo "Aplicar mitigacion:  $SCRIPT_NAME --fix"
    echo "Incluir TUN/TAP:     $SCRIPT_NAME --fix --block-tun"
    echo "Modo estricto:       $SCRIPT_NAME --strict"
  fi

  summary

  if (( ERRORS > 0 )); then
    exit 1
  fi
}

main "$@"
