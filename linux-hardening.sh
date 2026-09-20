#!/bin/bash
# OrangeBox Linux Hardening - Mega Script
# Version 1.0.0 - RHEL/CentOS/Rocky/AlmaLinux 6-10
# AUDIT by default. --fix applies conservative controls only.
# SSH crypto is configured directly in OpenSSH.
# IMPORTANT: update-crypto-policies and /etc/crypto-policies are NEVER touched.

set -u
VERSION=1.0.0
AUTO_FIX=false
MODULE=all
RUN_ID=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/var/backups/orangebox-linux-hardening/$RUN_ID
FIXED=0
WARNINGS=0
ERRORS=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok(){ echo -e "$GREEN[OK]$NC $*"; }
warn(){ WARNINGS=$((WARNINGS+1)); echo -e "$YELLOW[WARN]$NC $*"; }
bad(){ WARNINGS=$((WARNINGS+1)); echo -e "$RED[FAIL]$NC $*"; }
die(){ ERRORS=$((ERRORS+1)); echo -e "$RED[ERROR]$NC $*"; exit 1; }

require_root(){ [ "$EUID" -eq 0 ] || die "Debe ejecutarse como root."; }
detect_os(){
  [ -r /etc/os-release ] || die "No se pudo detectar el sistema."
  . /etc/os-release
  OS_ID=$ID
  OS_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
  case "$OS_ID" in rhel|centos|rocky|almalinux|ol|oracle) ;; *) [[ "$ID_LIKE" == *rhel* ]] || die "Distribución no soportada: $OS_ID";; esac
  case "$OS_VERSION" in 6|7|8|9|10) ;; *) die "Versión no soportada: $OS_VERSION";; esac
  ok "Detectado: $OS_ID $OS_VERSION"
}
prepare_backup(){ mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"; }
backup_once(){
  src=$1; [ -e "$src" ] || return
  rel=$(echo "$src" | sed 's#^/##'); dst="$BACKUP_DIR/$rel"
  [ -e "$dst" ] && return
  mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"
}
set_sysctl(){
  key=$1; value=$2; file=/etc/sysctl.d/99-orangebox-hardening.conf
  current=$(sysctl -n "$key" 2>/dev/null || true)
  [ "$current" = "$value" ] && { ok "$key=$value"; return; }
  warn "$key actual=$current requerido=$value"
  $AUTO_FIX || return
  backup_once "$file"; touch "$file"
  if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$file"; then sed -ri "s|^[[:space:]]*$key[[:space:]]*=.*|$key = $value|" "$file"; else echo "$key = $value" >> "$file"; fi
  sysctl -w "$key=$value" >/dev/null 2>&1 || warn "No se pudo aplicar $key en runtime"
  FIXED=$((FIXED+1))
}

ssh_supported(){ sshd -T 2>/dev/null | awk -v k="$1" '$1==k{$1="";sub(/^ /,"");print;exit}'; }
filter_algorithms(){
  supported=$1; shift; result=
  for alg in "$@"; do
    echo "$supported" | tr ',' '\n' | grep -Fxq "$alg" || continue
    [ -n "$result" ] && result="$result,"
    result="$result$alg"
  done
  echo "$result"
}
ssh_module(){
  echo -e "\n$BLUE### SSH ###$NC"
  [ -f /etc/ssh/sshd_config ] || { warn "sshd_config no existe"; return; }
  backup_once /etc/ssh/sshd_config
  perms=$(stat -c %a /etc/ssh/sshd_config 2>/dev/null || true)
  [ "$perms" = 600 ] && ok "sshd_config permisos 600" || warn "sshd_config permisos=$perms"
  command -v sshd >/dev/null 2>&1 || { warn "sshd no disponible"; return; }

  ciphers=$(filter_algorithms "$(ssh_supported ciphers)" chacha20-poly1305@openssh.com aes256-gcm@openssh.com aes128-gcm@openssh.com aes256-ctr aes192-ctr aes128-ctr)
  kex=$(filter_algorithms "$(ssh_supported kexalgorithms)" curve25519-sha256 curve25519-sha256@libssh.org diffie-hellman-group18-sha512 diffie-hellman-group16-sha512 diffie-hellman-group-exchange-sha256)
  macs=$(filter_algorithms "$(ssh_supported macs)" hmac-sha2-512-etm@openssh.com hmac-sha2-256-etm@openssh.com umac-128-etm@openssh.com hmac-sha2-512 hmac-sha2-256)

  [ -n "$ciphers" ] && ok "Ciphers soportados: $ciphers" || warn "No hay ciphers aprobados disponibles"
  [ -n "$kex" ] && ok "KEX soportados: $kex" || warn "No hay KEX aprobados disponibles"
  [ -n "$macs" ] && ok "MACs soportados: $macs" || warn "No hay MACs aprobados disponibles"
  $AUTO_FIX || return

  file=/etc/ssh/sshd_config
  [ "$OS_VERSION" -ge 8 ] && [ -d /etc/ssh/sshd_config.d ] && file=/etc/ssh/sshd_config.d/49-orangebox-hardening.conf
  backup_once "$file"
  {
    echo "# OrangeBox Linux Hardening $VERSION"
    echo "# System-wide crypto-policies intentionally untouched."
    [ -n "$kex" ] && echo "KexAlgorithms $kex"
    [ -n "$ciphers" ] && echo "Ciphers $ciphers"
    [ -n "$macs" ] && echo "MACs $macs"
    echo "X11Forwarding no"
    echo "IgnoreRhosts yes"
    echo "HostbasedAuthentication no"
    echo "PermitUserEnvironment no"
    echo "PermitEmptyPasswords no"
    echo "GSSAPIAuthentication no"
    echo "KerberosAuthentication no"
    echo "MaxAuthTries 4"
    echo "LoginGraceTime 60"
    echo "ClientAliveInterval 300"
    echo "ClientAliveCountMax 2"
    echo "Compression no"
    echo "LogLevel INFO"
    echo "UsePAM yes"
  } > "$file"
  if sshd -t >/dev/null 2>&1; then ok "sshd -t válido"; FIXED=$((FIXED+1)); else bad "sshd -t falló; se elimina configuración generada"; rm -f "$file"; fi
}

sudo_module(){
  echo -e "\n$BLUE### SUDO ###$NC"
  command -v visudo >/dev/null 2>&1 || { warn "visudo no disponible"; return; }
  visudo -cf /etc/sudoers >/dev/null 2>&1 && ok "sudoers válido" || bad "sudoers inválido"
  grep -RqsE '^[[:space:]]*Defaults[[:space:]]+use_pty' /etc/sudoers /etc/sudoers.d 2>/dev/null && ok "use_pty habilitado" || warn "use_pty no configurado"
  if $AUTO_FIX && ! grep -RqsE '^[[:space:]]*Defaults[[:space:]]+use_pty' /etc/sudoers /etc/sudoers.d 2>/dev/null; then
    f=/etc/sudoers.d/99-orangebox-hardening; backup_once "$f"; echo 'Defaults use_pty' > "$f"; chmod 440 "$f"; chown root:root "$f"
    visudo -cf "$f" >/dev/null 2>&1 && FIXED=$((FIXED+1)) || rm -f "$f"
  fi
}

password_module(){
  echo -e "\n$BLUE### PASSWORD / PAM ###$NC"
  [ -f /etc/login.defs ] || return
  max=$(awk '$1=="PASS_MAX_DAYS"{print $2}' /etc/login.defs | tail -1)
  min=$(awk '$1=="PASS_MIN_DAYS"{print $2}' /etc/login.defs | tail -1)
  warnage=$(awk '$1=="PASS_WARN_AGE"{print $2}' /etc/login.defs | tail -1)
  [ -n "$max" ] && [ "$max" -le 365 ] 2>/dev/null && ok "PASS_MAX_DAYS=$max" || warn "PASS_MAX_DAYS no cumple"
  [ -n "$min" ] && [ "$min" -ge 1 ] 2>/dev/null && ok "PASS_MIN_DAYS=$min" || warn "PASS_MIN_DAYS no cumple"
  [ -n "$warnage" ] && [ "$warnage" -ge 7 ] 2>/dev/null && ok "PASS_WARN_AGE=$warnage" || warn "PASS_WARN_AGE no cumple"
  command -v authselect >/dev/null 2>&1 && ok "authselect detectado; PAM no se edita a ciegas" || warn "authselect no detectado; revisar PAM según release"
  [ -f /etc/security/pwquality.conf ] && grep -Eq '^[[:space:]]*minlen[[:space:]]*=[[:space:]]*(1[4-9]|[2-9][0-9])' /etc/security/pwquality.conf && ok "pwquality minlen >=14" || warn "pwquality minlen no verificado"
}

kernel_module(){
  echo -e "\n$BLUE### KERNEL / SYSCTL ###$NC"
  set_sysctl fs.suid_dumpable 0; set_sysctl kernel.dmesg_restrict 1; set_sysctl kernel.kptr_restrict 2
  set_sysctl kernel.randomize_va_space 2; set_sysctl fs.protected_fifos 1; set_sysctl fs.protected_hardlinks 1
  set_sysctl fs.protected_symlinks 1; set_sysctl net.ipv4.conf.all.accept_redirects 0
  set_sysctl net.ipv4.conf.default.accept_redirects 0; set_sysctl net.ipv4.conf.all.send_redirects 0
  set_sysctl net.ipv4.conf.default.send_redirects 0; set_sysctl net.ipv4.tcp_syncookies 1
}

filesystem_module(){
  echo -e "\n$BLUE### FILESYSTEM ###$NC"
  for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    [ -e "$f" ] || continue; p=$(stat -c %a "$f")
    case "$f" in /etc/passwd|/etc/group) [ "$p" -le 644 ] 2>/dev/null && ok "$f=$p" || warn "$f=$p";;
    *) [ "$p" = 600 ] || [ "$p" = 640 ] || [ "$p" = 0 ] && ok "$f=$p" || warn "$f=$p";; esac
  done
}

auditd_module(){
  echo -e "\n$BLUE### AUDITD ###$NC"
  command -v auditctl >/dev/null 2>&1 || { warn "auditd no instalado"; return; }
  systemctl is-enabled auditd >/dev/null 2>&1 && ok "auditd habilitado" || warn "auditd no habilitado"
  systemctl is-active auditd >/dev/null 2>&1 && ok "auditd activo" || warn "auditd no activo"
  [ -d /etc/audit/rules.d ] && ok "rules.d disponible" || warn "rules.d no existe"
}

rsyslog_module(){
  echo -e "\n$BLUE### RSYSLOG / JOURNAL ###$NC"
  command -v rsyslogd >/dev/null 2>&1 && ok "rsyslog instalado" || warn "rsyslog no instalado"
  systemctl is-active rsyslog >/dev/null 2>&1 && ok "rsyslog activo" || warn "rsyslog no activo"
  [ -d /var/log/journal ] && ok "journal persistente" || warn "/var/log/journal no existe"
  if $AUTO_FIX && [ -f /etc/systemd/journald.conf ]; then
    f=/etc/systemd/journald.conf; backup_once "$f"
    if grep -Eq '^[[:space:]]*Storage=' "$f"; then sed -ri 's/^[[:space:]]*Storage=.*/Storage=persistent/' "$f"; else echo 'Storage=persistent' >> "$f"; fi
    mkdir -p /var/log/journal; systemctl restart systemd-journald >/dev/null 2>&1 || warn "No se pudo reiniciar journald"; FIXED=$((FIXED+1))
  fi
}

selinux_module(){
  echo -e "\n$BLUE### SELINUX ###$NC"
  command -v getenforce >/dev/null 2>&1 || { warn "SELinux no disponible"; return; }
  mode=$(getenforce); [ "$mode" = Enforcing ] && ok "SELinux Enforcing" || warn "SELinux=$mode"
  if $AUTO_FIX && [ -f /etc/selinux/config ] && [ "$mode" != Enforcing ]; then
    backup_once /etc/selinux/config; sed -ri 's/^[[:space:]]*SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config; FIXED=$((FIXED+1))
  fi
}

cron_module(){
  echo -e "\n$BLUE### CRON / AT ###$NC"
  for f in /etc/cron.allow /etc/at.allow; do [ -e "$f" ] && ok "$f existe" || warn "$f no existe"; done
  if $AUTO_FIX; then for f in /etc/cron.allow /etc/at.allow; do [ -e "$f" ] || { touch "$f"; chmod 600 "$f"; chown root:root "$f"; FIXED=$((FIXED+1)); }; done; fi
}

usb_module(){
  echo -e "\n$BLUE### USB STORAGE ###$NC"
  lsmod 2>/dev/null | grep -q '^usb_storage' && warn "usb_storage cargado" || ok "usb_storage no cargado"
  warn "USB no se bloquea automáticamente; puede romper dispositivos existentes."
}

services_module(){
  echo -e "\n$BLUE### SERVICES / PACKAGES ###$NC"
  for s in telnet.socket xinetd tftp.socket rsh.socket rlogin.socket rexec.socket; do systemctl list-unit-files "$s" 2>/dev/null | grep -q "$s" && warn "Servicio legacy presente: $s"; done
  for p in telnet-server xinetd rsh-server tftp-server; do rpm -q "$p" >/dev/null 2>&1 && warn "Paquete legacy instalado: $p"; done
  warn "No se eliminan paquetes ni servicios automáticamente."
}

banners_module(){
  echo -e "\n$BLUE### BANNERS ###$NC"
  [ -s /etc/issue.net ] && ok "/etc/issue.net configurado" || warn "/etc/issue.net vacío/inexistente"
  if $AUTO_FIX; then backup_once /etc/issue.net; echo 'Sistema de uso autorizado. El acceso no autorizado está prohibido.' > /etc/issue.net; chmod 644 /etc/issue.net; chown root:root /etc/issue.net; FIXED=$((FIXED+1)); fi
}

time_module(){
  echo -e "\n$BLUE### TIME SYNC ###$NC"
  if command -v chronyc >/dev/null 2>&1; then chronyc tracking >/dev/null 2>&1 && ok "chrony operativo" || warn "chrony no responde"
  elif command -v timedatectl >/dev/null 2>&1; then timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qi yes && ok "NTP sincronizado" || warn "NTP no sincronizado"
  else warn "No se detectó NTP/chrony"; fi
}

grub_module(){
  echo -e "\n$BLUE### GRUB ###$NC"
  cfg=$(find /boot /etc -maxdepth 4 -type f -name grub.cfg 2>/dev/null | head -1)
  [ -n "$cfg" ] && ok "grub.cfg=$cfg" || warn "grub.cfg no localizado"
  warn "GRUB no se modifica automáticamente; BIOS/UEFI requiere revisión."
}

firewall_module(){
  echo -e "\n$BLUE### FIREWALL ###$NC"
  if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --state 2>/dev/null | grep -q running && ok "firewalld activo" || warn "firewalld no activo"
  elif command -v nft >/dev/null 2>&1; then nft list ruleset >/dev/null 2>&1 && ok "nftables disponible" || warn "nftables sin ruleset"
  elif command -v iptables >/dev/null 2>&1; then iptables -S 2>/dev/null | head -20
  else warn "No se detectó firewall"; fi
  warn "No se aplican políticas DROP automáticamente."
}

fapolicyd_module(){
  echo -e "\n$BLUE### FAPOLICYD ###$NC"
  rpm -q fapolicyd >/dev/null 2>&1 && systemctl is-active fapolicyd >/dev/null 2>&1 && ok "fapolicyd activo" || warn "fapolicyd ausente/inactivo"
  warn "No se instala/habilita automáticamente."
}

listening_module(){
  echo -e "\n$BLUE### LISTENING SERVICES ###$NC"
  command -v ss >/dev/null 2>&1 && ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null || warn "ss/netstat no disponible"
}

bash_module(){
  echo -e "\n$BLUE### BASH ###$NC"
  [ -d /etc/profile.d ] && ok "/etc/profile.d existe" || warn "/etc/profile.d ausente"
  warn "No se modifican perfiles de usuarios automáticamente."
}

usage(){
  echo "OrangeBox Linux Hardening $VERSION"
  echo "Uso: $0 [--fix] [--module MODULO]"
  echo "Módulos: ssh sudo password kernel filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash"
  echo "Sin --fix solo audita."
  echo "SSH crypto: configuración directa de OpenSSH."
  echo "Crypto-policies globales: NO se modifican."
}

run_module(){
  case "$1" in
    ssh) ssh_module;; sudo) sudo_module;; password) password_module;; kernel) kernel_module;;
    filesystem) filesystem_module;; auditd) auditd_module;; rsyslog) rsyslog_module;; selinux) selinux_module;;
    cron) cron_module;; usb) usb_module;; services) services_module;; banners) banners_module;; time) time_module;;
    grub) grub_module;; firewall) firewall_module;; fapolicyd) fapolicyd_module;; listening) listening_module;; bash) bash_module;;
    *) die "Módulo desconocido: $1";;
  esac
}

main(){
  require_root; detect_os; prepare_backup
  while [ $# -gt 0 ]; do
    case "$1" in
      --fix|-f) AUTO_FIX=true;;
      --module|-m) shift; MODULE=$1;;
      --help|-h) usage; exit 0;;
      --list-modules) echo "ssh sudo password kernel filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash"; exit 0;;
    esac
    shift
  done
  $AUTO_FIX && warn "MODO FIX: controles conservadores" || ok "MODO AUDITORÍA: sin cambios"
  if [ "$MODULE" = all ]; then
    for m in ssh sudo password kernel filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash; do run_module "$m"; done
  else
    run_module "$MODULE"
  fi
  echo -e "\n$GREEN============================================================$NC"
  echo -e "$GREEN OrangeBox Linux Hardening $VERSION - FIN $NC"
  echo "Correcciones: $FIXED"; echo "Advertencias: $WARNINGS"; echo "Errores: $ERRORS"; echo "Backup: $BACKUP_DIR"
  echo -e "$GREEN============================================================$NC"
}
main "$@"
