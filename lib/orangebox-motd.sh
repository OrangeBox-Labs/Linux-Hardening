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
    printf '%s\n' "[OK] FIGlet quedó disponible; el MOTD usará el logotipo FIGlet."
    return 0
  fi

  printf '%s\n' "[WARN] No se pudo instalar FIGlet o falta la fuente small; se usará el logo ASCII integrado."
  return 1
}

orangebox_motd_write_profile() {
  local output="$1"
  [ -n "$output" ] || return 2

  cat > "$output" <<'ORANGEBOX_SESSION_MOTD'
# OrangeBox dynamic login banner. This file is sourced by /etc/profile.
# A static /etc/motd cannot know the client IP for each individual SSH session.
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac
[ -t 1 ] || return 0 2>/dev/null || exit 0

OB_RESET=
OB_BOLD=
OB_ORANGE=
OB_CYAN=
OB_YELLOW=
OB_RED=
OB_MAGENTA=
OB_WHITE=
OB_COLORS=0
if command -v tput >/dev/null 2>&1 && [ -n "$TERM" ] && [ "$TERM" != dumb ]; then
  OB_RESET=$(tput sgr0 2>/dev/null || true)
  OB_BOLD=$(tput bold 2>/dev/null || true)
  OB_COLORS=$(tput colors 2>/dev/null || printf '0')
  case "$OB_COLORS" in ''|*[!0-9]*) OB_COLORS=0 ;; esac
  if [ "$OB_COLORS" -ge 256 ] 2>/dev/null; then
    OB_ORANGE=$(tput setaf 214 2>/dev/null || tput setaf 3 2>/dev/null || true)
    OB_CYAN=$(tput setaf 39 2>/dev/null || tput setaf 6 2>/dev/null || true)
    OB_YELLOW=$(tput setaf 226 2>/dev/null || tput setaf 3 2>/dev/null || true)
    OB_RED=$(tput setaf 196 2>/dev/null || tput setaf 1 2>/dev/null || true)
    OB_MAGENTA=$(tput setaf 205 2>/dev/null || tput setaf 5 2>/dev/null || true)
    OB_WHITE=$(tput setaf 15 2>/dev/null || tput setaf 7 2>/dev/null || true)
  elif [ "$OB_COLORS" -ge 8 ] 2>/dev/null; then
    OB_ORANGE=$(tput setaf 3 2>/dev/null || true)
    OB_CYAN=$(tput setaf 6 2>/dev/null || true)
    OB_YELLOW=$(tput setaf 3 2>/dev/null || true)
    OB_RED=$(tput setaf 1 2>/dev/null || true)
    OB_MAGENTA=$(tput setaf 5 2>/dev/null || true)
    OB_WHITE=$(tput setaf 7 2>/dev/null || true)
  fi
fi

# SSH_CONNECTION = client IP, client port, server IP, server port.
OB_REMOTE_IP=
OB_SERVER_IP=
if [ -n "$SSH_CONNECTION" ]; then
  OB_REMOTE_IP=$(printf '%s\n' "$SSH_CONNECTION" | awk 'NF {print $1; exit}')
  OB_SERVER_IP=$(printf '%s\n' "$SSH_CONNECTION" | awk 'NF {print $3; exit}')
elif [ -n "$SSH_CLIENT" ]; then
  OB_REMOTE_IP=$(printf '%s\n' "$SSH_CLIENT" | awk 'NF {print $1; exit}')
fi

# For local console sessions, detect an IPv4 address on the server.
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
[ -n "$OB_REMOTE_IP" ] || OB_REMOTE_IP="Sesión local / IP no disponible"
[ -n "$OB_SERVER_IP" ] || OB_SERVER_IP="No detectada"

OB_UPTIME=$(awk 'NR == 1 {s=int($1); printf "up %d days, %d hours, %d minutes", int(s/86400), int((s%86400)/3600), int((s%3600)/60)}' /proc/uptime 2>/dev/null)
[ -n "$OB_UPTIME" ] || OB_UPTIME="No disponible"
OB_LOAD=$(awk 'NR == 1 {printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg 2>/dev/null)
[ -n "$OB_LOAD" ] || OB_LOAD="No disponible"
OB_KERNEL=$(uname -r 2>/dev/null)
[ -n "$OB_KERNEL" ] || OB_KERNEL="No disponible"

ob_center() {
  ob_text="$1"
  ob_color="$2"
  ob_pad=$(awk -v text="$ob_text" -v width="$OB_COLUMNS" 'BEGIN {p=int((width-length(text))/2); if (p<0) p=0; print p}')
  printf '%*s%s%s%s\n' "$ob_pad" '' "$ob_color" "$ob_text" "$OB_RESET"
}
OB_COLUMNS=$(tput cols 2>/dev/null || printf '80')
case "$OB_COLUMNS" in ''|*[!0-9]*) OB_COLUMNS=80 ;; esac
[ "$OB_COLUMNS" -gt 0 ] 2>/dev/null || OB_COLUMNS=80

if command -v figlet >/dev/null 2>&1 && figlet -f small OrangeBox >/dev/null 2>&1; then
  printf '%s' "$OB_ORANGE"
  figlet -f small OrangeBox 2>/dev/null
  printf '%s\n' "$OB_RESET"
else
  printf '%s' "$OB_ORANGE"
  cat <<'ORANGEBOX_ASCII'
   ___                        ____            
  / _ \ _ __ __ _ _ __   __ _| __ )  _____  __
 | | | | '__/ _| | '_ \ / _| |  _ \ / _ \ \/ /
 | |_| | | | (_| | | | | (_| | |_) | (_) >  < 
  \___/|_|  \__,_|_| |_|\__, |____/ \___/_/\_\
                         |___/                  
ORANGEBOX_ASCII
  printf '%s\n' "$OB_RESET"
fi

printf '\n'
ob_center "SISTEMA DE ACCESO RESTRINGIDO" "$OB_RED$OB_BOLD"
ob_center "www.orangebox.cl" "$OB_CYAN"
printf '\n'
printf '  %sIP remota:%s    %s\n' "$OB_CYAN" "$OB_RESET" "$OB_REMOTE_IP"
printf '  %sIP servidor:%s  %s\n' "$OB_CYAN" "$OB_RESET" "$OB_SERVER_IP"
printf '  %sUptime:%s       %s\n' "$OB_YELLOW" "$OB_RESET" "$OB_UPTIME"
printf '  %sLoad (1/5/15m):%s %s\n' "$OB_MAGENTA" "$OB_RESET" "$OB_LOAD"
printf '  %sKernel:%s       %s\n' "$OB_MAGENTA" "$OB_RESET" "$OB_KERNEL"
printf '\n'
ob_center "AVISO DE SEGURIDAD" "$OB_RED$OB_BOLD"
printf '\n'
printf '  %sTodas las conexiones y los comandos ejecutados quedan%s\n' "$OB_WHITE" "$OB_RESET"
printf '  %sasociados a la IP de origen y se registran en sistemas%s\n' "$OB_WHITE" "$OB_RESET"
printf '  %sremotos de auditoría.%s\n' "$OB_WHITE" "$OB_RESET"
printf '\n'
printf '  %sTodo acceso, uso o actividad no autorizada será%s\n' "$OB_RED" "$OB_RESET"
printf '  %sdocumentado y reportado a las autoridades competentes.%s\n' "$OB_RED" "$OB_RESET"
printf '\n'
printf '  %sSi no cuenta con autorización, desconéctese%s\n' "$OB_RED$OB_BOLD" "$OB_RESET"
printf '  %sinmediatamente.%s\n' "$OB_RED$OB_BOLD" "$OB_RESET"
printf '\n'
ORANGEBOX_SESSION_MOTD
}
