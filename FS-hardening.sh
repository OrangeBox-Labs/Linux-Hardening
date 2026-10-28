#!/bin/bash

# ==============================================
# Script: FS-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening operativo del sistema de archivos (perfil OrangeBox)
#              - Verifica particiones separadas criticas
#              - No calcula cumplimiento CIS; eso corresponde a cis-benchmark-check.sh
#              - Configura opciones de montaje seguras
#              - Deshabilita modulos de filesystem inseguros
#              - Aplica sticky bit
#              - Deshabilita autofs
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false
CHECK_MODE=true

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo auditoría (solo lectura; valor predeterminado)"
  echo "  $0 --check    - Modo auditoría explícito (solo lectura)"
  echo "  $0 --fix      - Aplicar propuestas con confirmación individual"
  echo "  $0 -c         - Modo auditoría (version corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Revisar el estado sin modificar el servidor"
  echo "  ./FS-hardening.sh"
  echo ""
  echo "  # Aplicar correcciones automáticamente tras el preflight"
  echo "  ./FS-hardening.sh --fix"
  echo ""
}

confirm_fs_change() {
  if [ "${ORANGEBOX_ASSUME_YES:-0}" = "1" ]; then printf "[AUTO-YES] %s\n" "${1:-cambio}"; return 0; fi
  local description="$1" effect="$2" answer=""
  printf '\n[WARN] Cambio de filesystem: %s\n' "$description"
  printf 'Qué hace/riesgo: %s\n' "$effect"
  printf '%s' "¿Aplicar este parámetro? [s/N]: "
  if [ "$AUTO_FIX" != true ] || [ "$CHECK_MODE" = true ]; then
    printf '\n[INFO] Modo auditoría; no se aplican cambios.\n'
    return 1
  fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    printf '\n[WARN] No hay terminal interactiva; se omite el cambio por seguridad.\n'
    return 1
  fi
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in s|S|si|SI|sí|Sí|SÍ) return 0 ;; *) echo '[INFO] Se conserva el estado actual.'; return 1 ;; esac
}

backup_fs_file() {
  local source="$1" backup_dir="/var/backups/orangebox-filesystem-hardening/$(date +%Y%m%d-%H%M%S)-$RANDOM"
  [ -e "$source" ] || return 0
  [ ! -L "$source" ] || { echo "[ERROR] $source es un enlace simbólico; no se modifica."; return 1; }
  mkdir -p "$backup_dir" && chmod 700 "$backup_dir" && cp -p "$source" "$backup_dir/" || {
    echo "[ERROR] No se pudo respaldar $source."
    return 1
  }
  echo "[INFO] Backup $source guardado en $backup_dir/$(basename "$source")"
}

persist_mount_options() {
  local mount_point="$1" add_if_missing="$2" spec="$3"
  shift 3
  local -a approved=("$@")
  local entry="" current="" merged="" opt="" tmp="" has_entry=false
  local -a existing=()
  [ -f /etc/fstab ] || { echo "[ERROR] /etc/fstab no existe."; return 1; }
  entry="$(awk -v mp="$mount_point" '$0 !~ /^[[:space:]]*#/ && NF>=4 && $2==mp {print; exit}' /etc/fstab)"
  if [ -n "$entry" ]; then
    has_entry=true
    current="$(printf '%s\n' "$entry" | awk '{print $4}')"
    merged="$current"
    for opt in "${approved[@]}"; do
      case ",$merged," in *",$opt,"*) ;; *) merged="$merged,$opt" ;; esac
    done
    tmp="$(mktemp /etc/.fstab.orangebox.XXXXXX)" || return 1
    awk -v mp="$mount_point" -v opts="$merged" '
      /^[[:space:]]*#/ {print; next}
      NF>=4 && $2==mp { $4=opts }
      {print}
    ' /etc/fstab > "$tmp" || { rm -f "$tmp"; return 1; }
  elif [ "$add_if_missing" = true ] && [ -n "$spec" ]; then
    tmp="$(mktemp /etc/.fstab.orangebox.XXXXXX)" || return 1
    cat /etc/fstab > "$tmp" || { rm -f "$tmp"; return 1; }
    printf '\n# OrangeBox filesystem hardening: %s\n%s\n' "$mount_point" "$spec" >> "$tmp"
  else
    echo "[WARN] No hay una entrada fstab para $mount_point; el cambio queda aplicado solo en runtime."
    return 2
  fi
  chmod --reference=/etc/fstab "$tmp" 2>/dev/null || chmod 644 "$tmp"
  chown --reference=/etc/fstab "$tmp" 2>/dev/null || chown root:root "$tmp"
  if ! mv "$tmp" /etc/fstab; then rm -f "$tmp"; echo "[ERROR] No se pudo actualizar /etc/fstab."; return 1; fi
  echo "[✓] /etc/fstab actualizado para $mount_point"
}
# ==============================================
# DEFINICION DE PUNTOS DE MONTAJE CRITICOS
# ==============================================

declare -a MUST_BE_SEPARATED=(
  "/opt"
  "/var"
  "/tmp"
  "/boot"
  "/home"
  "/var/log"
)

declare -a ADDITIONAL_MOUNTS=(
  "/var/tmp"
  "/var/log/audit"
  "/var/ossec"
)

declare -A MOUNT_REQUIREMENTS=(
  ["/var"]="noexec,nosuid,nodev"
  ["/tmp"]="noexec,nosuid,nodev"
  ["/opt"]="nosuid,nodev"
  ["/boot"]="nodev,nosuid,noexec"
  ["/home"]="noexec,nosuid,nodev"
  ["/var/log"]="noexec,nosuid,nodev"
  ["/var/tmp"]="noexec,nosuid,nodev"
  ["/var/log/audit"]="noexec,nosuid,nodev"
  ["/var/ossec"]="nosuid,nodev"
  ["/dev/shm"]="noexec,nosuid,nodev"
)

# ==============================================
# FUNCION PARA VERIFICAR SI USA LVM
# ==============================================
check_lvm() {
  echo -e "\n${BLUE}[*] Verificando si el sistema usa LVM...${NC}"

  if command -v lvm &>/dev/null && pvs &>/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Sistema usa LVM${NC}"
    return 0
  else
    echo -e "${RED}[!] El sistema NO utiliza LVM${NC}"
    return 1
  fi
}

# ==============================================
# DESHABILITAR MODULOS DE FILESYSTEM
# ==============================================
disable_modules() {
  local modules="cramfs squashfs udf freevxfs jffs2 hfs hfsplus"
  local module conf_file f effect backup_failed loaded

  echo -e "\n${BLUE}[*] Deshabilitando sistemas de archivos no usados... ${NC}"
  for module in $modules; do
    conf_file="/etc/modprobe.d/99-disable-$module.conf"
    echo -e "\n${YELLOW}[*] Verificando modulo: $module ${NC}"

    if modprobe -n -v "$module" 2>&1 | grep -q "not found"; then
      echo -e "${GREEN}[✓] $module no existe en el sistema${NC}"
      continue
    fi
    if grep -rq "^install $module /bin/false" /etc/modprobe.d/ 2>/dev/null &&
       grep -rq "^blacklist $module" /etc/modprobe.d/ 2>/dev/null; then
      echo -e "${GREEN}[✓] $module ya está bloqueado${NC}"
      continue
    fi

    effect="Bloquea futuras cargas del módulo $module, reduciendo la superficie de ataque. Puede impedir montar sistemas de archivos que lo necesiten. Si ya está cargado, no se descargará automáticamente porque podría estar en uso."
    echo -e "${YELLOW}[WARN] $module puede cargarse actualmente${NC}"
    echo "Qué hace/riesgo: $effect"

    if [ "$AUTO_FIX" != true ] || [ "$CHECK_MODE" = true ]; then
      echo "Recomendación: crear $conf_file con install $module /bin/false y blacklist $module."
      WARNINGS=$((WARNINGS + 1))
      continue
    fi
    if ! confirm_fs_change "Bloquear el módulo $module" "$effect"; then
      WARNINGS=$((WARNINGS + 1))
      continue
    fi

    backup_failed=false
    for f in /etc/modprobe.d/*.conf; do
      [ -f "$f" ] || continue
      if grep -q "^install $module /bin/true" "$f" 2>/dev/null; then
        backup_fs_file "$f" || backup_failed=true
      fi
    done
    if [ -e "$conf_file" ]; then backup_fs_file "$conf_file" || backup_failed=true; fi
    if $backup_failed; then
      echo "[ERROR] Falló un backup previo; no se modifica la configuración de $module."
      WARNINGS=$((WARNINGS + 1))
      continue
    fi
    [ ! -L "$conf_file" ] || { echo "[ERROR] $conf_file es un enlace simbólico; se omite."; WARNINGS=$((WARNINGS+1)); continue; }

    for f in /etc/modprobe.d/*.conf; do
      [ -f "$f" ] || continue
      if grep -q "^install $module /bin/true" "$f" 2>/dev/null; then
        sed -i '/^install '"$module"' \/bin\/true/d' "$f"
        sed -i '/^# Deshabilitar '"$module"'/d' "$f"
      fi
    done

    cat > "$conf_file" <<EOF
# OrangeBox hardening: block loading of unused filesystem module
# Explanation: reduces the attack surface; may prevent mounting legacy filesystems.
install $module /bin/false
blacklist $module
EOF
    if [ $? -ne 0 ]; then
      echo "[ERROR] No se pudo escribir $conf_file."
      WARNINGS=$((WARNINGS + 1))
      continue
    fi
    echo -e "${GREEN}[✓] $module bloqueado para futuras cargas en $conf_file${NC}"
    FIXED=$((FIXED + 1))

    if lsmod | grep -q "^$module"; then
      echo -e "${YELLOW}[WARN] $module está cargado actualmente; no se descarga en caliente. El bloqueo impedirá cargas futuras y la descarga debe planificarse tras confirmar que no está en uso.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
}

# ==============================================
# FUNCION PARA VERIFICAR PARTICIONES SEPARADAS
# ==============================================
check_separated_partitions() {
  echo -e "\n${BLUE}[*] Verificando particiones separadas criticas...${NC}"
  echo -e "${BLUE}============================================${NC}"

  local missing_separated=()
  local root_device=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/\[.*\]//' | xargs)
  local root_device_real=$(readlink -f "$root_device" 2>/dev/null)

  echo -e "${BLUE}Dispositivo raiz: ${root_device}${NC}\n"

  for mount_point in "${MUST_BE_SEPARATED[@]}"; do
    if ! findmnt -n "$mount_point" &>/dev/null; then
      echo -e "${RED}[✗] $mount_point NO esta montado${NC}"
      missing_separated+=("$mount_point")
      continue
    fi

    local mount_device=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | sed 's/\[.*\]//' | xargs)
    local mount_device_real=$(readlink -f "$mount_device" 2>/dev/null)

    if [ -n "$mount_device" ] && [ "$mount_device_real" != "$root_device_real" ] && [ "$mount_device" != "$root_device" ]; then
      echo -e "${GREEN}[✓] $mount_point es una particion separada (${mount_device})${NC}"
    else
      echo -e "${RED}[✗] $mount_point NO es una particion separada${NC}"
      missing_separated+=("$mount_point")
    fi
  done

  for mount_point in "${ADDITIONAL_MOUNTS[@]}"; do
    if findmnt -n "$mount_point" &>/dev/null; then
      local mount_device=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | sed 's/\[.*\]//' | xargs)
      local mount_device_real=$(readlink -f "$mount_device" 2>/dev/null)

      if [ -n "$mount_device" ] && [ "$mount_device_real" != "$root_device_real" ] && [ "$mount_device" != "$root_device" ]; then
        echo -e "${GREEN}[✓] $mount_point es una particion separada (${mount_device})${NC}"
      else
        echo -e "${YELLOW}[!] $mount_point NO es particion separada${NC}"
        missing_separated+=("$mount_point")
      fi
    fi
  done

  if [ ${#missing_separated[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}============================================${NC}"
    echo -e "${YELLOW} ⚠️  ADVERTENCIA DE SEGURIDAD ⚠️${NC}"
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${RED}Las siguientes particiones NO estan separadas:${NC}"
    for mp in "${missing_separated[@]}"; do
      echo -e "  • ${mp}"
    done

    if check_lvm; then
      echo -e "\n${BLUE}🛠️  Como el sistema usa LVM, puede crear estas particiones sin reinstalar:${NC}"
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo -e "\n${YELLOW}⚠️  NOTA: Realice backup antes de modificar particiones!${NC}"
    else
      echo -e "\n${RED}════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED} 🚨 RECOMENDACION IMPORTANTE - REINSTALACION NECESARIA 🚨${NC}"
      echo -e "${RED}════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED}El sistema NO usa LVM. Se recomienda reinstalar con particiones separadas.${NC}"
    fi
    WARNINGS=$((WARNINGS + ${#missing_separated[@]}))
  else
    echo -e "\n${GREEN}[✓] EXCELENTE: Todas las particiones criticas estan separadas${NC}"
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR OPCIONES DE MONTAJE
# ==============================================
check_mount_options() {
  local mount_point="$1" required_opts="$2" current_opts="" opt="" missing_opts="" approved_opts="" new_opts="" effect=""
  local -a required_array=()
  echo -e "\n${BLUE}[*] Verificando opciones de montaje de $mount_point...${NC}"

  if ! findmnt -n "$mount_point" >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] $mount_point no está montado; no se modifica.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  current_opts="$(findmnt -n -o OPTIONS "$mount_point" 2>/dev/null | tr ',' '\n' | sort -u | paste -sd, -)"
  IFS=',' read -r -a required_array <<< "$required_opts"
  for opt in "${required_array[@]}"; do
    case ",$current_opts," in
      *",$opt,"*) ;;
      *)
        missing_opts="$missing_opts $opt"
        effect=""
        case "$opt" in
          nodev) effect="Qué hace: impide usar nodos de dispositivo en este montaje. Riesgo: puede afectar herramientas que los necesiten." ;;
          nosuid) effect="Qué hace: ignora bits SUID/SGID en este montaje. Riesgo: programas que dependan de esos bits no podrán elevar privilegios." ;;
          noexec) effect="Qué hace: bloquea la ejecución directa de binarios en $mount_point. Riesgo: puede impedir ejecutar aplicaciones o scripts legítimos desde ese montaje." ;;
          *) effect="restringe una capacidad del montaje; valida las aplicaciones que usen $mount_point." ;;
        esac
        echo -e "${YELLOW}[WARN] $mount_point necesita opción $opt.${NC}"
        echo "Qué hace/riesgo: $effect"
        if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
          if confirm_fs_change "$mount_point: $opt" "$effect"; then
            approved_opts="$approved_opts $opt"
          else
            WARNINGS=$((WARNINGS + 1))
          fi
        else
          WARNINGS=$((WARNINGS + 1))
        fi
        ;;
    esac
  done
  [ -n "$missing_opts" ] || { echo -e "${GREEN}[✓] $mount_point cumple las opciones requeridas${NC}"; return 0; }
  if [ "$AUTO_FIX" != true ] || [ "$CHECK_MODE" = true ]; then
    echo "Opciones actuales: $current_opts; faltantes:$missing_opts"
    return 0
  fi
  [ -n "$approved_opts" ] || { echo "[INFO] No se aprobaron cambios para $mount_point."; return 0; }

  backup_fs_file /etc/fstab || { WARNINGS=$((WARNINGS + 1)); return 1; }
  new_opts="$current_opts"
  for opt in $approved_opts; do
    case ",$new_opts," in *",$opt,"*) ;; *) new_opts="$new_opts,$opt" ;; esac
  done
  if mount -o remount,"$new_opts" "$mount_point"; then
    echo -e "${GREEN}[✓] $mount_point remontado con opciones aprobadas: $approved_opts${NC}"
    local -a approved_array=()
    IFS=' ' read -r -a approved_array <<< "$approved_opts"
    if ! persist_mount_options "$mount_point" false "" "${approved_array[@]}"; then
      echo -e "${YELLOW}[WARN] El montaje está protegido en runtime, pero no se pudo hacer persistente en /etc/fstab; revise manualmente.${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[ERROR] No se pudo remontar $mount_point; no se modificó fstab.${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# APLICAR STICKY BIT
# ==============================================
apply_sticky_bit() {
  echo -e "\n${BLUE}[*] Verificando sticky bit...${NC}"
  local sticky_issues effect
  sticky_issues="$(df --local -P 2>/dev/null | awk '{if (NR!=1) print $6}' | xargs -I '{}' find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null)"
  if [ -z "$sticky_issues" ]; then
    echo -e "${GREEN}[✓] Todos los directorios world-writable tienen sticky bit${NC}"
    return 0
  fi
  echo -e "${YELLOW}[WARN] Directorios escribibles por todos sin sticky bit:${NC}"
  printf '%s\n' "$sticky_issues"
  effect="El sticky bit limita quién puede borrar o renombrar archivos de un directorio compartido (normalmente solo el propietario o root). Es una protección común, pero puede cambiar flujos de aplicaciones que borran archivos de otros usuarios."
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ] || [ "$CHECK_MODE" = true ]; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if ! confirm_fs_change "Aplicar sticky bit a los directorios listados" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if printf '%s\n' "$sticky_issues" | xargs -r chmod a+t; then
    echo -e "${GREEN}[✓] Sticky bit aplicado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[ERROR] No se pudo aplicar sticky bit a todos los directorios.${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# DESHABILITAR AUTOFS
# ==============================================
disable_autofs() {
  echo -e "\n${BLUE}[*] Verificando autofs...${NC}"
  local present=false active=false enabled=false effect
  if command -v automount >/dev/null 2>&1; then present=true; fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl list-unit-files autofs.service 2>/dev/null | grep -q 'autofs.service' && present=true
    systemctl is-active --quiet autofs 2>/dev/null && active=true
    systemctl is-enabled --quiet autofs 2>/dev/null && enabled=true
  elif command -v service >/dev/null 2>&1; then
    service autofs status >/dev/null 2>&1 && active=true
    if command -v chkconfig >/dev/null 2>&1 && chkconfig --list autofs 2>/dev/null | grep -Eq '2:on|3:on|4:on|5:on'; then enabled=true; fi
  fi
  if [ "$present" != true ]; then
    echo -e "${GREEN}[✓] autofs no está instalado${NC}"
    return 0
  fi
  if [ "$active" != true ] && [ "$enabled" != true ]; then
    echo -e "${GREEN}[✓] autofs no está activo ni habilitado${NC}"
    return 0
  fi
  effect="detiene/deshabilita el montaje automático de medios y recursos. Si el servidor usa automount para NFS, directorios de usuarios o almacenamiento, esos recursos pueden dejar de montarse."
  echo -e "${YELLOW}[WARN] autofs presente: active=$active enabled=$enabled${NC}"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ] || [ "$CHECK_MODE" = true ]; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  if ! confirm_fs_change "Deshabilitar autofs" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
  local rc=0
  if command -v systemctl >/dev/null 2>&1; then
    [ "$active" != true ] || systemctl stop autofs || rc=1
    [ "$enabled" != true ] || systemctl disable autofs || rc=1
  else
    [ "$active" != true ] || service autofs stop || rc=1
    [ "$enabled" != true ] || chkconfig autofs off || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    echo -e "${GREEN}[✓] autofs detenido/deshabilitado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${RED}[ERROR] No se pudo deshabilitar autofs completamente.${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR /DEV/SHM
# ==============================================
configure_dev_shm() {
  echo -e "\n${BLUE}[*] Verificando /dev/shm...${NC}"
  if ! findmnt -n /dev/shm >/dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] /dev/shm no aparece montado; no se monta automáticamente para evitar superponer un recurso vivo.${NC}"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  local current_opts="" opt="" approved_opts="" new_opts="" effect
  local -a required=("noexec" "nosuid" "nodev") approved_array=()
  current_opts="$(findmnt -n -o OPTIONS /dev/shm 2>/dev/null | tr ',' '\n' | sort -u | paste -sd, -)"
  for opt in "${required[@]}"; do
    case ",$current_opts," in
      *",$opt,"*) ;;
      *)
        case "$opt" in
          noexec) effect="bloquea la ejecución directa desde la memoria compartida; puede afectar aplicaciones que generen y ejecuten binarios temporales." ;;
          nosuid) effect="ignora bits SUID/SGID en /dev/shm; programas que dependan de esos bits no elevarán privilegios." ;;
          nodev) effect="impide interpretar nodos de dispositivo desde /dev/shm." ;;
        esac
        echo -e "${YELLOW}[WARN] Falta $opt en /dev/shm.${NC}"
        echo "Qué hace/riesgo: $effect"
        if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
          if confirm_fs_change "/dev/shm: $opt" "$effect"; then approved_opts="$approved_opts $opt"; else WARNINGS=$((WARNINGS+1)); fi
        else
          WARNINGS=$((WARNINGS+1))
        fi
        ;;
    esac
  done
  [ -n "$approved_opts" ] || return 0
  backup_fs_file /etc/fstab || { WARNINGS=$((WARNINGS+1)); return 1; }
  new_opts="$current_opts"
  for opt in $approved_opts; do
    case ",$new_opts," in *",$opt,"*) ;; *) new_opts="$new_opts,$opt" ;; esac
  done
  if ! mount -o remount,"$new_opts" /dev/shm; then
    echo -e "${RED}[ERROR] No se pudo remontar /dev/shm.${NC}"
    WARNINGS=$((WARNINGS+1))
    return 1
  fi
  IFS=' ' read -r -a approved_array <<< "$approved_opts"
  if ! persist_mount_options /dev/shm true "tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0" "${approved_array[@]}"; then
    echo -e "${YELLOW}[WARN] /dev/shm está corregido en runtime, pero no se pudo persistir la configuración.${NC}"
    WARNINGS=$((WARNINGS+1))
  fi
  echo -e "${GREEN}[✓] /dev/shm actualizado con opciones aprobadas: $approved_opts${NC}"
  FIXED=$((FIXED+1))
}

# ==============================================
# ==============================================
# ==============================================
# MOSTRAR RESUMEN FINAL
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  FILESYSTEM HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  echo -e "\n${YELLOW}VERIFICAR PARTICIONES SEPARADAS:${NC}"
  echo -e "  lsblk"
  echo -e "  findmnt /opt /var /tmp /boot /home /var/log"

  echo -e "\n${YELLOW}VERIFICAR MODULOS DESHABILITADOS:${NC}"
  echo -e "  lsmod | grep -E 'cramfs|squashfs|udf|freevxfs|jffs2|hfs|hfsplus'"
  echo -e "  grep -r 'install.*\/bin\/false' /etc/modprobe.d/"

  echo -e "\n${YELLOW}VERIFICAR FSTAB:${NC}"
  echo -e "  grep -E '(/opt|/var|/tmp|/boot|/home|/var/log|/dev/shm|/proc)' /etc/fstab"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}==============================================${NC}"
  echo -e "${GREEN}  Hardening de Filesystem - perfil OrangeBox${NC}"
  echo -e "${GREEN}==============================================${NC}\n"

  case "$1" in
    --help|-h) show_usage; exit 0 ;;
    --fix|-f)
      AUTO_FIX=true
      # El módulo standalone exige confirmación por cambio. El orquestador puede
      # exportar ORANGEBOX_ASSUME_YES=1 explícitamente para su modo --fix automático.
      CHECK_MODE=false
      echo -e "${YELLOW}MODO FIX: se solicitará confirmación individual antes de cada cambio sensible.${NC}"
      ;;
    --check|-c|"")
      AUTO_FIX=false
      CHECK_MODE=true
      echo -e "${GREEN}MODO AUDITORÍA: no se aplicarán cambios.${NC}"
      ;;
    *)
      echo "${RED}Argumento desconocido: $1${NC}" >&2
      show_usage
      exit 2
      ;;
  esac

  disable_modules
  check_separated_partitions

  local mount_point required_opts
  for mount_point in /opt /var /tmp /boot /home /var/log /var/tmp /var/ossec /var/log/audit; do
    if findmnt -n "$mount_point" >/dev/null 2>&1; then
      required_opts="${MOUNT_REQUIREMENTS[$mount_point]}"
      [ -z "$required_opts" ] || check_mount_options "$mount_point" "$required_opts"
    fi
  done

  configure_dev_shm
  echo -e "${BLUE}[INFO] /proc se conserva sin hidepid=2 para no interferir con agentes de monitorización como Zabbix.${NC}"
  apply_sticky_bit
  disable_autofs

  show_summary
  if [ "$CHECK_MODE" = true ] && [ "$WARNINGS" -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar los cambios, ejecute: $0 --fix${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
