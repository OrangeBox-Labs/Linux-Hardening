#!/usr/bin/env bash
# OrangeBox SELinux status audit.
# Policy: Linux-Hardening must never change SELinux mode, configuration,
# contexts, packages, or trigger a reboot.
set -u

printf '%s\n' 'OrangeBox SELinux - solo auditoría de estado (sin cambios)'

if command -v getenforce >/dev/null 2>&1; then
  mode="$(getenforce 2>/dev/null || printf '%s' 'desconocido')"
  case "$mode" in
    Enforcing)
      printf '[OK] SELinux está %s. No se modifica.\n' "$mode"
      ;;
    Permissive)
      printf '[WARN] SELinux está %s. Requiere revisión; este script no lo cambia.\n' "$mode"
      ;;
    Disabled)
      printf '[WARN] SELinux está %s. Requiere revisión; este script no lo habilita ni solicita reinicio.\n' "$mode"
      ;;
    *)
      printf '[WARN] No se pudo determinar el modo actual de SELinux; no se modifica.\n'
      ;;
  esac
else
  printf '[WARN] getenforce no está disponible; no se puede comprobar el modo. No se instala ningún paquete.\n'
fi

if [ -r /etc/selinux/config ]; then
  configured="$(awk -F= '/^[[:space:]]*SELINUX[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' /etc/selinux/config)"
  printf '[INFO] SELINUX configurado en /etc/selinux/config: %s (solo lectura).\n' "${configured:-no definido}"
else
  printf '[INFO] /etc/selinux/config no está disponible; no se crea ni modifica.\n'
fi

printf '%s\n' 'Política OrangeBox: este módulo informa el estado y nunca modifica SELinux.'
exit 0
