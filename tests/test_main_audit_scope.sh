#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
MAIN="$ROOT_DIR/linux-hardening.sh"
NETWORK="$ROOT_DIR/network-hardening.sh"
fail(){ echo "[FAIL] $*" >&2; exit 1; }
pass(){ echo "[PASS] $*"; }
grep -Fq 'report_selinux_state()' "$MAIN" || fail "el baseline debe informar SELinux"
! grep -Fq 'selinux-secure-setup.sh' "$MAIN" || fail "el baseline no debe invocar el script dedicado SELinux"
! grep -Fq 'selinux-setup' "$MAIN" || fail "SELinux no debe ser un módulo del baseline"
! grep -Fq 'shorewall' "$MAIN" || fail "linux-hardening contiene lógica Shorewall"
! grep -Fq 'shorewall' "$NETWORK" || fail "network-hardening contiene lógica Shorewall"
if grep -Eiq 'iptables-save|iptables[[:space:]]+-|nft[[:space:]]+(add|delete|flush)|csf[[:space:]]+(-[a-z]|--)' "$MAIN" "$NETWORK"; then
  fail "el hardening contiene referencias operativas a firewalls"
fi
grep -Fq 'ORANGEBOX_ASSUME_YES=1' "$MAIN" || fail "--fix debe propagar aprobación automática"
grep -Fq 'MODO --FIX AUTOMÁTICO' "$MAIN" || fail "el modo fix debe anunciarse como automático"
grep -Fq 'logrotate-full' "$MAIN" || fail "logrotate debe formar parte del baseline"
! grep -Fq 'audit-firewall-listeners.sh' "$MAIN" || fail "el baseline no debe ejecutar auditoría firewall"
pass "SELinux informativo, firewall fuera de alcance, --fix automático y logrotate incluido"
