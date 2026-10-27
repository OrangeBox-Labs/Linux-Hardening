#!/bin/bash

# ==============================================
# Script: kernel-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening del kernel y limites del sistema
# ==============================================

# Colores para output
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$SCRIPT_DIR/lib/sysctl-safe.sh" ]; then
  # shellcheck source=lib/sysctl-safe.sh
  source "$SCRIPT_DIR/lib/sysctl-safe.sh"
else
  echo "[ERROR] Falta lib/sysctl-safe.sh; actualice el repositorio completo." >&2
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
FIXED=0
WARNINGS=0
AUTO_FIX=false
KERNEL_BACKUP_DIR="/var/backups/orangebox-kernel-hardening/$(date +%Y%m%d-%H%M%S)-${BASHPID}"

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 --fix      - Modo automático (aplica las correcciones)"
  echo "  $0 -f         - Modo automático (versión corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./kernel-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./kernel-hardening.sh --fix"
  echo ""
}

# ==============================================
# CAMBIOS DELICADOS: CONSENTIMIENTO Y BACKUPS
# ==============================================
kernel_confirm_change() {
  local description="$1" effect="$2" answer=""
  printf '\n[WARN] Cambio de límite/kernel: %s\n' "$description"
  printf 'Qué hace/riesgo: %s\n' "$effect"
  printf '%s' "¿Aplicar este parámetro? [s/N]: "
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    printf '\n[WARN] No hay terminal interactiva; se omite el cambio por seguridad.\n'
    return 1
  fi
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in s|S|si|SI|sí|Sí|SÍ) return 0 ;; *) echo '[INFO] Se conserva el valor actual.'; return 1 ;; esac
}

kernel_backup_file() {
  local source="$1" backup_dir="$KERNEL_BACKUP_DIR" backup parent mode
  [ -e "$source" ] || [ -L "$source" ] || return 0
  [ ! -L "$source" ] || { echo "[ERROR] $source es un symlink; no se modifica." >&2; return 1; }
  backup="$backup_dir$source"
  parent="$(dirname "$backup")"
  if ! mkdir -p "$parent"; then
    echo "[ERROR] No se pudo preparar el destino del backup para $source." >&2
    return 1
  fi
  if [ -L "$backup_dir" ] || [ ! -d "$backup_dir" ] || ! chmod 700 "$backup_dir"; then
    echo "[ERROR] No se pudo asegurar el directorio del backup de kernel." >&2
    return 1
  fi
  mode="$(stat -c '%a' "$backup_dir" 2>/dev/null || true)"
  if [ "$mode" != 700 ]; then
    echo "[ERROR] No se pudo verificar el modo 0700 del backup de kernel."
    return 1
  fi
  # A repeated call for the same file must preserve the original pre-change copy.
  [ -e "$backup" ] && return 0
  if ! cp -p "$source" "$backup" || [ ! -f "$backup" ]; then
    echo "[ERROR] No se pudo crear el backup de $source." >&2
    return 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "[ERROR] sha256sum no está disponible para verificar el backup de $source." >&2
    return 1
  fi
  local source_hash backup_hash
  source_hash="$(sha256sum "$source" 2>/dev/null | awk '{print $1}')"
  backup_hash="$(sha256sum "$backup" 2>/dev/null | awk '{print $1}')"
  if [ -z "$source_hash" ] || [ -z "$backup_hash" ] || [ "$source_hash" != "$backup_hash" ]; then
    echo "[ERROR] No se pudo verificar el backup de $source." >&2
    return 1
  fi
  echo "[INFO] Backup $source: $backup"
}

kernel_write_limit() {
  local entry="$1" domain="$2" type="$3" item="$4"
  local target="/etc/security/limits.d/zzzzzzzz-orangebox-hardening.conf" tmp=""
  mkdir -p /etc/security/limits.d || return 1
  [ ! -L "$target" ] || { echo "[ERROR] $target es un symlink; no se modifica."; return 1; }
  [ ! -e "$target" ] || kernel_backup_file "$target" || return 1
  tmp="$(mktemp /etc/security/limits.d/zzzzzzzz-orangebox-hardening.conf.XXXXXX)" || return 1
  if [ -f "$target" ]; then
    awk -v d="$domain" -v t="$type" -v i="$item" '
      $1==d && $2==t && $3==i { next }
      { print }
    ' "$target" > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  printf '%s\n' "$entry" >> "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 644 "$tmp" && chown root:root "$tmp" || { rm -f "$tmp"; return 1; }
  if ! mv "$tmp" "$target"; then rm -f "$tmp"; return 1; fi
  return 0
}

# ==============================================
# FUNCION PARA VERIFICAR O AGREGAR PARAMETRO SYSCTL
# ==============================================
check_sysctl_param() {
  local param="$1" expected="$2" description="$3"
  local SYSCTL_FILE="/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf"
  if sysctl_safe_apply "$param" "$expected" "$description" "$SYSCTL_FILE" "/var/backups/orangebox-kernel-hardening" "$AUTO_FIX" "" ""; then
    [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_kptr_restrict_policy() {
  local SYSCTL_FILE="/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf"
  if sysctl_safe_apply_kptr_restrict_policy "$SYSCTL_FILE" "/var/backups/orangebox-kernel-hardening" "$AUTO_FIX"; then
    [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR O AGREGAR A LIMITS.CONF
# ==============================================
check_limits_param() {
  local entry="$1" description="$2"
  local domain type item expected current="" compliant=false effect=""
  local -a limits_files=()
  read -r domain type item expected <<< "$entry"
  limits_files=(/etc/security/limits.conf /etc/security/limits.d/*.conf)
  current="$(awk -v d="$domain" -v t="$type" -v i="$item" '
    /^[[:space:]]*#/ || NF < 4 { next }
    $1==d && $2==t && $3==i { value=$4 }
    END { if (value != "") print value }
  ' "${limits_files[@]}" 2>/dev/null)"
  case "$item" in
    core)
      effect="Qué hace: desactiva volcados de memoria. Riesgo: limita el análisis post-mortem."
      [ "$current" = "0" ] && compliant=true
      ;;
    nofile)
      effect="Qué hace: limita archivos y sockets abiertos por sesión. Riesgo: valores bajos pueden agotar conexiones o archivos."
      if [[ "$current" =~ ^[0-9]+$ ]] && [ "$current" -ge "$expected" ]; then compliant=true; fi
      ;;
    maxlogins)
      effect="Qué hace: limita sesiones simultáneas por usuario. Riesgo: puede impedir sesiones administrativas o automatizaciones."
      if [[ "$current" =~ ^[0-9]+$ ]] && [ "$current" -le "$expected" ]; then compliant=true; fi
      ;;
    nproc)
      effect="Qué hace: limita procesos por usuario. Riesgo: puede impedir iniciar servicios, workers PHP, SSH o tareas cron."
      if [[ "$current" =~ ^[0-9]+$ ]] && [ "$current" -ge 1024 ] && [ "$current" -le "$expected" ]; then compliant=true; fi
      ;;
    *) effect="ajusta un límite de recursos; un valor restrictivo puede afectar aplicaciones." ;;
  esac

  if [ "$compliant" = true ]; then
    echo -e "${GREEN}[✓] $description ya cumple (valor actual: $current)${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] $description pendiente; valor actual: ${current:-no definido}; objetivo OrangeBox: $expected.${NC}"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 0; fi
  if ! kernel_confirm_change "$description -> $expected" "$effect"; then WARNINGS=$((WARNINGS + 1)); return 0; fi
  if ! kernel_write_limit "$entry" "$domain" "$type" "$item"; then
    echo "[ERROR] No se pudo escribir el límite $entry."
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  echo -e "${GREEN}[✓] $description configurado: $entry${NC}"
  FIXED=$((FIXED + 1))
}

check_systemd_coredump() {
  local override="/etc/systemd/coredump.conf.d/zzzzzzzz-orangebox-hardening.conf"
  local effective="" target_dir="/etc/systemd/coredump.conf.d" tmp=""
  if ! command -v systemd-coredump >/dev/null 2>&1 && [ ! -f /etc/systemd/coredump.conf ] && [ ! -d /etc/systemd/coredump.conf.d ]; then
    echo "[N/A] systemd-coredump no está disponible; no aplica en este sistema."
    return 0
  fi
  echo -e "\n${YELLOW}[*] Verificando systemd-coredump Storage...${NC}"
  if command -v systemd-analyze >/dev/null 2>&1; then
    effective="$(systemd-analyze cat-config systemd/coredump.conf 2>/dev/null | awk -F= '/^[[:space:]]*Storage[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); value=$2} END{print value}')"
  fi
  if [ -z "$effective" ] && [ -r "$override" ]; then
    effective="$(awk -F= '/^[[:space:]]*Storage[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); value=$2} END{print value}' "$override")"
  fi
  if [ "$effective" = "none" ]; then
    echo "${GREEN}[✓] systemd-coredump Storage=none en la configuración efectiva${NC}"
    return 0
  fi
  echo "${YELLOW}[WARN] systemd-coredump no está limitado a Storage=none; valor efectivo: ${effective:-default/no verificable}.${NC}"
  local effect="Qué hace: evita guardar volcados que pueden contener secretos. Riesgo: dificulta el diagnóstico post-mortem."
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 0; fi
  if ! kernel_confirm_change "systemd-coredump Storage=none" "$effect"; then WARNINGS=$((WARNINGS + 1)); return 0; fi
  if [ -L "$override" ]; then echo "[ERROR] $override es un symlink; no se modifica."; WARNINGS=$((WARNINGS + 1)); return 1; fi
  if [ -f "$override" ]; then kernel_backup_file "$override" || { WARNINGS=$((WARNINGS + 1)); return 1; }; fi
  mkdir -p "$target_dir" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  tmp="$(mktemp "$override.XXXXXX")" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  if [ -f "$override" ]; then
    awk ' /^[[:space:]]*Storage[[:space:]]*=/ { next } { print } ' "$override" > "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  fi
  printf '\n[Coredump]\nStorage=none\n' >> "$tmp"
  chmod 644 "$tmp" && chown root:root "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  if ! mv "$tmp" "$override"; then rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; fi
  echo "${GREEN}[✓] Storage=none configurado en $override${NC}"
  FIXED=$((FIXED + 1))
}

restrict_core_dumps() {
  echo -e "\n${BLUE}[*] CIS 1.5.1 - Restringiendo core dumps...${NC}"
  check_sysctl_param "fs.suid_dumpable" "0" "fs.suid_dumpable"
  check_limits_param "* hard core 0" "Limite de core dump"
  check_systemd_coredump
}

# ==============================================
# 2. LIMITAR NUMERO DE PROCESOS (nproc)
# ==============================================
limit_nproc() {
  echo -e "\n${BLUE}[*] Limitando numero de procesos... ${NC}"
  # A hard nproc cap can prevent daemons/SSH/hosting workers from creating
  # child processes. The shared helper audits and asks before changing it.
  check_limits_param "* hard nproc 4096" "Límite máximo de procesos por usuario"
}

# ==============================================
# 3. LIMITAR NUMERO DE ARCHIVOS ABIERTOS (nofile)
# ==============================================
limit_nofile() {
  echo -e "\n${BLUE}[*] Limitando archivos abiertos...${NC}"
  check_limits_param "* hard nofile 65536" "Limite de archivos abiertos"
}

# ==============================================
# 4. LIMITAR SESIONES SIMULTANEAS (maxlogins)
# ==============================================
limit_maxlogins() {
  echo -e "\n${BLUE}[*] Limitando sesiones simultaneas...${NC}"
  check_limits_param "* hard maxlogins 10" "Limite de sesiones simultaneas"
}

# ==============================================
# 5. RESTRINGIR ACCESO A DMESG
# ==============================================
restrict_dmesg() {
  echo -e "\n${BLUE}[*] Restringiendo acceso a dmesg...${NC}"
  check_sysctl_param "kernel.dmesg_restrict" "1" "kernel.dmesg_restrict"
}

# ==============================================
# 6. RESTRINGIR PTRACE
# ==============================================
restrict_ptrace() {
  echo -e "\n${BLUE}[*] Restringiendo ptrace...${NC}"
  check_sysctl_param "kernel.yama.ptrace_scope" "1" "kernel.yama.ptrace_scope"
}

# ==============================================
# 7. OCULTAR DIRECCIONES DEL KERNEL
# ==============================================
hide_kernel_addresses() {
  echo -e "\n${BLUE}[*] Ocultando direcciones del kernel...${NC}"
  check_kptr_restrict_policy
}

# ==============================================
# 8. PROTECCION DE FIFOS Y HARDLINKS
# ==============================================
protect_filesystem() {
  echo -e "\n${BLUE}[*] Protegiendo filesystem...${NC}"
  check_sysctl_param "fs.protected_fifos" "2" "fs.protected_fifos"
  check_sysctl_param "fs.protected_regular" "2" "fs.protected_regular"
  check_sysctl_param "fs.protected_hardlinks" "1" "fs.protected_hardlinks"
  check_sysctl_param "fs.protected_symlinks" "1" "fs.protected_symlinks"
}

# ==============================================
# 9. HARDENING DE RED
# ==============================================
network_hardening() {
  echo -e "\n${BLUE}[*] Aplicando hardening de red...${NC}"
  # Both forwarding controls are high-impact; sysctl-safe explains their effects
  # and requires an individual interactive confirmation before changing them.
  check_sysctl_param "net.ipv4.ip_forward" "0" "net.ipv4.ip_forward"
  if [ -d /proc/sys/net/ipv6 ]; then
    check_sysctl_param "net.ipv6.conf.all.forwarding" "0" "net.ipv6.conf.all.forwarding"
  else
    echo "[N/A] IPv6 forwarding no está expuesto por este kernel; no aplica."
  fi
  check_sysctl_param "net.ipv4.conf.all.accept_redirects" "0" "net.ipv4.conf.all.accept_redirects"
  check_sysctl_param "net.ipv4.conf.default.accept_redirects" "0" "net.ipv4.conf.default.accept_redirects"
  if [ -d /proc/sys/net/ipv6 ]; then
    check_sysctl_param "net.ipv6.conf.all.accept_redirects" "0" "net.ipv6.conf.all.accept_redirects"
    check_sysctl_param "net.ipv6.conf.default.accept_redirects" "0" "net.ipv6.conf.default.accept_redirects"
  else
    echo "[N/A] IPv6 ICMP redirects no están expuestos por este kernel; no aplica."
  fi
  check_sysctl_param "net.ipv4.conf.all.send_redirects" "0" "net.ipv4.conf.all.send_redirects"
  check_sysctl_param "net.ipv4.conf.default.send_redirects" "0" "net.ipv4.conf.default.send_redirects"
  check_sysctl_param "net.ipv4.tcp_syncookies" "1" "net.ipv4.tcp_syncookies"
}

# ==============================================
# 10. SEGURIDAD DE MEMORIA
# ==============================================
memory_security() {
  echo -e "\n${BLUE}[*] Configurando seguridad de memoria y superficies locales...${NC}"
  check_sysctl_param "kernel.randomize_va_space" "2" "ASLR (kernel.randomize_va_space)"
  check_sysctl_param "vm.mmap_min_addr" "65536" "vm.mmap_min_addr"
  check_sysctl_param "kernel.unprivileged_bpf_disabled" "2" "kernel.unprivileged_bpf_disabled"
  check_sysctl_param "user.max_user_namespaces" "0" "user.max_user_namespaces"
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  KERNEL HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${YELLOW}[!] Se recomienda reiniciar el sistema para asegurar los cambios${NC}"
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Kernel Hardening y Limites del Sistema${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Modo ayuda
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  # Modo verificación (sin --fix)
  if [ "$1" != "--fix" ] && [ "$1" != "-f" ]; then
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"
    AUTO_FIX=false
  fi

  # Modo automático (--fix o -f)
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
    export ORANGEBOX_ASSUME_YES=1
  fi

  # Ejecutar todas las verificaciones/correcciones
  restrict_core_dumps
  limit_nproc
  limit_nofile
  limit_maxlogins
  restrict_dmesg
  restrict_ptrace
  hide_kernel_addresses
  protect_filesystem
  # Network sysctls are evaluated/applied by the separate network-full module.
  memory_security

  show_summary

  if [ "$AUTO_FIX" = false ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
