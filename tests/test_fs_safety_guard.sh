#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
FS="$ROOT_DIR/FS-hardening.sh"
CORE="$ROOT_DIR/linux-hardening.sh"
fail(){ printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass(){ printf '[PASS] %s\n' "$*"; }

grep -Fq 'AUTO_FIX=false' "$FS" || fail "filesystem hardening debe iniciar en modo auditoría"
grep -Fq 'case "$1" in' "$FS" || fail "FS-hardening debe discriminar --fix explícitamente"
grep -Fq -- '--fix      - Aplicar cambios, con confirmación individual por parámetro' "$FS" || fail "ayuda no documenta --fix y consentimiento por parámetro"
grep -Fq 'confirm_fs_change()' "$FS" || fail "faltan confirmaciones por parámetro"
grep -Fq 'No hay terminal interactiva; se omite el cambio por seguridad.' "$FS" || fail "cambio no se omite en modo no interactivo"
grep -Fq 'noexec) effect=' "$FS" || fail "noexec no explica que puede romper ejecución de aplicaciones"
grep -Fq 'hidepid=2' "$FS" || fail "hidepid no se verifica"
grep -Fiq 'puede romper o limitar agentes de monitoreo' "$FS" || fail "hidepid no explica impacto en monitoreo"
if grep -Eq 'rmmod[[:space:]]+"?\$module' "$FS"; then fail "FS-hardening no debe descargar módulos de filesystem en caliente"; fi
grep -Fq 'backup_fs_file /etc/fstab' "$FS" || fail "fstab no se respalda antes de cambios de montaje"
grep -Fq 'fix_arg="--fix"' "$CORE" || fail "el orquestador no pasa --fix al módulo filesystem-full"
pass "filesystem: modo auditoría por defecto, confirmación por parámetro, backups y sin rmmod en caliente"
