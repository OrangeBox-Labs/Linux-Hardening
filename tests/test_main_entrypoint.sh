#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
MAIN="$ROOT_DIR/linux-hardening.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

[ -s "$MAIN" ] || fail "falta linux-hardening.sh"

# main() currently requires root before it parses --help. Use non-interactive
# sudo on hosted CI runners; compatibility containers run this test as root.
if [ "$(id -u)" -eq 0 ]; then
  if output="$(bash "$MAIN" --help 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
else
  command -v sudo >/dev/null 2>&1 || fail "la prueba necesita root o sudo para ejecutar --help"
  if output="$(sudo -n bash "$MAIN" --help 2>&1)"; then
    rc=0
  else
    rc=$?
  fi
fi

[ "$rc" -eq 0 ] || {
  printf '%s\n' "$output" >&2
  fail "--help terminó con código $rc"
}
printf '%s\n' "$output" | grep -Fq 'Uso:' ||
  fail "linux-hardening.sh --help no muestra la sección de uso; ¿se invoca main?"
printf '%s\n' "$output" | grep -Fq 'Auditoría del baseline interno' ||
  fail "la ayuda no documenta el modo de auditoría por defecto"

pass "el punto de entrada de linux-hardening.sh procesa --help y muestra la ayuda"
