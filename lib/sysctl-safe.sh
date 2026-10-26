#!/usr/bin/env bash
# Shared sysctl safety helpers for OrangeBox hardening scripts.
# Inventories active settings before changing them; conflicting settings require confirmation.

SYSCTL_SAFE_CHANGED=false

# Status colors follow the same semantic palette used by the main scripts.
# Resolve color variables at call time so this library works when sourced by
# either linux-hardening.sh, kernel-hardening.sh or network-hardening.sh.
sysctl_safe_log() {
  local level="$1"
  shift
  if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
    case "$level" in
      OK) OK_COUNT=$((${OK_COUNT:-0}+1)) ;;
      N/A) NOT_APPLICABLE_COUNT=$((${NOT_APPLICABLE_COUNT:-0}+1)) ;;
    esac
    case "$level" in INFO|CAMBIO\ PROPUESTO) return 0 ;; esac
  fi
  local color reset="${NC:-$'\033[0m'}"
  case "$level" in
    OK) color="${GREEN:-$'\033[0;32m'}" ;;
    ERROR) color="${RED:-$'\033[0;31m'}" ;;
    INFO|CAMBIO\ PROPUESTO|N/A) color="${BLUE:-$'\033[0;34m'}" ;;
    *) color="${YELLOW:-$'\033[0;33m'}" ;;
  esac
  printf '%b[SYSCTL][%s]%b %s\n' "$color" "$level" "$reset" "$*"
}

sysctl_safe_description() {
  case "$1" in
    fs.suid_dumpable) echo "Impide core dumps de programas privilegiados que podrían contener datos sensibles; puede limitar el análisis post-mortem." ;;
    kernel.dmesg_restrict) echo "Restringe el acceso no privilegiado a mensajes del kernel y reduce la exposición de información del sistema." ;;
    kernel.kptr_restrict) echo "Oculta direcciones de memoria del kernel, dificultando ataques que dependen de direcciones internas." ;;
    kernel.randomize_va_space) echo "Controla ASLR; el valor 2 aleatoriza ampliamente el espacio de direcciones de los procesos." ;;
    kernel.yama.ptrace_scope) echo "Restringe qué procesos pueden inspeccionar otros mediante ptrace; puede afectar gdb, strace y herramientas de monitoreo." ;;
    kernel.user_ptrace|kernel.user_ptrace_self) echo "Restringe el uso de ptrace; verifique compatibilidad con depuración y herramientas de diagnóstico." ;;
    fs.protected_fifos) echo "Protege FIFO en directorios sticky compartidos; el valor 2 también cubre directorios group-writable. Puede afectar flujos IPC que dependan de abrir FIFO de otro usuario." ;;
    fs.protected_regular) echo "Impide ciertos accesos/creaciones de archivos regulares en directorios sticky compartidos cuando el archivo pertenece a otro usuario/grupo. Reduce ataques locales en /tmp, pero puede romper aplicaciones que dependen de esas operaciones compartidas." ;;
    fs.protected_hardlinks) echo "Restringe hard links a archivos que el usuario no controla, protegiendo archivos sensibles." ;;
    fs.protected_symlinks) echo "Mitiga ataques con enlaces simbólicos en directorios compartidos y escribibles." ;;
    net.ipv4.ip_forward) echo "Deshabilita el reenvío IPv4 del host. Puede cortar routing, NAT, gateway/VPN, firewalls, redes de contenedores y cargas que enrutan tráfico. Solo cambia tras confirmación individual y con acceso de recuperación." ;;
    net.ipv6.conf.all.forwarding) echo "Deshabilita el reenvío IPv6 del host. Puede interrumpir routing IPv6, VPN, gateways y redes de contenedores; el ajuste también puede cambiar el comportamiento de Router Advertisements. Solo cambia tras confirmación individual." ;;
    net.ipv4.conf.all.accept_redirects|net.ipv4.conf.default.accept_redirects) echo "Ignora redirecciones ICMP recibidas; reduce cambios de ruta inducidos por terceros. Revise si la red depende de ellas." ;;
    net.ipv6.conf.all.accept_redirects|net.ipv6.conf.default.accept_redirects) echo "Ignora redirecciones ICMPv6 recibidas; evita modificaciones de ruta inducidas por terceros, pero puede afectar redes que dependan de esas redirecciones. El cambio se confirma individualmente." ;;
    net.ipv4.conf.all.secure_redirects|net.ipv4.conf.default.secure_redirects) echo "Controla redirecciones ICMP consideradas seguras desde gateways conocidos. El valor 0 es más restrictivo y puede afectar redes que dependan de esos redirects." ;;
    net.ipv4.conf.all.send_redirects|net.ipv4.conf.default.send_redirects) echo "Controla el envío de redirecciones ICMP por este host; desactivarlo evita que actúe como router anunciando rutas." ;;
    net.ipv4.conf.all.accept_source_route|net.ipv4.conf.default.accept_source_route|net.ipv6.conf.all.accept_source_route|net.ipv6.conf.default.accept_source_route) echo "Rechaza paquetes con rutas especificadas por el origen; reduce manipulación de rutas." ;;
    net.ipv4.conf.all.log_martians|net.ipv4.conf.default.log_martians) echo "Registra paquetes con direcciones de origen sospechosas; puede aumentar el volumen de logs." ;;
    net.ipv4.conf.all.rp_filter|net.ipv4.conf.default.rp_filter) echo "Valida la ruta inversa para reducir spoofing. El valor 1 es estricto y 2 flexible; el modo estricto puede descartar tráfico asimétrico o multihomed." ;;
    net.ipv4.icmp_echo_ignore_broadcasts) echo "Ignora ICMP echo a broadcast y reduce participación en ataques de amplificación tipo Smurf." ;;
    net.ipv4.icmp_ignore_bogus_error_responses) echo "Ignora mensajes ICMP de error inválidos y reduce ruido por respuestas malformadas." ;;
    net.ipv4.tcp_syncookies) echo "Activa SYN cookies cuando la cola TCP de conexiones pendientes se satura; bajo ataque puede reducir algunas características TCP." ;;
    net.ipv4.tcp_max_syn_backlog) echo "Define la cola máxima de conexiones TCP que aún no completan el handshake; valores altos toleran más pendientes y usan más recursos potencialmente." ;;
    net.core.somaxconn) echo "Limita la cola máxima de conexiones completadas solicitada por aplicaciones; valores altos ayudan con picos si la aplicación los aprovecha." ;;
    net.ipv4.tcp_synack_retries) echo "Define las retransmisiones SYN-ACK; cambiarlo afecta la tolerancia a pérdida/latencia y la duración de conexiones incompletas." ;;
    net.ipv4.tcp_syn_retries) echo "Define reintentos SYN de conexiones TCP salientes; aumentarlo puede alargar el tiempo antes de declarar fallida una conexión." ;;
    net.ipv6.conf.all.accept_ra|net.ipv6.conf.default.accept_ra) echo "Controla anuncios de router IPv6; desactivarlo puede romper rutas automáticas si la red depende de Router Advertisements." ;;
    user.max_user_namespaces) echo "El valor 0 bloquea user namespaces y puede mitigar vías de escalada local, pero puede romper contenedores rootless, sandboxes y aplicaciones que dependan de ellos." ;;
    kernel.unprivileged_bpf_disabled) echo "Deshabilita BPF para procesos sin privilegios y reduce superficie de ataque local; puede afectar herramientas de tracing/observabilidad que ejecuten BPF sin privilegios." ;;
    vm.mmap_min_addr) echo "Evita mapeos de memoria en direcciones muy bajas; reduce ciertas explotaciones, aunque puede afectar aplicaciones antiguas." ;;
    *) sysctl -d "$1" 2>/dev/null | sed -n '1p' | sed 's/^[^:]*:[[:space:]]*//' ;;
  esac
}

# Emits filepath|line|value for all active exact-key definitions.
# Accepts both "key = value" and "key value" syntax, and slash/dot key notation.
sysctl_safe_inventory() {
  local key="$1" file real_file seen_paths=" "
  for file in /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/local/lib/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf; do
    [ -f "$file" ] || continue
    real_file="$(readlink -f "$file" 2>/dev/null || echo "$file")"
    case "$seen_paths" in *" $real_file "*) continue ;; esac
    seen_paths="$seen_paths$real_file "
    awk -v key="$key" -v path="$file" '
      function trim(s) {
        sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s
      }
      {
        line=$0
        if (line ~ /^[ \t]*#/) next
        sub(/[ \t]*#.*/, "", line)
        eq=index(line, "=")
        if (eq) {
          lhs=trim(substr(line, 1, eq-1))
          rhs=trim(substr(line, eq+1))
        } else {
          line=trim(line)
          if (line !~ /^[^ \t]+[ \t]+[^ \t]/) next
          lhs=line
          sub(/[ \t].*$/, "", lhs)
          rhs=line
          sub(/^[^ \t]+[ \t]+/, "", rhs)
          rhs=trim(rhs)
        }
        gsub(/\//, ".", lhs)
        if (lhs == key && rhs != "") printf "%s|%d|%s\n", path, FNR, rhs
      }
    ' "$file" 2>/dev/null
  done
}

sysctl_safe_write_profile() {
  local key="$1" value="$2" file="$3" backup_dir="$4" begin="$5" end="$6"
  local tmp mode backup
  [ -n "$file" ] || { sysctl_safe_log "ERROR" "No se definió archivo de persistencia."; return 1; }
  mkdir -p "$(dirname "$file")" || return 1
  if [ "$file" = "/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf" ] && [ -L "$file" ]; then
    sysctl_safe_log "ERROR" "$file es un enlace simbólico; no se reemplaza."
    return 1
  fi
  if [ "$file" = "/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf" ] && [ -e "$file" ] && ! grep -Fqx "# OrangeBox managed sysctl overrides" "$file"; then
    sysctl_safe_log "ERROR" "$file ya existe, pero no contiene el marcador de propiedad OrangeBox; no se sobrescribe."
    return 1
  fi
  if [ -n "$begin" ] && [ -n "$end" ] && [ -e "$file" ]; then
    if ! grep -Fqx "$begin" "$file" || ! grep -Fqx "$end" "$file"; then
      sysctl_safe_log "ERROR" "$file existe pero no contiene el bloque gestionado esperado; no se modifica."
      return 1
    fi
  fi
  if [ -e "$file" ]; then
    mode="$(stat -c '%a' "$file" 2>/dev/null || echo 644)"
    if [ -n "$backup_dir" ]; then
      mkdir -p "$backup_dir" || return 1
      backup="$backup_dir/$(basename "$file")"
      if [ ! -e "$backup" ]; then cp -a "$file" "$backup" || return 1; fi
    fi
  else
    mode=644
  fi
  tmp="$(mktemp "$file.XXXXXX")" || return 1

  if [ -n "$begin" ] && [ -n "$end" ]; then
    if [ -f "$file" ]; then
      awk -v key="$key" -v value="$value" -v begin="$begin" -v end="$end" '
        function trim(s) {
          sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s
        }
        function haskey(line, eq, lhs, rest) {
          if (line ~ /^[ \t]*#/) return 0
          eq=index(line, "=")
          if (eq) lhs=trim(substr(line, 1, eq-1))
          else {
            line=trim(line)
            if (line !~ /^[^ \t]+[ \t]+[^ \t]/) return 0
            lhs=line
            sub(/[ \t].*$/, "", lhs)
          }
          gsub(/\//, ".", lhs)
          return lhs == key
        }
        $0 == begin { inside=1; print; next }
        $0 == end {
          if (!written) { print key " = " value; written=1 }
          inside=0; print; next
        }
        inside && haskey($0) {
          if (!written) { print key " = " value; written=1 }
          next
        }
        { print }
      ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
      awk -v key="$key" -v begin="$begin" -v end="$end" '
        $0==begin {inside=1; next}
        $0==end {inside=0; next}
        inside {
          line=$0
          if (line ~ /^[ \t]*#/) next
          eq=index(line, "=")
          if (eq) lhs=substr(line,1,eq-1)
          else {
            line2=line
            if (line2 !~ /^[ \t]*[^ \t]+[ \t]+[^ \t]/) next
            sub(/^[ \t]+/, "", line2)
            lhs=line2
            sub(/[ \t].*$/, "", lhs)
          }
          gsub(/^[ \t]+|[ \t]+$/, "", lhs); gsub(/\//, ".", lhs)
          if (lhs==key) found=1
        }
        END {exit(found?0:1)}
      ' "$tmp" || { rm -f "$tmp"; sysctl_safe_log "ERROR" "No se pudo actualizar $key dentro del bloque gestionado."; return 1; }
    else
      if [ "$begin" = "# BEGIN ORANGEBOX SYNFLOOD" ]; then
        { echo "# OrangeBox managed SYN flood profile"; echo "$begin"; echo "$key = $value"; echo "$end"; } > "$tmp" || { rm -f "$tmp"; return 1; }
      else
        { echo "# OrangeBox managed sysctl profile"; echo "$begin"; echo "$key = $value"; echo "$end"; } > "$tmp" || { rm -f "$tmp"; return 1; }
      fi
    fi
  else
    if [ -f "$file" ]; then
      awk -v key="$key" -v value="$value" '
        function trim(s) {
          sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s
        }
        function haskey(line, eq, lhs) {
          if (line ~ /^[ \t]*#/) return 0
          eq=index(line, "=")
          if (eq) lhs=trim(substr(line, 1, eq-1))
          else {
            line=trim(line)
            if (line !~ /^[^ \t]+[ \t]+[^ \t]/) return 0
            lhs=line
            sub(/[ \t].*$/, "", lhs)
          }
          gsub(/\//, ".", lhs)
          return lhs == key
        }
        haskey($0) { if (!written) { print key " = " value; written=1 } ; next }
        { print }
        END { if (!written) print key " = " value }
      ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    else
      {
        printf '# OrangeBox managed sysctl overrides\n'
        printf '%s = %s\n' "$key" "$value"
      } > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
  fi
  chmod "$mode" "$tmp" || { rm -f "$tmp"; return 1; }
  chown root:root "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  return 0
}

# Usage: sysctl_safe_apply KEY VALUE DESCRIPTION TARGET_FILE BACKUP_DIR FIX_MODE SECTION_BEGIN SECTION_END
# Return 0 when already correct or applied; 1 when skipped or failed.
sysctl_safe_apply() {
  local key="$1" expected="$2" supplied_desc="$3" target="$4" backup_dir="$5" fix_mode="$6" begin="$7" end="$8"
  local current defs any_defs=false conflict=false sysctl_conf_conflict=false cfg_file cfg_line cfg_value answer desc need_persist=false target_value legacy_target
  SYSCTL_SAFE_CHANGED=false
  current="$(sysctl -n "$key" 2>/dev/null || true)"
  if [ -z "$current" ]; then sysctl_safe_log "WARN" "$key no está disponible en este kernel; no se aplica."; return 1; fi
  desc="$supplied_desc"
  if [ -z "$desc" ] || [ "$desc" = "$key" ]; then desc="$(sysctl_safe_description "$key")"; fi
  [ -n "$desc" ] || desc="Ajusta el comportamiento del parámetro de kernel $key."
  defs="$(sysctl_safe_inventory "$key")"
  if [ -n "$defs" ]; then
    any_defs=true
    while IFS='|' read -r cfg_file cfg_line cfg_value; do
      [ -n "$cfg_value" ] || continue
      if [ "$cfg_value" != "$expected" ]; then
        conflict=true
        [ "$cfg_file" = "/etc/sysctl.conf" ] && sysctl_conf_conflict=true
      fi
    done <<< "$defs"
  fi

  if [ "$current" = "$expected" ] && [ "$sysctl_conf_conflict" != true ] && [ "$conflict" = true ]; then
    local expected_definition=false
    while IFS='|' read -r cfg_file cfg_line cfg_value; do
      [ "$cfg_value" = "$expected" ] && expected_definition=true
    done <<< "$defs"
    if [ "$expected_definition" = true ]; then
      if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
        sysctl_safe_log "OK" "$key=$expected activo con definición persistente objetivo; se conserva la precedencia actual."
        return 0
      fi
      sysctl_safe_log "OK" "$key=$expected ya está activo y existe una definición persistente con ese valor."
      echo "  Se conservan las demás definiciones sin crear un override innecesario:"
      while IFS='|' read -r cfg_file cfg_line cfg_value; do
        [ -n "$cfg_value" ] && printf '  - conservado: %s:%s = %s\n' "$cfg_file" "$cfg_line" "$cfg_value"
      done <<< "$defs"
      return 0
    fi
  fi

  if [ "$conflict" = true ]; then
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ] && [ "$fix_mode" != true ]; then
      sysctl_safe_log "WARN" "$key tiene definiciones persistentes en conflicto; --fix puede reconciliarlas con confirmación individual."
      return 1
    fi
    echo
    sysctl_safe_log "CONFLICTO" "$key ya tiene definiciones persistentes diferentes."
    echo "  Qué cambia: $desc"
    echo "  Valor activo: $current | Valor propuesto: $expected"
    echo "  Definiciones detectadas (los archivos existentes no se modifican salvo /etc/sysctl.conf si se confirma):"
    while IFS='|' read -r cfg_file cfg_line cfg_value; do
      [ -n "$cfg_value" ] && printf '    - %s:%s = %s\n' "$cfg_file" "$cfg_line" "$cfg_value"
    done <<< "$defs"

    target_value="$(sysctl_safe_inventory "$key" | awk -F'|' -v target="$target" '$1==target {value=$3} END {print value}')"
    if [ "$current" = "$expected" ] && [ "$target_value" = "$expected" ] && [ "$sysctl_conf_conflict" != true ]; then
      sysctl_safe_log "OK" "$key=$expected ya está aplicado mediante el override $target; las definiciones anteriores se conservan y no se vuelve a preguntar."
      return 0
    fi

    if [ "$fix_mode" != true ]; then sysctl_safe_log "WARN" "Auditoría: se conserva la configuración actual."; return 1; fi
    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then sysctl_safe_log "WARN" "No hay terminal interactiva; se omite $key por seguridad."; return 1; fi
    if [ "$sysctl_conf_conflict" = true ]; then
      printf '¿Confirmas aplicar %s=%s, crear el override en %s y actualizar solo las asignaciones conflictivas de /etc/sysctl.conf? [s/N] ' "$key" "$expected" "$target" > /dev/tty
    else
      printf '¿Confirmas aplicar %s=%s y añadir/actualizar el override en %s? [s/N] ' "$key" "$expected" "$target" > /dev/tty
    fi
    IFS= read -r answer < /dev/tty || answer=""
    case "$answer" in y|Y|yes|YES|s|S|si|SI|sí|Sí|SÍ) ;; *) sysctl_safe_log "OMITIDO" "No se modificó $key."; return 1 ;; esac
    need_persist=true
  elif [ "$current" = "$expected" ] && [ "$any_defs" = true ]; then
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
      sysctl_safe_log "OK" "$key=$expected; valor activo y persistente alineados."
      return 0
    fi
    sysctl_safe_log "OK" "$key=$expected; valor activo y persistente alineados."
    while IFS='|' read -r cfg_file cfg_line cfg_value; do
      [ -n "$cfg_value" ] && printf '  - conservado: %s:%s = %s\n' "$cfg_file" "$cfg_line" "$cfg_value"
    done <<< "$defs"
    return 0
  elif [ "$fix_mode" != true ]; then
    if [ "${PENDING_ONLY_AUDIT:-false}" = true ]; then
      if [ "$current" = "$expected" ]; then
        sysctl_safe_log "WARN" "$key=$expected está activo, pero falta persistencia."
      else
        sysctl_safe_log "WARN" "$key activo=$current; objetivo=$expected."
      fi
      return 1
    fi
    if [ "$current" = "$expected" ]; then
      sysctl_safe_log "WARN" "$key está activo en $expected, pero no tiene definición persistente; no se modifica en auditoría."
    else
      sysctl_safe_log "WARN" "$key activo=$current; recomendado=$expected. Qué cambia: $desc"
      if [ "$any_defs" = true ]; then
        echo "  Hay una definición persistente con el valor recomendado; se conserva."
        while IFS='|' read -r cfg_file cfg_line cfg_value; do
          [ -n "$cfg_value" ] && printf '  - %s:%s = %s\n' "$cfg_file" "$cfg_line" "$cfg_value"
        done <<< "$defs"
      else echo "  No hay definiciones persistentes activas para este parámetro."; fi
    fi
    return 1
  else
    if [ "$any_defs" = false ] || [ "$current" != "$expected" ]; then need_persist=true; fi
    if [ "$current" != "$expected" ]; then
      echo
      sysctl_safe_log "CAMBIO PROPUESTO" "$key: activo=$current; propuesto=$expected."
      echo "  Qué cambia: $desc"
      if [ "$fix_mode" != true ]; then
        sysctl_safe_log "WARN" "Auditoría: no se cambia $key."
        return 1
      fi
      if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
        sysctl_safe_log "WARN" "No hay terminal interactiva; se omite $key por seguridad."
        return 1
      fi
      printf '¿Confirmas cambiar %s de %s a %s y persistirlo cuando corresponda? [s/N] ' "$key" "$current" "$expected" > /dev/tty
      IFS= read -r answer < /dev/tty || answer=""
      case "$answer" in y|Y|yes|YES|s|S|si|SI|sí|Sí|SÍ) ;; *) sysctl_safe_log "OMITIDO" "No se modificó $key."; return 1 ;; esac
    fi
  fi

  # If runtime already matches but no persistent definition exists, persistence
  # is still a change: require per-parameter consent rather than silently writing it.
  if [ "$need_persist" = true ] && [ "$current" = "$expected" ] && [ "$any_defs" = false ]; then
    sysctl_safe_log "CAMBIO PROPUESTO" "$key=$expected ya está activo, pero falta persistencia."
    echo "  Qué cambia: añadir una definición persistente en $target; el valor activo se conserva."
    if [ "$fix_mode" != true ]; then
      sysctl_safe_log "WARN" "Auditoría: no se cambia la persistencia de $key."
      return 1
    fi
    if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
      sysctl_safe_log "WARN" "No hay terminal interactiva; se omite la persistencia de $key por seguridad."
      return 1
    fi
    printf '¿Confirmas persistir %s=%s en %s? [s/N] ' "$key" "$expected" "$target" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    case "$answer" in y|Y|yes|YES|s|S|si|SI|sí|Sí|SÍ) ;; *) sysctl_safe_log "OMITIDO" "No se modificó la persistencia de $key."; return 1 ;; esac
  fi

  if [ "$need_persist" = true ]; then
    if ! sysctl_safe_write_profile "$key" "$expected" "$target" "$backup_dir" "$begin" "$end"; then
      sysctl_safe_log "ERROR" "No se pudo persistir $key en $target; no se aplica en runtime."
      return 1
    fi
    SYSCTL_SAFE_CHANGED=true
    sysctl_safe_log "OK" "Persistencia de $key=$expected escrita en $target; las otras definiciones quedan intactas."
    if [ "$sysctl_conf_conflict" = true ]; then
      legacy_target="$(readlink -f /etc/sysctl.conf 2>/dev/null || echo /etc/sysctl.conf)"
      if ! sysctl_safe_write_profile "$key" "$expected" "$legacy_target" "$backup_dir" "" ""; then
        sysctl_safe_log "WARN" "Se escribió $target, pero no se pudo reconciliar la asignación conflictiva de /etc/sysctl.conf ($legacy_target)."
        return 1
      fi
      sysctl_safe_log "OK" "Asignación conflictiva de $key actualizada en $legacy_target tras la confirmación."
    fi
  fi
  if [ "$current" != "$expected" ]; then
    if sysctl -w "$key=$expected" >/dev/null 2>&1 && [ "$(sysctl -n "$key" 2>/dev/null || true)" = "$expected" ]; then
      SYSCTL_SAFE_CHANGED=true
      sysctl_safe_log "OK" "Valor activo de $key aplicado: $expected."
    else
      sysctl_safe_log "WARN" "No se pudo aplicar/verificar $key=$expected; revise la precedencia de sysctl."
      return 1
    fi
  fi
  return 0
}


# OrangeBox policy for kernel.kptr_restrict:
# preserve active values 1 and 2 without touching runtime or persistent files;
# only route an active value of 0 through the normal individually-confirmed helper.
sysctl_safe_apply_kptr_restrict_policy() {
  local target="$1" backup_dir="$2" fix_mode="$3" begin="${4:-}" end="${5:-}"
  local current
  SYSCTL_SAFE_CHANGED=false
  current="$(sysctl -n kernel.kptr_restrict 2>/dev/null || true)"

  case "$current" in
    1|2)
      sysctl_safe_log "OK" "kernel.kptr_restrict=$current; la política OrangeBox acepta 1 o 2. Se conserva sin tocar runtime ni persistencia."
      return 0
      ;;
    0)
      sysctl_safe_apply "kernel.kptr_restrict" "1" "$(sysctl_safe_description kernel.kptr_restrict)" "$target" "$backup_dir" "$fix_mode" "$begin" "$end"
      return $?
      ;;
    "")
      sysctl_safe_log "N/A" "kernel.kptr_restrict no está disponible en este kernel; el control no aplica."
      return 0
      ;;
    *)
      sysctl_safe_log "WARN" "kernel.kptr_restrict=$current no es un valor contemplado por la política; solo se cambia cuando el valor activo es 0. Se conserva sin cambios y requiere revisión."
      return 1
      ;;
  esac
}

