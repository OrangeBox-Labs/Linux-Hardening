#!/bin/bash
# OrangeBox Linux Hardening - Safe Enterprise Baseline
# Version 1.4.1 - RHEL/CentOS/Rocky/AlmaLinux 6-10
# Audit by default. Interactive --fix asks separately before delicate modules; --fix --auto only applies banners/Bash and audits the delicate controls.
# Core baseline never changes SELinux or creates cron.allow/at.allow.
# High-risk companion modules require explicit selection and --allow-risky.
# System-wide crypto-policies are never changed by the core baseline.

set -u
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$SCRIPT_DIR/lib/sysctl-safe.sh" ]; then
  # shellcheck source=lib/sysctl-safe.sh
  source "$SCRIPT_DIR/lib/sysctl-safe.sh"
else
  echo "[ERROR] Falta lib/sysctl-safe.sh; actualice el repositorio completo." >&2
  exit 1
fi
SCRIPT_VERSION=1.4.1
AUTO_FIX=false
AUTO_MODE=false
ALLOW_RISKY=false
ALLOW_SHOREWALL=false
MODULE=all
RUN_ID=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/var/backups/orangebox-linux-hardening/$RUN_ID
FIXED=0
WARNINGS=0
ERRORS=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok(){ echo -e "$GREEN[OK]$NC $*"; }; info(){ echo -e "$BLUE[INFO]$NC $*"; }; warn(){ WARNINGS=$((WARNINGS+1)); echo -e "$YELLOW[WARN]$NC $*"; }; bad(){ WARNINGS=$((WARNINGS+1)); echo -e "$RED[FAIL]$NC $*"; }; die(){ ERRORS=$((ERRORS+1)); echo -e "$RED[ERROR]$NC $*"; exit 1; }
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
  local key="$1" value="$2" file=/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf
  if sysctl_safe_apply "$key" "$value" "$(sysctl_safe_description "$key")" "$file" "$BACKUP_DIR" "$AUTO_FIX" "" ""; then
    [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED+1))
  else
    WARNINGS=$((WARNINGS+1))
  fi
}

SYNFLOOD_FILE=/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf
SYNFLOOD_KEYS="net.ipv4.tcp_syncookies net.ipv4.tcp_max_syn_backlog net.core.somaxconn"
SYNFLOOD_VALUES=(1 4096 4096)
synflood_module(){
  echo -e "\n$BLUE### SYN FLOOD / TCP BACKLOG ###$NC"
  [ -d /etc/sysctl.d ] || { warn "/etc/sysctl.d no existe"; return; }

  local idx=0 key desired
  for key in $SYNFLOOD_KEYS; do
    desired="${SYNFLOOD_VALUES[$idx]}"
    if sysctl_safe_apply "$key" "$desired" "$(sysctl_safe_description "$key")" "$SYNFLOOD_FILE" "$BACKUP_DIR" "$AUTO_FIX" "" ""; then
      [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED+1))
    else
      WARNINGS=$((WARNINGS+1))
    fi
    idx=$((idx+1))
  done
  info "Los valores externos de sysctl se conservan. Los valores distintos solo se imponen con confirmación individual."
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
      { echo "# OrangeBox Linux Hardening $SCRIPT_VERSION"; echo "IgnoreRhosts yes"; echo "HostbasedAuthentication no"; echo "PermitEmptyPasswords no"; echo "PermitUserEnvironment no"; echo "MaxAuthTries 6"; echo "LoginGraceTime 60"; echo "ClientAliveInterval 300"; echo "ClientAliveCountMax 2"; echo "LogLevel INFO"; } > "$tmp"
      chmod 600 "$tmp"; chown root:root "$tmp" 2>/dev/null||true; mv "$tmp" "$drop"
      if sshd -t >/dev/null 2>&1; then ok "sshd -t válido después del hardening"; FIXED=$((FIXED+1)); else bad "sshd -t falló; se elimina el drop-in recién creado"; rm -f "$drop"; fi
    fi
  elif $AUTO_FIX; then
    if [ "$OS_VERSION" -lt 8 ]; then
      warn "RHEL/CentOS <8: no se edita sshd_config automáticamente para evitar riesgo de perder acceso"
    elif [ ! -d /etc/ssh/sshd_config.d ]; then
      warn "/etc/ssh/sshd_config.d no existe; no se modifica sshd_config automáticamente para evitar riesgo de perder acceso"
    else
      warn "No se cumplen las condiciones para instalar el drop-in SSH; no se modifica sshd_config automáticamente"
    fi
  fi
  info "No se fuerzan PasswordAuthentication, PubkeyAuthentication, PermitRootLogin, AllowUsers/AllowGroups, forwarding, GSSAPI/Kerberos ni algoritmos criptográficos sin inventario de clientes e integraciones."
}

cpanel_host_detected() {
  [ -d /usr/local/cpanel ] || [ -f /etc/cpanel/cpanel.config ] || command -v whmapi1 >/dev/null 2>&1
}

sudo_module() {
  echo -e "\n$BLUE### SUDO ###$NC"
  command -v visudo >/dev/null 2>&1 || { warn "visudo no disponible"; return; }
  visudo -cf /etc/sudoers >/dev/null 2>&1 && ok "sudoers válido" || bad "sudoers inválido"

  if grep -RqsE '^[[:space:]]*Defaults[[:space:]]+use_pty([[:space:]]|$)' /etc/sudoers /etc/sudoers.d 2>/dev/null; then
    ok "use_pty habilitado"
    return
  fi

  if cpanel_host_detected; then
    info "cPanel detectado: por política OrangeBox no se activa use_pty, ya que puede romper funcionalidades o automatizaciones del hosting."
    return
  fi

  warn "use_pty no configurado"
  $AUTO_FIX || return

  local answer f=/etc/sudoers.d/99-orangebox-hardening
  if [ -e "$f" ]; then
    warn "$f ya existe; no se sobrescribe para conservar la configuración existente"
    return
  fi
  if [ ! -r /dev/tty ]; then
    warn "No hay terminal interactiva para confirmar use_pty; no se modifica sudoers"
    return
  fi
  echo "Qué cambia: obliga a sudo a utilizar un pseudo-terminal; puede afectar automatizaciones que dependen de una sesión sin TTY."
  read -r -p "¿Deseas habilitar Defaults use_pty en este servidor? [s/N]: " answer </dev/tty
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) ;;
    *) info "use_pty rechazado/no confirmado; se conserva la configuración actual"; return ;;
  esac

  printf '%s\n' 'Defaults use_pty' > "$f" || { warn "No se pudo preparar $f"; return; }
  chmod 440 "$f" && chown root:root "$f" || { rm -f "$f"; warn "No se pudieron fijar los permisos de $f"; return; }
  if visudo -cf /etc/sudoers >/dev/null 2>&1; then
    ok "use_pty habilitado y sudoers validado"
    FIXED=$((FIXED+1))
  else
    rm -f "$f"
    bad "sudoers no validó; se retiró el drop-in recién creado"
  fi
}
password_module() {
  echo -e "\n$BLUE### PASSWORD / PAM ###$NC"
  [ -f /etc/login.defs ] || return
  local max
  max=$(awk '$1=="PASS_MAX_DAYS"{v=$2}END{print v}' /etc/login.defs)
  info "PASS_MAX_DAYS=${max:-no definido}; se conserva sin cambios por política operacional para evitar expiraciones que puedan bloquear accesos."
  command -v authselect >/dev/null 2>&1 && authselect current >/dev/null 2>&1 && ok "authselect operativo; PAM no se edita a ciegas" || warn "PAM requiere revisión; no se insertan reglas automáticamente"
  grep -Rqs 'pam_faillock.so' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null && ok "pam_faillock presente" || warn "pam_faillock no presente; se deja en auditoría"
  getent group wheel >/dev/null 2>&1 && ok "wheel existe" || warn "wheel no existe"
}
kernel_module(){
  echo -e "\n$BLUE### KERNEL / SYSCTL ###$NC"
  local forwarding rp_filter ipv6_forward
  forwarding=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)
  rp_filter=1
  if [ "$forwarding" = 1 ]; then
    # Strict reverse-path filtering can drop legitimate asymmetric routed traffic.
    rp_filter=2
    ok "IP forwarding=1: se usa rp_filter=2 (modo loose) para preservar el enrutamiento"
  fi

  set_sysctl fs.suid_dumpable 0
  set_sysctl kernel.dmesg_restrict 1
  set_sysctl kernel.kptr_restrict 2
  set_sysctl kernel.randomize_va_space 2
  set_sysctl fs.protected_fifos 1
  set_sysctl fs.protected_hardlinks 1
  set_sysctl fs.protected_symlinks 1

  # Baseline de red compartido con network-hardening.sh.
  # No se cambia net.ipv4.ip_forward ni otros parámetros de routing no acordados.
  set_sysctl net.ipv4.conf.all.accept_redirects 0
  set_sysctl net.ipv4.conf.default.accept_redirects 0
  set_sysctl net.ipv4.conf.all.send_redirects 0
  set_sysctl net.ipv4.conf.default.send_redirects 0
  set_sysctl net.ipv4.conf.all.accept_source_route 0
  set_sysctl net.ipv4.conf.default.accept_source_route 0
  set_sysctl net.ipv4.conf.all.secure_redirects 0
  set_sysctl net.ipv4.conf.default.secure_redirects 0
  set_sysctl net.ipv4.conf.all.log_martians 1
  set_sysctl net.ipv4.conf.default.log_martians 1
  set_sysctl net.ipv4.icmp_echo_ignore_broadcasts 1
  set_sysctl net.ipv4.icmp_ignore_bogus_error_responses 1
  set_sysctl net.ipv4.conf.all.rp_filter "$rp_filter"
  set_sysctl net.ipv4.conf.default.rp_filter "$rp_filter"

  if [ -d /proc/sys/net/ipv6 ]; then
    set_sysctl net.ipv6.conf.all.accept_source_route 0
    set_sysctl net.ipv6.conf.default.accept_source_route 0
    ipv6_forward=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo 0)
    if [ "$ipv6_forward" = 1 ]; then
      warn "IPv6 forwarding está activo: se preserva accept_ra para no cortar el descubrimiento de rutas del uplink"
    else
      set_sysctl net.ipv6.conf.all.accept_ra 0
      set_sysctl net.ipv6.conf.default.accept_ra 0
    fi
  fi
}
filesystem_module(){
  echo -e "\n$BLUE### FILESYSTEM ###$NC"
  local f p
  for f in /etc/passwd /etc/group /etc/shadow /etc/gshadow; do
    [ -f "$f" ] || continue
    p=$(stat -c %a "$f" 2>/dev/null || true)
    case "$f" in
      /etc/passwd|/etc/group)
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -le 644 ]; then
          ok "$f=$p"
        else
          warn "$f=$p"
        fi
        ;;
      *)
        # GNU stat prints mode 000 as "0", not "000".
        if [ "$p" = 600 ] || [ "$p" = 640 ] || [ "$p" = 0 ] || [ "$p" = 000 ]; then
          ok "$f=$p"
        else
          warn "$f=$p; no se fuerza"
        fi
        ;;
    esac
  done
}
auditd_module(){ echo -e "\n$BLUE### AUDITD ###$NC"; command -v auditctl >/dev/null 2>&1&&systemctl is-active auditd >/dev/null 2>&1&&ok "auditd activo"||warn "auditd ausente/inactivo"; [ -d /etc/audit/rules.d ]&&ok "rules.d disponible"||warn "rules.d no existe"; }
rsyslog_module(){
  echo -e "\n$BLUE### JOURNAL ###$NC"
  local conf=/etc/systemd/journald.conf

  if [ "$AUTO_FIX" != true ]; then
    if [ -d /var/log/journal ] && grep -Eq '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent([[:space:]]*(#.*)?)?$' "$conf" 2>/dev/null; then
      ok "journal persistente (Storage=persistent y /var/log/journal existe)"
    else
      warn "journal no persistente o Storage=persistent no configurado explícitamente"
    fi
    return
  fi

  if [ ! -f "$conf" ]; then
    warn "$conf no existe; no se modifica journald automáticamente"
    return
  fi

  if [ -d /var/log/journal ] && grep -Eq '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent([[:space:]]*(#.*)?)?$' "$conf"; then
    ok "journal persistente (configuración y directorio verificados)"
    return
  fi

  backup_once "$conf"
  if grep -Eq '^[[:space:]]*Storage[[:space:]]*=' "$conf"; then
    if ! sed -ri 's/^[[:space:]]*Storage[[:space:]]*=.*/Storage=persistent/' "$conf"; then
      warn "No se pudo configurar Storage=persistent en $conf"
      return
    fi
  else
    printf '\nStorage=persistent\n' >> "$conf" || {
      warn "No se pudo añadir Storage=persistent a $conf"
      return
    }
  fi

  if ! mkdir -p /var/log/journal; then
    warn "No se pudo crear /var/log/journal"
    return
  fi
  if command -v systemd-tmpfiles >/dev/null 2>&1; then
    systemd-tmpfiles --create --prefix=/var/log/journal >/dev/null 2>&1 || warn "systemd-tmpfiles no pudo normalizar /var/log/journal"
  fi
  if ! systemctl restart systemd-journald >/dev/null 2>&1; then
    warn "journald no reinició; revisar $conf y el estado del servicio"
    return
  fi

  if [ -d /var/log/journal ] && grep -Eq '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent([[:space:]]*(#.*)?)?$' "$conf" && systemctl is-active --quiet systemd-journald; then
    ok "journal configurado como persistente y verificado tras reiniciar journald"
    FIXED=$((FIXED+1))
  else
    warn "No se pudo verificar la persistencia de journald después del cambio"
  fi
}

selinux_module(){ echo -e "\n$BLUE### SELINUX ###$NC"; command -v getenforce >/dev/null 2>&1||{ warn "SELinux no disponible"; return; }; local mode; mode=$(getenforce); [ "$mode" = Enforcing ]&&ok "SELinux Enforcing"||warn "SELinux=$mode; NO se modifica por política OrangeBox"; }
cron_module(){ echo -e "\n$BLUE### CRON / AT ###$NC"; [ -e /etc/cron.allow ]&&ok "cron.allow existe"||warn "cron.allow no existe; se deja intacto para no romper cPanel"; [ -e /etc/at.allow ]&&ok "at.allow existe"||warn "at.allow no existe; se deja intacto"; }
usb_module(){ echo -e "\n$BLUE### USB ###$NC"; lsmod 2>/dev/null|grep -q '^usb_storage'&&warn "usb_storage cargado"||ok "usb_storage no cargado"; info "USB no se bloquea automáticamente; requiere decisión explícita de política"; }
services_module(){ echo -e "\n$BLUE### LEGACY SERVICES ###$NC"; for s in telnet.socket xinetd tftp.socket rsh.socket rlogin.socket rexec.socket; do systemctl list-unit-files "$s" 2>/dev/null|grep -q "$s"&&warn "Servicio legacy presente: $s"; done; for p in telnet-server xinetd rsh-server tftp-server; do rpm -q "$p" >/dev/null 2>&1&&warn "Paquete legacy instalado: $p"; done; info "No se eliminan servicios automáticamente; revisar los servicios legacy detectados si los hubiera"; }
configure_ssh_banner() {
  local main=/etc/ssh/sshd_config current tmp backup reload_ok=0
  echo -e "\n$BLUE### SSH LOGIN BANNER ###$NC"
  [ -f "$main" ] || { warn "$main no existe; no se configura el banner SSH"; return; }
  command -v sshd >/dev/null 2>&1 || { warn "sshd no disponible; no se puede validar el banner SSH"; return; }

  current="$(sshd -T -f "$main" 2>/dev/null | awk '$1=="banner"{print $2; exit}')"
  if [ "$current" = "/etc/issue.net" ]; then
    ok "Banner SSH efectivo apunta a /etc/issue.net"
    return
  fi
  if ! $AUTO_FIX; then
    warn "Banner SSH efectivo=${current:-no verificable}; recomendado /etc/issue.net"
    return
  fi

  backup_once "$main"
  backup="$BACKUP_DIR$main"
  tmp="$(mktemp)" || { warn "No se pudo crear temporal para sshd_config"; return; }

  # OpenSSH suele procesar Include al inicio. El primer valor efectivo gana;
  # por eso Banner debe ir antes del primer Include y antes de cualquier Match.
  # Se eliminan Banner previos del archivo principal para evitar valores
  # posteriores o específicos de Match que contradigan el banner corporativo.
  awk '
    BEGIN { done=0 }
    {
      keyword=tolower($1)
      if (keyword == "banner") next
      if (keyword == "include" && !done) {
        print "Banner /etc/issue.net"
        done=1
      }
      if (keyword == "match" && !done) {
        print "Banner /etc/issue.net"
        done=1
      }
      print
    }
    END { if (!done) print "Banner /etc/issue.net" }
  ' "$main" > "$tmp" || { rm -f "$tmp"; warn "No se pudo preparar sshd_config"; return; }
  chmod --reference="$main" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  chown --reference="$main" "$tmp" 2>/dev/null || chown root:root "$tmp"
  mv "$tmp" "$main" || { rm -f "$tmp"; warn "No se pudo instalar sshd_config"; return; }

  current="$(sshd -T -f "$main" 2>/dev/null | awk '$1=="banner"{print $2; exit}')"
  if sshd -t -f "$main" >/dev/null 2>&1 && [ "$current" = "/etc/issue.net" ]; then
    if command -v systemctl >/dev/null 2>&1 && systemctl reload sshd >/dev/null 2>&1; then
      reload_ok=1
    elif command -v service >/dev/null 2>&1 && service sshd reload >/dev/null 2>&1; then
      reload_ok=1
    fi
    if [ "$reload_ok" -eq 1 ]; then
      ok "Banner SSH aplicado, validado y sshd recargado sin cortar sesiones"
      FIXED=$((FIXED+1))
    else
      warn "Banner SSH configurado y validado; no se pudo recargar sshd, revisar servicio"
    fi
  else
    if [ -f "$backup" ]; then cp -a "$backup" "$main"; fi
    bad "La configuración SSH no validó el banner; se restauró sshd_config desde el backup"
  fi
}

banners_module() {
  echo -e "\n$BLUE### BANNERS / MOTD ###$NC"
  local login_tmp motd_tmp target content_tmp mode owner group

  login_tmp="$(mktemp)" || { warn "No se pudo crear el banner previo al login"; return; }
  motd_tmp="$(mktemp)" || { rm -f "$login_tmp"; warn "No se pudo crear el MOTD"; return; }

  # Aviso legal previo a la autenticación: no enumera tecnologías defensivas.
  cat > "$login_tmp" <<'ORANGEBOX_LOGIN_BANNER'
*******************************************************************************
  ___                         ___
 / _ \ _ _ __ _ _ _  __ _ ___| _ ) _____ __
| (_) | '_/ _` | ' \/ _` / -_) _ \/ _ \ \ /
 \___/|_| \__,_|_||_\__, \___|___/\___/_\_\\
                    |___/
                         SISTEMA DE ACCESO RESTRINGIDO
                           www.orangebox.cl
*******************************************************************************

Solo usuarios autorizados pueden acceder a este sistema.
El acceso o uso no autorizado esta prohibido.

La actividad realizada en este sistema puede ser registrada y revisada
conforme a las politicas de la organizacion y a la legislacion aplicable.
Si no cuenta con autorizacion, desconectese inmediatamente.

*******************************************************************************
ORANGEBOX_LOGIN_BANNER

  # MOTD se presenta después del login: mantenerlo breve para no duplicar
  # la advertencia legal que SSH ya muestra desde /etc/issue.net.
  cat > "$motd_tmp" <<'ORANGEBOX_MOTD'
*******************************************************************************
                         ORANGEBOX IT SERVICES
*******************************************************************************
Sesion iniciada en un sistema administrado por OrangeBox.
Respete las politicas de uso de la organizacion.
*******************************************************************************
ORANGEBOX_MOTD

  for target in /etc/motd /etc/issue /etc/issue.net; do
    if [ "$target" = "/etc/motd" ]; then
      content_tmp="$motd_tmp"
    else
      content_tmp="$login_tmp"
    fi

    mode="$(stat -c '%a' "$target" 2>/dev/null || true)"
    owner="$(stat -c '%U' "$target" 2>/dev/null || true)"
    group="$(stat -c '%G' "$target" 2>/dev/null || true)"
    if [ -f "$target" ] && cmp -s "$content_tmp" "$target" && [ "$mode" = 644 ] && [ "$owner" = root ] && [ "$group" = root ]; then
      ok "$target ya contiene el mensaje OrangeBox correcto"
      continue
    fi
    if $AUTO_FIX; then
      [ ! -e "$target" ] || backup_once "$target"
      if install -o root -g root -m 644 "$content_tmp" "$target"; then
        if [ -f "$target" ] && cmp -s "$content_tmp" "$target" && [ "$(stat -c '%a' "$target" 2>/dev/null)" = 644 ] && [ "$(stat -c '%U' "$target" 2>/dev/null)" = root ] && [ "$(stat -c '%G' "$target" 2>/dev/null)" = root ]; then
          ok "$target actualizado (root:root 0644)"
          FIXED=$((FIXED+1))
        else
          warn "No se pudo verificar completamente $target"
        fi
      else
        warn "No se pudo escribir $target"
      fi
    else
      warn "$target requiere actualizar el contenido o los permisos"
    fi
  done

  rm -f "$login_tmp" "$motd_tmp"
  configure_ssh_banner
}
time_module(){ echo -e "\n$BLUE### TIME SYNC ###$NC"; command -v chronyc >/dev/null 2>&1&&chronyc tracking >/dev/null 2>&1&&ok "chrony operativo"||warn "NTP/chrony no verificado"; }
grub_module(){ echo -e "\n$BLUE### GRUB ###$NC"; find /boot /etc -maxdepth 4 -type f -name grub.cfg 2>/dev/null|head -1|grep -q .&&ok "grub.cfg localizado"||warn "grub.cfg no localizado"; info "GRUB no se modifica automáticamente; los parámetros de arranque requieren revisión específica"; }
firewall_module() {
  echo -e "\n$BLUE### FIREWALL ###$NC"
  local status rules
  if command -v shorewall >/dev/null 2>&1; then
    status="$(systemctl is-active shorewall 2>/dev/null || true)"
    if [ "$status" = "active" ]; then
      ok "Shorewall activo (firewall detectado)"
    else
      status="$(shorewall status 2>&1 || true)"
      if printf '%s\n' "$status" | grep -Eiq 'not running|stopped|inactive|is down'; then
        warn "Shorewall está instalado pero el estado indica que no está activo"
        printf '%s\n' "$status" | head -n 5
      elif printf '%s\n' "$status" | grep -Eiq 'running|active|started'; then
        ok "Shorewall activo (según shorewall status)"
      else
        ok "Shorewall detectado; verificar estado con: shorewall status"
        printf '%s\n' "$status" | head -n 5
      fi
    fi
    if command -v iptables-save >/dev/null 2>&1; then
      rules="$(iptables-save 2>/dev/null || true)"
      if printf '%s\n' "$rules" | grep -q '^-A '; then
        ok "Se detectan reglas de filtrado en iptables"
      else
        warn "Shorewall detectado, pero iptables-save no mostró reglas -A; revisar backend y estado de Shorewall"
      fi
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q .; then
      ok "Se detectan reglas de filtrado en nftables"
    else
      warn "No se pudo inspeccionar el ruleset efectivo; no se modifica el firewall"
    fi
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
    ok "firewalld activo"
  elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q .; then
    ok "nftables tiene un ruleset cargado"
  elif command -v iptables-save >/dev/null 2>&1 && iptables-save 2>/dev/null | grep -q '^-A '; then
    ok "iptables tiene reglas de filtrado cargadas"
  elif command -v firewall-cmd >/dev/null 2>&1; then
    warn "firewalld no activo y no se pudo confirmar otro ruleset mediante las comprobaciones básicas"
  else
    warn "No se detectó un backend de firewall con ruleset verificable"
  fi
  info "No se aplican reglas DROP automáticamente; el firewall debe revisarse y modificarse por separado"
}
fapolicyd_module() {
  echo -e "\n$BLUE### FAPOLICYD ###$NC"
  local installed=false active=false
  if [ -x /var/ossec/bin/wazuh-control ] || rpm -q wazuh-agent >/dev/null 2>&1 || rpm -q wazuh-manager >/dev/null 2>&1; then
    info "Wazuh detectado: según la política OrangeBox, el control de seguridad se gestiona con Wazuh; Linux-Hardening no instalará ni activará fapolicyd."
  fi
  rpm -q fapolicyd >/dev/null 2>&1 && installed=true
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet fapolicyd 2>/dev/null; then
    active=true
  fi
  if $installed && $active; then
    info "fapolicyd ya está activo; el baseline no lo modifica ni lo detiene."
  elif $installed; then
    info "fapolicyd está instalado pero inactivo; por política no se activa ni modifica."
  else
    info "fapolicyd no está instalado; por política no se instala ni se activa desde Linux-Hardening."
  fi
}
listening_module(){ echo -e "\n$BLUE### LISTENING SERVICES ###$NC"; command -v ss >/dev/null 2>&1&&ss -lntup 2>/dev/null||true; }
normalize_history_dotfile() {
  local file="$1" tmp
  [ -f "$file" ] || return 0
  if grep -Fq '# ORANGEBOX UNLIMITED HISTORY BEGIN' "$file" &&
     grep -Eq '^[[:space:]]*export[[:space:]]+HISTSIZE=-1[[:space:]]*$' "$file" &&
     grep -Eq '^[[:space:]]*export[[:space:]]+HISTFILESIZE=-1[[:space:]]*$' "$file" &&
     ! grep -Eq '^[[:space:]]*readonly[[:space:]]+HISTFILE([[:space:]]|$)' "$file" &&
     ! grep -Eq 'PROMPT_COMMAND=.*history -c; history -r|^[[:space:]]*PROMPT_COMMAND="orangebox_history_guard;' "$file"; then
    ok "$file: historial habilitado y sin límite"
    return 0
  fi
  if ! $AUTO_FIX; then
    warn "$file: se normalizará el historial a ilimitado al aplicar --fix"
    return 0
  fi

  backup_once "$file"
  tmp=$(mktemp) || { warn "No se pudo crear temporal para $file"; return 1; }
  awk '
    $0 == "# ORANGEBOX UNLIMITED HISTORY BEGIN" { skip=1; next }
    $0 == "# ORANGEBOX UNLIMITED HISTORY END" { skip=0; next }
    skip { next }
    # Remove legacy code that clears/reloads all history on every prompt.
    /^export PROMPT_COMMAND="history -a; history -c; history -r;/ { next }
    /^PROMPT_COMMAND="orangebox_history_guard; / { next }
    /^orangebox_history_guard\(\) \{$/ { skip_guard=1; next }
    skip_guard && /^\}$/ { skip_guard=0; next }
    skip_guard { next }
    /^[[:space:]]*readonly[[:space:]]+HISTFILE([[:space:]]|$)/ { next }
    { print }
  ' "$file" > "$tmp" || { rm -f "$tmp"; warn "No se pudo leer $file"; return 1; }
  cat >> "$tmp" <<'ORANGEBOX_UNLIMITED_HISTORY'
# ORANGEBOX UNLIMITED HISTORY BEGIN
# El historial interactivo se conserva completo, sin límite de líneas.
set -o history
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTCONTROL=
unset HISTIGNORE
case "${HISTFILE:-}" in
  ""|/dev/null|/dev/zero|/var/log/bash_history/*) export HISTFILE="$HOME/.bash_history" ;;
esac
shopt -s histappend
# ORANGEBOX UNLIMITED HISTORY END
ORANGEBOX_UNLIMITED_HISTORY
  chmod --reference="$file" "$tmp" 2>/dev/null || chmod 644 "$tmp"
  chown --reference="$file" "$tmp" 2>/dev/null || chown root:root "$tmp"
  if mv "$tmp" "$file"; then
    ok "$file: historial habilitado y sin límite"
    FIXED=$((FIXED+1))
  else
    rm -f "$tmp"
    warn "No se pudo instalar configuración de historial en $file"
    return 1
  fi
}

bash_module() {
  echo -e "\n$BLUE### BASH / HISTORIAL / PROMPT ###$NC"
  local target=/etc/profile.d/99-orangebox-linux-hardening.sh tmp f
  [ -d /etc/profile.d ] || { warn "/etc/profile.d no existe"; return; }

  # Detectar directivas que suelen deshabilitar el historial.
  for f in /etc/profile /etc/bashrc /etc/profile.d/*.sh /root/.bash_profile /root/.bashrc; do
    [ -f "$f" ] || continue
    if grep -Eiq '(^|[[:space:]])(export[[:space:]]+)?(HISTSIZE|HISTFILESIZE)[[:space:]]*=[[:space:]]*0([[:space:]]|$)|(^|[[:space:]])(export[[:space:]]+)?HISTFILE[[:space:]]*=[[:space:]]*"?(/dev/null|/dev/zero)"?([[:space:]]|$)|^[[:space:]]*unset[[:space:]]+HISTFILE([[:space:]]|$)|^[[:space:]]*set[[:space:]]+\+[[:space:]]*o[[:space:]]+history([[:space:]]|$)' "$f"; then
      warn "Posible deshabilitación de Bash History detectada en $f; se revisará la configuración efectiva"
    fi
  done

  tmp="$(mktemp)" || { warn "No se pudo crear temporal para Bash"; return; }
  cat > "$tmp" <<'ORANGEBOX_BASH'
# OrangeBox Linux Hardening - historial ilimitado y prompt por rol
# Solo se aplica a shells interactivos.
case $- in
  *i*) ;;
  *) return 0 ;;
esac

# Protección de mejor esfuerzo: impedir borrado/sobrescritura accidental por
# los comandos comunes "history -c", "history -d" y "history -w".
# No es una frontera de seguridad: "builtin history", edición del archivo o
# modificación de la shell pueden eludir este wrapper.
history() {
  local arg opts
  for arg in "$@"; do
    case "$arg" in
      --) break ;;
      -?*)
        opts="${arg#-}"
        case "$opts" in
          *c*|*d*|*w*)
            printf '%s\n' 'OrangeBox: bloqueado history -c/-d/-w para proteger el historial de esta sesión.' >&2
            return 2
            ;;
        esac
        case "$opts" in
          *p*|*s*) break ;;
        esac
        ;;
      *) break ;;
    esac
  done
  builtin history "$@"
}

orangebox_history_guard() {
  set -o history 2>/dev/null || true
  HISTSIZE=-1
  HISTFILESIZE=-1
  case "${HISTFILE:-}" in
    ""|/dev/null|/dev/zero|/var/log/bash_history/*) HISTFILE="${HOME}/.bash_history" ;;
  esac
  export HISTSIZE HISTFILESIZE HISTFILE
  HISTCONTROL=
  export HISTCONTROL
  unset HISTIGNORE
  shopt -s histappend
}

export HISTTIMEFORMAT='%F %T '
orangebox_history_guard

orangebox_secure_history_file() {
  [ -n "${HOME:-}" ] && [ -d "$HOME" ] || return 0
  [ "$HISTFILE" = "$HOME/.bash_history" ] || return 0
  if [ ! -e "$HISTFILE" ]; then (umask 077; : > "$HISTFILE") 2>/dev/null || true; fi
  if [ -f "$HISTFILE" ] && [ -O "$HISTFILE" ]; then chmod 600 "$HISTFILE" 2>/dev/null || true; fi
}
orangebox_secure_history_file

# Normalizar la edición de línea en Bash para administración.
# Ctrl+A = inicio de línea; Ctrl+E = final de línea.
# No depender de un ~/.inputrc o /etc/inputrc personalizado.
set -o emacs 2>/dev/null || true
bind '"\C-a": beginning-of-line' 2>/dev/null || true
bind '"\C-e": end-of-line' 2>/dev/null || true

# Resolver hostname FQDN una vez por shell; evitar consultas en cada prompt.
ORANGEBOX_PROMPT_HOST="$(hostname -f 2>/dev/null || true)"
case "$ORANGEBOX_PROMPT_HOST" in
  ""|localhost|localhost.localdomain) ORANGEBOX_PROMPT_HOST="$(hostname 2>/dev/null || true)" ;;
esac
[ -n "$ORANGEBOX_PROMPT_HOST" ] || ORANGEBOX_PROMPT_HOST=unknown

# Fijar el prompt antes de cada indicador; otros perfiles pueden redefinir PS1.
orangebox_set_prompt() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    PS1='\[\e[2m\]\D{%H:%M:%S}\[\e[0m\] \[\e[1;31m\]\u@'"$ORANGEBOX_PROMPT_HOST"' \w #\[\e[0m\] '
  else
    PS1='\[\e[2m\]\D{%H:%M:%S}\[\e[0m\] \[\e[1;32m\]\u@'"$ORANGEBOX_PROMPT_HOST"' \w $\[\e[0m\] '
  fi
}

orangebox_pre_prompt() {
  # /root/.bashrc puede activar "set -o vi" después de cargar este perfil.
  # Reafirmar el modo Emacs y las teclas antes de presentar cada prompt.
  set -o emacs 2>/dev/null || true
  bind '"\C-a": beginning-of-line' 2>/dev/null || true
  bind '"\C-e": end-of-line' 2>/dev/null || true
  orangebox_history_guard
  history -a
  orangebox_set_prompt
}
case ";${PROMPT_COMMAND:-};" in
  *";orangebox_pre_prompt;"*|*"; orangebox_pre_prompt;"*) ;;
  *)
    if [ -n "${PROMPT_COMMAND:-}" ]; then
      PROMPT_COMMAND="${PROMPT_COMMAND}; orangebox_pre_prompt"
    else
      PROMPT_COMMAND="orangebox_pre_prompt"
    fi
    ;;
esac
export PROMPT_COMMAND
orangebox_set_prompt
ORANGEBOX_BASH

  if [ -f "$target" ] && cmp -s "$tmp" "$target" &&
     [ "$(stat -c '%a' "$target" 2>/dev/null)" = 644 ] &&
     [ "$(stat -c '%U' "$target" 2>/dev/null)" = root ] &&
     [ "$(stat -c '%G' "$target" 2>/dev/null)" = root ]; then
    ok "Bash History habilitado e ilimitado; prompt OrangeBox ya configurado"
  elif $AUTO_FIX; then
    [ ! -e "$target" ] || backup_once "$target"
    if install -o root -g root -m 644 "$tmp" "$target" && cmp -s "$tmp" "$target"; then
      ok "Bash History habilitado sin límite y prompt por rol aplicado en $target"
      FIXED=$((FIXED+1))
    else
      warn "No se pudo instalar/verificar $target"
    fi
  else
    warn "$target requiere habilitar Bash History y establecer HISTSIZE/HISTFILESIZE=-1"
  fi
  rm -f "$tmp"

  # Normalizar también los dotfiles administrados más sensibles sin tocar
  # aliases, umask, timeout ni el resto de las preferencias existentes.
  normalize_history_dotfile /root/.bashrc
  normalize_history_dotfile /etc/skel/.bashrc

  # CentOS/RHEL inicia shells interactivos no-login desde /etc/bashrc.
  local system_bashrc=/etc/bashrc
  if [ -f "$system_bashrc" ] && ! grep -Fq '# OrangeBox Linux Hardening managed shell config' "$system_bashrc"; then
    if $AUTO_FIX; then
      backup_once "$system_bashrc"
      if printf '\n%s\n%s\n' \
        '# OrangeBox Linux Hardening managed shell config' \
        '[ -r /etc/profile.d/99-orangebox-linux-hardening.sh ] && . /etc/profile.d/99-orangebox-linux-hardening.sh' \
        >> "$system_bashrc"; then
        ok "Include idempotente agregado a /etc/bashrc para shells interactivos no-login"
        FIXED=$((FIXED+1))
      else
        warn "No se pudo añadir el include a /etc/bashrc"
      fi
    else
      warn "/etc/bashrc no incluye el perfil OrangeBox para shells no-login"
    fi
  fi
}

usage() {
  cat <<EOF
OrangeBox Linux Hardening $SCRIPT_VERSION

Uso:
  $0                                Auditoría del baseline interno
  $0 --fix                          Modo interactivo: explica los riesgos y pregunta
  $0 --fix --auto                   Aplica banners/Bash; audita y omite los módulos delicados
  ./linux-hardening-audit.sh         Auditoría agregada, separada y de solo lectura
  $0 --fix --module banners         Fuerza MOTD, /etc/issue, /etc/issue.net y banner SSH
  $0 --fix --module bash            Historial con fecha/hora y prompt por rol
  $0 --fix --module synflood        Aplica SYN cookies, backlog y reintentos TCP persistentes
  $0 --fix --module network-full --allow-shorewall
                                    Autoriza explícitamente cambios de red con Shorewall
  $0 --module <modulo> [--fix] [--auto] [--allow-risky]

Baseline interno:
  ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron
  usb services banners time grub firewall fapolicyd listening bash all

Módulos adicionales:
  aide audit-listeners auditd-full bash-full time-sync cpu-full cron-full
  packages-remove services-remove usb-storage grub-full kernel-full lpe-2026
  network-full password-full gui-remove xinetd-remove rsyslog-full
  selinux-setup ssh-cis ssh-complete sudo-full filesystem-full

Evaluaciones independientes:
  ./cis-benchmark-check.sh       Evalúa exclusivamente el benchmark CIS.
  ./linux-hardening-audit.sh    Audita los módulos, sin calcular cumplimiento CIS.

Seguridad:
  --fix pregunta antes de cambios de riesgo y explica brevemente su impacto.
  --fix --auto no hace preguntas: aplica únicamente banners/MOTD y Bash. Kernel, SYN flood y los demás módulos delicados quedan en auditoría sin aplicar cambios.
  --allow-risky omite las preguntas y autoriza los módulos clasificados como riesgosos.
  --allow-shorewall es una autorización separada para ejecutar network-full con Shorewall.
  --module firewall-rules está bloqueado: el generador de iptables vacía reglas y
  aplica INPUT DROP, incompatible con la administración actual mediante Shorewall.
  post-install se omite: no tiene una ruta de auditoría de solo lectura.
  El benchmark CIS no se ejecuta como módulo; utiliza el comando independiente indicado arriba.
EOF
}

internal_module_requires_risk() {
  case "$1" in
    ssh|sudo|kernel|synflood|rsyslog) return 0 ;;
    *) return 1 ;;
  esac
}

risk_description() {
  case "$1" in
    ssh) echo "añade controles a sshd (intentos, tiempos de sesión y autenticación por host). Se valida la sintaxis; aun así, revisa clientes e integraciones SSH." ;;
    sudo) echo "revisa controles de sudo; use_pty solo se considera en servidores sin cPanel y requiere una confirmación específica." ;;
    kernel) echo "aplica el baseline sysctl acordado sin modificar net.ipv4.ip_forward; si el forwarding está activo usa rp_filter=2 (loose) para reducir el riesgo de descartar tráfico asimétrico." ;;
    synflood) echo "habilita SYN cookies y persiste backlog TCP/reintentos recomendados; no cambia net.ipv4.ip_forward." ;;
    rsyslog|rsyslog-full) echo "activa almacenamiento persistente de journald y reinicia journald; revisa espacio, retención y logging existente." ;;
    network-full) echo "cambia sysctl de red y bloquea módulos de kernel (por ejemplo SCTP/RDS/DCCP/TIPC); puede afectar VPN, routing o aplicaciones que usen esos protocolos." ;;
    firewall|firewall-rules) echo "modifica o reemplaza el filtrado. El generador de iptables está bloqueado porque vacía reglas y establece INPUT DROP; no se ejecutará sobre Shorewall." ;;
    ssh-cis|ssh-complete) echo "modifica parámetros de SSH y/o algoritmos criptográficos. Puede dejar fuera clientes antiguos, automatizaciones o el acceso administrativo." ;;
    password|password-full) echo "cambia política de contraseñas o valores por defecto. No se editará PAM a ciegas, pero podría afectar autenticación o futuras contraseñas." ;;
    filesystem|filesystem-full) echo "puede restringir montajes, ocultar procesos con hidepid, bloquear módulos o deshabilitar autofs; podría afectar monitoreo y aplicaciones." ;;
    cron|cron-full) echo "puede cambiar permisos de cron/at y crear listas allow limitadas a root, impidiendo tareas de usuarios o de hosting/cPanel." ;;
    selinux|selinux-setup) echo "solo informa el estado actual; SELinux no se modifica desde este repositorio." ;;
    grub|grub-full) echo "cambia parámetros del arranque y regenera grub.cfg; el efecto pleno requiere reinicio y un error puede impedir arrancar." ;;
    kernel-full|lpe-2026) echo "cambia mitigaciones de kernel/sysctl o bloquea módulos/namespaces; puede afectar contenedores, VPN y requiere reinicio para algunos efectos." ;;
    auditd|auditd-full) echo "modifica reglas y servicio de auditoría; puede incrementar volumen de eventos y afectar configuración de auditd existente." ;;
    time|time-sync) echo "puede cambiar el servicio de sincronización o dar un salto de hora; puede afectar certificados, autenticación y correlación de logs." ;;
    usb|usb-storage) echo "bloquea almacenamiento USB mediante modprobe; puede afectar dispositivos o flujos de recuperación que dependan de USB." ;;
    services|services-remove|packages-remove|xinetd-remove|gui-remove) echo "puede detener/deshabilitar servicios o eliminar paquetes y dependencias; podría afectar aplicaciones instaladas." ;;
    aide) echo "instala AIDE y crea una base de integridad; puede solaparse con Wazuh FIM y consumir espacio/CPU. El instalador explicará ese solapamiento y pedirá consentimiento explícito." ;;
    bash-full) echo "instala auditoría amplia de comandos mediante trap DEBUG/syslog; puede aumentar volumen y registrar argumentos sensibles." ;;
    post-install) echo "script para preparación inicial que puede tocar SELinux, GRUB y paquetes; está bloqueado en modo aplicación desde este orquestador." ;;
    *) echo "este módulo puede modificar configuración o servicios; revisa el alcance y conserva una vía de recuperación." ;;
  esac
}

confirm_risky_change() {
  local name="$1" answer description
  description="$(risk_description "$name")"
  echo
  echo -e "$YELLOW[ATENCIÓN] Control con riesgo operacional: $name$NC"
  echo "Qué hará: $description"
  if [ "$AUTO_MODE" = true ]; then
    warn "Modo --auto: cambio omitido; no se aplican controles críticos."
    return 1
  fi
  if [ "$ALLOW_RISKY" = true ]; then
    ok "--allow-risky autoriza aplicar este control sin confirmación adicional."
    return 0
  fi
  if [ ! -r /dev/tty ]; then
    warn "No hay terminal disponible para confirmar; el cambio se omitirá por seguridad."
    return 1
  fi
  read -r -p "¿Quieres aplicar '$name'? [s/N]: " answer </dev/tty
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) warn "Control '$name' rechazado por el usuario; se mantiene en auditoría."; return 1 ;;
  esac
}

run_internal_module_with_confirmation() {
  local name="$1" previous_fix="$AUTO_FIX"
  if [ "$AUTO_FIX" = true ] && internal_module_requires_risk "$name"; then
    if ! confirm_risky_change "$name"; then
      AUTO_FIX=false
      run_module "$name"
      AUTO_FIX="$previous_fix"
      return 0
    fi
  fi
  run_module "$name"
}

run_companion_module() {
  local name="$1" script="" fix_arg="--fix" audit_arg="" risky=false audit_only=false block_fix=false interactive=false
  if [ "$name" = "cis" ]; then
    die "El benchmark CIS es independiente de los módulos de hardening. Ejecuta: ./cis-benchmark-check.sh"
  fi
  case "$name" in
    aide) script="aide-install.sh"; risky=true ;;
    audit-listeners) script="audit-listening-services.sh"; audit_only=true; fix_arg="" ;;
    auditd-full) script="auditd-hardening.sh"; risky=true ;;
    bash-full) script="bash-hardening.sh"; risky=true ;;
    time-sync) script="configure-time-sync.sh"; risky=true ;;
    cpu-full) script="cpu-hardening.sh"; risky=true ;;
    cron-full) script="cron-hardening.sh"; risky=true ;;
    packages-remove) script="desintalar-paquetes-sin-usar.sh"; risky=true; interactive=true; fix_arg="" ;;
    services-remove) script="desintalar-servicios-sin-usar.sh"; risky=true; interactive=true; fix_arg="" ;;
    usb-storage) script="disable-usb-storage.sh"; risky=true ;;
    firewall-rules)
      die "Módulo bloqueado: generate-iptables-rules.sh vacía reglas, establece INPUT DROP y podría cortar SSH. En este host se usa Shorewall; no se aplicará un segundo firewall destructivo."
      ;;
    grub-full) script="grub-hardening.sh"; risky=true ;;
    kernel-full) script="kernel-hardening.sh"; risky=true ;;
    lpe-2026) script="kernel-lpe-2026-mitigation.sh"; risky=true; audit_arg="--check" ;;
    network-full) script="network-hardening.sh"; risky=true ;;
    password-full) script="password-hardening.sh"; risky=true ;;
    post-install)
      if [ "$AUTO_FIX" = true ]; then
        die "post-install no se ejecuta desde el orquestador: no dispone de una ruta de auditoría de solo lectura y puede cambiar el host."
      fi
      warn "Se omite post-install: puede instalar paquetes, cambiar SELinux/GRUB y habilitar servicios incluso sin --fix."
      return 0
      ;;
    gui-remove) script="remove-gui-hardening.sh"; risky=true; audit_arg="--check" ;;
    xinetd-remove) script="remove-xinetd.sh"; risky=true ;;
    rsyslog-full) script="rsyslog-hardening.sh"; risky=true ;;
    selinux-setup)
      info "selinux-setup bloqueado por política OrangeBox: SELinux solo se audita; nunca se cambian su modo, configuración, contextos ni se solicita reinicio."
      if command -v getenforce >/dev/null 2>&1; then
        info "Estado SELinux actual: $(getenforce 2>/dev/null || echo desconocido)"
      else
        warn "getenforce no disponible; no se puede determinar el estado actual de SELinux"
      fi
      return 0
      ;;
    ssh-cis) script="ssh-hardening.sh"; risky=true ;;
    ssh-complete) script="ssh-hardening-complete.sh"; risky=true ;;
    sudo-full) script="sudo-hardening.sh"; risky=true ;;
    filesystem-full) script="FS-hardening.sh"; risky=true; audit_arg="--check"; fix_arg="" ;;

    *) die "Módulo desconocido: $name" ;;
  esac

  local apply_fix="$AUTO_FIX" skip_without_audit=false
  if [ "$AUTO_FIX" = true ] && [ "$block_fix" = true ] && [ "$AUTO_MODE" != true ]; then
    die "Se bloquea --fix para $name: es para preparación inicial y puede modificar SELinux, GRUB y paquetes. Ejecuta el script aparte después de revisar el host."
  fi

  if [ "$AUTO_FIX" = true ] && [ "$risky" = true ]; then
    if [ "$AUTO_MODE" = true ]; then
      echo
      echo -e "$YELLOW[--auto] Se omitirá la aplicación de '$name'.$NC"
      echo "Qué haría: $(risk_description "$name")"
      apply_fix=false
    elif [ "$name" = "aide" ] && ! rpm -q aide >/dev/null 2>&1; then
      info "AIDE no está instalado; aide-install.sh explicará sus efectos y solicitará consentimiento explícito."
    elif ! confirm_risky_change "$name"; then
      apply_fix=false
    fi
    if [ "$apply_fix" != true ] && [ -z "$audit_arg" ] && [ "$audit_only" != true ]; then
      warn "No se ejecutó '$name': no tiene una ruta de auditoría segura declarada en el orquestador."
      return 0
    fi
  fi

  if [ ! -f "$SCRIPT_DIR/$script" ]; then
    die "No existe $SCRIPT_DIR/$script. Ejecuta este módulo desde el checkout completo del repositorio."
  fi
  if [ "$apply_fix" != true ] && [ "$interactive" = true ]; then
    warn "$name no ofrece auditoría no interactiva; se omite."
    return 0
  fi

  local -a args=()
  if [ "$apply_fix" = true ]; then
    if [ "$audit_only" = true ]; then
      warn "$name es de auditoría: no se aplicarán cambios desde este módulo."
    elif [ "$name" = "network-full" ]; then
      args=(--fix)
      if [ "$ALLOW_SHOREWALL" = true ]; then
        args+=(--allow-shorewall)
      fi
    elif [ -n "$fix_arg" ]; then
      args=("$fix_arg")
    fi
  elif [ -n "$audit_arg" ]; then
    args=("$audit_arg")
  fi
  echo
  echo "========== MÓDULO DEL REPOSITORIO: $name ($script) =========="
  if bash "$SCRIPT_DIR/$script" "${args[@]}"; then
    ok "Módulo $name finalizado"
  else
    warn "Módulo $name terminó con código distinto de cero; revisar la salida anterior"
  fi
}

run_module() {
  case "$1" in
    ssh) ssh_module ;;
    sudo) sudo_module ;;
    password) password_module ;;
    kernel) kernel_module ;;
    synflood) synflood_module ;;
    filesystem) filesystem_module ;;
    auditd) auditd_module ;;
    rsyslog) rsyslog_module ;;
    selinux) selinux_module ;;
    cron) cron_module ;;
    usb) usb_module ;;
    services) services_module ;;
    banners) banners_module ;;
    time) time_module ;;
    grub) grub_module ;;
    firewall) firewall_module ;;
    fapolicyd) fapolicyd_module ;;
    listening) listening_module ;;
    bash) bash_module ;;
    *) run_companion_module "$1" ;;
  esac
}

main() {
  require_root
  while [ $# -gt 0 ]; do
    case "$1" in
      --fix|-f) AUTO_FIX=true ;;
      --auto) AUTO_MODE=true ;;
      --allow-risky) ALLOW_RISKY=true ;;
      --allow-shorewall) ALLOW_SHOREWALL=true ;;
      --module|-m) shift; [ $# -gt 0 ] || die "--module requiere nombre"; MODULE="$1" ;;
      --help|-h) usage; exit 0 ;;
      --list-modules) usage; exit 0 ;;
      *) die "Argumento desconocido: $1" ;;
    esac
    shift
  done

  if [ "$AUTO_MODE" = true ] && [ "$AUTO_FIX" != true ]; then
    die "--auto requiere --fix. Usa --fix --auto para aplicar únicamente controles seguros."
  fi
  if [ "$AUTO_MODE" = true ] && [ "$ALLOW_RISKY" = true ]; then
    die "--auto y --allow-risky son incompatibles: --auto siempre omite controles críticos."
  fi
  if [ "$ALLOW_SHOREWALL" = true ] && [ "$MODULE" != "network-full" ]; then
    warn "--allow-shorewall solo se utiliza con --module network-full."
  fi

  if [ "$MODULE" = "repo-audit" ]; then
    die "La auditoría agregada se separó del orquestador de hardening. Ejecuta: ./linux-hardening-audit.sh"
  fi

  detect_os
  if [ "$AUTO_FIX" = true ]; then
    prepare_backup
  fi

  if [ "$MODULE" = "all" ] && [ "$AUTO_FIX" = true ] && [ "$AUTO_MODE" = true ]; then
    warn "MODO --FIX --AUTO: se aplican banners/MOTD y Bash; los módulos delicados (incluidos kernel/SYN flood) quedan en auditoría."
    run_module banners
    run_module bash

    local previous_fix="$AUTO_FIX" m
    AUTO_FIX=false
    for m in ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services time grub firewall fapolicyd listening; do
      run_module "$m"
    done
    AUTO_FIX="$previous_fix"
    echo
    echo "Modo automático terminado: solo se aplicaron banners/MOTD y Bash; los módulos delicados quedaron en auditoría sin cambios."
  elif [ "$MODULE" = "all" ] && [ "$AUTO_FIX" = true ]; then
    echo -e "$BLUE[INFO]$NC MODO --FIX INTERACTIVO: banners/MOTD y Bash se aplican directamente; cada módulo delicado pregunta por separado y explica su impacto antes de cambiar el sistema."
    echo -e "$BLUE[INFO]$NC Si no hay terminal o se responde No, ese módulo no cambia el sistema y se muestra en auditoría."
    run_module banners
    run_module bash

    local m
    for m in ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services time grub firewall fapolicyd listening; do
      run_internal_module_with_confirmation "$m"
    done

    # AIDE is optional because Wazuh FIM may already cover the same files.
    # Its installer owns the consent prompt and must explain that tradeoff.
    run_module aide
  elif [ "$MODULE" = "all" ]; then
    ok "MODO AUDITORÍA: sin cambios"
    local m
    for m in ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash; do
      run_module "$m"
    done
  else
    if [ "$AUTO_FIX" = true ]; then
      echo -e "$BLUE[INFO]$NC MODO FIX: módulo seleccionado=$MODULE"
    else
      ok "MODO AUDITORÍA: módulo seleccionado=$MODULE"
    fi
    if [ "$AUTO_FIX" = true ] && internal_module_requires_risk "$MODULE"; then
      if [ "$AUTO_MODE" = true ]; then
        echo
        echo -e "$YELLOW[--auto] Se omitirá la aplicación del módulo '$MODULE'.$NC"
        echo "Qué haría: $(risk_description "$MODULE")"
        local previous_fix="$AUTO_FIX"
        AUTO_FIX=false
        run_module "$MODULE"
        AUTO_FIX="$previous_fix"
      else
        run_internal_module_with_confirmation "$MODULE"
      fi
    else
      run_module "$MODULE"
    fi
  fi

  echo -e "\n$GREEN============================================================$NC"
  echo -e "$GREEN OrangeBox Linux Hardening $SCRIPT_VERSION - FIN $NC"
  echo "Correcciones: $FIXED"
  echo "Advertencias: $WARNINGS"
  echo "Errores: $ERRORS"
  if [ "$AUTO_FIX" = true ]; then
    echo "Backup: $BACKUP_DIR"
  else
    echo "Backup: no creado (modo auditoría)"
  fi
  echo -e "$GREEN============================================================$NC"
}
main "$@"
