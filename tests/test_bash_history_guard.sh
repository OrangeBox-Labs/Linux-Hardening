#!/usr/bin/env bash
# Regression tests for the history() protection embedded in the hardening scripts.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}
pass() {
  printf '[PASS] %s\n' "$*"
}

extract_history_function() {
  local source="$1" destination="$2"
  awk '
    !found && /^[[:space:]]*history\(\) \{$/ { found=1; inside=1 }
    inside { print }
    inside && /^[[:space:]]*\}[[:space:]]*$/ { exit }
    END { if (!found) exit 1 }
  ' "$source" > "$destination" || return 1
  [ -s "$destination" ] || return 1
  bash -n "$destination"
}

test_one_script() {
  local source="$1" label="$2"
  local wrapper="$TMP_DIR/${label}-history-function.sh"
  local histfile="$TMP_DIR/${label}.history"
  local errors="$TMP_DIR/${label}.stderr"
  local output="$TMP_DIR/${label}.stdout"

  extract_history_function "$source" "$wrapper" ||
    fail "$label: no se pudo extraer/validar la función history()"

  printf '%s\n' '# ORANGEBOX_TEST_SENTINEL_KEEP' > "$histfile"
  chmod 600 "$histfile"

  # Se prueba en una subshell aislada, sin cargar perfiles ni tocar el historial real.
  HISTFILE="$histfile" bash --noprofile --norc -c '
    set -o history
    source "$1"

    check_blocked() {
      local description="$1"
      shift
      local rc
      if history "$@" >"$OUT" 2>"$ERR"; then
        printf "[FAIL] se permitió history %s\n" "$description" >&2
        exit 21
      else
        rc=$?
      fi
      if [ "$rc" -ne 2 ]; then
        printf "[FAIL] history %s devolvió %s, se esperaba 2\n" "$description" "$rc" >&2
        cat "$ERR" >&2
        exit 22
      fi
      if ! grep -q "bloqueado history -c/-d/-w" "$ERR"; then
        printf "[FAIL] history %s no mostró el mensaje de bloqueo\n" "$description" >&2
        cat "$ERR" >&2
        exit 23
      fi
    }

    export OUT="$2" ERR="$3"
    check_blocked "-c" -c
    check_blocked "-d 1" -d 1
    check_blocked "-w" -w
    check_blocked "-cw (opciones combinadas)" -cw

    # Operaciones no destructivas que deben seguir disponibles.
    history -a
    history -n
    history -p "printf test"
    history -s "echo benign-history-test"
  ' _ "$wrapper" "$output" "$errors" ||
    fail "$label: prueba funcional de la protección falló"

  grep -Fxq '# ORANGEBOX_TEST_SENTINEL_KEEP' "$histfile" ||
    fail "$label: el archivo de historial de prueba fue alterado o vaciado"

  pass "$label: -c/-d/-w/-cw bloqueados; -a/-n/-p/-s permitidos; sentinel conservado"
}

test_one_script "$ROOT_DIR/linux-hardening.sh" "core"
test_one_script "$ROOT_DIR/bash-hardening.sh" "standalone"
printf 'Todas las pruebas de protección del historial pasaron.\n'
