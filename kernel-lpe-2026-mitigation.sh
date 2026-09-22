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
    id="rhel-family"
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
    warn "user.max_user_namespaces no existe en este kernel."
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
    error "No es posible aplicar user.max_user_namespaces=0."
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

  if "$BLOCK_TUN" || "$STRICT"; then
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
    block_module tun || true
  fi
}

summary() {
  echo
  echo "============================================================"
  echo " OrangeBox - Kernel LPE Quartet Mitigation 2026"
  echo "============================================================"
  echo "Kernel            : $(uname -r)"
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
