#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
grep -Fq 'COMPANION_MODULES_REBOOT_REQUIRED=1' "$CORE" || fail "el orquestador debe preservar el estado de mantenimiento pendiente"
grep -Fq 'if [ "$COMPANION_MODULES_REBOOT_REQUIRED" -eq 1 ]; then return 3; fi' "$CORE" || fail "el orquestador debe devolver código 3 si un módulo requiere reinicio controlado"
pass "--fix es automático, propaga mantenimiento pendiente y el hardening no gestiona firewalls"
