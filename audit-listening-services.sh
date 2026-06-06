#!/bin/bash

# ==============================================
# Script: audit-listening-services.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Audita servicios en escucha y sugiere acciones
#              CIS 2.4 - Ensure nonessential services are removed or masked
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================
# BASE DE DATOS DE SERVICIOS CONOCIDOS
# ==============================================

get_service_info() {
  local port=$1

  case "$port" in
  21) echo "vsftpd|vsftpd|eliminar|Servidor FTP (inseguro, usar SFTP)" ;;
  22) echo "sshd|openssh-server|mantener|SSH - necesario para administracion remota" ;;
  23) echo "telnet|telnet-server|eliminar|Telnet (inseguro, usar SSH)" ;;
  25) echo "postfix|postfix|configurar-local|Servidor de correo SMTP" ;;
  53) echo "named|bind|eliminar|Servidor DNS (si no es servidor DNS)" ;;
  80) echo "httpd|httpd|eliminar|Servidor web HTTP (si no es servidor web)" ;;
  110) echo "dovecot|dovecot|eliminar|Servidor POP3 (correo)" ;;
  111) echo "rpcbind|rpcbind|eliminar|RPC bind (necesario solo para NFS)" ;;
  139) echo "smb|samba|eliminar|Samba (comparticion archivos Windows)" ;;
  143) echo "dovecot|dovecot|eliminar|Servidor IMAP (correo)" ;;
  199) echo "snmpd|net-snmp|eliminar|SNMP (si no se usa monitoreo)" ;;
  389) echo "slapd|openldap-servers|eliminar|Servidor LDAP" ;;
  443) echo "httpd|httpd|eliminar|Servidor web HTTPS (si no es servidor web)" ;;
  445) echo "smb|samba|eliminar|Samba (comparticion archivos Windows)" ;;
  465) echo "postfix|postfix|configurar-local|SMTP con SSL" ;;
  514) echo "rsyslog|rsyslog|mantener|Syslog (logging del sistema)" ;;
  587) echo "postfix|postfix|configurar-local|SMTP" ;;
  631) echo "cups|cups|eliminar|Servidor de impresion" ;;
  993) echo "dovecot|dovecot|eliminar|IMAP con SSL (correo)" ;;
  995) echo "dovecot|dovecot|eliminar|POP3 con SSL (correo)" ;;
  1433) echo "mssql|mssql-server|eliminar|SQL Server" ;;
  2049) echo "nfs|nfs-utils|eliminar|NFS (comparticion archivos Unix)" ;;
  3000) echo "grafana-server|grafana|monitoreo|Grafana (monitoreo)" ;;
  3128) echo "squid|squid|eliminar|Proxy HTTP" ;;
  3306) echo "mysqld|MariaDB-server|eliminar|MySQL/MariaDB" ;;
  5432) echo "postgresql|postgresql-server|eliminar|PostgreSQL" ;;
  5665) echo "icinga2|icinga2|monitoreo|Icinga2 (monitoreo)" ;;
  5666) echo "nrpe|nrpe|monitoreo|NRPE (monitoreo Nagios)" ;;
  5667) echo "nsca|nsca|monitoreo|NSCA (monitoreo Nagios)" ;;
  6379) echo "redis|redis|eliminar|Redis" ;;
  8080) echo "tomcat|tomcat|eliminar|Tomcat" ;;
  8086) echo "influxdb|influxdb|monitoreo|InfluxDB (series temporales)" ;;
  8088) echo "influxdb|influxdb|monitoreo|InfluxDB (cluster)" ;;
  8443) echo "tomcat|tomcat|eliminar|Tomcat SSL" ;;
  9000) echo "php-fpm|php-fpm|eliminar|PHP-FPM" ;;
  27017) echo "mongod|mongodb-org|eliminar|MongoDB" ;;
  *) echo "desconocido|desconocido|revisar|Servicio no identificado" ;;
  esac
}

# ==============================================
# MOSTRAR CABECERA
# ==============================================
show_header() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Auditoria de Servicios en Escucha${NC}"
  echo -e "${GREEN}  CIS 2.4 - Nonessential Services${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo ""
}

# ==============================================
# EXTRAER PUERTO DE LA COLUMNA 4 (formato: 127.0.0.1:8088 o *:80)
# ==============================================
extract_port() {
  local addr_port="$1"
  echo "$addr_port" | awk -F: '{print $NF}'
}

# ==============================================
# EXTRAER NOMBRE DEL PROGRAMA DE LA COLUMNA 6
# ==============================================
extract_program() {
  local users="$1"
  # Extrae el nombre del programa entre comillas dobles
  if [[ "$users" =~ users:\(\(\"([^\"]+)\" ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "desconocido"
  fi
}

# ==============================================
# AUDITAR PUERTOS LISTEN USANDO SS
# ==============================================
audit_listening_ports() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}  PUERTOS EN ESCUCHA (LISTEN)${NC}"
  echo -e "${BLUE}========================================${NC}\n"

  printf "${YELLOW}%-8s %-20s %-25s %-15s %s${NC}\n" "PUERTO" "SERVICIO" "PAQUETE" "ACCION" "DESCRIPCION"
  echo -e "${BLUE}----------------------------------------------------------------------------------------------${NC}"

  ss -tlnp 2>/dev/null | grep LISTEN | while read line; do
    # La columna 4 tiene la direccion:puerto
    addr_port=$(echo "$line" | awk '{print $4}')
    port=$(extract_port "$addr_port")

    # La columna 6 tiene los usuarios y programas
    users_info=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | tr -d '\n')
    program=$(extract_program "$users_info")

    # Saltar si no hay puerto valido
    [ -z "$port" ] && continue

    # Obtener informacion del servicio
    IFS='|' read -r service pkg action desc <<<"$(get_service_info "$port")"

    # Si no se identifico por puerto, usar el programa detectado
    if [ "$service" = "desconocido" ]; then
      service="$program"
      pkg="desconocido"
    fi

    # Color segun accion
    case $action in
    eliminar)
      color="$RED"
      accion_sugerida="ELIMINAR"
      ;;
    configurar-local)
      color="$YELLOW"
      accion_sugerida="CONFIGURAR LOCAL"
      ;;
    mantener)
      color="$GREEN"
      accion_sugerida="MANTENER"
      ;;
    monitoreo)
      color="$GREEN"
      accion_sugerida="MONITOREO"
      ;;
    *)
      color="$YELLOW"
      accion_sugerida="REVISAR"
      ;;
    esac

    printf "${color}%-8s %-20s %-25s %-15s %s${NC}\n" \
      "$port" "${service:0:20}" "${pkg:0:25}" "$accion_sugerida" "${desc:0:50}"
  done
}

# ==============================================
# GENERAR COMANDOS SUGERIDOS
# ==============================================
generate_commands() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}  COMANDOS SUGERIDOS${NC}"
  echo -e "${BLUE}========================================${NC}\n"

  ss -tlnp 2>/dev/null | grep LISTEN | while read line; do
    addr_port=$(echo "$line" | awk '{print $4}')
    port=$(extract_port "$addr_port")

    [ -z "$port" ] && continue

    IFS='|' read -r service pkg action desc <<<"$(get_service_info "$port")"

    if [ "$action" = "eliminar" ] && [ "$pkg" != "desconocido" ]; then
      echo -e "${YELLOW}yum remove $pkg -y  # $desc${NC}"
    elif [ "$action" = "configurar-local" ] && [ "$pkg" = "postfix" ]; then
      echo -e "${YELLOW}sed -i 's/^inet_interfaces =.*/inet_interfaces = localhost/' /etc/postfix/main.cf && systemctl restart postfix  # $desc${NC}"
    fi
  done | sort -u
}

# ==============================================
# MOSTRAR RESULTADO FINAL
# ==============================================
show_summary() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  RESUMEN DE LA AUDITORIA${NC}"
  echo -e "${GREEN}============================================${NC}"

  local open_ports=$(ss -tlnp 2>/dev/null | grep LISTEN | wc -l)

  echo -e "\n${YELLOW}Puertos abiertos (escuchando): $open_ports${NC}"
  echo -e "\n${GREEN}[✓] Auditoria completada${NC}"
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  show_header
  audit_listening_ports
  generate_commands
  show_summary
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
