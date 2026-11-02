#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/.." && pwd -P)"
MODULE="$ROOT_DIR/logrotate-hardening.sh"
TMP_DIR="$(mktemp -d "$ROOT_DIR/.orangebox-test-audit-retention.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

HELPER="$TMP_DIR/auditd-retention.sh"
awk '
  /cat <<.AUDIT_RETENTION./ { inside=1; next }
  inside && /^AUDIT_RETENTION$/ { exit }
  inside { print }
' "$MODULE" > "$HELPER"
[[ -s "$HELPER" ]] || fail "no se pudo extraer el helper de retención auditd"
bash -n "$HELPER" || fail "el helper extraído no tiene sintaxis Bash válida"
grep -Fq '# ORANGEBOX_AUDIT_LOG_RETENTION' "$HELPER" || fail "falta el marcador OrangeBox"
grep -Eq '^KEEP_DAYS=7$' "$HELPER" || fail "la retención no es de siete días"
grep -Fq "audit\\.log\\.[0-9]+" "$HELPER" || fail "solo debe seleccionar generaciones numéricas"
grep -Fq -- '-delete' "$HELPER" || fail "la limpieza debe borrar generaciones vencidas"
! grep -Fq 'auditd rotate' "$HELPER" || fail "el helper no debe solicitar otra rotación"
! grep -Eq '(^|[[:space:]])gzip([[:space:]]|$)' "$HELPER" || fail "el helper no debe comprimir generaciones nuevas"

AUDIT_DIR="$TMP_DIR/audit"
mkdir -p "$AUDIT_DIR"
printf 'active-log-content\n' > "$AUDIT_DIR/audit.log"
printf 'expired-numbered-generation\n' > "$AUDIT_DIR/audit.log.2048"
printf 'recent-numbered-generation\n' > "$AUDIT_DIR/audit.log.1"
printf 'expired-orangebox-archive\n' > "$AUDIT_DIR/audit.log.orangebox.expired.gz"
printf 'recent-orangebox-archive\n' > "$AUDIT_DIR/audit.log.orangebox.recent.gz"
printf 'unmanaged-backup\n' > "$AUDIT_DIR/unmanaged-backup.gz"
printf 'non-numeric-suffix\n' > "$AUDIT_DIR/audit.log.previous"

touch -d '8 days ago' \
  "$AUDIT_DIR/audit.log.2048" \
  "$AUDIT_DIR/audit.log.orangebox.expired.gz" \
  "$AUDIT_DIR/unmanaged-backup.gz" \
  "$AUDIT_DIR/audit.log.previous"
touch -d '6 days ago' \
  "$AUDIT_DIR/audit.log.1" \
  "$AUDIT_DIR/audit.log.orangebox.recent.gz"

ORANGEBOX_AUDIT_LOG_DIR="$AUDIT_DIR" bash "$HELPER" ||
  fail "el helper no completó la limpieza de retención"

[[ -f "$AUDIT_DIR/audit.log" ]] || fail "se perdió el audit.log activo"
grep -Fq 'active-log-content' "$AUDIT_DIR/audit.log" || fail "se modificó el contenido del audit.log activo"
[[ ! -e "$AUDIT_DIR/audit.log.2048" ]] || fail "no eliminó la generación numérica con más de siete días"
[[ -f "$AUDIT_DIR/audit.log.1" ]] || fail "eliminó una generación numérica de menos de siete días"
[[ ! -e "$AUDIT_DIR/audit.log.orangebox.expired.gz" ]] || fail "no eliminó el archivo OrangeBox heredado vencido"
[[ -f "$AUDIT_DIR/audit.log.orangebox.recent.gz" ]] || fail "eliminó un archivo OrangeBox reciente"
[[ -f "$AUDIT_DIR/unmanaged-backup.gz" ]] || fail "eliminó un archivo ajeno a OrangeBox"
[[ -f "$AUDIT_DIR/audit.log.previous" ]] || fail "eliminó un sufijo no numérico"

pass "la retención elimina solo generaciones audit.log.N y archivos OrangeBox >7 días; preserva el log activo y los recientes"
