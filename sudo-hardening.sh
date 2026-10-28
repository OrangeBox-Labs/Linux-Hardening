#!/bin/bash

# ==============================================
# Script: sudo-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de sudo segun CIS Benchmark
#              CIS 5.2.1 - 5.2.4
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

SUDOERS_FILE="/etc/sudoers"
SUDOERS_D_DIR="/etc/sudoers.d"
BACKUP_DIR="/root/sudo-backup-$(date +%Y%m%d-%H%M%S)"

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
  echo "  ./sudo-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./sudo-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  [ "$AUTO_FIX" = true ] || return 0
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[!] No se pudo preparar el directorio de backup; se cancela el hardening.${NC}"
    return 1
  fi
  if [ -f "$SUDOERS_FILE" ] && ! cp -p "$SUDOERS_FILE" "$BACKUP_DIR/sudoers"; then
    echo -e "${RED}[!] No se pudo respaldar $SUDOERS_FILE; se cancela el hardening.${NC}"
    return 1
  fi
  if [ -d "$SUDOERS_D_DIR" ] && ! cp -a "$SUDOERS_D_DIR" "$BACKUP_DIR/"; then
    echo -e "${RED}[!] No se pudo respaldar $SUDOERS_D_DIR; se cancela el hardening.${NC}"
    return 1
  fi
  echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
}

confirm_sudo_change() {
  if [ "${ORANGEBOX_ASSUME_YES:-0}" = "1" ]; then printf "[AUTO-YES] sudo %s\n" "${1:-cambio}"; return 0; fi
  local title="$1" current="$2" proposed="$3" effect="$4" answer=""
  echo -e "${YELLOW}[WARN] Cambio sudo pendiente: $title${NC}"
  echo "Estado actual: ${current:-no definido}"
  echo "Propuesta: $proposed"
  echo "Qué hace/riesgo: $effect"
  [ "$AUTO_FIX" = true ] || { WARNINGS=$((WARNINGS + 1)); return 1; }
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "${YELLOW}[WARN] No hay terminal interactiva; se omite el cambio sensible.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  printf '¿Aplicar este cambio de sudo? [s/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) echo -e "${YELLOW}[INFO] Cambio rechazado; sudo conserva su configuración actual.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1 ;;
  esac
}

sudoers_sources() {
  local f base
  printf '%s\n' "$SUDOERS_FILE"
  if grep -Eq '^[[:space:]]*(#includedir|@includedir)[[:space:]]+/etc/sudoers.d([[:space:]]|$)' "$SUDOERS_FILE" 2>/dev/null; then
    for f in "$SUDOERS_D_DIR"/*; do
      [ -f "$f" ] || continue
      base="${f##*/}"
      case "$base" in *.*|*~) continue ;; esac
      printf '%s\n' "$f"
    done
  fi
}

sudoers_config_contains() {
  local pattern="$1" f
  while IFS= read -r f; do
    [ -r "$f" ] || continue
    grep -Eq "^[[:space:]]*${pattern}" "$f" 2>/dev/null && return 0
  done < <(sudoers_sources)
  return 1
}

sudoers_option_value() {
  local key="$1" f
  local -a sources=()
  while IFS= read -r f; do
    [ -r "$f" ] && sources+=("$f")
  done < <(sudoers_sources)
  [ "${#sources[@]}" -gt 0 ] || return 0
  awk -v wanted="$key" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == "Defaults" {
      for (i=2; i<=NF; i++) {
        count=split($i, part, ",")
        for (j=1; j<=count; j++) {
          token=part[j]
          gsub(/^[ \t]+|[ \t]+$/, "", token)
          if (token == "!" wanted) value="disabled"
          else if (index(token, "=")) {
            eq=index(token, "=")
            name=substr(token, 1, eq-1)
            val=substr(token, eq+1)
            if (name == wanted) { gsub(/"/, "", val); value=val }
          } else if (token == wanted) value="enabled"
        }
      }
    }
    END { if (value != "") print value }
  ' "${sources[@]}" 2>/dev/null
}

sudo_backup_once() {
  [ -f "$BACKUP_DIR/sudoers" ] && return 0
  mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR" &&
    cp -p "$SUDOERS_FILE" "$BACKUP_DIR/sudoers"
}

append_sudoers_line_safely() {
  local pattern="$1" line="$2" tmp="" previous="" mode=""
  [ -L "$SUDOERS_FILE" ] && { echo -e "${RED}[!] $SUDOERS_FILE es un enlace simbólico; no se modifica.${NC}"; return 1; }
  [ -f "$SUDOERS_FILE" ] || { echo -e "${RED}[!] $SUDOERS_FILE no es un archivo regular; no se modifica.${NC}"; return 1; }
  sudoers_config_contains "$pattern" && return 0
  sudo_backup_once || { echo -e "${RED}[!] No se pudo respaldar sudoers; no se modifica.${NC}"; return 1; }
  previous="$(mktemp "$(dirname "$SUDOERS_FILE")/.sudoers.orangebox.prev.XXXXXX")" || return 1
  tmp="$(mktemp "$(dirname "$SUDOERS_FILE")/.sudoers.orangebox.new.XXXXXX")" || { rm -f "$previous"; return 1; }
  cp -p "$SUDOERS_FILE" "$previous" || { rm -f "$previous" "$tmp"; return 1; }
  cat "$SUDOERS_FILE" > "$tmp" && printf '\n%s\n' "$line" >> "$tmp" || { rm -f "$previous" "$tmp"; return 1; }
  mode="$(stat -c '%a' "$SUDOERS_FILE" 2>/dev/null || echo 440)"
  chmod "$mode" "$tmp" && chown root:root "$tmp" || { rm -f "$previous" "$tmp"; return 1; }
  if ! visudo -c -f "$tmp" >/dev/null 2>&1; then
    rm -f "$previous" "$tmp"
    echo -e "${RED}[!] La propuesta no valida con visudo; sudoers no fue modificado.${NC}"
    return 1
  fi
  if ! mv "$tmp" "$SUDOERS_FILE"; then rm -f "$previous" "$tmp"; return 1; fi
  if visudo -c >/dev/null 2>&1; then
    rm -f "$previous"
    return 0
  fi
  cp -p "$previous" "$SUDOERS_FILE"
  rm -f "$previous"
  echo -e "${RED}[!] La configuración instalada no pasó visudo -c; se restauró el estado anterior.${NC}"
  return 1
}

sudoers_logfile_path() {
  sudoers_option_value logfile
}

# ==============================================
# FUNCION PARA VERIFICAR CONFIGURACION EN SUDOERS
# ==============================================
check_sudoers_config() {
  local pattern="$1" description="$2" fix_line="$3"
  local actual="" expected="" effect="" proposed="$fix_line"
  case "$fix_line" in
    *logfile=*)
      actual="$(sudoers_option_value logfile)"
      if [ -n "$actual" ]; then
        echo -e "${GREEN}[✓] $description (ruta configurada: $actual)${NC}"
        return 0
      fi
      expected='/var/log/sudo.log'
      effect="Configura registro local de comandos privilegiados. El fichero puede crecer y contener metadatos sensibles; valida espacio y si algún colector necesita leerlo."
      ;;
    *timestamp_timeout=*)
      actual="$(sudoers_option_value timestamp_timeout)"
      expected=5
      effect="Reduce la duración de credenciales sudo en caché a cinco minutos. Aumenta solicitudes de autenticación y puede interrumpir automatizaciones largas."
      [ "$actual" = "$expected" ] && { echo -e "${GREEN}[✓] $description (valor=$actual)${NC}"; return 0; }
      ;;
    *env_reset*)
      actual="$(sudoers_option_value env_reset)"
      expected=enabled
      effect="Limpia el entorno heredado al ejecutar sudo y reduce el riesgo por variables manipulables. Puede cambiar automatizaciones que dependan de variables heredadas."
      [ "$actual" = "$expected" ] && { echo -e "${GREEN}[✓] $description (activo)${NC}"; return 0; }
      ;;
    *)
      if sudoers_config_contains "$pattern"; then echo -e "${GREEN}[✓] $description${NC}"; return 0; fi
      effect="Cambia la política de sudo; puede afectar privilegios administrativos o automatizaciones."
      ;;
  esac
  echo -e "${YELLOW}[WARN] $description: actual=${actual:-no definido}; objetivo=$expected ($proposed)${NC}"
  echo "Qué hace/riesgo: $effect"
  [ "$AUTO_FIX" = true ] || { WARNINGS=$((WARNINGS + 1)); return 1; }
  if ! confirm_sudo_change "$description" "${actual:-no definido}" "$proposed" "$effect"; then return 1; fi
  if append_sudoers_line_safely "$pattern" "$fix_line"; then
    echo -e "${GREEN}[✓] Configuración añadida y validada: $fix_line${NC}"
    FIXED=$((FIXED + 1))
    return 0
  fi
  echo -e "${RED}[!] No se aplicó $fix_line; revisar backup y visudo.${NC}"
  WARNINGS=$((WARNINGS + 1))
  return 1
}

# ==============================================
# FUNCION PARA VALIDAR SINTAXIS DE SUDOERS
# ==============================================
validate_sudoers() {
  if visudo -c &>/dev/null; then
    echo -e "${GREEN}[✓] Sintaxis de sudoers correcta${NC}"
    return 0
  else
    echo -e "${RED}[!] Error en sintaxis de sudoers${NC}"
    if [ "$AUTO_FIX" = true ] && [ -f "$BACKUP_DIR/sudoers" ]; then
      cp "$BACKUP_DIR/sudoers" "$SUDOERS_FILE"
      echo -e "${YELLOW}[!] Restaurado backup por error de sintaxis${NC}"
    fi
    return 1
  fi
}

# ==============================================
# 5.2.1 - ENSURE SUDO IS INSTALLED
# ==============================================
check_sudo_installed() {
  echo -e "\n${BLUE}[*] CIS 5.2.1 - Verificando sudo instalado...${NC}"
  if rpm -q sudo >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] sudo instalado ($(rpm -q sudo))${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] sudo no instalado.${NC}"
  local effect="Instala la herramienta de escalamiento administrativo sudo y puede añadir dependencias. Si el gestor falla, la ausencia no se considera corregida; asegure una vía administrativa funcional."
  if [ "$AUTO_FIX" != true ]; then
    echo "Qué hace/riesgo: $effect"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if ! confirm_sudo_change "instalar sudo" "paquete ausente" "dnf/yum install sudo" "$effect"; then return 1; fi
  if command -v dnf >/dev/null 2>&1; then dnf install sudo -y
  elif command -v yum >/dev/null 2>&1; then yum install sudo -y
  else echo -e "${RED}[!] No hay dnf ni yum; no se instala sudo.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1
  fi
  if rpm -q sudo >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] sudo instalado y verificado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] No se confirmó la instalación de sudo${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 5.2.2 - ENSURE SUDO COMMANDS USE PTY
# ==============================================
cpanel_host_detected() {
  [ -d /usr/local/cpanel ] || [ -f /etc/cpanel/cpanel.config ] || command -v whmapi1 >/dev/null 2>&1
}

check_sudo_pty() {
  echo -e "\n${BLUE}[*] CIS 5.2.2 - Verificando uso de pseudo-terminal (pty) en sudo...${NC}"
  local effect="Fuerza a sudo a ejecutar comandos en un pseudo-terminal. Mejora la auditoría de terminal, pero puede romper scripts o automatizaciones sin TTY; en cPanel se omite."
  if cpanel_host_detected; then
    if sudoers_config_contains 'Defaults[[:space:]]+use_pty([,[:space:]]|$)'; then
      echo -e "${YELLOW}[WARN] cPanel detectado y use_pty está configurado; puede afectar automatizaciones del hosting. No se modifica.${NC}"
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "${BLUE}[INFO] cPanel detectado: se omite use_pty porque puede romper funcionalidades/automatizaciones del hosting.${NC}"
    fi
    return 0
  fi
  if sudoers_config_contains 'Defaults[[:space:]]+use_pty([,[:space:]]|$)'; then
    echo -e "${GREEN}[✓] sudo usa pseudo-terminal (pty)${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] sudo no tiene Defaults use_pty configurado.${NC}"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 1; fi
  if [ "${ORANGEBOX_ASSUME_YES:-0}" != "1" ]; then
    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
      echo -e "${YELLOW}[WARN] No hay terminal para confirmar; use_pty no se modificará.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
    local answer
    read -r -p "¿Habilitar Defaults use_pty? Puede afectar automatizaciones sin TTY. [s/N]: " answer </dev/tty
    case "$answer" in
      s|S|si|SI|Si|sí|Sí|SÍ) ;;
      *) echo -e "${YELLOW}[INFO] use_pty rechazado; se conserva la configuración actual.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1 ;;
    esac
  else
    echo "[AUTO-YES] sudo Defaults use_pty"
  fi
  if append_sudoers_line_safely 'Defaults[[:space:]]+use_pty([,[:space:]]|$)' 'Defaults use_pty'; then
    echo -e "${GREEN}[✓] Configuración agregada y validada: Defaults use_pty${NC}"
    FIXED=$((FIXED + 1))
    return 0
  fi
  echo -e "${RED}[!] No se aplicó Defaults use_pty; revisar backup y visudo.${NC}"
  WARNINGS=$((WARNINGS + 1))
  return 1
}

# ==============================================
# 5.2.3 - ENSURE SUDO LOG FILE EXISTS
# ==============================================
check_sudo_logfile() {
  echo -e "\n${BLUE}[*] CIS 5.2.3 - Verificando archivo de log de sudo...${NC}"
  check_sudoers_config "Defaults.*logfile=" "sudo tiene archivo de log configurado" 'Defaults logfile="/var/log/sudo.log"'
  local LOGFILE="" parent="" current_perms="" current_owner="" current_group="" effect=""
  LOGFILE="$(sudoers_logfile_path)"
  if [ -z "$LOGFILE" ]; then
    echo -e "${YELLOW}[WARN] No se pudo determinar una ruta de logfile; no se crea ningún archivo.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ -L "$LOGFILE" ]; then
    echo -e "${RED}[WARN] $LOGFILE es enlace simbólico; no se modifica.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  parent="$(dirname "$LOGFILE")"
  if [ ! -d "$parent" ]; then
    echo -e "${YELLOW}[WARN] No existe $parent; no se crea un árbol de logs desconocido automáticamente.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if [ ! -e "$LOGFILE" ]; then
    effect="Crea el fichero de auditoría local de sudo con propietario root:root y modo 0600. Puede contener metadatos privilegiados y los permisos pueden afectar a colectores que lean el fichero directamente."
    echo -e "${YELLOW}[WARN] Archivo de log $LOGFILE no existe.${NC}"
    if ! confirm_sudo_change "crear $LOGFILE" "ausente" "archivo regular root:root 0600" "$effect"; then return 1; fi
    if (umask 077; set -C; : > "$LOGFILE") 2>/dev/null && chown root:root "$LOGFILE" && chmod 600 "$LOGFILE"; then
      echo -e "${GREEN}[✓] Archivo de log creado y protegido: $LOGFILE${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] No se pudo crear/proteger $LOGFILE; no se sigue.${NC}"
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi
  fi
  [ -f "$LOGFILE" ] || { echo -e "${YELLOW}[WARN] $LOGFILE no es archivo regular; no se cambian permisos.${NC}"; WARNINGS=$((WARNINGS + 1)); return 1; }
  current_perms="$(stat -c '%a' "$LOGFILE" 2>/dev/null || true)"
  current_owner="$(stat -c '%U' "$LOGFILE" 2>/dev/null || true)"
  current_group="$(stat -c '%G' "$LOGFILE" 2>/dev/null || true)"
  if [ "$current_perms" = 600 ] && [ "$current_owner" = root ] && [ "$current_group" = root ]; then
    echo -e "${GREEN}[✓] $LOGFILE permisos/propiedad root:root 0600${NC}"
    return 0
  fi
  effect="Protege metadatos de comandos privilegiados con root:root 0600. Un agente que lea el log como usuario no privilegiado podría perder acceso; valide cómo se recolecta y reenvía antes de aceptar."
  echo -e "${YELLOW}[WARN] $LOGFILE actual=$current_perms $current_owner:$current_group; recomendado=600 root:root${NC}"
  if ! confirm_sudo_change "proteger permisos/propiedad de $LOGFILE" "$current_perms $current_owner:$current_group" "600 root:root" "$effect"; then return 1; fi
  if chown root:root "$LOGFILE" && chmod 600 "$LOGFILE" &&
     [ "$(stat -c '%a' "$LOGFILE" 2>/dev/null)" = 600 ] &&
     [ "$(stat -c '%U:%G' "$LOGFILE" 2>/dev/null)" = root:root ]; then
    echo -e "${GREEN}[✓] Permisos/propiedad de $LOGFILE ajustados y verificados${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[!] No se pudo proteger $LOGFILE; revise permisos inmediatamente.${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURACIONES ADICIONALES RECOMENDADAS
# ==============================================
check_additional_configs() {
  echo -e "\n${BLUE}[*] Verificando configuraciones adicionales de seguridad...${NC}"
  check_sudoers_config 'Defaults.*timestamp_timeout=5' "timeout de sudo (objetivo 5 minutos)" 'Defaults timestamp_timeout=5'
  check_sudoers_config 'Defaults[[:space:]]+env_reset([,[:space:]]|$)' "env_reset activo" 'Defaults env_reset'
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  SUDO HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACION:${NC}"
  echo -e "  visudo -c"
  echo -e "  sudo -l"
  echo -e "  grep -E 'use_pty|logfile|timestamp_timeout|env_reset' /etc/sudoers"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Sudo Hardening - CIS 5.2.x${NC}"
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
    if ! make_backup; then
      echo -e "${RED}[!] Backup fallido; no se aplicarán cambios de sudo.${NC}"
      exit 1
    fi
  fi

  # Ejecutar verificaciones/correcciones
  check_sudo_installed
  check_sudo_pty
  check_sudo_logfile
  check_additional_configs
  validate_sudoers

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
