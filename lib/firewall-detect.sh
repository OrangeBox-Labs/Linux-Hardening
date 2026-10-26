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

firewall_add_active_manager() {
  local name="$1"
  if [ -z "$FIREWALL_ACTIVE_MANAGERS" ]; then
    FIREWALL_ACTIVE_MANAGERS="$name"
  else
    FIREWALL_ACTIVE_MANAGERS="$FIREWALL_ACTIVE_MANAGERS + $name"
  fi
  FIREWALL_ACTIVE_MANAGER_COUNT=$((FIREWALL_ACTIVE_MANAGER_COUNT+1))
}

# Inventario conservador de solo lectura. Un binario instalado por sí solo no
# demuestra que administre las reglas cargadas actualmente.
firewall_report_detected() {
  local out rc state service_state backend rules_count hooks ruleset_present=false
  local csf_status=no_detectado shorewall_status=no_detectado firewalld_status=no_detectado
  local nft_status=no_detectado iptables_services_status=no_detectado ufw_status=no_detectado
  local imunify_status=no_detectado

  FIREWALL_WARNINGS=0
  FIREWALL_ACTIVE_MANAGERS=""
  FIREWALL_ACTIVE_MANAGER_COUNT=0

  echo "### INVENTARIO DE FIREWALL (solo lectura) ###"

  # CSF has no dedicated firewall daemon; require visible CSF chains in its
  # read-only listing before claiming that its rules are active.
  if command -v csf >/dev/null 2>&1; then
    rc=0
    out="$(csf -l 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eiq '(^|[^[:alnum:]_])(LOCALINPUT|ALLOWIN|DENYIN|LOGDROPIN|LOCALOUTPUT|DENYOUT|CC_ALLOW|CC_DENY)([^[:alnum:]_]|$)|CSF'; then
      csf_status="instalado; actividad confirmada por cadenas/listado CSF"
      firewall_add_active_manager "CSF"
    elif [ "$rc" -eq 0 ]; then
      csf_status="instalado; csf -l funciona, reglas CSF activas no confirmadas"
    else
      csf_status="instalado; listado no verificable (rc=$rc)"
    fi
  fi
  echo "CSF: $csf_status"

  if command -v shorewall >/dev/null 2>&1; then
    rc=0
    out="$(shorewall status 2>&1)" || rc=$?
    if printf '%s\n' "$out" | grep -Eiq 'not running|stopped|inactive|is down'; then
      shorewall_status="instalado; inactivo"
    elif printf '%s\n' "$out" | grep -Eiq 'running|started|active|is up'; then
      shorewall_status="instalado; activo"
      firewall_add_active_manager "Shorewall"
    else
      service_state="$(firewall_service_state shorewall)"
      if [ "$service_state" = activo ]; then
        shorewall_status="instalado; servicio activo"
        firewall_add_active_manager "Shorewall"
      else
        shorewall_status="instalado; actividad no confirmada (rc=$rc, servicio=$service_state)"
      fi
    fi
  else
    service_state="$(firewall_service_state shorewall)"
    if [ "$service_state" = activo ]; then
      shorewall_status="servicio activo, comando shorewall no disponible"
      firewall_add_active_manager "Shorewall"
    fi
  fi
  echo "Shorewall: $shorewall_status"

  state=""
  if command -v firewall-cmd >/dev/null 2>&1; then
    state="$(firewall-cmd --state 2>/dev/null || true)"
  fi
  service_state="$(firewall_service_state firewalld)"
  if [ "$state" = running ] || [ "$service_state" = activo ]; then
    firewalld_status="activo"
    firewall_add_active_manager "firewalld"
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewalld_status="herramienta presente; servicio no activo/no confirmado"
  elif [ "$service_state" = inactivo ]; then
    firewalld_status="inactivo/no detectado"
  fi
  echo "firewalld: $firewalld_status"

  if command -v nft >/dev/null 2>&1; then
    rc=0
    out="$(nft list ruleset 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      hooks="$(printf '%s\n' "$out" | grep -Ec 'hook[[:space:]]+input' || true)"
      rules_count="$(printf '%s\n' "$out" | grep -Ec '^[[:space:]]*(accept|drop|reject|jump|goto|tcp dport|udp dport|ip |ip6 )' || true)"
      nft_status="ruleset consultable; hooks INPUT=$hooks; reglas relevantes visibles=$rules_count"
      if printf '%s\n' "$out" | grep -Eiq 'hook[[:space:]]+input|chain[[:space:]]+(INPUT|input)[[:space:]]*\{'; then
        ruleset_present=true
      fi
    else
      nft_status="herramienta presente; ruleset no consultable"
    fi
  fi
  service_state="$(firewall_service_state nftables)"
  if [ "$service_state" = activo ]; then
    nft_status="$nft_status; servicio nftables activo"
    firewall_add_active_manager "servicio nftables"
  fi
  echo "nftables: $nft_status"

  service_state="$(firewall_service_state iptables)"
  if [ "$service_state" != activo ]; then
    service_state="$(firewall_service_state ip6tables)"
  fi
  if [ "$service_state" = activo ]; then
    iptables_services_status="servicio iptables/ip6tables activo"
    firewall_add_active_manager "iptables-services"
  else
    iptables_services_status="servicio no activo/no confirmado"
  fi
  echo "iptables-services: $iptables_services_status"

  if command -v ufw >/dev/null 2>&1; then
    rc=0
    out="$(ufw status 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eiq 'Status:[[:space:]]*active'; then
      ufw_status="activo"
      firewall_add_active_manager "UFW"
    elif [ "$rc" -eq 0 ]; then
      ufw_status="instalado; inactivo"
    else
      ufw_status="instalado; estado no verificable"
    fi
  fi
  echo "UFW: $ufw_status"

  if firewall_has_imunify360_rules; then
    imunify_status="reglas/cadenas de integración detectadas"
  fi
  echo "Imunify360: $imunify_status"

  # Use loaded INPUT chains as evidence of a filtering ruleset, not as proof
  # that a particular daemon owns it. Do not conflate iptables-nft with nft's
  # own service: on modern RHEL both frontends may describe the same kernel.
  for save_cmd in iptables-save iptables-legacy-save ip6tables-save ip6tables-legacy-save; do
    if command -v "$save_cmd" >/dev/null 2>&1; then
      rc=0
      out="$("$save_cmd" 2>/dev/null)" || rc=$?
      if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eq '^-A INPUT([[:space:]]|$)|^:INPUT[[:space:]]'; then
        ruleset_present=true
      fi
    fi
  done

  backend="$(firewall_frontend_backend iptables)"
  case "$backend" in
    nf_tables) echo "Backend iptables observado: nf_tables (iptables-nft)" ;;
    legacy) echo "Backend iptables observado: legacy (iptables-legacy)" ;;
    no_disponible) echo "Backend iptables observado: no disponible" ;;
    *) echo "Backend iptables observado: no identificado" ;;
  esac

  if [ "$FIREWALL_ACTIVE_MANAGER_COUNT" -eq 1 ]; then
    printf '[OK] Gestor activo detectado: %s. La detección identifica actividad, no modifica ni valida por sí sola cada regla.\n' "$FIREWALL_ACTIVE_MANAGERS"
  elif [ "$FIREWALL_ACTIVE_MANAGER_COUNT" -gt 1 ]; then
    printf '[WARN] Gestores activos ambiguos: %s. Revisar coexistencia y orden de hooks; no se elegirá ni cambiará ninguno.\n' "$FIREWALL_ACTIVE_MANAGERS"
    FIREWALL_WARNINGS=$((FIREWALL_WARNINGS+1))
  elif [ "$ruleset_present" = true ]; then
    echo "[WARN] Hay un ruleset de entrada visible, pero no se confirmó qué gestor lo administra (puede ser configuración manual o una integración externa)."
    FIREWALL_WARNINGS=$((FIREWALL_WARNINGS+1))
  else
    echo "[WARN] No se pudo confirmar un gestor activo ni un ruleset INPUT verificable."
    FIREWALL_WARNINGS=$((FIREWALL_WARNINGS+1))
  fi

  firewall_print_backend_diagnostics
  echo "[INFO] El contraste de listeners se hace aparte, usando solo reglas consultables; reglas complejas pueden producir estado indeterminado."
  echo "[INFO] Solo lectura: no se ejecutan comandos para bloquear, editar, habilitar, detener, reiniciar ni recargar firewalls."
}
