#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
AUDITD="$ROOT_DIR/auditd-hardening.sh"
GRUB="$ROOT_DIR/grub-hardening.sh"
AGGREGATOR="$ROOT_DIR/linux-hardening-audit.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

grep -Fq 'legacy_auditd_readonly()' "$AUDITD" || fail "auditd-hardening no ofrece auditoría legacy EL6"
grep -Fq '/etc/audit/audit.rules' "$AUDITD" || fail "auditd legacy no verifica la ruta de reglas EL6"
grep -Fq 'audit_legacy_grub_readonly()' "$GRUB" || fail "grub-hardening no ofrece auditoría de GRUB legacy"
grep -Fq '/boot/grub/grub.conf' "$GRUB" || fail "GRUB legacy no verifica grub.conf"
if grep -Fq '.*release[[:space:]]+([0-9]+).*/\\1/p' "$GRUB"; then
  fail "el detector GRUB legacy tiene una referencia sed con doble escape"
fi
if grep -Fq 'grub-full) skip_reason=' "$AGGREGATOR" || grep -Fq 'auditd-full) skip_reason=' "$AGGREGATOR"; then
  fail "el agregador sigue omitiendo controles auditd/GRUB en EL6"
fi
grep -Fq 'ssh-complete) skip_reason=' "$AGGREGATOR" || fail "el agregador no conserva el skip explícito del SSH Complete no compatible"
pass "EL6 recibe auditoría legacy de auditd y GRUB; solo se omiten controles explícitamente incompatibles"
