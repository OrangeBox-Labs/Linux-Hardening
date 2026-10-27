#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SELINUX="$ROOT_DIR/selinux-secure-setup.sh"
ORCHESTRATOR="$ROOT_DIR/linux-hardening.sh"
fail(){ printf '[FAIL] %s\\n' "$*" >&2; exit 1; }
pass(){ printf '[PASS] %s\\n' "$*"; }

grep -Fq 'FIX_REQUESTED=true' "$SELINUX" || fail "--fix debe conservar compatibilidad CLI sin aplicar cambios"
grep -Fq 'OrangeBox SELinux - auditoría estrictamente de solo lectura' "$SELINUX" || fail "no se declara explícitamente la política audit-only"
grep -Fq 'No modifica SELinux' "$SELINUX" || fail "el mensaje de --fix no explica que SELinux no se modifica"
grep -Fq 'No se modifica.' "$SELINUX" || fail "el estado persistente no se presenta como solo lectura"
! grep -Eq '^[[:space:]]*setenforce[[:space:]]' "$SELINUX" || fail "SELinux audit-only no debe ejecutar setenforce"
! grep -Eq '^[[:space:]]*(mv|sed[[:space:]]+-i|cp)[[:space:]].*/etc/selinux/config' "$SELINUX" || fail "SELinux audit-only no debe escribir /etc/selinux/config"
! grep -Fq 'apply_selinux_fix()' "$SELINUX" || fail "la función de remediación SELinux no debe existir"
grep -Fq 'selinux-setup) script="selinux-secure-setup.sh"; audit_only=true; fix_arg=""' "$ORCHESTRATOR" || fail "el orquestador no debe lanzar SELinux en modo fix"
pass "SELinux permanece estrictamente audit-only, incluido --fix, y siempre muestra advertencias sin cambiar el sistema"
