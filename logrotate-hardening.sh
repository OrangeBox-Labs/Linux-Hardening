#!/usr/bin/env bash
# OrangeBox logrotate baseline: compressed logs with a bounded five-file rotation.
set -u

AUTO_FIX=false
LOGROTATE_CONF="/etc/logrotate.conf"
LOGROTATE_DIR="/etc/logrotate.d"
AUDITD_CONF="/etc/audit/auditd.conf"
AUDIT_RETENTION_SCRIPT="/etc/cron.daily/orangebox-audit-logrotate"
AUDIT_ROTATION_CONFLICT_FOUND=false
RUN_ID="$(date +%Y%m%d-%H%M%S)-$BASHPID"
BACKUP_DIR="/var/backups/orangebox-logrotate-hardening/$RUN_ID"
FIXED=0
WARNINGS=0
CHANGED_FILES=()
FILES=()

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

show_usage() {
  echo "Uso: $0 [--audit|--check|--fix]"
  echo "  --audit / --check  Solo informa qué reglas faltan o difieren."
  echo "  --fix              Aplica compress y rotate 5 sin solicitar confirmación."
}

normalize_file() {
  local file="$1"
  awk '
    function trim(s) {
      sub(/^[ \t]+/, "", s)
      sub(/[ \t]+$/, "", s)
      return s
    }
    BEGIN {
      inserted=0
      seen_stanza=0
      top_compress=0
      top_rotate=0
    }
    {
      line=$0
      body=trim(line)
      if (body !~ /^#/ && body != "") {
        if (body ~ /^nocompress([ \t]|$)/) {
          sub(/nocompress/, "compress", line)
          body=trim(line)
        }
        if (body ~ /^rotate[ \t]+[0-9]+([ \t]|$|#)/) {
          if (body !~ /^rotate[ \t]+5([ \t]|$|#)/) {
            sub(/rotate[ \t]+[0-9]+/, "rotate 5", line)
            body=trim(line)
          }
        }

        if (!seen_stanza) {
          if (body ~ /^compress([ \t]|$)/) top_compress=1
          if (body ~ /^rotate[ \t]+5([ \t]|$|#)/) top_rotate=1
        }

        if (!inserted && (body ~ /^include([ \t]|$)/ || body ~ /^[^# \t].*\{[ \t]*$/)) {
          if (!top_compress) print "compress"
          if (!top_rotate) print "rotate 5"
          inserted=1
          seen_stanza=1
        } else if (body ~ /^[^# \t].*\{[ \t]*$/) {
          seen_stanza=1
        }
      }
      print line
    }
    END {
      if (!inserted) {
        if (!top_compress) print "compress"
        if (!top_rotate) print "rotate 5"
      }
    }
  ' "$file"
}

make_backup_dir() {
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[ERROR] No se pudo preparar el directorio de respaldo: $BACKUP_DIR${NC}" >&2
    return 1
  fi
}

backup_one() {
  local file="$1" dest="" source_hash="" backup_hash=""

  # Assign the destination only after file has been initialized. In Bash,
  # expansions in one local declaration can see the caller's file variable.
  dest="$BACKUP_DIR$file"

  mkdir -p "$(dirname "$dest")" || {
    echo -e "${RED}[ERROR] No se pudo crear el directorio del backup para $file: $(dirname "$dest")${NC}" >&2
    return 1
  }
  cp -p "$file" "$dest" || {
    echo -e "${RED}[ERROR] No se pudo copiar $file al backup $dest${NC}" >&2
    return 1
  }
  source_hash="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')" || {
    echo -e "${RED}[ERROR] No se pudo calcular SHA256 del origen $file${NC}" >&2
    return 1
  }
  backup_hash="$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')" || {
    echo -e "${RED}[ERROR] No se pudo calcular SHA256 del backup $dest${NC}" >&2
    return 1
  }
  if [ -z "$source_hash" ] || [ "$source_hash" != "$backup_hash" ]; then
    echo -e "${RED}[ERROR] El backup no coincide con el archivo original: $file -> $dest${NC}" >&2
    return 1
  fi
}

restore_changed_files() {
  local file backup
  for file in "${CHANGED_FILES[@]}"; do
    backup="$BACKUP_DIR$file"
    if [ -f "$backup" ]; then
      cp -p "$backup" "$file" || echo -e "${RED}[ERROR] No se pudo restaurar $file desde $backup${NC}" >&2
    else
      # An absent backup means this managed file was created during this run.
      rm -f -- "$file" || echo -e "${RED}[ERROR] No se pudo retirar el archivo nuevo $file${NC}" >&2
    fi
  done
}

process_file() {
  local file="$1" tmp="" dest="" mode="" owner_group=""
  [ -f "$file" ] || return 0
  [ ! -L "$file" ] || {
    echo -e "${YELLOW}[WARN] Se omite enlace simbólico de logrotate: $file${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  }

  # Si existe una política específica de audit, no reescribir ni esa regla ni logrotate.conf
  # (sus directivas globales pueden heredarse desde la regla incluida).
  if [ "$AUDIT_ROTATION_CONFLICT_FOUND" = true ]; then
    if [ "$file" = "$LOGROTATE_CONF" ] || awk '
      /^[[:space:]]*#/ { next }
      /\/var\/log\/audit/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$file" 2>/dev/null; then
      echo -e "${YELLOW}[WARN] Se conserva $file porque participa en una política de rotación de audit existente.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 0
    fi
  fi

  if [ "$AUTO_FIX" = true ]; then
    # En modo fix, el temporal debe estar junto al destino para permitir
    # reemplazo atómico dentro del mismo filesystem.
    tmp="$(mktemp "$(dirname "$file")/.logrotate-orangebox.XXXXXX")" || {
      echo -e "${RED}[ERROR] No se pudo crear un temporal para $file${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    }
    if ! normalize_file "$file" > "$tmp"; then
      rm -f "$tmp"
      echo -e "${RED}[ERROR] No se pudo procesar $file${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
    if cmp -s "$file" "$tmp"; then
      rm -f "$tmp"
      echo -e "${GREEN}[OK] $file: compress y rotate 5 ya están configurados${NC}"
      return 0
    fi
  else
    # La auditoría compara el resultado por stdout; no crea archivos temporales
    # ni escribe dentro de /etc/logrotate.conf o /etc/logrotate.d.
    if cmp -s "$file" <(normalize_file "$file"); then
      echo -e "${GREEN}[OK] $file: compress y rotate 5 ya están configurados${NC}"
      return 0
    fi
    echo -e "${YELLOW}[PENDIENTE] $file: aplicar compress y rotate 5; se revisan también directivas locales nocompress/rotate.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if ! backup_one "$file"; then
    rm -f "$tmp"
    echo -e "${RED}[ERROR] Falló el backup de $file; no se modifica${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  mode="$(stat -c '%a' "$file" 2>/dev/null || echo 644)"
  owner_group="$(stat -c '%u:%g' "$file" 2>/dev/null || echo 0:0)"
  chmod "$mode" "$tmp" 2>/dev/null || { rm -f "$tmp"; WARNINGS=$((WARNINGS+1)); return 1; }
  chown "$owner_group" "$tmp" 2>/dev/null || { rm -f "$tmp"; WARNINGS=$((WARNINGS+1)); return 1; }
  if ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    echo -e "${RED}[ERROR] No se pudo reemplazar $file${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  CHANGED_FILES+=("$file")
  FIXED=$((FIXED + 1))
  echo -e "${GREEN}[OK] $file actualizado: compress + rotate 5${NC}"
}


# Detects an existing independent audit.log rotator before installing OrangeBox policy.
# Direct logrotate handling of audit.log is not replaced because auditd owns the open file.
audit_rotation_conflict() {
  local candidate=""
  for candidate in "$LOGROTATE_CONF" "$LOGROTATE_DIR"/*; do
    [ -f "$candidate" ] || continue
    [ "$candidate" = "$AUDIT_RETENTION_SCRIPT" ] && continue
    if awk '
      /^[[:space:]]*#/ { next }
      /\/var\/log\/audit([/[:space:]]|$|\*)/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  # Also detect packaged or administrator-created cron jobs that already signal auditd to rotate.
  for candidate in /etc/cron.daily/* /etc/cron.hourly/* /etc/cron.weekly/* /etc/cron.d/*; do
    [ -f "$candidate" ] || continue
    [ "$candidate" = "$AUDIT_RETENTION_SCRIPT" ] && continue
    if awk '
      /^[[:space:]]*#/ { next }
      /service[[:space:]]+auditd[[:space:]]+rotate/ ||
      /auditctl[[:space:]]+--signal[[:space:]]+rotate/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Creates a retention-only helper. auditd keeps its configured native rotation.
# The daily job removes only closed generations older than seven days and legacy OrangeBox archives.
write_audit_retention_script() {
  cat <<'AUDIT_RETENTION'
#!/usr/bin/env bash
set -euo pipefail

# ORANGEBOX_AUDIT_LOG_RETENTION
# Preserve auditd's native rotation; purge only closed generations older than seven days.
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:$PATH"
AUDIT_LOG_DIR="${ORANGEBOX_AUDIT_LOG_DIR:-/var/log/audit}"
KEEP_DAYS=7
KEEP_MINUTES=$((KEEP_DAYS * 1440))

log_message() {
  if command -v logger >/dev/null 2>&1; then
    logger -t orangebox-audit-retention -- "$*"
  fi
}

[ -d "$AUDIT_LOG_DIR" ] || exit 0
command -v find >/dev/null 2>&1 || {
  log_message "ERROR: find no está disponible; no se aplicó la retención."
  exit 1
}

# Solo borra generaciones cerradas audit.log.N y archivos del helper OrangeBox anterior.
# El archivo activo audit.log nunca coincide con estos patrones.
if ! deleted_count="$(find "$AUDIT_LOG_DIR" -regextype posix-extended -maxdepth 1 -type f \
  \( -regex '.*/audit\.log\.[0-9]+' -o -name 'audit.log.orangebox.*.gz' \) \
  -mmin "+$KEEP_MINUTES" -print -delete | wc -l)"; then
  log_message "ERROR: falló la purga de generaciones auditd antiguas."
  exit 1
fi

deleted_count="$(printf '%s' "$deleted_count" | tr -d '[:space:]')"
log_message "Retención diaria completada: archivos con más de siete días eliminados: ${deleted_count:-0}. La rotación nativa de auditd no fue modificada."
exit 0
AUDIT_RETENTION
}

# Cron must be running and enabled so the daily retention cleanup actually executes.
# EL7+ uses systemd; EL6 falls back to service/chkconfig.
audit_cron_scheduler_ready() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet crond.service &&
      systemctl is-enabled crond.service >/dev/null 2>&1
    return $?
  fi
  command -v service >/dev/null 2>&1 || return 1
  service crond status >/dev/null 2>&1 || return 1
  command -v chkconfig >/dev/null 2>&1 || return 1
  chkconfig --list crond 2>/dev/null | grep -Eq '3:on.*5:on'
}

# Installs daily cleanup without replacing auditd's native size-based rotation.
configure_audit_retention() {
  local conflict="" tmp="" mode="" owner_group=""
  local script_marker="# ORANGEBOX_AUDIT_LOG_RETENTION"
  local legacy_marker="# ORANGEBOX_AUDIT_LOG_ROTATION"

  if [ ! -f "$AUDITD_CONF" ] || [ -L "$AUDITD_CONF" ] || [ ! -d /var/log/audit ]; then
    echo -e "${BLUE}[INFO] auditd no está instalado/configurado; se omite la retención de sus logs.${NC}"
    return 0
  fi

  if ! command -v find >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] No se instala la retención audit: find no está disponible.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  conflict="$(audit_rotation_conflict || true)"
  if [ -n "$conflict" ]; then
    AUDIT_ROTATION_CONFLICT_FOUND=true
    echo -e "${YELLOW}[WARN] Se detectó otra política de rotación de audit en $conflict; no se instala una limpieza paralela.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if [ -L "$AUDIT_RETENTION_SCRIPT" ]; then
    AUDIT_ROTATION_CONFLICT_FOUND=true
    echo -e "${YELLOW}[WARN] $AUDIT_RETENTION_SCRIPT es un enlace simbólico; no se modifica.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if [ -e "$AUDIT_RETENTION_SCRIPT" ] &&
     ! grep -Fq "$script_marker" "$AUDIT_RETENTION_SCRIPT" &&
     ! grep -Fq "$legacy_marker" "$AUDIT_RETENTION_SCRIPT"; then
    AUDIT_ROTATION_CONFLICT_FOUND=true
    echo -e "${YELLOW}[WARN] $AUDIT_RETENTION_SCRIPT ya existe y no pertenece a OrangeBox; se conserva sin cambios.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if ! audit_cron_scheduler_ready; then
    echo -e "${YELLOW}[WARN] crond no está activo y habilitado; no se instala la limpieza diaria. Configure el scheduler y vuelva a ejecutar logrotate-hardening.sh --fix.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  [ "$AUTO_FIX" = true ] || {
    if [ -f "$AUDIT_RETENTION_SCRIPT" ] &&
       grep -Fq "$script_marker" "$AUDIT_RETENTION_SCRIPT" &&
       grep -Eq '^KEEP_DAYS=7$' "$AUDIT_RETENTION_SCRIPT" &&
       grep -Fq "audit\\.log\\.[0-9]+" "$AUDIT_RETENTION_SCRIPT" &&
       grep -Fq -- '-delete' "$AUDIT_RETENTION_SCRIPT" &&
       ! grep -Fq 'auditd rotate' "$AUDIT_RETENTION_SCRIPT" &&
       ! grep -Eq '(^|[[:space:]])gzip([[:space:]]|$)' "$AUDIT_RETENTION_SCRIPT"; then
      echo -e "${GREEN}[OK] Auditd: rotación nativa preservada y purga diaria de generaciones con más de siete días.${NC}"
    else
      echo -e "${YELLOW}[PENDIENTE] Auditd: falta instalar/actualizar la limpieza diaria de generaciones con más de siete días.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    return 0
  }

  mkdir -p /etc/cron.daily || return 1
  tmp="$(mktemp /etc/cron.daily/.orangebox-audit-retention.XXXXXX)" || return 1
  write_audit_retention_script > "$tmp" || { rm -f "$tmp"; return 1; }
  bash -n "$tmp" || { rm -f "$tmp"; echo -e "${RED}[ERROR] Sintaxis inválida en el helper de retención auditd.${NC}"; return 1; }

  if [ -f "$AUDIT_RETENTION_SCRIPT" ] && cmp -s "$tmp" "$AUDIT_RETENTION_SCRIPT"; then
    rm -f "$tmp"
  else
    if [ -f "$AUDIT_RETENTION_SCRIPT" ]; then
      backup_one "$AUDIT_RETENTION_SCRIPT" || { rm -f "$tmp"; return 1; }
    fi
    chmod 750 "$tmp" && chown root:root "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$AUDIT_RETENTION_SCRIPT" || { rm -f "$tmp"; return 1; }
    CHANGED_FILES+=("$AUDIT_RETENTION_SCRIPT")
    FIXED=$((FIXED + 1))
    echo -e "${GREEN}[OK] Helper diario de retención auditd instalado/actualizado en $AUDIT_RETENTION_SCRIPT.${NC}"
  fi

  echo -e "${GREEN}[OK] Retención auditd: siete días. No se solicita rotación adicional, no se comprimen las generaciones nuevas y no se modifica auditd.conf.${NC}"
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --fix|-f) AUTO_FIX=true; ORANGEBOX_ASSUME_YES=1; export ORANGEBOX_ASSUME_YES ;;
      --audit|--check) AUTO_FIX=false ;;
      --help|-h) show_usage; exit 0 ;;
      *) echo -e "${RED}[ERROR] Argumento desconocido: $1${NC}" >&2; show_usage; exit 2 ;;
    esac
    shift
  done

  echo
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE} [MÓDULO] LOGROTATE | Compresión y rotación de logs${NC}"
  if [ "$AUTO_FIX" = true ]; then
    echo -e "${BLUE} [MODO] FIX AUTOMÁTICO — sin confirmaciones${NC}"
  else
    echo -e "${BLUE} [MODO] AUDITORÍA — solo lectura${NC}"
  fi
  echo -e "${BLUE}============================================================${NC}"

  if [ ! -f "$LOGROTATE_CONF" ] || [ -L "$LOGROTATE_CONF" ]; then
    echo -e "${RED}[ERROR] $LOGROTATE_CONF no existe, no es regular o es un enlace simbólico${NC}"
    exit 1
  fi
  if ! command -v logrotate >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] logrotate no está instalado; no se modifica configuración${NC}"
    exit 1
  fi
  [ "$AUTO_FIX" != true ] || make_backup_dir || exit 1

  FILES=("$LOGROTATE_CONF")
  if [ -d "$LOGROTATE_DIR" ]; then
    while IFS= read -r -d '' file; do FILES+=("$file"); done < <(find "$LOGROTATE_DIR" -type f -print0 | sort -z)
    while IFS= read -r -d '' file; do
      echo -e "${YELLOW}[WARN] Enlace simbólico omitido para no editar un destino externo: $file${NC}"
      WARNINGS=$((WARNINGS + 1))
    done < <(find "$LOGROTATE_DIR" -type l -print0)
  else
    echo -e "${YELLOW}[WARN] $LOGROTATE_DIR no existe; se procesa solo $LOGROTATE_CONF${NC}"
  fi

  # Auditd conflict checks happen before any logrotate file is normalized.
  if ! configure_audit_retention; then
    echo -e "${RED}[ERROR] Falló la instalación de la retención de auditd; se restauran los cambios realizados.${NC}"
    restore_changed_files
    exit 1
  fi

  local file
  for file in "${FILES[@]}"; do
    if ! process_file "$file"; then
      echo -e "${RED}[ERROR] Falló el procesamiento de $file; se restauran los archivos ya modificados.${NC}"
      restore_changed_files
      exit 1
    fi
  done

  if [ "$AUTO_FIX" = true ] && [ "$FIXED" -gt 0 ]; then
    local validation="$BACKUP_DIR/logrotate-validation.txt"
    echo -e "${BLUE}[VALIDANDO] logrotate -d /etc/logrotate.conf${NC}"
    if ! logrotate -d -s "$BACKUP_DIR/status-validation" "$LOGROTATE_CONF" >"$validation" 2>&1; then
      echo -e "${RED}[ERROR] La configuración no valida; se restauran los archivos modificados${NC}"
      tail -30 "$validation" 2>/dev/null || true
      restore_changed_files
      exit 1
    fi
    echo -e "${GREEN}[OK] Sintaxis de logrotate validada${NC}"
  elif [ "$AUTO_FIX" = true ]; then
    echo -e "${GREEN}[OK] No hay cambios pendientes${NC}"
  fi

  echo
  echo -e "${BLUE}RESUMEN LOGROTATE${NC}"
  echo "  Archivos corregidos: $FIXED"
  echo "  Advertencias: $WARNINGS"
  [ "$AUTO_FIX" != true ] || echo "  Backup: $BACKUP_DIR"
  echo -e "${BLUE}============================================================${NC}"
}

main "$@"
