#!/bin/bash

# ==============================================
# Script: FS-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de sistema de archivos segun CIS Benchmark
#              - Verifica particiones separadas criticas
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
AUTO_FIX=true
CHECK_MODE=false

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo automatico (aplica las correcciones)"
  echo "  $0 --check    - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 -c         - Modo verificación (version corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Aplicar los cambios directamente"
  echo "  ./FS-hardening.sh"
  echo ""
  echo "  # Ver qué cambios se aplicarían sin hacerlos"
  echo "  ./FS-hardening.sh --check"
  echo ""
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
  ["/proc"]="hidepid=2"
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

  echo -e "\n${BLUE}[*] Deshabilitando sistemas de archivos no usados...${NC}"

  for module in $modules; do
    local conf_file="/etc/modprobe.d/99-disable-${module}.conf"

    echo -e "\n${YELLOW}[*] Verificando modulo: $module${NC}"

    # Verificar si el modulo existe en el sistema
    if modprobe -n -v "$module" 2>&1 | grep -q "not found"; then
      echo -e "${GREEN}[✓] $module no existe en el sistema${NC}"
      continue
    fi

    # Verificar si ya esta correctamente deshabilitado con /bin/false
    if grep -q "^install $module /bin/false" "$conf_file" 2>/dev/null; then
      echo -e "${GREEN}[✓] $module ya estaba correctamente deshabilitado${NC}"
      continue
    fi

    # Verificar si existe configuracion incorrecta (con /bin/true) en algun archivo
    if grep -rq "^install $module /bin/true" /etc/modprobe.d/ 2>/dev/null; then
      echo -e "${YELLOW}[!] $module tiene configuracion incorrecta (/bin/true)${NC}"
      if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
        # Eliminar la configuracion incorrecta de todos los archivos
        for f in /etc/modprobe.d/*.conf; do
          if grep -q "^install $module /bin/true" "$f" 2>/dev/null; then
            sed -i '/^install '$module' \/bin\/true/d' "$f"
            sed -i '/^# Deshabilitar '$module'/d' "$f"
            echo -e "${GREEN}[✓] Configuracion incorrecta eliminada de $f${NC}"
          fi
        done
      fi
    fi

    # El modulo no esta deshabilitado o hay que crearlo
    echo -e "${RED}[!] $module NO esta deshabilitado correctamente${NC}"

    if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
      cat >"$conf_file" <<EOF
# ==============================================
# Hardening: Modulo $module deshabilitado
# Script: FS-hardening.sh
# Fuente: https://www.orangebox.cl
# ==============================================
install $module /bin/false
blacklist $module
EOF
      echo -e "${GREEN}[✓] $module deshabilitado en $conf_file${NC}"

      # Si el modulo esta cargado, descargarlo
      if lsmod | grep -q "^$module"; then
        rmmod "$module" 2>/dev/null
        echo -e "${GREEN}[✓] $module descargado del kernel${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Crear $conf_file con:${NC}"
      echo -e "      install $module /bin/false"
      echo -e "      blacklist $module"
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
  local mount_point="$1"
  local required_opts="$2"

  echo -e "\n${BLUE}[*] Verificando opciones de montaje de ${mount_point}...${NC}"

  if ! findmnt -n "$mount_point" &>/dev/null; then
    echo -e "${YELLOW}[!] ${mount_point} no esta montado${NC}"
    return 1
  fi

  local current_opts=$(findmnt -n -o OPTIONS "$mount_point" 2>/dev/null | tr ',' '\n' | sort | uniq | tr '\n' ',' | sed 's/,$//')

  local missing_opts=""
  IFS=',' read -ra required_array <<<"$required_opts"
  for opt in "${required_array[@]}"; do
    if [[ ! "$current_opts" == *"$opt"* ]]; then
      missing_opts="$missing_opts,$opt"
    fi
  done
  missing_opts="${missing_opts#,}"

  if [ -z "$missing_opts" ]; then
    echo -e "${GREEN}[✓] ${mount_point} tiene todas las opciones requeridas${NC}"
    return 0
  fi

  echo -e "${RED}[!] ${mount_point} falta opciones: ${missing_opts}${NC}"
  echo -e "    Opciones actuales: ${current_opts}"
  echo -e "    Opciones requeridas: ${required_opts}"

  if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
    local new_opts="$current_opts"
    for opt in "${required_array[@]}"; do
      if [[ ! "$new_opts" == *"$opt"* ]]; then
        new_opts="$new_opts,$opt"
      fi
    done

    echo -e "${YELLOW}[*] Aplicando nuevas opciones...${NC}"
    if mount -o remount,"$new_opts" "$mount_point" 2>/dev/null; then
      echo -e "${GREEN}[✓] ${mount_point} remontado con exito${NC}"

      if grep -q "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab 2>/dev/null; then
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d-%H%M%S)
        local fstab_opts=$(grep "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab | head -1 | awk '{print $4}')
        local fstab_new_opts="$fstab_opts"
        for opt in "${required_array[@]}"; do
          if [[ ! "$fstab_new_opts" == *"$opt"* ]]; then
            fstab_new_opts="$fstab_new_opts,$opt"
          fi
        done
        sed -i "s|\(.*[[:space:]]${mount_point}[[:space:]].*\)${fstab_opts}|\1${fstab_new_opts}|" /etc/fstab
        echo -e "${GREEN}[✓] /etc/fstab actualizado${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al remontar ${mount_point}${NC}"
    fi
  else
    echo -e "${YELLOW}[!] Se requiere aplicar: mount -o remount,${new_opts} ${mount_point}${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# APLICAR STICKY BIT
# ==============================================
apply_sticky_bit() {
  echo -e "\n${BLUE}[*] Verificando sticky bit...${NC}"

  local sticky_issues=$(df --local -P 2>/dev/null | awk '{if (NR!=1) print $6}' | xargs -I '{}' find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null)

  if [ -z "$sticky_issues" ]; then
    echo -e "${GREEN}[✓] Todos los directorios world-writable tienen sticky bit${NC}"
    return 0
  fi

  echo -e "${RED}[!] Directorios sin sticky bit encontrados${NC}"

  if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
    echo "$sticky_issues" | xargs chmod a+t 2>/dev/null
    echo -e "${GREEN}[✓] Sticky bit aplicado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}[!] Se requiere aplicar: chmod a+t a los directorios listados${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# DESHABILITAR AUTOFS
# ==============================================
disable_autofs() {
  echo -e "\n${BLUE}[*] Verificando autofs...${NC}"

  if ! command -v automount &>/dev/null && ! systemctl list-unit-files 2>/dev/null | grep -q "autofs.service"; then
    echo -e "${GREEN}[✓] autofs no esta instalado${NC}"
    return 0
  fi

  local need_fix=0
  if systemctl is-active --quiet autofs 2>/dev/null; then
    echo -e "${RED}[!] autofs esta ACTIVO${NC}"
    need_fix=1
  else
    echo -e "${GREEN}[✓] autofs no esta activo${NC}"
  fi

  if systemctl is-enabled --quiet autofs 2>/dev/null; then
    echo -e "${RED}[!] autofs esta habilitado${NC}"
    need_fix=1
  else
    echo -e "${GREEN}[✓] autofs no esta habilitado${NC}"
  fi

  if [ $need_fix -eq 1 ]; then
    if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
      systemctl stop autofs 2>/dev/null
      systemctl disable autofs 2>/dev/null
      echo -e "${GREEN}[✓] autofs deshabilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}[!] Se requiere: systemctl stop autofs && systemctl disable autofs${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# CONFIGURAR /DEV/SHM
# ==============================================
configure_dev_shm() {
  echo -e "\n${BLUE}[*] Configurando /dev/shm...${NC}"

  if ! findmnt -n /dev/shm &>/dev/null; then
    echo -e "${YELLOW}[!] /dev/shm no esta montado, creando...${NC}"
    if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
      mount -t tmpfs tmpfs /dev/shm 2>/dev/null
    fi
  fi

  local current_opts=$(findmnt -n -o OPTIONS /dev/shm 2>/dev/null)
  local required_opts="noexec,nosuid,nodev"

  if [[ "$current_opts" == *"noexec"* ]] && [[ "$current_opts" == *"nodev"* ]] && [[ "$current_opts" == *"nosuid"* ]]; then
    echo -e "${GREEN}[✓] /dev/shm ya tiene opciones seguras${NC}"
    return 0
  fi

  echo -e "${RED}[!] /dev/shm falta opciones de seguridad${NC}"

  if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
    mount -o remount,"$required_opts" /dev/shm 2>/dev/null
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[✓] /dev/shm configurado con opciones seguras${NC}"
      if ! grep -q "^[^#].*/dev/shm" /etc/fstab 2>/dev/null; then
        echo -e "\n# ==============================================" >>/etc/fstab
        echo "# Hardening: /dev/shm con opciones seguras" >>/etc/fstab
        echo "# Fuente: https://www.orangebox.cl" >>/etc/fstab
        echo "tmpfs /dev/shm tmpfs defaults,$required_opts 0 0" >>/etc/fstab
        echo -e "${GREEN}[✓] Entrada agregada a /etc/fstab${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al configurar /dev/shm${NC}"
    fi
  else
    echo -e "${YELLOW}[!] Se requiere: mount -o remount,${required_opts} /dev/shm${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR /PROC CON HIDEPID
# ==============================================
configure_proc() {
  echo -e "\n${BLUE}[*] Configurando /proc con hidepid=2...${NC}"

  if ! findmnt -n /proc &>/dev/null; then
    echo -e "${YELLOW}[!] /proc no esta montado${NC}"
    return 1
  fi

  local current_opts=$(findmnt -n -o OPTIONS /proc 2>/dev/null)

  if [[ "$current_opts" == *"hidepid=2"* ]] || [[ "$current_opts" == *"hidepid=invisible"* ]]; then
    echo -e "${GREEN}[✓] /proc ya tiene hidepid=2 configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] /proc no tiene hidepid=2${NC}"
  echo -e "    Actual: $current_opts"
  echo -e "    Requerido: hidepid=2"

  if [ "$AUTO_FIX" = true ] && [ "$CHECK_MODE" = false ]; then
    mount -o remount,hidepid=2 /proc 2>/dev/null
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[✓] /proc configurado con hidepid=2${NC}"
      if ! grep -q "^[^#].*/proc" /etc/fstab 2>/dev/null; then
        echo -e "\n# ==============================================" >>/etc/fstab
        echo "# Hardening: /proc con hidepid=2" >>/etc/fstab
        echo "# Fuente: https://www.orangebox.cl" >>/etc/fstab
        echo "proc /proc proc defaults,hidepid=2 0 0" >>/etc/fstab
        echo -e "${GREEN}[✓] Entrada agregada a /etc/fstab${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al configurar /proc${NC}"
    fi
  else
    echo -e "${YELLOW}[!] Se requiere: mount -o remount,hidepid=2 /proc${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

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
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Hardening de Filesystem - CIS Benchmark${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  if [ "$1" = "--check" ] || [ "$1" = "-c" ]; then
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    CHECK_MODE=true
    AUTO_FIX=false
  else
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    CHECK_MODE=false
    AUTO_FIX=true
  fi

  # Deshabilitar modulos de filesystem
  disable_modules

  # Verificar particiones separadas (solo muestra, no puede corregirse automaticamente)
  check_separated_partitions

  # Verificar opciones de montaje
  for mount_point in /opt /var /tmp /boot /home /var/log /var/tmp /var/ossec; do
    if findmnt -n "$mount_point" &>/dev/null; then
      required_opts="${MOUNT_REQUIREMENTS[$mount_point]}"
      if [ -n "$required_opts" ]; then
        check_mount_options "$mount_point" "$required_opts"
      fi
    fi
  done

  # Configurar puntos especiales
  configure_dev_shm
  configure_proc

  # Otras configuraciones
  apply_sticky_bit
  disable_autofs

  show_summary

  if [ "$CHECK_MODE" = true ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
