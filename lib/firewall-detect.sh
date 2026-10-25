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
    command -v "$save_cmd" >/dev/null 2>&1 || continue
    rc=0
    output="$("$save_cmd" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 0 ]; then
      rule_count="$(printf '%s\n' "$output" | grep -c '^-A ' || true)"
      printf '    %s: accesible; reglas=%s\n' "$save_cmd" "$rule_count"
      if printf '%s\n' "$output" | grep -Eiq imunify360; then
        printf '      [INFO] Hay referencias a Imunify360 en este ruleset.\n'
      fi
    else
      printf '    %s: existe pero no pudo consultar las reglas (rc=%s)\n' "$save_cmd" "$rc"
    fi
  done
}
