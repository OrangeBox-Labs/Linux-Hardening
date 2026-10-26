#!/bin/bash
# OrangeBox Linux Hardening - CIS 1.1.24
# Audit-only by default. --fix blocks future usb-storage module loads after consent.
# Never unload a currently loaded module: connected storage may be in use.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AUTO_FIX=false
FIXED=0
WARNINGS=0
CONF_FILE="/etc/modprobe.d/99-orangebox-disable-usb-storage.conf"
BACKUP_DIR="/root/usb-storage-backup-$(date +%Y%m%d-%H%M%S)"

fail() { echo -e "${RED}[ERROR] $* ${NC}" >&2; }

module_loaded() {
  lsmod 2>/dev/null | grep -Eq '^[[:space:]]*usb[_-]storage[[:space:]]'
}

module_effectively_blocked() {
  local output=""
  output="$(modprobe -n -v usb-storage 2>/dev/null || true)"
  printf '%s\n' "$output" | grep -Eq '^[[:space:]]*install[[:space:]]+/bin/(true|false)([[:space:]]|$)'
}

module_blacklisted() {
  modprobe -c 2>/dev/null | grep -Eiq '^[[:space:]]*blacklist[[:space:]]+usb[_-]storage([[:space:]]|$)'
}

confirm_usb_change() {
  local current="$1" proposed="$2" effect="$3" answer=""
  echo -e "${YELLOW}[WARN] Cambio de hardening USB pendiente${NC}"
  echo "Estado actual: $current"
  echo "Propuesta: $proposed"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "${YELLOW}[WARN] No hay terminal interactiva; no se modifica la configuración USB.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  printf '¿Aplicar este cambio? [s/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) echo -e "${YELLOW}[INFO] Cambio rechazado; se conserva la configuración actual.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1 ;;
  esac
}

audit_usb_storage() {
  local loaded="no" blocked="no" blacklisted="no" module_output=""
  echo -e "\n${BLUE}[*] CIS 1.1.24 - Auditoría de almacenamiento USB${NC}"

  if ! command -v modprobe >/dev/null 2>&1; then
    echo -e "${YELLOW}[N/A] modprobe no está disponible; no se puede comprobar el bloqueo del módulo.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  module_output="$(modprobe -n -v usb-storage 2>&1 || true)"
  if printf '%s\n' "$module_output" | grep -Eiq 'module usb[-_]storage not found|module not found'; then
    echo -e "${GREEN}[N/A] El módulo usb-storage no está disponible en este kernel.${NC}"
    return 0
  fi

  module_loaded && loaded="sí"
  module_effectively_blocked && blocked="sí"
  module_blacklisted && blacklisted="sí"

  echo "Módulo cargado actualmente: $loaded"
  echo "Carga bloqueada por modprobe: $blocked"
  echo "Blacklist configurada: $blacklisted"

  if [ "$blocked" = "sí" ] && [ "$blacklisted" = "sí" ]; then
    if [ "$loaded" = "sí" ]; then
      echo -e "${YELLOW}[WARN] El bloqueo persistente está configurado, pero el módulo ya está cargado. No se descarga en caliente; el estado runtime requiere mantenimiento/reinicio autorizado.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
    echo -e "${GREEN}[✓] Carga futura de usb-storage bloqueada y módulo no cargado.${NC}"
    return 0
  fi

  echo -e "${YELLOW}[WARN] usb-storage no está completamente bloqueado en la configuración persistente.${NC}"
  echo -e "  Efecto propuesto: impedir futuras cargas de almacenamiento masivo USB."
  echo -e "  Riesgo: pendrives, discos USB y ciertos medios externos de backup/recuperación dejarán de funcionar tras aplicar la regla."
  if [ "$loaded" = "sí" ]; then
    echo -e "  El módulo está cargado: esta herramienta no lo descarga ni interrumpe dispositivos en uso."
  fi
  WARNINGS=$((WARNINGS + 1))
  return 1
}

apply_usb_storage_block() {
  local current="" output="" tmp="" backup="" had_file=false mode="644"
  local effect="Bloquea futuras cargas del módulo de almacenamiento masivo USB mediante modprobe. Puede impedir el uso de discos/pendrives USB y medios externos de backup o recuperación. Si usb-storage está ya cargado, no se descarga en caliente; el bloqueo runtime requiere una ventana de mantenimiento/reinicio autorizada."

  if module_effectively_blocked && module_blacklisted && ! module_loaded; then
    echo -e "${GREEN}[✓] usb-storage ya está bloqueado; no se modifica.${NC}"
    return 0
  fi

  output="$(modprobe -n -v usb-storage 2>/dev/null || true)"
  if printf '%s\n' "$output" | grep -Eq '^[[:space:]]*install[[:space:]]+(?!/bin/(true|false))'; then
    echo -e "${YELLOW}[WARN] Existe una directiva install personalizada para usb-storage; no se sobrescribe automáticamente.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  current="loaded=$(module_loaded && echo yes || echo no), blocked=$(module_effectively_blocked && echo yes || echo no), blacklist=$(module_blacklisted && echo yes || echo no)"
  if ! confirm_usb_change "$current" "install usb-storage /bin/true y blacklist usb_storage en $CONF_FILE" "$effect"; then return 1; fi

  if [ -L "$CONF_FILE" ] || { [ -e "$CONF_FILE" ] && [ ! -f "$CONF_FILE" ]; }; then
    echo -e "${RED}[WARN] $CONF_FILE no es un archivo regular seguro; no se modifica.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if ! mkdir -p /etc/modprobe.d || ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[WARN] No se pudo preparar la configuración/backup; no se modifica.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ -f "$CONF_FILE" ]; then
    had_file=true
    mode="$(stat -c '%a' "$CONF_FILE" 2>/dev/null || echo 644)"
    backup="$BACKUP_DIR/$(basename "$CONF_FILE").bak"
    if ! cp -p "$CONF_FILE" "$backup"; then
      echo -e "${RED}[WARN] No se pudo respaldar $CONF_FILE; no se modifica.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  fi

  tmp="$(mktemp /etc/modprobe.d/.orangebox-usb-storage.XXXXXX)" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  if [ -f "$CONF_FILE" ]; then
    cat "$CONF_FILE" > "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  fi
  if ! grep -Eq '^[[:space:]]*install[[:space:]]+usb[-_]storage[[:space:]]+/bin/(true|false)([[:space:]]|$)' "$tmp"; then
    printf '\n# OrangeBox CIS 1.1.24: block future usb-storage loads\ninstall usb-storage /bin/true\n' >> "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  fi
  if ! grep -Eq '^[[:space:]]*blacklist[[:space:]]+usb[_-]storage([[:space:]]|$)' "$tmp"; then
    printf 'blacklist usb_storage\n' >> "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  fi
  chmod "$mode" "$tmp" && chown root:root "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  if ! mv "$tmp" "$CONF_FILE"; then
    rm -f "$tmp"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if module_effectively_blocked && module_blacklisted; then
    echo -e "${GREEN}[✓] Bloqueo persistente de usb-storage configurado y validado.${NC}"
    FIXED=$((FIXED + 1))
    if module_loaded; then
      echo -e "${YELLOW}[WARN] usb-storage sigue cargado en runtime. No se ejecutó rmmod; programe la descarga/reanudación en una ventana de mantenimiento.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    return 0
  fi

  echo -e "${RED}[WARN] No se validó el bloqueo tras escribir $CONF_FILE.${NC}"
  if [ "$had_file" = true ] && [ -f "$backup" ]; then cp -p "$backup" "$CONF_FILE"; else rm -f "$CONF_FILE"; fi
  WARNINGS=$((WARNINGS + 1))
  return 1
}

main() {
  if [ "$EUID" -ne 0 ]; then fail "Ejecuta como root."; exit 1; fi
  case "${1:-}" in
    "") AUTO_FIX=false ;;
    --fix|-f) AUTO_FIX=true ;;
    --help|-h)
      echo "Uso: $0 [--fix]"
      echo "Sin opciones: auditoría de solo lectura."
      exit 0
      ;;
    *) fail "Opción desconocida: $1"; exit 2 ;;
  esac

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN} OrangeBox - Hardening de almacenamiento USB ${NC}"
  echo -e "${GREEN}============================================${NC}"
  audit_usb_storage
  if [ "$AUTO_FIX" = true ]; then apply_usb_storage_block; fi
  echo -e "\n${GREEN}Resumen: cambios=$FIXED advertencias=$WARNINGS${NC}"
}

main "$@"
