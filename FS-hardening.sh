#!/bin/bash

# ==============================================
# Script: FS-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de sistema de archivos segun CIS Benchmark
#              - Verifica particiones separadas criticas
#              - Configura opciones de montaje seguras
#              - Aplica sticky bit
#              - Deshabilita autofs y modulos inseguros
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
# DEFINICION DE PUNTOS DE MONTAJE CRITICOS
# ==============================================

# Puntos de montaje que DEBEN ser particiones separadas
# Estos directorios deben estar en discos/particiones diferentes a /
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

  # Obtener el dispositivo de la raiz (/) para comparar
  local root_device=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/\[.*\]//' | xargs)
  local root_device_real=$(readlink -f "$root_device" 2>/dev/null)

  echo -e "${BLUE}Dispositivo raiz (/: ${root_device}${NC}\n"

  # Verificar cada punto de montaje que DEBE estar separado
  for mount_point in "${MUST_BE_SEPARATED[@]}"; do
    # Verificar si el punto de montaje existe como filesystem
    if ! findmnt -n "$mount_point" &>/dev/null; then
      echo -e "${RED}[✗] $mount_point NO esta montado o NO existe como punto de montaje independiente${NC}"
      missing_separated+=("$mount_point")
      continue
    fi

    # Obtener el dispositivo de montaje
    local mount_device=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | sed 's/\[.*\]//' | xargs)
    local mount_device_real=$(readlink -f "$mount_device" 2>/dev/null)

    # Verificar si es un punto de montaje independiente (diferente de la raiz)
    if [ -n "$mount_device" ] && [ "$mount_device_real" != "$root_device_real" ] && [ "$mount_device" != "$root_device" ]; then
      echo -e "${GREEN}[✓] $mount_point es una particion separada (${mount_device})${NC}"
      existing_separated+=("$mount_point")
    else
      echo -e "${RED}[✗] $mount_point NO es una particion separada (comparte dispositivo con /)${NC}"
      missing_separated+=("$mount_point")
    fi
  done

  # Verificar puntos de montaje adicionales (si existen)
  for mount_point in "${ADDITIONAL_MOUNTS[@]}"; do
    if findmnt -n "$mount_point" &>/dev/null; then
      local mount_device=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | sed 's/\[.*\]//' | xargs)
      local mount_device_real=$(readlink -f "$mount_device" 2>/dev/null)

      if [ -n "$mount_device" ] && [ "$mount_device_real" != "$root_device_real" ] && [ "$mount_device" != "$root_device" ]; then
        echo -e "${GREEN}[✓] $mount_point es una particion separada (${mount_device})${NC}"
        existing_separated+=("$mount_point")
      else
        echo -e "${YELLOW}[!] $mount_point existe pero NO es particion separada${NC}"
        missing_separated+=("$mount_point")
      fi
    fi
  done

  # Si hay particiones no separadas, mostrar advertencia detallada
  if [ ${#missing_separated[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}============================================${NC}"
    echo -e "${YELLOW} ⚠️  ADVERTENCIA DE SEGURIDAD ⚠️${NC}"
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${RED}Las siguientes particiones NO estan separadas de la raiz (/):${NC}"
    for mp in "${missing_separated[@]}"; do
      echo -e "  • ${mp}"
    done

    echo -e "\n${YELLOW}📌 Riesgos de seguridad especificos:${NC}"
    for mp in "${missing_separated[@]}"; do
      case "$mp" in
      "/opt")
        echo -e "  ${RED}→ /opt:${NC}"
        echo -e "      • Aplicaciones de terceros pueden comprometer la particion root"
        echo -e "      • Instalaciones grandes pueden llenar espacio root"
        echo -e "      • Permite ejecucion de binarios no verificados"
        ;;
      "/tmp")
        echo -e "  ${RED}→ /tmp:${NC}"
        echo -e "      • Permite ejecucion de archivos temporales maliciosos"
        echo -e "      • Un atacante puede llenar /tmp y causar DoS en particion root"
        echo -e "      • Ataques de symlink pueden afectar archivos del sistema"
        ;;
      "/var")
        echo -e "  ${RED}→ /var:${NC}"
        echo -e "      • Logs pueden llenar particion root causando DoS"
        echo -e "      • Datos variables pueden comprometer estabilidad del sistema"
        echo -e "      • Spools y caches pueden crecer sin control"
        ;;
      "/var/log")
        echo -e "  ${RED}→ /var/log:${NC}"
        echo -e "      • Logs de auditoria pueden llenar particion root"
        echo -e "      • Un ataque puede generar logs masivos para DoS"
        echo -e "      • Rotacion de logs puede fallar por falta de espacio"
        ;;
      "/var/tmp")
        echo -e "  ${RED}→ /var/tmp:${NC}"
        echo -e "      • Archivos temporales persistentes pueden llenar particion root"
        echo -e "      • Datos temporales entre reinicios pueden acumularse"
        ;;
      "/home")
        echo -e "  ${RED}→ /home:${NC}"
        echo -e "      • Usuarios pueden llenar particion root con archivos personales"
        echo -e "      • Ataques de quota pueden afectar sistema completo"
        echo -e "      • Backups de usuarios pueden saturar el sistema"
        ;;
      "/boot")
        echo -e "  ${RED}→ /boot:${NC}"
        echo -e "      • Multiples kernels pueden llenar la particion"
        echo -e "      • Actualizaciones fallidas por falta de espacio"
        echo -e "      • Riesgo de corrupcion del bootloader"
        ;;
      "/var/log/audit")
        echo -e "  ${RED}→ /var/log/audit:${NC}"
        echo -e "      • Logs de auditoria pueden llenar particion root"
        echo -e "      • Sistema puede dejar de auditar eventos criticos"
        echo -e "      • Cumplimiento normativo en riesgo"
        ;;
      esac
    done

    # Recomendaciones segun tipo de almacenamiento
    if check_lvm; then
      echo -e "\n${BLUE}🛠️  Como el sistema usa LVM, puede crear estas particiones SIN reinstalar:${NC}"
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

      for mp in "${missing_separated[@]}"; do
        case "$mp" in
        "/home")
          echo -e "\n${GREEN}Ejemplo para crear /home como particion separada:${NC}"
          echo -e "  # 1. Crear volumen logico de 10GB para /home"
          echo -e "  lvcreate -L 10G -n home VolGroup00"
          echo -e "  # 2. Formatear"
          echo -e "  mkfs.ext4 /dev/VolGroup00/home"
          echo -e "  # 3. Montar temporal y copiar datos"
          echo -e "  mkdir /mnt/new_home"
          echo -e "  mount /dev/VolGroup00/home /mnt/new_home"
          echo -e "  cp -a /home/* /mnt/new_home/"
          echo -e "  # 4. Reemplazar montaje"
          echo -e "  umount /home"
          echo -e "  mount /dev/VolGroup00/home /home"
          echo -e "  # 5. Persistencia en /etc/fstab"
          echo -e "  echo '/dev/VolGroup00/home /home ext4 defaults,noexec,nosuid,nodev 0 2' >> /etc/fstab"
          ;;
        "/opt")
          echo -e "\n${GREEN}Ejemplo para crear /opt como particion separada:${NC}"
          echo -e "  # 1. Crear volumen logico de 5GB para /opt"
          echo -e "  lvcreate -L 5G -n opt VolGroup00"
          echo -e "  # 2. Formatear"
          echo -e "  mkfs.ext4 /dev/VolGroup00/opt"
          echo -e "  # 3. Montar temporal y copiar datos"
          echo -e "  mkdir /mnt/new_opt"
          echo -e "  mount /dev/VolGroup00/opt /mnt/new_opt"
          echo -e "  cp -a /opt/* /mnt/new_opt/"
          echo -e "  # 4. Reemplazar montaje"
          echo -e "  umount /opt"
          echo -e "  mount /dev/VolGroup00/opt /opt"
          echo -e "  # 5. Persistencia en /etc/fstab"
          echo -e "  echo '/dev/VolGroup00/opt /opt ext4 defaults,nosuid,nodev 0 2' >> /etc/fstab"
          ;;
        "/tmp")
          echo -e "\n${GREEN}Ejemplo para crear /tmp como particion separada:${NC}"
          echo -e "  # 1. Crear volumen logico de 2GB para /tmp"
          echo -e "  lvcreate -L 2G -n tmp VolGroup00"
          echo -e "  # 2. Formatear"
          echo -e "  mkfs.ext4 /dev/VolGroup00/tmp"
          echo -e "  # 3. Montar temporal y copiar datos"
          echo -e "  mkdir /mnt/new_tmp"
          echo -e "  mount /dev/VolGroup00/tmp /mnt/new_tmp"
          echo -e "  cp -a /tmp/* /mnt/new_tmp/"
          echo -e "  # 4. Reemplazar montaje"
          echo -e "  umount /tmp"
          echo -e "  mount /dev/VolGroup00/tmp /tmp"
          echo -e "  # 5. Persistencia en /etc/fstab"
          echo -e "  echo '/dev/VolGroup00/tmp /tmp ext4 defaults,noexec,nosuid,nodev 0 0' >> /etc/fstab"
          ;;
        "/var")
          echo -e "\n${GREEN}Ejemplo para crear /var como particion separada:${NC}"
          echo -e "  # 1. Crear volumen logico de 5GB para /var"
          echo -e "  lvcreate -L 5G -n var VolGroup00"
          echo -e "  # 2. Formatear"
          echo -e "  mkfs.ext4 /dev/VolGroup00/var"
          echo -e "  # 3. Montar temporal y copiar datos (modo single user recomendado)"
          echo -e "  mkdir /mnt/new_var"
          echo -e "  mount /dev/VolGroup00/var /mnt/new_var"
          echo -e "  cp -a /var/* /mnt/new_var/"
          echo -e "  # 4. Reemplazar montaje"
          echo -e "  umount /var"
          echo -e "  mount /dev/VolGroup00/var /var"
          echo -e "  # 5. Persistencia en /etc/fstab"
          echo -e "  echo '/dev/VolGroup00/var /var ext4 defaults,noexec,nosuid,nodev 0 2' >> /etc/fstab"
          ;;
        "/boot")
          echo -e "\n${GREEN}Ejemplo para crear /boot como particion separada:${NC}"
          echo -e "  # NOTA: /boot debe crearse ANTES de la instalacion"
          echo -e "  # No se puede crear facilmente en un sistema existente"
          echo -e "  # Se recomienda reinstalar con particion /boot separada"
          ;;
        esac
      done
      echo -e "\n${YELLOW}⚠️  NOTA: Realice backup antes de modificar particiones!${NC}"
      echo -e "${YELLOW}⚠️  Para /var se recomienda hacerlo en modo single user (systemctl rescue)${NC}"
      echo -e "${YELLOW}⚠️  /boot no se puede crear facilmente en un sistema existente${NC}"
    else
      echo -e "\n${RED}════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED} 🚨 RECOMENDACION IMPORTANTE - REINSTALACION NECESARIA 🚨${NC}"
      echo -e "${RED}════════════════════════════════════════════════════════════════════${NC}"
      echo -e "${RED}El sistema NO usa LVM. Para cumplir con CIS Benchmark,${NC}"
      echo -e "${RED}es necesario REINSTALAR el sistema con las siguientes particiones separadas:${NC}"
      echo -e ""
      echo -e "${GREEN}┌─────────────────┬───────────────┬────────────────────────────────────┐${NC}"
      echo -e "${GREEN}│ Particion       │ Tamaño minimo │ Opciones de montaje                │${NC}"
      echo -e "${GREEN}├─────────────────┼───────────────┼────────────────────────────────────┤${NC}"
      echo -e "│ /boot           │ 1GB           │ defaults,nodev,nosuid,noexec        │"
      echo -e "│ /home           │ 5GB+          │ defaults,noexec,nosuid,nodev        │"
      echo -e "│ /tmp            │ 2GB           │ defaults,noexec,nosuid,nodev        │"
      echo -e "│ /var            │ 5GB           │ defaults,noexec,nosuid,nodev        │"
      echo -e "│ /var/log        │ 2GB           │ defaults,noexec,nosuid,nodev        │"
      echo -e "│ /var/log/audit  │ 1GB           │ defaults,noexec,nosuid,nodev        │"
      echo -e "│ /var/tmp        │ 1GB           │ defaults,noexec,nosuid,nodev        │"
      echo -e "│ /opt            │ 2GB           │ defaults,nosuid,nodev               │"
      echo -e "${GREEN}└─────────────────┴───────────────┴────────────────────────────────────┘${NC}"
      echo -e ""
      echo -e "${YELLOW}Ejemplo de esquema de particionado para instalacion:${NC}"
      echo -e "  sda1 (1GB)  → /boot"
      echo -e "  sda2 (20GB) → / (root)"
      echo -e "  sda3 (10GB) → /home"
      echo -e "  sda4 (5GB)  → /var"
      echo -e "  sda5 (2GB)  → /tmp"
      echo -e "  sda6 (2GB)  → /opt"
    fi

    WARNINGS=$((WARNINGS + ${#missing_separated[@]}))
  else
    echo -e "\n${GREEN}[✓] EXCELENTE: Todas las particiones criticas estan separadas${NC}"
  fi

  echo ""
  # Retornar lista de particiones existentes para procesar
  echo "${existing_separated[@]}"
}

# ==============================================
# FUNCION PARA VERIFICAR OPCIONES DE MONTAJE
# ==============================================
check_mount_options() {
  local mount_point="$1"
  local required_opts="$2"

  echo -e "\n${BLUE}[*] Verificando opciones de montaje de ${mount_point}...${NC}"

  if ! findmnt -n "$mount_point" &>/dev/null; then
    echo -e "${YELLOW}[!] ${mount_point} no esta montado o no existe${NC}"
    return 1
  fi

  local current_opts=$(findmnt -n -o OPTIONS "$mount_point" 2>/dev/null | tr ',' '\n' | sort | uniq | tr '\n' ',' | sed 's/,$//')
  local current_opts_raw="$current_opts"

  # Separar opciones requeridas
  IFS=',' read -ra required_array <<<"$required_opts"

  # Verificar opciones faltantes
  local missing_opts=""
  for opt in "${required_array[@]}"; do
    if [[ ! "$current_opts_raw" == *"$opt"* ]]; then
      missing_opts="$missing_opts,$opt"
    fi
  done

  missing_opts="${missing_opts#,}"

  if [ -z "$missing_opts" ]; then
    echo -e "${GREEN}[✓] ${mount_point} tiene todas las opciones requeridas${NC}"
    echo -e "    Opciones actuales: ${current_opts_raw}"
    return 0
  fi

  echo -e "${RED}[!] ${mount_point} falta opciones: ${missing_opts}${NC}"
  echo -e "    Opciones actuales: ${current_opts_raw}"
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
    # Construir nuevas opciones
    local new_opts="$current_opts_raw"
    for opt in "${required_array[@]}"; do
      if [[ ! "$new_opts" == *"$opt"* ]]; then
        if [ -z "$new_opts" ]; then
          new_opts="$opt"
        else
          new_opts="$new_opts,$opt"
        fi
      fi
    done

    echo -e "${YELLOW}[*] Aplicando nuevas opciones a ${mount_point}...${NC}"

    # Remontar con nuevas opciones
    if mount -o remount,"$new_opts" "$mount_point" 2>/dev/null; then
      echo -e "${GREEN}[✓] ${mount_point} remontado con exito${NC}"

      # Verificar nuevas opciones
      local final_opts=$(findmnt -n -o OPTIONS "$mount_point" 2>/dev/null)
      echo -e "    Nuevas opciones: ${final_opts}"

      # Actualizar /etc/fstab si existe entrada
      if grep -q "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab 2>/dev/null; then
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d-%H%M%S)

        local fstab_opts=$(grep "^[^#].*[[:space:]]${mount_point}[[:space:]]" /etc/fstab | head -1 | awk '{print $4}')
        local fstab_new_opts="defaults"
        for opt in "${required_array[@]}"; do
          fstab_new_opts="$fstab_new_opts,$opt"
        done
        fstab_new_opts=$(echo "$fstab_new_opts" | sed 's/^defaults,defaults/defaults/')

        sed -i "s|\(.*[[:space:]]${mount_point}[[:space:]].*\)${fstab_opts}|\1${fstab_new_opts}|" /etc/fstab
        echo -e "${GREEN}[✓] /etc/fstab actualizado: ${fstab_new_opts}${NC}"
      else
        echo -e "${YELLOW}[!] No se encontro entrada en /etc/fstab para ${mount_point}${NC}"
        local source=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null)
        local fstype=$(findmnt -n -o FSTYPE "$mount_point" 2>/dev/null)
        local fstab_new_opts="defaults"
        for opt in "${required_array[@]}"; do
          fstab_new_opts="$fstab_new_opts,$opt"
        done
        echo -e "${BLUE}    Para persistencia, agregue:${NC}"
        echo -e "${BLUE}    ${source} ${mount_point} ${fstype} ${fstab_new_opts} 0 0${NC}"
      fi
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] Error al remontar ${mount_point}${NC}"
      echo -e "${YELLOW}    Puede intentar manualmente: mount -o remount,${new_opts} ${mount_point}${NC}"
    fi
  else
    echo -e "${YELLOW}[!] Omitiendo correccion para ${mount_point}${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# DESHABILITAR SISTEMAS DE ARCHIVOS NO USADOS
# ==============================================
disable_modules() {
  local CONF_FILE="/etc/modprobe.d/99-CIS-hardening.conf"

  echo -e "\n${BLUE}[*] Deshabilitando sistemas de archivos no usados...${NC}"

  if [ ! -f "$CONF_FILE" ]; then
    echo "# CIS Hardening - Filesystem modules" >"$CONF_FILE"
    echo "# Fecha: $(date)" >>"$CONF_FILE"
    echo "" >>"$CONF_FILE"
  fi

  MODULES="cramfs squashfs udf freevxfs jffs2 hfs hfsplus"

  for module in $MODULES; do
    if grep -q "install $module /bin/true" "$CONF_FILE" 2>/dev/null; then
      echo -e "${GREEN}[✓] $module ya estaba deshabilitado${NC}"
      continue
    fi

    if lsmod | grep -q "^$module"; then
      echo -e "${YELLOW}[*] $module esta cargado, descargando...${NC}"
      rmmod "$module" 2>/dev/null
    fi

    echo "# Deshabilitar $module por seguridad" >>"$CONF_FILE"
    echo "install $module /bin/true" >>"$CONF_FILE"
    echo "" >>"$CONF_FILE"

    echo -e "${GREEN}[✓] $module deshabilitado${NC}"
    FIXED=$((FIXED + 1))
  done
}

# ==============================================
# APLICAR STICKY BIT
# ==============================================
apply_sticky_bit() {
  echo -e "\n${BLUE}[*] Verificando sticky bit en directorios world-writable...${NC}"

  local sticky_issues=$(df --local -P 2>/dev/null | awk '{if (NR!=1) print $6}' | xargs -I '{}' find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null)

  if [ -z "$sticky_issues" ]; then
    echo -e "${GREEN}[✓] Todos los directorios world-writable tienen sticky bit${NC}"
    return 0
  fi

  echo -e "${RED}[!] Directorios sin sticky bit encontrados:${NC}"
  echo "$sticky_issues"

  local apply_fix=false

  if [ "$AUTO_FIX" = true ]; then
    apply_fix=true
  else
    echo -e "${YELLOW}¿Desea aplicar sticky bit a estos directorios? (s/n)${NC}"
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
      echo -e "${YELLOW}[!] Omitiendo deshabilitacion de autofs${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# CONFIGURAR /DEV/SHM (SIEMPRE PRESENTE)
# ==============================================
configure_dev_shm() {
  echo -e "\n${BLUE}[*] Configurando /dev/shm con opciones seguras...${NC}"

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
  echo -e "    Actual: $current_opts"
  echo -e "    Requerido: $required_opts"

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
    echo -e "${YELLOW}[!] Omitiendo correccion para /dev/shm${NC}"
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
  local required_opts="hidepid=2"

  if [[ "$current_opts" == *"hidepid=2"* ]]; then
    echo -e "${GREEN}[✓] /proc ya tiene hidepid=2 configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] /proc no tiene hidepid=2 (permite ver procesos de otros usuarios)${NC}"
  echo -e "    Actual: $current_opts"
  echo -e "    Requerido: $required_opts"

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
    echo -e "${YELLOW}[!] Omitiendo correccion para /proc${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# MOSTRAR RESUMEN FINAL
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  FILESYSTEM HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  echo -e "\n${YELLOW}VERIFICAR PARTICIONES SEPARADAS:${NC}"
  echo -e "  lsblk"
  echo -e "  findmnt /opt /var /tmp /boot /home /var/log"

  echo -e "\n${YELLOW}VERIFICAR OPCIONES DE MONTAJE ACTUALES:${NC}"
  echo -e "  findmnt /opt /var /tmp /boot /home /var/log /var/tmp /dev/shm /proc"

  echo -e "\n${YELLOW}VERIFICAR FSTAB:${NC}"
  echo -e "  grep -E '(/opt|/var|/tmp|/boot|/home|/var/log|/dev/shm|/proc)' /etc/fstab"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Hardening de Filesystem - CIS Benchmark${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  echo -e "${YELLOW}Este script verificara:${NC}"
  echo -e "  1. Que existan particiones separadas para directorios criticos"
  echo -e "  2. Las opciones de montaje de cada particion existente"
  echo -e "  3. Aplicara correcciones si es necesario"
  echo -e ""
  echo -e "${BLUE}Directorios que DEBEN estar en particiones separadas:${NC}"
  echo -e "  • /opt        -> nosuid,nodev"
  echo -e "  • /var        -> noexec,nosuid,nodev"
  echo -e "  • /tmp        -> noexec,nosuid,nodev"
  echo -e "  • /boot       -> nodev,nosuid,noexec"
  echo -e "  • /home       -> noexec,nosuid,nodev"
  echo -e "  • /var/log    -> noexec,nosuid,nodev"
  echo -e ""
  echo -e "${BLUE}Directorios adicionales (si existen):${NC}"
  echo -e "  • /var/tmp    -> noexec,nosuid,nodev"
  echo -e "  • /var/ossec  -> nosuid,nodev"
  echo -e "  • /dev/shm    -> noexec,nosuid,nodev"
  echo -e "  • /proc       -> hidepid=2"
  echo -e ""

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    echo -e "${YELLOW}[!] Modo automatico: aplicando correcciones sin preguntar${NC}"
    echo -e "${YELLOW}[!] 5 segundos para cancelar (Ctrl+C)...${NC}"
    sleep 5
  else
    echo -e "${YELLOW}[!] Modo interactivo: se preguntara antes de cada cambio${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para modo automatico${NC}\n"
  fi

  # 1. Verificar particiones separadas
  check_separated_partitions

  # 2. Verificar opciones de montaje para cada punto de montaje existente
  for mount_point in /opt /var /tmp /boot /home /var/log /var/tmp /var/ossec; do
    if findmnt -n "$mount_point" &>/dev/null; then
      required_opts="${MOUNT_REQUIREMENTS[$mount_point]}"
      if [ -n "$required_opts" ]; then
        check_mount_options "$mount_point" "$required_opts"
      fi
    fi
  done

  # 3. Configurar puntos de montaje especiales
  configure_dev_shm
  configure_proc

  # 4. Otras configuraciones
  disable_modules
  apply_sticky_bit
  disable_autofs

  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
