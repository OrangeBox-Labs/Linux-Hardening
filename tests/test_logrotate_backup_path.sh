#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT_DIR/logrotate-hardening.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\\n' "$*"; }

BACKUP_FUNCTION="$TMP_DIR/backup-one.sh"
awk '
  /^backup_one\(\) \{$/ { inside=1 }
  inside { print }
  inside && /^}$/ { exit }
' "$SCRIPT" > "$BACKUP_FUNCTION"
[[ -s "$BACKUP_FUNCTION" ]] || fail "no se pudo extraer backup_one"
bash -n "$BACKUP_FUNCTION" || fail "backup_one no tiene sintaxis válida"

RED=red
NC=reset
BACKUP_DIR="$TMP_DIR/backups/run"
mkdir -p "$BACKUP_DIR"

# A caller-scope variable named file must not influence backup_one's target path.
file="$TMP_DIR/outer-scope-file"
SOURCE="$TMP_DIR/source/auditd.conf"
mkdir -p "$(dirname "$SOURCE")"
printf 'max_log_file = 50\\nmax_log_file_action = ROTATE\\n' > "$SOURCE"
chmod 640 "$SOURCE"

# Source the actual production function in the test process.
source "$BACKUP_FUNCTION"
backup_one "$SOURCE" || fail "backup_one devolvió error"

EXPECTED="$BACKUP_DIR$SOURCE"
[[ -f "$EXPECTED" ]] || fail "el respaldo no se creó en la ruta espejo esperada: $EXPECTED"
cmp -s "$SOURCE" "$EXPECTED" || fail "el contenido del respaldo no coincide"
[[ "$(stat -c '%a' "$SOURCE")" = "$(stat -c '%a' "$EXPECTED")" ]] || fail "no conservó los permisos del archivo"
[[ ! -e "$BACKUP_DIR$TMP_DIR/outer-scope-file" ]] || fail "el destino dependió de la variable file del llamador"

pass "backup_one construye la ruta desde su argumento y verifica contenido/permisos"
