#!/usr/bin/env bash
# Regression tests for OS identification on CentOS/RHEL generations without os-release.
set -eu
ROOT_DIR="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

awk '/^detect_os\(\)\{/,/^}/ { print }' "$CORE" > "$TMP_DIR/detect-os.sh"
[ -s "$TMP_DIR/detect-os.sh" ] || { echo "[FAIL] No se pudo extraer detect_os" >&2; exit 1; }

run_legacy_case() {
  local release_line="$1" expected_id="$2" expected_version="$3"
  printf '%s\n' "$release_line" > "$TMP_DIR/redhat-release"
  (
    export ORANGEBOX_OS_RELEASE_FILE="$TMP_DIR/no-os-release"
    export ORANGEBOX_REDHAT_RELEASE_FILE="$TMP_DIR/redhat-release"
    ok() { :; }
    die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
    . "$TMP_DIR/detect-os.sh"
    detect_os
    [ "$OS_ID" = "$expected_id" ] || { echo "[FAIL] ID esperado=$expected_id observado=$OS_ID" >&2; exit 1; }
    [ "$OS_VERSION" = "$expected_version" ] || { echo "[FAIL] Versión esperada=$expected_version observada=$OS_VERSION" >&2; exit 1; }
  )
  printf '[PASS] %s => %s %s\n' "$release_line" "$expected_id" "$expected_version"
}

run_legacy_case "CentOS release 6.5 (Final)" centos 6
run_legacy_case "CentOS release 7.9 (Core)" centos 7
run_legacy_case "Red Hat Enterprise Linux Server release 6.10 (Santiago)" rhel 6
run_legacy_case "Oracle Linux Server release 6.10" ol 6

# Modern /etc/os-release must still take precedence when available.
(
  printf '%s\n' 'ID=almalinux' 'VERSION_ID="9.8"' 'ID_LIKE="rhel centos fedora"' > "$TMP_DIR/os-release"
  printf '%s\n' "CentOS release 6.5 (Final)" > "$TMP_DIR/redhat-release"
  export ORANGEBOX_OS_RELEASE_FILE="$TMP_DIR/os-release"
  export ORANGEBOX_REDHAT_RELEASE_FILE="$TMP_DIR/redhat-release"
  ok() { :; }
  die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
  . "$TMP_DIR/detect-os.sh"
  detect_os
  [ "$OS_ID" = almalinux ] || { echo "[FAIL] /etc/os-release debe tener precedencia" >&2; exit 1; }
  [ "$OS_VERSION" = 9 ] || { echo "[FAIL] VERSION_ID debía normalizar a 9" >&2; exit 1; }
)
printf '[PASS] /etc/os-release conserva precedencia cuando existe\n'
