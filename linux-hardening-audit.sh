#!/usr/bin/env bash
# OrangeBox Linux Hardening - auditoría agregada estrictamente de solo lectura.
# Este script únicamente invoca los modos de verificación de los módulos.
# No crea backups, no instala paquetes y no aplica correcciones.
# Sin 'set -u': mantiene compatibilidad con Bash 4.4 (CentOS/RHEL 8)
# al expandir arrays vacíos de argumentos de auditoría.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_VERSION="1.1.0"
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

CIS_SEEN=false
CIS_PASS_COUNT=0
CIS_FAIL_COUNT=0
CIS_WARN_COUNT=0
CIS_TOTAL_COUNT=0
CIS_SCORE="N/D"
declare -a CIS_CRITICAL_FINDINGS=()
declare -a CIS_WARNING_FINDINGS=()
declare -a SUPPLEMENTAL_CRITICAL=()
declare -a SUPPLEMENTAL_FINDINGS=()

strip_ansi() {
  sed -E 's/\\x1B\\[[0-9;]*[[:alpha:]]//g'
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

collect_cis_summary() {
  local output="$1" clean tenths whole decimal
  clean="$(printf '%s\\n' "$output" | strip_ansi)"

  CIS_PASS_COUNT="$(printf '%s\\n' "$clean" | sed -nE 's/.*Tests PASADOS:[[:space:]]*([0-9]+).*/\\1/p' | tail -n 1)"
  CIS_FAIL_COUNT="$(printf '%s\\n' "$clean" | sed -nE 's/.*Tests FALLADOS \\(CRITICOS\\):[[:space:]]*([0-9]+).*/\\1/p' | tail -n 1)"
  CIS_WARN_COUNT="$(printf '%s\\n' "$clean" | sed -nE 's/.*Tests WARNING:[[:space:]]*([0-9]+).*/\\1/p' | tail -n 1)"
  CIS_TOTAL_COUNT="$(printf '%s\\n' "$clean" | sed -nE 's/.*Total tests:[[:space:]]*([0-9]+).*/\\1/p' | tail -n 1)"

  [ -n "$CIS_PASS_COUNT" ] || CIS_PASS_COUNT=0
  [ -n "$CIS_FAIL_COUNT" ] || CIS_FAIL_COUNT=0
  [ -n "$CIS_WARN_COUNT" ] || CIS_WARN_COUNT=0
  [ -n "$CIS_TOTAL_COUNT" ] || CIS_TOTAL_COUNT=$((CIS_PASS_COUNT + CIS_FAIL_COUNT + CIS_WARN_COUNT))
  CIS_SEEN=true

  if [ "$CIS_TOTAL_COUNT" -gt 0 ]; then
    tenths=$(((CIS_PASS_COUNT * 1000 + CIS_TOTAL_COUNT / 2) / CIS_TOTAL_COUNT))
    whole=$((tenths / 10))
    decimal=$((tenths % 10))
    CIS_SCORE="${whole},${decimal}%"
  else
    CIS_SCORE="N/D"
  fi

  mapfile -t CIS_CRITICAL_FINDINGS < <(
    printf '%s\\n' "$clean" | awk '
      /\\[FAIL\\] / {
        title=$0
        sub(/^.*\\[FAIL\\] /, "", title)
        getline
        detail=$0
        gsub(/[[:space:]]+/, " ", title)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", detail)
        gsub(/[[:space:]]+/, " ", detail)
        if (title != "") {
          if (detail != "") print title " — " detail
          else print title
        }
      }'
  )
  mapfile -t CIS_WARNING_FINDINGS < <(
    printf '%s\\n' "$clean" | awk '
      /\\[WARN\\] [0-9]/ {
        title=$0
        sub(/^.*\\[WARN\\] /, "", title)
        getline
        detail=$0
        gsub(/[[:space:]]+/, " ", title)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", detail)
        gsub(/[[:space:]]+/, " ", detail)
        if (title != "") {
          if (detail != "") print title " — " detail
          else print title
        }
      }'
  )
}

collect_supplemental_findings() {
  local name="$1" output="$2" clean line finding lower
  [ "$name" = "cis" ] && return 0
  clean="$(printf '%s\\n' "$output" | strip_ansi)"

  while IFS= read -r line; do
    line="${line%$'\\r'}"
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

    # El fin de soporte de la distribución es un riesgo crítico independiente
    # del score CIS. Otros hallazgos no-CIS se muestran aparte sin severidad CIS.
    if [ "$name" = "lpe-2026" ] && [[ "$lower" == *"fuera de soporte"* ]]; then
      append_unique critical "$name: $finding"
    else
      append_unique finding "$name: $finding"
    fi
  done <<< "$clean"
}

run_audit_module() {
  local name="$1" script="" report_cis=false output="" rc=0
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

  # Capturar cada ejecución en memoria permite generar un resumen consolidado
  # sin crear archivos temporales ni reportes persistentes.
  if [ "$report_cis" = true ]; then
    if output="$(ORANGEBOX_CIS_REPORT_FILE=/dev/null bash "$SCRIPT_DIR/$script" "${args[@]}" 2>&1)"; then
      rc=0
    else
      rc=$?
    fi
  else
    if output="$(bash "$SCRIPT_DIR/$script" "${args[@]}" 2>&1)"; then
      rc=0
    else
      rc=$?
    fi
  fi

  printf '%s\\n' "$output"
  if [ "$report_cis" = true ]; then
    collect_cis_summary "$output"
  fi
  collect_supplemental_findings "$name" "$output"

  if [ "$rc" -eq 0 ]; then
    ok "Módulo $name finalizado"
  else
    warn "Módulo $name terminó con código distinto de cero (rc=$rc); revisar la salida."
    ERRORS=$((ERRORS + 1))
  fi
}

print_final_summary() {
  local pending=0 item
  echo
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE} RESUMEN EJECUTIVO DE SEGURIDAD${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo "Módulos ejecutados: $MODULES_RUN"
  echo "Errores de ejecución del auditor: $ERRORS"

  if [ "$CIS_SEEN" = true ] && [ "$CIS_TOTAL_COUNT" -gt 0 ]; then
    pending=$((CIS_FAIL_COUNT + CIS_WARN_COUNT))
    echo
    echo "CIS Benchmark:"
    echo "  Cumplimiento: $CIS_SCORE ($CIS_PASS_COUNT de $CIS_TOTAL_COUNT controles PASS; redondeado: $(((CIS_PASS_COUNT * 100 + CIS_TOTAL_COUNT / 2) / CIS_TOTAL_COUNT))%)"
    echo "  OK / PASS: $CIS_PASS_COUNT"
    echo "  CRÍTICOS / FAIL: $CIS_FAIL_COUNT"
    echo "  WARNING: $CIS_WARN_COUNT"
    echo "  Total de controles CIS: $CIS_TOTAL_COUNT"
    echo "  Controles CIS pendientes (FAIL + WARNING): $pending"
  else
    echo
    echo "CIS Benchmark: no se pudo obtener un resumen válido."
  fi

  echo
  echo "Hallazgos críticos adicionales fuera del score CIS: ${#SUPPLEMENTAL_CRITICAL[@]}"
  for item in "${SUPPLEMENTAL_CRITICAL[@]}"; do
    echo "  - $item"
  done

  echo
  echo "CONTROLES CIS CRÍTICOS / FAIL PENDIENTES (${#CIS_CRITICAL_FINDINGS[@]}):"
  if [ "${#CIS_CRITICAL_FINDINGS[@]}" -eq 0 ]; then
    echo "  - Ninguno reportado."
  else
    for item in "${CIS_CRITICAL_FINDINGS[@]}"; do
      echo "  - $item"
    done
  fi

  echo
  echo "CONTROLES CIS WARNING PENDIENTES (${#CIS_WARNING_FINDINGS[@]}):"
  if [ "${#CIS_WARNING_FINDINGS[@]}" -eq 0 ]; then
    echo "  - Ninguno reportado."
  else
    for item in "${CIS_WARNING_FINDINGS[@]}"; do
      echo "  - $item"
    done
  fi

  echo
  echo "HALLAZGOS COMPLEMENTARIOS DE OTROS MÓDULOS: ${#SUPPLEMENTAL_FINDINGS[@]}"
  echo "No se suman al score CIS porque los módulos pueden revisar controles solapados o criterios distintos."
  if [ "${#SUPPLEMENTAL_FINDINGS[@]}" -eq 0 ]; then
    echo "  - Ninguno reportado."
  else
    for item in "${SUPPLEMENTAL_FINDINGS[@]}"; do
      echo "  - $item"
    done
  fi

  echo
  echo "Solo auditoría: no se aplicaron correcciones ni se creó un backup desde el auditor."
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

  print_final_summary
  [ "$ERRORS" -eq 0 ]
}

main "$@"
