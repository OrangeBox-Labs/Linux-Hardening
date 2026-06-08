#!/bin/bash

# ==============================================
# Script: ssh-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de SSH segun CIS Benchmark y mejores practicas
#              Compatible con OpenSSH 7.4+ (RHEL 7,8,9,10)
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
BACKUP_DIR="/root/ssh-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA OBTENER VERSION DE OPENSSH
# ==============================================
get_ssh_version() {
  ssh -V 2>&1 | grep -oE 'OpenSSH_[0-9]+\.[0-9]+' | cut -d'_' -f2 | cut -d'.' -f1
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    if [ -f "$SSHD_CONFIG" ]; then
      cp -p "$SSHD_CONFIG" "$BACKUP_DIR/"
    fi
    if [ -d "$SSHD_CONFIG_DIR" ]; then
      cp -r "$SSHD_CONFIG_DIR" "$BACKUP_DIR/"
    fi
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR Y CONFIGURAR PARAMETRO
# ==============================================
check_sshd_param() {
  local param="$1"
  local expected="$2"
  local description="$3"
  local fix_line="$4"

  # Extraer el nombre del parametro del fix_line (lo que va antes del espacio)
  local param_name=$(echo "$fix_line" | awk '{print $1}')

  local current=$(sshd -T 2>/dev/null | grep -i "^$param" | awk '{print $2}' | head -1)

  if [ -z "$current" ]; then
    echo -e "${RED}[!] $description - NO CONFIGURADO${NC}"
    if [ "$AUTO_FIX" = true ] && [ -n "$fix_line" ]; then
      # Verificar si ya existe la linea comentada
      if grep -qi "^#\s*$param_name" "$SSHD_CONFIG"; then
        # Descomentar y modificar
        sed -i "s/^#\s*$param_name.*/$fix_line/i" "$SSHD_CONFIG"
      else
        # Agregar al final
        echo "$fix_line" >>"$SSHD_CONFIG"
      fi
      echo -e "${GREEN}[✓] Configuracion agregada: $fix_line${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  elif [ "$current" = "$expected" ]; then
    echo -e "${GREEN}[✓] $description: $current${NC}"
  else
    echo -e "${RED}[!] $description: $current (debe ser $expected)${NC}"
    if [ "$AUTO_FIX" = true ] && [ -n "$fix_line" ]; then
      # Buscar la linea existente (case insensitive) y reemplazarla
      if grep -qi "^$param_name\s" "$SSHD_CONFIG"; then
        sed -i "s/^$param_name\s.*/$fix_line/i" "$SSHD_CONFIG"
      elif grep -qi "^#\s*$param_name\s" "$SSHD_CONFIG"; then
        sed -i "s/^#\s*$param_name\s.*/$fix_line/i" "$SSHD_CONFIG"
      else
        echo "$fix_line" >>"$SSHD_CONFIG"
      fi
      echo -e "${GREEN}[✓] Configuracion corregida: $fix_line${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# FUNCION PARA VERIFICAR PERMISOS
# ==============================================
check_permissions() {
  local file="$1"
  local perms="$2"
  local owner="$3"
  local group="$4"
  local description="$5"

  if [ ! -f "$file" ]; then
    echo -e "${YELLOW}[!] $file no existe${NC}"
    return 1
  fi

  local current_perms=$(stat -c "%a" "$file" 2>/dev/null)
  local current_owner=$(stat -c "%U" "$file" 2>/dev/null)
  local current_group=$(stat -c "%G" "$file" 2>/dev/null)

  local needs_fix=0

  if [ "$current_perms" != "$perms" ]; then
    echo -e "${RED}[!] $description permisos: $current_perms (debe ser $perms)${NC}"
    needs_fix=1
  else
    echo -e "${GREEN}[✓] $description permisos correctos: $current_perms${NC}"
  fi

  if [ "$current_owner" != "$owner" ]; then
    echo -e "${RED}[!] $description propietario: $current_owner (debe ser $owner)${NC}"
    needs_fix=1
  else
    echo -e "${GREEN}[✓] $description propietario correcto: $current_owner${NC}"
  fi

  if [ "$current_group" != "$group" ]; then
    echo -e "${RED}[!] $description grupo: $current_group (debe ser $group)${NC}"
    needs_fix=1
  else
    echo -e "${GREEN}[✓] $description grupo correcto: $current_group${NC}"
  fi

  if [ $needs_fix -eq 1 ] && [ "$AUTO_FIX" = true ]; then
    chmod "$perms" "$file" 2>/dev/null
    chown "$owner:$group" "$file" 2>/dev/null
    echo -e "${GREEN}[✓] $description corregido${NC}"
    FIXED=$((FIXED + 1))
  elif [ $needs_fix -eq 1 ]; then
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# VERIFICAR PERMISOS DE SSHD_CONFIG
# ==============================================
check_config_permissions() {
  echo -e "\n${BLUE}[*] Verificando permisos de $SSHD_CONFIG...${NC}"
  check_permissions "$SSHD_CONFIG" "600" "root" "root" "Permisos de sshd_config"
}

# ==============================================
# 5.3.2 - LIMITAR ACCESO SSH
# ==============================================
check_access_limit() {
  echo -e "\n${BLUE}[*] CIS 5.3.2 - Limitando acceso SSH...${NC}"

  local allow_users=$(sshd -T 2>/dev/null | grep -i "allowusers" | awk '{print $2}')
  local allow_groups=$(sshd -T 2>/dev/null | grep -i "allowgroups" | awk '{print $2}')

  if [ -n "$allow_users" ] || [ -n "$allow_groups" ]; then
    echo -e "${GREEN}[✓] Acceso limitado a usuarios/grupos especificos${NC}"
  else
    echo -e "${RED}[!] No hay restriccion de acceso SSH${NC}"
    echo -e "${YELLOW}    Recomendacion: Agregar 'AllowUsers usuario1 usuario2' o 'AllowGroups grupo'${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 5.3.3 - LOGLEVEL
# ==============================================
check_loglevel() {
  echo -e "\n${BLUE}[*] CIS 5.3.3 - Configurando LogLevel...${NC}"
  check_sshd_param "loglevel" "INFO" "Nivel de log" "LogLevel INFO"
}

# ==============================================
# 5.3.4 - X11 FORWARDING
# ==============================================
check_x11() {
  echo -e "\n${BLUE}[*] CIS 5.3.4 - Deshabilitando X11 Forwarding...${NC}"
  check_sshd_param "x11forwarding" "no" "X11 Forwarding" "X11Forwarding no"
}

# ==============================================
# 5.3.5 - MAXAUTHRIES
# ==============================================
check_maxauth() {
  echo -e "\n${BLUE}[*] CIS 5.3.5 - Configurando MaxAuthTries...${NC}"
  check_sshd_param "maxauthtries" "4" "Maximo intentos de autenticacion" "MaxAuthTries 4"
}

# ==============================================
# 5.3.6 - IGNORERHOSTS
# ==============================================
check_ignorerhosts() {
  echo -e "\n${BLUE}[*] CIS 5.3.6 - Deshabilitando IgnoreRhosts...${NC}"
  check_sshd_param "ignorerhosts" "yes" "Ignore Rhosts" "IgnoreRhosts yes"
}

# ==============================================
# 5.3.7 - HOSTBASEDAUTHENTICATION
# ==============================================
check_hostbased() {
  echo -e "\n${BLUE}[*] CIS 5.3.7 - Deshabilitando HostbasedAuthentication...${NC}"
  check_sshd_param "hostbasedauthentication" "no" "Hostbased Authentication" "HostbasedAuthentication no"
}

# ==============================================
# 5.3.8 - PERMITROOTLOGIN
# ==============================================
check_root_login() {
  echo -e "\n${BLUE}[*] CIS 5.3.8 - Deshabilitando login root...${NC}"
  check_sshd_param "permitrootlogin" "no" "Permitir login root" "PermitRootLogin no"
}

# ==============================================
# 5.3.9 - PERMITEMPTYPASSWORDS
# ==============================================
check_empty_passwords() {
  echo -e "\n${BLUE}[*] CIS 5.3.9 - Deshabilitando contraseñas vacias...${NC}"
  check_sshd_param "permitemptypasswords" "no" "Permitir contraseñas vacias" "PermitEmptyPasswords no"
}

# ==============================================
# 5.3.10 - PERMITUSERENVIRONMENT
# ==============================================
check_user_env() {
  echo -e "\n${BLUE}[*] CIS 5.3.10 - Deshabilitando PermitUserEnvironment...${NC}"
  check_sshd_param "permituserenvironment" "no" "Permitir entorno de usuario" "PermitUserEnvironment no"
}

# ==============================================
# 5.3.11 - CIPHERS
# ==============================================
check_ciphers() {
  echo -e "\n${BLUE}[*] CIS 5.3.11 - Verificando algoritmos de cifrado...${NC}"

  local ciphers=$(sshd -T 2>/dev/null | grep -i "ciphers" | awk '{print $2}')

  if [ -n "$ciphers" ]; then
    echo -e "${GREEN}[✓] Algoritmos de cifrado configurados${NC}"
  else
    echo -e "${RED}[!] No hay algoritmos de cifrado explicitos${NC}"
    if [ "$AUTO_FIX" = true ]; then
      # Verificar si existe linea comentada
      if grep -qi "^#\s*Ciphers" "$SSHD_CONFIG"; then
        sed -i "s/^#\s*Ciphers.*/Ciphers aes256-ctr,aes192-ctr,aes128-ctr/i" "$SSHD_CONFIG"
      else
        echo 'Ciphers aes256-ctr,aes192-ctr,aes128-ctr' >>"$SSHD_CONFIG"
      fi
      echo -e "${GREEN}[✓] Cifrado fuerte configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.3.12 - MESSAGE AUTHENTICATION CODES
# ==============================================
check_macs() {
  echo -e "\n${BLUE}[*] CIS 5.3.12 - Verificando algoritmos MAC...${NC}"

  local macs=$(sshd -T 2>/dev/null | grep -i "macs" | awk '{print $2}')

  if [ -n "$macs" ]; then
    echo -e "${GREEN}[✓] Algoritmos MAC configurados${NC}"
  else
    echo -e "${RED}[!] No hay algoritmos MAC explicitos${NC}"
    if [ "$AUTO_FIX" = true ]; then
      if grep -qi "^#\s*MACs" "$SSHD_CONFIG"; then
        sed -i "s/^#\s*MACs.*/MACs hmac-sha2-512,hmac-sha2-256/i" "$SSHD_CONFIG"
      else
        echo 'MACs hmac-sha2-512,hmac-sha2-256' >>"$SSHD_CONFIG"
      fi
      echo -e "${GREEN}[✓] MAC fuerte configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.3.13 - KEY EXCHANGE
# ==============================================
check_kex() {
  echo -e "\n${BLUE}[*] CIS 5.3.13 - Verificando algoritmos de intercambio de claves...${NC}"

  local kex=$(sshd -T 2>/dev/null | grep -i "kexalgorithms" | awk '{print $2}')

  if [ -n "$kex" ]; then
    echo -e "${GREEN}[✓] Algoritmos KEX configurados${NC}"
  else
    echo -e "${RED}[!] No hay algoritmos KEX explicitos${NC}"
    if [ "$AUTO_FIX" = true ]; then
      local kex_line='KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256'
      if grep -qi "^#\s*KexAlgorithms" "$SSHD_CONFIG"; then
        sed -i "s|^#\s*KexAlgorithms.*|$kex_line|i" "$SSHD_CONFIG"
      else
        echo "$kex_line" >>"$SSHD_CONFIG"
      fi
      echo -e "${GREEN}[✓] KEX fuerte configurado${NC}"
      FIXED=$((FIXED + 1))
    else
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.3.14 - IDLE TIMEOUT
# ==============================================
check_idle_timeout() {
  echo -e "\n${BLUE}[*] CIS 5.3.14 - Configurando ClientAliveInterval...${NC}"

  local interval=$(sshd -T 2>/dev/null | grep -i "clientaliveinterval" | awk '{print $2}')
  local count=$(sshd -T 2>/dev/null | grep -i "clientalivecountmax" | awk '{print $2}')

  if [ -n "$interval" ] && [ "$interval" -le 300 ] 2>/dev/null && [ "$count" -le 3 ] 2>/dev/null; then
    echo -e "${GREEN}[✓] Idle timeout configurado: $interval segundos, $count intentos${NC}"
  else
    echo -e "${RED}[!] Idle timeout no configurado correctamente${NC}"
    if [ "$AUTO_FIX" = true ]; then
      # Eliminar lineas existentes (comentadas o no)
      sed -i '/^#\?\s*ClientAliveInterval/d' "$SSHD_CONFIG"
      sed -i '/^#\?\s*ClientAliveCountMax/d' "$SSHD_CONFIG"
      echo "ClientAliveInterval 300" >>"$SSHD_CONFIG"
      echo "ClientAliveCountMax 0" >>"$SSHD_CONFIG"
      echo -e "${GREEN}[✓] Idle timeout configurado: 300 segundos${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: ClientAliveInterval 300 y ClientAliveCountMax 0${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.3.15 - LOGINGRACETIME
# ==============================================
check_grace_time() {
  echo -e "\n${BLUE}[*] CIS 5.3.15 - Configurando LoginGraceTime...${NC}"
  check_sshd_param "logingracetime" "60" "Tiempo de gracia para login" "LoginGraceTime 60"
}

# ==============================================
# 5.3.16 - WARNING BANNER
# ==============================================
check_banner() {
  echo -e "\n${BLUE}[*] CIS 5.3.16 - Configurando banner de advertencia...${NC}"

  local banner=$(sshd -T 2>/dev/null | grep -i "banner" | awk '{print $2}')

  if [ -n "$banner" ] && [ -f "$banner" ]; then
    echo -e "${GREEN}[✓] Banner configurado: $banner${NC}"
  else
    echo -e "${RED}[!] Banner de advertencia no configurado${NC}"
    if [ "$AUTO_FIX" = true ]; then
      # Crear banner si no existe
      if [ ! -f "/etc/issue.net" ]; then
        echo "Sistema de uso autorizado solamente. Acceso no autorizado es un delito." >/etc/issue.net
      fi
      if grep -qi "^#\?\s*Banner" "$SSHD_CONFIG"; then
        sed -i "s/^#\?\s*Banner.*/Banner \/etc\/issue.net/i" "$SSHD_CONFIG"
      else
        echo "Banner /etc/issue.net" >>"$SSHD_CONFIG"
      fi
      echo -e "${GREEN}[✓] Banner configurado: /etc/issue.net${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Banner /etc/issue.net${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 5.3.17 - PAM
# ==============================================
check_pam() {
  echo -e "\n${BLUE}[*] CIS 5.3.17 - Verificando PAM...${NC}"
  check_sshd_param "usepam" "yes" "Uso de PAM" "UsePAM yes"
}

# ==============================================
# 5.3.18 - ALLOWTCPFORWARDING
# ==============================================
check_tcp_forwarding() {
  echo -e "\n${BLUE}[*] CIS 5.3.18 - Deshabilitando TCP forwarding...${NC}"
  check_sshd_param "allowtcpforwarding" "no" "Allow TCP Forwarding" "AllowTcpForwarding no"
}

# ==============================================
# 5.3.19 - MAXSTARTUPS
# ==============================================
check_maxstartups() {
  echo -e "\n${BLUE}[*] CIS 5.3.19 - Configurando MaxStartups...${NC}"
  check_sshd_param "maxstartups" "10:30:60" "Maximo de conexiones simultaneas" "MaxStartups 10:30:60"
}

# ==============================================
# 5.3.20 - MAXSESSIONS
# ==============================================
check_maxsessions() {
  echo -e "\n${BLUE}[*] CIS 5.3.20 - Configurando MaxSessions...${NC}"
  check_sshd_param "maxsessions" "10" "Maximo de sesiones por conexion" "MaxSessions 10"
}

# ==============================================
# CONFIGURACIONES ADICIONALES DE SEGURIDAD
# COMPATIBLE CON OPENSSH 7.4+ (RHEL 7 A 10)
# ==============================================
check_extra_security() {
  echo -e "\n${BLUE}[*] Configurando medidas de seguridad adicionales...${NC}"

  local ssh_version=$(get_ssh_version)
  echo -e "${BLUE}[*] Version detectada: OpenSSH $ssh_version${NC}"

  # Configurar algoritmos de clave publica segun version
  if [ "$ssh_version" -ge 9 ] 2>/dev/null; then
    check_sshd_param "pubkeyacceptedalgorithms" "" "Algoritmos de clave publica" "PubkeyAcceptedAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256"
  elif [ "$ssh_version" -ge 7 ] 2>/dev/null; then
    check_sshd_param "pubkeyacceptedkeytypes" "" "Algoritmos de clave publica" "PubkeyAcceptedKeyTypes ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256"
  else
    echo -e "${YELLOW}[!] No se pudo detectar version, omitiendo configuracion de algoritmos de clave${NC}"
  fi

  check_sshd_param "compression" "no" "Compresion" "Compression no"
  check_sshd_param "gssapiauthentication" "no" "GSSAPI Authentication" "GSSAPIAuthentication no"
  check_sshd_param "kerberosauthentication" "no" "Kerberos Authentication" "KerberosAuthentication no"
}

# ==============================================
# REINICIAR SSH
# ==============================================
restart_ssh() {
  echo -e "\n${BLUE}[*] Validando y reiniciando SSH...${NC}"

  if [ "$AUTO_FIX" = true ]; then
    if sshd -t; then
      systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] SSH reiniciado correctamente${NC}"
      else
        echo -e "${YELLOW}[!] SSH configuracion valida pero servicio no reiniciado${NC}"
      fi
    else
      echo -e "${RED}[!] Error en configuracion de SSH${NC}"
      sshd -t
      echo -e "${RED}[!] Restaurando backup...${NC}"
      if [ -f "$BACKUP_DIR/sshd_config" ]; then
        cp "$BACKUP_DIR/sshd_config" "$SSHD_CONFIG"
        systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null
        echo -e "${YELLOW}[!] Backup restaurado${NC}"
      fi
      exit 1
    fi
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  REPORTE SSH HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"

  echo -e "\n${YELLOW}PARA VERIFICAR CONFIGURACION:${NC}"
  echo -e "  sshd -T"
  echo -e "  sshd -t"
  echo -e "  cat $SSHD_CONFIG | grep -E '^(PermitRootLogin|PasswordAuthentication|Port|Protocol)'"

  echo -e "\n${YELLOW}PARA VER LOGS DE SSH:${NC}"
  echo -e "  tail -f /var/log/secure | grep sshd\n"
  echo -e "\n${YELLOW}PARA APLICAR LAS CORRECCIONES EJECUTA:${NC}"
  echo -e "  ./ssh-hardening.sh --fix\n"
}

# ==============================================
# MOSTRAR INTRO
# ==============================================
show_intro() {
  echo -e "${YELLOW}"
  echo "Este script configura hardening de SSH segun CIS Benchmark"
  echo ""
  echo "LOS CAMBIOS INCLUYEN:"
  echo "  - Permisos 600 para /etc/ssh/sshd_config"
  echo "  - Deshabilitar login root"
  echo "  - Limitar intentos de autenticacion a 4"
  echo "  - Deshabilitar X11Forwarding y TCPForwarding"
  echo "  - Configurar timeout de sesion inactiva"
  echo "  - Algoritmos de cifrado, MAC y KEX fuertes"
  echo "  - Banner de advertencia"
  echo ""
  echo -e "${RED}NOTA: Deshabilitar login root puede afectar administradores acostumbrados a usar root directamente${NC}"
  echo -e "${RED}      Se recomienda tener un usuario con sudo configurado antes de aplicar${NC}"
  echo ""
  echo -e "${YELLOW}Backup de configuraciones en: $BACKUP_DIR${NC}"
  echo ""
  echo -e "${GREEN}Presione Enter para continuar o Ctrl+C para cancelar...${NC}"
  read -r
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  SSH Hardening - CIS 5.3.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    make_backup
    show_intro
    echo -e "${YELLOW}[!] Modo automatico: aplicando configuraciones...${NC}"
    echo ""
  else
    AUTO_FIX=false
    echo -e "${YELLOW}[!] Modo verificacion: no se aplicaran cambios${NC}"
    echo -e "${YELLOW}[!] Ejecute con --fix para aplicar${NC}"
    echo ""
  fi

  check_config_permissions
  check_access_limit
  check_loglevel
  check_x11
  check_maxauth
  check_ignorerhosts
  check_hostbased
  check_root_login
  check_empty_passwords
  check_user_env
  check_ciphers
  check_macs
  check_kex
  check_idle_timeout
  check_grace_time
  check_banner
  check_pam
  check_tcp_forwarding
  check_maxstartups
  check_maxsessions
  check_extra_security
  restart_ssh
  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
