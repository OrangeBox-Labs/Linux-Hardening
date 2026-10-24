#!/bin/bash
# OrangeBox Linux Hardening - Safe Enterprise Baseline
# Version 1.3.1 - RHEL/CentOS/Rocky/AlmaLinux 6-10
# AUDIT by default. --fix applies conservative controls only.
# SELinux is never changed. cron.allow/at.allow are never created.
# System-wide crypto-policies are never changed and SSH crypto is audited, not overridden.

set -u
VERSION=1.3.1
AUTO_FIX=false
MODULE=all
RUN_ID=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/var/backups/orangebox-linux-hardening/$RUN_ID
FIXED=0
WARNINGS=0
ERRORS=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok(){ echo -e "$GREEN[OK]$NC $*"; }; warn(){ WARNINGS=$((WARNINGS+1)); echo -e "$YELLOW[WARN]$NC $*"; }; bad(){ WARNINGS=$((WARNINGS+1)); echo -e "$RED[FAIL]$NC $*"; }; die(){ ERRORS=$((ERRORS+1)); echo -e "$RED[ERROR]$NC $*"; exit 1; }
require_root(){ [ "$EUID" -eq 0 ] || die "Debe ejecutarse como root."; }
detect_os(){
  [ -r /etc/os-release ] || die "Falta /etc/os-release"; . /etc/os-release
  OS_ID=${ID:-}; OS_VERSION=$(echo "${VERSION_ID:-}"|cut -d. -f1); ID_LIKE=${ID_LIKE:-}
  case "$OS_ID" in rhel|centos|rocky|almalinux|ol|oracle) ;; *) [[ "$ID_LIKE" == *rhel* ]] || die "Distribución no soportada: $OS_ID";; esac
  case "$OS_VERSION" in 6|7|8|9|10) ;; *) die "Versión no soportada: $OS_VERSION";; esac
  ok "Detectado: $OS_ID $OS_VERSION"
}
prepare_backup(){ mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"; }
backup_once(){ local src="$1"; [ -e "$src" ] || return 0; local dst="$BACKUP_DIR$(dirname "$src")"; mkdir -p "$dst"; cp -a "$src" "$BACKUP_DIR$src"; }
set_sysctl(){
  local key="$1" value="$2" file=/etc/sysctl.d/99-orangebox-hardening.conf current
  current=$(sysctl -n "$key" 2>/dev/null||true); [ "$current" = "$value" ] && { ok "$key=$value"; return; }
  warn "$key actual=$current recomendado=$value"; $AUTO_FIX || return
  backup_once "$file"; touch "$file"
  if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$file"; then sed -ri "s|^[[:space:]]*$key[[:space:]]*=.*|$key = $value|" "$file"; else echo "$key = $value" >> "$file"; fi
  if sysctl -w "$key=$value" >/dev/null 2>&1 && [ "$(sysctl -n "$key" 2>/dev/null||true)" = "$value" ]; then ok "$key aplicado/verificado=$value"; FIXED=$((FIXED+1)); else warn "No se pudo aplicar/verificar $key"; fi
}

SYNFLOOD_FILE=/etc/sysctl.d/99-orangebox-synflood-hardening.conf
SYNFLOOD_LEGACY_FILE=/etc/sysctl.d/99-cpanel-synflood-hardening.conf
SYNFLOOD_KEYS="net.ipv4.tcp_syncookies net.ipv4.tcp_max_syn_backlog net.core.somaxconn net.ipv4.tcp_synack_retries net.ipv4.tcp_syn_retries"
# 3/5 is deliberately more conservative than the previous 2/2 profile.
SYNFLOOD_VALUES="1 4096 4096 3 5"
synflood_managed(){ local f="$1"; [ -f "$f" ] && grep -Fqx '# OrangeBox managed SYN flood profile' "$f" && grep -Fqx '# BEGIN ORANGEBOX SYNFLOOD' "$f" && grep -Fqx '# END ORANGEBOX SYNFLOOD' "$f"; }
synflood_module(){
  echo -e "\n$BLUE### SYN FLOOD / TCP BACKLOG ###$NC"; [ -d /etc/sysctl.d ] || { warn "/etc/sysctl.d no existe"; return; }
  local idx=1 key current desired external cfg profile="$SYNFLOOD_FILE"
  [ -e "$SYNFLOOD_FILE" ] && ! synflood_managed "$SYNFLOOD_FILE" && { warn "$SYNFLOOD_FILE no es gestionado por OrangeBox; no se sobrescribe"; return; }
  [ ! -e "$SYNFLOOD_FILE" ] && synflood_managed "$SYNFLOOD_LEGACY_FILE" && profile="$SYNFLOOD_LEGACY_FILE"
  for key in $SYNFLOOD_KEYS; do
    current=$(sysctl -n "$key" 2>/dev/null||true); desired=$(printf '%s\n' "$SYNFLOOD_VALUES"|awk -v n="$idx" 'NR==n{print}')
    [ -n "$current" ] || { warn "$key no existe"; idx=$((idx+1)); continue; }
    external=""
    for cfg in /etc/sysctl.conf /etc/sysctl.d/*.conf; do [ -f "$cfg" ] || continue; [ "$cfg" = "$SYNFLOOD_FILE" ] || [ "$cfg" = "$profile" ] && continue; grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$cfg" && { external="$cfg"; break; }; done
    [ -n "$external" ] && warn "$key definido en $external; se conserva" || { [ "$current" = "$desired" ] && ok "$key=$desired" || warn "$key actual=$current recomendado=$desired"; }
    idx=$((idx+1))
  done
  $AUTO_FIX || return
  backup_once "$SYNFLOOD_FILE"; [ "$profile" = "$SYNFLOOD_FILE" ] || backup_once "$profile"
  local tmp; tmp=$(mktemp "$SYNFLOOD_FILE.XXXXXX") || { warn "No se pudo crear temporal"; return; }
  if [ -e "$profile" ]; then awk '$0=="# BEGIN ORANGEBOX SYNFLOOD"{i=1;next}$0=="# END ORANGEBOX SYNFLOOD"{i=0;next}!i&&$0!="# OrangeBox managed SYN flood profile"{print}' "$profile" > "$tmp" || { rm -f "$tmp"; warn "No se pudo leer perfil"; return; }; fi
  { [ ! -s "$tmp" ] || printf '\n'; echo '# OrangeBox managed SYN flood profile'; echo '# BEGIN ORANGEBOX SYNFLOOD'; idx=1; for key in $SYNFLOOD_KEYS; do desired=$(printf '%s\n' "$SYNFLOOD_VALUES"|awk -v n="$idx" 'NR==n{print}'); echo "$key = $desired"; idx=$((idx+1)); done; echo '# END ORANGEBOX SYNFLOOD'; } >> "$tmp"
  chmod 644 "$tmp"; chown root:root "$tmp" 2>/dev/null||true; mv "$tmp" "$SYNFLOOD_FILE" || { rm -f "$tmp"; warn "No se pudo instalar perfil"; return; }; [ "$profile" = "$SYNFLOOD_FILE" ] || rm -f "$profile"
  idx=1; for key in $SYNFLOOD_KEYS; do desired=$(printf '%s\n' "$SYNFLOOD_VALUES"|awk -v n="$idx" 'NR==n{print}'); if sysctl -w "$key=$desired" >/dev/null 2>&1 && [ "$(sysctl -n "$key" 2>/dev/null||true)" = "$desired" ]; then FIXED=$((FIXED+1)); else warn "No se pudo aplicar/verificar $key"; fi; idx=$((idx+1)); done
  ok "SYN flood conservador: syncookies=1 backlog=4096 somaxconn=4096 synack_retries=3 syn_retries=5"
}

ssh_effective(){ sshd -T 2>/dev/null|awk -v k="$1" '$1==k{$1="";sub(/^ /,"");print;exit}'; }
ssh_module(){
  echo -e "\n$BLUE### SSH ###$NC"; [ -f /etc/ssh/sshd_config ] || { warn "sshd_config no existe"; return; }; command -v sshd >/dev/null 2>&1 || { warn "sshd no disponible"; return; }
  local perms policy; perms=$(stat -c %a /etc/ssh/sshd_config 2>/dev/null||true); [ "$perms" = 600 ] || warn "sshd_config permisos=$perms; no se cambia automáticamente"
  policy=$(command -v update-crypto-policies >/dev/null 2>&1 && update-crypto-policies --show 2>/dev/null||echo unknown); case "$policy" in LEGACY*) warn "Crypto policy=$policy: revisar migración";; unknown) warn "No se pudo determinar crypto policy";; *) ok "Crypto policy=$policy";; esac
  [ -n "$(ssh_effective ciphers)" ] && ok "Ciphers efectivos auditados" || warn "No se pudieron leer ciphers efectivos"; [ -n "$(ssh_effective kexalgorithms)" ] && ok "KEX efectivos auditados" || warn "No se pudieron leer KEX efectivos"; [ -n "$(ssh_effective macs)" ] && ok "MACs efectivos auditados" || warn "No se pudieron leer MACs efectivos"
  # Safe SSH controls only. Existing crypto/auth/forwarding choices are preserved.
  if $AUTO_FIX && [ "$OS_VERSION" -ge 8 ] && [ -d /etc/ssh/sshd_config.d ]; then
    local drop=/etc/ssh/sshd_config.d/49-orangebox-hardening.conf tmp
    if [ -e "$drop" ]; then warn "$drop ya existe; no se sobrescribe para preservar configuración existente"; else
      tmp=$(mktemp "$drop.XXXXXX") || { warn "No se pudo crear SSH temporal"; return; }
      { echo "# OrangeBox Linux Hardening $VERSION"; echo "IgnoreRhosts yes"; echo "HostbasedAuthentication no"; echo "PermitEmptyPasswords no"; echo "PermitUserEnvironment no"; echo "MaxAuthTries 6"; echo "LoginGraceTime 60"; echo "ClientAliveInterval 300"; echo "ClientAliveCountMax 2"; echo "LogLevel INFO"; } > "$tmp"
      chmod 600 "$tmp"; chown root:root "$tmp" 2>/dev/null||true; mv "$tmp" "$drop"
      if sshd -t >/dev/null 2>&1; then ok "sshd -t válido después del hardening"; FIXED=$((FIXED+1)); else bad "sshd -t falló; se elimina el drop-in recién creado"; rm -f "$drop"; fi
    fi
  elif $AUTO_FIX; then warn "RHEL <8: no se edita sshd_config automáticamente; se evita riesgo de perder acceso"
  fi
  warn "No se fuerza PasswordAuthentication, PubkeyAuthentication, PermitRootLogin, AllowUsers/AllowGroups, forwarding, GSSAPI/Kerberos ni crypto algorithms: esos cambios requieren inventario de clientes/integraciones para no romper accesos."
}

sudo_module(){ echo -e "\n$BLUE### SUDO ###$NC"; command -v visudo >/dev/null 2>&1 || { warn "visudo no disponible"; return; }; visudo -cf /etc/sudoers >/dev/null 2>&1&&ok "sudoers válido"||bad "sudoers inválido"; grep -RqsE '^[[:space:]]*Defaults[[:space:]]+use_pty' /etc/sudoers /etc/sudoers.d 2>/dev/null&&ok "use_pty habilitado"||{ warn "use_pty no configurado"; if $AUTO_FIX; then local f=/etc/sudoers.d/99-orangebox-hardening; echo 'Defaults use_pty'>"$f"; chmod 440 "$f"; chown root:root "$f"; visudo -cf "$f" >/dev/null 2>&1&&{ ok "use_pty habilitado"; FIXED=$((FIXED+1)); }||rm -f "$f"; fi; }
}
password_module(){ echo -e "\n$BLUE### PASSWORD / PAM ###$NC"; [ -f /etc/login.defs ]||return; local max; max=$(awk '$1=="PASS_MAX_DAYS"{v=$2}END{print v}' /etc/login.defs); [ "$max" = -1 ]||[ "$max" = 0 ]&&ok "PASS_MAX_DAYS=$max (sin expiración)"||warn "PASS_MAX_DAYS=$max; password-hardening.sh debe corregirlo"; command -v authselect >/dev/null 2>&1&&authselect current >/dev/null 2>&1&&ok "authselect operativo; PAM no se edita a ciegas"||warn "PAM requiere revisión; no se insertan reglas automáticamente"; grep -Rqs 'pam_faillock.so' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null&&ok "pam_faillock presente"||warn "pam_faillock no presente; se deja en auditoría"; getent group wheel >/dev/null 2>&1&&ok "wheel existe"||warn "wheel no existe"; }
kernel_module(){ echo -e "\n$BLUE### KERNEL / SYSCTL ###$NC"; set_sysctl fs.suid_dumpable 0; set_sysctl kernel.dmesg_restrict 1; set_sysctl kernel.kptr_restrict 2; set_sysctl kernel.randomize_va_space 2; set_sysctl fs.protected_fifos 1; set_sysctl fs.protected_hardlinks 1; set_sysctl fs.protected_symlinks 1; set_sysctl net.ipv4.conf.all.accept_redirects 0; set_sysctl net.ipv4.conf.default.accept_redirects 0; set_sysctl net.ipv4.conf.all.send_redirects 0; set_sysctl net.ipv4.conf.default.send_redirects 0; }
filesystem_module(){ echo -e "\n$BLUE### FILESYSTEM ###$NC"; for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do [ -f "$f" ]||continue; local p; p=$(stat -c %a "$f"); case "$f" in /etc/passwd|/etc/group) [ "$p" -le 644 ]&&ok "$f=$p"||warn "$f=$p";; *) [ "$p" = 600 ]||[ "$p" = 640 ]||[ "$p" = 000 ]&&ok "$f=$p"||warn "$f=$p; no se fuerza";; esac; done; }
auditd_module(){ echo -e "\n$BLUE### AUDITD ###$NC"; command -v auditctl >/dev/null 2>&1&&systemctl is-active auditd >/dev/null 2>&1&&ok "auditd activo"||warn "auditd ausente/inactivo"; [ -d /etc/audit/rules.d ]&&ok "rules.d disponible"||warn "rules.d no existe"; }
rsyslog_module(){ echo -e "\n$BLUE### JOURNAL ###$NC"; [ -d /var/log/journal ]&&ok "journal persistente"||warn "journal no persistente"; if $AUTO_FIX&&[ -f /etc/systemd/journald.conf ]; then backup_once /etc/systemd/journald.conf; grep -Eq '^[[:space:]]*Storage=' /etc/systemd/journald.conf&&sed -ri 's/^[[:space:]]*Storage=.*/Storage=persistent/' /etc/systemd/journald.conf||echo 'Storage=persistent'>>/etc/systemd/journald.conf; mkdir -p /var/log/journal; systemctl restart systemd-journald >/dev/null 2>&1||warn "journald no reinició"; FIXED=$((FIXED+1)); fi; }
selinux_module(){ echo -e "\n$BLUE### SELINUX ###$NC"; command -v getenforce >/dev/null 2>&1||{ warn "SELinux no disponible"; return; }; local mode; mode=$(getenforce); [ "$mode" = Enforcing ]&&ok "SELinux Enforcing"||warn "SELinux=$mode; NO se modifica por política OrangeBox"; }
cron_module(){ echo -e "\n$BLUE### CRON / AT ###$NC"; [ -e /etc/cron.allow ]&&ok "cron.allow existe"||warn "cron.allow no existe; se deja intacto para no romper cPanel"; [ -e /etc/at.allow ]&&ok "at.allow existe"||warn "at.allow no existe; se deja intacto"; }
usb_module(){ echo -e "\n$BLUE### USB ###$NC"; lsmod 2>/dev/null|grep -q '^usb_storage'&&warn "usb_storage cargado"||ok "usb_storage no cargado"; warn "USB no se bloquea automáticamente"; }
services_module(){ echo -e "\n$BLUE### LEGACY SERVICES ###$NC"; for s in telnet.socket xinetd tftp.socket rsh.socket rlogin.socket rexec.socket; do systemctl list-unit-files "$s" 2>/dev/null|grep -q "$s"&&warn "Servicio legacy presente: $s"; done; for p in telnet-server xinetd rsh-server tftp-server; do rpm -q "$p" >/dev/null 2>&1&&warn "Paquete legacy instalado: $p"; done; warn "No se eliminan servicios automáticamente"; }
banners_module(){ echo -e "\n$BLUE### BANNER ###$NC"; [ -s /etc/issue.net ]&&ok "issue.net configurado"||warn "issue.net vacío"; if $AUTO_FIX; then backup_once /etc/issue.net; echo 'Sistema de uso autorizado. El acceso no autorizado está prohibido.'>/etc/issue.net; chmod 644 /etc/issue.net; chown root:root /etc/issue.net; FIXED=$((FIXED+1)); fi; }
time_module(){ echo -e "\n$BLUE### TIME SYNC ###$NC"; command -v chronyc >/dev/null 2>&1&&chronyc tracking >/dev/null 2>&1&&ok "chrony operativo"||warn "NTP/chrony no verificado"; }
grub_module(){ echo -e "\n$BLUE### GRUB ###$NC"; find /boot /etc -maxdepth 4 -type f -name grub.cfg 2>/dev/null|head -1|grep -q .&&ok "grub.cfg localizado"||warn "grub.cfg no localizado"; warn "GRUB no se modifica automáticamente"; }
firewall_module(){ echo -e "\n$BLUE### FIREWALL ###$NC"; if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --state 2>/dev/null|grep -q running&&ok "firewalld activo"||warn "firewalld no activo"; elif command -v nft >/dev/null 2>&1; then nft list ruleset >/dev/null 2>&1&&ok "nftables disponible"||warn "nftables sin ruleset"; else warn "No se detectó firewall"; fi; warn "No se aplican DROP automáticamente"; }
fapolicyd_module(){ echo -e "\n$BLUE### FAPOLICYD ###$NC"; rpm -q fapolicyd >/dev/null 2>&1&&systemctl is-active fapolicyd >/dev/null 2>&1&&ok "fapolicyd activo"||warn "fapolicyd ausente/inactivo; no se habilita automáticamente"; }
listening_module(){ echo -e "\n$BLUE### LISTENING SERVICES ###$NC"; command -v ss >/dev/null 2>&1&&ss -lntup 2>/dev/null||true; }
bash_module(){ echo -e "\n$BLUE### BASH ###$NC"; [ -d /etc/profile.d ]&&ok "/etc/profile.d existe"||warn "/etc/profile.d ausente"; }
usage(){ echo "OrangeBox Linux Hardening $VERSION"; echo "Uso: $0 [--fix] [--module MODULO]"; echo "Módulos: ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash"; }
run_module(){ case "$1" in ssh)ssh_module;;sudo)sudo_module;;password)password_module;;kernel)kernel_module;;synflood)synflood_module;;filesystem)filesystem_module;;auditd)auditd_module;;rsyslog)rsyslog_module;;selinux)selinux_module;;cron)cron_module;;usb)usb_module;;services)services_module;;banners)banners_module;;time)time_module;;grub)grub_module;;firewall)firewall_module;;fapolicyd)fapolicyd_module;;listening)listening_module;;bash)bash_module;;*)die "Módulo desconocido: $1";;esac; }
main(){ require_root; while [ $# -gt 0 ]; do case "$1" in --fix|-f)AUTO_FIX=true;;--module|-m)shift;[ $# -gt 0]||die "--module requiere nombre";MODULE=$1;;--help|-h)usage;exit 0;;--list-modules)echo "ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash";exit 0;;*)die "Argumento desconocido: $1";;esac;shift;done; detect_os;prepare_backup; $AUTO_FIX&&warn "MODO FIX: controles conservadores; no se toca SELinux, cron.allow ni PAM de forma destructiva"||ok "MODO AUDITORÍA: sin cambios"; if [ "$MODULE" = all ];then for m in ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash;do run_module "$m";done;else run_module "$MODULE";fi; echo -e "\n$GREEN============================================================$NC";echo -e "$GREEN OrangeBox Linux Hardening $VERSION - FIN $NC";echo "Correcciones: $FIXED";echo "Advertencias: $WARNINGS";echo "Errores: $ERRORS";echo "Backup: $BACKUP_DIR";echo -e "$GREEN============================================================$NC"; }
main "$@"
