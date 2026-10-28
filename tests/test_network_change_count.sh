#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

sed -n '/^network_module_reported_fixes() {/,/^}/p' "$CORE" > "$TMP_DIR/helper.sh"
[ -s "$TMP_DIR/helper.sh" ] || fail "no se pudo extraer el contador de network-full"
# shellcheck source=/dev/null
source "$TMP_DIR/helper.sh"

# The child module wraps the number in ANSI color codes; the global summary must
# still count exactly the value from the dedicated NETWORK HARDENING section.
printf 'Correcciones: 99\nNETWORK HARDENING\nRESUMEN:\n  • Correcciones aplicadas: \033[0;32m2\033[0m\n  • Advertencias pendientes: 0\nMODULOS DESHABILITADOS:\nCorrecciones aplicadas: 88\n' > "$TMP_DIR/network-two.log"
actual="$(network_module_reported_fixes "$TMP_DIR/network-two.log")"
[ "$actual" = 2 ] || fail "se esperaba contar 2 correcciones de red, resultado=${actual:-vacío}"

printf 'NETWORK HARDENING\nRESUMEN:\n  • Correcciones aplicadas: \033[0;32m0\033[0m\nMODULOS DESHABILITADOS:\n' > "$TMP_DIR/network-zero.log"
actual="$(network_module_reported_fixes "$TMP_DIR/network-zero.log")"
[ "$actual" = 0 ] || fail "un módulo idempotente debe reportar 0, resultado=${actual:-vacío}"

printf 'Correcciones aplicadas: 7\n' > "$TMP_DIR/no-network-section.log"
actual="$(network_module_reported_fixes "$TMP_DIR/no-network-section.log")"
[ -z "$actual" ] || fail "no debe contar valores ajenos al resumen NETWORK HARDENING"

pass "el resumen global puede contabilizar los cambios de network-full y conserva el cero en ejecuciones idempotentes"
