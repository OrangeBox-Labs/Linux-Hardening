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
    systemd)
      # systemd puede ser propietario de un socket activable; no inferir
      # qué servicio está detrás sin consultar su unidad.
      case "$port" in 111) printf '%s\n' ACTIVACION_SOCKET ;; *) printf '%s\n' NO_CLASIFICADO ;; esac
      ;;
    cpsrvd*|cpdavd*) printf '%s\n' CPANEL ;;
    cphulkd*|cPhulkd*) printf '%s\n' SEGURIDAD_CPANEL ;;
    imunify360-webs|imunify-agent-p|imunify-residen|ie-dec-node|ie-quarantine)
      printf '%s\n' SEGURIDAD ;;
    ossec-remoted) printf '%s\n' SEGURIDAD_MONITOREO ;;
    chronyd) printf '%s\n' SINCRONIZACION_HORARIA ;;
    spamd*) printf '%s\n' FILTRO_CORREO ;;
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

# Entrada: una línea de "netstat -plntu" en sistemas sin un formato ss compatible.
# Admite el formato SysV/EL6 de net-tools y normaliza tcp6/udp6.
parse_netstat_socket_line() {
  local line="$1" protocol state local_addr pid_program port process category scope
  local -a fields=()
  read -r -a fields <<< "$line"
  [ "${#fields[@]}" -ge 6 ] || return 1
  case "${fields[0]}" in
    tcp|tcp6)
      protocol=tcp
      [ "${#fields[@]}" -ge 7 ] || return 1
      state="${fields[5]}"
      [ "$state" = LISTEN ] || return 1
      pid_program="${fields[6]}"
      ;;
    udp|udp6)
      protocol=udp
      state=UNCONN
      pid_program="${fields[5]}"
      ;;
    *) return 1 ;;
  esac
  local_addr="${fields[3]}"
  [[ "$local_addr" == *:* ]] || return 1
  port="${local_addr##*:}"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  process=desconocido
  if [[ "$pid_program" == */* ]]; then
    process="${pid_program#*/}"
    [ -n "$process" ] || process=desconocido
  fi
  category="$(classify_listening_process "$process" "$port")"
  scope="$(classify_bind_address "$local_addr")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$protocol" "$state" "$port" "$local_addr" "$process" "$category" "$scope"
}

audit_listening_ports() {
  local socket_output="" line parsed protocol state port local_addr process category scope note proto_upper first_token
  local count=0 skipped=0 ss_ok=false netstat_ok=false
  local -a rows=()

  if command -v ss >/dev/null 2>&1; then
    if socket_output="$(ss -H -lntup 2>/dev/null)"; then
      ss_ok=true
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        if parsed="$(parse_ss_socket_line "$line")"; then
          rows+=("$parsed")
          count=$((count + 1))
        else
          first_token="${line%%[[:space:]]*}"
          case "$first_token" in tcp|tcp6|udp|udp6|LISTEN|UNCONN) skipped=$((skipped + 1)) ;; esac
        fi
      done <<< "$socket_output"
    fi
  fi

  # ss puede existir y aun así usar un formato no soportado por este parser.
  # Si hay líneas de socket no interpretadas, usa netstat cuando esté disponible.
  if [ "$ss_ok" != true ] || [ "$skipped" -gt 0 ]; then
    if command -v netstat >/dev/null 2>&1; then
      echo "[INFO] ss no produjo un inventario interpretable completo; intentando netstat."
      if socket_output="$(netstat -plntu 2>/dev/null)"; then
        netstat_ok=true
        rows=()
        count=0
        skipped=0
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          if parsed="$(parse_netstat_socket_line "$line")"; then
            rows+=("$parsed")
            count=$((count + 1))
          else
            first_token="${line%%[[:space:]]*}"
            case "$first_token" in tcp|tcp6|udp|udp6) skipped=$((skipped + 1)) ;; esac
          fi
        done <<< "$socket_output"
      fi
    fi
  fi

  printf '%-5s %-8s %-7s %-30s %-24s %-17s %-18s %s\n' \
    PROTO ESTADO PUERTO "DIRECCION LOCAL" PROCESO CLASE BIND OBSERVACION
  printf '%s\n' "---------------------------------------------------------------------------------------------------------------"
  for parsed in "${rows[@]}"; do
    IFS=$'\t' read -r protocol state port local_addr process category scope <<< "$parsed"
    proto_upper="$(printf '%s' "$protocol" | tr '[:lower:]' '[:upper:]')"
    case "$scope" in
      LOOPBACK) note="Solo loopback" ;;
      TODAS_INTERFACES) note="Revisar ACL/firewall" ;;
      *) note="Revisar red/ACL" ;;
    esac
    case "$category" in
      ACTIVACION_SOCKET) note="$note; identificar unidad systemd" ;;
      NO_CLASIFICADO) note="$note; validar propósito" ;;
    esac
    printf '%-5s %-8s %-7s %-30.30s %-24.24s %-17s %-18s %s\n' \
      "$proto_upper" "$state" "$port" "$local_addr" "$process" "$category" "$scope" "$note"
  done

  echo
  echo "Sockets procesados: $count"
  [ "$netstat_ok" = true ] && echo "Fuente: netstat (compatibilidad legacy)"
  if [ "$skipped" -gt 0 ]; then
    echo "[WARN] Líneas de sockets no interpretadas: $skipped; el inventario es incompleto."
  fi
  echo "BIND wildcard no demuestra accesibilidad desde Internet: deben revisarse CSF/Imunify360,"
  echo "todos los backends de firewall, las rutas y las reglas externas."
  echo "Los procesos NO_CLASIFICADO quedan para revisión; no se recomiendan eliminaciones de paquetes."

  if [ "$skipped" -gt 0 ] || { [ "$count" -eq 0 ] && [ "$ss_ok" != true ] && [ "$netstat_ok" != true ]; }; then
    return 2
  fi
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
