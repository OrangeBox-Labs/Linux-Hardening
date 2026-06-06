#!/bin/bash

# ==============================================
# Script: generate-iptables-rules.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Genera un script de reglas iptables interactivo
#              Detecta puertos en escucha y pregunta si permitirlos
#              SSH siempre permitido con proteccion anti-DoS
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

IPTABLES_SCRIPT="/root/iptables.sh"
IP6TABLES_SCRIPT="/root/ip6tables.sh"
ALLOWED_PORTS=()

# ==============================================
# DETECTAR PUERTOS EN ESCUCHA (EXCLUYENDO SSH)
# ==============================================
detect_listening_ports() {
  echo -e "\n${BLUE}[*] Detectando puertos en escucha en este servidor...${NC}"

  local ports=$(ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4}' | awk -F: '{print $NF}' | sort -n | uniq | grep -v "^22$")

  echo -e "\n${YELLOW}Puertos detectados (excluyendo SSH):${NC}"
  for port in $ports; do
    local service=$(ss -tlnp 2>/dev/null | grep ":$port" | head -1 | awk '{print $6}' | cut -d'"' -f2)
    [ -z "$service" ] && service="desconocido"
    echo -e "  ${GREEN}Port $port${NC} ($service)"
  done

  if [ -z "$ports" ]; then
    echo -e "${GREEN}[✓] No se detectaron puertos adicionales (solo SSH)${NC}"
    return 0
  fi

  echo -e "\n${YELLOW}¿Desea permitir todos estos puertos en el firewall? (s/N): ${NC}"
  read -r confirm_all

  if [[ "$confirm_all" =~ ^[Ss]$ ]]; then
    for port in $ports; do
      ALLOWED_PORTS+=("$port")
    done
    echo -e "${GREEN}[✓] Se permitiran todos los puertos detectados${NC}"
  else
    echo -e "\n${YELLOW}Ingrese los puertos que desea permitir (separados por espacio):${NC}"
    echo -e "  Ejemplo: 80 443 3306"
    read -r -a ALLOWED_PORTS
  fi
}

# ==============================================
# VERIFICAR SERVICIOS DE FIREWALL
# ==============================================
check_firewall_services() {
  echo -e "\n${BLUE}[*] Verificando servicios de firewall...${NC}"

  if ! rpm -q iptables-services &>/dev/null; then
    echo -e "${YELLOW}[!] iptables-services no instalado. Instalando...${NC}"
    yum install iptables-services -y 2>/dev/null || dnf install iptables-services -y 2>/dev/null
  else
    echo -e "${GREEN}[✓] iptables-services instalado${NC}"
  fi

  if rpm -q firewalld &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    echo -e "${YELLOW}[!] firewalld esta activo. Se recomienda deshabilitarlo para usar iptables.${NC}"
  fi

  if rpm -q nftables &>/dev/null && systemctl is-active --quiet nftables 2>/dev/null; then
    echo -e "${YELLOW}[!] nftables esta activo. Se recomienda deshabilitarlo para usar iptables.${NC}"
  fi

}

# ==============================================
# GENERAR SCRIPT DE IPTABLES
# ==============================================
generate_iptables_script() {
  echo -e "\n${BLUE}[*] Generando script de iptables en $IPTABLES_SCRIPT${NC}"

  cat >"$IPTABLES_SCRIPT" <<'EOF'
#!/bin/bash
# ==============================================
# Script de reglas iptables
# Generado automaticamente
# Fecha: $(date)
# ==============================================

# Limpiar reglas existentes
echo "[*] Limpiando reglas existentes..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F
iptables -Z

# Politicas por defecto
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# ==============================================
# CONNECTION TRACKING
# ==============================================
# Permitir conexiones establecidas y relacionadas
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# ==============================================
# PERMITIR LOOPBACK
# ==============================================
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ==============================================
# PERMITIR PING (ICMP)
# ==============================================
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# ==============================================
# PROTECCIONES ANTI-DDoS PARA SSH
# ==============================================
# Limitar conexiones SSH por IP (max 4 por minuto)
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -j ACCEPT

# Limitar conexiones SSH globales (max 10 por segundo)
iptables -A INPUT -p tcp --dport 22 -m limit --limit 10/second --limit-burst 20 -j ACCEPT

# ==============================================
# PROTECCIONES TCP BASICAS (Hardening)
# ==============================================

# 1. Proteccion SYN Flood
iptables -A INPUT -p tcp --syn -m limit --limit 20/second --limit-burst 50 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# 2. Proteccion contra paquetes invalidos
iptables -A INPUT -m state --state INVALID -j DROP

# 3. Proteccion contra fragmentacion
iptables -A INPUT -f -j DROP

# 4. Bloquear puertos comunes de ataques (eliminado porque la politica está en DROP)
#iptables -A INPUT -p tcp --dport 135 -j DROP
#iptables -A INPUT -p udp --dport 137:139 -j DROP
#iptables -A INPUT -p tcp --dport 445 -j DROP

# 5. Proteccion contra scans (limitar conexiones nuevas por IP)
iptables -A INPUT -m state --state NEW -m recent --set --name SCAN
iptables -A INPUT -m state --state NEW -m recent --update --seconds 60 --hitcount 10 --name SCAN -j DROP

# 6. Bloquear null packets
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# 7. Bloquear syn-flood packets
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# 8. Bloquear XMAS packets
iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP

EOF

  # Agregar puertos permitidos
  for port in "${ALLOWED_PORTS[@]}"; do
    cat >>"$IPTABLES_SCRIPT" <<EOF

# Puerto $port
iptables -A INPUT -p tcp --dport $port -m state --state NEW -j ACCEPT
EOF
  done

  # Agregar guardado
  cat >>"$IPTABLES_SCRIPT" <<'EOF'

# ==============================================
# LOGGING (opcional - descomentar para habilitar)
# ==============================================
# iptables -A INPUT -j LOG --log-prefix "IPTables-Dropped: " --log-level 4

# ==============================================
# GUARDAR REGLAS
# ==============================================
echo "[*] Guardando reglas..."
iptables-save > /etc/sysconfig/iptables
service iptables save 2>/dev/null || true

echo "[✓] Reglas iptables aplicadas y guardadas"
EOF

  chmod +x "$IPTABLES_SCRIPT"
  echo -e "${GREEN}[✓] Script generado: $IPTABLES_SCRIPT${NC}"
}

# ==============================================
# GENERAR SCRIPT DE IP6TABLES
# ==============================================
generate_ip6tables_script() {
  echo -e "\n${BLUE}[*] Generando script de ip6tables en $IP6TABLES_SCRIPT${NC}"

  cat >"$IP6TABLES_SCRIPT" <<'EOF'
#!/bin/bash
# ==============================================
# Script de reglas ip6tables (IPv6)
# Generado automaticamente
# Fecha: $(date)
# ==============================================

# Limpiar reglas existentes
echo "[*] Limpiando reglas existentes..."
ip6tables -F
ip6tables -X
ip6tables -t mangle -F
ip6tables -Z

# Politicas por defecto
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# ==============================================
# CONNECTION TRACKING
# ==============================================
ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# ==============================================
# PERMITIR LOOPBACK
# ==============================================
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

# ==============================================
# PERMITIR PING (ICMPv6)
# ==============================================
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-reply -j ACCEPT

# ==============================================
# ICMPv6 necesario para IPv6
# ==============================================
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type router-advertisement -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT

# ==============================================
# PROTECCIONES ANTI-DDoS PARA SSH
# ==============================================
# Limitar conexiones SSH por IP (max 4 por minuto)
ip6tables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
ip6tables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP
ip6tables -A INPUT -p tcp --dport 22 -m state --state NEW -j ACCEPT

# Limitar conexiones SSH globales (max 10 por segundo)
ip6tables -A INPUT -p tcp --dport 22 -m limit --limit 10/second --limit-burst 20 -j ACCEPT

# ==============================================
# PROTECCIONES TCP BASICAS (Hardening)
# ==============================================
ip6tables -A INPUT -p tcp --syn -m limit --limit 20/second --limit-burst 50 -j ACCEPT
ip6tables -A INPUT -p tcp --syn -j DROP
ip6tables -A INPUT -m state --state INVALID -j DROP
ip6tables -A INPUT -m state --state NEW -m recent --set --name SCAN
ip6tables -A INPUT -m state --state NEW -m recent --update --seconds 60 --hitcount 10 --name SCAN -j DROP

EOF

  # Agregar puertos permitidos en IPv6
  for port in "${ALLOWED_PORTS[@]}"; do
    cat >>"$IP6TABLES_SCRIPT" <<EOF

# Puerto $port
ip6tables -A INPUT -p tcp --dport $port -m state --state NEW -j ACCEPT
EOF
  done

  # Agregar guardado
  cat >>"$IP6TABLES_SCRIPT" <<'EOF'

# ==============================================
# GUARDAR REGLAS
# ==============================================
echo "[*] Guardando reglas..."
ip6tables-save > /etc/sysconfig/ip6tables
service ip6tables save 2>/dev/null || true

echo "[✓] Reglas ip6tables aplicadas y guardadas"
EOF

  chmod +x "$IP6TABLES_SCRIPT"
  echo -e "${GREEN}[✓] Script generado: $IP6TABLES_SCRIPT${NC}"
}

# ==============================================
# MOSTRAR RESUMEN
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  SCRIPT GENERADO${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}Script de iptables: ${GREEN}$IPTABLES_SCRIPT${NC}"
  echo -e "${YELLOW}Script de ip6tables: ${GREEN}$IP6TABLES_SCRIPT${NC}"

  if [ ${#ALLOWED_PORTS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Puertos permitidos:${NC}"
    for port in "${ALLOWED_PORTS[@]}"; do
      echo -e "  - TCP $port"
    done
  else
    echo -e "\n${GREEN}[✓] Solo SSH esta permitido${NC}"
  fi

  echo -e "\n${YELLOW}Para aplicar las reglas de firewall:${NC}"
  echo -e "  ${GREEN}sh $IPTABLES_SCRIPT${NC}"
  echo -e "  ${GREEN}sh $IP6TABLES_SCRIPT${NC}"
  echo -e "  ${GREEN}systemctl enable iptables ip6tables${NC}"

  echo -e "\n${YELLOW}Para deshabilitar firewalld/nftables (recomendado):${NC}"
  echo -e "  systemctl stop firewalld nftables"
  echo -e "  systemctl disable firewalld nftables"
  echo -e "  systemctl mask firewalld nftables"

  echo -e "\n${YELLOW}Para ver las reglas aplicadas:${NC}"
  echo -e "  iptables -L -n -v"
  echo -e "  ip6tables -L -n -v"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Generador de Scripts iptables${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  echo -e "${YELLOW}Este script generara un archivo con reglas iptables"
  echo -e "Detectara los puertos en escucha (excluyendo SSH) y preguntara cuales permitir."
  echo -e "SSH siempre estara permitido con protecciones anti-DDoS."
  echo -e "Solo se aplicaran las reglas cuando ejecute el script generado.${NC}\n"

  read -p "Presione Enter para continuar..."

  check_firewall_services
  detect_listening_ports
  generate_iptables_script
  generate_ip6tables_script
  show_summary

  echo -e "\n${GREEN}[✓] Proceso completado${NC}"
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
