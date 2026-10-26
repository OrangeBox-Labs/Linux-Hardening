#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CIS="$ROOT_DIR/cis-benchmark-check.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

sed -n \
  -e '/^cis_stream_has_kernel_argument() {/,/^}/p' \
  -e '/^cis_file_has_kernel_argument() {/,/^}/p' \
  -e '/^cis_systemd_config_dump() {/,/^}/p' \
  -e '/^cis_systemd_config_value() {/,/^}/p' \
  "$CIS" > "$TMP_DIR/effective-config-helpers.sh"
[ -s "$TMP_DIR/effective-config-helpers.sh" ] || fail "no se pudieron extraer los helpers de configuración efectiva"

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/systemd-analyze" <<'FAKE_SYSTEMD_ANALYZE'
#!/usr/bin/env bash
if [ "${1:-}" = "cat-config" ] && [ "${2:-}" = "systemd/coredump.conf" ]; then
  cat "$FAKE_SYSTEMD_CONFIG"
else
  exit 2
fi
FAKE_SYSTEMD_ANALYZE
chmod +x "$TMP_DIR/bin/systemd-analyze"

cat > "$TMP_DIR/coredump-effective.conf" <<'COREDUMP_CONFIG'
# /etc/systemd/coredump.conf
[Coredump]
Storage=none
ProcessSizeMax=0
# /etc/systemd/coredump.conf.d/90-override.conf
[Coredump]
Storage=external
ProcessSizeMax=2G
COREDUMP_CONFIG

PATH="$TMP_DIR/bin:$PATH"
FAKE_SYSTEMD_CONFIG="$TMP_DIR/coredump-effective.conf"
export PATH FAKE_SYSTEMD_CONFIG
# shellcheck source=/dev/null
source "$TMP_DIR/effective-config-helpers.sh"

actual="$(cis_systemd_config_value systemd/coredump.conf /etc/systemd/coredump.conf Coredump Storage)" || fail "no se pudo calcular Storage efectivo"
[ "$actual" = "external" ] || fail "se ignoró el override de Storage (actual=$actual)"
actual="$(cis_systemd_config_value systemd/coredump.conf /etc/systemd/coredump.conf Coredump ProcessSizeMax)" || fail "no se pudo calcular ProcessSizeMax efectivo"
[ "$actual" = "2G" ] || fail "se ignoró el override de ProcessSizeMax (actual=$actual)"

if printf '%s\n' '# GRUB_CMDLINE_LINUX="quiet selinux=0"' 'GRUB_CMDLINE_LINUX="quiet rhgb"' |
   cis_stream_has_kernel_argument "selinux=0"; then
  fail "un argumento comentado no debe contar como activo"
fi
printf '%s\n' 'options root=UUID=example quiet selinux=0' > "$TMP_DIR/loader-entry.conf"
cis_file_has_kernel_argument "$TMP_DIR/loader-entry.conf" "selinux=0" ||
  fail "no se detectó selinux=0 en una entrada BLS activa"
printf '%s\n' 'options root=UUID=example quiet' > "$TMP_DIR/loader-entry.conf"
if cis_file_has_kernel_argument "$TMP_DIR/loader-entry.conf" "selinux=0"; then
  fail "un argumento ausente se marcó como presente"
fi

pass "core dumps evalúa overrides efectivos y SELinux examina argumentos activos"
