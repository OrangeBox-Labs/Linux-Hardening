#!/bin/bash

# ==============================================
# Script: bash-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de Bash shell y entorno de usuario
#              Configura historial con fecha/hora, prompt mejorado,
#              timeout, umask segura, alias útiles, auditoría en syslog
#              y protecciones adicionales
# Compatible con RHEL/CentOS/Rocky/AlmaLinux/Oracle 7,8,9,10
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/bash-backup-$(date +%Y%m%d-%H%M%S)"

# Archivos de configuración
BASHRC_SYSTEM="/etc/bashrc"
PROFILE_D="/etc/profile.d/orangebox.sh"
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
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    for file in "$BASHRC_SYSTEM" "$PROFILE_D" "$ALIASES_D" "$HISTORY_SYSLOG" "$HISTORY_SECURE" "$BASHRC_ROOT" "$SKEL_BASHRC" "$RSYSLOG_CONF"; do
      [ -f "$file" ] && cp "$file" "$BACKUP_DIR/"
    done
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# VERIFICAR SI FIGLET ESTA INSTALADO
# ==============================================
check_figlet() {
  if ! command -v figlet &>/dev/null; then
    echo -e "${YELLOW}[!] figlet no esta instalado (opcional para banner)${NC}"
    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Instalando figlet...${NC}"
      if command -v dnf &>/dev/null; then
        dnf install -y figlet 2>/dev/null
      else
        yum install -y figlet 2>/dev/null
      fi
      if command -v figlet &>/dev/null; then
        echo -e "${GREEN}[✓] figlet instalado${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${YELLOW}[!] No se pudo instalar figlet, banner omitido${NC}"
      fi
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# CONFIGURAR PROFILE.D CON BANNER Y PROMPT
# ==============================================
configure_profile() {
  echo -e "\n${BLUE}[*] Configurando banner de login y prompt de bash...${NC}"

  if [ -f "$PROFILE_D" ] && grep -q "OrangeBox" "$PROFILE_D" 2>/dev/null; then
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

# Banner de OrangeBox (si figlet esta instalado)
if command -v figlet &>/dev/null; then
    echo "$(tput setaf 214)$(figlet -f small 'OrangeBox')$(tput sgr0)"
    echo -e "${GREEN}  Hardening Bash - Configuracion segura${NC}"
    echo ""
fi

# Mostrar información de la conexión
echo -e "${YELLOW}=== INFORMACION DE CONEXION ===${NC}"
echo -e "${GREEN}Hostname completo:${NC} $(hostname -f 2>/dev/null || hostname)"
echo -e "${GREEN}IP del cliente:${NC} $(who am i | awk '{print $5}' | tr -d '()' || echo 'local')"
echo -e "${GREEN}Usuario:${NC} $USER"
echo -e "${GREEN}Fecha/Hora:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Prompt personalizado: [HORA] usuario@hostname directorio $
export PS1="\[\e[2m\]\A\[\e[0m\] \[\e[1;32m\]\u@\H\[\e[0m\] \[\e[1;34m\]\W\[\e[0m\] $ "

# Historial con fecha y hora
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000
export HISTFILESIZE=50000
export HISTCONTROL=ignoredups:ignorespace
export HISTFILE="$HOME/.bash_history"

# Unificar historial de múltiples sesiones
shopt -s histappend
export PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

# Timeout de sesión inactiva (15 minutos)
export TMOUT=900
readonly TMOUT

# Umask segura (archivos nuevos con permisos 750 para directorios, 640 para archivos)
umask 027

# Alias útiles para seguridad
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias vi='vim'
alias sudo='sudo '

# Historial inmutable (evita que el usuario lo desactive)
readonly HISTFILE
EOF
    echo -e "${GREEN}[✓] Profile creado en $PROFILE_D${NC}"
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
alias myip='curl -s ifconfig.me && echo ""'

# Navegación rápida
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias /='cd /'

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

    # Configurar rsyslog
    cat >"$RSYSLOG_CONF" <<'EOF'
# Logs de comandos bash - OrangeBox Labs
local1.notice    /var/log/bash_commands.log
EOF
    if systemctl restart rsyslog 2>/dev/null; then
      echo -e "${GREEN}[✓] Rsyslog configurado para recibir comandos${NC}"
      FIXED=$((FIXED + 1))
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

  if [ -f "$HISTORY_SECURE" ] && grep -q "OrangeBox" "$HISTORY_SECURE" 2>/dev/null; then
    echo -e "${GREEN}[✓] Historial seguro ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] Historial seguro NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    # Crear directorio para historial
    mkdir -p /var/log/bash_history
    chmod 750 /var/log/bash_history
    chown root:root /var/log/bash_history

    cat >"$HISTORY_SECURE" <<'EOF'
# ==============================================
# Historial seguro por usuario - OrangeBox Labs
# ==============================================

# Crear archivo de historial por usuario en /var/log/bash_history
if [ ! -d "/var/log/bash_history" ]; then
    mkdir -p /var/log/bash_history
    chmod 750 /var/log/bash_history
fi

HISTORY_FILE="/var/log/bash_history/${USER}.history"
touch "$HISTORY_FILE" 2>/dev/null && chmod 640 "$HISTORY_FILE" 2>/dev/null
export HISTFILE="$HISTORY_FILE"
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

  if grep -q "OrangeBox" "$BASHRC_ROOT" 2>/dev/null; then
    echo -e "${GREEN}[✓] /root/.bashrc ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] /root/.bashrc NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    cat >>"$BASHRC_ROOT" <<'EOF'

# ==============================================
# Hardening Bash - OrangeBox Labs
# ==============================================

# Historial mejorado
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=20000
export HISTFILESIZE=100000
export HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"

# Historial inmutable (protegido)
readonly HISTFILE

# Prompt personalizado para root (en rojo)
export PS1="\[\e[2m\]\A\[\e[0m\] \[\e[1;31m\]\u@\H\[\e[0m\] \[\e[1;34m\]\W\[\e[0m\] # "

# Timeout más estricto para root (10 minutos)
export TMOUT=600
readonly TMOUT

# Umask segura
umask 027

# Alias con confirmación
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias vi='vim'
alias reboot='echo "Use shutdown -r now to reboot"'
alias poweroff='echo "Use shutdown -h now to poweroff"'
EOF
    echo -e "${GREEN}[✓] /root/.bashrc actualizado${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR /etc/skel PARA NUEVOS USUARIOS
# ==============================================
configure_skel() {
  echo -e "\n${BLUE}[*] Configurando /etc/skel para nuevos usuarios...${NC}"

  if [ -f "$SKEL_BASHRC" ] && grep -q "OrangeBox" "$SKEL_BASHRC" 2>/dev/null; then
    echo -e "${GREEN}[✓] /etc/skel/.bashrc ya configurado${NC}"
    return 0
  fi

  echo -e "${RED}[!] /etc/skel/.bashrc NO configurado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    cat >>"$SKEL_BASHRC" <<'EOF'

# ==============================================
# Hardening Bash - OrangeBox Labs
# ==============================================

export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000
export HISTFILESIZE=50000
export HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
export TMOUT=900
umask 027
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
EOF
    echo -e "${GREEN}[✓] /etc/skel/.bashrc actualizado${NC}"
    FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# INSTALAR HERRAMIENTAS OPCIONALES
# ==============================================
install_optional_tools() {
  echo -e "\n${BLUE}[*] Verificando herramientas opcionales...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    # bat - cat con colores y sintaxis
    if ! command -v bat &>/dev/null; then
      echo -e "${YELLOW}[*] Intentando instalar bat...${NC}"
      if command -v dnf &>/dev/null; then
        dnf install -y bat 2>/dev/null || echo -e "${YELLOW}[!] bat no disponible en repositorios${NC}"
      else
        yum install -y bat 2>/dev/null || echo -e "${YELLOW}[!] bat no disponible en repositorios${NC}"
      fi
      if command -v bat &>/dev/null; then
        echo -e "${GREEN}[✓] bat instalado${NC}"
        echo "alias cat='bat'" >>"$ALIASES_D"
        FIXED=$((FIXED + 1))
      fi
    fi

    # exa - ls mejorado (requiere EPEL)
    if ! command -v exa &>/dev/null; then
      echo -e "${YELLOW}[*] Intentando instalar exa...${NC}"
      if command -v dnf &>/dev/null; then
        dnf install -y exa 2>/dev/null || echo -e "${YELLOW}[!] exa no disponible en repositorios${NC}"
      else
        yum install -y exa 2>/dev/null || echo -e "${YELLOW}[!] exa no disponible en repositorios${NC}"
      fi
      if command -v exa &>/dev/null; then
        echo -e "${GREEN}[✓] exa instalado${NC}"
        echo "alias ls='exa -l --git'" >>"$ALIASES_D"
        FIXED=$((FIXED + 1))
      fi
    fi

    # duf - df mejorado
    if ! command -v duf &>/dev/null; then
      echo -e "${YELLOW}[*] Intentando instalar duf...${NC}"
      if command -v dnf &>/dev/null; then
        dnf install -y duf 2>/dev/null || echo -e "${YELLOW}[!] duf no disponible en repositorios${NC}"
      else
        yum install -y duf 2>/dev/null || echo -e "${YELLOW}[!] duf no disponible en repositorios${NC}"
      fi
      if command -v duf &>/dev/null; then
        echo -e "${GREEN}[✓] duf instalado${NC}"
        echo "alias df='duf'" >>"$ALIASES_D"
        FIXED=$((FIXED + 1))
      fi
    fi
  fi
}

# ==============================================
# DESHABILITAR CTRL+ALT+DEL
# ==============================================
disable_ctrl_alt_del() {
  echo -e "\n${BLUE}[*] Deshabilitando Ctrl+Alt+Del...${NC}"

  if [ -f /usr/lib/systemd/system/ctrl-alt-del.target ]; then
    if systemctl is-enabled ctrl-alt-del.target 2>/dev/null | grep -q "masked"; then
      echo -e "${GREEN}[✓] Ctrl+Alt+Del ya esta deshabilitado${NC}"
      return 0
    fi

    echo -e "${RED}[!] Ctrl+Alt+Del NO esta deshabilitado${NC}"

    if [ "$AUTO_FIX" = true ]; then
      systemctl mask ctrl-alt-del.target
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

  echo -e "\n${BLUE}Aliases:${NC}"
  [ -f "$ALIASES_D" ] && echo -e "  ${GREEN}✓${NC} $ALIASES_D existe" || echo -e "  ${RED}✗${NC} $ALIASES_D no existe"

  echo -e "\n${BLUE}Historial con fecha:${NC}"
  [ -n "$HISTTIMEFORMAT" ] && echo -e "  ${GREEN}✓${NC} HISTTIMEFORMAT configurado" || echo -e "  ${RED}✗${NC} HISTTIMEFORMAT no configurado"

  echo -e "\n${BLUE}Timeout de sesion:${NC}"
  [ -n "$TMOUT" ] && echo -e "  ${GREEN}✓${NC} TMOUT configurado" || echo -e "  ${RED}✗${NC} TMOUT no configurado"

  echo -e "\n${BLUE}Umask:${NC}"
  echo -e "  $(umask)"

  echo -e "\n${BLUE}Ctrl+Alt+Del:${NC}"
  if systemctl is-enabled ctrl-alt-del.target 2>/dev/null | grep -q "masked"; then
    echo -e "  ${GREEN}✓${NC} Deshabilitado"
  else
    echo -e "  ${RED}✗${NC} Habilitado"
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
    make_backup
  fi

  # Ejecutar configuraciones
  check_figlet
  configure_profile
  configure_aliases
  configure_syslog_history
  configure_secure_history
  configure_root_bashrc
  configure_skel
  install_optional_tools
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
