#!/bin/bash

# ==============================================
# Script: ssh-hardening-complete.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening completo de SSH basado en ssh-audit
#              Compatible con RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10
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
SSH_MODULI="/etc/ssh/moduli"
BACKUP_DIR="/root/ssh-backup-$(date +%Y%m%d-%H%M%S)"

# ==============================================
# FUNCION PARA VERIFICAR E INSTALAR ssh-audit
# ==============================================
check_ssh_audit() {
  if ! command -v ssh-audit &>/dev/null; then
    echo -e "${RED}[!] ssh-audit no esta instalado${NC}"
    echo -e "${YELLOW}[*] Intentando instalar ssh-audit...${NC}"

    INSTALL_SUCCESS=false

    # Intentar con dnf (RHEL 8,9,10, Fedora)
    if command -v dnf &>/dev/null; then
      # Verificar si epel-release esta instalado
      if ! rpm -q epel-release &>/dev/null; then
        echo -e "${YELLOW}[*] Instalando epel-release...${NC}"
        dnf install epel-release -y 2>/dev/null
      fi

      dnf install ssh-audit -y 2>/dev/null
      if [ $? -eq 0 ]; then
        INSTALL_SUCCESS=true
      fi
    fi

    # Intentar con yum (RHEL 7)
    if [ "$INSTALL_SUCCESS" = false ] && command -v yum &>/dev/null; then
      if ! rpm -q epel-release &>/dev/null; then
        echo -e "${YELLOW}[*] Instalando epel-release...${NC}"
        yum install epel-release -y 2>/dev/null
      fi

      yum install ssh-audit -y 2>/dev/null
      if [ $? -eq 0 ]; then
        INSTALL_SUCCESS=true
      fi
    fi

    # Intentar con apt (Debian/Ubuntu)
    if [ "$INSTALL_SUCCESS" = false ] && command -v apt &>/dev/null; then
      apt update 2>/dev/null
      apt install ssh-audit -y 2>/dev/null
      if [ $? -eq 0 ]; then
        INSTALL_SUCCESS=true
      fi
    fi

    # Verificar si la instalacion fue exitosa
    if [ "$INSTALL_SUCCESS" = true ] && command -v ssh-audit &>/dev/null; then
      echo -e "${GREEN}[✓] ssh-audit instalado correctamente${NC}"
    else
      echo -e "${RED}[!] No se pudo instalar ssh-audit automaticamente${NC}"
      echo -e "${YELLOW}    Instalacion manual:${NC}"
      echo -e "      RHEL/CentOS/Rocky/Alma: dnf install epel-release -y && dnf install ssh-audit -y"
      echo -e "      Debian/Ubuntu: apt install ssh-audit -y"
      echo -e "      Desde fuente: pip install ssh-audit"
      exit 1
    fi
  else
    echo -e "${GREEN}[✓] ssh-audit esta instalado${NC}"
  fi
}

# ==============================================
# FUNCION PARA DETECTAR DISTRIBUCION
# ==============================================
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
    rocky | almalinux | centos | rhel | oracle)
      distro="$ID"
      distro_version=$(echo "$VERSION_ID" | cut -d. -f1)
      ;;
    *)
      if [[ "$ID_LIKE" == *"rhel"* ]]; then
        distro="rhel"
        distro_version=$(echo "$VERSION_ID" | cut -d. -f1)
      else
        echo -e "${RED}[!] Distribucion no soportada: $ID${NC}"
        exit 1
      fi
      ;;
    esac
  else
    echo -e "${RED}[!] No se pudo detectar la distribucion${NC}"
    exit 1
  fi

  case "$distro_version" in
  7 | 8 | 9 | 10)
    rhel_version="$distro_version"
    ;;
  *)
    echo -e "${RED}[!] Version no soportada: $distro_version${NC}"
    echo -e "${YELLOW}    Versiones soportadas: 7, 8, 9, 10${NC}"
    exit 1
    ;;
  esac

  echo -e "${GREEN}[✓] Distribucion detectada: $distro $rhel_version${NC}"
}

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
  echo "  ./ssh-hardening-complete.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./ssh-hardening-complete.sh --fix"
  echo ""
}

# ==============================================
# FUNCION PARA MOSTRAR ANALISIS ACTUAL DE SSH-AUDIT
# ==============================================
show_ssh_audit_analysis() {
  echo -e "\n${BLUE}[*] Analisis actual de ssh-audit:${NC}\n"

  local audit_output=$(ssh-audit localhost 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

  echo -e "${YELLOW}=== KEY EXCHANGE ALGORITHMS ===${NC}"
  local in_section=""

  while IFS= read -r line; do
    if echo "$line" | grep -q "^# key exchange algorithms"; then
      in_section="kex"
      continue
    fi
    if echo "$line" | grep -q "^# host-key algorithms"; then
      in_section="key"
      echo ""
      echo -e "${YELLOW}=== HOST-KEY ALGORITHMS ===${NC}"
      continue
    fi
    if echo "$line" | grep -q "^# encryption algorithms"; then
      in_section="enc"
      echo ""
      echo -e "${YELLOW}=== ENCRYPTION ALGORITHMS ===${NC}"
      continue
    fi
    if echo "$line" | grep -q "^# message authentication code algorithms"; then
      in_section="mac"
      echo ""
      echo -e "${YELLOW}=== MAC ALGORITHMS ===${NC}"
      continue
    fi
    if echo "$line" | grep -q "^# fingerprints"; then
      in_section=""
      continue
    fi

    if [ -n "$in_section" ] && echo "$line" | grep -q "^("; then
      if echo "$line" | grep -q "\[fail\]"; then
        echo -e "  ${RED}❌ FAIL:${NC} $line"
      elif echo "$line" | grep -q "\[warn\]"; then
        echo -e "  ${YELLOW}⚠️  WARN:${NC} $line"
      elif echo "$line" | grep -q "\[info\]"; then
        echo -e "  ${GREEN}✓${NC} $line"
      else
        echo -e "  ${BLUE}ℹ️${NC} $line"
      fi
    fi
  done <<<"$audit_output"

  echo -e "\n${YELLOW}=== RECOMENDACIONES ===${NC}"
  local recs=$(echo "$audit_output" | grep -E "\(rec\)")

  if [ -n "$recs" ]; then
    echo "$recs" | while read line; do
      local clean_line=$(echo "$line" | sed 's/(rec) //')
      if echo "$clean_line" | grep -q "^-"; then
        echo -e "  ${RED}➖ REMOVER:${NC} $(echo "$clean_line" | sed 's/^-//')"
      elif echo "$clean_line" | grep -q "^+"; then
        echo -e "  ${GREEN}➕ AGREGAR:${NC} $(echo "$clean_line" | sed 's/^+//')"
      else
        echo -e "  ${BLUE}→${NC} $clean_line"
      fi
    done
  else
    echo -e "  ${GREEN}✓ No hay recomendaciones pendientes${NC}"
  fi
}

# ==============================================
# FUNCION PARA MOSTRAR CONFIGURACION ACTUAL
# ==============================================
show_current_config() {
  echo -e "\n${BLUE}[*] Configuracion actual de SSH:${NC}\n"

  echo -e "${YELLOW}KexAlgorithms:${NC}"
  grep -i "^KexAlgorithms" "$SSHD_CONFIG" 2>/dev/null || echo "  (no configurado - usando defaults del sistema)"

  echo -e "\n${YELLOW}Ciphers:${NC}"
  grep -i "^Ciphers" "$SSHD_CONFIG" 2>/dev/null || echo "  (no configurado - usando defaults del sistema)"

  echo -e "\n${YELLOW}MACs:${NC}"
  grep -i "^MACs" "$SSHD_CONFIG" 2>/dev/null || echo "  (no configurado - usando defaults del sistema)"

  echo -e "\n${YELLOW}HostKeyAlgorithms:${NC}"
  grep -i "^HostKeyAlgorithms" "$SSHD_CONFIG" 2>/dev/null || echo "  (no configurado - usando defaults del sistema)"

  echo -e "\n${YELLOW}PermitRootLogin:${NC}"
  grep -i "^PermitRootLogin" "$SSHD_CONFIG" 2>/dev/null || echo "  (no configurado - usando defaults del sistema)"
}

# ==============================================
# FUNCION PARA MOSTRAR LO QUE SE VA A APLICAR
# ==============================================
show_will_apply() {
  echo -e "\n${YELLOW}📋 LO QUE SE APLICARA CON --fix:${NC}\n"

  echo -e "  ${GREEN}1.${NC} Regeneracion de claves SSH:"
  echo -e "     - Eliminacion de claves existentes"
  echo -e "     - Regeneracion de clave RSA (4096 bits)"
  echo -e "     - Regeneracion de clave ED25519"

  echo -e "\n  ${GREEN}2.${NC} Eliminacion de moduli Diffie-Hellman:"
  echo -e "     - Filtrado de moduli menores a 3071 bits"
  echo -e "     - Respaldo del archivo original"

  echo -e "\n  ${GREEN}3.${NC} Configuracion de algoritmos seguros:"
  echo -e "     - KEX: curve25519, diffie-hellman-group16/18 (sin curvas NIST)"
  echo -e "     - Ciphers: chacha20-poly1305, AES-GCM, AES-CTR"
  echo -e "     - MACs: solo ETM (encrypt-then-MAC)"
  echo -e "     - HostKeyAlgorithms: ED25519, RSA-SHA2-512/256"

  echo -e "\n  ${GREEN}4.${NC} Hardening adicional:"
  echo -e "     - Deshabilitado: PermitRootLogin, X11Forwarding, TCP forwarding"
  echo -e "     - Timeout: 5 minutos de inactividad (ClientAliveInterval 300)"
  echo -e "     - MaxAuthTries: 4 intentos"
  echo -e "     - LoginGraceTime: 60 segundos"
  echo -e "     - LogLevel: VERBOSE"

  if [ "$rhel_version" -ge 8 ]; then
    echo -e "\n  ${GREEN}5.${NC} Throttling de conexiones (firewalld):"
    echo -e "     - Maximo 10 conexiones cada 10 segundos por IP"
    echo -e "     - Reglas permanentes en firewalld"
  fi
}

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  if [ "$AUTO_FIX" = true ]; then
    mkdir -p "$BACKUP_DIR"
    [ -f "$SSHD_CONFIG" ] && cp -p "$SSHD_CONFIG" "$BACKUP_DIR/"
    [ -f "$SSH_MODULI" ] && cp -p "$SSH_MODULI" "$BACKUP_DIR/"
    echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"
  fi
}

# ==============================================
# FUNCIONES PARA RHEL 7
# ==============================================
apply_hardening_rhel7() {
  echo -e "\n${BLUE}[*] Aplicando hardening para RHEL/CentOS 7...${NC}"

  mkdir -p /etc/systemd/system/sshd-keygen.service.d
  cat <<'EOF' >/etc/systemd/system/sshd-keygen.service.d/ssh-audit.conf
[Unit]
ConditionFileNotEmpty=
ConditionFileNotEmpty=!/etc/ssh/ssh_host_ed25519_key
EOF
  systemctl daemon-reload
  echo -e "${GREEN}[✓] Deshabilitado auto-regen de claves inseguras${NC}"

  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
  chgrp ssh_keys /etc/ssh/ssh_host_ed25519_key 2>/dev/null
  chmod g+r /etc/ssh/ssh_host_ed25519_key 2>/dev/null
  echo -e "${GREEN}[✓] Regenerada clave ED25519${NC}"

  if [ -f "$SSH_MODULI" ]; then
    awk '$5 >= 3071' "$SSH_MODULI" >/etc/ssh/moduli.safe
    mv -f /etc/ssh/moduli.safe /etc/ssh/moduli
    echo -e "${GREEN}[✓] Eliminados moduli DH < 3071 bits${NC}"
  fi

  sed -i 's/^HostKey \/etc\/ssh\/ssh_host_\(rsa\|dsa\|ecdsa\)_key$/#HostKey \/etc\/ssh\/ssh_host_\1_key/g' "$SSHD_CONFIG"
  echo -e "${GREEN}[✓] Deshabilitadas claves RSA, DSA, ECDSA${NC}"

  cat <<'EOF' >>"$SSHD_CONFIG"

# ==============================================
# Hardening SSH - sshaudit.com
# ==============================================
HostKey /etc/ssh/ssh_host_ed25519_key
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group18-sha512,diffie-hellman-group16-sha512,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
X11Forwarding no
AllowTcpForwarding no
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 0
MaxAuthTries 4
MaxSessions 10
LoginGraceTime 60
LogLevel VERBOSE
UsePAM yes
Compression no
PrintLastLog yes
IgnoreRhosts yes
StrictModes yes
EOF

  echo -e "${GREEN}[✓] Configuracion SSH segura agregada${NC}"
}

# ==============================================
# FUNCIONES PARA RHEL 8
# ==============================================
apply_hardening_rhel8() {
  echo -e "\n${BLUE}[*] Aplicando hardening para RHEL/CentOS 8...${NC}"

  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
  chgrp ssh_keys /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_rsa_key 2>/dev/null
  chmod g+r /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_rsa_key 2>/dev/null
  echo -e "${GREEN}[✓] Regeneradas claves RSA (4096) y ED25519${NC}"

  if [ -f "$SSH_MODULI" ]; then
    awk '$5 >= 3071' "$SSH_MODULI" >/etc/ssh/moduli.safe
    mv -f /etc/ssh/moduli.safe /etc/ssh/moduli
    echo -e "${GREEN}[✓] Eliminados moduli DH < 3071 bits${NC}"
  fi

  sed -i 's/^HostKey \/etc\/ssh\/ssh_host_ecdsa_key$/#HostKey \/etc\/ssh\/ssh_host_ecdsa_key/g' "$SSHD_CONFIG"
  echo -e "${GREEN}[✓] Deshabilitada clave ECDSA${NC}"

  cp /etc/crypto-policies/back-ends/opensshserver.config /etc/crypto-policies/back-ends/opensshserver.config.orig 2>/dev/null

  cat <<'EOF' >/etc/crypto-policies/back-ends/opensshserver.config
CRYPTO_POLICY='-oCiphers=chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr -oMACs=hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com -oGSSAPIKexAlgorithms=gss-curve25519-sha256- -oKexAlgorithms=curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256 -oHostKeyAlgorithms=ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512 -oPubkeyAcceptedKeyTypes=ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-512'
EOF
  echo -e "${GREEN}[✓] Configuradas politicas criptograficas${NC}"

  cat <<'EOF' >>"$SSHD_CONFIG"

HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
X11Forwarding no
AllowTcpForwarding no
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 0
MaxAuthTries 4
MaxSessions 10
LoginGraceTime 60
LogLevel VERBOSE
UsePAM yes
Compression no
PrintLastLog yes
IgnoreRhosts yes
StrictModes yes
EOF

  echo -e "${GREEN}[✓] Configuracion adicional agregada${NC}"
}

# ==============================================
# FUNCIONES PARA RHEL 9
# ==============================================
apply_hardening_rhel9() {
  echo -e "\n${BLUE}[*] Aplicando hardening para RHEL/Rocky/AlmaLinux 9...${NC}"

  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
  echo -e "${GREEN}[✓] Regeneradas claves RSA (4096) y ED25519${NC}"

  echo -e "\nHostKey /etc/ssh/ssh_host_ed25519_key\nHostKey /etc/ssh/ssh_host_rsa_key" >>"$SSHD_CONFIG"
  echo -e "${GREEN}[✓] Habilitadas claves ED25519 y RSA${NC}"

  if [ -f "$SSH_MODULI" ]; then
    awk '$5 >= 3071' "$SSH_MODULI" >/etc/ssh/moduli.safe
    mv -f /etc/ssh/moduli.safe /etc/ssh/moduli
    echo -e "${GREEN}[✓] Eliminados moduli DH < 3071 bits${NC}"
  fi

  cat <<'EOF' >/etc/crypto-policies/back-ends/opensshserver.config
# Restrict key exchange, cipher, and MAC algorithms, as per sshaudit.com
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,gss-curve25519-sha256-,diffie-hellman-group16-sha512,gss-group16-sha512-,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-gcm@openssh.com,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms sk-ssh-ed25519-cert-v01@openssh.com,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,ssh-ed25519,rsa-sha2-512,rsa-sha2-256
RequiredRSASize 3072
CASignatureAlgorithms sk-ssh-ed25519@openssh.com,ssh-ed25519,rsa-sha2-512,rsa-sha2-256
GSSAPIKexAlgorithms gss-curve25519-sha256-,gss-group16-sha512-
HostbasedAcceptedAlgorithms sk-ssh-ed25519-cert-v01@openssh.com,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,ssh-ed25519,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-256
PubkeyAcceptedAlgorithms sk-ssh-ed25519-cert-v01@openssh.com,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,ssh-ed25519,rsa-sha2-512,rsa-sha2-256
EOF
  echo -e "${GREEN}[✓] Configuradas politicas criptograficas avanzadas${NC}"

  cat <<'EOF' >>"$SSHD_CONFIG"

PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
X11Forwarding no
AllowTcpForwarding no
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 0
MaxAuthTries 4
MaxSessions 10
LoginGraceTime 60
LogLevel VERBOSE
UsePAM yes
Compression no
PrintLastLog yes
IgnoreRhosts yes
StrictModes yes
EOF

  echo -e "${GREEN}[✓] Configuracion adicional agregada${NC}"
}

# ==============================================
# FUNCIONES PARA RHEL 10
# ==============================================
apply_hardening_rhel10() {
  echo -e "\n${BLUE}[*] Aplicando hardening para RHEL/Rocky/AlmaLinux 10...${NC}"

  rm -f /etc/ssh/ssh_host_*
  ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ""
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
  echo -e "${GREEN}[✓] Regeneradas claves RSA (4096) y ED25519${NC}"

  echo -e "\nHostKey /etc/ssh/ssh_host_ed25519_key\nHostKey /etc/ssh/ssh_host_rsa_key" >>"$SSHD_CONFIG"
  echo -e "${GREEN}[✓] Habilitadas claves ED25519 y RSA${NC}"

  if [ -f "$SSH_MODULI" ]; then
    awk '$5 >= 3071' "$SSH_MODULI" >/etc/ssh/moduli.safe
    mv -f /etc/ssh/moduli.safe /etc/ssh/moduli
    echo -e "${GREEN}[✓] Eliminados moduli DH < 3071 bits${NC}"
  fi

  cat <<'EOF' >/etc/crypto-policies/back-ends/opensshserver.config
# Restrict key exchange, cipher, and MAC algorithms, as per sshaudit.com
# Configuracion para RHEL 10
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-gcm@openssh.com,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-ed25519,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256
CASignatureAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
PubkeyAcceptedAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-ed25519,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256
EOF
  echo -e "${GREEN}[✓] Configuradas politicas criptograficas para RHEL 10${NC}"

  cat <<'EOF' >>"$SSHD_CONFIG"

PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
X11Forwarding no
AllowTcpForwarding no
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 0
MaxAuthTries 4
MaxSessions 10
LoginGraceTime 60
LogLevel VERBOSE
UsePAM yes
Compression no
PrintLastLog yes
IgnoreRhosts yes
StrictModes yes
EOF

  echo -e "${GREEN}[✓] Configuracion adicional agregada${NC}"
}

# ==============================================
# FUNCION PARA CONFIGURAR THROTTLING
# ==============================================
configure_throttling() {
  if [ "$rhel_version" -ge 8 ] && command -v firewall-cmd &>/dev/null; then
    echo -e "\n${BLUE}[*] Configurando throttling de conexiones SSH...${NC}"

    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 22 -m state --state NEW -m recent --set
    firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 1 -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 10 --hitcount 10 -j DROP
    firewall-cmd --permanent --direct --add-rule ipv6 filter INPUT 0 -p tcp --dport 22 -m state --state NEW -m recent --set
    firewall-cmd --permanent --direct --add-rule ipv6 filter INPUT 1 -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 10 --hitcount 10 -j DROP
    systemctl reload firewalld

    echo -e "${GREEN}[✓] Throttling configurado (max 10 conexiones/10 segundos)${NC}"
  fi
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  SSH HARDENING COMPLETADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  • Correcciones aplicadas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "  • Backup disponible en: ${GREEN}$BACKUP_DIR${NC}"
  fi

  echo -e "\n${YELLOW}PARA VERIFICAR:${NC}"
  echo -e "  sshd -t"
  echo -e "  ssh-audit localhost"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  SSH Hardening Complete - sshaudit.com${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  check_ssh_audit
  detect_distro

  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  if [ "$1" != "--fix" ] && [ "$1" != "-f" ]; then
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    show_ssh_audit_analysis
    show_current_config
    show_will_apply

    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
    exit 0
  fi

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    AUTO_FIX=true
    make_backup

    case "$rhel_version" in
    7)
      apply_hardening_rhel7
      FIXED=$((FIXED + 9))
      ;;
    8)
      apply_hardening_rhel8
      FIXED=$((FIXED + 7))
      configure_throttling
      FIXED=$((FIXED + 1))
      ;;
    9)
      apply_hardening_rhel9
      FIXED=$((FIXED + 8))
      configure_throttling
      FIXED=$((FIXED + 1))
      ;;
    10)
      apply_hardening_rhel10
      FIXED=$((FIXED + 8))
      configure_throttling
      FIXED=$((FIXED + 1))
      ;;
    esac

    echo -e "\n${BLUE}[*] Validando configuracion SSH...${NC}"
    if sshd -t &>/dev/null; then
      systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null
      echo -e "${GREEN}[✓] SSH reiniciado correctamente${NC}"
      show_summary
      echo -e "\n${BLUE}Verifique con: ssh-audit localhost${NC}"
    else
      echo -e "${RED}[!] Error en configuracion de SSH${NC}"
      sshd -t
      if [ -f "$BACKUP_DIR/sshd_config" ]; then
        cp "$BACKUP_DIR/sshd_config" "$SSHD_CONFIG"
        systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null
        echo -e "${YELLOW}[!] Backup restaurado${NC}"
      fi
      exit 1
    fi
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
