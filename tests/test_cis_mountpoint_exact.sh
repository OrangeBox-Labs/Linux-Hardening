#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CIS="$ROOT_DIR/cis-benchmark-check.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Extract only the two pure helpers; the full CIS checker is an executable audit.
sed -n \
  -e '/^cis_mount_is_exact() {/,/^}/p' \
  -e '/^cis_mount_option_enabled() {/,/^}/p' \
  "$CIS" > "$TMP_DIR/mount-helpers.sh"
[ -s "$TMP_DIR/mount-helpers.sh" ] || fail "no se pudieron extraer los helpers de montaje"

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/findmnt" <<'FAKE_FINDMNT'
#!/usr/bin/env bash
case "${3:-}" in
  TARGET,OPTIONS)
    printf '%s\n' \
      '/ rw,relatime' \
      '/dev/shm rw,nosuid,nodev,noexec' \
      '/home rw,nosuid,nodev'
    ;;
  TARGET)
    printf '%s\n' '/' '/dev/shm' '/home'
    ;;
  *)
    exit 2
    ;;
esac
FAKE_FINDMNT
chmod +x "$TMP_DIR/bin/findmnt"
PATH="$TMP_DIR/bin:$PATH"
export PATH
# shellcheck source=/dev/null
source "$TMP_DIR/mount-helpers.sh"

cis_mount_is_exact "/" || fail "el root filesystem debería reconocerse como mountpoint"
cis_mount_is_exact "/dev/shm" || fail "/dev/shm debería reconocerse como mountpoint exacto"
cis_mount_is_exact "/home" || fail "/home debería reconocerse como mountpoint exacto"
if cis_mount_is_exact "/tmp"; then
  fail "/tmp no es un mountpoint dedicado; no debe aprobar por heredar opciones de /"
fi
if cis_mount_option_enabled "/tmp" "nodev"; then
  fail "no debe heredar nodev del filesystem raíz para aprobar /tmp"
fi
cis_mount_option_enabled "/dev/shm" "noexec" || fail "/dev/shm debería aprobar noexec"
cis_mount_option_enabled "/dev/shm" "nodev" || fail "/dev/shm debería aprobar nodev"
cis_mount_option_enabled "/home" "nosuid" || fail "/home debería aprobar nosuid"
if cis_mount_option_enabled "/home" "noexec"; then
  fail "/home no debería aprobar una opción ausente"
fi

pass "el verificador CIS exige mountpoint exacto y no infiere opciones desde el padre"
