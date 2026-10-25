#!/usr/bin/env bash
# Regression guards for per-control idempotence, MOTD branding, and shell timeout.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CORE="$ROOT_DIR/linux-hardening.sh"
SYSCTL="$ROOT_DIR/lib/sysctl-safe.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

# Kernel/SYN flood must rely on per-parameter sysctl checks, not a blanket module prompt.
grep -Fq '      kernel)' "$CORE" || fail "kernel no tiene tratamiento de confirmación por parámetro"
grep -Fq '      synflood)' "$CORE" || fail "SYN flood no tiene tratamiento de confirmación por parámetro"
grep -Fq 'solo los que falten o difieran solicitarán confirmación' "$CORE" || fail "falta la política de confirmación por parámetro"
grep -Fq 'sysctl_safe_apply ' "$CORE" || fail "baseline dejó de usar el helper seguro de sysctl"

# sudo owns its specific prompt and is explicitly exempt from a redundant generic prompt.
grep -Fq '      sudo)' "$CORE" || fail "sudo no tiene una rama de confirmación específica"
grep -Fq 'solo su control específico puede solicitar confirmación' "$CORE" || fail "sudo aún depende de confirmación genérica"
grep -Fq 'cPanel detectado: por política OrangeBox no se activa use_pty' "$CORE" || fail "se perdió la exclusión de use_pty en cPanel"

# Journald should not ask/restart when already persistent; unavailable config stays read-only.
grep -Fq 'rsyslog_state_status()' "$CORE" || fail "falta preflight de journald"
grep -Fq 'Journald ya tiene Storage=persistent y /var/log/journal' "$CORE" || fail "falta omitir la confirmación de journald conforme"
grep -Fq 'journal_status=$?' "$CORE" || fail "el resultado del preflight de journald no se utiliza"
grep -Fq 'if ! confirm_risky_change "$name"; then' "$CORE" || fail "se perdió confirmación cuando rsyslog requiere cambios"

# Persistence-only changes are pending changes and must receive their own consent.
grep -Fq 'falta persistencia' "$SYSCTL" || fail "sysctl no distingue runtime correcto de persistencia ausente"
grep -Fq '¿Confirmas persistir %s=%s en %s? [s/N]' "$SYSCTL" || fail "no hay confirmación para cambios solo de persistencia"

# MOTD is deliberately different from the large pre-authentication legal banner.
grep -Fq 'ORANGEBOX IT SERVICES' "$CORE" || fail "MOTD perdió la marca OrangeBox"
grep -Fq 'LINUX ENTERPRISE  /  INFRAESTRUCTURA  /  SEGURIDAD' "$CORE" || fail "falta el subtítulo de marca en MOTD"
grep -Fq 'Las sesiones pueden ser registradas y auditadas.' "$CORE" || fail "falta el aviso breve del MOTD"

# Idle timeout is two minutes for interactive non-root sessions; root clears inherited TMOUT.
grep -Fq 'TMOUT=120' "$CORE" || fail "falta timeout interactivo de 120 segundos"
grep -Fq 'unset TMOUT 2>/dev/null || true' "$CORE" || fail "la shell root no elimina TMOUT heredado"
grep -Fq 'readonly TMOUT' "$CORE" || fail "TMOUT no está protegido contra cambios por el usuario"
grep -Fq 'solo aplica a shells interactivos' "$CORE" || fail "no se limita el resto del perfil a shells interactivos"

pass "confirmaciones idempotentes, MOTD de marca y TMOUT=120 exclusivo para sesiones interactivas no-root"
