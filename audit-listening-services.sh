#!/usr/bin/env bash
# OrangeBox Linux Hardening - inventario no destructivo de sockets en escucha.
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

classify_bind_address() {
  case "$1" in
    127.*:*|localhost:*|"[::1]:"*|"::1:"*) printf '%s\n' LOOPBACK ;;
    0.0.0.0:*|"[::]:"*|":::"*|\*:*) printf '%s\n' TODAS_INTERFACES ;;
    *) printf '%s\n' IP_ESPECIFICA ;;
  esac
}

# El proceso observado tiene prioridad sobre el número de puerto.
classify_listening_process() {
  local process="$1" port="$2"
  case "$process" in
    sshd) printf '%s\n' ADMINISTRACION ;;
    pure-ftpd|vsftpd|proftpd) printf '%s\n' FTP ;;
    pdns_server|named|dnsmasq|unbound|systemd-resolved) printf '%s\n' DNS ;;
    rpcbind) printf '%s\n' RPC_NFS ;;
    httpd|nginx|apache2|lshttpd|openlitespeed) printf '%s\n' WEB ;;
    postfix|dovecot|exim|sendmail) printf '%s\n' CORREO ;;
    master)
      case "$port" in 25|465|587) printf '%s\n' CORREO ;; *) printf '%s\n' NO_CLASIFICADO ;; esac
      ;;
    mariadbd|mysqld|mongod|postgres|postgresql|redis-server|memcached) printf '%s\n' BASE_DATOS ;;
    zabbix_agent2|zabbix_agentd|node_exporter|fluent-bit|otelcol|otelopscol|opentelemetry-collector|prometheus|grafana-server|dcgm-exporter)
      printf '%s\n' MONITOREO ;;
    *) printf '%s\n' NO_CLASIFICADO ;;
  esac
}

# Entrada: una línea de "ss -H -lntup". Salida TSV para pruebas reproducibles.
parse_ss_socket_line() {
  local line="$1" protocol state recvq sendq local_addr peer rest port process category scope
  IFS=' ' read -r protocol state recvq sendq local_addr peer rest <<< "$line"
  [ -n "$protocol" ] && [ -n "$local_addr" ] || return 1
  [[ "$local_addr" == *:* ]] || return 1
  port="$(printf '%s\n' "$local_addr" | awk -F: '{print $NF}')"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1

  process="$(printf '%s\n' "$line" | sed -n 's/.*users:(("//;t got;b;:got s/".*//;p')"
  [ -n "$process" ] || process=desconocido
  category="$(classify_listening_process "$process" "$port")"
  scope="$(classify_bind_address "$local_addr")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$protocol" "$state" "$port" "$local_addr" "$process" "$category" "$scope"
}

audit_listening_ports() {
  local socket_output line parsed protocol state port local_addr process category scope note proto_upper
  local count=0 skipped=0

  command -v ss >/dev/null 2>&1 || { echo "[ERROR] No se encontró ss." >&2; return 1; }
  if ! socket_output="$(ss -H -lntup 2>&1)"; then
    echo "[ERROR] ss no pudo enumerar sockets:" >&2
    printf '%s\n' "$socket_output" >&2
    return 1
  fi

  printf '%-5s %-8s %-7s %-30s %-24s %-17s %-18s %s\n' \
    PROTO ESTADO PUERTO "DIRECCION LOCAL" PROCESO CLASE BIND OBSERVACION
  printf '%s\n' "---------------------------------------------------------------------------------------------------------------"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! parsed="$(parse_ss_socket_line "$line")"; then
      skipped=$((skipped + 1))
      continue
    fi
    IFS=$'\t' read -r protocol state port local_addr process category scope <<< "$parsed"
    proto_upper="$(printf '%s' "$protocol" | tr '[:lower:]' '[:upper:]')"
    case "$scope" in
      LOOPBACK) note="Solo loopback" ;;
      TODAS_INTERFACES) note="Revisar ACL/firewall" ;;
      *) note="Revisar red/ACL" ;;
    esac
    [ "$category" != NO_CLASIFICADO ] || note="$note; validar propósito"
    printf '%-5s %-8s %-7s %-30.30s %-24.24s %-17s %-18s %s\n' \
      "$proto_upper" "$state" "$port" "$local_addr" "$process" "$category" "$scope" "$note"
    count=$((count + 1))
  done <<< "$socket_output"

  echo
  echo "Sockets procesados: $count"
  [ "$skipped" -eq 0 ] || echo "Líneas omitidas por formato no reconocido: $skipped"
  echo "BIND wildcard no demuestra accesibilidad desde Internet: deben revisarse CSF/Imunify360,"
  echo "todos los backends de firewall, las rutas y las reglas externas."
  echo "Los procesos NO_CLASIFICADO quedan para revisión; no se recomiendan eliminaciones de paquetes."
}

main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --check) ;;
      -h|--help) echo "Uso: $0 [--check]"; echo "Auditoría TCP/UDP de solo lectura."; return 0 ;;
      *) echo "Opción desconocida: $arg" >&2; return 2 ;;
    esac
  done
  [ "$EUID" -eq 0 ] || { echo "[ERROR] Ejecuta como root para identificar los procesos." >&2; return 1; }
  echo -e "$GREEN============================================================$NC"
  echo -e "$GREEN OrangeBox - Auditoría de sockets en escucha (solo lectura)$NC"
  echo -e "$GREEN============================================================$NC"
  audit_listening_ports || return $?
  echo -e "$GREEN Auditoría completada. No se aplicaron cambios.$NC"
  echo "Para diagnosticar gestores/backends de firewall: ./network-hardening.sh --check"
}

# Permite cargar las funciones en pruebas unitarias sin lanzar la auditoría.
if [ "$0" = "$BASH_SOURCE" ]; then
  main "$@"
fi
