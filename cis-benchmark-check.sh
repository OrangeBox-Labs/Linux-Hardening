#!/bin/bash

# ==============================================
# Script: cis-benchmark-check.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Verificador de cumplimiento CIS Benchmark
#              Para RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10
#              Los tests en WARN o FAIL incluyen recomendaciones de mitigación
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_FILE="reporte_orangebox_cis_benchmark.log"
TOTAL_TESTS=0
PASSED=0
FAILED=0
WARN=0

# ==============================================
# FUNCION PARA ESCRIBIR EN REPORTE Y PANTALLA
# ==============================================
log_result() {
  local status="$1"
  local title="$2"
  local details="$3"
  local mitigation="$4"
  local color="$5"

  echo -e "${color}[${status}]${NC} ${title}"
  if [ -n "$details" ]; then
    echo -e "  ${details}"
  fi
  if [ "$status" = "FAIL" ] || [ "$status" = "WARN" ]; then
    if [ -n "$mitigation" ]; then
      echo -e "  ${BLUE}🔧 Mitigacion:${NC} ${mitigation}"
    fi
  fi
  echo "[${status}] ${title}" >>"$REPORT_FILE"
  if [ -n "$details" ]; then
    echo "  ${details}" >>"$REPORT_FILE"
  fi
  if [ "$status" = "FAIL" ] || [ "$status" = "WARN" ]; then
    if [ -n "$mitigation" ]; then
      echo "  Mitigacion: ${mitigation}" >>"$REPORT_FILE"
    fi
  fi
}

# ==============================================
# FUNCION PARA EJECUTAR UN TEST
# ==============================================
run_test() {
  local test_name="$1"
  local test_func="$2"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo -e "\n${BLUE}[*]${NC} Test: ${test_name}" | tee -a "$REPORT_FILE"

  if $test_func; then
    PASSED=$((PASSED + 1))
    return 0
  else
    local exit_code=$?
    if [ $exit_code -eq 2 ]; then
      WARN=$((WARN + 1))
    else
      FAILED=$((FAILED + 1))
    fi
    return 1
  fi
}

# ==============================================
# 1.1.1.1 - DESHABILITAR SQUASHFS
# ==============================================
check_squashfs() {
  if modprobe -n -v squashfs 2>&1 | grep -q "install /bin/false\|not found"; then
    if ! lsmod | grep -q "^squashfs"; then
      log_result "PASS" "1.1.1.1 - Deshabilitar montaje de sistemas de archivos squashfs" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.1.1.1 - Deshabilitar montaje de sistemas de archivos squashfs" "El modulo squashfs esta habilitado" "Crear archivo /etc/modprobe.d/squashfs.conf con: install squashfs /bin/false y blacklist squashfs. Luego ejecutar: rmmod squashfs" "$RED"
  return 1
}

# ==============================================
# 1.1.1.2 - DESHABILITAR UDF
# ==============================================
check_udf() {
  if modprobe -n -v udf 2>&1 | grep -q "install /bin/false\|not found"; then
    if ! lsmod | grep -q "^udf"; then
      log_result "PASS" "1.1.1.2 - Deshabilitar montaje de sistemas de archivos udf" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.1.1.2 - Deshabilitar montaje de sistemas de archivos udf" "El modulo udf esta habilitado" "Crear archivo /etc/modprobe.d/udf.conf con: install udf /bin/false y blacklist udf. Luego ejecutar: rmmod udf" "$RED"
  return 1
}

# ==============================================
# 1.1.2.1 - ASEGURAR PARTICION SEPARADA PARA /tmp
# ==============================================
check_tmp_partition() {
  if findmnt --kernel /tmp &>/dev/null; then
    log_result "PASS" "1.1.2.1 - Asegurar que /tmp es una particion separada" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.1 - Asegurar que /tmp es una particion separada" "/tmp no es una particion separada" "Durante la instalacion, crear una particion separada para /tmp. En sistemas existentes, usar LVM para crear un volumen para /tmp y mover los datos" "$RED"
  return 1
}

# ==============================================
# 1.1.2.2 - OPCION NODEV EN /tmp
# ==============================================
check_tmp_nodev() {
  if findmnt --kernel /tmp | grep -q "nodev"; then
    log_result "PASS" "1.1.2.2 - Asegurar opcion nodev en particion /tmp" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.2 - Asegurar opcion nodev en particion /tmp" "nodev no esta configurado en /tmp" "Editar /etc/fstab y agregar nodev a las opciones de montaje de /tmp. Ejecutar: mount -o remount,nodev /tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.2.3 - OPCION NOEXEC EN /tmp
# ==============================================
check_tmp_noexec() {
  if findmnt --kernel /tmp | grep -q "noexec"; then
    log_result "PASS" "1.1.2.3 - Asegurar opcion noexec en particion /tmp" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.3 - Asegurar opcion noexec en particion /tmp" "noexec no esta configurado en /tmp" "Editar /etc/fstab y agregar noexec a las opciones de montaje de /tmp. Ejecutar: mount -o remount,noexec /tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.2.4 - OPCION NOSUID EN /tmp
# ==============================================
check_tmp_nosuid() {
  if findmnt --kernel /tmp | grep -q "nosuid"; then
    log_result "PASS" "1.1.2.4 - Asegurar opcion nosuid en particion /tmp" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.4 - Asegurar opcion nosuid en particion /tmp" "nosuid no esta configurado en /tmp" "Editar /etc/fstab y agregar nosuid a las opciones de montaje de /tmp. Ejecutar: mount -o remount,nosuid /tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.3.1 - ASEGURAR PARTICION SEPARADA PARA /var
# ==============================================
check_var_partition() {
  if findmnt --kernel /var &>/dev/null; then
    log_result "PASS" "1.1.3.1 - Asegurar particion separada para /var" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.3.1 - Asegurar particion separada para /var" "/var no es una particion separada" "Durante la instalacion, crear una particion separada para /var. En sistemas existentes con LVM, crear un volumen para /var y migrar los datos" "$RED"
  return 1
}

# ==============================================
# 1.1.3.2 - OPCION NODEV EN /var
# ==============================================
check_var_nodev() {
  if findmnt --kernel /var | grep -q "nodev"; then
    log_result "PASS" "1.1.3.2 - Asegurar opcion nodev en particion /var" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.3.2 - Asegurar opcion nodev en particion /var" "nodev no esta configurado en /var" "Editar /etc/fstab y agregar nodev a las opciones de montaje de /var. Ejecutar: mount -o remount,nodev /var" "$RED"
  return 1
}

# ==============================================
# 1.1.3.3 - OPCION NOSUID EN /var
# ==============================================
check_var_nosuid() {
  if findmnt --kernel /var | grep -q "nosuid"; then
    log_result "PASS" "1.1.3.3 - Asegurar opcion nosuid en particion /var" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.3.3 - Asegurar opcion nosuid en particion /var" "nosuid no esta configurado en /var" "Editar /etc/fstab y agregar nosuid a las opciones de montaje de /var. Ejecutar: mount -o remount,nosuid /var" "$RED"
  return 1
}

# ==============================================
# 1.1.4.1 - ASEGURAR PARTICION SEPARADA PARA /var/tmp
# ==============================================
check_var_tmp_partition() {
  if findmnt --kernel /var/tmp &>/dev/null; then
    log_result "PASS" "1.1.4.1 - Asegurar particion separada para /var/tmp" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.1 - Asegurar particion separada para /var/tmp" "/var/tmp no es una particion separada" "Crear particion separada para /var/tmp. En sistemas con LVM, crear volumen y configurar en /etc/fstab" "$RED"
  return 1
}

# ==============================================
# 1.1.4.2 - OPCION NOEXEC EN /var/tmp
# ==============================================
check_var_tmp_noexec() {
  if findmnt --kernel /var/tmp | grep -q "noexec"; then
    log_result "PASS" "1.1.4.2 - Asegurar opcion noexec en particion /var/tmp" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.2 - Asegurar opcion noexec en particion /var/tmp" "noexec no esta configurado en /var/tmp" "Editar /etc/fstab y agregar noexec a las opciones de montaje de /var/tmp. Ejecutar: mount -o remount,noexec /var/tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.4.3 - OPCION NOSUID EN /var/tmp
# ==============================================
check_var_tmp_nosuid() {
  if findmnt --kernel /var/tmp | grep -q "nosuid"; then
    log_result "PASS" "1.1.4.3 - Asegurar opcion nosuid en particion /var/tmp" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.3 - Asegurar opcion nosuid en particion /var/tmp" "nosuid no esta configurado en /var/tmp" "Editar /etc/fstab y agregar nosuid a las opciones de montaje de /var/tmp. Ejecutar: mount -o remount,nosuid /var/tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.4.4 - OPCION NODEV EN /var/tmp
# ==============================================
check_var_tmp_nodev() {
  if findmnt --kernel /var/tmp | grep -q "nodev"; then
    log_result "PASS" "1.1.4.4 - Asegurar opcion nodev en particion /var/tmp" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.4 - Asegurar opcion nodev en particion /var/tmp" "nodev no esta configurado en /var/tmp" "Editar /etc/fstab y agregar nodev a las opciones de montaje de /var/tmp. Ejecutar: mount -o remount,nodev /var/tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.5.1 - ASEGURAR PARTICION SEPARADA PARA /var/log
# ==============================================
check_var_log_partition() {
  if findmnt --kernel /var/log &>/dev/null; then
    log_result "PASS" "1.1.5.1 - Asegurar particion separada para /var/log" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.1 - Asegurar particion separada para /var/log" "/var/log no es una particion separada" "Crear particion separada para /var/log. Los logs pueden llenar la particion root si no estan separados" "$RED"
  return 1
}

# ==============================================
# 1.1.5.2 - OPCION NODEV EN /var/log
# ==============================================
check_var_log_nodev() {
  if findmnt --kernel /var/log | grep -q "nodev"; then
    log_result "PASS" "1.1.5.2 - Asegurar opcion nodev en particion /var/log" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.2 - Asegurar opcion nodev en particion /var/log" "nodev no esta configurado en /var/log" "Editar /etc/fstab y agregar nodev a las opciones de montaje de /var/log. Ejecutar: mount -o remount,nodev /var/log" "$RED"
  return 1
}

# ==============================================
# 1.1.5.3 - OPCION NOEXEC EN /var/log
# ==============================================
check_var_log_noexec() {
  if findmnt --kernel /var/log | grep -q "noexec"; then
    log_result "PASS" "1.1.5.3 - Asegurar opcion noexec en particion /var/log" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.3 - Asegurar opcion noexec en particion /var/log" "noexec no esta configurado en /var/log" "Editar /etc/fstab y agregar noexec a las opciones de montaje de /var/log. Ejecutar: mount -o remount,noexec /var/log" "$RED"
  return 1
}

# ==============================================
# 1.1.5.4 - OPCION NOSUID EN /var/log
# ==============================================
check_var_log_nosuid() {
  if findmnt --kernel /var/log | grep -q "nosuid"; then
    log_result "PASS" "1.1.5.4 - Asegurar opcion nosuid en particion /var/log" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.4 - Asegurar opcion nosuid en particion /var/log" "nosuid no esta configurado en /var/log" "Editar /etc/fstab y agregar nosuid a las opciones de montaje de /var/log. Ejecutar: mount -o remount,nosuid /var/log" "$RED"
  return 1
}

# ==============================================
# 1.1.6.1 - ASEGURAR PARTICION SEPARADA PARA /var/log/audit
# ==============================================
check_var_log_audit_partition() {
  if findmnt --kernel /var/log/audit &>/dev/null; then
    log_result "PASS" "1.1.6.1 - Asegurar particion separada para /var/log/audit" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.1 - Asegurar particion separada para /var/log/audit" "/var/log/audit no es una particion separada" "Los logs de auditoria pueden crecer rapidamente. Crear particion separada para /var/log/audit" "$RED"
  return 1
}

# ==============================================
# 1.1.6.2 - OPCION NOEXEC EN /var/log/audit
# ==============================================
check_var_log_audit_noexec() {
  if findmnt --kernel /var/log/audit | grep -q "noexec"; then
    log_result "PASS" "1.1.6.2 - Asegurar opcion noexec en particion /var/log/audit" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.2 - Asegurar opcion noexec en particion /var/log/audit" "noexec no esta configurado en /var/log/audit" "Editar /etc/fstab y agregar noexec. Ejecutar: mount -o remount,noexec /var/log/audit" "$RED"
  return 1
}

# ==============================================
# 1.1.6.3 - OPCION NODEV EN /var/log/audit
# ==============================================
check_var_log_audit_nodev() {
  if findmnt --kernel /var/log/audit | grep -q "nodev"; then
    log_result "PASS" "1.1.6.3 - Asegurar opcion nodev en particion /var/log/audit" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.3 - Asegurar opcion nodev en particion /var/log/audit" "nodev no esta configurado en /var/log/audit" "Editar /etc/fstab y agregar nodev. Ejecutar: mount -o remount,nodev /var/log/audit" "$RED"
  return 1
}

# ==============================================
# 1.1.6.4 - OPCION NOSUID EN /var/log/audit
# ==============================================
check_var_log_audit_nosuid() {
  if findmnt --kernel /var/log/audit | grep -q "nosuid"; then
    log_result "PASS" "1.1.6.4 - Asegurar opcion nosuid en particion /var/log/audit" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.4 - Asegurar opcion nosuid en particion /var/log/audit" "nosuid no esta configurado en /var/log/audit" "Editar /etc/fstab y agregar nosuid. Ejecutar: mount -o remount,nosuid /var/log/audit" "$RED"
  return 1
}

# ==============================================
# 1.1.7.1 - ASEGURAR PARTICION SEPARADA PARA /home
# ==============================================
check_home_partition() {
  if findmnt --kernel /home &>/dev/null; then
    log_result "PASS" "1.1.7.1 - Asegurar particion separada para /home" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.7.1 - Asegurar particion separada para /home" "/home no es una particion separada" "Los usuarios pueden llenar la particion root con datos. Crear particion separada para /home" "$RED"
  return 1
}

# ==============================================
# 1.1.7.2 - OPCION NODEV EN /home
# ==============================================
check_home_nodev() {
  if findmnt --kernel /home | grep -q "nodev"; then
    log_result "PASS" "1.1.7.2 - Asegurar opcion nodev en particion /home" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.7.2 - Asegurar opcion nodev en particion /home" "nodev no esta configurado en /home" "Editar /etc/fstab y agregar nodev. Ejecutar: mount -o remount,nodev /home" "$RED"
  return 1
}

# ==============================================
# 1.1.7.3 - OPCION NOSUID EN /home
# ==============================================
check_home_nosuid() {
  if findmnt --kernel /home | grep -q "nosuid"; then
    log_result "PASS" "1.1.7.3 - Asegurar opcion nosuid en particion /home" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.7.3 - Asegurar opcion nosuid en particion /home" "nosuid no esta configurado en /home" "Editar /etc/fstab y agregar nosuid. Ejecutar: mount -o remount,nosuid /home" "$RED"
  return 1
}

# ==============================================
# 1.1.8.1 - ASEGURAR PARTICION SEPARADA PARA /dev/shm
# ==============================================
check_dev_shm_partition() {
  if findmnt --kernel /dev/shm &>/dev/null; then
    log_result "PASS" "1.1.8.1 - Asegurar /dev/shm como particion separada" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.1 - Asegurar /dev/shm como particion separada" "/dev/shm no es una particion separada" "Agregar entrada en /etc/fstab: tmpfs /dev/shm tmpfs defaults,noexec,nodev,nosuid 0 0" "$RED"
  return 1
}

# ==============================================
# 1.1.8.2 - OPCION NODEV EN /dev/shm
# ==============================================
check_dev_shm_nodev() {
  if findmnt --kernel /dev/shm | grep -q "nodev"; then
    log_result "PASS" "1.1.8.2 - Asegurar opcion nodev en /dev/shm" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.2 - Asegurar opcion nodev en /dev/shm" "nodev no esta configurado en /dev/shm" "Remontar con: mount -o remount,nodev /dev/shm y actualizar /etc/fstab" "$RED"
  return 1
}

# ==============================================
# 1.1.8.3 - OPCION NOEXEC EN /dev/shm
# ==============================================
check_dev_shm_noexec() {
  if findmnt --kernel /dev/shm | grep -q "noexec"; then
    log_result "PASS" "1.1.8.3 - Asegurar opcion noexec en /dev/shm" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.3 - Asegurar opcion noexec en /dev/shm" "noexec no esta configurado en /dev/shm" "Remontar con: mount -o remount,noexec /dev/shm y actualizar /etc/fstab" "$RED"
  return 1
}

# ==============================================
# 1.1.8.4 - OPCION NOSUID EN /dev/shm
# ==============================================
check_dev_shm_nosuid() {
  if findmnt --kernel /dev/shm | grep -q "nosuid"; then
    log_result "PASS" "1.1.8.4 - Asegurar opcion nosuid en /dev/shm" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.4 - Asegurar opcion nosuid en /dev/shm" "nosuid no esta configurado en /dev/shm" "Remontar con: mount -o remount,nosuid /dev/shm y actualizar /etc/fstab" "$RED"
  return 1
}

# ==============================================
# 1.1.9 - DESHABILITAR USB STORAGE
# ==============================================
check_usb_storage() {
  if modprobe -n -v usb-storage 2>&1 | grep -q "install /bin/true\|not found"; then
    if ! lsmod | grep -q "^usb-storage"; then
      log_result "PASS" "1.1.9 - Deshabilitar almacenamiento USB" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.1.9 - Deshabilitar almacenamiento USB" "El modulo usb-storage esta habilitado" "Crear archivo /etc/modprobe.d/usb-storage.conf con: install usb-storage /bin/true. Luego ejecutar: rmmod usb-storage" "$RED"
  return 1
}

# ==============================================
# 1.2.2 - ASEGURAR GPGCHECK ACTIVADO GLOBALMENTE
# ==============================================
check_gpgcheck() {
  if grep -q "^gpgcheck=1" /etc/dnf/dnf.conf 2>/dev/null; then
    if ! grep -q "gpgcheck=0" /etc/yum.repos.d/*.repo 2>/dev/null; then
      log_result "PASS" "1.2.2 - Asegurar gpgcheck activado globalmente" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.2.2 - Asegurar gpgcheck activado globalmente" "gpgcheck no esta configurado correctamente" "Editar /etc/dnf/dnf.conf y establecer gpgcheck=1. En /etc/yum.repos.d/*.repo cambiar gpgcheck=0 a gpgcheck=1" "$RED"
  return 1
}

# ==============================================
# 1.3.1 - ASEGURAR AIDE INSTALADO
# ==============================================
check_aide() {
  if rpm -q aide &>/dev/null; then
    log_result "PASS" "1.3.1 - Asegurar AIDE instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.3.1 - Asegurar AIDE instalado" "AIDE no esta instalado" "Instalar AIDE: dnf install aide -y. Inicializar base de datos: aide --init y mover aide.db.new.gz a aide.db.gz" "$YELLOW"
  return 2
}

# ==============================================
# 1.3.2 - ASEGURAR VERIFICACION PERIODICA DE INTEGRIDAD
# ==============================================
check_aide_timer() {
  if systemctl is-enabled aidecheck.timer &>/dev/null; then
    log_result "PASS" "1.3.2 - Asegurar verificacion periodica de integridad" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.3.2 - Asegurar verificacion periodica de integridad" "aidecheck.timer no esta habilitado" "Crear servicio y timer de systemd para ejecutar aide --check diariamente. Habilitar con: systemctl enable aidecheck.timer" "$YELLOW"
  return 2
}

# ==============================================
# 1.4.1 - ASEGURAR CONTRASEÑA DE BOOTLOADER
# ==============================================
check_grub_password() {
  if grep -q "^password" /boot/grub2/grub.cfg 2>/dev/null || grep -q "set superusers" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "PASS" "1.4.1 - Asegurar contraseña de bootloader configurada" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.4.1 - Asegurar contraseña de bootloader configurada" "No se encontro contraseña de bootloader" "Ejecutar: grub2-setpassword para establecer contraseña de GRUB" "$YELLOW"
  return 2
}

# ==============================================
# 1.4.2 - ASEGURAR PERMISOS EN CONFIGURACION DE BOOTLOADER
# ==============================================
check_grub_permissions() {
  local perms=$(stat -c "%a" /boot/grub2/grub.cfg 2>/dev/null)
  if [ "$perms" = "600" ] || [ "$perms" = "400" ]; then
    log_result "PASS" "1.4.2 - Asegurar permisos en configuracion de bootloader" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.4.2 - Asegurar permisos en configuracion de bootloader" "Permisos de grub.cfg: $perms" "Ejecutar: chmod 600 /boot/grub2/grub.cfg y chown root:root /boot/grub2/grub.cfg" "$RED"
  return 1
}

# ==============================================
# 1.5.1 - DESHABILITAR ALMACENAMIENTO DE CORE DUMPS
# ==============================================
check_coredump_storage() {
  if grep -q "^Storage=none" /etc/systemd/coredump.conf 2>/dev/null; then
    log_result "PASS" "1.5.1 - Deshabilitar almacenamiento de core dumps" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.5.1 - Deshabilitar almacenamiento de core dumps" "Storage=none no configurado en coredump.conf" "Editar /etc/systemd/coredump.conf y agregar: Storage=none. Reiniciar: systemctl restart systemd-coredump" "$YELLOW"
  return 2
}

# ==============================================
# 1.5.2 - DESHABILITAR BACKTRACES DE CORE DUMPS
# ==============================================
check_coredump_backtraces() {
  if grep -q "^ProcessSizeMax=0" /etc/systemd/coredump.conf 2>/dev/null; then
    log_result "PASS" "1.5.2 - Deshabilitar backtraces de core dumps" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.5.2 - Deshabilitar backtraces de core dumps" "ProcessSizeMax=0 no configurado" "Editar /etc/systemd/coredump.conf y agregar: ProcessSizeMax=0. Reiniciar: systemctl restart systemd-coredump" "$YELLOW"
  return 2
}

# ==============================================
# 1.6.1.1 - ASEGURAR SELINUX INSTALADO
# ==============================================
check_selinux_installed() {
  if rpm -q libselinux &>/dev/null; then
    log_result "PASS" "1.6.1.1 - Asegurar SELinux instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.1 - Asegurar SELinux instalado" "libselinux no esta instalado" "Instalar SELinux: dnf install libselinux selinux-policy-targeted -y" "$RED"
  return 1
}

# ==============================================
# 1.6.1.2 - ASEGURAR SELINUX NO DESHABILITADO EN BOOTLOADER
# ==============================================
check_selinux_bootloader() {
  if grep -q "selinux=0" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "FAIL" "1.6.1.2 - Asegurar SELinux no deshabilitado en bootloader" "selinux=0 encontrado en grub.cfg" "Editar /boot/grub2/grub.cfg y eliminar los parametros selinux=0 o enforcing=0" "$RED"
    return 1
  fi
  log_result "PASS" "1.6.1.2 - Asegurar SELinux no deshabilitado en bootloader" "" "" "$GREEN"
  return 0
}

# ==============================================
# 1.6.1.3 - ASEGURAR POLITICA DE SELINUX CONFIGURADA
# ==============================================
check_selinux_policy() {
  if grep -q "^SELINUXTYPE=targeted" /etc/selinux/config 2>/dev/null; then
    log_result "PASS" "1.6.1.3 - Asegurar politica de SELinux configurada" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.3 - Asegurar politica de SELinux configurada" "SELINUXTYPE no es targeted" "Editar /etc/selinux/config y establecer: SELINUXTYPE=targeted. Reiniciar el sistema" "$RED"
  return 1
}

# ==============================================
# 1.6.1.4 - ASEGURAR MODO SELINUX NO DESHABILITADO
# ==============================================
check_selinux_mode() {
  local mode=$(getenforce 2>/dev/null)
  if [ "$mode" = "Enforcing" ] || [ "$mode" = "Permissive" ]; then
    log_result "PASS" "1.6.1.4 - Asegurar modo SELinux no deshabilitado" "Modo actual: $mode" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.4 - Asegurar modo SELinux no deshabilitado" "SELinux esta deshabilitado" "Editar /etc/selinux/config y establecer: SELINUX=permissive (o enforcing). Reiniciar el sistema" "$RED"
  return 1
}

# ==============================================
# 1.6.1.5 - ASEGURAR MODO SELINUX EN FORZOSO
# ==============================================
check_selinux_enforcing() {
  local mode=$(getenforce 2>/dev/null)
  if [ "$mode" = "Enforcing" ]; then
    log_result "PASS" "1.6.1.5 - Asegurar modo SELinux en forzoso" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.6.1.5 - Asegurar modo SELinux en forzoso" "Modo actual: $mode (deberia ser Enforcing)" "Cambiar a modo enforcing: setenforce 1 y editar /etc/selinux/config: SELINUX=enforcing" "$YELLOW"
  return 2
}

# ==============================================
# 1.6.1.6 - ASEGURAR NO HAY SERVICIOS SIN CONFINAR
# ==============================================
check_unconfined_services() {
  if ! ps -eZ 2>/dev/null | grep -q "unconfined_service_t"; then
    log_result "PASS" "1.6.1.6 - Asegurar no hay servicios sin confinar" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.6.1.6 - Asegurar no hay servicios sin confinar" "Se detectaron servicios sin confinar" "Investigar los procesos con contexto unconfined_service_t y crear politicas SELinux apropiadas" "$YELLOW"
  return 2
}

# ==============================================
# 1.6.1.7 - ASEGURAR SETROUBLESHOOT NO INSTALADO
# ==============================================
check_setroubleshoot() {
  if ! rpm -q setroubleshoot &>/dev/null; then
    log_result "PASS" "1.6.1.7 - Asegurar SETroubleshoot no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.7 - Asegurar SETroubleshoot no instalado" "setroubleshoot esta instalado" "Desinstalar: dnf remove setroubleshoot -y" "$RED"
  return 1
}

# ==============================================
# 1.6.1.8 - ASEGURAR MCS TRANSLATION SERVICE NO INSTALADO
# ==============================================
check_mcstrans() {
  if ! rpm -q mcstrans &>/dev/null; then
    log_result "PASS" "1.6.1.8 - Asegurar mcstrans no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.8 - Asegurar mcstrans no instalado" "mcstrans esta instalado" "Desinstalar: dnf remove mcstrans -y" "$RED"
  return 1
}

# ==============================================
# 1.7.1 - MENSAJE DEL DIA CONFIGURADO CORRECTAMENTE
# ==============================================
check_motd() {
  if [ -f /etc/motd ]; then
    if ! grep -q "\\\v\|\\\r\|\\\m\|\\\s" /etc/motd 2>/dev/null; then
      log_result "PASS" "1.7.1 - Mensaje del dia configurado correctamente" "" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "1.7.1 - Mensaje del dia configurado correctamente" "/etc/motd no existe" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.7.1 - Mensaje del dia configurado correctamente" "motd contiene informacion de version del SO" "Editar /etc/motd y eliminar referencias a \v, \r, \m, \s. Usar solo texto de advertencia" "$RED"
  return 1
}

# ==============================================
# 1.7.2 - BANNER DE LOGIN LOCAL CONFIGURADO
# ==============================================
check_issue() {
  if [ -f /etc/issue ]; then
    if ! grep -q "\\\v\|\\\r\|\\\m\|\\\s" /etc/issue 2>/dev/null; then
      log_result "PASS" "1.7.2 - Banner de login local configurado correctamente" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.2 - Banner de login local configurado correctamente" "/etc/issue contiene informacion de version del SO" "Editar /etc/issue y eliminar referencias a \v, \r, \m, \s. Usar texto de advertencia legal" "$RED"
  return 1
}

# ==============================================
# 1.7.3 - BANNER DE LOGIN REMOTO CONFIGURADO
# ==============================================
check_issue_net() {
  if [ -f /etc/issue.net ]; then
    if ! grep -q "\\\v\|\\\r\|\\\m\|\\\s" /etc/issue.net 2>/dev/null; then
      log_result "PASS" "1.7.3 - Banner de login remoto configurado correctamente" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.3 - Banner de login remoto configurado correctamente" "/etc/issue.net contiene informacion de version del SO" "Editar /etc/issue.net y eliminar referencias a \v, \r, \m, \s. Usar texto de advertencia legal" "$RED"
  return 1
}

# ==============================================
# 1.7.4 - PERMISOS EN /etc/motd
# ==============================================
check_motd_perms() {
  if [ -f /etc/motd ]; then
    local perms=$(stat -c "%a" /etc/motd 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "1.7.4 - Permisos en /etc/motd configurados" "" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "1.7.4 - Permisos en /etc/motd configurados" "/etc/motd no existe" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.7.4 - Permisos en /etc/motd configurados" "Permisos de motd: $perms" "Ejecutar: chmod 644 /etc/motd y chown root:root /etc/motd" "$RED"
  return 1
}

# ==============================================
# 1.7.5 - PERMISOS EN /etc/issue
# ==============================================
check_issue_perms() {
  if [ -f /etc/issue ]; then
    local perms=$(stat -c "%a" /etc/issue 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "1.7.5 - Permisos en /etc/issue configurados" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.5 - Permisos en /etc/issue configurados" "Permisos de issue: $perms" "Ejecutar: chmod 644 /etc/issue y chown root:root /etc/issue" "$RED"
  return 1
}

# ==============================================
# 1.7.6 - PERMISOS EN /etc/issue.net
# ==============================================
check_issue_net_perms() {
  if [ -f /etc/issue.net ]; then
    local perms=$(stat -c "%a" /etc/issue.net 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "1.7.6 - Permisos en /etc/issue.net configurados" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.6 - Permisos en /etc/issue.net configurados" "Permisos de issue.net: $perms" "Ejecutar: chmod 644 /etc/issue.net y chown root:root /etc/issue.net" "$RED"
  return 1
}

# ==============================================
# 2.1.1 - ASEGURAR SINCRONIZACION DE TIEMPO EN USO
# ==============================================
check_chrony() {
  if rpm -q chrony &>/dev/null; then
    log_result "PASS" "2.1.1 - Asegurar sincronizacion de tiempo en uso" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.1.1 - Asegurar sincronizacion de tiempo en uso" "chrony no esta instalado" "Instalar chrony: dnf install chrony -y. Configurar servidores NTP en /etc/chrony.conf. Habilitar: systemctl enable --now chronyd" "$RED"
  return 1
}

# ==============================================
# 2.2.1 - ASEGURAR X WINDOWS NO INSTALADO
# ==============================================
check_xwindow() {
  if ! rpm -q xorg-x11-server-common &>/dev/null; then
    log_result "PASS" "2.2.1 - Asegurar X Window System no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.1 - Asegurar X Window System no instalado" "Paquetes X Window estan instalados" "Desinstalar: dnf remove xorg-x11-server-common -y" "$RED"
  return 1
}

# ==============================================
# 2.2.2 - ASEGURAR AVAHI NO INSTALADO
# ==============================================
check_avahi() {
  if ! rpm -q avahi &>/dev/null; then
    log_result "PASS" "2.2.2 - Asegurar Avahi Server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.2 - Asegurar Avahi Server no instalado" "avahi esta instalado" "Desinstalar: dnf remove avahi -y" "$RED"
  return 1
}

# ==============================================
# 2.2.3 - ASEGURAR CUPS NO INSTALADO
# ==============================================
check_cups() {
  if ! rpm -q cups &>/dev/null; then
    log_result "PASS" "2.2.3 - Asegurar CUPS no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.3 - Asegurar CUPS no instalado" "cups esta instalado" "Desinstalar: dnf remove cups -y" "$RED"
  return 1
}

# ==============================================
# 2.2.4 - ASEGURAR DHCP SERVER NO INSTALADO
# ==============================================
check_dhcp() {
  if ! rpm -q dhcp-server &>/dev/null; then
    log_result "PASS" "2.2.4 - Asegurar DHCP Server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.4 - Asegurar DHCP Server no instalado" "dhcp-server esta instalado" "Desinstalar: dnf remove dhcp-server -y" "$RED"
  return 1
}

# ==============================================
# 2.2.5 - ASEGURAR DNS SERVER NO INSTALADO
# ==============================================
check_dns() {
  if ! rpm -q bind &>/dev/null; then
    log_result "PASS" "2.2.5 - Asegurar DNS Server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.5 - Asegurar DNS Server no instalado" "bind esta instalado" "Desinstalar: dnf remove bind -y" "$RED"
  return 1
}

# ==============================================
# 2.2.6 - ASEGURAR VSFTP SERVER NO INSTALADO
# ==============================================
check_vsftpd() {
  if ! rpm -q vsftpd &>/dev/null; then
    log_result "PASS" "2.2.6 - Asegurar VSFTP Server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.6 - Asegurar VSFTP Server no instalado" "vsftpd esta instalado" "Desinstalar: dnf remove vsftpd -y" "$RED"
  return 1
}

# ==============================================
# 2.2.7 - ASEGURAR TFTP SERVER NO INSTALADO
# ==============================================
check_tftp_server() {
  if ! rpm -q tftp-server &>/dev/null; then
    log_result "PASS" "2.2.7 - Asegurar TFTP Server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.7 - Asegurar TFTP Server no instalado" "tftp-server esta instalado" "Desinstalar: dnf remove tftp-server -y" "$RED"
  return 1
}

# ==============================================
# 2.2.8 - ASEGURAR WEB SERVER NO INSTALADO
# ==============================================
check_webserver() {
  if ! rpm -q httpd &>/dev/null && ! rpm -q nginx &>/dev/null; then
    log_result "PASS" "2.2.8 - Asegurar web server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.8 - Asegurar web server no instalado" "httpd o nginx estan instalados" "Desinstalar: dnf remove httpd nginx -y" "$RED"
  return 1
}

# ==============================================
# 2.2.9 - ASEGURAR IMAP Y POP3 NO INSTALADOS
# ==============================================
check_imap_pop3() {
  if ! rpm -q dovecot &>/dev/null && ! rpm -q cyrus-imapd &>/dev/null; then
    log_result "PASS" "2.2.9 - Asegurar servidor IMAP y POP3 no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.9 - Asegurar servidor IMAP y POP3 no instalado" "dovecot o cyrus-imapd estan instalados" "Desinstalar: dnf remove dovecot cyrus-imapd -y" "$RED"
  return 1
}

# ==============================================
# 2.2.10 - ASEGURAR SAMBA NO INSTALADO
# ==============================================
check_samba() {
  if ! rpm -q samba &>/dev/null; then
    log_result "PASS" "2.2.10 - Asegurar Samba no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.10 - Asegurar Samba no instalado" "samba esta instalado" "Desinstalar: dnf remove samba -y" "$RED"
  return 1
}

# ==============================================
# 2.2.11 - ASEGURAR HTTP PROXY NO INSTALADO
# ==============================================
check_squid() {
  if ! rpm -q squid &>/dev/null; then
    log_result "PASS" "2.2.11 - Asegurar HTTP Proxy Server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.11 - Asegurar HTTP Proxy Server no instalado" "squid esta instalado" "Desinstalar: dnf remove squid -y" "$RED"
  return 1
}

# ==============================================
# 2.2.12 - ASEGURAR NET-SNMP NO INSTALADO
# ==============================================
check_snmp() {
  if ! rpm -q net-snmp &>/dev/null; then
    log_result "PASS" "2.2.12 - Asegurar net-snmp no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.12 - Asegurar net-snmp no instalado" "net-snmp esta instalado" "Desinstalar: dnf remove net-snmp -y" "$RED"
  return 1
}

# ==============================================
# 2.2.13 - ASEGURAR TELNET-SERVER NO INSTALADO
# ==============================================
check_telnet_server() {
  if ! rpm -q telnet-server &>/dev/null; then
    log_result "PASS" "2.2.13 - Asegurar telnet-server no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.13 - Asegurar telnet-server no instalado" "telnet-server esta instalado" "Desinstalar: dnf remove telnet-server -y" "$RED"
  return 1
}

# ==============================================
# 2.2.14 - ASEGURAR DNSMASQ NO INSTALADO
# ==============================================
check_dnsmasq() {
  if ! rpm -q dnsmasq &>/dev/null; then
    log_result "PASS" "2.2.14 - Asegurar dnsmasq no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.14 - Asegurar dnsmasq no instalado" "dnsmasq esta instalado" "Desinstalar: dnf remove dnsmasq -y" "$RED"
  return 1
}

# ==============================================
# 2.2.15 - ASEGURAR MTA EN MODO SOLO LOCAL
# ==============================================
check_mta_local() {
  if ! ss -lntu 2>/dev/null | grep -q ":25 "; then
    log_result "PASS" "2.2.15 - Asegurar MTA configurado en modo solo local" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "2.2.15 - Asegurar MTA configurado en modo solo local" "MTA escuchando en puerto 25" "Configurar Postfix: editar /etc/postfix/main.cf y establecer inet_interfaces = localhost. Reiniciar: systemctl restart postfix" "$YELLOW"
  return 2
}

# ==============================================
# 2.2.16 - ASEGURAR NFS-UTILS NO INSTALADO O MASKED
# ==============================================
check_nfs() {
  if ! rpm -q nfs-utils &>/dev/null; then
    log_result "PASS" "2.2.16 - Asegurar nfs-utils no instalado o servicio masked" "" "" "$GREEN"
    return 0
  fi
  if systemctl is-enabled nfs-server 2>/dev/null | grep -q "masked"; then
    log_result "PASS" "2.2.16 - Asegurar nfs-utils no instalado o servicio masked" "nfs-server esta masked" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.16 - Asegurar nfs-utils no instalado o servicio masked" "nfs-utils instalado y nfs-server no masked" "Maskear el servicio: systemctl mask nfs-server" "$RED"
  return 1
}

# ==============================================
# 2.2.17 - ASEGURAR RPCBIND NO INSTALADO O MASKED
# ==============================================
check_rpcbind() {
  if ! rpm -q rpcbind &>/dev/null; then
    log_result "PASS" "2.2.17 - Asegurar rpcbind no instalado o servicios masked" "" "" "$GREEN"
    return 0
  fi
  if systemctl is-enabled rpcbind 2>/dev/null | grep -q "masked"; then
    log_result "PASS" "2.2.17 - Asegurar rpcbind no instalado o servicios masked" "rpcbind esta masked" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.17 - Asegurar rpcbind no instalado o servicios masked" "rpcbind instalado y no masked" "Maskear servicios: systemctl mask rpcbind.service rpcbind.socket" "$RED"
  return 1
}

# ==============================================
# 2.3.1 - ASEGURAR CLIENTE TELNET NO INSTALADO
# ==============================================
check_telnet_client() {
  if ! rpm -q telnet &>/dev/null; then
    log_result "PASS" "2.3.1 - Asegurar cliente telnet no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.1 - Asegurar cliente telnet no instalado" "telnet esta instalado" "Desinstalar: dnf remove telnet -y" "$RED"
  return 1
}

# ==============================================
# 2.3.2 - ASEGURAR CLIENTE LDAP NO INSTALADO
# ==============================================
check_ldap_client() {
  if ! rpm -q openldap-clients &>/dev/null; then
    log_result "PASS" "2.3.2 - Asegurar cliente LDAP no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.2 - Asegurar cliente LDAP no instalado" "openldap-clients esta instalado" "Desinstalar: dnf remove openldap-clients -y" "$RED"
  return 1
}

# ==============================================
# 2.3.3 - ASEGURAR CLIENTE TFTP NO INSTALADO
# ==============================================
check_tftp_client() {
  if ! rpm -q tftp &>/dev/null; then
    log_result "PASS" "2.3.3 - Asegurar cliente TFTP no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.3 - Asegurar cliente TFTP no instalado" "tftp esta instalado" "Desinstalar: dnf remove tftp -y" "$RED"
  return 1
}

# ==============================================
# 2.3.4 - ASEGURAR CLIENTE FTP NO INSTALADO
# ==============================================
check_ftp_client() {
  if ! rpm -q ftp &>/dev/null; then
    log_result "PASS" "2.3.4 - Asegurar cliente FTP no instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.4 - Asegurar cliente FTP no instalado" "ftp esta instalado" "Desinstalar: dnf remove ftp -y" "$RED"
  return 1
}

# ==============================================
# 3.1.3 - ASEGURAR TIPC DESHABILITADO
# ==============================================
check_tipc() {
  if modprobe -n -v tipc 2>&1 | grep -q "install /bin/true\|not found"; then
    if ! lsmod | grep -q "^tipc"; then
      log_result "PASS" "3.1.3 - Asegurar TIPC deshabilitado" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "3.1.3 - Asegurar TIPC deshabilitado" "El modulo tipc esta habilitado" "Crear archivo /etc/modprobe.d/tipc.conf con: install tipc /bin/false y blacklist tipc. Ejecutar: rmmod tipc" "$RED"
  return 1
}

# ==============================================
# 3.4.1.1 - ASEGURAR NFTABLES INSTALADO
# ==============================================
check_nftables() {
  if rpm -q nftables &>/dev/null; then
    log_result "PASS" "3.4.1.1 - Asegurar nftables instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "3.4.1.1 - Asegurar nftables instalado" "nftables no esta instalado" "Instalar nftables: dnf install nftables -y" "$RED"
  return 1
}

# ==============================================
# 4.1.1.1 - ASEGURAR AUDITD INSTALADO
# ==============================================
check_auditd_installed() {
  if rpm -q audit &>/dev/null; then
    log_result "PASS" "4.1.1.1 - Asegurar auditd instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.1.1 - Asegurar auditd instalado" "audit no esta instalado" "Instalar audit: dnf install audit -y" "$RED"
  return 1
}

# ==============================================
# 4.1.1.2 - ASEGURAR AUDITORIA EN PROCESOS PRE-AUDITD
# ==============================================
check_audit_boot() {
  if grep -q "audit=1" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "PASS" "4.1.1.2 - Asegurar auditoria de procesos previos a auditd" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.1.2 - Asegurar auditoria de procesos previos a auditd" "audit=1 no encontrado en grub.cfg" "Agregar audit=1 a GRUB_CMDLINE_LINUX en /etc/default/grub. Ejecutar: grub2-mkconfig -o /boot/grub2/grub.cfg" "$RED"
  return 1
}

# ==============================================
# 4.1.1.3 - ASEGURAR audit_backlog_limit SUFICIENTE
# ==============================================
check_audit_backlog() {
  if grep -q "audit_backlog_limit=8192" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "PASS" "4.1.1.3 - Asegurar audit_backlog_limit suficiente" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.1.3 - Asegurar audit_backlog_limit suficiente" "audit_backlog_limit no configurado" "Agregar audit_backlog_limit=8192 a GRUB_CMDLINE_LINUX en /etc/default/grub. Ejecutar: grub2-mkconfig -o /boot/grub2/grub.cfg" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.1.4 - ASEGURAR SERVICIO AUDITD HABILITADO
# ==============================================
check_auditd_enabled() {
  if systemctl is-enabled auditd &>/dev/null; then
    log_result "PASS" "4.1.1.4 - Asegurar servicio auditd habilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.1.4 - Asegurar servicio auditd habilitado" "auditd no esta habilitado" "Habilitar auditd: systemctl enable --now auditd" "$RED"
  return 1
}

# ==============================================
# 4.1.2.1 - ASEGURAR TAMAÑO DE LOGS DE AUDITORIA
# ==============================================
check_audit_log_size() {
  if grep -q "^max_log_file" /etc/audit/auditd.conf 2>/dev/null; then
    log_result "PASS" "4.1.2.1 - Asegurar tamaño de logs de auditoria configurado" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.2.1 - Asegurar tamaño de logs de auditoria configurado" "max_log_file no configurado" "Editar /etc/audit/auditd.conf y establecer: max_log_file = 50 (o segun politica)" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.2.2 - ASEGURAR LOGS NO ELIMINADOS AUTOMATICAMENTE
# ==============================================
check_audit_log_keep() {
  if grep -q "^max_log_file_action = keep_logs" /etc/audit/auditd.conf 2>/dev/null; then
    log_result "PASS" "4.1.2.2 - Asegurar logs de auditoria no eliminados automaticamente" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.2.2 - Asegurar logs de auditoria no eliminados automaticamente" "max_log_file_action no es keep_logs" "Editar /etc/audit/auditd.conf: max_log_file_action = keep_logs. Reiniciar: systemctl restart auditd" "$RED"
  return 1
}

# ==============================================
# 4.1.2.3 - ASEGURAR SISTEMA DESHABILITADO CUANDO LOGS LLENOS
# ==============================================
check_audit_full_action() {
  if grep -q "^admin_space_left_action = halt" /etc/audit/auditd.conf 2>/dev/null; then
    log_result "PASS" "4.1.2.3 - Asegurar sistema deshabilitado cuando logs llenos" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.2.3 - Asegurar sistema deshabilitado cuando logs llenos" "admin_space_left_action no es halt" "Editar /etc/audit/auditd.conf: admin_space_left_action = halt" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.1 - AUDITAR CAMBIOS EN SUDOERS
# ==============================================
check_audit_sudoers() {
  if auditctl -l 2>/dev/null | grep -q "sudoers" | grep -q "scope"; then
    log_result "PASS" "4.1.3.1 - Asegurar cambios en sudoers auditados" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.1 - Asegurar cambios en sudoers auditados" "Regla de auditoria para sudoers no encontrada" "Agregar reglas: -w /etc/sudoers -p wa -k scope y -w /etc/sudoers.d -p wa -k scope. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.2 - AUDITAR ACCIONES COMO OTRO USUARIO
# ==============================================
check_audit_user_emulation() {
  if auditctl -l 2>/dev/null | grep -q "user_emulation"; then
    log_result "PASS" "4.1.3.2 - Asegurar acciones como otro usuario auditadas" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.2 - Asegurar acciones como otro usuario auditadas" "Regla user_emulation no encontrada" "Agregar reglas para execve con archivos b32 y b64. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.4 - AUDITAR MODIFICACIONES DE FECHA Y HORA
# ==============================================
check_audit_time() {
  if auditctl -l 2>/dev/null | grep -q "time-change"; then
    log_result "PASS" "4.1.3.4 - Asegurar modificaciones de fecha/hora auditadas" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.4 - Asegurar modificaciones de fecha/hora auditadas" "Regla time-change no encontrada" "Agregar reglas para adjtimex, settimeofday, clock_settime y /etc/localtime. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.5 - AUDITAR MODIFICACIONES DE RED
# ==============================================
check_audit_network() {
  if auditctl -l 2>/dev/null | grep -q "system-locale"; then
    log_result "PASS" "4.1.3.5 - Asegurar modificaciones de red auditadas" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.5 - Asegurar modificaciones de red auditadas" "Regla system-locale no encontrada" "Agregar reglas para sethostname, setdomainname y archivos de red. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.8 - AUDITAR MODIFICACIONES DE USUARIO/Grupo
# ==============================================
check_audit_identity() {
  if auditctl -l 2>/dev/null | grep -q "identity"; then
    log_result "PASS" "4.1.3.8 - Asegurar modificaciones de usuario/grupo auditadas" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.8 - Asegurar modificaciones de usuario/grupo auditadas" "Regla identity no encontrada" "Agregar reglas para archivos /etc/group, /etc/passwd, /etc/gshadow, /etc/shadow, /etc/security/opasswd. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.10 - AUDITAR MONTADAS DE FILESYSTEM
# ==============================================
check_audit_mounts() {
  if auditctl -l 2>/dev/null | grep -q "mounts"; then
    log_result "PASS" "4.1.3.10 - Asegurar montadas de filesystem auditadas" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.10 - Asegurar montadas de filesystem auditadas" "Regla mounts no encontrada" "Agregar reglas para syscall mount. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.11 - AUDITAR INICIO DE SESION
# ==============================================
check_audit_session() {
  if auditctl -l 2>/dev/null | grep -q "session"; then
    log_result "PASS" "4.1.3.11 - Asegurar informacion de sesion auditada" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.11 - Asegurar informacion de sesion auditada" "Regla session no encontrada" "Agregar reglas para archivos utmp, wtmp, btmp. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.12 - AUDITAR EVENTOS DE LOGIN/LOGOUT
# ==============================================
check_audit_logins() {
  if auditctl -l 2>/dev/null | grep -q "logins"; then
    log_result "PASS" "4.1.3.12 - Asegurar eventos de login/logout auditados" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.12 - Asegurar eventos de login/logout auditados" "Regla logins no encontrada" "Agregar reglas para /var/log/lastlog y /var/run/faillock. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.13 - AUDITAR ELIMINACION DE ARCHIVOS
# ==============================================
check_audit_delete() {
  if auditctl -l 2>/dev/null | grep -q "delete"; then
    log_result "PASS" "4.1.3.13 - Asegurar eliminacion de archivos auditada" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.13 - Asegurar eliminacion de archivos auditada" "Regla delete no encontrada" "Agregar reglas para syscalls unlink, unlinkat, rename, renameat. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.14 - AUDITAR MODIFICACIONES DE SELINUX
# ==============================================
check_audit_mac() {
  if auditctl -l 2>/dev/null | grep -q "MAC-policy"; then
    log_result "PASS" "4.1.3.14 - Asegurar modificaciones de MAC auditadas" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.14 - Asegurar modificaciones de MAC auditadas" "Regla MAC-policy no encontrada" "Agregar reglas para /etc/selinux y /usr/share/selinux. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.19 - AUDITAR CARGA/DESCARGA DE MODULOS
# ==============================================
check_audit_modules() {
  if auditctl -l 2>/dev/null | grep -q "modules"; then
    log_result "PASS" "4.1.3.19 - Asegurar carga/descarga de modulos auditada" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.19 - Asegurar carga/descarga de modulos auditada" "Regla modules no encontrada" "Agregar reglas para init_module, finit_module, delete_module y /usr/bin/kmod. Cargar: augenrules --load" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.20 - ASEGURAR CONFIGURACION DE AUDITORIA INMUTABLE
# ==============================================
check_audit_immutable() {
  if auditctl -s 2>/dev/null | grep -q "enabled 2"; then
    log_result "PASS" "4.1.3.20 - Asegurar configuracion de auditoria inmutable" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.20 - Asegurar configuracion de auditoria inmutable" "Auditoria no en modo inmutable" "Agregar '-e 2' al final del archivo de reglas de auditoria. Requiere reinicio para aplicar" "$YELLOW"
  return 2
}

# ==============================================
# 5.1.1 - ASEGURAR SERVICIO CRON HABILITADO
# ==============================================
check_cron_enabled() {
  if systemctl is-enabled crond &>/dev/null; then
    log_result "PASS" "5.1.1 - Asegurar servicio cron habilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.1.1 - Asegurar servicio cron habilitado" "crond no esta habilitado" "Habilitar crond: systemctl enable --now crond" "$RED"
  return 1
}

# ==============================================
# 5.1.2 - PERMISOS EN /etc/crontab
# ==============================================
check_crontab_perms() {
  if [ -f /etc/crontab ]; then
    local perms=$(stat -c "%a" /etc/crontab 2>/dev/null)
    if [ "$perms" = "600" ]; then
      log_result "PASS" "5.1.2 - Asegurar permisos en /etc/crontab" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.2 - Asegurar permisos en /etc/crontab" "Permisos incorrectos" "Ejecutar: chmod 600 /etc/crontab && chown root:root /etc/crontab" "$RED"
  return 1
}

# ==============================================
# 5.1.3 - PERMISOS EN /etc/cron.hourly
# ==============================================
check_cron_hourly_perms() {
  if [ -d /etc/cron.hourly ]; then
    local perms=$(stat -c "%a" /etc/cron.hourly 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.3 - Asegurar permisos en /etc/cron.hourly" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.3 - Asegurar permisos en /etc/cron.hourly" "Permisos incorrectos" "Ejecutar: chmod 700 /etc/cron.hourly && chown root:root /etc/cron.hourly" "$RED"
  return 1
}

# ==============================================
# 5.1.4 - PERMISOS EN /etc/cron.daily
# ==============================================
check_cron_daily_perms() {
  if [ -d /etc/cron.daily ]; then
    local perms=$(stat -c "%a" /etc/cron.daily 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.4 - Asegurar permisos en /etc/cron.daily" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.4 - Asegurar permisos en /etc/cron.daily" "Permisos incorrectos" "Ejecutar: chmod 700 /etc/cron.daily && chown root:root /etc/cron.daily" "$RED"
  return 1
}

# ==============================================
# 5.1.5 - PERMISOS EN /etc/cron.weekly
# ==============================================
check_cron_weekly_perms() {
  if [ -d /etc/cron.weekly ]; then
    local perms=$(stat -c "%a" /etc/cron.weekly 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.5 - Asegurar permisos en /etc/cron.weekly" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.5 - Asegurar permisos en /etc/cron.weekly" "Permisos incorrectos" "Ejecutar: chmod 700 /etc/cron.weekly && chown root:root /etc/cron.weekly" "$RED"
  return 1
}

# ==============================================
# 5.1.6 - PERMISOS EN /etc/cron.monthly
# ==============================================
check_cron_monthly_perms() {
  if [ -d /etc/cron.monthly ]; then
    local perms=$(stat -c "%a" /etc/cron.monthly 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.6 - Asegurar permisos en /etc/cron.monthly" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.6 - Asegurar permisos en /etc/cron.monthly" "Permisos incorrectos" "Ejecutar: chmod 700 /etc/cron.monthly && chown root:root /etc/cron.monthly" "$RED"
  return 1
}

# ==============================================
# 5.1.7 - PERMISOS EN /etc/cron.d
# ==============================================
check_cron_d_perms() {
  if [ -d /etc/cron.d ]; then
    local perms=$(stat -c "%a" /etc/cron.d 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.7 - Asegurar permisos en /etc/cron.d" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.7 - Asegurar permisos en /etc/cron.d" "Permisos incorrectos" "Ejecutar: chmod 700 /etc/cron.d && chown root:root /etc/cron.d" "$RED"
  return 1
}

# ==============================================
# 5.1.8 - ASEGURAR CRON RESTRINGIDO A USUARIOS AUTORIZADOS
# ==============================================
check_cron_restricted() {
  if [ ! -f /etc/cron.deny ] && [ -f /etc/cron.allow ]; then
    local perms=$(stat -c "%a" /etc/cron.allow 2>/dev/null)
    if [ "$perms" = "640" ]; then
      log_result "PASS" "5.1.8 - Asegurar cron restringido a usuarios autorizados" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.8 - Asegurar cron restringido a usuarios autorizados" "cron.allow no configurado correctamente" "Eliminar cron.deny, crear cron.allow con solo root, permisos 640" "$RED"
  return 1
}

# ==============================================
# 5.1.9 - ASEGURAR AT RESTRINGIDO A USUARIOS AUTORIZADOS
# ==============================================
check_at_restricted() {
  if [ ! -f /etc/at.deny ] && [ -f /etc/at.allow ]; then
    local perms=$(stat -c "%a" /etc/at.allow 2>/dev/null)
    if [ "$perms" = "640" ]; then
      log_result "PASS" "5.1.9 - Asegurar at restringido a usuarios autorizados" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.9 - Asegurar at restringido a usuarios autorizados" "at.allow no configurado correctamente" "Eliminar at.deny, crear at.allow con solo root, permisos 640" "$RED"
  return 1
}

# ==============================================
# 5.2.1 - PERMISOS EN /etc/ssh/sshd_config
# ==============================================
check_sshd_perms() {
  if [ -f /etc/ssh/sshd_config ]; then
    local perms=$(stat -c "%a" /etc/ssh/sshd_config 2>/dev/null)
    if [ "$perms" = "600" ]; then
      log_result "PASS" "5.2.1 - Asegurar permisos en /etc/ssh/sshd_config" "" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.2.1 - Asegurar permisos en /etc/ssh/sshd_config" "Permisos incorrectos" "Ejecutar: chmod 600 /etc/ssh/sshd_config && chown root:root /etc/ssh/sshd_config" "$RED"
  return 1
}

# ==============================================
# 5.2.4 - ASEGURAR ACCESO SSH LIMITADO
# ==============================================
check_ssh_access() {
  if sshd -T 2>/dev/null | grep -qE "AllowUsers|AllowGroups|DenyUsers|DenyGroups"; then
    log_result "PASS" "5.2.4 - Asegurar acceso SSH limitado" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.4 - Asegurar acceso SSH limitado" "No hay restriccion de acceso configurada" "Agregar al /etc/ssh/sshd_config: AllowUsers usuario1 usuario2 o AllowGroups grupo. Reiniciar sshd" "$YELLOW"
  return 2
}

# ==============================================
# 5.2.5 - ASEGURAR LOGLEVEL DE SSH APROPIADO
# ==============================================
check_ssh_loglevel() {
  if sshd -T 2>/dev/null | grep -q "loglevel INFO\|loglevel VERBOSE"; then
    log_result "PASS" "5.2.5 - Asegurar LogLevel de SSH apropiado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.5 - Asegurar LogLevel de SSH apropiado" "LogLevel no es INFO o VERBOSE" "Configurar /etc/ssh/sshd_config: LogLevel VERBOSE. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.6 - ASEGURAR PAM HABILITADO EN SSH
# ==============================================
check_ssh_pam() {
  if sshd -T 2>/dev/null | grep -q "usepam yes"; then
    log_result "PASS" "5.2.6 - Asegurar PAM habilitado en SSH" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.6 - Asegurar PAM habilitado en SSH" "UsePAM no esta en yes" "Configurar /etc/ssh/sshd_config: UsePAM yes. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.7 - ASEGURAR LOGIN ROOT DESHABILITADO EN SSH
# ==============================================
check_ssh_root_login() {
  if sshd -T 2>/dev/null | grep -q "permitrootlogin no"; then
    log_result "PASS" "5.2.7 - Asegurar login root deshabilitado en SSH" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.7 - Asegurar login root deshabilitado en SSH" "PermitRootLogin no es no" "Configurar /etc/ssh/sshd_config: PermitRootLogin no. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.8 - ASEGURAR HOSTBASEDAUTHENTICATION DESHABILITADO
# ==============================================
check_ssh_hostbased() {
  if sshd -T 2>/dev/null | grep -q "hostbasedauthentication no"; then
    log_result "PASS" "5.2.8 - Asegurar HostbasedAuthentication deshabilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.8 - Asegurar HostbasedAuthentication deshabilitado" "HostbasedAuthentication no esta en no" "Configurar /etc/ssh/sshd_config: HostbasedAuthentication no. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.9 - ASEGURAR PERMITEMPTYPASSWORDS DESHABILITADO
# ==============================================
check_ssh_empty_pass() {
  if sshd -T 2>/dev/null | grep -q "permitemptypasswords no"; then
    log_result "PASS" "5.2.9 - Asegurar PermitEmptyPasswords deshabilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.9 - Asegurar PermitEmptyPasswords deshabilitado" "PermitEmptyPasswords no es no" "Configurar /etc/ssh/sshd_config: PermitEmptyPasswords no. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.10 - ASEGURAR PERMITUSERENVIRONMENT DESHABILITADO
# ==============================================
check_ssh_user_env() {
  if sshd -T 2>/dev/null | grep -q "permituserenvironment no"; then
    log_result "PASS" "5.2.10 - Asegurar PermitUserEnvironment deshabilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.10 - Asegurar PermitUserEnvironment deshabilitado" "PermitUserEnvironment no es no" "Configurar /etc/ssh/sshd_config: PermitUserEnvironment no. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.11 - ASEGURAR IGNORERHOSTS HABILITADO
# ==============================================
check_ssh_ignorerhosts() {
  if sshd -T 2>/dev/null | grep -q "ignorerhosts yes"; then
    log_result "PASS" "5.2.11 - Asegurar IgnoreRhosts habilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.11 - Asegurar IgnoreRhosts habilitado" "IgnoreRhosts no es yes" "Configurar /etc/ssh/sshd_config: IgnoreRhosts yes. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.12 - ASEGURAR X11 FORWARDING DESHABILITADO
# ==============================================
check_ssh_x11() {
  if sshd -T 2>/dev/null | grep -q "x11forwarding no"; then
    log_result "PASS" "5.2.12 - Asegurar X11 forwarding deshabilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.12 - Asegurar X11 forwarding deshabilitado" "X11Forwarding no es no" "Configurar /etc/ssh/sshd_config: X11Forwarding no. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.13 - ASEGURAR ALLOWTCPFORWARDING DESHABILITADO
# ==============================================
check_ssh_tcp_forward() {
  if sshd -T 2>/dev/null | grep -q "allowtcpforwarding no"; then
    log_result "PASS" "5.2.13 - Asegurar AllowTcpForwarding deshabilitado" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.13 - Asegurar AllowTcpForwarding deshabilitado" "AllowTcpForwarding no es no" "Configurar /etc/ssh/sshd_config: AllowTcpForwarding no. Reiniciar sshd" "$YELLOW"
  return 2
}

# ==============================================
# 5.2.15 - ASEGURAR BANNER DE ADVERTENCIA SSH
# ==============================================
check_ssh_banner() {
  if sshd -T 2>/dev/null | grep -q "banner /etc/issue.net"; then
    log_result "PASS" "5.2.15 - Asegurar banner de advertencia SSH configurado" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.15 - Asegurar banner de advertencia SSH configurado" "Banner no configurado" "Configurar /etc/ssh/sshd_config: Banner /etc/issue.net. Crear banner si no existe" "$YELLOW"
  return 2
}

# ==============================================
# 5.2.16 - ASEGURAR MAXAUTH TRIES 4 O MENOS
# ==============================================
check_ssh_maxauth() {
  local maxauth=$(sshd -T 2>/dev/null | grep -i "maxauthtries" | awk '{print $2}')
  if [ -n "$maxauth" ] && [ "$maxauth" -le 4 ]; then
    log_result "PASS" "5.2.16 - Asegurar MaxAuthTries 4 o menos" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.16 - Asegurar MaxAuthTries 4 o menos" "MaxAuthTries: $maxauth" "Configurar /etc/ssh/sshd_config: MaxAuthTries 4. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.18 - ASEGURAR MAXSESSIONS 10 O MENOS
# ==============================================
check_ssh_maxsessions() {
  local maxsessions=$(sshd -T 2>/dev/null | grep -i "maxsessions" | awk '{print $2}')
  if [ -n "$maxsessions" ] && [ "$maxsessions" -le 10 ]; then
    log_result "PASS" "5.2.18 - Asegurar MaxSessions 10 o menos" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.18 - Asegurar MaxSessions 10 o menos" "MaxSessions: $maxsessions" "Configurar /etc/ssh/sshd_config: MaxSessions 10. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.19 - ASEGURAR LOGINGRACETIME UN MINUTO O MENOS
# ==============================================
check_ssh_grace_time() {
  local grace=$(sshd -T 2>/dev/null | grep -i "logingracetime" | awk '{print $2}')
  if [ -n "$grace" ] && [ "$grace" -le 60 ]; then
    log_result "PASS" "5.2.19 - Asegurar LoginGraceTime un minuto o menos" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.19 - Asegurar LoginGraceTime un minuto o menos" "LoginGraceTime: $grace" "Configurar /etc/ssh/sshd_config: LoginGraceTime 60. Reiniciar sshd" "$RED"
  return 1
}

# ==============================================
# 5.2.20 - ASEGURAR TIMEOUT DE SESION SSH
# ==============================================
check_ssh_idle_timeout() {
  local interval=$(sshd -T 2>/dev/null | grep -i "clientaliveinterval" | awk '{print $2}')
  local count=$(sshd -T 2>/dev/null | grep -i "clientalivecountmax" | awk '{print $2}')
  if [ -n "$interval" ] && [ -n "$count" ] && [ "$interval" -gt 0 ] && [ "$count" -gt 0 ]; then
    log_result "PASS" "5.2.20 - Asegurar timeout de sesion SSH configurado" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.20 - Asegurar timeout de sesion SSH configurado" "ClientAlive no configurado correctamente" "Configurar /etc/ssh/sshd_config: ClientAliveInterval 300 y ClientAliveCountMax 0. Reiniciar sshd" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.1 - ASEGURAR SUDO INSTALADO
# ==============================================
check_sudo_installed() {
  if rpm -q sudo &>/dev/null; then
    log_result "PASS" "5.3.1 - Asegurar sudo instalado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.3.1 - Asegurar sudo instalado" "sudo no esta instalado" "Instalar sudo: dnf install sudo -y" "$RED"
  return 1
}

# ==============================================
# 5.3.2 - ASEGURAR COMANDOS SUDO USAN PTY
# ==============================================
check_sudo_pty() {
  if grep -q "Defaults use_pty" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    log_result "PASS" "5.3.2 - Asegurar comandos sudo usan pty" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.3.2 - Asegurar comandos sudo usan pty" "Defaults use_pty no configurado" "Agregar 'Defaults use_pty' a /etc/sudoers con visudo" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.3 - ASEGURAR ARCHIVO DE LOG DE SUDO
# ==============================================
check_sudo_logfile() {
  if grep -q "Defaults logfile=" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    log_result "PASS" "5.3.3 - Asegurar archivo de log de sudo existe" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.3.3 - Asegurar archivo de log de sudo existe" "Defaults logfile no configurado" "Agregar 'Defaults logfile=\"/var/log/sudo.log\"' a /etc/sudoers con visudo" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.6 - ASEGURAR TIMEOUT DE AUTENTICACION SUDO
# ==============================================
check_sudo_timeout() {
  if grep -q "timestamp_timeout" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    log_result "PASS" "5.3.6 - Asegurar timeout de autenticacion sudo configurado" "" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.3.6 - Asegurar timeout de autenticacion sudo configurado" "timestamp_timeout no configurado" "Agregar 'Defaults timestamp_timeout=5' a /etc/sudoers con visudo" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.7 - ASEGURAR ACCESO AL COMANDO SU RESTRINGIDO
# ==============================================
check_su_restricted() {
  if grep -q "pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
    log_result "PASS" "5.3.7 - Asegurar acceso al comando su restringido" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.3.7 - Asegurar acceso al comando su restringido" "pam_wheel.so no configurado" "Descomentar en /etc/pam.d/su: auth required pam_wheel.so use_uid. Crear grupo wheel si no existe" "$RED"
  return 1
}

# ==============================================
# 5.5.1 - REQUISITOS DE CREACION DE CONTRASEÑAS
# ==============================================
check_password_requirements() {
  local minlen=$(grep "^minlen" /etc/security/pwquality.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
  if [ -n "$minlen" ] && [ "$minlen" -ge 14 ]; then
    log_result "PASS" "5.5.1 - Requisitos de creacion de contraseñas configurados" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.1 - Requisitos de creacion de contraseñas configurados" "Password requirements no configurados" "Editar /etc/security/pwquality.conf: minlen=14, minclass=4 o dcredit=-1, ucredit=-1, ocredit=-1, lcredit=-1" "$RED"
  return 1
}

# ==============================================
# 5.5.2 - BLOQUEO POR INTENTOS FALLIDOS
# ==============================================
check_password_lockout() {
  if grep -q "pam_faillock.so" /etc/pam.d/system-auth 2>/dev/null; then
    log_result "PASS" "5.5.2 - Bloqueo por intentos fallidos configurado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.2 - Bloqueo por intentos fallidos configurado" "pam_faillock.so no configurado" "Configurar pam_faillock en /etc/pam.d/system-auth y password-auth. Usar authselect o editar manualmente" "$RED"
  return 1
}

# ==============================================
# 5.5.3 - LIMITAR REUSO DE CONTRASEÑAS
# ==============================================
check_password_reuse() {
  if grep -q "remember" /etc/pam.d/system-auth 2>/dev/null; then
    log_result "PASS" "5.5.3 - Reuso de contraseñas limitado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.3 - Reuso de contraseñas limitado" "remember no configurado" "Agregar 'remember=5' a la linea pam_unix.so en /etc/pam.d/system-auth" "$RED"
  return 1
}

# ==============================================
# 5.5.4 - ALGORITMO DE HASH SHA-512
# ==============================================
check_password_hashing() {
  if grep -q "ENCRYPT_METHOD SHA512" /etc/login.defs 2>/dev/null; then
    log_result "PASS" "5.5.4 - Algoritmo de hash SHA-512 configurado" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.4 - Algoritmo de hash SHA-512 configurado" "ENCRYPT_METHOD no es SHA512" "Editar /etc/login.defs: ENCRYPT_METHOD SHA512. Configurar pam_unix.so con sha512" "$RED"
  return 1
}

# ==============================================
# 5.6.1.1 - EXPIRACION DE CONTRASEÑA 365 DIAS O MENOS
# ==============================================
check_password_expiration() {
  local max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
  if [ -n "$max_days" ] && [ "$max_days" -le 365 ] && [ "$max_days" -gt 0 ]; then
    log_result "PASS" "5.6.1.1 - Expiracion de contraseña 365 dias o menos" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.1 - Expiracion de contraseña 365 dias o menos" "PASS_MAX_DAYS: $max_days" "Editar /etc/login.defs: PASS_MAX_DAYS 365. Aplicar a usuarios existentes con chage --maxdays 365" "$RED"
  return 1
}

# ==============================================
# 5.6.1.2 - DIAS MINIMOS ENTRE CAMBIOS DE CONTRASEÑA
# ==============================================
check_password_min_days() {
  local min_days=$(grep "^PASS_MIN_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
  if [ -n "$min_days" ] && [ "$min_days" -ge 7 ]; then
    log_result "PASS" "5.6.1.2 - Dias minimos entre cambios de contraseña 7 o mas" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.2 - Dias minimos entre cambios de contraseña 7 o mas" "PASS_MIN_DAYS: $min_days" "Editar /etc/login.defs: PASS_MIN_DAYS 7. Aplicar a usuarios existentes con chage --mindays 7" "$RED"
  return 1
}

# ==============================================
# 5.6.1.3 - DIAS DE ADVERTENCIA DE EXPIRACION
# ==============================================
check_password_warn_age() {
  local warn_age=$(grep "^PASS_WARN_AGE" /etc/login.defs 2>/dev/null | awk '{print $2}')
  if [ -n "$warn_age" ] && [ "$warn_age" -ge 7 ]; then
    log_result "PASS" "5.6.1.3 - Dias de advertencia de expiracion 7 o mas" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.3 - Dias de advertencia de expiracion 7 o mas" "PASS_WARN_AGE: $warn_age" "Editar /etc/login.defs: PASS_WARN_AGE 7. Aplicar a usuarios con chage --warndays 7" "$RED"
  return 1
}

# ==============================================
# 5.6.1.4 - BLOQUEO DE CUENTA INACTIVA 30 DIAS
# ==============================================
check_password_inactive() {
  local inactive=$(useradd -D 2>/dev/null | grep INACTIVE | cut -d= -f2)
  if [ -n "$inactive" ] && [ "$inactive" -le 30 ] && [ "$inactive" -ge 0 ]; then
    log_result "PASS" "5.6.1.4 - Bloqueo de cuenta inactiva 30 dias o menos" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.4 - Bloqueo de cuenta inactiva 30 dias o menos" "INACTIVE: $inactive" "Ejecutar: useradd -D -f 30. Aplicar a usuarios existentes con chage --inactive 30" "$RED"
  return 1
}

# ==============================================
# 6.1.1 - PERMISOS EN /etc/passwd
# ==============================================
check_passwd_perms() {
  local perms=$(stat -c "%a" /etc/passwd 2>/dev/null)
  if [ "$perms" = "644" ]; then
    log_result "PASS" "6.1.1 - Permisos en /etc/passwd configurados" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.1 - Permisos en /etc/passwd configurados" "Permisos: $perms" "Ejecutar: chmod 644 /etc/passwd && chown root:root /etc/passwd" "$RED"
  return 1
}

# ==============================================
# 6.1.2 - PERMISOS EN /etc/passwd-
# ==============================================
check_passwd_dash_perms() {
  if [ -f /etc/passwd- ]; then
    local perms=$(stat -c "%a" /etc/passwd- 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "6.1.2 - Permisos en /etc/passwd- configurados" "" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "6.1.2 - Permisos en /etc/passwd- configurados" "Archivo no existe" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.2 - Permisos en /etc/passwd- configurados" "Permisos: $perms" "Ejecutar: chmod 644 /etc/passwd- && chown root:root /etc/passwd-" "$RED"
  return 1
}

# ==============================================
# 6.1.3 - PERMISOS EN /etc/group
# ==============================================
check_group_perms() {
  local perms=$(stat -c "%a" /etc/group 2>/dev/null)
  if [ "$perms" = "644" ]; then
    log_result "PASS" "6.1.3 - Permisos en /etc/group configurados" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.3 - Permisos en /etc/group configurados" "Permisos: $perms" "Ejecutar: chmod 644 /etc/group && chown root:root /etc/group" "$RED"
  return 1
}

# ==============================================
# 6.1.4 - PERMISOS EN /etc/group-
# ==============================================
check_group_dash_perms() {
  if [ -f /etc/group- ]; then
    local perms=$(stat -c "%a" /etc/group- 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "6.1.4 - Permisos en /etc/group- configurados" "" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "6.1.4 - Permisos en /etc/group- configurados" "Archivo no existe" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.4 - Permisos en /etc/group- configurados" "Permisos: $perms" "Ejecutar: chmod 644 /etc/group- && chown root:root /etc/group-" "$RED"
  return 1
}

# ==============================================
# 6.1.5 - PERMISOS EN /etc/shadow
# ==============================================
check_shadow_perms() {
  local perms=$(stat -c "%a" /etc/shadow 2>/dev/null)
  if [ "$perms" = "0" ]; then
    log_result "PASS" "6.1.5 - Permisos en /etc/shadow configurados" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.5 - Permisos en /etc/shadow configurados" "Permisos: $perms" "Ejecutar: chmod 0000 /etc/shadow && chown root:root /etc/shadow" "$RED"
  return 1
}

# ==============================================
# 6.1.6 - PERMISOS EN /etc/shadow-
# ==============================================
check_shadow_dash_perms() {
  if [ -f /etc/shadow- ]; then
    local perms=$(stat -c "%a" /etc/shadow- 2>/dev/null)
    if [ "$perms" = "0" ]; then
      log_result "PASS" "6.1.6 - Permisos en /etc/shadow- configurados" "" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "6.1.6 - Permisos en /etc/shadow- configurados" "Archivo no existe" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.6 - Permisos en /etc/shadow- configurados" "Permisos: $perms" "Ejecutar: chmod 0000 /etc/shadow- && chown root:root /etc/shadow-" "$RED"
  return 1
}

# ==============================================
# 6.1.7 - PERMISOS EN /etc/gshadow
# ==============================================
check_gshadow_perms() {
  local perms=$(stat -c "%a" /etc/gshadow 2>/dev/null)
  if [ "$perms" = "0" ]; then
    log_result "PASS" "6.1.7 - Permisos en /etc/gshadow configurados" "" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.7 - Permisos en /etc/gshadow configurados" "Permisos: $perms" "Ejecutar: chmod 0000 /etc/gshadow && chown root:root /etc/gshadow" "$RED"
  return 1
}

# ==============================================
# 6.1.8 - PERMISOS EN /etc/gshadow-
# ==============================================
check_gshadow_dash_perms() {
  if [ -f /etc/gshadow- ]; then
    local perms=$(stat -c "%a" /etc/gshadow- 2>/dev/null)
    if [ "$perms" = "0" ]; then
      log_result "PASS" "6.1.8 - Permisos en /etc/gshadow- configurados" "" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "6.1.8 - Permisos en /etc/gshadow- configurados" "Archivo no existe" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.8 - Permisos en /etc/gshadow- configurados" "Permisos: $perms" "Ejecutar: chmod 0000 /etc/gshadow- && chown root:root /etc/gshadow-" "$RED"
  return 1
}

# ==============================================
# 6.2.1 - USO DE SHADOW PASSWORDS
# ==============================================
check_shadowed_passwords() {
  if grep -q "^[^:]*:[^x][^:]*:" /etc/passwd 2>/dev/null; then
    log_result "FAIL" "6.2.1 - Asegurar cuentas en /etc/passwd usan shadow passwords" "Algunas cuentas no usan shadow passwords" "Ejecutar: pwconv para convertir contraseñas a shadow" "$RED"
    return 1
  fi
  log_result "PASS" "6.2.1 - Asegurar cuentas en /etc/passwd usan shadow passwords" "" "" "$GREEN"
  return 0
}

# ==============================================
# 6.2.2 - CAMPOS DE CONTRASEÑA NO VACIOS EN /etc/shadow
# ==============================================
check_shadow_empty() {
  if grep -q "^[^:]*::" /etc/shadow 2>/dev/null; then
    log_result "FAIL" "6.2.2 - Asegurar campos de contraseña no vacios en /etc/shadow" "Cuentas con contraseña vacia encontradas" "Bloquear cuentas con contraseña vacia: passwd -l <usuario>" "$RED"
    return 1
  fi
  log_result "PASS" "6.2.2 - Asegurar campos de contraseña no vacios en /etc/shadow" "" "" "$GREEN"
  return 0
}

# ==============================================
# 6.2.9 - ROOT ES LA UNICA CUENTA CON UID 0
# ==============================================
check_unique_uid0() {
  if grep -v "^root:" /etc/passwd 2>/dev/null | grep -q ":0:"; then
    log_result "FAIL" "6.2.9 - Asegurar root es la unica cuenta con UID 0" "Otras cuentas con UID 0 encontradas" "Revisar cuentas con UID 0 y cambiar su UID o eliminar la cuenta" "$RED"
    return 1
  fi
  log_result "PASS" "6.2.9 - Asegurar root es la unica cuenta con UID 0" "" "" "$GREEN"
  return 0
}

# ==============================================
# FUNCION PARA MOSTRAR RESUMEN FINAL
# ==============================================
show_final_summary() {
  local total=$TOTAL_TESTS
  local percentage=$((PASSED * 100 / total))

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  VERIFICACION CIS BENCHMARK COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN FINAL:${NC}"
  echo -e "  • Tests PASADOS: ${GREEN}${PASSED}${NC}"
  echo -e "  • Tests FALLADOS (CRITICOS): ${RED}${FAILED}${NC}"
  echo -e "  • Tests WARNING: ${YELLOW}${WARN}${NC}"
  echo -e "  • Total tests: ${BLUE}${total}${NC}"
  echo -e "\n${YELLOW}Porcentaje de cumplimiento: ${GREEN}${percentage}%${NC}"

  echo -e "\n${YELLOW}RECOMENDACIONES GENERALES:${NC}"
  echo -e "  • Los tests en ${RED}ROJO${NC} requieren atencion inmediata - representan riesgos de seguridad"
  echo -e "  • Los tests en ${YELLOW}AMARILLO${NC} son mejorables - implementar segun politica"
  echo -e "  • Revise el reporte completo en: ${REPORT_FILE}"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  Reporte guardado en: ${REPORT_FILE}${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Herramienta de Verificacion CIS Benchmark${NC}"
  echo -e "${GREEN}  Para RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Limpiar reporte anterior
  echo "CIS Benchmark Verification Report" >"$REPORT_FILE"
  echo "Fecha: $(date)" >>"$REPORT_FILE"
  echo "=============================================" >>"$REPORT_FILE"
  echo "" >>"$REPORT_FILE"

  # Seccion 1.1 - Configuracion de Filesystem
  echo -e "\n${BLUE}=== Seccion 1.1 - Configuracion del Sistema de Archivos ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.1.1.1 - squashfs deshabilitado" check_squashfs
  run_test "1.1.1.2 - udf deshabilitado" check_udf
  run_test "1.1.2.1 - /tmp particion separada" check_tmp_partition
  run_test "1.1.2.2 - /tmp nodev" check_tmp_nodev
  run_test "1.1.2.3 - /tmp noexec" check_tmp_noexec
  run_test "1.1.2.4 - /tmp nosuid" check_tmp_nosuid
  run_test "1.1.3.1 - /var particion separada" check_var_partition
  run_test "1.1.3.2 - /var nodev" check_var_nodev
  run_test "1.1.3.3 - /var nosuid" check_var_nosuid
  run_test "1.1.4.1 - /var/tmp particion separada" check_var_tmp_partition
  run_test "1.1.4.2 - /var/tmp noexec" check_var_tmp_noexec
  run_test "1.1.4.3 - /var/tmp nosuid" check_var_tmp_nosuid
  run_test "1.1.4.4 - /var/tmp nodev" check_var_tmp_nodev
  run_test "1.1.5.1 - /var/log particion separada" check_var_log_partition
  run_test "1.1.5.2 - /var/log nodev" check_var_log_nodev
  run_test "1.1.5.3 - /var/log noexec" check_var_log_noexec
  run_test "1.1.5.4 - /var/log nosuid" check_var_log_nosuid
  run_test "1.1.6.1 - /var/log/audit particion separada" check_var_log_audit_partition
  run_test "1.1.6.2 - /var/log/audit noexec" check_var_log_audit_noexec
  run_test "1.1.6.3 - /var/log/audit nodev" check_var_log_audit_nodev
  run_test "1.1.6.4 - /var/log/audit nosuid" check_var_log_audit_nosuid
  run_test "1.1.7.1 - /home particion separada" check_home_partition
  run_test "1.1.7.2 - /home nodev" check_home_nodev
  run_test "1.1.7.3 - /home nosuid" check_home_nosuid
  run_test "1.1.8.1 - /dev/shm particion separada" check_dev_shm_partition
  run_test "1.1.8.2 - /dev/shm nodev" check_dev_shm_nodev
  run_test "1.1.8.3 - /dev/shm noexec" check_dev_shm_noexec
  run_test "1.1.8.4 - /dev/shm nosuid" check_dev_shm_nosuid
  run_test "1.1.9 - USB storage deshabilitado" check_usb_storage

  # Seccion 1.2 - Gestion de Paquetes
  echo -e "\n${BLUE}=== Seccion 1.2 - Gestion de Paquetes ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.2.2 - gpgcheck activado" check_gpgcheck

  # Seccion 1.3 - AIDE
  echo -e "\n${BLUE}=== Seccion 1.3 - AIDE ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.3.1 - AIDE instalado" check_aide
  run_test "1.3.2 - Verificacion periodica AIDE" check_aide_timer

  # Seccion 1.4 - Bootloader
  echo -e "\n${BLUE}=== Seccion 1.4 - Bootloader ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.4.1 - Contraseña de bootloader" check_grub_password
  run_test "1.4.2 - Permisos bootloader" check_grub_permissions

  # Seccion 1.5 - Core Dumps
  echo -e "\n${BLUE}=== Seccion 1.5 - Core Dumps ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.5.1 - Almacenamiento core dumps" check_coredump_storage
  run_test "1.5.2 - Backtraces core dumps" check_coredump_backtraces

  # Seccion 1.6 - SELinux
  echo -e "\n${BLUE}=== Seccion 1.6 - SELinux ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.6.1.1 - SELinux instalado" check_selinux_installed
  run_test "1.6.1.2 - SELinux habilitado en boot" check_selinux_bootloader
  run_test "1.6.1.3 - Politica SELinux" check_selinux_policy
  run_test "1.6.1.4 - Modo SELinux no deshabilitado" check_selinux_mode
  run_test "1.6.1.5 - Modo SELinux enforcing" check_selinux_enforcing
  run_test "1.6.1.6 - Servicios sin confinar" check_unconfined_services
  run_test "1.6.1.7 - SETroubleshoot" check_setroubleshoot
  run_test "1.6.1.8 - mcstrans" check_mcstrans

  # Seccion 1.7 - Banners de Advertencia
  echo -e "\n${BLUE}=== Seccion 1.7 - Banners de Advertencia ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.7.1 - MOTD configurado" check_motd
  run_test "1.7.2 - Banner local" check_issue
  run_test "1.7.3 - Banner remoto" check_issue_net
  run_test "1.7.4 - Permisos MOTD" check_motd_perms
  run_test "1.7.5 - Permisos issue" check_issue_perms
  run_test "1.7.6 - Permisos issue.net" check_issue_net_perms

  # Seccion 2.1 - Sincronizacion de Tiempo
  echo -e "\n${BLUE}=== Seccion 2.1 - Sincronizacion de Tiempo ===${NC}" | tee -a "$REPORT_FILE"
  run_test "2.1.1 - Sincronizacion de tiempo" check_chrony

  # Seccion 2.2 - Servicios Especiales
  echo -e "\n${BLUE}=== Seccion 2.2 - Servicios Especiales ===${NC}" | tee -a "$REPORT_FILE"
  run_test "2.2.1 - X Window" check_xwindow
  run_test "2.2.2 - Avahi" check_avahi
  run_test "2.2.3 - CUPS" check_cups
  run_test "2.2.4 - DHCP server" check_dhcp
  run_test "2.2.5 - DNS server" check_dns
  run_test "2.2.6 - VSFTP server" check_vsftpd
  run_test "2.2.7 - TFTP server" check_tftp_server
  run_test "2.2.8 - Web server" check_webserver
  run_test "2.2.9 - IMAP/POP3" check_imap_pop3
  run_test "2.2.10 - Samba" check_samba
  run_test "2.2.11 - HTTP proxy" check_squid
  run_test "2.2.12 - SNMP" check_snmp
  run_test "2.2.13 - Telnet server" check_telnet_server
  run_test "2.2.14 - dnsmasq" check_dnsmasq
  run_test "2.2.15 - MTA local" check_mta_local
  run_test "2.2.16 - NFS" check_nfs
  run_test "2.2.17 - rpcbind" check_rpcbind

  # Seccion 2.3 - Clientes
  echo -e "\n${BLUE}=== Seccion 2.3 - Clientes ===${NC}" | tee -a "$REPORT_FILE"
  run_test "2.3.1 - Telnet client" check_telnet_client
  run_test "2.3.2 - LDAP client" check_ldap_client
  run_test "2.3.3 - TFTP client" check_tftp_client
  run_test "2.3.4 - FTP client" check_ftp_client

  # Seccion 3.1 - Parametros de Red
  echo -e "\n${BLUE}=== Seccion 3.1 - Parametros de Red ===${NC}" | tee -a "$REPORT_FILE"
  run_test "3.1.3 - TIPC deshabilitado" check_tipc

  # Seccion 3.4 - Firewall
  echo -e "\n${BLUE}=== Seccion 3.4 - Firewall ===${NC}" | tee -a "$REPORT_FILE"
  run_test "3.4.1.1 - nftables instalado" check_nftables

  # Seccion 4.1 - Auditd
  echo -e "\n${BLUE}=== Seccion 4.1 - Auditd ===${NC}" | tee -a "$REPORT_FILE"
  run_test "4.1.1.1 - auditd instalado" check_auditd_installed
  run_test "4.1.1.2 - audit=1 en boot" check_audit_boot
  run_test "4.1.1.3 - audit_backlog_limit" check_audit_backlog
  run_test "4.1.1.4 - auditd habilitado" check_auditd_enabled
  run_test "4.1.2.1 - Tamaño logs audit" check_audit_log_size
  run_test "4.1.2.2 - Logs no eliminados" check_audit_log_keep
  run_test "4.1.2.3 - Accion logs llenos" check_audit_full_action
  run_test "4.1.3.1 - audit sudoers" check_audit_sudoers
  run_test "4.1.3.2 - audit user emulation" check_audit_user_emulation
  run_test "4.1.3.4 - audit time changes" check_audit_time
  run_test "4.1.3.5 - audit network changes" check_audit_network
  run_test "4.1.3.8 - audit identity" check_audit_identity
  run_test "4.1.3.10 - audit mounts" check_audit_mounts
  run_test "4.1.3.11 - audit session" check_audit_session
  run_test "4.1.3.12 - audit logins" check_audit_logins
  run_test "4.1.3.13 - audit file deletion" check_audit_delete
  run_test "4.1.3.14 - audit MAC" check_audit_mac
  run_test "4.1.3.19 - audit modules" check_audit_modules
  run_test "4.1.3.20 - audit immutable" check_audit_immutable

  # Seccion 5.1 - Cron y At
  echo -e "\n${BLUE}=== Seccion 5.1 - Cron y At ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.1.1 - cron habilitado" check_cron_enabled
  run_test "5.1.2 - permisos crontab" check_crontab_perms
  run_test "5.1.3 - permisos cron.hourly" check_cron_hourly_perms
  run_test "5.1.4 - permisos cron.daily" check_cron_daily_perms
  run_test "5.1.5 - permisos cron.weekly" check_cron_weekly_perms
  run_test "5.1.6 - permisos cron.monthly" check_cron_monthly_perms
  run_test "5.1.7 - permisos cron.d" check_cron_d_perms
  run_test "5.1.8 - cron restringido" check_cron_restricted
  run_test "5.1.9 - at restringido" check_at_restricted

  # Seccion 5.2 - SSH
  echo -e "\n${BLUE}=== Seccion 5.2 - SSH ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.2.1 - permisos sshd_config" check_sshd_perms
  run_test "5.2.4 - acceso SSH limitado" check_ssh_access
  run_test "5.2.5 - LogLevel SSH" check_ssh_loglevel
  run_test "5.2.6 - PAM en SSH" check_ssh_pam
  run_test "5.2.7 - root login SSH" check_ssh_root_login
  run_test "5.2.8 - HostbasedAuthentication" check_ssh_hostbased
  run_test "5.2.9 - PermitEmptyPasswords" check_ssh_empty_pass
  run_test "5.2.10 - PermitUserEnvironment" check_ssh_user_env
  run_test "5.2.11 - IgnoreRhosts" check_ssh_ignorerhosts
  run_test "5.2.12 - X11 forwarding" check_ssh_x11
  run_test "5.2.13 - AllowTcpForwarding" check_ssh_tcp_forward
  run_test "5.2.15 - Banner SSH" check_ssh_banner
  run_test "5.2.16 - MaxAuthTries" check_ssh_maxauth
  run_test "5.2.18 - MaxSessions" check_ssh_maxsessions
  run_test "5.2.19 - LoginGraceTime" check_ssh_grace_time
  run_test "5.2.20 - Idle timeout" check_ssh_idle_timeout

  # Seccion 5.3 - Sudo
  echo -e "\n${BLUE}=== Seccion 5.3 - Sudo ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.3.1 - sudo instalado" check_sudo_installed
  run_test "5.3.2 - sudo use_pty" check_sudo_pty
  run_test "5.3.3 - sudo logfile" check_sudo_logfile
  run_test "5.3.6 - sudo timeout" check_sudo_timeout
  run_test "5.3.7 - su restringido" check_su_restricted

  # Seccion 5.5 - Politicas de Contraseñas
  echo -e "\n${BLUE}=== Seccion 5.5 - Politicas de Contraseñas ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.5.1 - requisitos contraseñas" check_password_requirements
  run_test "5.5.2 - lockout" check_password_lockout
  run_test "5.5.3 - reuso limitado" check_password_reuse
  run_test "5.5.4 - hash SHA-512" check_password_hashing

  # Seccion 5.6 - Expiracion de Contraseñas
  echo -e "\n${BLUE}=== Seccion 5.6 - Expiracion de Contraseñas ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.6.1.1 - expiracion 365 dias" check_password_expiration
  run_test "5.6.1.2 - dias minimos" check_password_min_days
  run_test "5.6.1.3 - dias advertencia" check_password_warn_age
  run_test "5.6.1.4 - bloqueo inactivo" check_password_inactive

  # Seccion 6.1 - Permisos de Archivos
  echo -e "\n${BLUE}=== Seccion 6.1 - Permisos de Archivos ===${NC}" | tee -a "$REPORT_FILE"
  run_test "6.1.1 - permisos passwd" check_passwd_perms
  run_test "6.1.2 - permisos passwd-" check_passwd_dash_perms
  run_test "6.1.3 - permisos group" check_group_perms
  run_test "6.1.4 - permisos group-" check_group_dash_perms
  run_test "6.1.5 - permisos shadow" check_shadow_perms
  run_test "6.1.6 - permisos shadow-" check_shadow_dash_perms
  run_test "6.1.7 - permisos gshadow" check_gshadow_perms
  run_test "6.1.8 - permisos gshadow-" check_gshadow_dash_perms

  # Seccion 6.2 - Cuentas de Usuario
  echo -e "\n${BLUE}=== Seccion 6.2 - Cuentas de Usuario ===${NC}" | tee -a "$REPORT_FILE"
  run_test "6.2.1 - shadow passwords" check_shadowed_passwords
  run_test "6.2.2 - sin contraseñas vacias" check_shadow_empty
  run_test "6.2.9 - UID 0 unico" check_unique_uid0

  show_final_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
