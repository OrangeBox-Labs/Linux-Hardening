#!/usr/bin/env bash
# OrangeBox Linux Hardening - auditoría agregada estrictamente de solo lectura.
# Este script únicamente invoca los modos de verificación de los módulos.
# No crea backups, no instala paquetes y no aplica correcciones.
# Sin 'set -u': mantiene compatibilidad con Bash 4.4 (CentOS/RHEL 8)
# al expandir arrays vacíos de argumentos de auditoría.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_VERSION="1.0.0"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'
MODULES_RUN=0
ERRORS=0

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

require_root() {
  [ "${EUID}" -eq 0 ] || die "Ejecuta esta auditoría como root para obtener resultados completos."
}

usage() {
  cat <<EOF
OrangeBox Linux Hardening Audit $SCRIPT_VERSION

Uso:
  $0             Ejecuta la auditoría agregada de solo lectura.
  $0 --help      Muestra esta ayuda.

Este programa NO aplica hardening ni ejecuta opciones --fix.
No crea backups ni reportes persistentes. El informe CIS se muestra
por pantalla y su salida de archivo se dirige a /dev/null.

No se ejecutan módulos que instalan/eliminan paquetes, preparan hosts,
modifican SELinux sin un modo de verificación garantizado o generan
reglas de firewall destructivas.
EOF
}

run_audit_module() {
  local name="$1" script="" report_cis=false
  shift
  local -a args=("$@")

  case "$name" in
    aide)              script="aide-install.sh" ;;
    audit-listeners)   script="audit-listening-services.sh" ;;
    auditd-full)       script="auditd-hardening.sh" ;;
    bash-full)         script="bash-hardening.sh" ;;
    cis)               script="cis-benchmark-check.sh"; report_cis=true ;;
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

  echo
  echo "========== AUDITORÍA: $name ($script) =========="
  MODULES_RUN=$((MODULES_RUN + 1))

  # CIS normalmente persiste un reporte en el directorio actual. Redirigimos
  # ese archivo a /dev/null para que la auditoría agregada no escriba archivos.
  if [ "$report_cis" = true ]; then
    if ORANGEBOX_CIS_REPORT_FILE=/dev/null bash "$SCRIPT_DIR/$script" "${args[@]}"; then
      ok "Módulo $name finalizado"
    else
      warn "Módulo $name terminó con código distinto de cero; revisar la salida."
      ERRORS=$((ERRORS + 1))
    fi
  elif bash "$SCRIPT_DIR/$script" "${args[@]}"; then
    ok "Módulo $name finalizado"
  else
    warn "Módulo $name terminó con código distinto de cero; revisar la salida."
    ERRORS=$((ERRORS + 1))
  fi
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

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "Sistema detectado: ${PRETTY_NAME:-${ID:-Linux} ${VERSION_ID:-}}"
  fi
  echo "Directorio de trabajo: $SCRIPT_DIR"
  echo "No se crean backups ni reportes persistentes; hallazgos en pantalla."

  local name
  for name in \
    aide audit-listeners auditd-full bash-full cis time-sync cpu-full cron-full \
    usb-storage grub-full kernel-full lpe-2026 network-full password-full \
    gui-remove xinetd-remove rsyslog-full ssh-cis ssh-complete sudo-full filesystem-full
  do
    run_audit_module "$name"
  done

  echo
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE} OrangeBox Linux Hardening Audit - FIN${NC}"
  echo "Módulos ejecutados: $MODULES_RUN"
  echo "Errores de ejecución de módulos: $ERRORS"
  echo "Estos contadores no suman los hallazgos internos; revisar cada resumen."
  echo "No se aplicaron correcciones ni se creó backup desde este auditor."
  echo -e "${BLUE}============================================================${NC}"
  [ "$ERRORS" -eq 0 ]
}

main "$@"
