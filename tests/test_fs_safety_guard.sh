#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FS="$ROOT_DIR/FS-hardening.sh"
fail(){ echo "[FAIL] $*" >&2; exit 1; }
pass(){ echo "[PASS] $*"; }
grep -Fq '["/var"]="noexec,nosuid,nodev"' "$FS" || fail "/var debe conservar noexec,nosuid,nodev"
grep -Fq '["/home"]="noexec,nosuid,nodev"' "$FS" || fail "/home debe incluir noexec,nosuid,nodev"
! grep -Fq '["/proc"]="hidepid=2"' "$FS" || fail "/proc no debe aplicar hidepid=2"
! grep -Fq 'configure_proc()' "$FS" || fail "no debe existir el control hidepid"
grep -Fq 'ORANGEBOX_ASSUME_YES' "$FS" || fail "--fix debe ser automático"
grep -Fq 'Qué hace: bloquea la ejecución directa de binarios en $mount_point' "$FS" || fail "noexec necesita descripción clara"
pass "filesystem mantiene noexec y no activa hidepid=2"
