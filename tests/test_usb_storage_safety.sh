#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
USB="$ROOT_DIR/disable-usb-storage.sh"
CORE="$ROOT_DIR/linux-hardening.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
grep -Fq 'confirm_usb_change()' "$USB" || fail "USB no exige consentimiento interactivo"
grep -Fq 'install usb-storage /bin/true' "$USB" || fail "no se instala la regla de bloqueo esperada"
grep -Fq 'blacklist usb_storage' "$USB" || fail "no se añade blacklist para cargas futuras"
grep -Fq 'No se descarga en caliente' "$USB" || fail "no se explica la decisión de evitar descarga en caliente"
if grep -Eq '(^|[[:space:]])rmmod[[:space:]]+usb' "$USB"; then fail "el script descarga módulos USB en caliente"; fi
grep -Fq '|usb-storage)' "$CORE" || fail "el orquestador no delega la confirmación por acción al módulo USB"
pass "USB: auditoría por defecto, confirmación de fix y sin descarga de módulos en caliente"
