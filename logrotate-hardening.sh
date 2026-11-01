#!/usr/bin/env bash
# OrangeBox logrotate baseline: compressed logs with a bounded five-file rotation.
set -u

AUTO_FIX=false
LOGROTATE_CONF="/etc/logrotate.conf"
LOGROTATE_DIR="/etc/logrotate.d"
AUDITD_CONF="/etc/audit/auditd.conf"
AUDIT_ROTATION_SCRIPT="/etc/cron.daily/orangebox-audit-logrotate"
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
  local file="$1" dest="$BACKUP_DIR$file" source_hash backup_hash
  mkdir -p "$(dirname "$dest")" || return 1
  cp -p "$file" "$dest" || return 1
  source_hash="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
  backup_hash="$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')"
  [ -n "$source_hash" ] && [ "$source_hash" = "$backup_hash" ]
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


# Reads the last active max_log_file_action value without treating comments as configuration.
auditd_rotation_action() {
  [ -r "$AUDITD_CONF" ] || return 1
  awk -F= '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      key=$1; gsub(/[[:space:]]/, "", key)
      if (key == "max_log_file_action") {
        value=$2
        sub(/[[:space:]]*#.*/, "", value)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        current=tolower(value)
      }
    }
    END { if (current != "") print current; else exit 1 }
  ' "$AUDITD_CONF"
}

# Detects an existing independent audit.log rotator before installing OrangeBox policy.
# Direct logrotate handling of audit.log is not replaced because auditd owns the open file.
audit_rotation_conflict() {
  local candidate=""
  for candidate in "$LOGROTATE_CONF" "$LOGROTATE_DIR"/*; do
    [ -f "$candidate" ] || continue
    [ "$candidate" = "$AUDIT_ROTATION_SCRIPT" ] && continue
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
    [ "$candidate" = "$AUDIT_ROTATION_SCRIPT" ] && continue
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

# Creates the Red Hat-supported time-based auditd rotation helper.
# auditd rotates its own active file on request; this helper then timestamps,
# compresses and removes only OrangeBox archives older than seven days.
write_audit_rotation_script() {
  cat <<'AUDIT_ROTATION'
#!/usr/bin/env bash
set -u

# ORANGEBOX_AUDIT_LOG_ROTATION
# Rotate auditd once per day, compress archives and retain seven days.
export PATH="/sbin:/bin:/usr/sbin:/usr/bin:$PATH"
AUDIT_LOG_DIR="${ORANGEBOX_AUDIT_LOG_DIR:-/var/log/audit}"
KEEP_DAYS=7
KEEP_MINUTES=$((KEEP_DAYS * 1440))
SERVICE_BIN="${ORANGEBOX_AUDIT_SERVICE_BIN:-service}"

log_message() {
  if command -v logger >/dev/null 2>&1; then
    logger -t orangebox-audit-rotation -- "$*"
  fi
}

# Compress numbered auditd rotations without touching the active audit.log.
archive_rotated_logs() {
  local file suffix timestamp epoch archive staging
  for file in "$AUDIT_LOG_DIR"/audit.log.[0-9]*; do
    [ -f "$file" ] || continue
    suffix="${file##*.}"
    [[ "$suffix" =~ ^[0-9]+$ ]] || continue

    timestamp="$(date -r "$file" '+%Y%m%d_%H%M%S')" || return 1
    epoch="$(date -r "$file" '+%s')" || return 1
    archive="$AUDIT_LOG_DIR/audit.log.orangebox.$timestamp.$epoch.$suffix.gz"
    staging="$archive.tmp"

    [ ! -e "$archive" ] || archive="$AUDIT_LOG_DIR/audit.log.orangebox.$timestamp.$epoch.$suffix.$$.gz"
    staging="$archive.tmp"

    mv -- "$file" "$staging" || return 1
    if ! gzip -f -- "$staging"; then
      mv -- "$staging" "$file" 2>/dev/null || true
      return 1
    fi
    mv -- "$staging.gz" "$archive" || return 1
  done
}

[ -d "$AUDIT_LOG_DIR" ] || exit 0
command -v gzip >/dev/null 2>&1 || { log_message "ERROR: gzip no está disponible"; exit 1; }
command -v "$SERVICE_BIN" >/dev/null 2>&1 || { log_message "ERROR: service no está disponible"; exit 1; }

# Preserve archives from the previous rotation before auditd reuses audit.log.1.
archive_rotated_logs || { log_message "ERROR: no se pudieron comprimir logs audit anteriores"; exit 1; }

# Request rotation through auditd; never rename or truncate the active file ourselves.
"$SERVICE_BIN" auditd rotate
rotate_status=$?
if [ "$rotate_status" -ne 0 ]; then
  log_message "ERROR: auditd rotate terminó con código $rotate_status"
  exit "$rotate_status"
fi

# Allow auditd to finish closing the previous file and creating the new active log.
sleep 2
archive_rotated_logs || { log_message "ERROR: no se pudieron comprimir los logs audit rotados"; exit 1; }

# Delete only archives created by this policy after seven full days.
find "$AUDIT_LOG_DIR" -maxdepth 1 -type f -name 'audit.log.orangebox.*.gz' \
  -mmin "+$KEEP_MINUTES" -exec rm -f -- {} +

log_message "Rotación diaria completada; compresión gzip y retención de siete días."
exit 0
AUDIT_ROTATION
}

# Reconciles auditd time-based rotation only when no other active audit rotator exists.
configure_audit_rotation() {
  local conflict="" action="" tmp="" mode="" owner_group="" changed_action=0
  local script_marker="# ORANGEBOX_AUDIT_LOG_ROTATION"

  if [ ! -f "$AUDITD_CONF" ] || [ -L "$AUDITD_CONF" ] || [ ! -d /var/log/audit ]; then
    echo -e "${BLUE}[INFO] auditd no está instalado/configurado; se omite la retención de sus logs.${NC}"
    return 0
  fi

  if ! command -v gzip >/dev/null 2>&1 || ! command -v service >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] No se instala la rotación audit: se requiere gzip y service.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  conflict="$(audit_rotation_conflict || true)"
  if [ -n "$conflict" ]; then
    echo -e "${YELLOW}[WARN] Se detectó otra política de rotación de audit en $conflict; no se crea una segunda política ni se modifica auditd.conf.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if [ -L "$AUDIT_ROTATION_SCRIPT" ]; then
    echo -e "${YELLOW}[WARN] $AUDIT_ROTATION_SCRIPT es un enlace simbólico; no se modifica.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if [ -e "$AUDIT_ROTATION_SCRIPT" ] && ! grep -Fq "$script_marker" "$AUDIT_ROTATION_SCRIPT"; then
    echo -e "${YELLOW}[WARN] $AUDIT_ROTATION_SCRIPT ya existe y no pertenece a OrangeBox; se conserva sin cambios.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  action="$(auditd_rotation_action 2>/dev/null || true)"
  case "$action" in
    ""|rotate|ignore) ;;
    *)
      echo -e "${YELLOW}[WARN] max_log_file_action=$action parece una política personalizada; no se reemplaza por ignore.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 0
      ;;
  esac

  [ "$AUTO_FIX" = true ] || {
    if [ "$action" = "ignore" ] && [ -f "$AUDIT_ROTATION_SCRIPT" ] && grep -Fq "$script_marker" "$AUDIT_ROTATION_SCRIPT"; then
      echo -e "${GREEN}[OK] Auditd: rotación diaria, compresión y retención de siete días ya configuradas.${NC}"
    else
      echo -e "${YELLOW}[PENDIENTE] Auditd: falta configurar la rotación diaria con compresión y retención de siete días.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    return 0
  }

  mkdir -p /etc/cron.daily || return 1
  tmp="$(mktemp /etc/cron.daily/.orangebox-audit-rotation.XXXXXX)" || return 1
  write_audit_rotation_script > "$tmp" || { rm -f "$tmp"; return 1; }
  bash -n "$tmp" || { rm -f "$tmp"; echo -e "${RED}[ERROR] Sintaxis inválida en el rotador auditd.${NC}"; return 1; }

  if [ -f "$AUDIT_ROTATION_SCRIPT" ] && cmp -s "$tmp" "$AUDIT_ROTATION_SCRIPT"; then
    rm -f "$tmp"
  else
    if [ -f "$AUDIT_ROTATION_SCRIPT" ]; then
      backup_one "$AUDIT_ROTATION_SCRIPT" || { rm -f "$tmp"; return 1; }
    fi
    chmod 750 "$tmp" && chown root:root "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$AUDIT_ROTATION_SCRIPT" || { rm -f "$tmp"; return 1; }
    CHANGED_FILES+=("$AUDIT_ROTATION_SCRIPT")
    FIXED=$((FIXED + 1))
    echo -e "${GREEN}[OK] Rotador auditd instalado/actualizado en $AUDIT_ROTATION_SCRIPT.${NC}"
  fi

  if [ "$action" != "ignore" ]; then
    backup_one "$AUDITD_CONF" || return 1
    tmp="$(mktemp "$(dirname "$AUDITD_CONF")/.auditd.conf.orangebox.XXXXXX")" || return 1
    awk '
      function trim(s) { sub(/^[ \\t]+/, "", s); sub(/[ \\t]+$/, "", s); return s }
      /^[ \\t]*#/ || /^[ \\t]*$/ { print; next }
      {
        line=$0
        sub(/[ \\t]+#.*/, "", line)
        equal=index(line, "=")
        key=equal ? trim(substr(line, 1, equal-1)) : ""
        if (key == "max_log_file_action") {
          if (!written) print "max_log_file_action = ignore"
          written=1
          next
        }
        print
      }
      END { if (!written) print "max_log_file_action = ignore" }
    ' "$AUDITD_CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
    mode="$(stat -c '%a' "$AUDITD_CONF" 2>/dev/null || echo 640)"
    owner_group="$(stat -c '%u:%g' "$AUDITD_CONF" 2>/dev/null || echo 0:0)"
    chmod "$mode" "$tmp" && chown "$owner_group" "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$AUDITD_CONF" || { rm -f "$tmp"; return 1; }
    CHANGED_FILES+=("$AUDITD_CONF")
    FIXED=$((FIXED + 1))
    changed_action=1
    echo -e "${GREEN}[OK] max_log_file_action actualizado a ignore para usar rotación diaria.${NC}"
  fi

  if [ "$changed_action" -eq 1 ]; then
    local auditd_pid=""
    auditd_pid="$(pidof auditd 2>/dev/null || true)"
    if [ -n "$auditd_pid" ]; then
      # Red Hat documents SIGHUP as the portable way to reload auditd.conf.
      kill -HUP $auditd_pid || return 1
      echo -e "${GREEN}[OK] auditd recibió SIGHUP para aplicar la nueva política.${NC}"
    fi
  fi

  echo -e "${GREEN}[OK] Auditd: gzip + siete días; el archivo activo sigue bajo control de auditd.${NC}"
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

  local file
  for file in "${FILES[@]}"; do
    if ! process_file "$file"; then
      echo -e "${RED}[ERROR] Falló el procesamiento de $file; se restauran los archivos ya modificados.${NC}"
      restore_changed_files
      exit 1
    fi
  done

  if ! configure_audit_rotation; then
    echo -e "${RED}[ERROR] Falló la configuración de retención de auditd; se restauran los cambios realizados.${NC}"
    restore_changed_files
    exit 1
  fi

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
