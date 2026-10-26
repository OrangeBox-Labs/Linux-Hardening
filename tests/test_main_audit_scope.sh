#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
MAIN="$ROOT_DIR/linux-hardening.sh"
FIREWALL="$ROOT_DIR/audit-firewall-listeners.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
[ -f "$MAIN" ] || fail "falta linux-hardening.sh"
[ -f "$FIREWALL" ] || fail "falta el auditor independiente"
if grep -Eq 'source .*lib/(listener-firewall-audit|firewall-detect)\.sh|lfa_audit_listener_firewall|firewall_report_detected' "$MAIN"; then
  fail "el orquestador aún incorpora la auditoría detallada de firewall"
fi
grep -Fq 'PENDING_ONLY_AUDIT=true' "$MAIN" || fail "falta el modo de pendientes corregibles"
grep -Fq 'for m in ssh sudo kernel synflood rsyslog banners bash; do' "$MAIN" || fail "hay módulos no correctivos en el reporte principal"
grep -Fq 'firewall) die "La auditoría de firewall es independiente:' "$MAIN" || fail "firewall no remite al comando independiente"
grep -Fq 'listening) die "El inventario de sockets es independiente:' "$MAIN" || fail "listeners no remite al comando independiente"
grep -Fq 'source "$SCRIPT_DIR/lib/firewall-detect.sh"' "$FIREWALL" || fail "falta detección de backend"
grep -Fq 'source "$SCRIPT_DIR/lib/listener-firewall-audit.sh"' "$FIREWALL" || fail "falta auditoría de listeners"
grep -Fq 'firewall_report_detected' "$FIREWALL" || fail "falta inventario de firewall"
grep -Fq 'lfa_audit_listener_firewall' "$FIREWALL" || fail "falta correlación de INPUT/listeners"
pass "auditoría de pendientes separada de la auditoría de firewall"
