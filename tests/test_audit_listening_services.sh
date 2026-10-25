#!/usr/bin/env bash
# Pruebas unitarias aisladas: no consultan ni modifican el host.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
# shellcheck source=../audit-listening-services.sh
source "$ROOT_DIR/audit-listening-services.sh"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

assert_socket() {
  local fixture="$1" ep="$2" eport="$3" eaddr="$4" eproc="$5" eclass="$6" escope="$7"
  local parsed protocol state port address process category scope
  parsed="$(parse_ss_socket_line "$fixture")" || fail "no se pudo parsear: $fixture"
  IFS=$'\t' read -r protocol state port address process category scope <<< "$parsed"
  [ "$protocol" = "$ep" ] || fail "protocolo esperado=$ep actual=$protocol"
  [ "$port" = "$eport" ] || fail "puerto esperado=$eport actual=$port"
  [ "$address" = "$eaddr" ] || fail "dirección esperada=$eaddr actual=$address"
  [ "$process" = "$eproc" ] || fail "proceso esperado=$eproc actual=$process"
  [ "$category" = "$eclass" ] || fail "clase esperada=$eclass actual=$category"
  [ "$scope" = "$escope" ] || fail "bind esperado=$escope actual=$scope"
}

assert_socket 'tcp LISTEN 0 128 0.0.0.0:21 0.0.0.0:* users:(("pure-ftpd",pid=101,fd=4))' tcp 21 0.0.0.0:21 pure-ftpd FTP TODAS_INTERFACES
assert_socket 'tcp LISTEN 0 128 0.0.0.0:53 0.0.0.0:* users:(("pdns_server",pid=102,fd=5))' tcp 53 0.0.0.0:53 pdns_server DNS TODAS_INTERFACES
assert_socket 'tcp LISTEN 0 128 127.0.0.1:27217 0.0.0.0:* users:(("mongod",pid=103,fd=6))' tcp 27217 127.0.0.1:27217 mongod BASE_DATOS LOOPBACK
assert_socket 'tcp LISTEN 0 128 *:20202 *:* users:(("fluent-bit",pid=104,fd=7))' tcp 20202 '*:20202' fluent-bit MONITOREO TODAS_INTERFACES
assert_socket 'udp UNCONN 0 0 [::]:53 [::]:* users:(("pdns_server",pid=105,fd=8))' udp 53 '[::]:53' pdns_server DNS TODAS_INTERFACES
assert_socket 'tcp LISTEN 0 128 127.0.0.1:9100 0.0.0.0:* users:(("node_exporter",pid=106,fd=9))' tcp 9100 127.0.0.1:9100 node_exporter MONITOREO LOOPBACK

unknown="$(parse_ss_socket_line 'tcp LISTEN 0 32 0.0.0.0:45678 0.0.0.0:* users:(("custom-agent",pid=107,fd=10))')"
IFS=$'\t' read -r protocol state port address process category scope <<< "$unknown"
[ "$process" = custom-agent ] || fail "no se conservó proceso desconocido"
[ "$category" = NO_CLASIFICADO ] || fail "proceso desconocido clasificado incorrectamente"
if grep -qiE 'yum remove|dnf remove|ELIMINAR' "$ROOT_DIR/audit-listening-services.sh"; then
  fail "el auditor contiene sugerencias de eliminación de paquetes"
fi
pass "TCP/UDP, Pure-FTPd, PowerDNS, MongoDB, monitoreo, bind y procesos desconocidos"
