#!/usr/bin/env bash
# Diagnóstico de solo lectura de frontends y rulesets de firewall.

firewall_frontend_backend() {
  local frontend="$1" version=""
  command -v "$frontend" >/dev/null 2>&1 || { printf '%s\n' no_disponible; return 0; }
  version="$("$frontend" -V 2>/dev/null || true)"
  case "$version" in
    *"(nf_tables)"*) printf '%s\n' nf_tables ;;
    *"(legacy)"*) printf '%s\n' legacy ;;
    *) printf '%s\n' no_identificado ;;
  esac
}

# Inspecciona los volcados seleccionados y legacy, tanto IPv4 como IPv6.
firewall_has_imunify360_rules() {
  local save_cmd
  for save_cmd in iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
    command -v "$save_cmd" >/dev/null 2>&1 || continue
    if "$save_cmd" 2>/dev/null | grep -Eiq imunify360; then
      return 0
    fi
  done
  return 1
}

firewall_print_backend_diagnostics() {
  local frontend save_cmd backend version output rc rule_count
  echo "  Frontends iptables:"
  for frontend in iptables ip6tables; do
    if command -v "$frontend" >/dev/null 2>&1; then
      backend="$(firewall_frontend_backend "$frontend")"
      version="$("$frontend" -V 2>/dev/null || echo 'versión no disponible')"
      printf '    %s: backend=%s; %s\n' "$frontend" "$backend" "$version"
    else
      printf '    %s: no disponible\n' "$frontend"
    fi
  done

  echo "  Volcados de reglas disponibles:"
  for save_cmd in iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
    if ! command -v "$save_cmd" >/dev/null 2>&1; then
      printf '    %s: NO DISPONIBLE (no se puede verificar este ruleset con la herramienta instalada)\n' "$save_cmd"
      continue
    fi
    rc=0
    output="$("$save_cmd" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      rule_count="$(printf '%s\n' "$output" | grep -c '^-A ' || true)"
      printf '    %s: accesible; reglas=%s\n' "$save_cmd" "$rule_count"
      if printf '%s\n' "$output" | grep -Eiq imunify360; then
        printf '      [INFO] Hay referencias a Imunify360 en este ruleset.\n'
      fi
    else
      printf '    %s: no se pudo consultar las reglas (rc=%s); resultado indeterminado\n' "$save_cmd" "$rc"
    fi
  done
}


# Diagnóstico de gestores y backends: comandos de consulta, nunca de aplicación.
firewall_service_state() {
  local name="$1" result=""
  if command -v systemctl >/dev/null 2>&1; then
    result="$(systemctl is-active "$name" 2>/dev/null || true)"
    case "$result" in active) printf '%s\n' activo; return 0 ;; inactive|failed|deactivating|activating|unknown) printf '%s\n' inactivo; return 0 ;; esac
  fi
  if command -v service >/dev/null 2>&1; then
    result="$(service "$name" status 2>&1 || true)"
    if printf '%s\n' "$result" | grep -Eiq 'running|active|started'; then printf '%s\n' activo; return 0; fi
    if printf '%s\n' "$result" | grep -Eiq 'stopped|not running|inactive|dead'; then printf '%s\n' inactivo; return 0; fi
  fi
  printf '%s\n' indeterminado
}

firewall_report_detected() {
  local out rc state rules_count hooks backend save_cmd service_state
  local csf_status=no_detectado shorewall_status=no_detectado firewalld_status=no_detectado nft_status=no_detectado imunify_status=no_detectado

  echo "### INVENTARIO DE FIREWALL (solo lectura) ###"

  if command -v csf >/dev/null 2>&1; then
    out="$(csf -l 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then csf_status="instalado; csf -l consultable"; else csf_status="instalado; reglas no verificables (rc=$rc)"; fi
  fi
  echo "CSF: $csf_status"

  if command -v shorewall >/dev/null 2>&1; then
    out="$(shorewall status 2>&1 || true)"
    if printf '%s\n' "$out" | grep -Eiq 'stopped|not running|inactive|is down'; then shorewall_status="instalado; inactivo"
    elif printf '%s\n' "$out" | grep -Eiq 'running|started|active'; then shorewall_status="instalado; activo"
    else service_state="$(firewall_service_state shorewall)"; shorewall_status="instalado; estado=$service_state"; fi
  fi
  echo "Shorewall: $shorewall_status"

  if command -v firewall-cmd >/dev/null 2>&1; then
    state="$(firewall-cmd --state 2>/dev/null || true)"
    if [ "$state" = running ]; then firewalld_status="herramienta presente; activo"
    else firewalld_status="herramienta presente; estado no activo/no verificable"; fi
  else
    service_state="$(firewall_service_state firewalld)"
    if [ "$service_state" != indeterminado ]; then firewalld_status="servicio $service_state"; fi
  fi
  echo "firewalld: $firewalld_status"

  if command -v nft >/dev/null 2>&1; then
    out="$(nft list ruleset 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ]; then
      hooks="$(printf '%s\n' "$out" | grep -Ec 'hook[[:space:]]+input' || true)"
      rules_count="$(printf '%s\n' "$out" | grep -Ec '^[[:space:]]*(accept|drop|reject|jump|goto|tcp dport|udp dport|ip |ip6 )' || true)"
      nft_status="herramienta presente; hooks INPUT=$hooks; reglas relevantes visibles=$rules_count"
    else nft_status="herramienta presente; ruleset no consultable"; fi
  fi
  echo "nftables: $nft_status"

  if firewall_has_imunify360_rules; then imunify_status="reglas/cadenas de Imunify360 detectadas"; fi
  echo "Imunify360: $imunify_status"

  firewall_print_backend_diagnostics
  echo "[INFO] El inventario identifica gestores/herramientas; la decisión de acceso se estima desde los rulesets legibles y puede quedar indeterminada si las reglas son complejas."
  echo "[INFO] Solo lectura: no se ejecutan comandos de bloqueo, reinicio, recarga ni escritura de reglas."
}
