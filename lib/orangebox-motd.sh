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
  local width="${2:-79}"
  local pad=$(( (width - ${#text}) / 2 ))
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

# Una paleta ANSI común para todos los usuarios; no depende de tput ni de
# si la cuenta que inicia Bash es root o un usuario normal.
OB_RESET=
OB_CYAN=
if [ -t 1 ] && [ "${TERM:-}" != dumb ]; then
  OB_RESET=$(printf '\033[0m')
  OB_CYAN=$(printf '\033[1;36m')
fi

# FIGlet se usa en la sesión interactiva cuando está disponible. Si no,
# se muestra un logo ASCII integrado sin instalar paquetes en el login.
OB_LOGO=
if command -v figlet >/dev/null 2>&1; then
  OB_LOGO=$(figlet -f small OrangeBox 2>/dev/null || true)
fi
if [ -z "$OB_LOGO" ]; then
  OB_LOGO=$(cat <<'ORANGEBOX_ASCII'
   ___                        ____
  / _ \ _ __ __ _ _ __   __ _ | __ )
 | | | | '__/ _| | '_ \ / _| ||  _ \
 | |_| | | | (_| | | | | (_| || |_) |
  \___/|_|  \__,_|_| |_| \__,_||____/
ORANGEBOX_ASCII
)
fi

# Centrar el logo sin depender de herramientas externas.
OB_TERM_WIDTH=${COLUMNS:-80}
case "$OB_TERM_WIDTH" in
  ''|*[!0-9]*) OB_TERM_WIDTH=80 ;;
esac
[ "$OB_TERM_WIDTH" -ge 40 ] 2>/dev/null || OB_TERM_WIDTH=80
printf '%s\n' "$OB_LOGO" | while IFS= read -r OB_LOGO_LINE; do
  OB_PAD=$(( (OB_TERM_WIDTH - ${#OB_LOGO_LINE}) / 2 ))
  [ "$OB_PAD" -ge 0 ] || OB_PAD=0
  printf '%*s%s%s%s\n' "$OB_PAD" '' "$OB_CYAN" "$OB_LOGO_LINE" "$OB_RESET"
done

OB_SERVER_IP=
if [ -n "${SSH_CONNECTION:-}" ]; then
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

OB_CLIENT_IP=
if [ -n "${SSH_CONNECTION:-}" ]; then
  OB_CLIENT_IP=$(printf '%s\n' "$SSH_CONNECTION" | awk 'NF {print $1; exit}')
elif [ -n "${SSH_CLIENT:-}" ]; then
  OB_CLIENT_IP=$(printf '%s\n' "$SSH_CLIENT" | awk 'NF {print $1; exit}')
else
  OB_CLIENT_IP=$(who am i 2>/dev/null | awk 'match($0, /\([^)]*\)/) {print substr($0,RSTART+1,RLENGTH-2); exit}')
fi
[ -n "$OB_CLIENT_IP" ] || OB_CLIENT_IP="Local"

OB_USERNAME=$(id -un 2>/dev/null || printf '%s' "${USER:-unknown}")
OB_UPTIME=$(awk 'NR == 1 {s=int($1); printf "up %d days, %d hours, %d minutes", int(s/86400), int((s%86400)/3600), int((s%3600)/60)}' /proc/uptime 2>/dev/null)
[ -n "$OB_UPTIME" ] || OB_UPTIME="No disponible"
OB_LOAD=$(awk 'NR == 1 {printf "%s, %s, %s", $1, $2, $3}' /proc/loadavg 2>/dev/null)
[ -n "$OB_LOAD" ] || OB_LOAD="No disponible"

# Memoria actual: MemAvailable cuando el kernel la expone; fallback a
# free+buffers+cache para kernels legacy (por ejemplo, CentOS/RHEL 6).
OB_MEMORY_STATS=$(awk '
  $1 == "MemTotal:" { total = $2 }
  $1 == "MemAvailable:" { available = $2; have_available = 1 }
  $1 == "MemFree:" { free_mem = $2 }
  $1 == "Buffers:" { buffers = $2 }
  $1 == "Cached:" { cached = $2 }
  $1 == "SwapTotal:" { swap_total = $2 }
  $1 == "SwapFree:" { swap_free = $2 }
  END {
    if (total > 0) {
      if (!have_available) available = free_mem + buffers + cached
      used = total - available
      if (used < 0) used = 0
      printf "%.1f/%.1f GiB (%.0f%%)", used / 1048576, total / 1048576, used * 100 / total
    } else {
      printf "No disponible"
    }
    printf "|"
    if (swap_total > 0) {
      swap_used = swap_total - swap_free
      if (swap_used < 0) swap_used = 0
      printf "%.1f/%.1f GiB (%.0f%%)", swap_used / 1048576, swap_total / 1048576, swap_used * 100 / swap_total
    } else if (swap_total == 0) {
      printf "No configurada"
    } else {
      printf "No disponible"
    }
  }
' /proc/meminfo 2>/dev/null)
[ -n "$OB_MEMORY_STATS" ] || OB_MEMORY_STATS="No disponible|No disponible"
OB_RAM_USAGE=${OB_MEMORY_STATS%%|*}
OB_SWAP_USAGE=${OB_MEMORY_STATS#*|}
OB_DATETIME=$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)
[ -n "$OB_DATETIME" ] || OB_DATETIME="No disponible"

# Consultar la IP pública solo durante un tiempo acotado; el login no debe
# quedarse esperando si el servidor está aislado o el servicio externo falla.
OB_EXTERNAL_IP=
if command -v curl >/dev/null 2>&1; then
  OB_EXTERNAL_IP=$(curl -4 -fsS --connect-timeout 1 --max-time 2 https://ifconfig.me/ip 2>/dev/null | tr -d '[:space:]')
elif command -v wget >/dev/null 2>&1; then
  OB_EXTERNAL_IP=$(wget -q -T 2 -O - https://ifconfig.me/ip 2>/dev/null | tr -d '[:space:]')
fi
if [ -n "$OB_EXTERNAL_IP" ] && ! printf '%s\n' "$OB_EXTERNAL_IP" | awk -F. '
  NF != 4 { exit 1 }
  {
    for (i = 1; i <= 4; i++) {
      if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1
    }
    exit 0
  }
'; then
  OB_EXTERNAL_IP=
fi
[ -n "$OB_EXTERNAL_IP" ] || OB_EXTERNAL_IP="No disponible"

printf '\n'
printf '  %s%-15s%s %s\n' "$OB_CYAN" "Fecha/hora:" "$OB_RESET" "$OB_DATETIME"
printf '  %s%-15s%s %s\n' "$OB_CYAN" "IP externa:" "$OB_RESET" "$OB_EXTERNAL_IP"
printf '  %s%-15s%s %s\n' "$OB_CYAN" "IP interna:" "$OB_RESET" "$OB_SERVER_IP"
printf '  %s%-15s%s %s\n' "$OB_CYAN" "IP del cliente:" "$OB_RESET" "$OB_CLIENT_IP"
printf '  %s%-15s%s %s\n' "$OB_CYAN" "Uptime:" "$OB_RESET" "$OB_UPTIME"
printf '  %s%-15s%s %s | RAM usada: %s | Swap usada: %s\n' "$OB_CYAN" "Load:" "$OB_RESET" "$OB_LOAD" "$OB_RAM_USAGE" "$OB_SWAP_USAGE"
printf '  %s%-15s%s %s\n' "$OB_CYAN" "Usuario:" "$OB_RESET" "$OB_USERNAME"
printf '\n'
ORANGEBOX_SESSION_MOTD
}
