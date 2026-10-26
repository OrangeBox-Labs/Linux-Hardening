#!/usr/bin/env bash
# Common interactive consent helper for high-impact Linux hardening changes.
# Callers remain responsible for auditing the current state and backing up files.

ob_confirm_hardening_change() {
  local title="$1" current="$2" proposed="$3" impact="$4" answer=""
  printf '\n[WARN] Cambio de hardening pendiente: %s\n' "$title"
  printf 'Valor/estado actual: %s\n' "${current:-no verificado}"
  printf 'Propuesta: %s\n' "$proposed"
  printf 'Qué hace y posible impacto: %s\n' "$impact"

  if [ "${AUTO_FIX:-false}" != true ]; then
    printf '[INFO] Modo auditoría; no se modifica el sistema.\n'
    return 1
  fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    printf '[WARN] No hay terminal interactiva; se omite el cambio para evitar aprobación implícita.\n'
    return 1
  fi

  printf '%s' "¿Aplicar este cambio? [s/N]: "
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) printf '[INFO] Cambio rechazado; se conserva la configuración actual.\n'; return 1 ;;
  esac
}
