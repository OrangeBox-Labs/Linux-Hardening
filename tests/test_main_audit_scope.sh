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
# SSH stays in the compact audit when the drop-in route is unavailable.
grep -Fq 'section "SSH"' "$MAIN" || fail "el módulo SSH no genera su sección de auditoría"
if grep -Fq 'ssh_module_can_apply || return 0' "$MAIN"; then
  fail "la auditoría compacta todavía oculta SSH si el drop-in no es aplicable"
fi
grep -Fq 'ssh_apply_pending_settings' "$MAIN" || fail "falta el flujo de aplicación segura de SSH"
grep -Fq 'SSH_MANAGED_BEGIN="# BEGIN ORANGEBOX SSH HARDENING MANAGED BLOCK"' "$MAIN" || fail "falta el bloque gestionado alternativo de sshd_config"
grep -Fq 'ssh_print_manual_remediation' "$MAIN" || fail "falta la guía de remediación manual SSH"
grep -Fq 'systemctl reload sshd' "$MAIN" || fail "falta la recarga de sshd tras validar el cambio"
grep -Fq 'firewall_report_detected' "$FIREWALL" || fail "falta inventario de firewall"
grep -Fq 'lfa_audit_listener_firewall' "$FIREWALL" || fail "falta correlación de INPUT/listeners"
# Default audit must present both success and pending counts.
grep -Fq 'OK_COUNT=0' "$MAIN" || fail "falta el contador de controles correctos"
grep -Fq 'echo "Controles correctos: $OK_COUNT"' "$MAIN" || fail "falta el resumen de controles correctos"
grep -Fq 'echo "Pendientes: $WARNINGS"' "$MAIN" || fail "falta el resumen de pendientes"
grep -Fq 'echo "Errores: $ERRORS"' "$MAIN" || fail "falta el resumen de errores"
grep -Fq 'case "$level" in INFO|CAMBIO\ PROPUESTO) return 0 ;; esac' "$ROOT_DIR/lib/sysctl-safe.sh" || fail "la biblioteca sysctl sigue ocultando los estados OK"

# Exercise the helper with the compact-audit flag exactly as the baseline does.
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
# shellcheck source=lib/sysctl-safe.sh
source "$ROOT_DIR/lib/sysctl-safe.sh"
PENDING_ONLY_AUDIT=true
OK_COUNT=0
sysctl_safe_log "OK" "control de prueba conforme" > "$OUT"
grep -Fq '[SYSCTL][OK]' "$OUT" || fail "sysctl_safe_log no muestra el estado OK"
grep -Fq 'control de prueba conforme' "$OUT" || fail "sysctl_safe_log no muestra el detalle del estado OK"
[ "$OK_COUNT" -eq 1 ] || fail "el estado OK de sysctl no incrementa el contador"
: > "$OUT"
sysctl_safe_log "INFO" "mensaje informativo oculto" > "$OUT"
[ ! -s "$OUT" ] || fail "el reporte predeterminado aún muestra mensajes informativos no accionables"
[ "$OK_COUNT" -eq 1 ] || fail "un mensaje informativo alteró el contador OK"

pass "auditoría presenta estados OK y pendientes, con resumen y firewall independiente"
