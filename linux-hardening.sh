#!/bin/bash
# OrangeBox Linux Hardening - Safe Enterprise Baseline
# Version 1.3.0 - RHEL/CentOS/Rocky/AlmaLinux 6-10
# AUDIT by default. --fix applies only controls designed to be operationally safe.
# IMPORTANT: SELinux state is NEVER changed. cron.allow/at.allow are NEVER created.
# IMPORTANT: system-wide crypto-policies are NEVER changed; SSH crypto is audited, not overridden.

set -u
VERSION=1.3.0
AUTO_FIX=false
INTERACTIVE=false
ROLLBACK_TARGET=""
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
  OS_ID=""; OS_VERSION=""; ID_LIKE=""
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    OS_ID=${ID:-}; ID_LIKE=${ID_LIKE:-}; OS_VERSION=$(echo "${VERSION_ID:-}" | cut -d. -f1)
  elif [ -r /etc/redhat-release ]; then
    release=$(cat /etc/redhat-release)
    OS_VERSION=$(printf '%s\n' "$release" | sed -n 's/.*release \([0-9][0-9]*\).*/\1/p' | head -n1)
    case "$release" in *CentOS*) OS_ID=centos;; *Oracle*) OS_ID=oracle;; *Red\ Hat*) OS_ID=rhel;; *) OS_ID=unknown;; esac
    ID_LIKE=rhel
  else
    die "No se pudo detectar sistema."
  fi
  case "$OS_ID" in rhel|centos|rocky|almalinux|ol|oracle) ;; *) [[ "$ID_LIKE" == *rhel* ]] || die "Distribución no soportada: $OS_ID";; esac
  case "$OS_VERSION" in 6|7|8|9|10) ;; *) die "Versión no soportada: $OS_VERSION";; esac
  ok "Detectado: $OS_ID $OS_VERSION"
}
prepare_backup(){ mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"; }
backup_once(){
  local src="$1" rel dst
  [ -e "$src" ] || return 0
  rel=$(echo "$src" | sed 's#^/##'); dst="$BACKUP_DIR/$rel"
  [ -e "$dst" ] && return 0
  mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"
}

set_sysctl(){
  local key="$1" value="$2" file=/etc/sysctl.d/99-orangebox-hardening.conf current
  current=$(sysctl -n "$key" 2>/dev/null || true)
  [ "$current" = "$value" ] && { ok "$key=$value"; return 0; }
  warn "$key actual=$current recomendado=$value"
  $AUTO_FIX || return 0
  backup_once "$file"; touch "$file"
  if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$file"; then
    sed -ri "s|^[[:space:]]*$key[[:space:]]*=.*|$key = $value|" "$file"
  else
    echo "$key = $value" >> "$file"
  fi
  if sysctl -w "$key=$value" >/dev/null 2>&1 && [ "$(sysctl -n "$key" 2>/dev/null || true)" = "$value" ]; then
    ok "$key aplicado/verificado=$value"; FIXED=$((FIXED+1))
  else
    warn "No se pudo aplicar/verificar $key en runtime"
  fi
}

SYNFLOOD_FILE=/etc/sysctl.d/99-orangebox-synflood-hardening.conf
SYNFLOOD_LEGACY_FILE=/etc/sysctl.d/99-cpanel-synflood-hardening.conf
# Conservative values: keep the backlog protection but avoid the aggressive retry reduction (2/2).
SYNFLOOD_KEYS="net.ipv4.tcp_syncookies net.ipv4.tcp_max_syn_backlog net.core.somaxconn net.ipv4.tcp_synack_retries net.ipv4.tcp_syn_retries"
SYNFLOOD_VALUES="1 4096 4096 3 5"

synflood_value(){ local f="$1" k="$2"; awk -v key="$k" '$0 ~ "^[[:space:]]*" key "[[:space:]]*=" {v=$0;sub(/^[^=]*=[[:space:]]*/,"",v);sub(/[[:space:]#].*$/,"",v);got=v} END{if(got!="")print got}' "$f" 2>/dev/null; }
synflood_managed_profile(){
  local f="$1"
  [ -f "$f" ] && grep -Fqx "# OrangeBox managed SYN flood profile" "$f" && grep -Fqx "# BEGIN ORANGEBOX SYNFLOOD" "$f" && grep -Fqx "# END ORANGEBOX SYNFLOOD" "$f"
}

synflood_module(){
  echo -e "\n$BLUE### SYN FLOOD / TCP BACKLOG ###$NC"
  [ -d /etc/sysctl.d ] || { warn "/etc/sysctl.d no existe"; return; }
  local idx=1 key current desired cfg external profile_source="$SYNFLOOD_FILE"
  [ -e "$SYNFLOOD_FILE" ] && ! synflood_managed_profile "$SYNFLOOD_FILE" && { warn "$SYNFLOOD_FILE existe pero no es gestionado por OrangeBox; no se sobrescribe"; return; }
  if [ ! -e "$SYNFLOOD_FILE" ] && synflood_managed_profile "$SYNFLOOD_LEGACY_FILE"; then profile_source="$SYNFLOOD_LEGACY_FILE"; fi

  for key in $SYNFLOOD_KEYS; do
    current=$(sysctl -n "$key" 2>/dev/null || true)
    desired=$(printf '%s\n' "$SYNFLOOD_VALUES" | awk -v n="$idx" 'NR==n{print}')
    [ -n "$current" ] || { warn "$key no existe en el kernel"; idx=$((idx+1)); continue; }
    external=""
    for cfg in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
      [ -f "$cfg" ] || continue
      [ "$cfg" = "$SYNFLOOD_FILE" ] || [ "$cfg" = "$profile_source" ] && continue
      if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$cfg"; then external="$cfg"; break; fi
    done
    if [ -n "$external" ]; then warn "$key definido en $external; se conserva para evitar conflictos"; idx=$((idx+1)); continue; fi
    [ "$current" = "$desired" ] && ok "$key=$desired" || warn "$key actual=$current recomendado=$desired"
    idx=$((idx+1))
  done
  $AUTO_FIX || return 0

  backup_once "$SYNFLOOD_FILE"; [ "$profile_source" = "$SYNFLOOD_FILE" ] || backup_once "$profile_source"
  local tmp; tmp=$(mktemp "$SYNFLOOD_FILE.XXXXXX") || { warn "No se pudo crear temporal"; return; }
  if [ -e "$profile_source" ]; then
    awk '$0=="# BEGIN ORANGEBOX SYNFLOOD"{inside=1;next} $0=="# END ORANGEBOX SYNFLOOD"{inside=0;next} !inside && $0!="# OrangeBox managed SYN flood profile"{print}' "$profile_source" > "$tmp" || { rm -f "$tmp"; warn "No se pudo leer perfil existente"; return; }
  fi
  {
    [ ! -s "$tmp" ] || printf '\n'
    echo '# OrangeBox managed SYN flood profile'
    echo '# BEGIN ORANGEBOX SYNFLOOD'
    idx=1
    for key in $SYNFLOOD_KEYS; do
      desired=$(printf '%s\n' "$SYNFLOOD_VALUES" | awk -v n="$idx" 'NR==n{print}')
      printf '%s = %s\n' "$key" "$desired"
      idx=$((idx+1))
    done
    echo '# END ORANGEBOX SYNFLOOD'
  } >> "$tmp"
  chmod 644 "$tmp"; chown root:root "$tmp" 2>/dev/null || true
  mv "$tmp" "$SYNFLOOD_FILE" || { rm -f "$tmp"; warn "No se pudo instalar perfil"; return; }
  if [ "$profile_source" = "$SYNFLOOD_LEGACY_FILE" ]; then rm -f "$profile_source"; fi
  idx=1
  for key in $SYNFLOOD_KEYS; do
    desired=$(printf '%s\n' "$SYNFLOOD_VALUES" | awk -v n="$idx" 'NR==n{print}')
    if sysctl -w "$key=$desired" >/dev/null 2>&1 && [ "$(sysctl -n "$key" 2>/dev/null || true)" = "$desired" ]; then FIXED=$((FIXED+1)); else warn "No se pudo aplicar/verificar $key"; fi
    idx=$((idx+1))
  done
  ok "SYN flood conservador aplicado: syncookies=1 backlog=4096 somaxconn=4096 synack_retries=3 syn_retries=5"
}

ssh_effective(){ sshd -T 2>/dev/null | awk -v k="$1" '$1==k{$1="";sub(/^ /,"");print;exit}'; }
ssh_module(){
  echo -e "\n$BLUE### SSH ###$NC"
  [ -f /etc/ssh/sshd_config ] || { warn "sshd_config no existe"; return; }
  command -v sshd >/dev/null 2>&1 || { warn "sshd no disponible"; return; }
  backup_once /etc/ssh/sshd_config
  local perms; perms=$(stat -c %a /etc/ssh/sshd_config 2>/dev/null || true)
  [ "$perms" = 600 ] || warn "sshd_config permisos=$perms; no se cambia automáticamente"

  # Do not override RHEL system crypto policy. Audit effective algorithms instead.
  local policy="unknown"
  command -v update-crypto-policies >/dev/null 2>&1 && policy=$(update-crypto-policies --show 2>/dev/null || echo unknown)
  case "$policy" in LEGACY*) warn "Crypto policy=$policy; evaluar migración porque reduce la seguridad";; *) [ "$policy" != unknown ] && ok "Crypto policy=$policy";; esac
  local ciphers kex macs; ciphers=$(ssh_effective ciphers); kex=$(ssh_effective kexalgorithms); macs=$(ssh_effective macs)
  [ -n "$ciphers" ] && ok "Ciphers efectivos auditados" || warn "No se pudieron obtener ciphers efectivos"
  [ -n "$kex" ] && ok "KEX efectivos auditados" || warn "No se pudieron obtener KEX efectivos"
  [ -n "$macs" ] && ok "MACs efectivos auditados" || warn "No se pudieron obtener MACs efectivos"

  local drop=/etc/ssh/sshd_config.d/49-orangebox-hardening.conf
  [ "$OS_VERSION" -ge 8 ] && [ -d /etc/ssh/sshd_config.d ] || drop=/etc/ssh/sshd_config
  if $AUTO_FIX; then
    [ "$drop" != /etc/ssh/sshd_config ] && backup_once "$drop"
    local tmp; tmp=$(mktemp "$drop.XXXXXX") || { warn "No se pudo crear configuración SSH temporal"; return; }
    {
      echo "# OrangeBox Linux Hardening $VERSION"
      echo "# Safe SSH baseline: crypto policy and authentication methods are not overridden."
      echo "IgnoreRhosts yes"
      echo "HostbasedAuthentication no"
      echo "PermitEmptyPasswords no"
      echo "PermitUserEnvironment no"
      echo "MaxAuthTries 6"
      echo "LoginGraceTime 60"
      echo "ClientAliveInterval 300"
      echo "ClientAliveCountMax 2"
      echo "LogLevel INFO"
    } > "$tmp"
    chmod 600 "$tmp"; chown root:root "$tmp" 2>/dev/null || true
    if sshd -t -f "$tmp" >/dev/null 2>&1; then
      if [ "$drop" = /etc/ssh/sshd_config ]; then
        # On old releases, append only safe directives and keep existing configuration intact.
        cat "$tmp" >> "$drop" && rm -f "$tmp"
      else
        mv "$tmp" "$drop"
      fi
      if sshd -t >/dev/null 2>&1; then ok "sshd -t válido después del hardening"; FIXED=$((FIXED+1)); else bad "sshd -t falló; se revierte el drop-in"; [ "$drop" != /etc/ssh/sshd_config ] && rm -f "$drop"; fi
    else
      rm -f "$tmp"; bad "Configuración SSH generada inválida; no se aplica"
    fi
  fi
  local val
  for val in PasswordAuthentication PubkeyAuthentication UsePAM PermitRootLogin AllowUsers AllowGroups; do
    local effective; effective=$(ssh_effective "$(echo "$val" | tr '[:upper:]' '[:lower:]')")
    [ -n "$effective" ] && echo "  $val $effective"
  done
  warn "No se fuerza PasswordAuthentication no, PermitRootLogin, AllowUsers/AllowGroups, forwarding ni GSSAPI/Kerberos: esos cambios pueden romper accesos, integraciones o túneles existentes."
}

sudo_module(){
  echo -e "\n$BLUE### SUDO ###$NC"
  command -v visudo >/dev/null 2>&1 || { warn "visudo no disponible"; return; }
  visudo -cf /etc/sudoers >/dev/null 2>&1 && ok "sudoers válido" || bad "sudoers inválido"
  if grep -RqsE '^[[:space:]]*Defaults[[:space:]]+use_pty' /etc/sudoers /etc/sudoers.d 2>/dev/null; then ok "use_pty habilitado"; elif $AUTO_FIX; then
    local f=/etc/sudoers.d/99-orangebox-hardening; backup_once "$f"; echo 'Defaults use_pty' > "$f"; chmod 440 "$f"; chown root:root "$f"; visudo -cf "$f" >/dev/null 2>&1 && { ok "use_pty habilitado"; FIXED=$((FIXED+1)); } || { rm -f "$f"; warn "No se pudo validar use_pty"; }
  else warn "use_pty no configurado"; fi
}

password_module(){
  echo -e "\n$BLUE### PASSWORD / PAM ###$NC"
  [ -f /etc/login.defs ] || { warn "/etc/login.defs no existe"; return; }
  local max min warnage; max=$(awk '$1=="PASS_MAX_DAYS"{print $2}' /etc/login.defs | tail -1); min=$(awk '$1=="PASS_MIN_DAYS"{print $2}' /etc/login.defs | tail -1); warnage=$(awk '$1=="PASS_WARN_AGE"{print $2}' /etc/login.defs | tail -1)
  [ "$max" = -1 ] || [ "$max" = 0 ] || warn "PASS_MAX_DAYS=$max; la política OrangeBox no debe caducar passwords"
  [ -n "$min" ] && [ "$min" -ge 0 ] 2>/dev/null && ok "PASS_MIN_DAYS=$min" || warn "PASS_MIN_DAYS no verificado"
  [ -n "$warnage" ] && ok "PASS_WARN_AGE=$warnage" || warn "PASS_WARN_AGE no configurado"
  command -v authselect >/dev/null 2>&1 && { authselect current >/dev/null 2>&1 && ok "authselect detectado y operativo; PAM se gestiona mediante authselect" || warn "authselect instalado pero current falló"; } || warn "authselect no detectado; PAM requiere revisión según release"
  [ -f /etc/security/pwquality.conf ] && grep -Eq '^[[:space:]]*minlen[[:space:]]*=[[:space:]]*(1[4-9]|[2-9][0-9])' /etc/security/pwquality.conf && ok "pwquality minlen >=14" || warn "pwquality minlen <14/no configurado"
  grep -Rqs 'pam_faillock.so' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null && ok "pam_faillock ya está configurado" || warn "pam_faillock no configurado; NO se inserta automáticamente para evitar romper PAM"
  getent group wheel >/dev/null 2>&1 && ok "grupo wheel existe" || warn "grupo wheel no existe"
  [ -f /etc/pam.d/su ] && grep -Eq '^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_wheel.so([[:space:]]|$)' /etc/pam.d/su && ok "su restringido a wheel" || warn "su no aparece restringido a wheel"
}

kernel_module(){
  echo -e "\n$BLUE### KERNEL / SYSCTL ###$NC"
  set_sysctl fs.suid_dumpable 0; set_sysctl kernel.dmesg_restrict 1; set_sysctl kernel.kptr_restrict 2
  set_sysctl kernel.randomize_va_space 2; set_sysctl fs.protected_fifos 1; set_sysctl fs.protected_hardlinks 1
  set_sysctl fs.protected_symlinks 1; set_sysctl net.ipv4.conf.all.accept_redirects 0
  set_sysctl net.ipv4.conf.default.accept_redirects 0; set_sysctl net.ipv4.conf.all.send_redirects 0
  set_sysctl net.ipv4.conf.default.send_redirects 0
}

filesystem_module(){
  echo -e "\n$BLUE### FILESYSTEM ###$NC"
  for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    [ -e "$f" ] || continue; local p; p=$(stat -c %a "$f")
    case "$f" in /etc/passwd|/etc/group) [ "$p" -le 644 ] 2>/dev/null && ok "$f=$p" || warn "$f=$p";; *) [ "$p" = 600 ] || [ "$p" = 640 ] || [ "$p" = 0 ] && ok "$f=$p" || warn "$f=$p";; esac
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
    local f=/etc/systemd/journald.conf; backup_once "$f"
    if grep -Eq '^[[:space:]]*Storage=' "$f"; then sed -ri 's/^[[:space:]]*Storage=.*/Storage=persistent/' "$f"; else echo 'Storage=persistent' >> "$f"; fi
    mkdir -p /var/log/journal; systemctl restart systemd-journald >/dev/null 2>&1 || warn "No se pudo reiniciar journald"; FIXED=$((FIXED+1))
  fi
}

selinux_module(){
  echo -e "\n$BLUE### SELINUX ###$NC"
  command -v getenforce >/dev/null 2>&1 || { warn "SELinux no disponible"; return; }
  local mode; mode=$(getenforce)
  [ "$mode" = Enforcing ] && ok "SELinux Enforcing" || warn "SELinux=$mode; no se modifica por política OrangeBox"
}

cron_module(){
  echo -e "\n$BLUE### CRON / AT ###$NC"
  [ -e /etc/cron.allow ] && ok "/etc/cron.allow existe" || warn "/etc/cron.allow no existe; se deja intacto para no romper cPanel"
  [ -e /etc/at.allow ] && ok "/etc/at.allow existe" || warn "/etc/at.allow no existe; se deja intacto"
  warn "No se crean ni modifican cron.allow/at.allow automáticamente"
}

usb_module(){ echo -e "\n$BLUE### USB STORAGE ###$NC"; lsmod 2>/dev/null | grep -q '^usb_storage' && warn "usb_storage cargado" || ok "usb_storage no cargado"; warn "USB no se bloquea automáticamente"; }
services_module(){ echo -e "\n$BLUE### SERVICES / PACKAGES ###$NC"; for s in telnet.socket xinetd tftp.socket rsh.socket rlogin.socket rexec.socket; do systemctl list-unit-files "$s" 2>/dev/null | grep -q "$s" && warn "Servicio legacy presente: $s"; done; for p in telnet-server xinetd rsh-server tftp-server; do rpm -q "$p" >/dev/null 2>&1 && warn "Paquete legacy instalado: $p"; done; warn "No se eliminan paquetes ni servicios automáticamente"; }
banners_module(){ echo -e "\n$BLUE### BANNERS ###$NC"; [ -s /etc/issue.net ] && ok "/etc/issue.net configurado" || warn "/etc/issue.net vacío/inexistente"; if $AUTO_FIX; then backup_once /etc/issue.net; echo 'Sistema de uso autorizado. El acceso no autorizado está prohibido.' > /etc/issue.net; chmod 644 /etc/issue.net; chown root:root /etc/issue.net; FIXED=$((FIXED+1)); fi; }
time_module(){ echo -e "\n$BLUE### TIME SYNC ###$NC"; if command -v chronyc >/dev/null 2>&1; then chronyc tracking >/dev/null 2>&1 && ok "chrony operativo" || warn "chrony no responde"; elif command -v timedatectl >/dev/null 2>&1; then timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qi yes && ok "NTP sincronizado" || warn "NTP no sincronizado"; else warn "No se detectó NTP/chrony"; fi; }
grub_module(){ echo -e "\n$BLUE### GRUB ###$NC"; local cfg; cfg=$(find /boot /etc -maxdepth 4 -type f -name grub.cfg 2>/dev/null | head -1); [ -n "$cfg" ] && ok "grub.cfg=$cfg" || warn "grub.cfg no localizado"; warn "GRUB no se modifica automáticamente"; }
firewall_module(){ echo -e "\n$BLUE### FIREWALL ###$NC"; if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --state 2>/dev/null | grep -q running && ok "firewalld activo" || warn "firewalld no activo"; elif command -v nft >/dev/null 2>&1; then nft list ruleset >/dev/null 2>&1 && ok "nftables disponible" || warn "nftables sin ruleset"; elif command -v iptables >/dev/null 2>&1; then iptables -S 2>/dev/null | head -20; else warn "No se detectó firewall"; fi; warn "No se aplican políticas DROP automáticamente"; }
fapolicyd_module(){ echo -e "\n$BLUE### FAPOLICYD ###$NC"; rpm -q fapolicyd >/dev/null 2>&1 && systemctl is-active fapolicyd >/dev/null 2>&1 && ok "fapolicyd activo" || warn "fapolicyd ausente/inactivo"; warn "No se instala/habilita automáticamente"; }
listening_module(){ echo -e "\n$BLUE### LISTENING SERVICES ###$NC"; command -v ss >/dev/null 2>&1 && ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null || warn "ss/netstat no disponible"; }
bash_module(){ echo -e "\n$BLUE### BASH ###$NC"; [ -d /etc/profile.d ] && ok "/etc/profile.d existe" || warn "/etc/profile.d ausente"; warn "No se modifican perfiles de usuarios automáticamente"; }

usage(){
  echo "OrangeBox Linux Hardening $VERSION"
  echo "Uso: $0 [--fix | --interactive] [--module MODULO]"
  echo "Módulos: ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash"
  echo "SELinux: solo auditoría. cron.allow/at.allow: solo auditoría. Crypto-policies: nunca se modifican."
  echo "SYN flood: syncookies=1 backlog=4096 somaxconn=4096 synack_retries=3 syn_retries=5"
}
run_module(){ case "$1" in ssh) ssh_module;; sudo) sudo_module;; password) password_module;; kernel) kernel_module;; filesystem) filesystem_module;; synflood) synflood_module;; auditd) auditd_module;; rsyslog) rsyslog_module;; selinux) selinux_module;; cron) cron_module;; usb) usb_module;; services) services_module;; banners) banners_module;; time) time_module;; grub) grub_module;; firewall) firewall_module;; fapolicyd) fapolicyd_module;; listening) listening_module;; bash) bash_module;; *) die "Módulo desconocido: $1";; esac; }

main(){
  require_root
  while [ $# -gt 0 ]; do
    case "$1" in
      --fix|-f) AUTO_FIX=true;;
      --interactive|-i) INTERACTIVE=true;;
      --module|-m) shift; [ $# -gt 0 ] || die "--module requiere un nombre"; MODULE=$1;;
      --help|-h) usage; exit 0;;
      --list-modules) echo "ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash"; exit 0;;
      *) die "Argumento desconocido: $1";;
    esac
    shift
  done
  detect_os; prepare_backup
  $INTERACTIVE && warn "MODO INTERACTIVO: esta versión no aplica controles peligrosos de autenticación/SELinux/cron" || true
  $AUTO_FIX && warn "MODO FIX: solo controles conservadores y reversibles" || ok "MODO AUDITORÍA: sin cambios"
  if [ "$MODULE" = all ]; then
    for m in ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash; do run_module "$m"; done
  else run_module "$MODULE"; fi
  echo -e "\n$GREEN============================================================$NC"
  echo -e "$GREEN OrangeBox Linux Hardening $VERSION - FIN $NC"
  echo "Correcciones: $FIXED"; echo "Advertencias: $WARNINGS"; echo "Errores: $ERRORS"; echo "Backup: $BACKUP_DIR"
  echo -e "$GREEN============================================================$NC"
}
main "$@"
