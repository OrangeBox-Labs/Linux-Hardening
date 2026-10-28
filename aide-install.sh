#!/bin/bash
# OrangeBox Linux Hardening - AIDE integrity monitoring
# Audit-only by default. Every fix action is explained and requires terminal consent.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AUTO_FIX=false
FIXED=0
WARNINGS=0
AIDE_BIN=""
AIDE_DB="/var/lib/aide/aide.db.gz"
AIDE_NEW_DB="/var/lib/aide/aide.db.new.gz"
BACKUP_DIR="/root/aide-backup-$(date +%Y%m%d-%H%M%S)"

confirm_aide_change() {
  # AIDE siempre requiere consentimiento interactivo para instalar, inicializar o programar.
  # ORANGEBOX_ASSUME_YES del --fix global nunca autoriza estas acciones opcionales.
  local title="$1" current="$2" proposed="$3" effect="$4" answer=""
  echo -e "\n${YELLOW}[WARN] Acción AIDE pendiente: $title${NC}"
  echo "Estado actual: $current"
  echo "Propuesta: $proposed"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "${YELLOW}[WARN] No hay terminal interactiva; se omite esta acción de AIDE.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  printf '¿Aplicar esta acción? [s/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) echo -e "${YELLOW}[INFO] Acción rechazada; no se modifica AIDE.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1 ;;
  esac
}

prepare_backup_dir() {
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[WARN] No se pudo preparar $BACKUP_DIR; se cancela la modificación.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  return 0
}

aide_scheduled_check_present() {
  if crontab -u root -l 2>/dev/null | grep -Eq '(^|[[:space:]/])aide[[:space:]]+--check([[:space:]]|$)'; then
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1 &&
     systemctl is-enabled --quiet aidecheck.timer 2>/dev/null &&
     systemctl is-active --quiet aidecheck.timer 2>/dev/null; then
    return 0
  fi
  return 1
}

check_aide_installed() {
  echo -e "\n${BLUE}[*] CIS 1.3.1 - Verificando instalación de AIDE...${NC}"
  if rpm -q aide >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] AIDE instalado: $(rpm -q aide)${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] AIDE no está instalado.${NC}"
  local effect="Instala un paquete adicional y sus dependencias desde los repositorios configurados; aumenta la superficie de software y requiere mantenimiento de actualizaciones."
  if [ "$AUTO_FIX" != true ]; then
    echo "Qué hace/riesgo: $effect"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if ! confirm_aide_change "instalar paquete AIDE" "paquete ausente" "instalar aide con dnf/yum" "$effect"; then return 1; fi
  if command -v dnf >/dev/null 2>&1; then dnf install aide -y
  elif command -v yum >/dev/null 2>&1; then yum install aide -y
  else
    echo -e "${RED}[WARN] No hay dnf ni yum; AIDE no se instala.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if rpm -q aide >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] AIDE instalado y verificado.${NC}"
    FIXED=$((FIXED + 1))
    return 0
  fi
  echo -e "${RED}[WARN] No se pudo confirmar la instalación de AIDE.${NC}"
  WARNINGS=$((WARNINGS + 1))
  return 1
}

check_aide_database() {
  echo -e "\n${BLUE}[*] CIS 1.3.1 - Verificando base de referencia de AIDE...${NC}"
  if [ ! -x "$AIDE_BIN" ]; then
    echo -e "${YELLOW}[N/A] AIDE no está disponible; no se puede comprobar/inicializar la base.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ -s "$AIDE_DB" ]; then
    echo -e "${GREEN}[✓] Base de datos AIDE presente: $AIDE_DB${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] No existe una base de referencia inicializada en $AIDE_DB.${NC}"
  local effect="Recorre el sistema de archivos y calcula la base de integridad, usando CPU y E/S de disco. La base inicial confía en el estado actual: se debe inicializar solo después de revisar que el servidor esté limpio y autorizado."
  if [ "$AUTO_FIX" != true ]; then
    echo "Qué hace/riesgo: $effect"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ -e "$AIDE_NEW_DB" ]; then
    echo -e "${YELLOW}[WARN] Ya existe $AIDE_NEW_DB de una inicialización previa; se conserva para revisión y no se sobrescribe.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if ! confirm_aide_change "inicializar base de datos AIDE" "base ausente" "ejecutar '$AIDE_BIN --init' y promover aide.db.new.gz" "$effect"; then return 1; fi
  if ! prepare_backup_dir; then return 1; fi
  if "$AIDE_BIN" --init; then
    if [ -s "$AIDE_NEW_DB" ]; then
      if mv "$AIDE_NEW_DB" "$AIDE_DB" && [ -s "$AIDE_DB" ]; then
        echo -e "${GREEN}[✓] Base AIDE inicializada y verificada: $AIDE_DB${NC}"
        FIXED=$((FIXED + 1))
        return 0
      fi
    fi
  fi
  echo -e "${RED}[WARN] AIDE no produjo una base de datos válida; no se promueve el archivo nuevo.${NC}"
  WARNINGS=$((WARNINGS + 1))
  return 1
}

configure_periodic_check() {
  echo -e "\n${BLUE}[*] CIS 1.3.2 - Verificando comprobación periódica de AIDE...${NC}"
  if aide_scheduled_check_present; then
    echo -e "${GREEN}[✓] Comprobación periódica detectada en cron o aidecheck.timer activo.${NC}"
    return 0
  fi
  if [ ! -s "$AIDE_DB" ]; then
    echo -e "${YELLOW}[WARN] No se programa aide --check hasta disponer de una base de referencia válida.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  echo -e "${YELLOW}[WARN] No se detectó comprobación periódica de AIDE.${NC}"
  local effect="Añade una comprobación diaria de integridad a las 05:00. El escaneo puede usar CPU/E/S y competir con backups o ventanas batch; los resultados deben ser recogidos/revisados."
  if [ "$AUTO_FIX" != true ]; then
    echo "Qué hace/riesgo: $effect"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if ! confirm_aide_change "programar comprobación diaria de AIDE" "sin tarea detectada" "agregar '$AIDE_BIN --check' al crontab de root a las 05:00" "$effect"; then return 1; fi
  if ! command -v crontab >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] crontab no está disponible; no se modifica la programación.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if ! prepare_backup_dir; then return 1; fi

  local current="" new="" had_cron=false
  current="$(mktemp)" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  new="$(mktemp)" || { rm -f "$current"; WARNINGS=$((WARNINGS + 1)); return 1; }
  if crontab -u root -l > "$current" 2>/dev/null; then
    had_cron=true
  elif [ -f /var/spool/cron/root ]; then
    rm -f "$current" "$new"
    echo -e "${YELLOW}[WARN] El crontab de root existe pero no se pudo leer; no se sobrescribe.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  else
    : > "$current"
  fi
  if [ ! -f "$BACKUP_DIR/root.crontab.before" ]; then
    if ! cp "$current" "$BACKUP_DIR/root.crontab.before" || ! chmod 600 "$BACKUP_DIR/root.crontab.before" || ! chown root:root "$BACKUP_DIR/root.crontab.before"; then
      rm -f "$current" "$new"
      echo -e "${RED}[WARN] No se pudo respaldar el crontab de root; no se modifica.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  fi
  cat "$current" > "$new" || { rm -f "$current" "$new"; WARNINGS=$((WARNINGS + 1)); return 1; }
  printf '\n0 5 * * * %s --check\n' "$AIDE_BIN" >> "$new" || { rm -f "$current" "$new"; WARNINGS=$((WARNINGS + 1)); return 1; }
  if crontab -u root "$new" && crontab -u root -l 2>/dev/null | grep -Fq "$AIDE_BIN --check"; then
    echo -e "${GREEN}[✓] Comprobación diaria añadida al crontab de root; backup=$BACKUP_DIR/root.crontab.before${NC}"
    FIXED=$((FIXED + 1))
    rm -f "$current" "$new"
    return 0
  fi

  echo -e "${RED}[WARN] No se validó el nuevo crontab; se intenta restaurar el anterior.${NC}"
  if [ "$had_cron" = true ]; then
    crontab -u root "$current" >/dev/null 2>&1 || true
  else
    crontab -u root -r >/dev/null 2>&1 || true
  fi
  rm -f "$current" "$new"
  WARNINGS=$((WARNINGS + 1))
  return 1
}

show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  RESUMEN AIDE${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  if [ "$AUTO_FIX" = true ]; then echo "  • Backup de crontab (si se modificó): $BACKUP_DIR/root.crontab.before"; fi
}

main() {
  case "${1:-}" in
    --help|-h)
      echo "Uso: $0 [--fix]"
      echo "Sin opciones: auditoría de solo lectura; --fix pide confirmación por cada cambio."
      exit 0
      ;;
    --fix|-f) AUTO_FIX=true ;;
    "") AUTO_FIX=false ;;
    *) echo -e "${RED}[!] Opción desconocida: $1${NC}" >&2; exit 2 ;;
  esac
  if [ "$EUID" -ne 0 ]; then echo -e "${RED}[!] Ejecuta como root.${NC}" >&2; exit 1; fi

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  AIDE - Integridad de archivos CIS 1.3.x${NC}"
  echo -e "${GREEN}============================================${NC}"
  check_aide_installed
  if rpm -q aide >/dev/null 2>&1; then
    AIDE_BIN="$(command -v aide 2>/dev/null || true)"
    if [ -z "$AIDE_BIN" ]; then
      echo -e "${YELLOW}[WARN] El paquete está instalado pero no se localiza el ejecutable aide.${NC}"
      WARNINGS=$((WARNINGS + 1))
    else
      check_aide_database
      if [ -s "$AIDE_DB" ]; then configure_periodic_check; fi
    fi
  else
    echo -e "${YELLOW}[N/A] Sin AIDE instalado, no se inicializa base ni se programa cron.${NC}"
  fi
  show_summary
  return 0
}

main "$@"
