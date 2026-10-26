#!/bin/bash

# ==============================================
# Script: grub-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de GRUB según CIS Benchmark
#              Configura contraseña de bootloader
#              Agrega parámetros de seguridad al kernel
#              Compatible con RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false
GRUB_PARAMS_CHANGED=false

GRUB_CONFIG="/etc/default/grub"
GRUB_CFG="/boot/grub2/grub.cfg"
GRUB_USER_CFG="/boot/grub2/user.cfg"
GRUB_SCRIPT="/etc/grub.d/01_users"
BACKUP_DIR="/root/grub-backup-$(date +%Y%m%d-%H%M%S)-${BASHPID}"

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
confirm_grub_change() {
  local control="$1" effect="$2" answer=""
  echo -e "\n$YELLOW[CONFIRMACIÓN REQUERIDA]$NC $control"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then return 1; fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "$YELLOW[WARN] No hay terminal interactiva; no se modifica GRUB.$NC"
    return 1
  fi
  printf '¿Confirmas este cambio? [s/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) echo -e "$BLUE[INFO] Cambio rechazado; se conserva la configuración actual.$NC"; return 1 ;;
  esac
}

grub_config_has_param() {
  local file="$1" param="$2"
  [ -r "$file" ] || return 1
  awk -v param="$param" '
    /^[ \t]*#/ { next }
    /^[ \t]*GRUB_CMDLINE_LINUX=/ {
      line=$0
      sub(/^[^=]*=/, "", line)
      gsub(/"/, " ", line)
      n=split(line, tokens, /[ \t]+/)
      for (i=1; i<=n; i++) if (tokens[i] == param) found=1
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 --fix      - Modo automático (aplica las correcciones)"
  echo "  $0 -f         - Modo automático (versión corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./grub-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./grub-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  [ "$AUTO_FIX" = true ] || return 0
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[ERROR] No se pudo preparar el backup $BACKUP_DIR; no se modifica GRUB.${NC}" >&2
    return 1
  fi
  local mode file backup source_hash backup_hash
  mode="$(stat -c '%a' "$BACKUP_DIR" 2>/dev/null || true)"
  [ "$mode" = 700 ] || {
    echo -e "${RED}[ERROR] No se pudo verificar el modo 0700 del backup GRUB.${NC}" >&2
    return 1
  }
  for file in "$GRUB_CONFIG" "$GRUB_CFG" "$GRUB_USER_CFG"; do
    [ -e "$file" ] || [ -L "$file" ] || continue
    if [ -L "$file" ]; then
      echo -e "${RED}[ERROR] $file es un enlace simbólico; no se modifica GRUB sin un backup seguro.${NC}" >&2
      return 1
    fi
    [ -f "$file" ] || continue
    backup="$BACKUP_DIR/$(basename "$file")"
    if ! cp -p "$file" "$backup"; then
      echo -e "${RED}[ERROR] No se pudo respaldar $file; no se modifica GRUB.${NC}" >&2
      return 1
    fi
    command -v sha256sum >/dev/null 2>&1 || { echo -e "${RED}[ERROR] sha256sum no está disponible para verificar $file; no se modifica GRUB.${NC}" >&2; return 1; }
    source_hash="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
    backup_hash="$(sha256sum "$backup" 2>/dev/null | awk '{print $1}')"
    if [ -z "$source_hash" ] || [ -z "$backup_hash" ] || [ "$source_hash" != "$backup_hash" ]; then
      echo -e "${RED}[ERROR] El backup de $file no coincide con el original; no se modifica GRUB.${NC}" >&2
      return 1
    fi
  done
  echo -e "${GREEN}[✓] Backup de GRUB verificado en: $BACKUP_DIR${NC}"
}

# ==============================================
# FUNCION PARA AGREGAR PARAMETROS AL KERNEL
# ==============================================
add_kernel_param() {
  local param="$1" description="$2" effect="" tmp="" mode=""
  if grub_config_has_param "$GRUB_CONFIG" "$param"; then
    echo -e "$GREEN[✓] $description - ya configurado$NC"
    return 0
  fi

  echo -e "$RED[!] $description - NO CONFIGURADO$NC"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 0; fi

  effect="Añade el parámetro $param a GRUB_CMDLINE_LINUX y requiere regenerar la configuración de GRUB. Puede cambiar el comportamiento del kernel tras reiniciar; un valor no compatible o un error de configuración puede impedir el arranque. Verifica consola/recuperación y mantén una sesión administrativa disponible."
  if ! confirm_grub_change "$description ($param)" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if ! grep -Eq '^[[:space:]]*GRUB_CMDLINE_LINUX="[^\"]*"$' "$GRUB_CONFIG"; then
    echo -e "$RED[!] No hay una asignación GRUB_CMDLINE_LINUX con comillas dobles que pueda actualizarse de forma segura; no se modifica.$NC"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  tmp="$(mktemp "$GRUB_CONFIG.orangebox.XXXXXX")" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  awk -v param="$param" '
    /^[ \t]*GRUB_CMDLINE_LINUX="/ && /"$/ {
      line=$0
      sub(/"$/, " " param "\"", line)
      print line
      changed=1
      next
    }
    { print }
    END { if (!changed) exit 1 }
  ' "$GRUB_CONFIG" > "$tmp" || { rm -f "$tmp"; echo -e "$RED[!] No se pudo preparar GRUB_CMDLINE_LINUX.$NC"; WARNINGS=$((WARNINGS + 1)); return 1; }
  mode="$(stat -c "%a" "$GRUB_CONFIG" 2>/dev/null || echo 600)"
  chmod "$mode" "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  chown --reference="$GRUB_CONFIG" "$tmp" 2>/dev/null || chown root:root "$tmp" 2>/dev/null || true
  if ! grub_config_has_param "$tmp" "$param"; then
    rm -f "$tmp"
    echo -e "$RED[!] El cambio temporal no contiene el parámetro esperado; no se instala.$NC"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if mv "$tmp" "$GRUB_CONFIG" && grub_config_has_param "$GRUB_CONFIG" "$param"; then
    echo -e "$GREEN[✓] $description agregado y verificado: $param$NC"
    FIXED=$((FIXED + 1))
    GRUB_PARAMS_CHANGED=true
  else
    rm -f "$tmp"
    echo -e "$RED[!] No se pudo instalar/verificar $param en $GRUB_CONFIG$NC"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_permissions() {
  local file="$1" expected_perms="$2" description="$3"
  local current_perms="" current_owner="" current_group="" effect=""
  if [ ! -f "$file" ]; then
    echo -e "$YELLOW[!] $file no existe$NC"
    return 1
  fi

  current_perms="$(stat -c "%a" "$file" 2>/dev/null || true)"
  current_owner="$(stat -c "%U" "$file" 2>/dev/null || true)"
  current_group="$(stat -c "%G" "$file" 2>/dev/null || true)"
  if [ "$current_perms" = "$expected_perms" ] && [ "$current_owner" = "root" ] && [ "$current_group" = "root" ]; then
    echo -e "$GREEN[✓] $description permisos correctos: $expected_perms root:root$NC"
    return 0
  fi

  echo -e "$RED[!] $description permisos incorrectos: $current_perms $current_owner:$current_group (debe ser $expected_perms root:root)$NC"
  if [ "$AUTO_FIX" != true ]; then WARNINGS=$((WARNINGS + 1)); return 0; fi

  effect="Restringe la modificación/lectura del archivo de arranque $file a root. Puede afectar herramientas administrativas o automatizaciones que lean GRUB; evita que usuarios no privilegiados alteren parámetros de arranque."
  if ! confirm_grub_change "permisos de $file -> $expected_perms root:root" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if chmod "$expected_perms" "$file" && chown root:root "$file" &&
     [ "$(stat -c "%a" "$file" 2>/dev/null)" = "$expected_perms" ] &&
     [ "$(stat -c "%U:%G" "$file" 2>/dev/null)" = "root:root" ]; then
    echo -e "$GREEN[✓] $description permisos corregidos y verificados$NC"
    FIXED=$((FIXED + 1))
  else
    echo -e "$RED[!] No se pudo verificar el cambio de permisos de $file$NC"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_grub_password() {
  echo -e "\n${BLUE}[*] 1.4.1 - Verificando contraseña de bootloader...${NC}"

  # Verificar si existe user.cfg con contraseña
  if [ -f "$GRUB_USER_CFG" ] && [ -s "$GRUB_USER_CFG" ]; then
    echo -e "${GREEN}[✓] Contraseña de bootloader configurada${NC}"
    return 0
  fi

  # Verificar si la contraseña está en grub.cfg
  if grep -q "^password\|^set superusers" "$GRUB_CFG" 2>/dev/null; then
    echo -e "${GREEN}[✓] Contraseña de bootloader configurada${NC}"
    return 0
  fi

  echo -e "${RED}[!] Contraseña de bootloader - NO CONFIGURADA${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${YELLOW}[!] Para establecer contraseña de GRUB, ejecute manualmente:${NC}"
    echo -e "  ${BLUE}grub2-setpassword${NC}"
    echo -e "${YELLOW}  Luego reinicie el sistema para que los cambios tomen efecto${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${YELLOW}  Recomendacion: Ejecutar 'grub2-setpassword' como root${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 1.4.2 - VERIFICAR PERMISOS DE ARCHIVOS GRUB
# ==============================================
check_grub_permissions() {
  echo -e "\n${BLUE}[*] 1.4.2 - Verificando permisos de archivos GRUB...${NC}"
  check_permissions "$GRUB_CFG" "600" "grub.cfg"
  check_permissions "$GRUB_USER_CFG" "600" "user.cfg" 2>/dev/null
}

# ==============================================
# 4.1.1.2 - AUDIT=1 EN BOOT (CORREGIDO)
# ==============================================
check_audit_boot() {
  echo -e "\n${BLUE}[*] 4.1.1.2 - Verificando auditoria de procesos previos a auditd...${NC}"

  if grep -q "audit=1" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] audit=1 configurado en GRUB_CMDLINE_LINUX${NC}"
    return 0
  fi

  echo -e "${RED}[!] audit=1 no configurado en GRUB_CMDLINE_LINUX${NC}"

  if [ "$AUTO_FIX" = true ]; then
    add_kernel_param "audit=1" "audit=1 (auditoria de procesos previos a auditd)"
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 4.1.1.3 - AUDIT_BACKLOG_LIMIT
# ==============================================
check_audit_backlog() {
  echo -e "\n${BLUE}[*] 4.1.1.3 - Verificando audit_backlog_limit...${NC}"

  if grep -q "audit_backlog_limit=8192" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] audit_backlog_limit=8192 configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] audit_backlog_limit=8192 no configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    add_kernel_param "audit_backlog_limit=8192" "audit_backlog_limit=8192 (tamaño de cola de auditoria)"
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 1.6.1.2 - ASEGURAR SELINUX NO DESHABILITADO EN BOOT
# ==============================================
remove_kernel_param() {
  local param="$1" description="$2" effect="$3" tmp="" mode=""
  if ! grub_config_has_param "$GRUB_CONFIG" "$param"; then return 0; fi
  if ! confirm_grub_change "$description ($param)" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  tmp="$(mktemp "$GRUB_CONFIG.orangebox.XXXXXX")" || { WARNINGS=$((WARNINGS + 1)); return 1; }
  awk -v param="$param" '
    /^[ \t]*GRUB_CMDLINE_LINUX="/ && /"$/ {
      line=$0
      eq=index(line, "=")
      prefix=substr(line, 1, eq)
      value=substr(line, eq+1)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      n=split(value, fields, /[ \t]+/)
      rebuilt=""
      removed=0
      for (i=1; i<=n; i++) {
        if (fields[i] == param) { removed=1; continue }
        if (fields[i] == "") continue
        if (rebuilt != "") rebuilt=rebuilt " "
        rebuilt=rebuilt fields[i]
      }
      if (removed) {
        print prefix "\"" rebuilt "\""
        changed=1
        next
      }
    }
    { print }
    END { if (!changed) exit 1 }
  ' "$GRUB_CONFIG" > "$tmp" || { rm -f "$tmp"; echo -e "$RED[!] No se pudo preparar la eliminación de $param.$NC"; WARNINGS=$((WARNINGS + 1)); return 1; }
  mode="$(stat -c "%a" "$GRUB_CONFIG" 2>/dev/null || echo 600)"
  chmod "$mode" "$tmp" || { rm -f "$tmp"; WARNINGS=$((WARNINGS + 1)); return 1; }
  chown --reference="$GRUB_CONFIG" "$tmp" 2>/dev/null || chown root:root "$tmp" 2>/dev/null || true
  if grep -qF "$param" "$tmp"; then
    rm -f "$tmp"
    echo -e "$RED[!] El parámetro $param sigue presente; no se instala el cambio.$NC"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
  if mv "$tmp" "$GRUB_CONFIG"; then
    echo -e "$GREEN[✓] $description eliminado y verificado$NC"
    FIXED=$((FIXED + 1))
    GRUB_PARAMS_CHANGED=true
  else
    rm -f "$tmp"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
}

check_selinux_boot() {
  echo -e "\n$BLUE[*] 1.6.1.2 - Verificando SELinux no deshabilitado en boot...$NC"

  if grub_config_has_param "$GRUB_CONFIG" "selinux=0"; then
    echo -e "$RED[!] selinux=0 encontrado en GRUB_CMDLINE_LINUX$NC"
    if [ "$AUTO_FIX" = true ]; then
      effect="Quitar selinux=0 permite que SELinux pueda inicializarse tras el próximo arranque, según /etc/selinux/config. Si la política/contextos están mal preparados, servicios pueden quedar bloqueados; puede requerirse relabel y consola de recuperación."
      remove_kernel_param "selinux=0" "evitar SELinux deshabilitado al arrancar" "$effect"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 1
  fi

  if grub_config_has_param "$GRUB_CONFIG" "enforcing=0"; then
    echo -e "$RED[!] enforcing=0 encontrado en GRUB_CMDLINE_LINUX$NC"
    if [ "$AUTO_FIX" = true ]; then
      effect="Quitar enforcing=0 puede pasar SELinux a enforcing en el próximo arranque cuando SELinux esté configurado como enabled. Aplicaciones con políticas o contextos incompletos pueden fallar; verifica AVCs y conserva consola de recuperación."
      remove_kernel_param "enforcing=0" "evitar desactivar SELinux enforcing al arrancar" "$effect"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
    return 1
  fi

  echo -e "$GREEN[✓] SELinux no está deshabilitado en boot$NC"
  return 0
}

# ==============================================
# PARAMETROS ADICIONALES DE SEGURIDAD DEL KERNEL
# ==============================================
check_additional_params() {
  echo -e "\n${BLUE}[*] Verificando parametros adicionales de seguridad del kernel...${NC}"

  # Slab/SANITIZE (proteccion contra desbordamiento de memoria)
  if grep -q "slab_nomerge" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] slab_nomerge - proteccion contra merging de slabs${NC}"
  else
    echo -e "${RED}[!] slab_nomerge - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      add_kernel_param "slab_nomerge" "slab_nomerge (proteccion contra ataques de heap)"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Page allocator randomization
  if grep -q "page_alloc.shuffle=1" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] page_alloc.shuffle=1 - randomizacion de paginas de memoria${NC}"
  else
    echo -e "${RED}[!] page_alloc.shuffle=1 - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      add_kernel_param "page_alloc.shuffle=1" "page_alloc.shuffle=1 (randomizacion de paginas de memoria)"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi

  # Randomize kernel stack offset
  if grep -q "randomize_kstack_offset=on" "$GRUB_CONFIG" 2>/dev/null; then
    echo -e "${GREEN}[✓] randomize_kstack_offset=on - randomizacion de pila del kernel${NC}"
  else
    echo -e "${RED}[!] randomize_kstack_offset=on - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ]; then
      add_kernel_param "randomize_kstack_offset=on" "randomize_kstack_offset=on (randomizacion de pila del kernel)"
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# REGENERAR CONFIGURACION DE GRUB
# ==============================================
regenerate_grub() {
  local output="/boot/grub2/grub.cfg" os_major="" efi_cfgs="" count=0 effect=""
  [ "$AUTO_FIX" = true ] || return 0
  [ "$GRUB_PARAMS_CHANGED" = true ] || {
    echo -e "$BLUE[INFO] No se regenera GRUB porque no cambió GRUB_CMDLINE_LINUX.$NC"
    return 0
  }

  if [ -d /sys/firmware/efi ]; then
    os_major="$(get_el_major)"
    if [ "$os_major" = "7" ]; then
      efi_cfgs="$(find /boot/efi/EFI -maxdepth 2 -type f -name grub.cfg -print 2>/dev/null)"
      count="$(printf '%s\n' "$efi_cfgs" | grep -c . || true)"
      if [ "$count" -eq 1 ]; then
        output="$efi_cfgs"
      elif [ "$count" -gt 1 ]; then
        echo -e "$RED[!] Hay múltiples grub.cfg en particiones EFI; no se elige un destino automáticamente. Revise manualmente.$NC"
        WARNINGS=$((WARNINGS + 1))
        return 1
      fi
    fi
  fi

  if ! command -v grub2-mkconfig >/dev/null 2>&1; then
    echo -e "$RED[!] grub2-mkconfig no está disponible; los cambios en GRUB_CMDLINE_LINUX aún no están aplicados al archivo generado.$NC"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  effect="Regenera $output a partir de la configuración GRUB. Un destino incorrecto o error de generación puede impedir el arranque; verifica el backup y la consola de recuperación, y no reinicies hasta comprobar la salida."
  if ! confirm_grub_change "regenerar la configuración de GRUB en $output" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi

  if grub2-mkconfig -o "$output" && [ -s "$output" ]; then
    echo -e "$GREEN[✓] Configuración GRUB regenerada y archivo de salida no vacío: $output$NC"
    FIXED=$((FIXED + 1))
  else
    echo -e "$RED[!] Error al regenerar GRUB; no reinicie. Revise backup y salida del comando.$NC"
    WARNINGS=$((WARNINGS + 1))
    return 1
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  GRUB HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACIONES:${NC}"
  echo -e "  cat /etc/default/grub | grep GRUB_CMDLINE_LINUX"
  echo -e "  grub2-mkconfig -o /boot/grub2/grub.cfg"

  echo -e "\n${YELLOW}PARA ESTABLECER CONTRASEÑA DE GRUB:${NC}"
  echo -e "  grub2-setpassword"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
  echo -e "${GREEN}============================================${NC}"
}


get_el_major() {
  local major=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    major="${VERSION_ID%%.*}"
  elif [ -r /etc/redhat-release ]; then
    major="$(sed -nE 's/.*release[[:space:]]+([0-9]+).*/\1/p' /etc/redhat-release | head -1)"
  fi
  printf '%s\n' "$major"
}

audit_legacy_grub_readonly() {
  local cfg="/boot/grub/grub.conf" perms owner group
  echo -e "\n${BLUE}[*] GRUB legacy: comprobaciones de solo lectura para EL6...${NC}"

  if [ ! -f "$cfg" ]; then
    echo -e "${RED}[!] No se encontró $cfg; no se puede verificar la configuración del bootloader${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  perms="$(stat -c '%a' "$cfg" 2>/dev/null)"
  owner="$(stat -c '%U' "$cfg" 2>/dev/null)"
  group="$(stat -c '%G' "$cfg" 2>/dev/null)"
  if [ "$perms" = "600" ] && [ "$owner" = "root" ] && [ "$group" = "root" ]; then
    echo -e "${GREEN}[✓] $cfg tiene permisos 600 root:root${NC}"
  else
    echo -e "${RED}[!] $cfg tiene permisos/propietario $perms $owner:$group; se recomienda 600 root:root${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  if grep -Eq '^[[:space:]]*password[[:space:]]+--(md5|encrypted)[[:space:]]+' "$cfg"; then
    echo -e "${GREEN}[✓] GRUB legacy tiene una directiva password --md5/--encrypted${NC}"
  else
    echo -e "${RED}[!] GRUB legacy no tiene una directiva de contraseña detectada${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  if grep -Eq '^[[:space:]]*kernel[[:space:]].*[[:space:]]audit=1([[:space:]]|$)' "$cfg"; then
    echo -e "${GREEN}[✓] audit=1 está persistido en una entrada de kernel de GRUB legacy${NC}"
  else
    echo -e "${YELLOW}[!] audit=1 no aparece en las entradas de kernel de $cfg${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  if grep -Eq '^[[:space:]]*kernel[[:space:]].*[[:space:]](selinux=0|enforcing=0)([[:space:]]|$)' "$cfg"; then
    echo -e "${RED}[!] Se encontró selinux=0 o enforcing=0 en una entrada de kernel${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] No se detectó SELinux deshabilitado en las entradas de kernel${NC}"
  fi

  if [ -r /proc/cmdline ] && grep -qw 'audit=1' /proc/cmdline; then
    echo -e "${GREEN}[✓] El kernel actualmente iniciado contiene audit=1${NC}"
  else
    echo -e "${YELLOW}[!] El kernel actualmente iniciado no muestra audit=1 en /proc/cmdline${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi

  echo -e "${YELLOW}[N/A] No se auditan parámetros exclusivos de kernels modernos (slab_nomerge, page_alloc.shuffle, randomize_kstack_offset) en esta generación legacy.${NC}"
}

show_legacy_grub_summary() {
  echo
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  GRUB LEGACY - RESUMEN DE AUDITORÍA${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo "Correcciones aplicadas: 0 (modo solo lectura)"
  echo "Advertencias pendientes: $WARNINGS"
  echo "Archivo revisado: /boot/grub/grub.conf"
  echo "Verificación manual: grep -E '^[[:space:]]*(password|kernel)' /boot/grub/grub.conf"
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  GRUB Hardening - Seguridad del Bootloader${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Modo ayuda
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  local os_major
  os_major="$(get_el_major)"
  if [[ "$os_major" =~ ^[0-9]+$ ]] && [ "$os_major" -lt 7 ]; then
    if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
      echo -e "${RED}[ERROR] --fix no está soportado para GRUB legacy; no se aplicaron cambios. Revise manualmente la salida de auditoría.${NC}" >&2
      exit 2
    fi
    echo -e "${YELLOW}MODO AUDITORÍA LEGACY: no se aplicarán cambios${NC}"
    audit_legacy_grub_readonly
    show_legacy_grub_summary
    return 0
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
    if ! make_backup; then
      echo -e "${RED}[ERROR] Backup de GRUB falló; se aborta antes de ejecutar controles con cambios.${NC}" >&2
      exit 1
    fi
  fi

  # Ejecutar verificaciones/correcciones
  check_grub_password
  check_grub_permissions
  check_audit_boot
  check_audit_backlog
  check_selinux_boot
  check_additional_params

  # Regenerar configuracion de GRUB si se hicieron cambios
  if [ "$AUTO_FIX" = true ] && [ "$GRUB_PARAMS_CHANGED" = true ]; then
    regenerate_grub
    echo -e "\n${YELLOW}[!] Se recomienda reiniciar el sistema para aplicar los cambios${NC}"
  fi

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
