#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
SYSCTL="$ROOT_DIR/lib/sysctl-safe.sh"
CONFIRM="$ROOT_DIR/lib/hardening-confirm.sh"
fail(){ echo "[FAIL] $*" >&2; exit 1; }
pass(){ echo "[PASS] $*"; }
grep -Fq 'ORANGEBOX_ASSUME_YES=1' "$CORE" || fail "core debe exportar aprobación automática"
grep -Fq 'ORANGEBOX_ASSUME_YES' "$SYSCTL" || fail "sysctl-safe debe admitir --fix automático"
grep -Fq 'ORANGEBOX_ASSUME_YES' "$CONFIRM" || fail "helper de confirmación debe admitir --fix automático"
grep -Fq 'AUTO-YES' "$CORE" || fail "core debe informar aprobación automática"
! grep -Fq 'shorewall' "$CORE" || fail "core contiene alcance Shorewall"
! grep -Fq 'shorewall' "$ROOT_DIR/network-hardening.sh" || fail "network-hardening contiene alcance Shorewall"
! grep -Fq 'audit-firewall-listeners.sh' "$CORE" || fail "core no debe invocar auditoría de firewall"
grep -Fq 'logrotate-full' "$CORE" || fail "logrotate debe estar registrado"
pass "--fix es automático y el hardening no gestiona firewalls"
