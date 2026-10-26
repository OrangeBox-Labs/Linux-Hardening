#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SELINUX="$ROOT_DIR/selinux-secure-setup.sh"
fail(){ printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass(){ printf '[PASS] %s\n' "$*"; }
grep -Fq 'AUTO_FIX=false' "$SELINUX" || fail "el modo por defecto no es auditoría"
grep -Fq 'confirm_selinux_change' "$SELINUX" || fail "falta confirmación interactiva"
grep -Fq 'setenforce 1' "$SELINUX" || fail "falta transición runtime desde Permissive"
grep -Fq 'SELINUX=enforcing' "$SELINUX" || fail "falta el cambio persistente"
grep -Fq 'No se habilita automáticamente' "$SELINUX" || fail "no se protege el modo Disabled"
grep -Fq '/var/backups/orangebox-selinux-hardening-' "$SELINUX" || fail "falta backup antes de cambiar SELinux"
! grep -Eq '^[[:space:]]*(restorecon|semanage|reboot)[[:space:]]' "$SELINUX" || fail "no debe ejecutar relabel, semanage o reboot"
pass "SELinux audit-only by default; --fix requires consent and preserves Disabled"
