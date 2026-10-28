#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../lib/service-compat.sh
. "$ROOT_DIR/lib/service-compat.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

mockbin="$(mktemp -d)"
trap 'rm -rf "$mockbin"' EXIT
cat >"$mockbin/chkconfig" <<'MOCK'
#!/bin/sh
if [ "$1" = "--list" ]; then
  if [ "$MOCK_ENABLED" = "1" ]; then
    echo "$2 0:off 1:off 2:on 3:on 4:on 5:on 6:off"
  else
    echo "$2 0:off 1:off 2:off 3:off 4:off 5:off 6:off"
  fi
  exit 0
fi
exit 0
MOCK
cat >"$mockbin/service" <<'MOCK'
#!/bin/sh
case "$2" in
  status) [ "$MOCK_ACTIVE" = "1" ] ;;
  start|restart) exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$mockbin/chkconfig" "$mockbin/service"
export MOCK_ENABLED=1 MOCK_ACTIVE=1
# Export the mock PATH for the entire test process. Prefix assignments on
# individual shell-function calls can behave differently across shells and
# make command discovery depend on the invocation context.
export PATH="$mockbin:$PATH"
hash -r
command -v chkconfig | grep -F "$mockbin/chkconfig" >/dev/null || fail "no se está usando el mock chkconfig"
command -v service | grep -F "$mockbin/service" >/dev/null || fail "no se está usando el mock service"

ob_service_is_enabled_sysv fake-service || fail "SysV enabled on runlevel 3 was not detected"
ob_service_is_active_sysv fake-service || fail "SysV running service was not detected"
MOCK_ENABLED=0 ob_service_is_enabled_sysv fake-service && fail "SysV disabled service was reported enabled"
MOCK_ACTIVE=0 ob_service_is_active_sysv fake-service && fail "SysV stopped service was reported active"
pass "SysV chkconfig/service state checks"
