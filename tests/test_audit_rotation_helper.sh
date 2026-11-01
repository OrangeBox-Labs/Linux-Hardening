#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
MODULE="$ROOT_DIR/logrotate-hardening.sh"
# Test mocks are executable files; /tmp may be mounted noexec on hardened hosts.
TMP_DIR="$(mktemp -d "$ROOT_DIR/.orangebox-test-audit-rotation.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

HELPER="$TMP_DIR/auditd-logrotate.sh"
awk '
  /cat <<.AUDIT_ROTATION./ { inside=1; next }
  inside && /^AUDIT_ROTATION$/ { exit }
  inside { print }
' "$MODULE" > "$HELPER"
[[ -s "$HELPER" ]] || fail "no se pudo extraer el helper auditd del módulo"
bash -n "$HELPER" || fail "el helper extraído no tiene sintaxis Bash válida"
grep -Fq '# ORANGEBOX_AUDIT_LOG_ROTATION' "$HELPER" || fail "falta el marcador OrangeBox"
grep -Eq '^KEEP_DAYS=7$' "$HELPER" || fail "la retención no es de siete días"

AUDIT_DIR="$TMP_DIR/audit"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$AUDIT_DIR" "$BIN_DIR"
printf 'active-before-rotation\n' > "$AUDIT_DIR/audit.log"
printf 'previous-generation\n' > "$AUDIT_DIR/audit.log.1"
printf 'old-managed-archive\n' > "$AUDIT_DIR/audit.log.orangebox.20000101_000000.946684800.1.gz"
printf 'unmanaged-backup\n' > "$AUDIT_DIR/unmanaged-backup.gz"
touch -d '8 days ago' "$AUDIT_DIR/audit.log.orangebox.20000101_000000.946684800.1.gz" "$AUDIT_DIR/unmanaged-backup.gz"

cat > "$BIN_DIR/service" <<'SERVICE'
#!/usr/bin/env bash
set -e
[[ "$1" = "auditd" && "$2" = "rotate" ]] || exit 2
mv -- "$TEST_AUDIT_DIR/audit.log" "$TEST_AUDIT_DIR/audit.log.1"
: > "$TEST_AUDIT_DIR/audit.log"
SERVICE
chmod 700 "$BIN_DIR/service"

ORANGEBOX_AUDIT_LOG_DIR="$AUDIT_DIR" \
ORANGEBOX_AUDIT_SERVICE_BIN="$BIN_DIR/service" \
TEST_AUDIT_DIR="$AUDIT_DIR" \
bash "$HELPER" || fail "el helper no completó la rotación simulada"

[[ -f "$AUDIT_DIR/audit.log" ]] || fail "se perdió el audit.log activo"
[[ ! -e "$AUDIT_DIR/audit.log.1" ]] || fail "quedó una generación numerada sin archivar"
[[ ! -e "$AUDIT_DIR/audit.log.orangebox.20000101_000000.946684800.1.gz" ]] || fail "no eliminó el archivo OrangeBox antiguo"
[[ -f "$AUDIT_DIR/unmanaged-backup.gz" ]] || fail "eliminó un archivo ajeno a OrangeBox"

archives=("$AUDIT_DIR"/audit.log.orangebox.*.gz)
[[ ${#archives[@]} -eq 2 ]] || fail "se esperaban dos archivos gzip recientes; se encontraron ${#archives[@]}"
for archive in "${archives[@]}"; do
  gzip -t "$archive" || fail "archivo gzip inválido: $archive"
done
gzip -cd "${archives[@]}" | grep -Eq 'previous-generation|active-before-rotation' ||
  fail "no se conserva el contenido de los logs rotados"

pass "auditd rota mediante service, los logs cerrados se comprimen y solo se eliminan archivos OrangeBox >7 días"
