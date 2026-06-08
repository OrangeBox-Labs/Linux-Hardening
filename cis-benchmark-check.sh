#!/bin/bash

# ==============================================
# Script: cis-benchmark-check.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Verificador de cumplimiento CIS Benchmark
#              Para RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10
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
  local color="$4"

  echo -e "${color}[${status}]${NC} ${title}"
  if [ -n "$details" ]; then
    echo -e "  ${details}"
  fi
  echo "[${status}] ${title}" >>"$REPORT_FILE"
  if [ -n "$details" ]; then
    echo "  ${details}" >>"$REPORT_FILE"
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
    if [ $? -eq 2 ]; then
      WARN=$((WARN + 1))
    else
      FAILED=$((FAILED + 1))
    fi
    return 1
  fi
}

# ==============================================
# 1.1.1.1 - DISABLE SQUASHFS
# ==============================================
check_squashfs() {
  if modprobe -n -v squashfs 2>&1 | grep -q "install /bin/false\|not found"; then
    if ! lsmod | grep -q "^squashfs"; then
      log_result "PASS" "1.1.1.1 - Ensure mounting of squashfs filesystems is disabled" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.1.1.1 - Ensure mounting of squashfs filesystems is disabled" "squashfs module is enabled" "$RED"
  return 1
}

# ==============================================
# 1.1.1.2 - DISABLE UDF
# ==============================================
check_udf() {
  if modprobe -n -v udf 2>&1 | grep -q "install /bin/false\|not found"; then
    if ! lsmod | grep -q "^udf"; then
      log_result "PASS" "1.1.1.2 - Ensure mounting of udf filesystems is disabled" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.1.1.2 - Ensure mounting of udf filesystems is disabled" "udf module is enabled" "$RED"
  return 1
}

# ==============================================
# 1.1.2.1 - ENSURE /tmp IS SEPARATE PARTITION
# ==============================================
check_tmp_partition() {
  if findmnt --kernel /tmp &>/dev/null; then
    log_result "PASS" "1.1.2.1 - Ensure /tmp is a separate partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.1 - Ensure /tmp is a separate partition" "/tmp is not a separate partition" "$RED"
  return 1
}

# ==============================================
# 1.1.2.2 - ENSURE NODEV OPTION ON /tmp
# ==============================================
check_tmp_nodev() {
  if findmnt --kernel /tmp | grep -q "nodev"; then
    log_result "PASS" "1.1.2.2 - Ensure nodev option set on /tmp partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.2 - Ensure nodev option set on /tmp partition" "nodev not set on /tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.2.3 - ENSURE NOEXEC OPTION ON /tmp
# ==============================================
check_tmp_noexec() {
  if findmnt --kernel /tmp | grep -q "noexec"; then
    log_result "PASS" "1.1.2.3 - Ensure noexec option set on /tmp partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.3 - Ensure noexec option set on /tmp partition" "noexec not set on /tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.2.4 - ENSURE NOSUID OPTION ON /tmp
# ==============================================
check_tmp_nosuid() {
  if findmnt --kernel /tmp | grep -q "nosuid"; then
    log_result "PASS" "1.1.2.4 - Ensure nosuid option set on /tmp partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.2.4 - Ensure nosuid option set on /tmp partition" "nosuid not set on /tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.3.1 - ENSURE /var IS SEPARATE PARTITION
# ==============================================
check_var_partition() {
  if findmnt --kernel /var &>/dev/null; then
    log_result "PASS" "1.1.3.1 - Ensure separate partition exists for /var" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.3.1 - Ensure separate partition exists for /var" "/var is not a separate partition" "$RED"
  return 1
}

# ==============================================
# 1.1.3.2 - ENSURE NODEV OPTION ON /var
# ==============================================
check_var_nodev() {
  if findmnt --kernel /var | grep -q "nodev"; then
    log_result "PASS" "1.1.3.2 - Ensure nodev option set on /var partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.3.2 - Ensure nodev option set on /var partition" "nodev not set on /var" "$RED"
  return 1
}

# ==============================================
# 1.1.3.3 - ENSURE NOSUID OPTION ON /var
# ==============================================
check_var_nosuid() {
  if findmnt --kernel /var | grep -q "nosuid"; then
    log_result "PASS" "1.1.3.3 - Ensure nosuid option set on /var partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.3.3 - Ensure nosuid option set on /var partition" "nosuid not set on /var" "$RED"
  return 1
}

# ==============================================
# 1.1.4.1 - ENSURE /var/tmp SEPARATE PARTITION
# ==============================================
check_var_tmp_partition() {
  if findmnt --kernel /var/tmp &>/dev/null; then
    log_result "PASS" "1.1.4.1 - Ensure separate partition exists for /var/tmp" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.1 - Ensure separate partition exists for /var/tmp" "/var/tmp is not a separate partition" "$RED"
  return 1
}

# ==============================================
# 1.1.4.2 - ENSURE NOEXEC OPTION ON /var/tmp
# ==============================================
check_var_tmp_noexec() {
  if findmnt --kernel /var/tmp | grep -q "noexec"; then
    log_result "PASS" "1.1.4.2 - Ensure noexec option set on /var/tmp partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.2 - Ensure noexec option set on /var/tmp partition" "noexec not set on /var/tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.4.3 - ENSURE NOSUID OPTION ON /var/tmp
# ==============================================
check_var_tmp_nosuid() {
  if findmnt --kernel /var/tmp | grep -q "nosuid"; then
    log_result "PASS" "1.1.4.3 - Ensure nosuid option set on /var/tmp partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.3 - Ensure nosuid option set on /var/tmp partition" "nosuid not set on /var/tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.4.4 - ENSURE NODEV OPTION ON /var/tmp
# ==============================================
check_var_tmp_nodev() {
  if findmnt --kernel /var/tmp | grep -q "nodev"; then
    log_result "PASS" "1.1.4.4 - Ensure nodev option set on /var/tmp partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.4.4 - Ensure nodev option set on /var/tmp partition" "nodev not set on /var/tmp" "$RED"
  return 1
}

# ==============================================
# 1.1.5.1 - ENSURE /var/log SEPARATE PARTITION
# ==============================================
check_var_log_partition() {
  if findmnt --kernel /var/log &>/dev/null; then
    log_result "PASS" "1.1.5.1 - Ensure separate partition exists for /var/log" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.1 - Ensure separate partition exists for /var/log" "/var/log is not a separate partition" "$RED"
  return 1
}

# ==============================================
# 1.1.5.2 - ENSURE NODEV OPTION ON /var/log
# ==============================================
check_var_log_nodev() {
  if findmnt --kernel /var/log | grep -q "nodev"; then
    log_result "PASS" "1.1.5.2 - Ensure nodev option set on /var/log partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.2 - Ensure nodev option set on /var/log partition" "nodev not set on /var/log" "$RED"
  return 1
}

# ==============================================
# 1.1.5.3 - ENSURE NOEXEC OPTION ON /var/log
# ==============================================
check_var_log_noexec() {
  if findmnt --kernel /var/log | grep -q "noexec"; then
    log_result "PASS" "1.1.5.3 - Ensure noexec option set on /var/log partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.3 - Ensure noexec option set on /var/log partition" "noexec not set on /var/log" "$RED"
  return 1
}

# ==============================================
# 1.1.5.4 - ENSURE NOSUID OPTION ON /var/log
# ==============================================
check_var_log_nosuid() {
  if findmnt --kernel /var/log | grep -q "nosuid"; then
    log_result "PASS" "1.1.5.4 - Ensure nosuid option set on /var/log partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.5.4 - Ensure nosuid option set on /var/log partition" "nosuid not set on /var/log" "$RED"
  return 1
}

# ==============================================
# 1.1.6.1 - ENSURE /var/log/audit SEPARATE PARTITION
# ==============================================
check_var_log_audit_partition() {
  if findmnt --kernel /var/log/audit &>/dev/null; then
    log_result "PASS" "1.1.6.1 - Ensure separate partition exists for /var/log/audit" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.1 - Ensure separate partition exists for /var/log/audit" "/var/log/audit is not a separate partition" "$RED"
  return 1
}

# ==============================================
# 1.1.6.2 - ENSURE NOEXEC OPTION ON /var/log/audit
# ==============================================
check_var_log_audit_noexec() {
  if findmnt --kernel /var/log/audit | grep -q "noexec"; then
    log_result "PASS" "1.1.6.2 - Ensure noexec option set on /var/log/audit partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.2 - Ensure noexec option set on /var/log/audit partition" "noexec not set on /var/log/audit" "$RED"
  return 1
}

# ==============================================
# 1.1.6.3 - ENSURE NODEV OPTION ON /var/log/audit
# ==============================================
check_var_log_audit_nodev() {
  if findmnt --kernel /var/log/audit | grep -q "nodev"; then
    log_result "PASS" "1.1.6.3 - Ensure nodev option set on /var/log/audit partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.3 - Ensure nodev option set on /var/log/audit partition" "nodev not set on /var/log/audit" "$RED"
  return 1
}

# ==============================================
# 1.1.6.4 - ENSURE NOSUID OPTION ON /var/log/audit
# ==============================================
check_var_log_audit_nosuid() {
  if findmnt --kernel /var/log/audit | grep -q "nosuid"; then
    log_result "PASS" "1.1.6.4 - Ensure nosuid option set on /var/log/audit partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.6.4 - Ensure nosuid option set on /var/log/audit partition" "nosuid not set on /var/log/audit" "$RED"
  return 1
}

# ==============================================
# 1.1.7.1 - ENSURE /home SEPARATE PARTITION
# ==============================================
check_home_partition() {
  if findmnt --kernel /home &>/dev/null; then
    log_result "PASS" "1.1.7.1 - Ensure separate partition exists for /home" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.7.1 - Ensure separate partition exists for /home" "/home is not a separate partition" "$RED"
  return 1
}

# ==============================================
# 1.1.7.2 - ENSURE NODEV OPTION ON /home
# ==============================================
check_home_nodev() {
  if findmnt --kernel /home | grep -q "nodev"; then
    log_result "PASS" "1.1.7.2 - Ensure nodev option set on /home partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.7.2 - Ensure nodev option set on /home partition" "nodev not set on /home" "$RED"
  return 1
}

# ==============================================
# 1.1.7.3 - ENSURE NOSUID OPTION ON /home
# ==============================================
check_home_nosuid() {
  if findmnt --kernel /home | grep -q "nosuid"; then
    log_result "PASS" "1.1.7.3 - Ensure nosuid option set on /home partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.7.3 - Ensure nosuid option set on /home partition" "nosuid not set on /home" "$RED"
  return 1
}

# ==============================================
# 1.1.8.1 - ENSURE /dev/shm IS SEPARATE PARTITION
# ==============================================
check_dev_shm_partition() {
  if findmnt --kernel /dev/shm &>/dev/null; then
    log_result "PASS" "1.1.8.1 - Ensure /dev/shm is a separate partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.1 - Ensure /dev/shm is a separate partition" "/dev/shm is not a separate partition" "$RED"
  return 1
}

# ==============================================
# 1.1.8.2 - ENSURE NODEV OPTION ON /dev/shm
# ==============================================
check_dev_shm_nodev() {
  if findmnt --kernel /dev/shm | grep -q "nodev"; then
    log_result "PASS" "1.1.8.2 - Ensure nodev option set on /dev/shm partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.2 - Ensure nodev option set on /dev/shm partition" "nodev not set on /dev/shm" "$RED"
  return 1
}

# ==============================================
# 1.1.8.3 - ENSURE NOEXEC OPTION ON /dev/shm
# ==============================================
check_dev_shm_noexec() {
  if findmnt --kernel /dev/shm | grep -q "noexec"; then
    log_result "PASS" "1.1.8.3 - Ensure noexec option set on /dev/shm partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.3 - Ensure noexec option set on /dev/shm partition" "noexec not set on /dev/shm" "$RED"
  return 1
}

# ==============================================
# 1.1.8.4 - ENSURE NOSUID OPTION ON /dev/shm
# ==============================================
check_dev_shm_nosuid() {
  if findmnt --kernel /dev/shm | grep -q "nosuid"; then
    log_result "PASS" "1.1.8.4 - Ensure nosuid option set on /dev/shm partition" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.1.8.4 - Ensure nosuid option set on /dev/shm partition" "nosuid not set on /dev/shm" "$RED"
  return 1
}

# ==============================================
# 1.1.9 - DISABLE USB STORAGE
# ==============================================
check_usb_storage() {
  if modprobe -n -v usb-storage 2>&1 | grep -q "install /bin/true\|not found"; then
    if ! lsmod | grep -q "^usb-storage"; then
      log_result "PASS" "1.1.9 - Disable USB Storage" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.1.9 - Disable USB Storage" "usb-storage module is enabled" "$RED"
  return 1
}

# ==============================================
# 1.2.2 - ENSURE GPGCHECK IS GLOBALLY ACTIVATED
# ==============================================
check_gpgcheck() {
  if grep -q "^gpgcheck=1" /etc/dnf/dnf.conf 2>/dev/null; then
    if ! grep -q "gpgcheck=0" /etc/yum.repos.d/*.repo 2>/dev/null; then
      log_result "PASS" "1.2.2 - Ensure gpgcheck is globally activated" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.2.2 - Ensure gpgcheck is globally activated" "gpgcheck not properly configured" "$RED"
  return 1
}

# ==============================================
# 1.3.1 - ENSURE AIDE IS INSTALLED
# ==============================================
check_aide() {
  if rpm -q aide &>/dev/null; then
    log_result "PASS" "1.3.1 - Ensure AIDE is installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.3.1 - Ensure AIDE is installed" "AIDE package not installed" "$RED"
  return 1
}

# ==============================================
# 1.3.2 - ENSURE FILESYSTEM INTEGRITY REGULARLY CHECKED
# ==============================================
check_aide_timer() {
  if systemctl is-enabled aidecheck.timer &>/dev/null; then
    log_result "PASS" "1.3.2 - Ensure filesystem integrity is regularly checked" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.3.2 - Ensure filesystem integrity is regularly checked" "aidecheck.timer not enabled" "$RED"
  return 1
}

# ==============================================
# 1.4.1 - ENSURE BOOTLOADER PASSWORD IS SET
# ==============================================
check_grub_password() {
  if grep -q "^password" /boot/grub2/grub.cfg 2>/dev/null || grep -q "set superusers" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "PASS" "1.4.1 - Ensure bootloader password is set" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.4.1 - Ensure bootloader password is set" "No bootloader password found" "$RED"
  return 1
}

# ==============================================
# 1.4.2 - ENSURE PERMISSIONS ON BOOTLOADER CONFIG
# ==============================================
check_grub_permissions() {
  local perms=$(stat -c "%a" /boot/grub2/grub.cfg 2>/dev/null)
  if [ "$perms" = "600" ] || [ "$perms" = "400" ]; then
    log_result "PASS" "1.4.2 - Ensure permissions on bootloader config are configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.4.2 - Ensure permissions on bootloader config are configured" "grub.cfg permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 1.5.1 - ENSURE CORE DUMP STORAGE IS DISABLED
# ==============================================
check_coredump_storage() {
  if grep -q "^Storage=none" /etc/systemd/coredump.conf 2>/dev/null; then
    log_result "PASS" "1.5.1 - Ensure core dump storage is disabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.5.1 - Ensure core dump storage is disabled" "Storage=none not set in coredump.conf" "$RED"
  return 1
}

# ==============================================
# 1.5.2 - ENSURE CORE DUMP BACKTRACES ARE DISABLED
# ==============================================
check_coredump_backtraces() {
  if grep -q "^ProcessSizeMax=0" /etc/systemd/coredump.conf 2>/dev/null; then
    log_result "PASS" "1.5.2 - Ensure core dump backtraces are disabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.5.2 - Ensure core dump backtraces are disabled" "ProcessSizeMax=0 not set" "$RED"
  return 1
}

# ==============================================
# 1.6.1.1 - ENSURE SELINUX IS INSTALLED
# ==============================================
check_selinux_installed() {
  if rpm -q libselinux &>/dev/null; then
    log_result "PASS" "1.6.1.1 - Ensure SELinux is installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.1 - Ensure SELinux is installed" "libselinux package not installed" "$RED"
  return 1
}

# ==============================================
# 1.6.1.2 - ENSURE SELINUX NOT DISABLED IN BOOTLOADER
# ==============================================
check_selinux_bootloader() {
  if grep -q "selinux=0" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "FAIL" "1.6.1.2 - Ensure SELinux is not disabled in bootloader configuration" "selinux=0 found in grub.cfg" "$RED"
    return 1
  fi
  log_result "PASS" "1.6.1.2 - Ensure SELinux is not disabled in bootloader configuration" "" "$GREEN"
  return 0
}

# ==============================================
# 1.6.1.3 - ENSURE SELINUX POLICY IS CONFIGURED
# ==============================================
check_selinux_policy() {
  if grep -q "^SELINUXTYPE=targeted" /etc/selinux/config 2>/dev/null; then
    log_result "PASS" "1.6.1.3 - Ensure SELinux policy is configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.3 - Ensure SELinux policy is configured" "SELINUXTYPE not set to targeted" "$RED"
  return 1
}

# ==============================================
# 1.6.1.4 - ENSURE SELINUX MODE NOT DISABLED
# ==============================================
check_selinux_mode() {
  local mode=$(getenforce 2>/dev/null)
  if [ "$mode" = "Enforcing" ] || [ "$mode" = "Permissive" ]; then
    log_result "PASS" "1.6.1.4 - Ensure the SELinux mode is not disabled" "Mode: $mode" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.4 - Ensure the SELinux mode is not disabled" "SELinux is disabled" "$RED"
  return 1
}

# ==============================================
# 1.6.1.5 - ENSURE SELINUX MODE IS ENFORCING
# ==============================================
check_selinux_enforcing() {
  local mode=$(getenforce 2>/dev/null)
  if [ "$mode" = "Enforcing" ]; then
    log_result "PASS" "1.6.1.5 - Ensure the SELinux mode is enforcing" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.6.1.5 - Ensure the SELinux mode is enforcing" "Mode: $mode (should be Enforcing)" "$YELLOW"
  return 2
}

# ==============================================
# 1.6.1.6 - ENSURE NO UNCONFINED SERVICES
# ==============================================
check_unconfined_services() {
  if ! ps -eZ 2>/dev/null | grep -q "unconfined_service_t"; then
    log_result "PASS" "1.6.1.6 - Ensure no unconfined services exist" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "1.6.1.6 - Ensure no unconfined services exist" "Unconfined services detected" "$YELLOW"
  return 2
}

# ==============================================
# 1.6.1.7 - ENSURE SETROUBLESHOOT NOT INSTALLED
# ==============================================
check_setroubleshoot() {
  if ! rpm -q setroubleshoot &>/dev/null; then
    log_result "PASS" "1.6.1.7 - Ensure SETroubleshoot is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.7 - Ensure SETroubleshoot is not installed" "setroubleshoot package is installed" "$RED"
  return 1
}

# ==============================================
# 1.6.1.8 - ENSURE MCS Translation SERVICE NOT INSTALLED
# ==============================================
check_mcstrans() {
  if ! rpm -q mcstrans &>/dev/null; then
    log_result "PASS" "1.6.1.8 - Ensure the MCS Translation Service (mcstrans) is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.6.1.8 - Ensure the MCS Translation Service (mcstrans) is not installed" "mcstrans package is installed" "$RED"
  return 1
}

# ==============================================
# 1.7.1 - ENSURE MESSAGE OF THE DAY IS CONFIGURED PROPERLY
# ==============================================
check_motd() {
  if [ -f /etc/motd ]; then
    if ! grep -q "\\\v\|\\\r\|\\\m\|\\\s" /etc/motd 2>/dev/null; then
      log_result "PASS" "1.7.1 - Ensure message of the day is configured properly" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "1.7.1 - Ensure message of the day is configured properly" "/etc/motd does not exist" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.7.1 - Ensure message of the day is configured properly" "motd contains OS version information" "$RED"
  return 1
}

# ==============================================
# 1.7.2 - ENSURE LOCAL LOGIN WARNING BANNER CONFIGURED
# ==============================================
check_issue() {
  if [ -f /etc/issue ]; then
    if ! grep -q "\\\v\|\\\r\|\\\m\|\\\s" /etc/issue 2>/dev/null; then
      log_result "PASS" "1.7.2 - Ensure local login warning banner is configured properly" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.2 - Ensure local login warning banner is configured properly" "/etc/issue contains OS version information" "$RED"
  return 1
}

# ==============================================
# 1.7.3 - ENSURE REMOTE LOGIN WARNING BANNER CONFIGURED
# ==============================================
check_issue_net() {
  if [ -f /etc/issue.net ]; then
    if ! grep -q "\\\v\|\\\r\|\\\m\|\\\s" /etc/issue.net 2>/dev/null; then
      log_result "PASS" "1.7.3 - Ensure remote login warning banner is configured properly" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.3 - Ensure remote login warning banner is configured properly" "/etc/issue.net contains OS version information" "$RED"
  return 1
}

# ==============================================
# 1.7.4 - ENSURE PERMISSIONS ON /etc/motd
# ==============================================
check_motd_perms() {
  if [ -f /etc/motd ]; then
    local perms=$(stat -c "%a" /etc/motd 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "1.7.4 - Ensure permissions on /etc/motd are configured" "" "$GREEN"
      return 0
    fi
  else
    log_result "PASS" "1.7.4 - Ensure permissions on /etc/motd are configured" "/etc/motd does not exist" "$GREEN"
    return 0
  fi
  log_result "FAIL" "1.7.4 - Ensure permissions on /etc/motd are configured" "motd permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 1.7.5 - ENSURE PERMISSIONS ON /etc/issue
# ==============================================
check_issue_perms() {
  if [ -f /etc/issue ]; then
    local perms=$(stat -c "%a" /etc/issue 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "1.7.5 - Ensure permissions on /etc/issue are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.5 - Ensure permissions on /etc/issue are configured" "issue permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 1.7.6 - ENSURE PERMISSIONS ON /etc/issue.net
# ==============================================
check_issue_net_perms() {
  if [ -f /etc/issue.net ]; then
    local perms=$(stat -c "%a" /etc/issue.net 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "1.7.6 - Ensure permissions on /etc/issue.net are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "1.7.6 - Ensure permissions on /etc/issue.net are configured" "issue.net permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 2.1.1 - ENSURE TIME SYNCHRONIZATION IS IN USE
# ==============================================
check_chrony() {
  if rpm -q chrony &>/dev/null; then
    log_result "PASS" "2.1.1 - Ensure time synchronization is in use" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.1.1 - Ensure time synchronization is in use" "chrony not installed" "$RED"
  return 1
}

# ==============================================
# 2.2.1 - ENSURE X WINDOW SYSTEM NOT INSTALLED
# ==============================================
check_xwindow() {
  if ! rpm -q xorg-x11-server-common &>/dev/null; then
    log_result "PASS" "2.2.1 - Ensure xorg-x11-server-common is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.1 - Ensure xorg-x11-server-common is not installed" "X Window packages are installed" "$RED"
  return 1
}

# ==============================================
# 2.2.2 - ENSURE AVAHI SERVER NOT INSTALLED
# ==============================================
check_avahi() {
  if ! rpm -q avahi &>/dev/null; then
    log_result "PASS" "2.2.2 - Ensure Avahi Server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.2 - Ensure Avahi Server is not installed" "avahi package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.3 - ENSURE CUPS NOT INSTALLED
# ==============================================
check_cups() {
  if ! rpm -q cups &>/dev/null; then
    log_result "PASS" "2.2.3 - Ensure CUPS is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.3 - Ensure CUPS is not installed" "cups package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.4 - ENSURE DHCP SERVER NOT INSTALLED
# ==============================================
check_dhcp() {
  if ! rpm -q dhcp-server &>/dev/null; then
    log_result "PASS" "2.2.4 - Ensure DHCP Server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.4 - Ensure DHCP Server is not installed" "dhcp-server package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.5 - ENSURE DNS SERVER NOT INSTALLED
# ==============================================
check_dns() {
  if ! rpm -q bind &>/dev/null; then
    log_result "PASS" "2.2.5 - Ensure DNS Server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.5 - Ensure DNS Server is not installed" "bind package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.6 - ENSURE VSFTP SERVER NOT INSTALLED
# ==============================================
check_vsftpd() {
  if ! rpm -q vsftpd &>/dev/null; then
    log_result "PASS" "2.2.6 - Ensure VSFTP Server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.6 - Ensure VSFTP Server is not installed" "vsftpd package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.7 - ENSURE TFTP SERVER NOT INSTALLED
# ==============================================
check_tftp_server() {
  if ! rpm -q tftp-server &>/dev/null; then
    log_result "PASS" "2.2.7 - Ensure TFTP Server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.7 - Ensure TFTP Server is not installed" "tftp-server package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.8 - ENSURE WEB SERVER NOT INSTALLED
# ==============================================
check_webserver() {
  if ! rpm -q httpd &>/dev/null && ! rpm -q nginx &>/dev/null; then
    log_result "PASS" "2.2.8 - Ensure a web server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.8 - Ensure a web server is not installed" "httpd or nginx is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.9 - ENSURE IMAP AND POP3 SERVER NOT INSTALLED
# ==============================================
check_imap_pop3() {
  if ! rpm -q dovecot &>/dev/null && ! rpm -q cyrus-imapd &>/dev/null; then
    log_result "PASS" "2.2.9 - Ensure IMAP and POP3 server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.9 - Ensure IMAP and POP3 server is not installed" "dovecot or cyrus-imapd is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.10 - ENSURE SAMBA NOT INSTALLED
# ==============================================
check_samba() {
  if ! rpm -q samba &>/dev/null; then
    log_result "PASS" "2.2.10 - Ensure Samba is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.10 - Ensure Samba is not installed" "samba package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.11 - ENSURE HTTP PROXY SERVER NOT INSTALLED
# ==============================================
check_squid() {
  if ! rpm -q squid &>/dev/null; then
    log_result "PASS" "2.2.11 - Ensure HTTP Proxy Server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.11 - Ensure HTTP Proxy Server is not installed" "squid package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.12 - ENSURE NET-SNMP NOT INSTALLED
# ==============================================
check_snmp() {
  if ! rpm -q net-snmp &>/dev/null; then
    log_result "PASS" "2.2.12 - Ensure net-snmp is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.12 - Ensure net-snmp is not installed" "net-snmp package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.13 - ENSURE TELNET-SERVER NOT INSTALLED
# ==============================================
check_telnet_server() {
  if ! rpm -q telnet-server &>/dev/null; then
    log_result "PASS" "2.2.13 - Ensure telnet-server is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.13 - Ensure telnet-server is not installed" "telnet-server package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.14 - ENSURE DNSMASQ NOT INSTALLED
# ==============================================
check_dnsmasq() {
  if ! rpm -q dnsmasq &>/dev/null; then
    log_result "PASS" "2.2.14 - Ensure dnsmasq is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.14 - Ensure dnsmasq is not installed" "dnsmasq package is installed" "$RED"
  return 1
}

# ==============================================
# 2.2.15 - ENSURE MTA CONFIGURED FOR LOCAL-ONLY MODE
# ==============================================
check_mta_local() {
  if ! ss -lntu 2>/dev/null | grep -q ":25 "; then
    log_result "PASS" "2.2.15 - Ensure mail transfer agent is configured for local-only mode" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "2.2.15 - Ensure mail transfer agent is configured for local-only mode" "MTA listening on port 25" "$YELLOW"
  return 2
}

# ==============================================
# 2.2.16 - ENSURE NFS-UTILS NOT INSTALLED OR MASKED
# ==============================================
check_nfs() {
  if ! rpm -q nfs-utils &>/dev/null; then
    log_result "PASS" "2.2.16 - Ensure nfs-utils is not installed or the nfs-server service is masked" "" "$GREEN"
    return 0
  fi
  if systemctl is-enabled nfs-server 2>/dev/null | grep -q "masked"; then
    log_result "PASS" "2.2.16 - Ensure nfs-utils is not installed or the nfs-server service is masked" "nfs-server is masked" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.16 - Ensure nfs-utils is not installed or the nfs-server service is masked" "nfs-utils installed and nfs-server not masked" "$RED"
  return 1
}

# ==============================================
# 2.2.17 - ENSURE RPCBIND NOT INSTALLED OR MASKED
# ==============================================
check_rpcbind() {
  if ! rpm -q rpcbind &>/dev/null; then
    log_result "PASS" "2.2.17 - Ensure rpcbind is not installed or the rpcbind services are masked" "" "$GREEN"
    return 0
  fi
  if systemctl is-enabled rpcbind 2>/dev/null | grep -q "masked"; then
    log_result "PASS" "2.2.17 - Ensure rpcbind is not installed or the rpcbind services are masked" "rpcbind is masked" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.2.17 - Ensure rpcbind is not installed or the rpcbind services are masked" "rpcbind installed and not masked" "$RED"
  return 1
}

# ==============================================
# 2.3.1 - ENSURE TELNET CLIENT NOT INSTALLED
# ==============================================
check_telnet_client() {
  if ! rpm -q telnet &>/dev/null; then
    log_result "PASS" "2.3.1 - Ensure telnet client is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.1 - Ensure telnet client is not installed" "telnet package is installed" "$RED"
  return 1
}

# ==============================================
# 2.3.2 - ENSURE LDAP CLIENT NOT INSTALLED
# ==============================================
check_ldap_client() {
  if ! rpm -q openldap-clients &>/dev/null; then
    log_result "PASS" "2.3.2 - Ensure LDAP client is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.2 - Ensure LDAP client is not installed" "openldap-clients package is installed" "$RED"
  return 1
}

# ==============================================
# 2.3.3 - ENSURE TFTP CLIENT NOT INSTALLED
# ==============================================
check_tftp_client() {
  if ! rpm -q tftp &>/dev/null; then
    log_result "PASS" "2.3.3 - Ensure TFTP client is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.3 - Ensure TFTP client is not installed" "tftp package is installed" "$RED"
  return 1
}

# ==============================================
# 2.3.4 - ENSURE FTP CLIENT NOT INSTALLED
# ==============================================
check_ftp_client() {
  if ! rpm -q ftp &>/dev/null; then
    log_result "PASS" "2.3.4 - Ensure FTP client is not installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "2.3.4 - Ensure FTP client is not installed" "ftp package is installed" "$RED"
  return 1
}

# ==============================================
# 3.1.3 - ENSURE TIPC IS DISABLED
# ==============================================
check_tipc() {
  if modprobe -n -v tipc 2>&1 | grep -q "install /bin/true\|not found"; then
    if ! lsmod | grep -q "^tipc"; then
      log_result "PASS" "3.1.3 - Ensure TIPC is disabled" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "3.1.3 - Ensure TIPC is disabled" "tipc module is enabled" "$RED"
  return 1
}

# ==============================================
# 3.4.1.1 - ENSURE NFTABLES IS INSTALLED
# ==============================================
check_nftables() {
  if rpm -q nftables &>/dev/null; then
    log_result "PASS" "3.4.1.1 - Ensure nftables is installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "3.4.1.1 - Ensure nftables is installed" "nftables package not installed" "$RED"
  return 1
}

# ==============================================
# 4.1.1.1 - ENSURE AUDITD IS INSTALLED
# ==============================================
check_auditd_installed() {
  if rpm -q audit &>/dev/null; then
    log_result "PASS" "4.1.1.1 - Ensure auditd is installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.1.1 - Ensure auditd is installed" "audit package not installed" "$RED"
  return 1
}

# ==============================================
# 4.1.1.2 - ENSURE AUDITING FOR PROCESSES THAT START PRIOR TO AUDITD
# ==============================================
check_audit_boot() {
  if grep -q "audit=1" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "PASS" "4.1.1.2 - Ensure auditing for processes that start prior to auditd is enabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.1.2 - Ensure auditing for processes that start prior to auditd is enabled" "audit=1 not found in grub.cfg" "$RED"
  return 1
}

# ==============================================
# 4.1.1.3 - ENSURE AUDIT_BACKLOG_LIMIT IS SUFFICIENT
# ==============================================
check_audit_backlog() {
  if grep -q "audit_backlog_limit=8192" /boot/grub2/grub.cfg 2>/dev/null; then
    log_result "PASS" "4.1.1.3 - Ensure audit_backlog_limit is sufficient" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.1.3 - Ensure audit_backlog_limit is sufficient" "audit_backlog_limit not set to 8192" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.1.4 - ENSURE AUDITD SERVICE IS ENABLED
# ==============================================
check_auditd_enabled() {
  if systemctl is-enabled auditd &>/dev/null; then
    log_result "PASS" "4.1.1.4 - Ensure auditd service is enabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.1.4 - Ensure auditd service is enabled" "auditd service not enabled" "$RED"
  return 1
}

# ==============================================
# 4.1.2.1 - ENSURE AUDIT LOG STORAGE SIZE IS CONFIGURED
# ==============================================
check_audit_log_size() {
  if grep -q "^max_log_file" /etc/audit/auditd.conf 2>/dev/null; then
    log_result "PASS" "4.1.2.1 - Ensure audit log storage size is configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.2.1 - Ensure audit log storage size is configured" "max_log_file not set in auditd.conf" "$RED"
  return 1
}

# ==============================================
# 4.1.2.2 - ENSURE AUDIT LOGS NOT AUTOMATICALLY DELETED
# ==============================================
check_audit_log_keep() {
  if grep -q "^max_log_file_action = keep_logs" /etc/audit/auditd.conf 2>/dev/null; then
    log_result "PASS" "4.1.2.2 - Ensure audit logs are not automatically deleted" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "4.1.2.2 - Ensure audit logs are not automatically deleted" "max_log_file_action not set to keep_logs" "$RED"
  return 1
}

# ==============================================
# 4.1.2.3 - ENSURE SYSTEM DISABLED WHEN AUDIT LOGS ARE FULL
# ==============================================
check_audit_full_action() {
  if grep -q "^admin_space_left_action = halt" /etc/audit/auditd.conf 2>/dev/null; then
    log_result "PASS" "4.1.2.3 - Ensure system is disabled when audit logs are full" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.2.3 - Ensure system is disabled when audit logs are full" "admin_space_left_action not set to halt" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.1 - ENSURE CHANGES TO SYSTEM ADMINISTRATION SCOPE (SUDOERS) IS COLLECTED
# ==============================================
check_audit_sudoers() {
  if auditctl -l 2>/dev/null | grep -q "sudoers" | grep -q "scope"; then
    log_result "PASS" "4.1.3.1 - Ensure changes to system administration scope (sudoers) is collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.1 - Ensure changes to system administration scope (sudoers) is collected" "sudoers audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.2 - ENSURE ACTIONS AS ANOTHER USER ARE ALWAYS LOGGED
# ==============================================
check_audit_user_emulation() {
  if auditctl -l 2>/dev/null | grep -q "user_emulation"; then
    log_result "PASS" "4.1.3.2 - Ensure actions as another user are always logged" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.2 - Ensure actions as another user are always logged" "user_emulation audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.4 - ENSURE EVENTS THAT MODIFY DATE AND TIME INFO ARE COLLECTED
# ==============================================
check_audit_time() {
  if auditctl -l 2>/dev/null | grep -q "time-change"; then
    log_result "PASS" "4.1.3.4 - Ensure events that modify date and time information are collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.4 - Ensure events that modify date and time information are collected" "time-change audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.5 - ENSURE EVENTS THAT MODIFY NETWORK ENVIRONMENT ARE COLLECTED
# ==============================================
check_audit_network() {
  if auditctl -l 2>/dev/null | grep -q "system-locale"; then
    log_result "PASS" "4.1.3.5 - Ensure events that modify the system's network environment are collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.5 - Ensure events that modify the system's network environment are collected" "system-locale audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.8 - ENSURE EVENTS THAT MODIFY USER/GROUP INFO ARE COLLECTED
# ==============================================
check_audit_identity() {
  if auditctl -l 2>/dev/null | grep -q "identity"; then
    log_result "PASS" "4.1.3.8 - Ensure events that modify user/group information are collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.8 - Ensure events that modify user/group information are collected" "identity audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.10 - ENSURE SUCCESSFUL FILE SYSTEM MOUNTS ARE COLLECTED
# ==============================================
check_audit_mounts() {
  if auditctl -l 2>/dev/null | grep -q "mounts"; then
    log_result "PASS" "4.1.3.10 - Ensure successful file system mounts are collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.10 - Ensure successful file system mounts are collected" "mounts audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.11 - ENSURE SESSION INITIATION INFORMATION IS COLLECTED
# ==============================================
check_audit_session() {
  if auditctl -l 2>/dev/null | grep -q "session"; then
    log_result "PASS" "4.1.3.11 - Ensure session initiation information is collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.11 - Ensure session initiation information is collected" "session audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.12 - ENSURE LOGIN AND LOGOUT EVENTS ARE COLLECTED
# ==============================================
check_audit_logins() {
  if auditctl -l 2>/dev/null | grep -q "logins"; then
    log_result "PASS" "4.1.3.12 - Ensure login and logout events are collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.12 - Ensure login and logout events are collected" "logins audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.13 - ENSURE FILE DELETION EVENTS BY USERS ARE COLLECTED
# ==============================================
check_audit_delete() {
  if auditctl -l 2>/dev/null | grep -q "delete"; then
    log_result "PASS" "4.1.3.13 - Ensure file deletion events by users are collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.13 - Ensure file deletion events by users are collected" "delete audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.14 - ENSURE EVENTS THAT MODIFY MAC ARE COLLECTED
# ==============================================
check_audit_mac() {
  if auditctl -l 2>/dev/null | grep -q "MAC-policy"; then
    log_result "PASS" "4.1.3.14 - Ensure events that modify the system's Mandatory Access Controls are collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.14 - Ensure events that modify the system's Mandatory Access Controls are collected" "MAC-policy audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.19 - ENSURE KERNEL MODULE LOADING/UNLOADING IS COLLECTED
# ==============================================
check_audit_modules() {
  if auditctl -l 2>/dev/null | grep -q "modules"; then
    log_result "PASS" "4.1.3.19 - Ensure kernel module loading unloading and modification is collected" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.19 - Ensure kernel module loading unloading and modification is collected" "modules audit rule not found" "$YELLOW"
  return 2
}

# ==============================================
# 4.1.3.20 - ENSURE AUDIT CONFIGURATION IS IMMUTABLE
# ==============================================
check_audit_immutable() {
  if auditctl -s 2>/dev/null | grep -q "enabled 2"; then
    log_result "PASS" "4.1.3.20 - Ensure the audit configuration is immutable" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "4.1.3.20 - Ensure the audit configuration is immutable" "Audit not in immutable mode" "$YELLOW"
  return 2
}

# ==============================================
# 5.1.1 - ENSURE CRON DAEMON IS ENABLED
# ==============================================
check_cron_enabled() {
  if systemctl is-enabled crond &>/dev/null; then
    log_result "PASS" "5.1.1 - Ensure cron daemon is enabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.1.1 - Ensure cron daemon is enabled" "cron daemon not enabled" "$RED"
  return 1
}

# ==============================================
# 5.1.2 - ENSURE PERMISSIONS ON /etc/crontab
# ==============================================
check_crontab_perms() {
  if [ -f /etc/crontab ]; then
    local perms=$(stat -c "%a" /etc/crontab 2>/dev/null)
    if [ "$perms" = "600" ]; then
      log_result "PASS" "5.1.2 - Ensure permissions on /etc/crontab are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.2 - Ensure permissions on /etc/crontab are configured" "/etc/crontab permissions incorrect" "$RED"
  return 1
}

# ==============================================
# 5.1.3 - ENSURE PERMISSIONS ON /etc/cron.hourly
# ==============================================
check_cron_hourly_perms() {
  if [ -d /etc/cron.hourly ]; then
    local perms=$(stat -c "%a" /etc/cron.hourly 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.3 - Ensure permissions on /etc/cron.hourly are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.3 - Ensure permissions on /etc/cron.hourly are configured" "/etc/cron.hourly permissions incorrect" "$RED"
  return 1
}

# ==============================================
# 5.1.4 - ENSURE PERMISSIONS ON /etc/cron.daily
# ==============================================
check_cron_daily_perms() {
  if [ -d /etc/cron.daily ]; then
    local perms=$(stat -c "%a" /etc/cron.daily 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.4 - Ensure permissions on /etc/cron.daily are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.4 - Ensure permissions on /etc/cron.daily are configured" "/etc/cron.daily permissions incorrect" "$RED"
  return 1
}

# ==============================================
# 5.1.5 - ENSURE PERMISSIONS ON /etc/cron.weekly
# ==============================================
check_cron_weekly_perms() {
  if [ -d /etc/cron.weekly ]; then
    local perms=$(stat -c "%a" /etc/cron.weekly 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.5 - Ensure permissions on /etc/cron.weekly are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.5 - Ensure permissions on /etc/cron.weekly are configured" "/etc/cron.weekly permissions incorrect" "$RED"
  return 1
}

# ==============================================
# 5.1.6 - ENSURE PERMISSIONS ON /etc/cron.monthly
# ==============================================
check_cron_monthly_perms() {
  if [ -d /etc/cron.monthly ]; then
    local perms=$(stat -c "%a" /etc/cron.monthly 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.6 - Ensure permissions on /etc/cron.monthly are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.6 - Ensure permissions on /etc/cron.monthly are configured" "/etc/cron.monthly permissions incorrect" "$RED"
  return 1
}

# ==============================================
# 5.1.7 - ENSURE PERMISSIONS ON /etc/cron.d
# ==============================================
check_cron_d_perms() {
  if [ -d /etc/cron.d ]; then
    local perms=$(stat -c "%a" /etc/cron.d 2>/dev/null)
    if [ "$perms" = "700" ]; then
      log_result "PASS" "5.1.7 - Ensure permissions on /etc/cron.d are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.7 - Ensure permissions on /etc/cron.d are configured" "/etc/cron.d permissions incorrect" "$RED"
  return 1
}

# ==============================================
# 5.1.8 - ENSURE CRON RESTRICTED TO AUTHORIZED USERS
# ==============================================
check_cron_restricted() {
  if [ ! -f /etc/cron.deny ] && [ -f /etc/cron.allow ]; then
    local perms=$(stat -c "%a" /etc/cron.allow 2>/dev/null)
    if [ "$perms" = "640" ]; then
      log_result "PASS" "5.1.8 - Ensure cron is restricted to authorized users" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.8 - Ensure cron is restricted to authorized users" "cron.allow not properly configured" "$RED"
  return 1
}

# ==============================================
# 5.1.9 - ENSURE AT RESTRICTED TO AUTHORIZED USERS
# ==============================================
check_at_restricted() {
  if [ ! -f /etc/at.deny ] && [ -f /etc/at.allow ]; then
    local perms=$(stat -c "%a" /etc/at.allow 2>/dev/null)
    if [ "$perms" = "640" ]; then
      log_result "PASS" "5.1.9 - Ensure at is restricted to authorized users" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.1.9 - Ensure at is restricted to authorized users" "at.allow not properly configured" "$RED"
  return 1
}

# ==============================================
# 5.2.1 - ENSURE PERMISSIONS ON /etc/ssh/sshd_config
# ==============================================
check_sshd_perms() {
  if [ -f /etc/ssh/sshd_config ]; then
    local perms=$(stat -c "%a" /etc/ssh/sshd_config 2>/dev/null)
    if [ "$perms" = "600" ]; then
      log_result "PASS" "5.2.1 - Ensure permissions on /etc/ssh/sshd_config are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "FAIL" "5.2.1 - Ensure permissions on /etc/ssh/sshd_config are configured" "sshd_config permissions incorrect" "$RED"
  return 1
}

# ==============================================
# 5.2.4 - ENSURE SSH ACCESS IS LIMITED
# ==============================================
check_ssh_access() {
  if sshd -T 2>/dev/null | grep -qE "AllowUsers|AllowGroups|DenyUsers|DenyGroups"; then
    log_result "PASS" "5.2.4 - Ensure SSH access is limited" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.4 - Ensure SSH access is limited" "No access restriction configured" "$YELLOW"
  return 2
}

# ==============================================
# 5.2.5 - ENSURE SSH LOGLEVEL IS APPROPRIATE
# ==============================================
check_ssh_loglevel() {
  if sshd -T 2>/dev/null | grep -q "loglevel INFO\|loglevel VERBOSE"; then
    log_result "PASS" "5.2.5 - Ensure SSH LogLevel is appropriate" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.5 - Ensure SSH LogLevel is appropriate" "LogLevel not set to INFO or VERBOSE" "$RED"
  return 1
}

# ==============================================
# 5.2.6 - ENSURE SSH PAM IS ENABLED
# ==============================================
check_ssh_pam() {
  if sshd -T 2>/dev/null | grep -q "usepam yes"; then
    log_result "PASS" "5.2.6 - Ensure SSH PAM is enabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.6 - Ensure SSH PAM is enabled" "UsePAM not set to yes" "$RED"
  return 1
}

# ==============================================
# 5.2.7 - ENSURE SSH ROOT LOGIN IS DISABLED
# ==============================================
check_ssh_root_login() {
  if sshd -T 2>/dev/null | grep -q "permitrootlogin no"; then
    log_result "PASS" "5.2.7 - Ensure SSH root login is disabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.7 - Ensure SSH root login is disabled" "PermitRootLogin not set to no" "$RED"
  return 1
}

# ==============================================
# 5.2.8 - ENSURE SSH HOSTBASEDAUTHENTICATION IS DISABLED
# ==============================================
check_ssh_hostbased() {
  if sshd -T 2>/dev/null | grep -q "hostbasedauthentication no"; then
    log_result "PASS" "5.2.8 - Ensure SSH HostbasedAuthentication is disabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.8 - Ensure SSH HostbasedAuthentication is disabled" "HostbasedAuthentication not set to no" "$RED"
  return 1
}

# ==============================================
# 5.2.9 - ENSURE SSH PERMITEMPTYPASSWORDS IS DISABLED
# ==============================================
check_ssh_empty_pass() {
  if sshd -T 2>/dev/null | grep -q "permitemptypasswords no"; then
    log_result "PASS" "5.2.9 - Ensure SSH PermitEmptyPasswords is disabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.9 - Ensure SSH PermitEmptyPasswords is disabled" "PermitEmptyPasswords not set to no" "$RED"
  return 1
}

# ==============================================
# 5.2.10 - ENSURE SSH PERMITUSERENVIRONMENT IS DISABLED
# ==============================================
check_ssh_user_env() {
  if sshd -T 2>/dev/null | grep -q "permituserenvironment no"; then
    log_result "PASS" "5.2.10 - Ensure SSH PermitUserEnvironment is disabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.10 - Ensure SSH PermitUserEnvironment is disabled" "PermitUserEnvironment not set to no" "$RED"
  return 1
}

# ==============================================
# 5.2.11 - ENSURE SSH IGNORERHOSTS IS ENABLED
# ==============================================
check_ssh_ignorerhosts() {
  if sshd -T 2>/dev/null | grep -q "ignorerhosts yes"; then
    log_result "PASS" "5.2.11 - Ensure SSH IgnoreRhosts is enabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.11 - Ensure SSH IgnoreRhosts is enabled" "IgnoreRhosts not set to yes" "$RED"
  return 1
}

# ==============================================
# 5.2.12 - ENSURE SSH X11 FORWARDING IS DISABLED
# ==============================================
check_ssh_x11() {
  if sshd -T 2>/dev/null | grep -q "x11forwarding no"; then
    log_result "PASS" "5.2.12 - Ensure SSH X11 forwarding is disabled" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.12 - Ensure SSH X11 forwarding is disabled" "X11Forwarding not set to no" "$RED"
  return 1
}

# ==============================================
# 5.2.13 - ENSURE SSH ALLOWTCPFORWARDING IS DISABLED
# ==============================================
check_ssh_tcp_forward() {
  if sshd -T 2>/dev/null | grep -q "allowtcpforwarding no"; then
    log_result "PASS" "5.2.13 - Ensure SSH AllowTcpForwarding is disabled" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.13 - Ensure SSH AllowTcpForwarding is disabled" "AllowTcpForwarding not set to no" "$YELLOW"
  return 2
}

# ==============================================
# 5.2.15 - ENSURE SSH WARNING BANNER IS CONFIGURED
# ==============================================
check_ssh_banner() {
  if sshd -T 2>/dev/null | grep -q "banner /etc/issue.net"; then
    log_result "PASS" "5.2.15 - Ensure SSH warning banner is configured" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.15 - Ensure SSH warning banner is configured" "Banner not set to /etc/issue.net" "$YELLOW"
  return 2
}

# ==============================================
# 5.2.16 - ENSURE SSH MAXAUTH TRIES IS SET TO 4 OR LESS
# ==============================================
check_ssh_maxauth() {
  local maxauth=$(sshd -T 2>/dev/null | grep -i "maxauthtries" | awk '{print $2}')
  if [ -n "$maxauth" ] && [ "$maxauth" -le 4 ]; then
    log_result "PASS" "5.2.16 - Ensure SSH MaxAuthTries is set to 4 or less" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.16 - Ensure SSH MaxAuthTries is set to 4 or less" "MaxAuthTries: $maxauth" "$RED"
  return 1
}

# ==============================================
# 5.2.18 - ENSURE SSH MAXSESSIONS IS SET TO 10 OR LESS
# ==============================================
check_ssh_maxsessions() {
  local maxsessions=$(sshd -T 2>/dev/null | grep -i "maxsessions" | awk '{print $2}')
  if [ -n "$maxsessions" ] && [ "$maxsessions" -le 10 ]; then
    log_result "PASS" "5.2.18 - Ensure SSH MaxSessions is set to 10 or less" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.18 - Ensure SSH MaxSessions is set to 10 or less" "MaxSessions: $maxsessions" "$RED"
  return 1
}

# ==============================================
# 5.2.19 - ENSURE SSH LOGINGRACETIME IS SET TO ONE MINUTE OR LESS
# ==============================================
check_ssh_grace_time() {
  local grace=$(sshd -T 2>/dev/null | grep -i "logingracetime" | awk '{print $2}')
  if [ -n "$grace" ] && [ "$grace" -le 60 ]; then
    log_result "PASS" "5.2.19 - Ensure SSH LoginGraceTime is set to one minute or less" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.2.19 - Ensure SSH LoginGraceTime is set to one minute or less" "LoginGraceTime: $grace" "$RED"
  return 1
}

# ==============================================
# 5.2.20 - ENSURE SSH IDLE TIMEOUT INTERVAL IS CONFIGURED
# ==============================================
check_ssh_idle_timeout() {
  local interval=$(sshd -T 2>/dev/null | grep -i "clientaliveinterval" | awk '{print $2}')
  local count=$(sshd -T 2>/dev/null | grep -i "clientalivecountmax" | awk '{print $2}')
  if [ -n "$interval" ] && [ -n "$count" ] && [ "$interval" -gt 0 ] && [ "$count" -gt 0 ]; then
    log_result "PASS" "5.2.20 - Ensure SSH Idle Timeout Interval is configured" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.2.20 - Ensure SSH Idle Timeout Interval is configured" "ClientAlive not properly configured" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.1 - ENSURE SUDO IS INSTALLED
# ==============================================
check_sudo_installed() {
  if rpm -q sudo &>/dev/null; then
    log_result "PASS" "5.3.1 - Ensure sudo is installed" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.3.1 - Ensure sudo is installed" "sudo package not installed" "$RED"
  return 1
}

# ==============================================
# 5.3.2 - ENSURE SUDO COMMANDS USE PTY
# ==============================================
check_sudo_pty() {
  if grep -q "Defaults use_pty" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    log_result "PASS" "5.3.2 - Ensure sudo commands use pty" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.3.2 - Ensure sudo commands use pty" "Defaults use_pty not configured" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.3 - ENSURE SUDO LOG FILE EXISTS
# ==============================================
check_sudo_logfile() {
  if grep -q "Defaults logfile=" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    log_result "PASS" "5.3.3 - Ensure sudo log file exists" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.3.3 - Ensure sudo log file exists" "Defaults logfile not configured" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.6 - ENSURE SUDO AUTHENTICATION TIMEOUT IS CONFIGURED CORRECTLY
# ==============================================
check_sudo_timeout() {
  if grep -q "timestamp_timeout" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    log_result "PASS" "5.3.6 - Ensure sudo authentication timeout is configured correctly" "" "$GREEN"
    return 0
  fi
  log_result "WARN" "5.3.6 - Ensure sudo authentication timeout is configured correctly" "timestamp_timeout not configured" "$YELLOW"
  return 2
}

# ==============================================
# 5.3.7 - ENSURE ACCESS TO SU COMMAND IS RESTRICTED
# ==============================================
check_su_restricted() {
  if grep -q "pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
    log_result "PASS" "5.3.7 - Ensure access to the su command is restricted" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.3.7 - Ensure access to the su command is restricted" "pam_wheel.so not configured in /etc/pam.d/su" "$RED"
  return 1
}

# ==============================================
# 5.5.1 - ENSURE PASSWORD CREATION REQUIREMENTS ARE CONFIGURED
# ==============================================
check_password_requirements() {
  local minlen=$(grep "^minlen" /etc/security/pwquality.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
  if [ -n "$minlen" ] && [ "$minlen" -ge 14 ]; then
    log_result "PASS" "5.5.1 - Ensure password creation requirements are configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.1 - Ensure password creation requirements are configured" "Password requirements not properly configured" "$RED"
  return 1
}

# ==============================================
# 5.5.2 - ENSURE LOCKOUT FOR FAILED PASSWORD ATTEMPTS IS CONFIGURED
# ==============================================
check_password_lockout() {
  if grep -q "pam_faillock.so" /etc/pam.d/system-auth 2>/dev/null; then
    log_result "PASS" "5.5.2 - Ensure lockout for failed password attempts is configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.2 - Ensure lockout for failed password attempts is configured" "pam_faillock.so not configured" "$RED"
  return 1
}

# ==============================================
# 5.5.3 - ENSURE PASSWORD REUSE IS LIMITED
# ==============================================
check_password_reuse() {
  if grep -q "remember" /etc/pam.d/system-auth 2>/dev/null; then
    log_result "PASS" "5.5.3 - Ensure password reuse is limited" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.3 - Ensure password reuse is limited" "remember option not configured in pam_unix.so" "$RED"
  return 1
}

# ==============================================
# 5.5.4 - ENSURE PASSWORD HASHING ALGORITHM IS SHA-512
# ==============================================
check_password_hashing() {
  if grep -q "ENCRYPT_METHOD SHA512" /etc/login.defs 2>/dev/null; then
    log_result "PASS" "5.5.4 - Ensure password hashing algorithm is SHA-512" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.5.4 - Ensure password hashing algorithm is SHA-512" "ENCRYPT_METHOD not set to SHA512" "$RED"
  return 1
}

# ==============================================
# 5.6.1.1 - ENSURE PASSWORD EXPIRATION IS 365 DAYS OR LESS
# ==============================================
check_password_expiration() {
  local max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
  if [ -n "$max_days" ] && [ "$max_days" -le 365 ] && [ "$max_days" -gt 0 ]; then
    log_result "PASS" "5.6.1.1 - Ensure password expiration is 365 days or less" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.1 - Ensure password expiration is 365 days or less" "PASS_MAX_DAYS: $max_days" "$RED"
  return 1
}

# ==============================================
# 5.6.1.2 - ENSURE MINIMUM DAYS BETWEEN PASSWORD CHANGES IS 7 OR MORE
# ==============================================
check_password_min_days() {
  local min_days=$(grep "^PASS_MIN_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}')
  if [ -n "$min_days" ] && [ "$min_days" -ge 7 ]; then
    log_result "PASS" "5.6.1.2 - Ensure minimum days between password changes is 7 or more" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.2 - Ensure minimum days between password changes is 7 or more" "PASS_MIN_DAYS: $min_days" "$RED"
  return 1
}

# ==============================================
# 5.6.1.3 - ENSURE PASSWORD EXPIRATION WARNING DAYS IS 7 OR MORE
# ==============================================
check_password_warn_age() {
  local warn_age=$(grep "^PASS_WARN_AGE" /etc/login.defs 2>/dev/null | awk '{print $2}')
  if [ -n "$warn_age" ] && [ "$warn_age" -ge 7 ]; then
    log_result "PASS" "5.6.1.3 - Ensure password expiration warning days is 7 or more" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.3 - Ensure password expiration warning days is 7 or more" "PASS_WARN_AGE: $warn_age" "$RED"
  return 1
}

# ==============================================
# 5.6.1.4 - ENSURE INACTIVE PASSWORD LOCK IS 30 DAYS OR LESS
# ==============================================
check_password_inactive() {
  local inactive=$(useradd -D 2>/dev/null | grep INACTIVE | cut -d= -f2)
  if [ -n "$inactive" ] && [ "$inactive" -le 30 ] && [ "$inactive" -ge 0 ]; then
    log_result "PASS" "5.6.1.4 - Ensure inactive password lock is 30 days or less" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "5.6.1.4 - Ensure inactive password lock is 30 days or less" "INACTIVE: $inactive" "$RED"
  return 1
}

# ==============================================
# 6.1.1 - ENSURE PERMISSIONS ON /etc/passwd ARE CONFIGURED
# ==============================================
check_passwd_perms() {
  local perms=$(stat -c "%a" /etc/passwd 2>/dev/null)
  if [ "$perms" = "644" ]; then
    log_result "PASS" "6.1.1 - Ensure permissions on /etc/passwd are configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.1 - Ensure permissions on /etc/passwd are configured" "Permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 6.1.2 - ENSURE PERMISSIONS ON /etc/passwd- ARE CONFIGURED
# ==============================================
check_passwd_dash_perms() {
  if [ -f /etc/passwd- ]; then
    local perms=$(stat -c "%a" /etc/passwd- 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "6.1.2 - Ensure permissions on /etc/passwd- are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "PASS" "6.1.2 - Ensure permissions on /etc/passwd- are configured" "File does not exist" "$GREEN"
  return 0
}

# ==============================================
# 6.1.3 - ENSURE PERMISSIONS ON /etc/group ARE CONFIGURED
# ==============================================
check_group_perms() {
  local perms=$(stat -c "%a" /etc/group 2>/dev/null)
  if [ "$perms" = "644" ]; then
    log_result "PASS" "6.1.3 - Ensure permissions on /etc/group are configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.3 - Ensure permissions on /etc/group are configured" "Permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 6.1.4 - ENSURE PERMISSIONS ON /etc/group- ARE CONFIGURED
# ==============================================
check_group_dash_perms() {
  if [ -f /etc/group- ]; then
    local perms=$(stat -c "%a" /etc/group- 2>/dev/null)
    if [ "$perms" = "644" ]; then
      log_result "PASS" "6.1.4 - Ensure permissions on /etc/group- are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "PASS" "6.1.4 - Ensure permissions on /etc/group- are configured" "File does not exist" "$GREEN"
  return 0
}

# ==============================================
# 6.1.5 - ENSURE PERMISSIONS ON /etc/shadow
# ==============================================
check_shadow_perms() {
  local perms=$(stat -c "%a" /etc/shadow 2>/dev/null)
  if [ "$perms" = "0" ]; then
    log_result "PASS" "6.1.5 - Ensure permissions on /etc/shadow are configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.5 - Ensure permissions on /etc/shadow are configured" "Permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 6.1.6 - ENSURE PERMISSIONS ON /etc/shadow-
# ==============================================
check_shadow_dash_perms() {
  if [ -f /etc/shadow- ]; then
    local perms=$(stat -c "%a" /etc/shadow- 2>/dev/null)
    if [ "$perms" = "0" ]; then
      log_result "PASS" "6.1.6 - Ensure permissions on /etc/shadow- are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "PASS" "6.1.6 - Ensure permissions on /etc/shadow- are configured" "File does not exist" "$GREEN"
  return 0
}

# ==============================================
# 6.1.7 - ENSURE PERMISSIONS ON /etc/gshadow
# ==============================================
check_gshadow_perms() {
  local perms=$(stat -c "%a" /etc/gshadow 2>/dev/null)
  if [ "$perms" = "0" ]; then
    log_result "PASS" "6.1.7 - Ensure permissions on /etc/gshadow are configured" "" "$GREEN"
    return 0
  fi
  log_result "FAIL" "6.1.7 - Ensure permissions on /etc/gshadow are configured" "Permissions: $perms" "$RED"
  return 1
}

# ==============================================
# 6.1.8 - ENSURE PERMISSIONS ON /etc/gshadow-
# ==============================================
check_gshadow_dash_perms() {
  if [ -f /etc/gshadow- ]; then
    local perms=$(stat -c "%a" /etc/gshadow- 2>/dev/null)
    if [ "$perms" = "0" ]; then
      log_result "PASS" "6.1.8 - Ensure permissions on /etc/gshadow- are configured" "" "$GREEN"
      return 0
    fi
  fi
  log_result "PASS" "6.1.8 - Ensure permissions on /etc/gshadow- are configured" "File does not exist" "$GREEN"
  return 0
}

# ==============================================
# 6.2.1 - ENSURE ACCOUNTS IN /etc/passwd USE SHADOWED PASSWORDS
# ==============================================
check_shadowed_passwords() {
  if grep -q "^[^:]*:[^x][^:]*:" /etc/passwd 2>/dev/null; then
    log_result "FAIL" "6.2.1 - Ensure accounts in /etc/passwd use shadowed passwords" "Some accounts don't use shadowed passwords" "$RED"
    return 1
  fi
  log_result "PASS" "6.2.1 - Ensure accounts in /etc/passwd use shadowed passwords" "" "$GREEN"
  return 0
}

# ==============================================
# 6.2.2 - ENSURE /etc/shadow PASSWORD FIELDS ARE NOT EMPTY
# ==============================================
check_shadow_empty() {
  if grep -q "^[^:]*::" /etc/shadow 2>/dev/null; then
    log_result "FAIL" "6.2.2 - Ensure /etc/shadow password fields are not empty" "Accounts with empty password found" "$RED"
    return 1
  fi
  log_result "PASS" "6.2.2 - Ensure /etc/shadow password fields are not empty" "" "$GREEN"
  return 0
}

# ==============================================
# 6.2.9 - ENSURE ROOT IS THE ONLY UID 0 ACCOUNT
# ==============================================
check_unique_uid0() {
  if grep -v "^root:" /etc/passwd 2>/dev/null | grep -q ":0:"; then
    log_result "FAIL" "6.2.9 - Ensure root is the only UID 0 account" "Other accounts with UID 0 found" "$RED"
    return 1
  fi
  log_result "PASS" "6.2.9 - Ensure root is the only UID 0 account" "" "$GREEN"
  return 0
}

# ==============================================
# MOSTRAR RESUMEN FINAL
# ==============================================
show_final_summary() {
  local total=$TOTAL_TESTS
  local percentage=$((PASSED * 100 / total))

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  CIS BENCHMARK VERIFICATION COMPLETED${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN FINAL:${NC}"
  echo -e "  • Tests PASADOS: ${GREEN}${PASSED}${NC}"
  echo -e "  • Tests FALLADOS: ${RED}${FAILED}${NC}"
  echo -e "  • Tests WARNING: ${YELLOW}${WARN}${NC}"
  echo -e "  • Total tests: ${BLUE}${total}${NC}"
  echo -e "\n${YELLOW}Porcentaje de cumplimiento: ${GREEN}${percentage}%${NC}"

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
  echo -e "${GREEN}  CIS Benchmark Verification Tool${NC}"
  echo -e "${GREEN}  Para RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Limpiar reporte anterior
  echo "CIS Benchmark Verification Report" >"$REPORT_FILE"
  echo "Fecha: $(date)" >>"$REPORT_FILE"
  echo "=============================================" >>"$REPORT_FILE"
  echo "" >>"$REPORT_FILE"

  # Seccion 1.1 - Filesystem Configuration
  echo -e "\n${BLUE}=== Seccion 1.1 - Filesystem Configuration ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.1.1.1 - squashfs disabled" check_squashfs
  run_test "1.1.1.2 - udf disabled" check_udf
  run_test "1.1.2.1 - /tmp separate partition" check_tmp_partition
  run_test "1.1.2.2 - /tmp nodev" check_tmp_nodev
  run_test "1.1.2.3 - /tmp noexec" check_tmp_noexec
  run_test "1.1.2.4 - /tmp nosuid" check_tmp_nosuid
  run_test "1.1.3.1 - /var separate partition" check_var_partition
  run_test "1.1.3.2 - /var nodev" check_var_nodev
  run_test "1.1.3.3 - /var nosuid" check_var_nosuid
  run_test "1.1.4.1 - /var/tmp separate partition" check_var_tmp_partition
  run_test "1.1.4.2 - /var/tmp noexec" check_var_tmp_noexec
  run_test "1.1.4.3 - /var/tmp nosuid" check_var_tmp_nosuid
  run_test "1.1.4.4 - /var/tmp nodev" check_var_tmp_nodev
  run_test "1.1.5.1 - /var/log separate partition" check_var_log_partition
  run_test "1.1.5.2 - /var/log nodev" check_var_log_nodev
  run_test "1.1.5.3 - /var/log noexec" check_var_log_noexec
  run_test "1.1.5.4 - /var/log nosuid" check_var_log_nosuid
  run_test "1.1.6.1 - /var/log/audit separate partition" check_var_log_audit_partition
  run_test "1.1.6.2 - /var/log/audit noexec" check_var_log_audit_noexec
  run_test "1.1.6.3 - /var/log/audit nodev" check_var_log_audit_nodev
  run_test "1.1.6.4 - /var/log/audit nosuid" check_var_log_audit_nosuid
  run_test "1.1.7.1 - /home separate partition" check_home_partition
  run_test "1.1.7.2 - /home nodev" check_home_nodev
  run_test "1.1.7.3 - /home nosuid" check_home_nosuid
  run_test "1.1.8.1 - /dev/shm separate partition" check_dev_shm_partition
  run_test "1.1.8.2 - /dev/shm nodev" check_dev_shm_nodev
  run_test "1.1.8.3 - /dev/shm noexec" check_dev_shm_noexec
  run_test "1.1.8.4 - /dev/shm nosuid" check_dev_shm_nosuid
  run_test "1.1.9 - USB storage disabled" check_usb_storage

  # Seccion 1.2 - Package Management
  echo -e "\n${BLUE}=== Seccion 1.2 - Package Management ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.2.2 - gpgcheck activated" check_gpgcheck

  # Seccion 1.3 - AIDE
  echo -e "\n${BLUE}=== Seccion 1.3 - AIDE ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.3.1 - AIDE installed" check_aide
  run_test "1.3.2 - AIDE regular check" check_aide_timer

  # Seccion 1.4 - Bootloader
  echo -e "\n${BLUE}=== Seccion 1.4 - Bootloader ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.4.1 - Bootloader password" check_grub_password
  run_test "1.4.2 - Bootloader permissions" check_grub_permissions

  # Seccion 1.5 - Core Dumps
  echo -e "\n${BLUE}=== Seccion 1.5 - Core Dumps ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.5.1 - Core dump storage disabled" check_coredump_storage
  run_test "1.5.2 - Core dump backtraces disabled" check_coredump_backtraces

  # Seccion 1.6 - SELinux
  echo -e "\n${BLUE}=== Seccion 1.6 - SELinux ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.6.1.1 - SELinux installed" check_selinux_installed
  run_test "1.6.1.2 - SELinux not disabled in bootloader" check_selinux_bootloader
  run_test "1.6.1.3 - SELinux policy configured" check_selinux_policy
  run_test "1.6.1.4 - SELinux mode not disabled" check_selinux_mode
  run_test "1.6.1.5 - SELinux mode enforcing" check_selinux_enforcing
  run_test "1.6.1.6 - No unconfined services" check_unconfined_services
  run_test "1.6.1.7 - SETroubleshoot not installed" check_setroubleshoot
  run_test "1.6.1.8 - mcstrans not installed" check_mcstrans

  # Seccion 1.7 - Warning Banners
  echo -e "\n${BLUE}=== Seccion 1.7 - Warning Banners ===${NC}" | tee -a "$REPORT_FILE"
  run_test "1.7.1 - MOTD configured" check_motd
  run_test "1.7.2 - Local login banner" check_issue
  run_test "1.7.3 - Remote login banner" check_issue_net
  run_test "1.7.4 - MOTD permissions" check_motd_perms
  run_test "1.7.5 - issue permissions" check_issue_perms
  run_test "1.7.6 - issue.net permissions" check_issue_net_perms

  # Seccion 2.1 - Time Synchronization
  echo -e "\n${BLUE}=== Seccion 2.1 - Time Synchronization ===${NC}" | tee -a "$REPORT_FILE"
  run_test "2.1.1 - Time synchronization in use" check_chrony

  # Seccion 2.2 - Special Purpose Services
  echo -e "\n${BLUE}=== Seccion 2.2 - Special Purpose Services ===${NC}" | tee -a "$REPORT_FILE"
  run_test "2.2.1 - X Window not installed" check_xwindow
  run_test "2.2.2 - Avahi not installed" check_avahi
  run_test "2.2.3 - CUPS not installed" check_cups
  run_test "2.2.4 - DHCP server not installed" check_dhcp
  run_test "2.2.5 - DNS server not installed" check_dns
  run_test "2.2.6 - VSFTP server not installed" check_vsftpd
  run_test "2.2.7 - TFTP server not installed" check_tftp_server
  run_test "2.2.8 - Web server not installed" check_webserver
  run_test "2.2.9 - IMAP/POP3 not installed" check_imap_pop3
  run_test "2.2.10 - Samba not installed" check_samba
  run_test "2.2.11 - HTTP proxy not installed" check_squid
  run_test "2.2.12 - SNMP not installed" check_snmp
  run_test "2.2.13 - Telnet server not installed" check_telnet_server
  run_test "2.2.14 - dnsmasq not installed" check_dnsmasq
  run_test "2.2.15 - MTA local-only mode" check_mta_local
  run_test "2.2.16 - NFS not installed or masked" check_nfs
  run_test "2.2.17 - rpcbind not installed or masked" check_rpcbind

  # Seccion 2.3 - Clients
  echo -e "\n${BLUE}=== Seccion 2.3 - Clients ===${NC}" | tee -a "$REPORT_FILE"
  run_test "2.3.1 - Telnet client not installed" check_telnet_client
  run_test "2.3.2 - LDAP client not installed" check_ldap_client
  run_test "2.3.3 - TFTP client not installed" check_tftp_client
  run_test "2.3.4 - FTP client not installed" check_ftp_client

  # Seccion 3.1 - Network Parameters
  echo -e "\n${BLUE}=== Seccion 3.1 - Network Parameters ===${NC}" | tee -a "$REPORT_FILE"
  run_test "3.1.3 - TIPC disabled" check_tipc

  # Seccion 3.4 - Firewall
  echo -e "\n${BLUE}=== Seccion 3.4 - Firewall ===${NC}" | tee -a "$REPORT_FILE"
  run_test "3.4.1.1 - nftables installed" check_nftables

  # Seccion 4.1 - Auditd
  echo -e "\n${BLUE}=== Seccion 4.1 - Auditd ===${NC}" | tee -a "$REPORT_FILE"
  run_test "4.1.1.1 - auditd installed" check_auditd_installed
  run_test "4.1.1.2 - auditd boot parameter" check_audit_boot
  run_test "4.1.1.3 - audit_backlog_limit" check_audit_backlog
  run_test "4.1.1.4 - auditd enabled" check_auditd_enabled
  run_test "4.1.2.1 - audit log size" check_audit_log_size
  run_test "4.1.2.2 - audit logs not deleted" check_audit_log_keep
  run_test "4.1.2.3 - audit full action" check_audit_full_action
  run_test "4.1.3.1 - audit sudoers" check_audit_sudoers
  run_test "4.1.3.2 - audit user emulation" check_audit_user_emulation
  run_test "4.1.3.4 - audit time changes" check_audit_time
  run_test "4.1.3.5 - audit network changes" check_audit_network
  run_test "4.1.3.8 - audit identity changes" check_audit_identity
  run_test "4.1.3.10 - audit mounts" check_audit_mounts
  run_test "4.1.3.11 - audit session" check_audit_session
  run_test "4.1.3.12 - audit logins" check_audit_logins
  run_test "4.1.3.13 - audit file deletion" check_audit_delete
  run_test "4.1.3.14 - audit MAC changes" check_audit_mac
  run_test "4.1.3.19 - audit kernel modules" check_audit_modules
  run_test "4.1.3.20 - audit immutable" check_audit_immutable

  # Seccion 5.1 - Cron and At
  echo -e "\n${BLUE}=== Seccion 5.1 - Cron and At ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.1.1 - cron enabled" check_cron_enabled
  run_test "5.1.2 - crontab permissions" check_crontab_perms
  run_test "5.1.3 - cron.hourly permissions" check_cron_hourly_perms
  run_test "5.1.4 - cron.daily permissions" check_cron_daily_perms
  run_test "5.1.5 - cron.weekly permissions" check_cron_weekly_perms
  run_test "5.1.6 - cron.monthly permissions" check_cron_monthly_perms
  run_test "5.1.7 - cron.d permissions" check_cron_d_perms
  run_test "5.1.8 - cron restricted" check_cron_restricted
  run_test "5.1.9 - at restricted" check_at_restricted

  # Seccion 5.2 - SSH
  echo -e "\n${BLUE}=== Seccion 5.2 - SSH ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.2.1 - sshd_config permissions" check_sshd_perms
  run_test "5.2.4 - SSH access limited" check_ssh_access
  run_test "5.2.5 - SSH LogLevel" check_ssh_loglevel
  run_test "5.2.6 - SSH PAM enabled" check_ssh_pam
  run_test "5.2.7 - SSH root login disabled" check_ssh_root_login
  run_test "5.2.8 - SSH HostbasedAuthentication disabled" check_ssh_hostbased
  run_test "5.2.9 - SSH PermitEmptyPasswords disabled" check_ssh_empty_pass
  run_test "5.2.10 - SSH PermitUserEnvironment disabled" check_ssh_user_env
  run_test "5.2.11 - SSH IgnoreRhosts enabled" check_ssh_ignorerhosts
  run_test "5.2.12 - SSH X11 forwarding disabled" check_ssh_x11
  run_test "5.2.13 - SSH AllowTcpForwarding disabled" check_ssh_tcp_forward
  run_test "5.2.15 - SSH warning banner" check_ssh_banner
  run_test "5.2.16 - SSH MaxAuthTries" check_ssh_maxauth
  run_test "5.2.18 - SSH MaxSessions" check_ssh_maxsessions
  run_test "5.2.19 - SSH LoginGraceTime" check_ssh_grace_time
  run_test "5.2.20 - SSH idle timeout" check_ssh_idle_timeout

  # Seccion 5.3 - Sudo
  echo -e "\n${BLUE}=== Seccion 5.3 - Sudo ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.3.1 - sudo installed" check_sudo_installed
  run_test "5.3.2 - sudo use_pty" check_sudo_pty
  run_test "5.3.3 - sudo logfile" check_sudo_logfile
  run_test "5.3.6 - sudo timeout" check_sudo_timeout
  run_test "5.3.7 - su restricted" check_su_restricted

  # Seccion 5.5 - Password Policies
  echo -e "\n${BLUE}=== Seccion 5.5 - Password Policies ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.5.1 - password creation requirements" check_password_requirements
  run_test "5.5.2 - password lockout" check_password_lockout
  run_test "5.5.3 - password reuse limited" check_password_reuse
  run_test "5.5.4 - password hashing SHA-512" check_password_hashing

  # Seccion 5.6 - Password Expiration
  echo -e "\n${BLUE}=== Seccion 5.6 - Password Expiration ===${NC}" | tee -a "$REPORT_FILE"
  run_test "5.6.1.1 - password expiration 365 days" check_password_expiration
  run_test "5.6.1.2 - minimum password days 7" check_password_min_days
  run_test "5.6.1.3 - password warning days 7" check_password_warn_age
  run_test "5.6.1.4 - inactive password lock 30 days" check_password_inactive

  # Seccion 6.1 - File Permissions
  echo -e "\n${BLUE}=== Seccion 6.1 - File Permissions ===${NC}" | tee -a "$REPORT_FILE"
  run_test "6.1.1 - /etc/passwd permissions" check_passwd_perms
  run_test "6.1.2 - /etc/passwd- permissions" check_passwd_dash_perms
  run_test "6.1.3 - /etc/group permissions" check_group_perms
  run_test "6.1.4 - /etc/group- permissions" check_group_dash_perms
  run_test "6.1.5 - /etc/shadow permissions" check_shadow_perms
  run_test "6.1.6 - /etc/shadow- permissions" check_shadow_dash_perms
  run_test "6.1.7 - /etc/gshadow permissions" check_gshadow_perms
  run_test "6.1.8 - /etc/gshadow- permissions" check_gshadow_dash_perms

  # Seccion 6.2 - User Accounts
  echo -e "\n${BLUE}=== Seccion 6.2 - User Accounts ===${NC}" | tee -a "$REPORT_FILE"
  run_test "6.2.1 - shadowed passwords" check_shadowed_passwords
  run_test "6.2.2 - no empty passwords" check_shadow_empty
  run_test "6.2.9 - unique UID 0" check_unique_uid0

  show_final_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
