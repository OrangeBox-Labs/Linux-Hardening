#!/usr/bin/env bash
# OrangeBox SELinux audit-only policy.
# SELinux is intentionally never enabled/changed by this repository's hardening.
set -u

ACTION="${1:-}"
FIX_REQUESTED=false
case "$ACTION" in
  ""|--check|-c) ;;
  --fix|-f)
    # Preserve CLI compatibility, but explicitly refuse to mutate SELinux.
    FIX_REQUESTED=true
    ;;
  --help|-h)
    cat <<'EOF'
Uso:
  ./selinux-secure-setup.sh          Auditoría de solo lectura
  ./selinux-secure-setup.sh --check  Auditoría de solo lectura
  ./selinux-secure-setup.sh --fix    Solo auditoría; no modifica SELinux

Política OrangeBox:
  SELinux únicamente se comprueba y genera advertencias.
  No se ejecuta setenforce, no se modifica /etc/selinux/config,
  no se instalan paquetes, no se relabela y no se reinicia.
EOF
    exit 0
    ;;
  *) echo "[ERROR] Opción desconocida: $ACTION" >&2; exit 2 ;;
esac

audit_selinux() {
  local mode="desconocido" configured="no definido" configured_lc=""
  if command -v getenforce >/dev/null 2>&1; then
    mode="$(getenforce 2>/dev/null || printf '%s' 'desconocido')"
    case "$mode" in
      Enforcing)
        printf '[OK] SELinux está Enforcing en runtime.\n'
        ;;
      Permissive)
        printf '[WARN] SELinux está Permissive: registra denegaciones, pero no aplica la política. OrangeBox no cambia el estado.\n'
        ;;
      Disabled)
        printf '[WARN] SELinux está Disabled; requiere planificación independiente si se desea habilitar. OrangeBox no lo cambiará.\n'
        ;;
      *)
        printf '[WARN] No se pudo determinar el modo runtime de SELinux.\n'
        ;;
    esac
  else
    printf '[WARN] getenforce no está disponible; no se instala ningún paquete.\n'
  fi

  if [ -r /etc/selinux/config ]; then
    configured="$(awk -F= '/^[[:space:]]*SELINUX[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/selinux/config)"
    configured="${configured:-no definido}"
    configured_lc="$(printf '%s' "$configured" | tr '[:upper:]' '[:lower:]')"
    if [ "$configured_lc" = "enforcing" ]; then
      printf '[OK] SELINUX=enforcing está configurado persistentemente.\n'
    else
      printf '[WARN] SELINUX configurado en /etc/selinux/config: %s. No se modifica.\n' "$configured"
    fi
  else
    printf '[WARN] /etc/selinux/config no está disponible; no se crea ni modifica.\n'
  fi
}

printf '%s\n' 'OrangeBox SELinux - auditoría estrictamente de solo lectura'
if [ "$FIX_REQUESTED" = true ]; then
  printf '%s\n' '[INFO] --fix no aplica cambios SELinux por política OrangeBox; se ejecutará únicamente la auditoría.'
fi
audit_selinux
exit 0
