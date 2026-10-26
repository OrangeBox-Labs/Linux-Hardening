#!/usr/bin/env bash
# OrangeBox Linux Hardening - auditoría independiente de firewall y listeners.
# Solo lectura: no modifica reglas, gestores, servicios ni configuración.
set -u
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$SCRIPT_DIR/lib/firewall-detect.sh" ]; then
  # shellcheck source=lib/firewall-detect.sh
  source "$SCRIPT_DIR/lib/firewall-detect.sh"
else
  echo "[ERROR] Falta lib/firewall-detect.sh; actualice el repositorio completo." >&2
  exit 1
fi
if [ -r "$SCRIPT_DIR/lib/listener-firewall-audit.sh" ]; then
  # shellcheck source=lib/listener-firewall-audit.sh
  source "$SCRIPT_DIR/lib/listener-firewall-audit.sh"
else
  echo "[ERROR] Falta lib/listener-firewall-audit.sh; actualice el repositorio completo." >&2
  exit 1
fi
FIREWALL_WARNINGS=0
LFA_WARNINGS=0
usage() {
  cat <<EOF
Auditoría OrangeBox de firewall y listeners (solo lectura)
Uso:
  $0
  $0 --help
Detecta gestores y backends de firewall, inventaría sockets TCP/UDP y
contrasta listeners con reglas INPUT legibles. Nunca aplica cambios.
EOF
}
main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) usage; return 0 ;;
      *) echo "[ERROR] Opción desconocida: $1" >&2; return 2 ;;
    esac
    shift
  done
  [ "$EUID" -eq 0 ] || { echo "[ERROR] Ejecuta como root para obtener el inventario completo." >&2; return 1; }
  echo "============================================================"
  echo " OrangeBox - Auditoría de firewall y listeners (solo lectura)"
  echo "============================================================"
  firewall_report_detected
  lfa_audit_listener_firewall
  echo
  echo "Resumen de la auditoría independiente:"
  echo "Advertencias de gestores/backend: ${FIREWALL_WARNINGS:-0}"
  echo "Advertencias de listeners: ${LFA_WARNINGS:-0}"
  echo "No se modificaron reglas, gestores, servicios ni configuración."
}
if [ "$0" = "$BASH_SOURCE" ]; then
  main "$@"
fi
