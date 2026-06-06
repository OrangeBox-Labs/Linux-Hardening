#!/bin/bash

# ==============================================
# Script: fix_filesystems.sh
# Descripción: Verifica y corrige los controles CIS:
#              1.1.1.1 - Disable cramfs
#              1.1.1.2 - Disable squashfs
#              1.1.1.3 - Disable udf
#              1.1.8  - Separate partition for /var (WARNING)
#              1.1.10 - Separate partition for /tmp (WARNING)
#              1.1.13 - Separate partition for /home (WARNING)
#              1.1.14 - /dev/shm with noexec,nodev,nosuid
#              1.1.15 - /proc with nodev,noexec,nosuid (hidepid)
# ==============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Contador de correcciones
FIXED=0

# Lista de módulos a verificar (nombre, CIS_ID)
MODULES=(
  "cramfs:1.1.1.1"
  "squashfs:1.1.1.2"
  "udf:1.1.1.3"
)

# Lista de montajes a verificar (punto_montaje, CIS_ID, opciones_requeridas)
MOUNTS=(
  "/tmp:1.1.10:noexec,nodev,nosuid"
  "/dev/shm:1.1.14:noexec,nodev,nosuid"
  "/home:1.1.13:nodev,nosuid"
  "/var:1.1.8:nodev"
)

# ==============================================
# Función para verificar y corregir un módulo
# ==============================================
check_and_fix_module() {
  local MODULE=$1
  local CIS_ID=$2
  local CONF_FILE="/etc/modprobe.d/${MODULE}.conf"

  echo -e "\n${YELLOW}[*] CIS $CIS_ID - Verificando módulo: $MODULE${NC}"

  # Verificar si el módulo está cargado
  if lsmod | grep -q "^$MODULE"; then
    echo -e "${RED}[!] Módulo $MODULE está CARGADO${NC}"
    NEED_FIX=1
  else
    echo -e "${GREEN}[✓] Módulo $MODULE no está cargado${NC}"
    NEED_FIX=0
  fi

  # Verificar si está bloqueado por modprobe.d
  if modprobe -n -v "$MODULE" 2>/dev/null | grep -q "install /bin/true"; then
    echo -e "${GREEN}[✓] $MODULE está correctamente deshabilitado (install /bin/true)${NC}"
    NEED_FIX=0
  elif modprobe -n -v "$MODULE" 2>/dev/null | grep -q "Module $MODULE not found"; then
    echo -e "${GREEN}[✓] $MODULE no encontrado (no está disponible en el kernel)${NC}"
    NEED_FIX=0
  else
    echo -e "${RED}[!] $MODULE NO está deshabilitado correctamente${NC}"
    NEED_FIX=1
  fi

  # Si necesita corrección
  if [ $NEED_FIX -eq 1 ]; then
    if [ "$AUTO_FIX" = true ]; then
      fix_module "$MODULE" "$CONF_FILE"
    else
      PENDING_FIX=true
    fi
  fi
}

# ==============================================
# Función para corregir un módulo
# ==============================================
fix_module() {
  local MODULE=$1
  local CONF_FILE=$2

  echo -e "${YELLOW}[*] Corrigiendo $MODULE...${NC}"

  # Crear o actualizar archivo de configuración
  if [ ! -f "$CONF_FILE" ]; then
    echo -e "${YELLOW}[*] Creando $CONF_FILE...${NC}"
    echo "# Deshabilitar $MODULE por seguridad (CIS)" >"$CONF_FILE"
    echo "install $MODULE /bin/true" >>"$CONF_FILE"
    FIXED=$((FIXED + 1))
  else
    # Verificar si ya tiene la línea correcta
    if ! grep -q "install $MODULE /bin/true" "$CONF_FILE"; then
      echo -e "${YELLOW}[*] Agregando línea a $CONF_FILE...${NC}"
      echo "install $MODULE /bin/true" >>"$CONF_FILE"
      FIXED=$((FIXED + 1))
    fi
  fi

  # Descargar el módulo si está cargado
  if lsmod | grep -q "^$MODULE"; then
    echo -e "${YELLOW}[*] Descargando módulo $MODULE...${NC}"
    rmmod "$MODULE" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}[✓] Módulo $MODULE descargado${NC}"
    else
      echo -e "${RED}[!] No se pudo descargar $MODULE (posiblemente en uso)${NC}"
    fi
  fi

  echo -e "${GREEN}[✓] $MODULE corregido${NC}"
}

# ==============================================
# Función para verificar montajes
# ==============================================
check_mount() {
  local MOUNT_POINT=$1
  local CIS_ID=$2
  local REQUIRED_OPTS=$3

  echo -e "\n${YELLOW}[*] CIS $CIS_ID - Verificando montaje de $MOUNT_POINT${NC}"

  # Verificar si el punto de montaje existe y está montado
  if ! findmnt -n "$MOUNT_POINT" &>/dev/null; then
    echo -e "${RED}[!] ADVERTENCIA: $MOUNT_POINT NO está montado como filesystem independiente${NC}"
    echo -e "${RED}    Esto es un riesgo de seguridad.${NC}"
    echo -e "\n${YELLOW}=== RECOMENDACIÓN ===${NC}"
    echo -e "${YELLOW}Para corregir, configura una partición separada para $MOUNT_POINT en /etc/fstab${NC}"
    return 1
  fi

  # Obtener opciones de montaje
  MOUNT_OPTS=$(findmnt -n -o OPTIONS "$MOUNT_POINT" 2>/dev/null)

  # Verificar cada opción requerida
  IFS=',' read -ra OPTS_ARRAY <<<"$REQUIRED_OPTS"
  MISSING_OPTS=()

  for opt in "${OPTS_ARRAY[@]}"; do
    if [[ ! "$MOUNT_OPTS" == *"$opt"* ]]; then
      MISSING_OPTS+=("$opt")
    fi
  done

  if [ ${#MISSING_OPTS[@]} -eq 0 ]; then
    echo -e "${GREEN}[✓] $MOUNT_POINT está correctamente montado con opciones: $MOUNT_OPTS${NC}"
    return 0
  else
    echo -e "${RED}[!] $MOUNT_POINT NO tiene todas las opciones de seguridad requeridas${NC}"
    echo -e "${RED}    Opciones actuales: $MOUNT_OPTS${NC}"
    echo -e "${RED}    Opciones faltantes: ${MISSING_OPTS[*]}${NC}"
    echo -e "\n${YELLOW}=== RECOMENDACIÓN ===${NC}"
    echo -e "${YELLOW}Ejecuta: mount -o remount,${REQUIRED_OPTS} $MOUNT_POINT${NC}"
    return 1
  fi
}

# ==============================================
# Función para verificar /proc (montaje especial)
# ==============================================
check_proc_mount() {
  echo -e "\n${YELLOW}[*] CIS 1.1.15 - Verificando montaje de /proc${NC}"

  if ! findmnt -n /proc &>/dev/null; then
    echo -e "${RED}[!] ADVERTENCIA: /proc NO está montado correctamente${NC}"
    return 1
  fi

  MOUNT_OPTS=$(findmnt -n -o OPTIONS /proc 2>/dev/null)

  if [[ "$MOUNT_OPTS" == *"nodev"* ]] && [[ "$MOUNT_OPTS" == *"noexec"* ]] && [[ "$MOUNT_OPTS" == *"nosuid"* ]] && [[ "$MOUNT_OPTS" == *"hidepid=2"* ]]; then
    echo -e "${GREEN}[✓] /proc está correctamente montado con nodev,noexec,nosuid,hidepid=2${NC}"
    return 0
  else
    echo -e "${RED}[!] /proc NO tiene todas las opciones de seguridad requeridas${NC}"
    echo -e "${RED}    Opciones actuales: $MOUNT_OPTS${NC}"
    echo -e "${RED}    Requerido: nodev,noexec,nosuid,hidepid=2${NC}"
    echo -e "\n${YELLOW}=== RECOMENDACIÓN ===${NC}"
    echo -e "${YELLOW}Edita /etc/fstab y agrega: proc /proc proc defaults,hidepid=2 0 0${NC}"
    echo -e "${YELLOW}Luego ejecuta: mount -o remount,nodev,noexec,nosuid,hidepid=2 /proc${NC}"
    return 1
  fi
}

# ==============================================
# Función para aplicar todas las correcciones
# ==============================================
apply_fixes() {
  echo -e "\n${YELLOW}[*] Aplicando correcciones de módulos...${NC}"
  for module_entry in "${MODULES[@]}"; do
    MODULE="${module_entry%%:*}"
    CONF_FILE="/etc/modprobe.d/${MODULE}.conf"
    fix_module "$MODULE" "$CONF_FILE"
  done
}

# ==============================================
# Función principal
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  CIS Benchmark 1.1.x - Filesystems & Mounts${NC}"
  echo -e "${GREEN}============================================${NC}"

  # Verificar si es modo automático
  AUTO_FIX=false
  PENDING_FIX=false

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    echo -e "${YELLOW}[!] Modo automático: se aplicarán correcciones sin preguntar${NC}"
  fi

  # Verificar módulos
  for module_entry in "${MODULES[@]}"; do
    MODULE="${module_entry%%:*}"
    CIS_ID="${module_entry##*:}"
    check_and_fix_module "$MODULE" "$CIS_ID"
  done

  # Verificar montajes
  for mount_entry in "${MOUNTS[@]}"; do
    MOUNT_POINT="${mount_entry%%:*}"
    CIS_ID=$(echo "$mount_entry" | cut -d':' -f2)
    REQUIRED_OPTS=$(echo "$mount_entry" | cut -d':' -f3)
    check_mount "$MOUNT_POINT" "$CIS_ID" "$REQUIRED_OPTS"
  done

  # Verificar /proc (caso especial)
  check_proc_mount

  # Si hay correcciones pendientes y no es modo automático, preguntar
  if [ "$PENDING_FIX" = true ] && [ "$AUTO_FIX" = false ]; then
    echo -e "\n${YELLOW}[!] Se requiere corrección para algunos módulos${NC}"
    read -p "¿Deseas aplicar las correcciones? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
      AUTO_FIX=true
      apply_fixes
    else
      echo -e "${YELLOW}[!] Corrección cancelada por el usuario${NC}"
      exit 1
    fi
  elif [ "$PENDING_FIX" = true ] && [ "$AUTO_FIX" = true ]; then
    apply_fixes
  fi

  # Resumen final
  echo -e "\n${GREEN}============================================${NC}"
  if [ $FIXED -eq 0 ] && [ "$PENDING_FIX" = false ]; then
    echo -e "${GREEN}[✓] El sistema ya cumple con los controles de módulos${NC}"
  elif [ $FIXED -gt 0 ]; then
    echo -e "${GREEN}[✓] Se corrigieron $FIXED módulo(s)${NC}"
    echo -e "${YELLOW}[!] Se recomienda reiniciar el sistema para asegurar los cambios${NC}"
  fi
  echo -e "${GREEN}============================================${NC}"
}

# Ejecutar como root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
