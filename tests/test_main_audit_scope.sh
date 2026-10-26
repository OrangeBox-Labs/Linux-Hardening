#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
MAIN="$ROOT_DIR/linux-hardening.sh"
FIREWALL="$ROOT_DIR/audit-firewall-listeners.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
[ -f "$MAIN" ] || fail "falta linux-hardening.sh"
[ -f "$FIREWALL" ] || fail "falta el auditor independiente"
if grep -Eq 'source .*lib/(listener-firewall-audit|firewall-detect)\.sh|lfa_audit_listener_firewall|firewall_report_detected' "$MAIN"; then
  fail "el orquestador aún incorpora la auditoría detallada de firewall"
fi
grep -Fq 'PENDING_ONLY_AUDIT=true' "$MAIN" || fail "falta el modo de pendientes corregibles"
grep -Fq 'for m in ssh sudo kernel synflood rsyslog banners bash; do' "$MAIN" || fail "hay módulos no correctivos en el reporte principal"
grep -Fq 'firewall) die "La auditoría de firewall es independiente:' "$MAIN" || fail "firewall no remite al comando independiente"
grep -Fq 'listening) die "El inventario de sockets es independiente:' "$MAIN" || fail "listeners no remite al comando independiente"
grep -Fq 'source "$SCRIPT_DIR/lib/firewall-detect.sh"' "$FIREWALL" || fail "falta detección de backend"
grep -Fq 'source "$SCRIPT_DIR/lib/listener-firewall-audit.sh"' "$FIREWALL" || fail "falta auditoría de listeners"
# SSH stays in the compact audit when the drop-in route is unavailable.
grep -Fq 'section "SSH"' "$MAIN" || fail "el módulo SSH no genera su sección de auditoría"
if grep -Fq 'ssh_module_can_apply || return 0' "$MAIN"; then
  fail "la auditoría compacta todavía oculta SSH si el drop-in no es aplicable"
fi
grep -Fq 'ssh_apply_pending_settings' "$MAIN" || fail "falta el flujo de aplicación segura de SSH"
grep -Fq 'SSH_MANAGED_BEGIN="# BEGIN ORANGEBOX SSH HARDENING MANAGED BLOCK"' "$MAIN" || fail "falta el bloque gestionado alternativo de sshd_config"
grep -Fq 'ssh_print_manual_remediation' "$MAIN" || fail "falta la guía de remediación manual SSH"
grep -Fq 'systemctl reload sshd' "$MAIN" || fail "falta la recarga de sshd tras validar el cambio"
grep -Fq 'firewall_report_detected' "$FIREWALL" || fail "falta inventario de firewall"
grep -Fq 'lfa_audit_listener_firewall' "$FIREWALL" || fail "falta correlación de INPUT/listeners"
# Default audit must present both success and pending counts.
grep -Fq 'OK_COUNT=0' "$MAIN" || fail "falta el contador de controles correctos"
grep -Fq 'echo "Controles correctos: $OK_COUNT"' "$MAIN" || fail "falta el resumen de controles correctos"
grep -Fq 'echo "Pendientes: $WARNINGS"' "$MAIN" || fail "falta el resumen de pendientes"
grep -Fq 'echo "Errores: $ERRORS"' "$MAIN" || fail "falta el resumen de errores"
grep -Fq 'case "$level" in INFO|CAMBIO\ PROPUESTO) return 0 ;; esac' "$ROOT_DIR/lib/sysctl-safe.sh" || fail "la biblioteca sysctl sigue ocultando los estados OK"

# Exercise the helper with the compact-audit flag exactly as the baseline does.
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
# shellcheck source=lib/sysctl-safe.sh
source "$ROOT_DIR/lib/sysctl-safe.sh"
PENDING_ONLY_AUDIT=true
OK_COUNT=0
sysctl_safe_log "OK" "control de prueba conforme" > "$OUT"
grep -Fq '[SYSCTL][OK]' "$OUT" || fail "sysctl_safe_log no muestra el estado OK"
grep -Fq 'control de prueba conforme' "$OUT" || fail "sysctl_safe_log no muestra el detalle del estado OK"
[ "$OK_COUNT" -eq 1 ] || fail "el estado OK de sysctl no incrementa el contador"
: > "$OUT"
sysctl_safe_log "INFO" "mensaje informativo oculto" > "$OUT"
[ ! -s "$OUT" ] || fail "el reporte predeterminado aún muestra mensajes informativos no accionables"
[ "$OK_COUNT" -eq 1 ] || fail "un mensaje informativo alteró el contador OK"
: > "$OUT"
NOT_APPLICABLE_COUNT=0
sysctl_safe_log "N/A" "control de kernel no aplicable" > "$OUT"
grep -Fq '[SYSCTL][N/A]' "$OUT" || fail "sysctl_safe_log no muestra estados N/A"
grep -Fq 'control de kernel no aplicable' "$OUT" || fail "sysctl_safe_log oculta el motivo N/A"
[ "$NOT_APPLICABLE_COUNT" -eq 1 ] || fail "el estado N/A no incrementa el contador"

# The default report covers every baseline family that interactive --fix can change.
grep -Fq 'NOT_APPLICABLE_COUNT=0' "$MAIN" || fail "falta contador de controles no aplicables"
grep -Fq '      --audit) AUDIT_MODE=true ;;' "$MAIN" || fail "falta el modo explícito --audit"
grep -Fq 'die "--audit y --fix son modos excluyentes."' "$MAIN" || fail "--audit debe rechazar la combinación ambigua con --fix"
grep -Fq 'echo "No aplicables: $NOT_APPLICABLE_COUNT"' "$MAIN" || fail "falta resumen de controles no aplicables"
grep -Fq 'aide_audit_module' "$MAIN" || fail "la auditoría predeterminada omite el hardening opcional AIDE"
grep -Fq 'Base de referencia AIDE inicializada' "$MAIN" || fail "AIDE no informa el estado de su base"
grep -Fq 'Verificación periódica de AIDE configurada' "$MAIN" || fail "AIDE no informa el estado del cron"
grep -Fq 'frecuencia/comando objetivo: 0 5 * * * /usr/sbin/aide --check' "$MAIN" || fail "AIDE no audita el cron contra su objetivo exacto"
if grep -Fq 'if [ "${PENDING_ONLY_AUDIT:-false}" = true ] && ! sysctl_baseline_target_writable; then return 0; fi' "$MAIN"; then
  fail "kernel/SYN flood siguen ocultando controles si el destino sysctl no es gestionable"
fi
grep -Fq 'sysctl_safe_log "N/A"' "$MAIN" || fail "los sysctl no aplicables no muestran un estado explícito"
grep -Fq 'No se puede confirmar Storage=persistent' "$MAIN" || fail "journald no informa config ausente"
grep -Fq 'carga el perfil OrangeBox para shells interactivos no-login' "$MAIN" || fail "Bash no comprueba el include de /etc/bashrc en audit"
grep -Fq 'no existe; no hay historial ilimitado configurado' "$MAIN" || fail "Bash oculta dotfiles de historial ausentes"
grep -Fq 'HISTSIZE no está fijado a -1' "$MAIN" || fail "Bash no audita HISTSIZE de dotfiles por separado"
grep -Fq 'HISTFILESIZE no está fijado a -1' "$MAIN" || fail "Bash no audita HISTFILESIZE de dotfiles por separado"
grep -Fq 'HISTCONTROL vacío (no se omiten comandos)' "$MAIN" || fail "Bash no audita HISTCONTROL en dotfiles"
grep -Fq 'HISTIGNORE eliminado' "$MAIN" || fail "Bash no audita HISTIGNORE en dotfiles"
grep -Fq 'histappend habilitado' "$MAIN" || fail "Bash no audita histappend en dotfiles"
grep -Fq 'bash_audit_external_history_overrides' "$MAIN" || fail "Bash no detecta perfiles externos que deshabiliten historial"
grep -Fq 'No se detectaron overrides conocidos que deshabiliten Bash History' "$MAIN" || fail "Bash no informa el estado conforme de perfiles externos"
grep -Fq 'IP forwarding=1: se usa rp_filter=2' "$MAIN" || fail "la política de rp_filter cuando hay forwarding no se muestra en audit"

# Every managed Bash hardening control must be surfaced separately in audit.
grep -Fq 'bash_audit_profile_controls "$target"' "$MAIN" || fail "Bash no informa cada control del perfil en audit"
for control in \
  'Bash timeout de usuario: TMOUT=120 y readonly' \
  'Bash: HISTSIZE=-1 (sin límite de líneas en memoria)' \
  'Bash: HISTFILESIZE=-1 (sin límite de líneas persistentes)' \
  'Bash: historial con fecha y hora' \
  'Bash: bloquea history -c/-d/-w desde el wrapper' \
  'Readline: Ctrl+A va al inicio de línea' \
  'Readline: Ctrl+E va al final de línea' \
  'Bash: obtiene FQDN mediante hostname -f' \
  'Bash: registra orangebox_pre_prompt en PROMPT_COMMAND'; do
  grep -Fq "$control" "$MAIN" || fail "falta estado individual de hardening Bash: $control"
done
grep -Fq 'net.ipv6.conf.default.accept_ra: este kernel no expone' "$MAIN" || fail "falta estado IPv6 N/A granular"
grep -Fq 'journald no aplica a CentOS/RHEL 6' "$MAIN" || fail "falta estado N/A de journald en EL6"

grep -Fq 'ssh_report_unverifiable_settings "$reason"' "$MAIN" || fail "SSH no muestra todos los parámetros cuando no puede verificar sshd"
grep -Fq 'bash_audit_system_bashrc_include' "$MAIN" || fail "Bash puede ocultar el include de /etc/bashrc si falla mktemp"
grep -Fq 'banners_audit_unverifiable()' "$MAIN" || fail "los controles banner/MOTD pueden desaparecer si falla la generación temporal"
grep -Fq 'SSH $directive: no se pudo verificar' "$MAIN" || fail "falta el estado no verificable por directiva SSH"

pass "auditoría presenta estados OK y pendientes, con resumen y firewall independiente"
