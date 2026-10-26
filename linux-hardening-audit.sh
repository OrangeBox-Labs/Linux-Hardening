#!/usr/bin/env bash
# OrangeBox Linux Hardening - auditoría agregada de módulos, estrictamente de solo lectura.
# Evalúa los módulos de hardening; el benchmark CIS se ejecuta de forma independiente.
# No crea backups, no instala paquetes y no aplica correcciones.
# Sin 'set -u': mantiene compatibilidad con Bash 4.4 (CentOS/RHEL 8)
# al expandir arrays vacíos de argumentos de auditoría.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_VERSION="1.3.1"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'
MODULES_RUN=0
MODULES_SKIPPED=0
ERRORS=0
OS_ID=""
OS_VERSION=""
OS_MAJOR=""
OS_NAME=""

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

require_root() {
  [ "${EUID}" -eq 0 ] || die "Ejecuta esta auditoría como root para obtener resultados completos."
}

detect_os() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_VERSION="${VERSION_ID:-}"
    OS_NAME="${PRETTY_NAME:-${ID:-Linux} ${VERSION_ID:-}}"
  elif [ -r /etc/redhat-release ]; then
    OS_NAME="$(cat /etc/redhat-release)"
    OS_ID=centos
    OS_VERSION="$(sed -nE 's/.*release[[:space:]]+([0-9]+(\.[0-9]+)*).*/\1/p' /etc/redhat-release)"
  fi
  OS_MAJOR="${OS_VERSION%%.*}"
}

usage() {
  cat <<EOF
OrangeBox Linux Hardening Audit $SCRIPT_VERSION

Uso:
  $0             Ejecuta la auditoría agregada de solo lectura.
  $0 --help      Muestra esta ayuda.

Este programa NO aplica hardening ni ejecuta opciones --fix.
No crea backups ni reportes persistentes. No ejecuta el benchmark CIS ni calcula
su porcentaje de cumplimiento; para eso usa ./cis-benchmark-check.sh.

No se ejecutan módulos que instalan/eliminan paquetes, preparan hosts,
modifican SELinux sin un modo de verificación garantizado o generan
reglas de firewall destructivas.
EOF
}

declare -a SUPPLEMENTAL_CRITICAL=()
declare -a SUPPLEMENTAL_FINDINGS=()

strip_ansi() {
  sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g'
}

append_unique() {
  local target="$1" item="$2" existing
  if [ "$target" = "critical" ]; then
    for existing in "${SUPPLEMENTAL_CRITICAL[@]}"; do
      [ "$existing" = "$item" ] && return 0
    done
    SUPPLEMENTAL_CRITICAL+=("$item")
  else
    for existing in "${SUPPLEMENTAL_FINDINGS[@]}"; do
      [ "$existing" = "$item" ] && return 0
    done
    SUPPLEMENTAL_FINDINGS+=("$item")
  fi
}

collect_supplemental_findings() {
  local name="$1" output="$2" clean line finding lower
  clean="$(printf '%s\n' "$output" | strip_ansi)"

  while IFS= read -r line; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    [ -n "$line" ] || continue

    case "$line" in
      "[WARN] "*)
        finding="${line#\[WARN\] }"
        ;;
      "[FAIL] "*)
        finding="${line#\[FAIL\] }"
        append_unique critical "$name: $finding"
        continue
        ;;
      "[ERROR] "*)
        finding="${line#\[ERROR\] }"
        append_unique critical "$name: $finding"
        continue
        ;;
      "[!] "*)
        finding="${line#\[!\] }"
        case "$finding" in
          Modo\ verificacion*|Modo\ verificación*|Ejecute\ con\ --fix*|3\ segundos\ para\ cancelar*|Modo\ automatico*|Modo\ automático*|MODO\ FIX*|MODO\ --FIX*|Para\ corregir\ ejecuta*|Para\ aplicar\ las\ correcciones*)
            continue
            ;;
        esac
        ;;
      "[✗]"*)
        finding="${line#\[✗\] }"
        ;;
      "✗ "*)
        finding="${line#✗ }"
        ;;
      *)
        # La tabla de puertos no usa etiquetas [WARN], pero contiene acciones
        # que necesitan confirmación del administrador, no ejecución automática.
        if [ "$name" = "audit-listeners" ] &&
           [[ "$line" =~ ^[0-9]+[[:space:]]+.*[[:space:]](REVISAR|ELIMINAR|CONFIGURAR[[:space:]]+LOCAL|MONITOREO)[[:space:]] ]]; then
          append_unique finding "$name: Revisar servicio/puerto: $line"
        fi
        continue
        ;;
    esac

    lower="$(printf '%s' "$finding" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      *recomendacion:*|*para\ corregir\ ejecuta*|*ejecute\ con\ --fix*|*para\ aplicar\ las\ correcciones*)
        continue
        ;;
    esac

    # El fin de soporte de la distribución es un riesgo crítico del módulo.
    if [ "$name" = "lpe-2026" ] && [[ "$lower" == *"fuera de soporte"* ]]; then
      append_unique critical "$name: $finding"
    else
      append_unique finding "$name: $finding"
    fi
  done <<< "$clean"
}

run_audit_module() {
  local name="$1" script="" output="" rc=0
  shift
  local -a args=("$@")

  case "$name" in
    aide)              script="aide-install.sh" ;;
    audit-listeners)   script="audit-listening-services.sh" ;;
    auditd-full)       script="auditd-hardening.sh" ;;
    bash-full)         script="bash-hardening.sh" ;;
    time-sync)         script="configure-time-sync.sh" ;;
    cpu-full)          script="cpu-hardening.sh" ;;
    cron-full)         script="cron-hardening.sh" ;;
    usb-storage)       script="disable-usb-storage.sh" ;;
    grub-full)         script="grub-hardening.sh" ;;
    kernel-full)       script="kernel-hardening.sh" ;;
    lpe-2026)          script="kernel-lpe-2026-mitigation.sh"; args=(--check) ;;
    network-full)      script="network-hardening.sh"; args=(--check) ;;
    password-full)     script="password-hardening.sh" ;;
    gui-remove)        script="remove-gui-hardening.sh"; args=(--check) ;;
    xinetd-remove)     script="remove-xinetd.sh" ;;
    rsyslog-full)      script="rsyslog-hardening.sh" ;;
    ssh-cis)           script="ssh-hardening.sh" ;;
    ssh-complete)      script="ssh-hardening-complete.sh" ;;
    sudo-full)         script="sudo-hardening.sh" ;;
    filesystem-full)   script="FS-hardening.sh"; args=(--check) ;;
    *)
      warn "Módulo no reconocido para auditoría de solo lectura: $name"
      ERRORS=$((ERRORS + 1))
      return 1
      ;;
  esac

  if [ ! -f "$SCRIPT_DIR/$script" ]; then
    warn "No existe $SCRIPT_DIR/$script; se omite $name."
    ERRORS=$((ERRORS + 1))
    return 1
  fi

  local skip_reason=""
  if [[ "$OS_MAJOR" =~ ^[0-9]+$ ]] && [ "$OS_MAJOR" -lt 7 ]; then
    case "$name" in
      ssh-complete) skip_reason="declara soporte para RHEL/CentOS/Rocky/AlmaLinux 7-10" ;;
    esac
    if [ -n "$skip_reason" ]; then
      echo
      echo "========== AUDITORÍA: $name ($script) =========="
      echo "[N/A] $script $skip_reason; se omite en ${OS_NAME:-EL $OS_VERSION} para evitar conclusiones falsas."
      MODULES_SKIPPED=$((MODULES_SKIPPED + 1))
      return 0
    fi
  fi

  echo
  echo "========== AUDITORÍA: $name ($script) =========="
  MODULES_RUN=$((MODULES_RUN + 1))

  # Capturar cada ejecución en memoria permite consolidar solo los hallazgos
  # de los módulos, sin crear archivos temporales ni reportes persistentes.
  if output="$(bash "$SCRIPT_DIR/$script" "${args[@]}" 2>&1)"; then
    rc=0
  else
    rc=$?
  fi

  printf '%s\n' "$output"
  collect_supplemental_findings "$name" "$output"

  if [ "$rc" -eq 0 ]; then
    ok "Módulo $name finalizado"
  else
    warn "Módulo $name terminó con código distinto de cero (rc=$rc); revisar la salida."
    ERRORS=$((ERRORS + 1))
  fi
}

print_final_summary() {
  local item

  echo
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE} RESUMEN DE AUDITORÍA DE MÓDULOS DE HARDENING${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo "Módulos ejecutados: $MODULES_RUN"
  echo "Módulos omitidos por compatibilidad: $MODULES_SKIPPED"
  echo "Errores de ejecución del auditor: $ERRORS"

  echo
  echo "HALLAZGOS CRÍTICOS DE MÓDULOS (${#SUPPLEMENTAL_CRITICAL[@]}):"
  if [ "${#SUPPLEMENTAL_CRITICAL[@]}" -eq 0 ]; then
    echo "  - Ninguno reportado."
  else
    for item in "${SUPPLEMENTAL_CRITICAL[@]}"; do
      echo "  - $item"
    done
  fi

  echo
  echo "HALLAZGOS NO CRÍTICOS DE MÓDULOS: ${#SUPPLEMENTAL_FINDINGS[@]}"
  echo
  echo "El benchmark CIS no se ejecutó ni forma parte de estos conteos."
  echo "Para evaluar exclusivamente el benchmark CIS, ejecuta: ./cis-benchmark-check.sh"
  echo
  echo "Auditoría de solo lectura: no se aplicaron correcciones ni se crearon backups."
  echo -e "${BLUE}============================================================${NC}"
}

main() {
  require_root
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      *) die "Opción desconocida: $1. Esta auditoría solo acepta --help." ;;
    esac
    shift
  done

  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE} OrangeBox Linux Hardening Audit $SCRIPT_VERSION${NC}"
  echo -e "${BLUE} MODO ESTRICTO DE AUDITORÍA: no aplicar cambios${NC}"
  echo -e "${BLUE}============================================================${NC}"

  detect_os
  [ -n "$OS_NAME" ] && echo "Sistema detectado: $OS_NAME"
  echo "Directorio de trabajo: $SCRIPT_DIR"
  echo "No se crean backups ni reportes persistentes; hallazgos en pantalla."

  local name
  for name in \
    aide audit-listeners auditd-full bash-full time-sync cpu-full cron-full \
    usb-storage grub-full kernel-full lpe-2026 network-full password-full \
    gui-remove xinetd-remove rsyslog-full ssh-cis ssh-complete sudo-full filesystem-full
  do
    run_audit_module "$name"
  done

  print_final_summary
  [ "$ERRORS" -eq 0 ]
}

main "$@"
