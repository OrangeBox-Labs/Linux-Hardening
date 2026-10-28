#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SELINUX="$ROOT_DIR/selinux-secure-setup.sh"
CORE="$ROOT_DIR/linux-hardening.sh"
GRUB="$ROOT_DIR/grub-hardening.sh"
fail(){ echo "[FAIL] $*" >&2; exit 1; }
pass(){ echo "[PASS] $*"; }
grep -Fq 'report_selinux_state()' "$CORE" || fail "baseline no informa SELinux"
! grep -Fq 'selinux-secure-setup.sh' "$CORE" || fail "baseline no debe invocar script SELinux"
! grep -Fq 'selinux-setup' "$CORE" || fail "SELinux no debe ser módulo del baseline"
grep -Fq 'SELINUX=permissive' "$SELINUX" || fail "script dedicado debe persistir Permissive"
grep -Fq 'setenforce 0' "$SELINUX" || fail "script dedicado debe admitir cambio runtime"
grep -Fq 'confirm_change()' "$SELINUX" || fail "cambio explícito exige confirmación"
grep -Fq 'Backup:' "$SELINUX" || fail "script dedicado debe respaldar config"
! grep -Eiq 'selinux=0|enforcing=0|selinux' "$GRUB" || fail "GRUB no debe tocar ni auditar SELinux"
pass "SELinux solo se informa en el baseline y se cambia mediante la utilidad exclusiva"
