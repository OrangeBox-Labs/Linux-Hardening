#!/usr/bin/env bash
# Herramienta exclusiva para cambiar SELinux a Permissive.
# Este script no forma parte de linux-hardening.sh ni se invoca desde el baseline.
set -u

ACTION="\${1:---check}"
FIX=false
case "$ACTION" in
  ""|--check|-c) FIX=false ;;
  --fix|-f) FIX=true ;;
  --help|-h)
    cat <<'EOF'
Uso:
  ./selinux-secure-setup.sh          Auditoría de solo lectura
  ./selinux-secure-setup.sh --check  Auditoría de solo lectura
  ./selinux-secure-setup.sh --fix    Solicita confirmación y cambia SELinux a Permissive

El modo --fix respalda /etc/selinux/config, cambia SELINUX=permissive
y, si SELinux está activo, aplica setenforce 0. No reinicia ni relabela.
Si SELinux está Disabled o el kernel usa selinux=0, puede requerirse
planificar un cambio de arranque y reinicio por separado.
EOF
    exit 0
    ;;
  *) echo "[ERROR] Opción desconocida: $ACTION" >&2; exit 2 ;;
esac

CONFIG="/etc/selinux/config"
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'

runtime_state() {
  if command -v getenforce >/dev/null 2>&1; then
    getenforce 2>/dev/null || printf '%s' "Unknown"
  else
    printf '%s' "Unknown"
  fi
}

configured_state() {
  [ -r "$CONFIG" ] || { printf '%s' "no definido"; return; }
  awk -F= '/^[[:space:]]*SELINUX[[:space:]]*=/ {gsub(/[[:space:]]/, "", $2); value=tolower($2)} END {if (value=="") print "no definido"; else print value}' "$CONFIG"
}

report_state() {
  local runtime configured
  runtime="$(runtime_state)"
  configured="$(configured_state)"
  echo -e "\n\${BLUE}[MÓDULO] SELinux independiente | Auditoría / cambio explícito\${NC}"
  echo "Estado runtime: $runtime"
  echo "Configuración persistente: SELINUX=$configured"
  if [ "$runtime" = "Permissive" ] && [ "$configured" = "permissive" ]; then
    echo -e "\${GREEN}[OK] SELinux ya está en Permissive y queda persistido.\${NC}"
  elif [ "$runtime" = "Enforcing" ]; then
    echo -e "\${YELLOW}[INFO] SELinux aplica políticas ahora; pasar a Permissive dejará de bloquear accesos, aunque seguirá registrando denegaciones.\${NC}"
  elif [ "$runtime" = "Disabled" ]; then
    echo -e "\${YELLOW}[WARN] SELinux está Disabled: cambiar la configuración no activa el estado runtime hasta un arranque planificado.\${NC}"
  fi
}

confirm_change() {
  local answer=""
  echo
  echo "Qué hace: SELinux Permissive registra las denegaciones, pero no bloquea las operaciones."
  echo "Riesgo: las políticas dejan de impedir accesos; aumenta la exposición hasta volver a Enforcing."
  printf '¿Cambiar SELinux a Permissive? [s/N]: '
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo
    echo "[WARN] No hay terminal interactiva; se omite el cambio."
    return 1
  fi
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;; *) echo "[INFO] Cambio rechazado."; return 1 ;; esac
}

main() {
  report_state
  [ "$FIX" = true ] || return 0
  [ "$EUID" -eq 0 ] || { echo "[ERROR] Ejecuta --fix como root." >&2; return 1; }
  [ -f "$CONFIG" ] && [ ! -L "$CONFIG" ] || {
    echo "[ERROR] $CONFIG no existe, no es un archivo regular o es un enlace simbólico; no se modifica."
    return 1
  }
  local runtime configured backup tmp mode owner_group before after
  runtime="$(runtime_state)"
  configured="$(configured_state)"
  if [ "$configured" = "permissive" ]; then
    case "$runtime" in
      Permissive) echo "[OK] No hay cambios pendientes."; return 0 ;;
      Disabled|Unknown)
        echo "[INFO] SELINUX=permissive ya está persistido; runtime=$runtime. No se modifica sin planificar el arranque."
        if [ -r /proc/cmdline ] && grep -qw "selinux=0" /proc/cmdline; then
          echo "[WARN] selinux=0 sigue deshabilitando SELinux desde el kernel."
        fi
        return 0
        ;;
    esac
  fi
  confirm_change || return 0

  backup="/root/selinux-backup-$(date +%Y%m%d-%H%M%S)-$BASHPID"
  if ! cp -p "$CONFIG" "$backup"; then
    echo "[ERROR] No se pudo respaldar $CONFIG; se aborta."
    return 1
  fi
  chmod 600 "$backup" || { rm -f "$backup"; echo "[ERROR] No se pudo proteger el backup."; return 1; }
  before="$(sha256sum "$CONFIG" 2>/dev/null | awk '{print $1}')"
  after="$(sha256sum "$backup" 2>/dev/null | awk '{print $1}')"
  if [ -z "$before" ] || [ "$before" != "$after" ]; then
    rm -f "$backup"
    echo "[ERROR] El backup no coincide con el archivo original; no se modifica."
    return 1
  fi

  tmp="$(mktemp /etc/selinux/.config.orangebox.XXXXXX)" || {
    echo "[ERROR] No se pudo crear archivo temporal; no se modifica SELinux."
    return 1
  }
  if ! awk '
    BEGIN { updated=0 }
    /^[[:space:]]*#/ { print; next }
    /^[[:space:]]*SELINUX[[:space:]]*=/ {
      if (!updated) print "SELINUX=permissive"
      updated=1
      next
    }
    { print }
    END { if (!updated) print "SELINUX=permissive" }
  ' "$CONFIG" > "$tmp"; then
    rm -f "$tmp"
    echo "[ERROR] No se pudo preparar SELINUX=permissive."
    return 1
  fi

  mode="$(stat -c '%a' "$CONFIG" 2>/dev/null || echo 644)"
  owner_group="$(stat -c '%u:%g' "$CONFIG" 2>/dev/null || echo 0:0)"
  if ! chmod "$mode" "$tmp" || ! chown "$owner_group" "$tmp" || ! mv -f "$tmp" "$CONFIG"; then
    rm -f "$tmp"
    echo "[ERROR] No se pudo actualizar $CONFIG; se conserva el estado runtime."
    return 1
  fi
  if [ "$(configured_state)" != "permissive" ]; then
    cp -p "$backup" "$CONFIG"
    echo "[ERROR] La configuración no quedó en permissive; se restauró el backup."
    return 1
  fi
  echo "[OK] SELINUX=permissive persistido. Backup: $backup"

  case "$runtime" in
    Enforcing)
      if command -v setenforce >/dev/null 2>&1 && setenforce 0 && [ "$(runtime_state)" = "Permissive" ]; then
        echo "[OK] Estado runtime cambiado a Permissive."
      else
        cp -p "$backup" "$CONFIG"
        setenforce 1 >/dev/null 2>&1 || true
        echo "[ERROR] No se pudo verificar Permissive; se restauró la configuración. Revisa el estado manualmente."
        return 1
      fi
      ;;
    Permissive)
      echo "[OK] Runtime ya estaba Permissive; se actualizó la persistencia."
      ;;
    Disabled|*)
      echo "[WARN] Runtime no está activo como SELinux; no se ejecuta setenforce. Puede requerir un arranque planificado."
      if [ -r /proc/cmdline ] && grep -qw 'selinux=0' /proc/cmdline; then
        echo "[WARN] Se detectó selinux=0 en /proc/cmdline; la configuración SELINUX=permissive no anulará ese parámetro."
      fi
      ;;
  esac
}

main "$@"
