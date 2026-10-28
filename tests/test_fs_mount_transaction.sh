#!/usr/bin/env bash
# Regression tests for FS-hardening.sh mount persistence/rollback.
# All filesystem, mount, and systemd operations are redirected to a temporary
# directory or mocked shell functions. This test never edits the host /etc/fstab
# and never invokes the real mount/systemctl commands.
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FS="$ROOT_DIR/FS-hardening.sh"
TEST_DIR="$(mktemp -d)"
TEST_FSTAB="$TEST_DIR/fstab"
trap 'rm -rf -- "$TEST_DIR"' EXIT

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

[[ -f "$FS" ]] || fail "No se encontró FS-hardening.sh"
bash -n "$FS" || fail "FS-hardening.sh tiene errores de sintaxis"

# Mock host operations. Function definitions override external commands.
backup_fs_file() { return 0; }
SYSTEMCTL_RC=0
MOUNT_RC=0
ACTIVE_OPTIONS="rw,nosuid,nodev,noexec,inode64"
systemctl() { return "$SYSTEMCTL_RC"; }
mount() { return "$MOUNT_RC"; }
findmnt() {
  if [[ " $* " == *" OPTIONS "* ]]; then
    printf '%s\n' "$ACTIVE_OPTIONS"
  fi
  return 0
}

# Load only the transaction functions, rewriting /etc paths into the temp dir.
# eval happens in this test process; no production paths are left in the loaded
# functions.
eval "$(sed -n '/^persist_mount_options()/,/^}/p; /^apply_mount_options_from_fstab()/,/^}/p' "$FS" | sed 's|/etc|${TEST_DIR}|g')"

write_fstab() {
  cat > "$TEST_FSTAB"
}
shm_count() {
  awk '$0 !~ /^[[:space:]]*#/ && NF >= 2 && $2 == "/dev/shm" {n++} END {print n+0}' "$TEST_FSTAB"
}
shm_opts() {
  awk '$0 !~ /^[[:space:]]*#/ && NF >= 4 && $2 == "/dev/shm" {print $4; exit}' "$TEST_FSTAB"
}

# 1. Missing /dev/shm entry: create one and apply required options.
write_fstab <<'EOF'
UUID=aaaa / ext4 defaults 1 1
EOF
SYSTEMCTL_RC=0 MOUNT_RC=0 ACTIVE_OPTIONS="rw,nosuid,nodev,noexec,inode64"
apply_mount_options_from_fstab /dev/shm true "tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0" noexec nosuid nodev >/dev/null 2>&1 ||
  fail "No pudo crear y aplicar la entrada ausente de /dev/shm"
[[ "$(shm_count)" == 1 ]] || fail "La entrada ausente no se creó exactamente una vez"
[[ "$(shm_opts)" == *noexec* && "$(shm_opts)" == *nosuid* && "$(shm_opts)" == *nodev* ]] ||
  fail "La entrada creada no contiene las opciones obligatorias"
pass "crea la entrada /dev/shm ausente y aplica las opciones aprobadas"

# 2. Canonicalization: collapse duplicates, preserve mode/size, remain idempotent.
write_fstab <<'EOF'
UUID=aaaa / ext4 defaults 1 1
tmpfs /dev/shm tmpfs mode=1777,size=1G,nosuid,nodev 0 0
tmpfs /dev/shm tmpfs defaults 0 0
EOF
persist_mount_options /dev/shm true "tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0" noexec nosuid nodev >/dev/null ||
  fail "Falló la normalización de entradas duplicadas"
[[ "$(shm_count)" == 1 ]] || fail "La normalización dejó entradas duplicadas"
opts="$(shm_opts)"
[[ "$opts" == *mode=1777* && "$opts" == *size=1G* && "$opts" == *noexec* && "$opts" == *nosuid* && "$opts" == *nodev* ]] ||
  fail "No preservó mode/size u opciones requeridas: $opts"
before="$opts"
persist_mount_options /dev/shm true "tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0" noexec nosuid nodev >/dev/null ||
  fail "La segunda normalización falló"
[[ "$(shm_count)" == 1 && "$(shm_opts)" == "$before" ]] ||
  fail "La normalización repetida no es idempotente"
pass "elimina duplicados, preserva mode/size y es idempotente"

# 3. Remount failure: restore the exact previous fstab content.
write_fstab <<'EOF'
UUID=aaaa / ext4 defaults 1 1
tmpfs /dev/shm tmpfs defaults,nosuid,nodev 0 0
EOF
cp "$TEST_FSTAB" "$TEST_DIR/expected"
SYSTEMCTL_RC=0 MOUNT_RC=32 ACTIVE_OPTIONS="rw,nosuid,nodev"
if apply_mount_options_from_fstab /dev/shm true "tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0" noexec >/dev/null 2>&1; then
  fail "Debió fallar cuando el remount simulado falla"
fi
cmp -s "$TEST_FSTAB" "$TEST_DIR/expected" || fail "No restauró fstab tras fallo de remount"
pass "revierte fstab cuando falla el remount"

# 4. Verification failure: remount succeeds but the required option is absent.
write_fstab <<'EOF'
UUID=aaaa / ext4 defaults 1 1
tmpfs /dev/shm tmpfs defaults,nosuid,nodev 0 0
EOF
cp "$TEST_FSTAB" "$TEST_DIR/expected"
SYSTEMCTL_RC=0 MOUNT_RC=0 ACTIVE_OPTIONS="rw,nosuid,nodev"
if apply_mount_options_from_fstab /dev/shm true "tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0" noexec >/dev/null 2>&1; then
  fail "Debió fallar si findmnt no refleja noexec"
fi
cmp -s "$TEST_FSTAB" "$TEST_DIR/expected" || fail "No restauró fstab tras fallo de validación"
pass "revierte fstab cuando findmnt no confirma la opción"

# 5. systemd reload failure: restore fstab and return failure.
write_fstab <<'EOF'
UUID=aaaa / ext4 defaults 1 1
tmpfs /dev/shm tmpfs defaults,nosuid,nodev 0 0
EOF
cp "$TEST_FSTAB" "$TEST_DIR/expected"
SYSTEMCTL_RC=1 MOUNT_RC=0 ACTIVE_OPTIONS="rw,nosuid,nodev,noexec"
if apply_mount_options_from_fstab /dev/shm true "tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0" noexec >/dev/null 2>&1; then
  fail "Debió fallar si daemon-reload falla"
fi
cmp -s "$TEST_FSTAB" "$TEST_DIR/expected" || fail "No restauró fstab tras fallo de daemon-reload"
pass "revierte fstab cuando falla systemctl daemon-reload"

pass "todas las pruebas aisladas de persistencia y rollback finalizaron"
