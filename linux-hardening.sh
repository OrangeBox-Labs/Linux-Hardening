#!/bin/bash
# OrangeBox Linux Hardening - Mega Script
# Version 1.2.0 - RHEL/CentOS/Rocky/AlmaLinux 6-10
# AUDIT by default. --fix applies conservative controls only.
# SSH crypto is configured directly in OpenSSH.
# IMPORTANT: update-crypto-policies and /etc/crypto-policies are NEVER touched.

set -u
VERSION=1.2.0
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
    die "No se pudo detectar sistema: faltan os-release y redhat-release."
  fi
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

# Dedicated network profile; explicit opt-in because TCP retry values affect connection reliability.
# Generic OrangeBox profile: this applies to supported Linux Enterprise servers, not only cPanel.
SYNFLOOD_FILE=/etc/sysctl.d/99-orangebox-synflood-hardening.conf
SYNFLOOD_LEGACY_FILE=/etc/sysctl.d/99-cpanel-synflood-hardening.conf
SYNFLOOD_KEYS="net.ipv4.tcp_syncookies net.ipv4.tcp_max_syn_backlog net.core.somaxconn net.ipv4.tcp_synack_retries net.ipv4.tcp_syn_retries"
SYNFLOOD_VALUES="1 4096 4096 2 2"

ask_synflood(){ [ "$INTERACTIVE" = true ] || return 0; while true; do printf "%s [y/N]: " "$1"; read -r answer || return 1; case "$answer" in y|Y|yes|YES) return 0;; n|N|no|NO|"") return 1;; *) echo "Responde y o n.";; esac; done; }
synflood_value(){ local f="$1" k="$2"; awk -v key="$k" '$0 ~ "^[[:space:]]*" key "[[:space:]]*=" {v=$0;sub(/^[^=]*=[[:space:]]*/,"",v);sub(/[[:space:]#].*$/,"",v);got=v} END{if(got!="")print got}' "$f" 2>/dev/null; }
synflood_managed_profile(){
  local f="$1"
  [ -f "$f" ] &&
    grep -Fqx "# OrangeBox managed SYN flood profile" "$f" &&
    grep -Fqx "# BEGIN ORANGEBOX SYNFLOOD" "$f" &&
    grep -Fqx "# END ORANGEBOX SYNFLOOD" "$f"
}
synflood_module(){
  echo -e "\n$BLUE### SYN FLOOD / TCP BACKLOG ###$NC"
  [ -d /etc/sysctl.d ] || { warn "/etc/sysctl.d no existe; revisión manual requerida"; return 1; }

  if [ -e "$SYNFLOOD_FILE" ] && [ -e "$SYNFLOOD_LEGACY_FILE" ]; then
    warn "Existen ambos perfiles SYN flood (nuevo y antiguo); no se modifican para evitar duplicados. Revisa ambos archivos."
    return 1
  fi

  local profile_source="$SYNFLOOD_FILE"
  if [ -e "$SYNFLOOD_FILE" ]; then
    synflood_managed_profile "$SYNFLOOD_FILE" || {
      warn "$SYNFLOOD_FILE existe pero no parece gestionado por OrangeBox; no se sobrescribe."
      return 1
    }
  elif synflood_managed_profile "$SYNFLOOD_LEGACY_FILE"; then
    profile_source="$SYNFLOOD_LEGACY_FILE"
    warn "Se detectó el perfil OrangeBox con nombre cPanel antiguo; se migrará al nombre genérico si se aceptan cambios."
  fi

  local idx key current desired cfg external external_count migration_candidate
  local picked_keys="" picked_values=""
  idx=1
  for key in $SYNFLOOD_KEYS; do
    current=$(sysctl -n "$key" 2>/dev/null || true)
    desired=$(printf "%s\n" "$SYNFLOOD_VALUES" | awk -v n="$idx" 'NR==n{print}')
    if [ -z "$current" ]; then
      warn "$key no existe en el kernel; omitido"
      idx=$((idx+1))
      continue
    fi

    external=""
    migration_candidate=""
    for cfg in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
      [ -f "$cfg" ] || continue
      [ "$cfg" = "$SYNFLOOD_FILE" ] && continue
      [ "$cfg" = "$profile_source" ] && continue
      if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$cfg"; then
        external_count=$(grep -Ec "^[[:space:]]*$key[[:space:]]*=" "$cfg" || true)
        if [ "$key" = "net.ipv4.tcp_syncookies" ] &&
           [ "$cfg" = "/etc/sysctl.d/99-orangebox-hardening.conf" ] &&
           [ "$external_count" = "1" ] &&
           [ "$(synflood_value "$cfg" "$key")" = "$desired" ]; then
          migration_candidate="$cfg"
          continue
        fi
        external="$cfg"
        break
      fi
    done

    if [ -n "$external" ]; then
      warn "$key definido en $external; se omite para evitar duplicados"
      idx=$((idx+1))
      continue
    fi
    [ -n "$migration_candidate" ] && warn "$key se migrará desde el perfil OrangeBox genérico con respaldo"

    [ "$current" = "$desired" ] && ok "$key=$desired" || warn "$key actual=$current requerido=$desired"
    if [ "$INTERACTIVE" = true ]; then
      ask_synflood "Aplicar $key=$desired?" || { idx=$((idx+1)); continue; }
    elif [ "$AUTO_FIX" != true ]; then
      idx=$((idx+1))
      continue
    fi
    picked_keys="$picked_keys $key"
    picked_values="$picked_values $desired"
    idx=$((idx+1))
  done

  [ -n "$picked_keys" ] || {
    ok "No hay cambios aceptados/necesarios; sin modificaciones"
    return 0
  }

  local state="$BACKUP_DIR/synflood"
  local legacy=/etc/sysctl.d/99-orangebox-hardening.conf
  local tmp value selected_value preserved selected_index active
  mkdir -p "$state" || die "No se pudo crear estado rollback"
  chmod 700 "$state" || die "No se pudo proteger estado rollback"

  if [ -e "$profile_source" ]; then
    echo yes > "$state/profile-existed"
    backup_once "$profile_source" || die "No se pudo respaldar el perfil SYN flood original."
  else
    echo no > "$state/profile-existed"
  fi
  printf "%s\n" "$profile_source" > "$state/profile-source-path"
  printf "%s\n" "$SYNFLOOD_FILE" > "$state/profile-target-path"

  if [ -e "$legacy" ]; then
    echo yes > "$state/legacy-existed"
    backup_once "$legacy" || die "No se pudo respaldar el perfil genérico antes de migrar tcp_syncookies."
  else
    echo no > "$state/legacy-existed"
  fi
  : > "$state/runtime.before"
  for key in $SYNFLOOD_KEYS; do
    value=$(sysctl -n "$key" 2>/dev/null || true)
    printf "%s|%s\n" "$key" "$value" >> "$state/runtime.before"
  done
  chmod 600 "$state/runtime.before"
  echo "$RUN_ID" > "$state/run-id"

  tmp=$(mktemp "$SYNFLOOD_FILE.XXXXXX") || die "No se pudo crear temporal de perfil"
  if [ -e "$profile_source" ]; then
    awk '$0=="# BEGIN ORANGEBOX SYNFLOOD"{inside=1;next} $0=="# END ORANGEBOX SYNFLOOD"{inside=0;next} !inside && $0!="# OrangeBox managed SYN flood profile"{print}' "$profile_source" > "$tmp" ||
      { rm -f "$tmp"; die "No se pudo leer perfil actual"; }
  fi

  {
    [ ! -s "$tmp" ] || printf "\n"
    echo "# OrangeBox managed SYN flood profile"
    echo "# BEGIN ORANGEBOX SYNFLOOD"
    idx=1
    for key in $SYNFLOOD_KEYS; do
      selected_value=""
      selected_index=1
      for active in $picked_keys; do
        if [ "$key" = "$active" ]; then
          selected_value=$(printf "%s\n" "$picked_values" | awk -v n="$selected_index" 'NR==n{print}')
          break
        fi
        selected_index=$((selected_index+1))
      done
      if [ -n "$selected_value" ]; then
        printf "%s = %s\n" "$key" "$selected_value"
      elif [ -e "$profile_source" ]; then
        preserved=$(synflood_value "$profile_source" "$key")
        case "$preserved" in
          ''|*[!0-9]*) ;;
          *) printf "%s = %s\n" "$key" "$preserved";;
        esac
      fi
      idx=$((idx+1))
    done
    echo "# END ORANGEBOX SYNFLOOD"
  } >> "$tmp" || { rm -f "$tmp"; die "No se pudo construir perfil"; }

  chmod 644 "$tmp" || { rm -f "$tmp"; die "No se pudo ajustar permisos"; }
  chown root:root "$tmp" 2>/dev/null || true
  awk '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} /^[[:space:]]*[a-zA-Z0-9_.]+[[:space:]]*=[[:space:]]*[0-9]+[[:space:]]*$/ {next} {exit 1}' "$tmp" ||
    { rm -f "$tmp"; die "Perfil temporal inválido"; }

  if ! cmp -s "$tmp" "$SYNFLOOD_FILE" 2>/dev/null; then
    mv "$tmp" "$SYNFLOOD_FILE" || { rm -f "$tmp"; die "No se pudo instalar perfil"; }
    FIXED=$((FIXED+1))
  else
    rm -f "$tmp"
  fi

  # After the generic profile is installed, remove the old filename only if managed.
  if [ "$profile_source" != "$SYNFLOOD_FILE" ] && [ "$profile_source" = "$SYNFLOOD_LEGACY_FILE" ]; then
    synflood_managed_profile "$profile_source" || {
      warn "El perfil anterior dejó de ser reconocido como gestionado; no se elimina."
      return 1
    }
    rm -f "$profile_source" || {
      warn "No se pudo retirar el perfil antiguo $profile_source; rollback disponible: $0 --rollback $RUN_ID."
      return 1
    }
    ok "Perfil antiguo migrado desde $profile_source a $SYNFLOOD_FILE."
  fi

  idx=1
  for key in $picked_keys; do
    desired=$(printf "%s\n" "$picked_values" | awk -v n="$idx" 'NR==n{print}')
    if ! sysctl -w "$key=$desired" >/dev/null 2>&1 || [ "$(sysctl -n "$key" 2>/dev/null || true)" != "$desired" ]; then
      warn "No se pudo aplicar/verificar $key; rollback disponible: $0 --rollback $RUN_ID"
      return 1
    fi
    ok "$key aplicado/verificado=$desired"
    FIXED=$((FIXED+1))
    idx=$((idx+1))
  done

  if [ -f "$legacy" ] && printf "%s\n" "$picked_keys" | grep -q "net.ipv4.tcp_syncookies"; then
    if [ "$(synflood_value "$legacy" "net.ipv4.tcp_syncookies")" = "1" ] &&
       [ "$(grep -Ec '^[[:space:]]*net[.]ipv4[.]tcp_syncookies[[:space:]]*=' "$legacy" || true)" = "1" ]; then
      local t
      t=$(mktemp "$legacy.XXXXXX") || die "No se pudo crear temporal de migración"
      awk '!/^[[:space:]]*net[.]ipv4[.]tcp_syncookies[[:space:]]*=/' "$legacy" > "$t" ||
        { rm -f "$t"; die "No se pudo preparar migración"; }
      chmod --reference="$legacy" "$t" 2>/dev/null || chmod 644 "$t"
      chown --reference="$legacy" "$t" 2>/dev/null || chown root:root "$t"
      mv "$t" "$legacy" || die "No se pudo guardar migración"
      ok "net.ipv4.tcp_syncookies migrado fuera del perfil OrangeBox genérico."
    fi
  fi

  ok "SYN flood aplicado. Backup: $BACKUP_DIR. Rollback: $0 --rollback $RUN_ID"
}
rollback_synflood(){
  local target="$1" bdir state legacy profile_source profile_target backup_legacy backup_profile key value rollback_failures=0
  case "$target" in *[!0-9A-Za-z._/-]*|"") die "RUN_ID rollback inválido";; esac
  case "$target" in /*) bdir="$target"; state="$target/synflood";; *) bdir="/var/backups/orangebox-linux-hardening/$target"; state="$bdir/synflood";; esac
  [ -r "$state/profile-existed" ] && [ -r "$state/legacy-existed" ] && [ -r "$state/runtime.before" ] ||
    die "Estado rollback incompleto"

  legacy=/etc/sysctl.d/99-orangebox-hardening.conf
  # Old executions did not store these paths and used the cPanel-specific filename.
  profile_source="$SYNFLOOD_LEGACY_FILE"
  profile_target="$SYNFLOOD_LEGACY_FILE"
  [ -r "$state/profile-source-path" ] && profile_source=$(cat "$state/profile-source-path")
  [ -r "$state/profile-target-path" ] && profile_target=$(cat "$state/profile-target-path")
  case "$profile_source" in "$SYNFLOOD_FILE"|"$SYNFLOOD_LEGACY_FILE") ;; *) die "Ruta de perfil de origen inválida en estado rollback.";; esac
  case "$profile_target" in "$SYNFLOOD_FILE"|"$SYNFLOOD_LEGACY_FILE") ;; *) die "Ruta de perfil de destino inválida en estado rollback.";; esac

  if [ "$(cat "$state/legacy-existed")" = yes ]; then
    backup_legacy="$bdir/etc/sysctl.d/99-orangebox-hardening.conf"
    [ -f "$backup_legacy" ] || die "Falta backup del perfil genérico"
    cp -a "$backup_legacy" "$legacy" || die "No se pudo restaurar perfil genérico"
  fi

  if [ "$(cat "$state/profile-existed")" = yes ]; then
    backup_profile="$bdir/$(printf "%s" "$profile_source" | sed 's#^/##')"
    [ -f "$backup_profile" ] || die "Falta backup del perfil SYN flood original: $backup_profile"
    cp -a "$backup_profile" "$profile_source" || die "No se pudo restaurar perfil SYN flood original"
    if [ "$profile_target" != "$profile_source" ] && [ -e "$profile_target" ]; then
      synflood_managed_profile "$profile_target" ||
        die "El perfil de destino $profile_target ya no parece gestionado; no se elimina automáticamente."
      rm -f "$profile_target" || die "No se pudo retirar el perfil SYN flood migrado."
    fi
  else
    if [ -e "$profile_target" ]; then
      synflood_managed_profile "$profile_target" ||
        die "El perfil de destino $profile_target ya no parece gestionado; no se elimina automáticamente."
      rm -f "$profile_target" || die "No se pudo retirar el perfil SYN flood creado por la ejecución."
    fi
  fi

  while IFS="|" read -r key value; do
    [ -n "$key" ] || continue
    [ -n "$value" ] || { warn "No hay valor previo capturado para $key; se omite"; rollback_failures=$((rollback_failures+1)); continue; }
    if ! sysctl -w "$key=$value" >/dev/null 2>&1 || [ "$(sysctl -n "$key" 2>/dev/null || true)" != "$value" ]; then
      warn "No se pudo restaurar/verificar runtime $key=$value"
      rollback_failures=$((rollback_failures+1))
    fi
  done < "$state/runtime.before"
  if [ "$rollback_failures" -gt 0 ]; then
    warn "Rollback de archivos completado con $rollback_failures valor(es) runtime sin restaurar/verificar."
    return 1
  fi
  ok "Rollback terminado y valores runtime verificados."
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
  echo "Uso: $0 [--fix | --interactive] [--module MODULO] | --rollback RUN_ID"
  echo "Módulos: ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash"
  echo "Sin --fix o --interactive solo audita. --fix aplica sin preguntas; --interactive pregunta por parámetro."
  echo "SYN flood es opt-in para Linux Enterprise compatible: --module synflood; rollback: $0 --rollback RUN_ID."
  echo "SSH crypto: configuración directa de OpenSSH."
  echo "Crypto-policies globales: NO se modifican."
}
run_module(){
  case "$1" in
    ssh) ssh_module;; sudo) sudo_module;; password) password_module;; kernel) kernel_module;;
    filesystem) filesystem_module;; synflood) synflood_module;; auditd) auditd_module;; rsyslog) rsyslog_module;; selinux) selinux_module;;
    cron) cron_module;; usb) usb_module;; services) services_module;; banners) banners_module;; time) time_module;;
    grub) grub_module;; firewall) firewall_module;; fapolicyd) fapolicyd_module;; listening) listening_module;; bash) bash_module;;
    *) die "Módulo desconocido: $1";;
  esac
}

main(){
  require_root
  while [ $# -gt 0 ]; do
    case "$1" in
      --fix|-f) AUTO_FIX=true;;
      --interactive|-i) INTERACTIVE=true;;
      --module|-m) shift; [ $# -gt 0 ] || die "--module requiere un nombre."; MODULE=$1;;
      --rollback) shift; [ $# -gt 0 ] || die "--rollback requiere RUN_ID."; ROLLBACK_TARGET=$1;;
      --help|-h) usage; exit 0;;
      --list-modules) echo "ssh sudo password kernel synflood filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash"; exit 0;;
      *) die "Argumento desconocido: $1";;
    esac
    shift
  done
  if [ -n "$ROLLBACK_TARGET" ]; then detect_os; rollback_synflood "$ROLLBACK_TARGET"; exit 0; fi
  detect_os; prepare_backup
  if [ "$INTERACTIVE" = true ]; then warn "MODO INTERACTIVO: se confirman los ajustes del módulo seleccionado."
  elif [ "$AUTO_FIX" = true ]; then warn "MODO FIX AUTOMÁTICO: se aplica sin preguntas."
  else ok "MODO AUDITORÍA: sin cambios"; fi
  if [ "$MODULE" = all ]; then for m in ssh sudo password kernel filesystem auditd rsyslog selinux cron usb services banners time grub firewall fapolicyd listening bash; do run_module "$m"; done; else run_module "$MODULE"; fi
  echo -e "\n$GREEN============================================================$NC"
  echo -e "$GREEN OrangeBox Linux Hardening $VERSION - FIN $NC"
  echo "Correcciones: $FIXED"; echo "Advertencias: $WARNINGS"; echo "Errores: $ERRORS"; echo "Backup: $BACKUP_DIR"
  echo -e "$GREEN============================================================$NC"
}
main "$@"
