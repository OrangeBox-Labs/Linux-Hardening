#!/bin/bash

OB_COMPAT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$OB_COMPAT_DIR/lib/service-compat.sh" ]; then
  # shellcheck source=lib/service-compat.sh
  . "$OB_COMPAT_DIR/lib/service-compat.sh"
else
  echo "[ERROR] Falta lib/service-compat.sh; actualice el repositorio completo." >&2
  exit 1
fi

if [ -r "$OB_COMPAT_DIR/lib/orangebox-motd.sh" ]; then
  # shellcheck source=lib/orangebox-motd.sh
  . "$OB_COMPAT_DIR/lib/orangebox-motd.sh"
else
  echo "[ERROR] Falta lib/orangebox-motd.sh; actualice el repositorio completo." >&2
  exit 1
fi

# ==============================================
# Script: bash-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de Bash shell y entorno de usuario
#              Configura historial con fecha/hora, prompt mejorado,
#              timeout, umask segura, alias útiles, auditoría en syslog
#              y protecciones adicionales
#              Compatible con RHEL/CentOS/Rocky/AlmaLinux/Oracle 7,8,9,10
#              NO requiere paquetes adicionales (usa solo herramientas base)
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/bash-backup-$(date +%Y%m%d-%H%M%S)-${BASHPID}"

# Archivos de configuración
BASHRC_SYSTEM="/etc/bashrc"
PROFILE_D="/etc/profile.d/orangebox.sh"
PROFILE_MOTD="/etc/profile.d/99-orangebox-motd.sh"
ALIASES_D="/etc/profile.d/aliases.sh"
HISTORY_SYSLOG="/etc/profile.d/syslog_history.sh"
HISTORY_SECURE="/etc/profile.d/history_secure.sh"
BASHRC_ROOT="/root/.bashrc"
SKEL_BASHRC="/etc/skel/.bashrc"
RSYSLOG_CONF="/etc/rsyslog.d/30-bash.conf"

# ==============================================
# FUNCION PARA MOSTRAR USO
# ==============================================
show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 --fix      - Modo automático (aplica las correcciones)"
  echo "  $0 -f         - Modo automático (versión corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./bash-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./bash-hardening.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  [ "$AUTO_FIX" = true ] || return 0
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[ERROR] No se pudo preparar el directorio de backup $BACKUP_DIR; no se modifica Bash.${NC}" >&2
    return 1
  fi
  local mode file backup parent source_hash backup_hash
  mode="$(stat -c '%a' "$BACKUP_DIR" 2>/dev/null || true)"
  if [ "$mode" != 700 ]; then
    echo -e "${RED}[ERROR] No se pudo verificar el modo 0700 del backup Bash $BACKUP_DIR.${NC}" >&2
    return 1
  fi
  for file in "$BASHRC_SYSTEM" "$PROFILE_D" "$PROFILE_MOTD" "$ALIASES_D" "$HISTORY_SYSLOG" "$HISTORY_SECURE" "$BASHRC_ROOT" "$SKEL_BASHRC" "$RSYSLOG_CONF"; do
    [ -e "$file" ] || [ -L "$file" ] || continue
    if [ -L "$file" ]; then
      echo -e "${RED}[ERROR] $file es un enlace simbólico; no se modifica Bash sin un backup seguro del destino.${NC}" >&2
      return 1
    fi
    backup="$BACKUP_DIR$file"
    parent="$(dirname "$backup")"
    if ! mkdir -p "$parent" || [ -L "$parent" ] || [ ! -d "$parent" ]; then
      echo -e "${RED}[ERROR] No se pudo preparar el destino de backup de $file; no se modifica Bash.${NC}" >&2
      return 1
    fi
    if ! cp -a "$file" "$backup"; then
      echo -e "${RED}[ERROR] No se pudo respaldar $file en $backup; no se modifica Bash.${NC}" >&2
      return 1
    fi
    if [ -f "$file" ]; then
      command -v sha256sum >/dev/null 2>&1 || { echo -e "${RED}[ERROR] sha256sum no está disponible para verificar $file; no se modifica Bash.${NC}" >&2; return 1; }
      source_hash="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
      backup_hash="$(sha256sum "$backup" 2>/dev/null | awk '{print $1}')"
      if [ -z "$source_hash" ] || [ -z "$backup_hash" ] || [ "$source_hash" != "$backup_hash" ]; then
        echo -e "${RED}[ERROR] El backup de $file no coincide con el original; no se modifica Bash.${NC}" >&2
        return 1
      fi
    elif [ -d "$file" ] && [ ! -d "$backup" ]; then
      echo -e "${RED}[ERROR] No se verificó el directorio de backup de $file; no se modifica Bash.${NC}" >&2
      return 1
    fi
  done
  echo -e "${GREEN}[✓] Backup de Bash verificado en: $BACKUP_DIR${NC}"
}

# ==============================================
# CONFIGURAR PROFILE.D DE BASH Y PROMPT
# ==============================================
configure_profile() {
  echo -e "\n${BLUE}[*] Configurando banner de login y prompt de bash...${NC}"

  if [ -f "$PROFILE_D" ] && grep -q "OrangeBox" "$PROFILE_D" 2>/dev/null && grep -Eq "^[[:space:]]*export HISTSIZE=-1$" "$PROFILE_D" && grep -Eq "^[[:space:]]*export HISTFILESIZE=-1$" "$PROFILE_D" && ! grep -Eq "readonly[[:space:]]+HISTFILE" "$PROFILE_D" && grep -Fq 'beginning-of-line' "$PROFILE_D" && grep -Fq 'end-of-line' "$PROFILE_D" && grep -Fq 'hostname -f' "$PROFILE_D" && grep -Fq 'orangebox_set_prompt' "$PROFILE_D" && grep -Fq 'history() {' "$PROFILE_D" && grep -Fq 'history -c/-d/-w' "$PROFILE_D" && grep -Fq 'ORANGEBOX_SESSION_DISPLAY=external-motd' "$PROFILE_D"; then
    echo -e "${GREEN}[✓] Profile ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] Profile NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    mkdir -p /etc/profile.d
    cat >"$PROFILE_D" <<'EOF'
# ==============================================
# Hardening Bash - OrangeBox Labs
# https://www.orangebox.cl
# ==============================================

# ORANGEBOX_SESSION_DISPLAY=external-motd
# Logo, estado y datos de conexión se muestran una sola vez en
# /etc/profile.d/99-orangebox-motd.sh. Este perfil configura Bash.

# Resolver hostname FQDN una vez por shell para mostrarlo en el prompt.
ORANGEBOX_PROMPT_HOST="$(hostname -f 2>/dev/null || true)"
case "$ORANGEBOX_PROMPT_HOST" in
    ""|localhost|localhost.localdomain) ORANGEBOX_PROMPT_HOST="$(hostname 2>/dev/null || true)" ;;
esac
[ -n "$ORANGEBOX_PROMPT_HOST" ] || ORANGEBOX_PROMPT_HOST=unknown

orangebox_set_prompt() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        PS1='\[\e[2m\]\A\[\e[0m\] \[\e[1;31m\]\u@'"$ORANGEBOX_PROMPT_HOST"'\[\e[0m\] \[\e[1;34m\]\W\[\e[0m\] # '
    else
        PS1='\[\e[2m\]\A\[\e[0m\] \[\e[1;32m\]\u@'"$ORANGEBOX_PROMPT_HOST"'\[\e[0m\] \[\e[1;34m\]\W\[\e[0m\] $ '
    fi
}
orangebox_set_prompt

# Historial con fecha y hora y sin límite de líneas.
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTCONTROL=
if [ -z "${HISTFILE:-}" ] || [ "${HISTFILE}" = /dev/null ] || [ "${HISTFILE}" = /dev/zero ]; then
    export HISTFILE="$HOME/.bash_history"
fi
unset HISTIGNORE
set -o history
shopt -s histappend

# Protección de mejor esfuerzo contra borrado o sobrescritura del historial.
# No es una frontera de seguridad: builtin history y la edición directa del
# archivo pueden eludir esta función.
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
    set -o history
    HISTSIZE=-1
    HISTFILESIZE=-1
    case "${HISTFILE:-}" in
        ""|/dev/null|/dev/zero|/var/log/bash_history/*) HISTFILE="$HOME/.bash_history" ;;
    esac
    export HISTSIZE HISTFILESIZE HISTFILE
    history -a
    set -o emacs 2>/dev/null || true
    bind '"\C-a": beginning-of-line' 2>/dev/null || true
    bind '"\C-e": end-of-line' 2>/dev/null || true
    orangebox_set_prompt
}
case ";${PROMPT_COMMAND:-};" in
    *";orangebox_history_guard;"*|*"; orangebox_history_guard;"*) ;;
    *)
        if [ -n "${PROMPT_COMMAND:-}" ]; then
            PROMPT_COMMAND="${PROMPT_COMMAND}; orangebox_history_guard"
        else
            PROMPT_COMMAND="orangebox_history_guard"
        fi
        ;;
esac
export PROMPT_COMMAND

# Readline interactivo: comportamiento Bash estándar para edición de comandos.
case $- in
  *i*)
    set -o emacs 2>/dev/null || true
    bind '"\C-a": beginning-of-line' 2>/dev/null || true
    bind '"\C-e": end-of-line' 2>/dev/null || true
    ;;
esac

# Timeout de sesión inactiva (15 minutos) - solo si no está definido
if [ -z "$TMOUT" ]; then
    export TMOUT=900
    readonly TMOUT
fi

# Umask segura
umask 027

# Historial habilitado e ilimitado; los valores se revalidan por sesión.
EOF
    echo -e "${GREEN}[✓] Profile creado en $PROFILE_D${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR BIENVENIDA ÚNICA DE SESIÓN
# ==============================================
configure_session_motd() {
  echo -e "\n${BLUE}[*] Configurando logo y datos de sesión...${NC}"

  if [ -f "$PROFILE_MOTD" ] &&
     grep -Fq 'figlet -f small OrangeBox' "$PROFILE_MOTD" &&
     grep -Fq '"Load:"' "$PROFILE_MOTD" &&
     ! grep -Fq 'Load (1/5/15m):' "$PROFILE_MOTD" &&
     grep -Fq 'IP del cliente:' "$PROFILE_MOTD" &&
     grep -Fq 'Fecha/hora:' "$PROFILE_MOTD" &&
     [ "$(grep -Fc 'Fecha/hora:' "$PROFILE_MOTD")" -eq 1 ] &&
     grep -Fq 'OB_CYAN=$(printf' "$PROFILE_MOTD" &&
     ! grep -Fq 'tput' "$PROFILE_MOTD"; then
    echo -e "${GREEN}[✓] Bienvenida de shell ya configurada${NC}"
    return 0
  fi

  echo -e "${RED}[!] Bienvenida de shell ausente o desactualizada${NC}"

  if [ "$AUTO_FIX" = true ]; then
    local motd_tmp
    motd_tmp=$(mktemp "${PROFILE_MOTD}.XXXXXX") || {
      echo -e "${RED}[ERROR] No se pudo crear temporal para $PROFILE_MOTD${NC}" >&2
      WARNINGS=$((WARNINGS + 1))
      return 1
    }

    if ! orangebox_motd_write_profile "$motd_tmp" || ! sh -n "$motd_tmp"; then
      rm -f "$motd_tmp"
      echo -e "${RED}[ERROR] No se pudo generar/validar la bienvenida dinámica${NC}" >&2
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi

    if ! chmod 644 "$motd_tmp" || ! chown root:root "$motd_tmp" || ! mv -f "$motd_tmp" "$PROFILE_MOTD"; then
      rm -f "$motd_tmp"
      echo -e "${RED}[ERROR] No se pudo instalar $PROFILE_MOTD${NC}" >&2
      WARNINGS=$((WARNINGS + 1))
      return 1
    fi

    echo -e "${GREEN}[✓] Bienvenida de shell instalada en $PROFILE_MOTD${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR ALIAS AVANZADOS
# ==============================================
configure_aliases() {
  echo -e "\n${BLUE}[*] Configurando alias avanzados...${NC}"

  if [ -f "$ALIASES_D" ] && grep -q "OrangeBox" "$ALIASES_D" 2>/dev/null; then
    echo -e "${GREEN}[✓] Aliases ya configurados${NC}"
    return 0
  fi

  echo -e "${RED}[!] Aliases NO configurados${NC}"

  if [ "$AUTO_FIX" = true ]; then
    cat >"$ALIASES_D" <<'EOF'
# ==============================================
# Alias avanzados - OrangeBox Labs
# ==============================================

# Navegación
shopt -s autocd
shopt -s cdspell
export CDPATH=".:~:/etc:/var:/usr/local"

# ls mejorado
alias ls='ls --color=auto -F'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# grep mejorado
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Comandos legibles
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ping='ping -c 5'

# Confirmaciones
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias mkdir='mkdir -p'

# Historial con fecha
alias h='history | tail -20'
alias hg='history | grep'

# Sistema
alias ps='ps auxf'
alias ports='ss -tulanp'
alias myip='curl -s ifconfig.me && echo "" 2>/dev/null || echo "Instalar curl para ver IP publica"'

# Navegación rápida (sin alias para / que es inválido)
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

# Editores
alias v='vim'
alias sv='sudo vim'

# Logs
alias syslog='tail -f /var/log/messages'
alias secure='tail -f /var/log/secure'
alias audit='tail -f /var/log/audit/audit.log'

# Comandos peligrosos con confirmación
alias reboot='echo "Use shutdown -r now to reboot"'
alias poweroff='echo "Use shutdown -h now to poweroff"'
alias halt='echo "Use shutdown -h now to halt"'
EOF
    echo -e "${GREEN}[✓] Aliases configurados en $ALIASES_D${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi

  show_reboot_warning
}

# ==============================================
# CONFIGURAR ENVIO DE COMANDOS A SYSLOG
# ==============================================
configure_syslog_history() {
  echo -e "\n${BLUE}[*] Configurando envio de comandos a syslog...${NC}"

  if [ -f "$HISTORY_SYSLOG" ] && grep -q "OrangeBox" "$HISTORY_SYSLOG" 2>/dev/null; then
    echo -e "${GREEN}[✓] Envio a syslog ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] Envio a syslog NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    # Crear el script de logging
    cat >"$HISTORY_SYSLOG" <<'EOF'
# ==============================================
# Envio de comandos ejecutados a syslog - OrangeBox Labs
# ==============================================

log_command() {
    logger -p local1.notice -t "bash[$$]" "USER=$USER PWD=$PWD CMD=$BASH_COMMAND"
}
trap log_command DEBUG
EOF
    echo -e "${GREEN}[✓] Envio de comandos a syslog configurado${NC}"
    FIXED=$((FIXED + 1))

    # Configurar rsyslog si existe
    if command -v rsyslogd >/dev/null 2>&1; then
      # Crear directorio si no existe
      mkdir -p /etc/rsyslog.d/

      cat >"$RSYSLOG_CONF" <<'EOF'
# Logs de comandos bash - OrangeBox Labs
local1.notice    /var/log/bash_commands.log
EOF
      # Intentar reiniciar rsyslog
      if ob_service_restart rsyslog 2>/dev/null; then
        echo -e "${GREEN}[✓] Rsyslog configurado para recibir comandos${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${YELLOW}[!] Rsyslog no esta corriendo, los comandos se envian a journald${NC}"
      fi
    else
      echo -e "${YELLOW}[!] Rsyslog no instalado, usando journald (systemd) por defecto${NC}"
    fi
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR HISTORIAL SEGURO (POR USUARIO)
# ==============================================
configure_secure_history() {
  echo -e "\n${BLUE}[*] Configurando historial seguro por usuario...${NC}"

  if [ -f "$HISTORY_SECURE" ] && grep -q "OrangeBox" "$HISTORY_SECURE" 2>/dev/null && grep -Fq 'HISTFILE="$HOME/.bash_history"' "$HISTORY_SECURE"; then
    echo -e "${GREEN}[✓] Historial seguro ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] Historial seguro NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    cat >"$HISTORY_SECURE" <<'EOF'
# ==============================================
# Historial seguro por usuario - OrangeBox Labs
# ==============================================

# Guardar el historial en el home propio de cada usuario.
# /var/log/bash_history root:root 0750 impide que los usuarios creen
# allí sus propios historiales y provocaba pérdida de historial.
case $- in
    *i*) ;;
    *) return 0 ;;
esac

if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
    HISTFILE="$HOME/.bash_history"
    export HISTFILE
    if [ ! -e "$HISTFILE" ]; then (umask 077; : > "$HISTFILE") 2>/dev/null || true; fi
    if [ -f "$HISTFILE" ] && [ -O "$HISTFILE" ]; then chmod 600 "$HISTFILE" 2>/dev/null || true; fi
fi
EOF
    echo -e "${GREEN}[✓] Historial seguro configurado${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR BASHRC DE ROOT
# ==============================================
configure_root_bashrc() {
  echo -e "\n${BLUE}[*] Configurando /root/.bashrc...${NC}"

  if grep -Fq '# ORANGEBOX BASH ROOT CONFIG V4 BEGIN' "$BASHRC_ROOT" 2>/dev/null; then
    echo -e "${GREEN}[✓] /root/.bashrc ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] /root/.bashrc NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    # Remove only the legacy OrangeBox history reload that cleared/re-read the
    # whole history at every prompt, preserving unrelated user configuration.
    if [ -f "$BASHRC_ROOT" ]; then
      tmp=$(mktemp) || { echo -e "${YELLOW}[!] No se pudo normalizar /root/.bashrc${NC}"; return; }
      awk '
        /^# ORANGEBOX BASH ROOT CONFIG V[23] BEGIN$/ { skip_v2=1; next }
        skip_v2 && /^# ORANGEBOX BASH ROOT CONFIG V[23] END$/ { skip_v2=0; next }
        skip_v2 { next }
        /^export PROMPT_COMMAND="history -a; history -c; history -r;/ { next }
        /^PROMPT_COMMAND="orangebox_history_guard; / { next }
        /^orangebox_history_guard\(\) \{$/ { skip=1; next }
        skip && /^\}$/ { skip=0; next }
        skip { next }
        { print }
      ' "$BASHRC_ROOT" > "$tmp" || { rm -f "$tmp"; echo -e "${YELLOW}[!] No se pudo leer /root/.bashrc${NC}"; return; }
      chmod --reference="$BASHRC_ROOT" "$tmp" 2>/dev/null || chmod 600 "$tmp"
      chown --reference="$BASHRC_ROOT" "$tmp" 2>/dev/null || chown root:root "$tmp"
      mv "$tmp" "$BASHRC_ROOT" || { rm -f "$tmp"; echo -e "${YELLOW}[!] No se pudo actualizar /root/.bashrc${NC}"; return; }
    fi
    cat >>"$BASHRC_ROOT" <<'EOF'

# ==============================================
# Hardening Bash - OrangeBox Labs
# ==============================================
# ORANGEBOX BASH ROOT CONFIG V4 BEGIN

# Protección de mejor esfuerzo contra borrado/sobrescritura de historial.
# No impide el uso explícito de "builtin history" ni la edición directa del archivo.
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

# Historial mejorado
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTCONTROL=
export HISTFILE="$HOME/.bash_history"
unset HISTIGNORE
set -o history
shopt -s histappend
if [ ! -e "$HISTFILE" ]; then (umask 077; : > "$HISTFILE") 2>/dev/null || true; fi
if [ -f "$HISTFILE" ] && [ -O "$HISTFILE" ]; then chmod 600 "$HISTFILE" 2>/dev/null || true; fi
set -o emacs 2>/dev/null || true
bind '"\C-a": beginning-of-line' 2>/dev/null || true
bind '"\C-e": end-of-line' 2>/dev/null || true


# Historial habilitado e ilimitado.

# Prompt personalizado para root (en rojo)
ORANGEBOX_PROMPT_HOST="${ORANGEBOX_PROMPT_HOST:-$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf unknown)}"
export PS1="\[\e[2m\]\A\[\e[0m\] \[\e[1;31m\]\u@${ORANGEBOX_PROMPT_HOST}\[\e[0m\] \[\e[1;34m\]\W\[\e[0m\] # "

# Timeout más estricto para root (10 minutos) - solo si no está definido
if [ -z "$TMOUT" ]; then
    export TMOUT=600
    readonly TMOUT
fi

# Umask segura
umask 027

# Alias con confirmación
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias vi='vim'
alias reboot='echo "Use shutdown -r now to reboot"'
alias poweroff='echo "Use shutdown -h now to poweroff"'
# ORANGEBOX BASH ROOT CONFIG V4 END
EOF
    echo -e "${GREEN}[✓] /root/.bashrc actualizado${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# MOSTRAR ADVERTENCIA DE COMANDOS BLOQUEADOS
# ==============================================
show_reboot_warning() {
  if [ "$AUTO_FIX" = true ]; then
    echo -e "\n${YELLOW}⚠️  NOTA IMPORTANTE - COMANDOS MODIFICADOS ⚠️${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Los siguientes comandos han sido bloqueados por seguridad:${NC}"
    echo -e "  • ${RED}reboot${NC}     → Muestra: ${GREEN}Use shutdown -r now to reboot${NC}"
    echo -e "  • ${RED}poweroff${NC}   → Muestra: ${GREEN}Use shutdown -h now to poweroff${NC}"
    echo -e "  • ${RED}halt${NC}       → Muestra: ${GREEN}Use shutdown -h now to halt${NC}"
    echo -e ""
    echo -e "${YELLOW}Para reiniciar o apagar el sistema, use:${NC}"
    echo -e "  ${GREEN}shutdown -r now${NC}  # Reiniciar inmediatamente"
    echo -e "  ${GREEN}shutdown -h now${NC}  # Apagar inmediatamente"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  fi
}

# ==============================================
# CONFIGURAR /etc/skel PARA NUEVOS USUARIOS
# ==============================================
configure_skel() {
  echo -e "\n${BLUE}[*] Configurando /etc/skel para nuevos usuarios...${NC}"

  if [ -f "$SKEL_BASHRC" ] && grep -Fq '# ORANGEBOX BASH DEFAULTS V4 BEGIN' "$SKEL_BASHRC"; then
    echo -e "${GREEN}[✓] /etc/skel/.bashrc ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] /etc/skel/.bashrc NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    # Remove only the previous OrangeBox-managed block before installing V3.
    if [ -f "$SKEL_BASHRC" ]; then
      tmp=$(mktemp) || { echo -e "${YELLOW}[!] No se pudo normalizar /etc/skel/.bashrc${NC}"; return; }
      awk '
        /^# ORANGEBOX BASH DEFAULTS V[23] BEGIN$/ { skip_v2=1; next }
        skip_v2 && /^# ORANGEBOX BASH DEFAULTS V[23] END$/ { skip_v2=0; next }
        skip_v2 { next }
        { print }
      ' "$SKEL_BASHRC" > "$tmp" || { rm -f "$tmp"; echo -e "${YELLOW}[!] No se pudo leer /etc/skel/.bashrc${NC}"; return; }
      chmod --reference="$SKEL_BASHRC" "$tmp" 2>/dev/null || chmod 644 "$tmp"
      chown --reference="$SKEL_BASHRC" "$tmp" 2>/dev/null || chown root:root "$tmp"
      mv "$tmp" "$SKEL_BASHRC" || { rm -f "$tmp"; echo -e "${YELLOW}[!] No se pudo actualizar /etc/skel/.bashrc${NC}"; return; }
    fi
    cat >>"$SKEL_BASHRC" <<'EOF'

# ==============================================
# Hardening Bash - OrangeBox Labs
# ==============================================
# ORANGEBOX BASH DEFAULTS V4 BEGIN

# Protección de mejor esfuerzo contra borrado/sobrescritura de historial.
# No impide el uso explícito de "builtin history" ni la edición directa del archivo.
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

export HISTTIMEFORMAT="%F %T "
export HISTSIZE=-1
export HISTFILESIZE=-1
export HISTCONTROL=
export HISTFILE="$HOME/.bash_history"
unset HISTIGNORE
set -o history
shopt -s histappend
if [ ! -e "$HISTFILE" ]; then (umask 077; : > "$HISTFILE") 2>/dev/null || true; fi
if [ -f "$HISTFILE" ] && [ -O "$HISTFILE" ]; then chmod 600 "$HISTFILE" 2>/dev/null || true; fi
case $- in
  *i*)
    set -o emacs 2>/dev/null || true
    bind '"\C-a": beginning-of-line' 2>/dev/null || true
    bind '"\C-e": end-of-line' 2>/dev/null || true
    ;;
esac

if [ -z "$TMOUT" ]; then
    export TMOUT=900
    readonly TMOUT
fi

umask 027
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
# ORANGEBOX BASH DEFAULTS V4 END
EOF
    echo -e "${GREEN}[✓] /etc/skel/.bashrc actualizado${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# DESHABILITAR CTRL+ALT+DEL
# ==============================================
disable_ctrl_alt_del() {
  echo -e "\n${BLUE}[*] Deshabilitando Ctrl+Alt+Del...${NC}"

  if ! command -v systemctl >/dev/null 2>&1; then
    if [ -r /etc/inittab ] && grep -Eq '^[[:space:]]*[^#[:space:]].*ctrlaltdel' /etc/inittab; then
      echo -e "${YELLOW}[!] Hay una acción ctrlaltdel activa en /etc/inittab; requiere revisión manual en SysV init.${NC}"
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "${GREEN}[✓] No hay acción ctrlaltdel activa en /etc/inittab${NC}"
    fi
    return 0
  fi

  CTRL_ALT_DEL_SYMLINK="/etc/systemd/system/ctrl-alt-del.target"
  CTRL_ALT_DEL_TARGET="/usr/lib/systemd/system/ctrl-alt-del.target"
  if [ -L "$CTRL_ALT_DEL_SYMLINK" ] && readlink "$CTRL_ALT_DEL_SYMLINK" 2>/dev/null | grep -q "dev/null"; then
    echo -e "${GREEN}[✓] Ctrl+Alt+Del ya esta deshabilitado${NC}"
    return 0
  fi

  if [ -f "$CTRL_ALT_DEL_TARGET" ] || [ -L "$CTRL_ALT_DEL_SYMLINK" ]; then
    echo -e "${RED}[!] Ctrl+Alt+Del NO esta deshabilitado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if ln -sf /dev/null "$CTRL_ALT_DEL_SYMLINK" 2>/dev/null; then
        :
      else
        systemctl mask --force ctrl-alt-del.target 2>/dev/null
      fi
      systemctl daemon-reload 2>/dev/null
      echo -e "${GREEN}[✓] Ctrl+Alt+Del deshabilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] Ctrl+Alt+Del no configurado en este sistema${NC}"
  fi
}
# ==============================================
# VERIFICAR ESTADO ACTUAL
# ==============================================
check_status() {
  echo -e "\n${YELLOW}Estado actual de configuraciones:${NC}\n"

  echo -e "${BLUE}Profile.d:${NC}"
  [ -f "$PROFILE_D" ] && echo -e "  ${GREEN}✓${NC} $PROFILE_D existe" || echo -e "  ${RED}✗${NC} $PROFILE_D no existe"

  echo -e "\n${BLUE}MOTD de shell:${NC}"
  if [ -f "$PROFILE_MOTD" ] && grep -Fq '"Load:"' "$PROFILE_MOTD" && ! grep -Fq 'Load (1/5/15m):' "$PROFILE_MOTD" && grep -Fq 'figlet -f small OrangeBox' "$PROFILE_MOTD"; then
    echo -e "  ${GREEN}✓${NC} Logo y ficha de sesión unificados"
  else
    echo -e "  ${RED}✗${NC} MOTD ausente o desactualizado"
  fi

  echo -e "\n${BLUE}Aliases:${NC}"
  [ -f "$ALIASES_D" ] && echo -e "  ${GREEN}✓${NC} $ALIASES_D existe" || echo -e "  ${RED}✗${NC} $ALIASES_D no existe"

  echo -e "\n${BLUE}Historial con fecha:${NC}"
  [ -n "$HISTTIMEFORMAT" ] && echo -e "  ${GREEN}✓${NC} HISTTIMEFORMAT configurado" || echo -e "  ${RED}✗${NC} HISTTIMEFORMAT no configurado"

  echo -e "\n${BLUE}Timeout de sesion:${NC}"
  [ -n "$TMOUT" ] && echo -e "  ${GREEN}✓${NC} TMOUT configurado" || echo -e "  ${RED}✗${NC} TMOUT no configurado"

  echo -e "\n${BLUE}Umask:${NC}"
  echo -e "  $(umask)"

  echo -e "\n${BLUE}Ctrl+Alt+Del:${NC}"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled ctrl-alt-del.target 2>/dev/null | grep -q "masked"; then
      echo -e "  ${GREEN}✓${NC} Deshabilitado"
    else
      echo -e "  ${RED}✗${NC} Habilitado / revisar estado de systemd"
    fi
  elif [ -r /etc/inittab ] && grep -Eq '^[[:space:]]*[^#[:space:]].*ctrlaltdel' /etc/inittab; then
    echo -e "  ${YELLOW}! ${NC} Acción ctrlaltdel definida en /etc/inittab"
  else
    echo -e "  ${GREEN}N/A${NC} Sin acción ctrlaltdel activa en SysV"
  fi

  echo -e "\n${BLUE}Syslog history:${NC}"
  [ -f "$HISTORY_SYSLOG" ] && echo -e "  ${GREEN}✓${NC} Configurado" || echo -e "  ${RED}✗${NC} No configurado"

  echo -e "\n${BLUE}Historial seguro por usuario:${NC}"
  [ -f "$HISTORY_SECURE" ] && echo -e "  ${GREEN}✓${NC} Configurado" || echo -e "  ${RED}✗${NC} No configurado"
}

# ==============================================
# MOSTRAR RESUMEN FINAL
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  BASH HARDENING${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA APLICAR CAMBIOS EN SESION ACTUAL:${NC}"
  echo -e "  source /etc/profile.d/orangebox.sh"
  echo -e "  source /etc/profile.d/aliases.sh"
  echo -e "  source ~/.bashrc"

  echo -e "\n${YELLOW}PARA VERIFICAR HISTORIAL CON FECHA:${NC}"
  echo -e "  history | tail -20"

  echo -e "\n${YELLOW}PARA VER LOG DE COMANDOS:${NC}"
  echo -e "  tail -f /var/log/bash_commands.log"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Bash Hardening - Seguridad del Shell${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Modo ayuda
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  # Modo verificación
  if [ "$1" != "--fix" ] && [ "$1" != "-f" ]; then
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"
    check_status
    AUTO_FIX=false
  fi

  # Modo automático
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
    if ! make_backup; then
      echo -e "${RED}[ERROR] Backup de Bash falló; se aborta antes de modificar perfiles.${NC}" >&2
      exit 1
    fi
  fi

  # Ejecutar configuraciones
  configure_profile
  configure_session_motd
  configure_aliases
  configure_syslog_history
  configure_secure_history
  configure_root_bashrc
  configure_skel
  disable_ctrl_alt_del

  show_summary

  if [ "$AUTO_FIX" = false ] && [ $WARNINGS -gt 0 ]; then
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
