#!/usr/bin/env bash
# Pruebas aisladas del diagnóstico de backends/reglas de firewall.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Create test executables inside the repository checkout. Executing mocks from
# /tmp, /var/tmp or /dev/shm triggers the production rule for execution from
# critical temporary locations and creates misleading alerts.
# Do not fall back to watched temporary directories if the checkout is noexec.
create_exec_tempdir() {
  local candidate probe
  candidate="$(mktemp -d "$ROOT_DIR/.orangebox-firewall-test.XXXXXX" 2>/dev/null)" || return 1
  probe="$candidate/.exec-test"
  if printf '#!/bin/sh\nexit 0\n' > "$probe" &&
     chmod 700 "$probe" &&
     "$probe" >/dev/null 2>&1; then
    rm -f "$probe"
    printf '%s\n' "$candidate"
    return 0
  fi
  rm -rf "$candidate"
  return 1
}

TMP="$(create_exec_tempdir)" || fail "no hay un directorio temporal escribible y ejecutable; revisa permisos y montajes noexec"
trap 'rm -rf "$TMP"' EXIT
MOCK_BIN="$TMP/bin"
RULES="$TMP/rules"
mkdir -p "$MOCK_BIN" "$RULES"

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

# Run assertions in a clean non-interactive Bash. env -i drops exported Bash
# functions, BASH_ENV, provider-specific wrappers and inherited environment
# variables that may shadow command lookup on hardened/hosting servers.
env -i \
  PATH="$MOCK_BIN:/usr/bin:/bin" \
  ROOT_DIR="$ROOT_DIR" \
  MOCK_BIN="$MOCK_BIN" \
  FAKE_RULES_DIR="$RULES" \
  /bin/bash --noprofile --norc -s <<'TEST_CASE'
set -euo pipefail
source "$ROOT_DIR/lib/firewall-detect.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

hash -r
[ "$(type -P iptables)" = "$MOCK_BIN/iptables" ] || fail "el mock de iptables no se resuelve desde el PATH aislado (type -P=$(type -P iptables 2>/dev/null || true))"
[ "$(type -P iptables-save)" = "$MOCK_BIN/iptables-save" ] || fail "el mock de iptables-save no se resuelve desde el PATH aislado"

printf '%s\n' 'iptables v1.8.10 (nf_tables)' > "$FAKE_RULES_DIR/iptables.version"
[ "$(firewall_frontend_backend iptables)" = nf_tables ] || fail "no detectó backend nf_tables"

printf '%s\n' 'iptables v1.8.10 (legacy)' > "$FAKE_RULES_DIR/iptables.version"
hash -r
legacy_output="$(iptables -V 2>/dev/null)" || fail "no se pudo consultar el mock de iptables"
[ "$legacy_output" = 'iptables v1.8.10 (legacy)' ] || fail "el mock no devolvió la versión legacy: $legacy_output"
detected_backend="$(firewall_frontend_backend iptables)"
[ "$detected_backend" = legacy ] || fail "no detectó backend legacy (obtuvo: $detected_backend; version=$legacy_output)"

for cmd in iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
  printf '%s\n' '*filter' COMMIT > "$FAKE_RULES_DIR/$cmd.rules"
done

# Imunify360 únicamente en el volcado legacy IPv4.
printf '%s\n' '*filter' ':INPUT_imunify360 - [0:0]' '-A INPUT -j INPUT_imunify360' COMMIT \
  > "$FAKE_RULES_DIR/iptables-legacy-save.rules"
firewall_has_imunify360_rules || fail "no detectó Imunify360 en iptables-legacy-save"

# También se revisa legacy IPv6.
printf '%s\n' '*filter' COMMIT > "$FAKE_RULES_DIR/iptables-legacy-save.rules"
printf '%s\n' '*filter' ':imunify360_webshield_ports - [0:0]' COMMIT \
  > "$FAKE_RULES_DIR/ip6tables-legacy-save.rules"
firewall_has_imunify360_rules || fail "no detectó Imunify360 en ip6tables-legacy-save"

# Sin referencias a Imunify360, no debe haber falso positivo.
for cmd in iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
  printf '%s\n' '*filter' COMMIT > "$FAKE_RULES_DIR/$cmd.rules"
done
if firewall_has_imunify360_rules; then fail "falso positivo de Imunify360"; fi

diagnostics="$(firewall_print_backend_diagnostics)"
printf '%s\n' "$diagnostics" | grep -q 'iptables-legacy-save: accesible' || fail "no informa legacy"
printf '%s\n' "$diagnostics" | grep -q 'iptables: backend=legacy' || fail "no muestra backend seleccionado"
pass "backend nf_tables/legacy e Imunify360 en reglas IPv4/IPv6, actuales y legacy"
TEST_CASE
