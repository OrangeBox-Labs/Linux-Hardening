#!/usr/bin/env bash
# OrangeBox SELinux audit and carefully gated transition to Enforcing.
# Disabled SELinux is never enabled automatically: that requires a planned relabel/reboot.
set -u

ACTION="${1:-}"
case "$ACTION" in
  ""|--check|-c) AUTO_FIX=false ;;
  --fix|-f) AUTO_FIX=true ;;
  --help|-h)
    cat <<'EOF'
Uso:
  ./selinux-secure-setup.sh          Auditoría de solo lectura
  ./selinux-secure-setup.sh --check  Auditoría de solo lectura
  ./selinux-secure-setup.sh --fix    Cambiar a Enforcing solo tras confirmación

El modo --fix no instala paquetes, no cambia contextos y no reinicia.
Nunca habilita automáticamente SELinux cuando el estado runtime/configurado es Disabled.
EOF
    exit 0
    ;;
  *) echo "[ERROR] Opción desconocida: $ACTION" >&2; exit 2 ;;
esac

confirm_selinux_change() {
  local effect="$1" answer=""
  printf '\n[WARN] Cambio SELinux propuesto: %s\n' "$effect"
  printf '%s\n' "Qué hace: SELinux Enforcing aplica las políticas MAC."
  printf '%s\n' "Riesgo: aplicaciones sin política/contextos adecuados pueden quedar bloqueadas; confirme consola de recuperación y acceso alternativo."
  printf '%s' "¿Confirmas este cambio? [s/N]: "
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    printf '\n[WARN] No hay terminal interactiva; se omite el cambio por seguridad.\n'
    return 1
  fi
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in s|S|si|SI|sí|Sí|SÍ) return 0 ;; *) printf '[INFO] No se aplicó el cambio SELinux.\n'; return 1 ;; esac
}

audit_selinux() {
  local mode="desconocido" configured="no definido"
  if command -v getenforce >/dev/null 2>&1; then
    mode="$(getenforce 2>/dev/null || printf '%s' 'desconocido')"
    case "$mode" in
      Enforcing) printf '[OK] SELinux está %s en runtime.\n' "$mode" ;;
      Permissive) printf '[WARN] SELinux está Permissive; las denegaciones se registran, pero no se aplican.\n' ;;
      Disabled) printf '[WARN] SELinux está Disabled; habilitarlo requiere planificación de relabel y reinicio. No se hará automáticamente.\n' ;;
      *) printf '[WARN] No se pudo determinar el modo runtime de SELinux.\n' ;;
    esac
  else printf '[WARN] getenforce no está disponible; no se instala ningún paquete.\n'; fi
  if [ -r /etc/selinux/config ]; then
    configured="$(awk -F= '/^[[:space:]]*SELINUX[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/selinux/config)"
    configured="${configured:-no definido}"
    if [ "$configured" = "enforcing" ]; then printf '[OK] SELINUX=enforcing configurado persistentemente.\n'
    else printf '[WARN] SELINUX configurado en /etc/selinux/config: %s.\n' "$configured"; fi
  else printf '[WARN] /etc/selinux/config no está disponible; no se crea ni modifica.\n'; fi
}

apply_selinux_fix() {
  local mode="desconocido" configured="" backup_dir="" backup_file="" tmp=""
  command -v getenforce >/dev/null 2>&1 || { echo '[WARN] getenforce no disponible; no se cambia SELinux.'; return 1; }
  [ -r /etc/selinux/config ] && [ -f /etc/selinux/config ] && [ ! -L /etc/selinux/config ] || {
    echo '[WARN] /etc/selinux/config no es un archivo regular legible; no se modifica.'
    return 1
  }
  mode="$(getenforce 2>/dev/null || printf '%s' 'desconocido')"
  configured="$(awk -F= '/^[[:space:]]*SELINUX[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/selinux/config)"
  configured="${configured:-no definido}"
  if [ "$mode" = "Disabled" ] || [ "$configured" = "disabled" ]; then
    echo '[WARN] SELinux está Disabled o configurado como disabled. No se habilita automáticamente: requiere planificar relabel, reinicio y consola de recuperación.'
    return 0
  fi
  if [ "$mode" != "Enforcing" ] && [ "$mode" != "Permissive" ]; then
    echo "[WARN] Estado SELinux '$mode' no reconocido; no se aplica ningún cambio."
    return 1
  fi
  if [ "$mode" = "Enforcing" ] && [ "$configured" = "enforcing" ]; then
    echo '[OK] SELinux ya está Enforcing en runtime y configuración persistente.'
    return 0
  fi
  local effect=""
  if [ "$mode" = "Permissive" ] && [ "$configured" != "enforcing" ]; then effect="establecer SELINUX=enforcing persistentemente y ejecutar setenforce 1 ahora"
  elif [ "$mode" = "Permissive" ]; then effect="ejecutar setenforce 1 ahora (SELINUX ya está configurado como enforcing)"
  else effect="cambiar /etc/selinux/config a SELINUX=enforcing para el próximo reinicio"; fi
  confirm_selinux_change "$effect" || return 0

  if [ "$configured" != "enforcing" ]; then
    backup_dir="/var/backups/orangebox-selinux-hardening-$(date +%Y%m%d-%H%M%S)-$$"
    if ! mkdir -p "$backup_dir" || ! chmod 700 "$backup_dir" || ! cp -p /etc/selinux/config "$backup_dir/selinux.config"; then
      echo '[ERROR] No se pudo respaldar /etc/selinux/config; no se modifica.'
      return 1
    fi
    backup_file="$backup_dir/selinux.config"
    tmp="$(mktemp /etc/selinux/config.orangebox.XXXXXX)" || { echo '[ERROR] No se pudo crear temporal para la configuración.'; return 1; }
    if ! awk '
      /^[[:space:]]*SELINUX[[:space:]]*=/ { if (!done) print "SELINUX=enforcing"; done=1; next }
      { print }
      END { if (!done) print "SELINUX=enforcing" }
    ' /etc/selinux/config > "$tmp"; then rm -f "$tmp"; echo '[ERROR] No se pudo preparar la configuración SELinux.'; return 1; fi
    chmod --reference=/etc/selinux/config "$tmp" 2>/dev/null || chmod 644 "$tmp"
    chown --reference=/etc/selinux/config "$tmp" 2>/dev/null || chown root:root "$tmp"
    if ! mv "$tmp" /etc/selinux/config; then rm -f "$tmp"; echo '[ERROR] No se pudo instalar la configuración.'; return 1; fi
    echo "[OK] SELINUX=enforcing configurado persistentemente. Backup: $backup_file"
  fi
  if [ "$mode" = "Permissive" ]; then
    if ! setenforce 1 || [ "$(getenforce 2>/dev/null)" != "Enforcing" ]; then
      echo '[ERROR] No se pudo verificar SELinux Enforcing tras setenforce; se intentará restaurar el estado anterior.'
      setenforce 0 >/dev/null 2>&1 || true
      if [ -n "$backup_file" ]; then cp -p "$backup_file" /etc/selinux/config; fi
      return 1
    fi
    echo '[OK] SELinux cambió a Enforcing en runtime.'
  fi
  echo '[INFO] No se instalaron paquetes, no se modificaron contextos y no se reinició el sistema.'
  return 0
}

echo 'OrangeBox SELinux - auditoría y remediación con confirmación'
audit_selinux
if [ "$AUTO_FIX" = true ]; then apply_selinux_fix; fi
exit 0
