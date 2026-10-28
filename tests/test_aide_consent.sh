#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
AIDE="$ROOT_DIR/aide-install.sh"
CORE="$ROOT_DIR/linux-hardening.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
grep -Fq 'confirm_aide_change()' "$AIDE" || fail "AIDE no tiene consentimiento por acción"
grep -Fq 'confirm_aide_change "inicializar base de datos AIDE"' "$AIDE" || fail "aide --init no requiere consentimiento"
grep -Fq 'confirm_aide_change "programar comprobación diaria de AIDE"' "$AIDE" || fail "el crontab no requiere consentimiento"
grep -Fq 'root.crontab.before' "$AIDE" || fail "no se respalda el crontab root antes de modificarlo"
grep -Fq 'No se programa aide --check hasta disponer de una base de referencia válida' "$AIDE" || fail "AIDE puede programarse sin base de datos"
! grep -Fq '[ "$WARNINGS" -eq 0 ]' "$AIDE" || fail "los hallazgos operacionales se devuelven como error de ejecución al orquestador"
grep -Fq 'usb-storage|aide)' "$CORE" || fail "el orquestador no delega consentimiento al módulo AIDE"
init_body="$(awk '/^check_aide_database\(\) \{/{p=1} p{print} p && /^}/{exit}' "$AIDE")"
confirm_line="$(printf '%s\n' "$init_body" | grep -n 'confirm_aide_change' | head -n1 | cut -d: -f1)"
init_line="$(printf '%s\n' "$init_body" | grep -n '"$AIDE_BIN" --init' | head -n1 | cut -d: -f1)"
[ -n "$confirm_line" ] && [ -n "$init_line" ] && [ "$confirm_line" -lt "$init_line" ] || fail "aide --init puede ejecutarse antes de pedir consentimiento"
pass "AIDE: confirma inicialización y programación, valida base y respalda crontab"
