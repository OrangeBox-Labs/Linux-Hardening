#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CIS="$ROOT_DIR/cis-benchmark-check.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Extract only the check under test so mocked modprobe and runtime paths do not affect the host.
awk '
  /^check_tipc\(\) \{$/ { inside=1 }
  inside { print }
  inside && /^}$/ { exit }
' "$CIS" > "$TMP_DIR/check-tipc.sh"
[[ -s "$TMP_DIR/check-tipc.sh" ]] || fail "no se pudo extraer check_tipc"

cat > "$TMP_DIR/harness.sh" <<'HARNESS'
RED=red
GREEN=green
YELLOW=yellow
log_result() { printf '[%s] %s - %s\n' "$1" "$2" "$3"; }
HARNESS
cat "$TMP_DIR/check-tipc.sh" >> "$TMP_DIR/harness.sh"
cat >> "$TMP_DIR/harness.sh" <<'HARNESS'

run_check() {
    check_tipc
}
HARNESS

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/sys/module"
: > "$TMP_DIR/proc.modules"

cat > "$TMP_DIR/bin/modprobe" <<'MODPROBE'
#!/usr/bin/env bash
set -u
if [[ "$1" = "-n" && "$2" = "-v" && "$3" = "tipc" ]]; then
    case "${TEST_TIPC_MODULE:-present}" in
        missing)
            echo "modprobe: FATAL: Module tipc not found in directory /lib/modules/test"
            exit 1
            ;;
        present)
            case "${TEST_TIPC_INSTALL:-false}" in
                false) echo "install /bin/false" ;;
                true) echo "install /bin/true" ;;
                none) echo "insmod /lib/modules/test/kernel/net/tipc/tipc.ko" ;;
            esac
            ;;
    esac
    exit 0
fi
if [[ "$1" = "-c" ]]; then
    [[ "${TEST_TIPC_BLACKLIST:-yes}" = yes ]] && echo "blacklist tipc"
    exit 0
fi
exit 2
MODPROBE
chmod 700 "$TMP_DIR/bin/modprobe"

export PATH="$TMP_DIR/bin:$PATH"
export CIS_MODULE_PROC="$TMP_DIR/proc.modules"
export CIS_MODULE_SYSROOT="$TMP_DIR/sys/module"

# Installed policy: install /bin/false + blacklist; module absent from runtime.
if output="$(TEST_TIPC_INSTALL=false TEST_TIPC_BLACKLIST=yes bash -c 'source "$1"; run_check' _ "$TMP_DIR/harness.sh" 2>&1)"; then
    [[ "$output" == *"[PASS]"* ]] || fail "la política correcta no produjo PASS: $output"
else
    fail "TIPC con install /bin/false + blacklist efectiva debe pasar: $output"
fi

# A module loaded in the running kernel must fail even when its persistent policy is correct.
mkdir -p "$TMP_DIR/sys/module/tipc"
if output="$(TEST_TIPC_INSTALL=false TEST_TIPC_BLACKLIST=yes bash -c 'source "$1"; run_check' _ "$TMP_DIR/harness.sh" 2>&1)"; then
    fail "TIPC cargado en runtime fue aceptado: $output"
else
    [[ "$output" == *"[FAIL]"* ]] || fail "no se informó FAIL para TIPC cargado: $output"
fi
rmdir "$TMP_DIR/sys/module/tipc"

# A blacklist without an effective install blocker is incomplete.
if output="$(TEST_TIPC_INSTALL=none TEST_TIPC_BLACKLIST=yes bash -c 'source "$1"; run_check' _ "$TMP_DIR/harness.sh" 2>&1)"; then
    fail "TIPC sin install blocker fue aceptado: $output"
else
    [[ "$output" == *"[FAIL]"* ]] || fail "no se informó FAIL para política incompleta: $output"
fi

# A module missing from the module tree and absent at runtime is not enabled.
if output="$(TEST_TIPC_MODULE=missing TEST_TIPC_BLACKLIST=no bash -c 'source "$1"; run_check' _ "$TMP_DIR/harness.sh" 2>&1)"; then
    [[ "$output" == *"[PASS]"* ]] || fail "módulo no disponible no produjo PASS: $output"
else
    fail "un TIPC ausente del árbol de módulos debe pasar: $output"
fi

pass "TIPC: bloqueado y descargado PASS; cargado o con política incompleta FAIL; ausente PASS"
