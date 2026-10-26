#!/usr/bin/env bash
# Shared helpers for the portable, session-aware OrangeBox login banner.

orangebox_motd_figlet_ready() {
  command -v figlet >/dev/null 2>&1 || return 1
  figlet -f small OrangeBox >/dev/null 2>&1
}

orangebox_motd_ensure_figlet() {
  local apply=false
  [ "$#" -gt 0 ] && apply="$1"

  if orangebox_motd_figlet_ready; then
    printf '%s\n' "[OK] FIGlet y la fuente small están disponibles."
    return 0
  fi

  if [ "$apply" != true ]; then
    printf '%s\n' "[INFO] FIGlet no está disponible; se usará el logo ASCII integrado. En --fix se intentará instalar."
    return 1
  fi

  printf '%s\n' "[INFO] FIGlet no está disponible; intentando instalar desde los repositorios ya configurados."
  printf '%s\n' "[INFO] No se habilitarán repositorios adicionales ni se actualizará el sistema completo."

  if command -v dnf >/dev/null 2>&1; then
    dnf -y install figlet
  elif command -v yum >/dev/null 2>&1; then
    yum -y install figlet
  elif command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y figlet
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install figlet
  else
    printf '%s\n' "[WARN] No se detectó un gestor de paquetes compatible para instalar FIGlet."
  fi

  if orangebox_motd_figlet_ready; then
    printf '%s\n' "[OK] FIGlet quedó disponible; el banner previo al login usará el logotipo FIGlet."
    return 0
  fi

  printf '%s\n' "[WARN] No se pudo instalar FIGlet o falta la fuente small; se usará el logo ASCII integrado."
  return 1
}

orangebox_motd_center_login_line() {
  local text="$1"
  local width="\${2:-79}"
  local pad=$(( (width - \${#text}) / 2 ))
  [ "$pad" -ge 0 ] || pad=0
  printf '%*s%s\n' "$pad" '' "$text"
}

orangebox_motd_write_login_banner() {
  local output="$1"
  local force_ascii=false
  local logo logo_line
  [ "$#" -ge 2 ] && force_ascii="$2"
  [ -n "$output" ] || return 2

  if [ "$force_ascii" != true ] && command -v figlet >/dev/null 2>&1 && figlet -f small OrangeBox >/dev/null 2>&1; then
    logo="$(figlet -f small OrangeBox)"
  else
    logo="$(cat <<'ORANGEBOX_ASCII'
   ___                        ____
  / _ \ _ __ __ _ _ __   __ _ | __ )
 | | | | '__/ _| | '_ \ / _| ||  _ \
 | |_| | | | (_| | | | | (_| || |_) |
  \___/|_|  \__,_|_| |_| \__,_||____/
ORANGEBOX_ASCII
)"
  fi

  {
    printf '%s\n' '*******************************************************************************'
    while IFS= read -r logo_line; do
      orangebox_motd_center_login_line "$logo_line" 79
    done <<< "$logo"
    printf '\n'
    orangebox_motd_center_login_line 'SISTEMA DE ACCESO RESTRINGIDO' 79
    orangebox_motd_center_login_line 'www.orangebox.cl' 79
    printf '%s\n' '*******************************************************************************'
    printf '\n'
    printf '    %s\n' 'Todas las conexiones y los comandos ejecutados quedan'
    printf '    %s\n' 'asociados a la IP de origen y se registran en sistemas'
    printf '    %s\n' 'remotos de auditoría.'
    printf '\n'
    printf '    %s\n' 'Todo acceso, uso o actividad no autorizada será'
    printf '    %s\n' 'documentado y reportado a las autoridades competentes.'
    printf '\n'
    printf '    %s\n' 'Si no cuenta con autorización, desconéctese'
    printf '    %s\n' 'inmediatamente.'
    printf '\n'
    printf '%s\n' '*******************************************************************************'
  } > "$output"
}

orangebox_motd_write_profile() {
  local output="$1"
  [ -n "$output" ] || return 2

  cat > "$output" <<'ORANGEBOX_SESSION_MOTD'
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac
[ -t 1 ] || return 0 2>/dev/null || exit 0

OB_RESET=
OB_CYAN=
OB_YELLOW=
OB_MAGENTA=
OB_COLORS=0
if command -v tput >/dev/null 2>&1 && [ -n "$TERM" ] && [ "$TERM" != dumb ]; then
  OB_RESET=$(tput sgr0 2>/dev/null || true)
  OB_COLORS=$(tput colors 2>/dev/null || printf '0')
  case "$OB_COLORS" in ''|*[!0-9]*) OB_COLORS=0 ;; esac
  if [ "$OB_COLORS" -ge 256 ] 2>/dev/null; then
    OB_CYAN=$(tput setaf 39 2>/dev/null || tput setaf 6 2>/dev/null || true)
    OB_YELLOW=$(tput setaf 226 2>/dev/null || tput setaf 3 2>/dev/null || true)
    OB_MAGENTA=$(tput setaf 205 2>/dev/null || tput setaf 5 2>/dev/null || true)
  elif [ "$OB_COLORS" -ge 8 ] 2>/dev/null; then
    OB_CYAN=$(tput setaf 6 2>/dev/null || true)
    OB_YELLOW=$(tput setaf 3 2>/dev/null || true)
    OB_MAGENTA=$(tput setaf 5 2>/dev/null || true)
  fi
fi

OB_SERVER_IP=
if [ -n "$SSH_CONNECTION" ]; then
  OB_SERVER_IP=$(printf '%s\n' "$SSH_CONNECTION" | awk 'NF {print $3; exit}')
fi
if [ -z "$OB_SERVER_IP" ] && command -v ip >/dev/null 2>&1; then
  OB_SERVER_IP=$(ip -o -4 addr show scope global 2>/dev/null |
    awk '$3 == "inet" && $4 !~ /^127\./ {split($4,a,"/"); print a[1]; exit}')
fi
if [ -z "$OB_SERVER_IP" ] && command -v ifconfig >/dev/null 2>&1; then
  OB_SERVER_IP=$(ifconfig -a 2>/dev/null | awk '
    /inet addr:/ {ip=$2; sub(/^addr:/,"",ip); if (ip !~ /^127\./) {print ip; exit}}
    $1 == "inet" {ip=$2; if (ip !~ /^127\./) {print ip; exit}}
  ')
fi
[ -n "$OB_SERVER_IP" ] || OB_SERVER_IP="No detectada"

OB_UPTIME=$(awk 'NR == 1 {s=int($1); printf "up %d days, %d hours, %d minutes", int(s/86400), int((s%86400)/3600), int((s%3600)/60)}' /proc/uptime 2>/dev/null)
[ -n "$OB_UPTIME" ] || OB_UPTIME="No disponible"
OB_LOAD=$(awk 'NR == 1 {printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg 2>/dev/null)
[ -n "$OB_LOAD" ] || OB_LOAD="No disponible"
OB_DATETIME=$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)
[ -n "$OB_DATETIME" ] || OB_DATETIME="No disponible"

printf '  %sIP interna:%s    %s\n' "$OB_CYAN" "$OB_RESET" "$OB_SERVER_IP"
printf '  %sUptime:%s        %s\n' "$OB_YELLOW" "$OB_RESET" "$OB_UPTIME"
printf '  %sLoad (1/5/15m):%s %s\n' "$OB_MAGENTA" "$OB_RESET" "$OB_LOAD"
printf '  %sFecha/hora:%s    %s\n' "$OB_CYAN" "$OB_RESET" "$OB_DATETIME"
printf '\n'
ORANGEBOX_SESSION_MOTD
}
