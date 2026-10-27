#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

[ -s "$CORE" ] || fail "falta linux-hardening.sh"

# The previous implementation expanded empty arrays in a script using set -u.
if grep -Eq '\$\{(audit_args|fix_args)\[@\]\}' "$CORE"; then
  fail "run_companion_module todavía expande arrays opcionales vacíos"
fi

# Extract the actual helper from the production script and test its argument
# handling under nounset, as done by the legacy CentOS 6 Bash environment.
sed -n '/^run_companion_script() {/,/^}/p' "$CORE" > "$TMP_DIR/helper.sh"
[ -s "$TMP_DIR/helper.sh" ] || fail "no se pudo extraer run_companion_script"
# shellcheck source=/dev/null
source "$TMP_DIR/helper.sh"

cat > "$TMP_DIR/child.sh" <<'CHILD'
#!/usr/bin/env bash
printf 'argc=%s\n' "$#"
index=1
for arg in "$@"; do
  printf 'arg%s=%s\n' "$index" "$arg"
  index=$((index + 1))
done
CHILD
chmod +x "$TMP_DIR/child.sh"

output="$(run_companion_script "$TMP_DIR/child.sh" "" "")"
printf '%s\n' "$output" | grep -Fqx 'argc=0' ||
  fail "una llamada sin argumentos debe ejecutar el hijo con argc=0"

output="$(run_companion_script "$TMP_DIR/child.sh" "--check" "")"
printf '%s\n' "$output" | grep -Fqx 'argc=1' ||
  fail "un argumento opcional debe producir argc=1"
printf '%s\n' "$output" | grep -Fqx 'arg1=--check' ||
  fail "el argumento --check no se conservó"

output="$(run_companion_script "$TMP_DIR/child.sh" "--fix" "--custom-flag")"
printf '%s\n' "$output" | grep -Fqx 'argc=2' ||
  fail "dos argumentos opcionales deben producir argc=2"
printf '%s\n' "$output" | grep -Fqx 'arg1=--fix' ||
  fail "no se conservó --fix"
printf '%s\n' "$output" | grep -Fqx 'arg2=--custom-flag' ||
  fail "no se conservó --custom-flag"

pass "la invocación de módulos admite cero, uno o dos argumentos bajo set -u"
