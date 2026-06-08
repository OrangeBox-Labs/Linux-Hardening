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
AUTO_FIX=false

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
  echo "  ./FS-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./FS-hardening.sh --fix"
  echo ""
}

# ==============================================
# DEFINICION DE PUNTOS DE MONTAJE CRITICOS
# ==============================================

# Puntos de montaje que DEBEN ser particiones separadas
declare -a MUST_BE_SEPARATED=(
  "/opt"
  "/var"
  "/tmp"
  "/boot"
  "/home"
  "/var/log"
)

# Puntos de montaje especiales o adicionales
declare -a ADDITIONAL_MOUNTS=(
  "/var/tmp"
  "/var/log/audit"
  "/var/ossec"
)

# Opciones requeridas para cada punto de montaje (si existe)
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

# Modulos de filesystem a deshabilitar (CIS 1.1.1.x)
declare -a MODULES_TO_DISABLE=(
  "cramfs"
  "squashfs"
  "udf"
  "freevxfs"
  "jffs2"
  "hfs"
  "hfsplus"
)

# ==============================================
# FUNCION PARA DESHABILITAR MODULO (CORREGIDO)
# ==============================================
disable_filesystem_module() {
  local module="$1"
  local conf_file="/etc/modprobe.d/99-disable-${module}.conf"

  echo -e "\n${BLUE}[*] Verificando modulo: $module${NC}"

  # Verificar si el modulo existe en el sistema
  if ! modprobe -n -v "$module" 2>&1 | grep -q "not found"; then
    # Verificar si ya esta deshabilitado (buscando en todos los archivos .conf)
    if grep -rq "^install $module /bin/false\|^install $module /bin/true" /etc/modprobe.d/ 2>/dev/null; then
      echo -e "${GREEN}[✓] $module ya estaba deshabilitado${NC}"
      return 0
    fi

    # Verificar si existe configuracion comentada
    if grep -rq "^#\s*install $module" /etc/modprobe.d/ 2>/dev/null; then
      echo -e "${YELLOW}[!] $module configuracion comentada encontrada${NC}"
      if [ "$AUTO_FIX" = true ]; then
        # Buscar y descomentar la configuracion existente
        for f in /etc/modprobe.d/*.conf; do
          if grep -q "^#\s*install $module" "$f" 2>/dev/null; then
            sed -i "s/^#\s*install $module/install $module/" "$f"
            sed -i "s/^#\s*blacklist $module/blacklist $module/" "$f"
            echo -e "${GREEN}[✓] $module configuracion descomentada en $f${NC}"
            FIXED=$((FIXED + 1))
          fi
        done
      else
        WARNINGS=$((WARNINGS + 1))
      fi
      return 0
    fi

    echo -e "${RED}[!] $module existe - debe deshabilitarse${NC}"

    if [ "$AUTO_FIX" = true ]; then
      # Crear archivo de configuracion
      cat >"$conf_file" <<EOF
# Deshabilitar $module por seguridad (CIS 1.1.1.x)
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
      echo -e "${YELLOW}    Recomendacion: Deshabilitar $module${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] $module no existe en el sistema${NC}"
  fi
}

# ==============================================
# FUNCION PARA PREGUNTAR AL USUARIO
# ==============================================
ask_confirmation() {
  local mount_point="$1"
  local missing_opts="$2"

  echo -e "${YELLOW}¿Desea agregar las opciones '${missing_opts}' a ${mount_point}? (s/n)${NC}"
  read -r answer
  case "$answer" in
  s | S | si | Si | SI | yes | Yes | YES)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

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
# FUNCION PARA VERIFICAR PARTICIONES SEPARADAS
# ==============================================
check_separated_partitions() {
  echo -e "\n${BLUE}[*] Verificando particiones separadas criticas...${NC}"
  echo -e "${BLUE}============================================${NC}"

  local missing_separated=()
  local existing_separated=()

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
      existing_separated+=("$mount_point")
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
        existing_separated+=("$mount_point")
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
      echo -e "${YELLOW}⚠️  Para /var se recomienda hacerlo en modo single user${NC}"
    else
      echo -e "\n${RED}════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED} 🚨 RECOMENDACION IMPORTANTE - REINSTALACION NECESARIA 🚨${NC}"
      echo -e "${RED}════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED}El sistema NO usa LVM. Para cumplir con CIS Benchmark,${NC}"
      echo -e "${RED}es necesario REINSTALAR el sistema con las siguientes particiones separadas:${NC}"
      echo -e ""
      echo -e "${GREEN}Particion     | Tamaño minimo | Opciones de montaje${NC}"
      echo -e "${GREEN}--------------|---------------|----------------------------------------${NC}"
      echo -e "/boot         | 1GB           | defaults,nodev,nosuid,noexec"
      echo -e "/home         | 5GB+          | defaults,noexec,nosuid,nodev"
      echo -e "/tmp          | 2GB           | defaults,noexec,nosuid,nodev"
      echo -e "/var          | 5GB           | defaults,noexec,nosuid,nodev"
      echo -e "/var/log      | 2GB           | defaults,noexec,nosuid,nodev"
      echo -e "/var/log/audit| 1GB           | defaults,noexec,nosuid,nodev"
      echo -e "/var/tmp      | 1GB           | defaults,noexec,nosuid,nodev"
      echo -e "/opt          | 2GB           | defaults,nosuid,nodev"
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

  local apply_fix=false
  if [ "$AUTO_FIX" = true ]; then
    apply_fix=true
  else
    if ask_confirmation "$mount_point" "$missing_opts"; then
      apply_fix=true
    fi
  fi

  if [ "$apply_fix" = true ]; then
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
        local fstab_new_opts="defaults"
        for opt in "${required_array[@]}"; do
          fstab_new_opts="$fstab_new_opts,$opt"
        done
        fstab_new_opts=$(echo "$fstab_new_opts" | sed 's/^defaults,defaults/defaults/')
        sed -i "s|\(.*[[:space:]]${mount_point}[[:space:]].*\)${fstab_opts}|\1${fstab_new_opts}|" /etc/fstab
        echo -e "${GREEN}[✓] /etc/fstab actualizado${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al remontar ${mount_point}${NC}"
    fi
  else
    echo -e "${YELLOW}[!] Omitiendo correccion${NC}"
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

  local apply_fix=false
  if [ "$AUTO_FIX" = true ]; then
    apply_fix=true
  else
    echo -e "${YELLOW}¿Desea aplicar sticky bit? (s/n)${NC}"
    read -r answer
    case "$answer" in
    s | S | si | Si | SI | yes | Yes | YES) apply_fix=true ;;
    esac
  fi

  if [ "$apply_fix" = true ]; then
    echo "$sticky_issues" | xargs chmod a+t 2>/dev/null
    echo -e "${GREEN}[✓] Sticky bit aplicado${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}[!] Omitiendo sticky bit${NC}"
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
    local apply_fix=false
    if [ "$AUTO_FIX" = true ]; then
      apply_fix=true
    else
      echo -e "${YELLOW}¿Desea deshabilitar autofs? (s/n)${NC}"
      read -r answer
      case "$answer" in
      s | S | si | Si | SI | yes | Yes | YES) apply_fix=true ;;
      esac
    fi

    if [ "$apply_fix" = true ]; then
      systemctl stop autofs 2>/dev/null
      systemctl disable autofs 2>/dev/null
      echo -e "${GREEN}[✓] autofs deshabilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}[!] Omitiendo deshabilitacion${NC}"
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
    mount -t tmpfs tmpfs /dev/shm 2>/dev/null
  fi

  local current_opts=$(findmnt -n -o OPTIONS /dev/shm 2>/dev/null)
  local required_opts="noexec,nosuid,nodev"

  if [[ "$current_opts" == *"noexec"* ]] && [[ "$current_opts" == *"nodev"* ]] && [[ "$current_opts" == *"nosuid"* ]]; then
    echo -e "${GREEN}[✓] /dev/shm ya tiene opciones seguras${NC}"
    return 0
  fi

  echo -e "${RED}[!] /dev/shm falta opciones de seguridad${NC}"

  local apply_fix=false
  if [ "$AUTO_FIX" = true ]; then
    apply_fix=true
  else
    echo -e "${YELLOW}¿Desea aplicar opciones seguras a /dev/shm? (s/n)${NC}"
    read -r answer
    case "$answer" in
    s | S | si | Si | SI | yes | Yes | YES) apply_fix=true ;;
    esac
  fi

  if [ "$apply_fix" = true ]; then
    mount -o remount,"$required_opts" /dev/shm 2>/dev/null
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[✓] /dev/shm configurado con opciones seguras${NC}"
      if ! grep -q "^[^#].*/dev/shm" /etc/fstab 2>/dev/null; then
        echo "tmpfs /dev/shm tmpfs defaults,$required_opts 0 0" >>/etc/fstab
        echo -e "${GREEN}[✓] Entrada agregada a /etc/fstab${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al configurar /dev/shm${NC}"
    fi
  else
    echo -e "${YELLOW}[!] Omitiendo correccion${NC}"
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

  if [[ "$current_opts" == *"hidepid=2"* ]]; then
    echo -e "${GREEN}[✓] /proc ya tiene hidepid=2 configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] /proc no tiene hidepid=2${NC}"

  local apply_fix=false
  if [ "$AUTO_FIX" = true ]; then
    apply_fix=true
  else
    echo -e "${YELLOW}¿Desea aplicar hidepid=2 a /proc? (s/n)${NC}"
    read -r answer
    case "$answer" in
    s | S | si | Si | SI | yes | Yes | YES) apply_fix=true ;;
    esac
  fi

  if [ "$apply_fix" = true ]; then
    mount -o remount,hidepid=2 /proc 2>/dev/null
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[✓] /proc configurado con hidepid=2${NC}"
      if ! grep -q "^[^#].*/proc" /etc/fstab 2>/dev/null; then
        echo "proc /proc proc defaults,hidepid=2 0 0" >>/etc/fstab
        echo -e "${GREEN}[✓] Entrada agregada a /etc/fstab${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al configurar /proc${NC}"
    fi
  else
    echo -e "${YELLOW}[!] Omitiendo correccion${NC}"
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
  echo -e "  grep -r 'install.*/bin/false' /etc/modprobe.d/"

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

  # Modo ayuda
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  # Modo verificación
  if [ "$1" != "--fix" ] && [ "$1" != "-f" ]; then
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"
    AUTO_FIX=false
  fi

  # Modo automático
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
  fi

  # Deshabilitar modulos de filesystem
  for module in "${MODULES_TO_DISABLE[@]}"; do
    disable_filesystem_module "$module"
  done

  # Verificar particiones separadas
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

  if [ "$AUTO_FIX" = false ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
