#!/usr/bin/env bash
# Pruebas aisladas del diagnóstico de backends/reglas de firewall.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/firewall-detect.sh
source "$ROOT_DIR/lib/firewall-detect.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MOCK_BIN="$TMP/bin"
RULES="$TMP/rules"
mkdir -p "$MOCK_BIN" "$RULES"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

for cmd in iptables ip6tables iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
  cat > "$MOCK_BIN/$cmd" <<'MOCK_COMMAND'
#!/bin/sh
name="$(basename "$0")"
if [ "$#" -gt 0 ] && [ "$1" = "-V" ]; then
  if [ -r "$FAKE_RULES_DIR/$name.version" ]; then
    cat "$FAKE_RULES_DIR/$name.version"
  else
    echo "$name v1.8.10 (nf_tables)"
  fi
else
  [ -r "$FAKE_RULES_DIR/$name.rules" ] || exit 1
  cat "$FAKE_RULES_DIR/$name.rules"
fi
MOCK_COMMAND
  chmod 755 "$MOCK_BIN/$cmd"
done

# Do not allow inherited aliases/functions to shadow the mocks. Bash can import
# exported functions from the parent shell (for example through BASH_FUNC_*).
for cmd in iptables ip6tables iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
  unset -f "$cmd" 2>/dev/null || :
  unalias "$cmd" 2>/dev/null || :
done

export PATH="$MOCK_BIN:$PATH"
export FAKE_RULES_DIR="$RULES"
# Clear Bash's command hash so tests always execute the mocks just created.
hash -r
resolved_iptables="$(type -P iptables 2>/dev/null || true)"
resolved_iptables_save="$(type -P iptables-save 2>/dev/null || true)"
[ "$resolved_iptables" = "$MOCK_BIN/iptables" ] || fail "el mock de iptables no se resuelve desde PATH (type -P=$resolved_iptables; command -v=$(command -v iptables 2>/dev/null || true))"
[ "$resolved_iptables_save" = "$MOCK_BIN/iptables-save" ] || fail "el mock de iptables-save no se resuelve desde PATH (type -P=$resolved_iptables_save; command -v=$(command -v iptables-save 2>/dev/null || true))"
printf '%s\n' 'iptables v1.8.10 (nf_tables)' > "$RULES/iptables.version"
[ "$(firewall_frontend_backend iptables)" = nf_tables ] || fail "no detectó backend nf_tables"
printf '%s\n' 'iptables v1.8.10 (legacy)' > "$RULES/iptables.version"
hash -r
legacy_output="$(iptables -V 2>/dev/null)" || fail "no se pudo consultar el mock de iptables"
[ "$legacy_output" = 'iptables v1.8.10 (legacy)' ] || fail "el mock no devolvió la versión legacy: $legacy_output"
detected_backend="$(firewall_frontend_backend iptables)"
[ "$detected_backend" = legacy ] || fail "no detectó backend legacy (obtuvo: $detected_backend; version=$legacy_output)"

for cmd in iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
  printf '%s\n' '*filter' COMMIT > "$RULES/$cmd.rules"
done

# Imunify360 únicamente en el volcado legacy IPv4.
printf '%s\n' '*filter' ':INPUT_imunify360 - [0:0]' '-A INPUT -j INPUT_imunify360' COMMIT \
  > "$RULES/iptables-legacy-save.rules"
firewall_has_imunify360_rules || fail "no detectó Imunify360 en iptables-legacy-save"

# También se revisa legacy IPv6.
printf '%s\n' '*filter' COMMIT > "$RULES/iptables-legacy-save.rules"
printf '%s\n' '*filter' ':imunify360_webshield_ports - [0:0]' COMMIT \
  > "$RULES/ip6tables-legacy-save.rules"
firewall_has_imunify360_rules || fail "no detectó Imunify360 en ip6tables-legacy-save"

# Sin referencias a Imunify360, no debe haber falso positivo.
for cmd in iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
  printf '%s\n' '*filter' COMMIT > "$RULES/$cmd.rules"
done
if firewall_has_imunify360_rules; then fail "falso positivo de Imunify360"; fi

diagnostics="$(firewall_print_backend_diagnostics)"
printf '%s\n' "$diagnostics" | grep -q 'iptables-legacy-save: accesible' || fail "no informa legacy"
printf '%s\n' "$diagnostics" | grep -q 'iptables: backend=legacy' || fail "no muestra backend seleccionado"
pass "backend nf_tables/legacy e Imunify360 en reglas IPv4/IPv6, actuales y legacy"
