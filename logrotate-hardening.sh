#!/usr/bin/env bash
# OrangeBox logrotate baseline: compressed logs with a bounded five-file rotation.
set -u

AUTO_FIX=false
LOGROTATE_CONF="/etc/logrotate.conf"
LOGROTATE_DIR="/etc/logrotate.d"
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
  local file="$1" tmp="$2"
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
  ' "$file" > "$tmp"
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

  tmp="$(mktemp "$(dirname "$file")/.logrotate-orangebox.XXXXXX")" || {
    echo -e "${RED}[ERROR] No se pudo crear un temporal para $file${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  }
  if ! normalize_file "$file" "$tmp"; then
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

  if [ "$AUTO_FIX" != true ]; then
    echo -e "${YELLOW}[PENDIENTE] $file: aplicar compress y rotate 5; se revisan también directivas locales nocompress/rotate.${NC}"
    WARNINGS=$((WARNINGS + 1))
    rm -f "$tmp"
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
