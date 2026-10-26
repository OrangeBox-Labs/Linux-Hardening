#!/usr/bin/env bash
# Auditoría de solo lectura: contrasta sockets expuestos con políticas INPUT.
# Nunca ejecuta comandos que modifiquen reglas ni servicios de firewall.

lfa_iptables_text_state() {
  local dump="$1" protocol="$2" port="$3"
  printf '%s\n' "$dump" | awk -v wp="$protocol" -v p="$port" '
    function target(line,a,n,i) { n=split(line,a,/[[:space:]]+/); for(i=1;i<n;i++) if(a[i]=="-j"||a[i]=="-g") return a[i+1]; return "" }
    function terminal(t) { return t=="ACCEPT"||t=="DROP"||t=="REJECT" }
    function jump_uncond(line,t) { t=target(line); return t!=""&&!terminal(t)&&line ~ /^-A [^[:space:]]+ -[jg] [^[:space:]]+[[:space:]]*$/ }
    function terminal_uncond(line,t) { t=target(line); if(t=="REJECT")return line~/^-A [^[:space:]]+ -j REJECT([[:space:]]+--reject-with[[:space:]]+[[:alnum:]_-]+)?[[:space:]]*$/; return (t=="ACCEPT"||t=="DROP")&&line ~ ("^-A [^[:space:]]+ -j " t "[[:space:]]*$") }
    function ports(spec,wanted,a,n,i,r) { gsub(/[{}[:space:]]/,"",spec); n=split(spec,a,","); for(i=1;i<=n;i++){if(a[i]~/^[0-9]+:[0-9]+$/){split(a[i],r,":");if(wanted+0>=r[1]+0&&wanted+0<=r[2]+0)return 1}else if(a[i]~/^[0-9]+-[0-9]+$/){split(a[i],r,"-");if(wanted+0>=r[1]+0&&wanted+0<=r[2]+0)return 1}else if(a[i]~/^[0-9]+$/&&a[i]+0==wanted+0)return 1}return 0}
    function established_only(line,v) { v=line; if(v~/--ctstate[[:space:]]+/){sub(/^.*--ctstate[[:space:]]+/,"",v);sub(/[[:space:]].*$/,"",v)}else if(v~/--state[[:space:]]+/){sub(/^.*--state[[:space:]]+/,"",v);sub(/[[:space:]].*$/,"",v)}else{return 0} return v=="ESTABLISHED"||v=="RELATED"||v=="ESTABLISHED,RELATED"||v=="RELATED,ESTABLISHED" }
    function has_port(line,proto,wanted,a,n,i,rp,spec) {
      if(established_only(line))return 0
      n=split(line,a,/[[:space:]]+/);rp=""
      for(i=1;i<n;i++)if(a[i]=="-p"){rp=a[i+1];break}
      if(rp!=proto&&!(proto=="tcp"&&rp=="6")&&!(proto=="udp"&&rp=="17"))return 0
      for(i=1;i<=n;i++){
        if(a[i]=="--dport"||a[i]=="--dports"||a[i]=="--destination-port"||a[i]=="--destination-ports"){if(i<n&&ports(a[i+1],wanted))return 1}
        else if(a[i]~/^--dport=/){spec=a[i];sub(/^--dport=/,"",spec);if(ports(spec,wanted))return 1}
        else if(a[i]~/^--dports=/){spec=a[i];sub(/^--dports=/,"",spec);if(ports(spec,wanted))return 1}
      }
      return 0
    }
    function scoped(line){return line~/(^|[[:space:]])(-s|--source|-d|--destination|-i|--in-interface|-o|--out-interface|--match-set|--src-range|--dst-range|--physdev-in|--physdev-out)([[:space:]]|$)/}
    BEGIN{in_filter=0;nr=0;policy="";seen=0;complex=0}
    $0=="*filter"{in_filter=1;next}
    $0=="COMMIT"{in_filter=0;next}
    !in_filter{next}
    $1~/^:/{c=$1;sub(/^:/,"",c);exists[c]=1;if(c=="INPUT"){seen=1;policy=$2};next}
    $1=="-A"{nr++;rules[nr]=$0;rc[nr]=$2;seq[nr]=chain_seq[$2]++}
    END{
      if(!seen){print "ALLOWED";exit}
      reachable["INPUT"]=1
      for(pass=1;pass<=nr;pass++)for(i=1;i<=nr;i++)if(reachable[rc[i]]){
        t=target(rules[i])
        if(t!=""&&!terminal(t)&&exists[t]){if(jump_uncond(rules[i]))reachable[t]=1;else complex=1}
      }
      for(i=1;i<=nr;i++)if(reachable[rc[i]]){
        t=target(rules[i])
        if(terminal(t)&&has_port(rules[i],wp,p)){
          if(scoped(rules[i])){if(t=="ACCEPT"){ra=1;rac=rc[i];rai=seq[i]}else{rd=1;rdc=rc[i];rdi=seq[i]}}
          else if(t=="ACCEPT"){a=1;ac=rc[i];ai=seq[i]}
          else{d=1;dc=rc[i];di=seq[i]}
        }else if(terminal_uncond(rules[i])){
          if(t=="ACCEPT"){ba=1;bac=rc[i];bai=seq[i]}else{bd=1;bdc=rc[i];bdi=seq[i]}
        }
      }
      if(a&&d){if(ac==dc){if(ai<di)d=0;else a=0}else{print "UNKNOWN";exit}}
      if(a&&bd){if(ac==bdc){if(bdi<ai)a=0;else bd=0}else{print "UNKNOWN";exit}}
      if(d&&ba){if(dc==bac){if(bai<di)d=0;else ba=0}else{print "UNKNOWN";exit}}
      if(ra&&d){if(rac==dc&&rai<di){print "RESTRICTED";exit}else if(rac==dc)ra=0;else{print "UNKNOWN";exit}}
      if(a){print "ALLOWED";exit}
      if(d){print "BLOCKED";exit}
      if(ra){if(policy=="ACCEPT"){print "ALLOWED";exit};if(policy=="DROP"||policy=="REJECT"){print "RESTRICTED";exit}}
      if(ba&&bd){if(bac==bdc){if(bai<bdi)print "ALLOWED";else print "BLOCKED"}else print "UNKNOWN";exit}
      if(ba){print "ALLOWED";exit}
      if(bd){print "BLOCKED";exit}
      if(policy=="ACCEPT"){print "ALLOWED";exit}
      if(policy=="DROP"||policy=="REJECT"){if(complex)print "UNKNOWN";else print "BLOCKED";exit}
      print "UNKNOWN"
    }'
}

lfa_nft_text_state() {
  local rules="$1" family="$2" protocol="$3" port="$4"
  printf '%s\n' "$rules" | awk -v wf="$family" -v wp="$protocol" -v p="$port" '
    function strip(s){sub(/^[[:space:]]*/,"",s);sub(/^counter packets [0-9]+ bytes [0-9]+[[:space:]]*/,"",s);return s}
    function target(line,s,a,n,i){s=strip(line);n=split(s,a,/[[:space:];]+/);for(i=1;i<n;i++)if(a[i]=="jump"||a[i]=="goto")return a[i+1];return ""}
    function action(line,s,a,n,i){s=strip(line);n=split(s,a,/[[:space:];]+/);for(i=n;i>=1;i--)if(a[i]=="accept"||a[i]=="drop"||a[i]=="reject")return a[i];return ""}
    function family_matches(tf,wf){return tf=="inet"||(wf=="ipv4"&&tf=="ip")||(wf=="ipv6"&&tf=="ip6")}
    function jump_uncond(line,s){s=strip(line);return s~/^(jump|goto)[[:space:]]+[[:alnum:]_.-]+[[:space:]]*;?$/}
    function terminal_uncond(line,s){s=strip(line);return s~/^(accept|drop|reject)[[:space:]]*;?$/}
    function scoped(line){return line~/((^|[[:space:]])(ip saddr|ip daddr|ip6 saddr|ip6 daddr|iifname|oifname|ether saddr|ether daddr|iif|oif)([[:space:]]|$))/}
    function established_only(line,v){v=line;if(v~/ct state[[:space:]]+/){sub(/^.*ct state[[:space:]]+/,"",v);sub(/[[:space:];].*$/,"",v)}else{return 0}return v=="established"||v=="related"||v=="established,related"||v=="related,established"}
    function ports(spec,wanted,a,n,i,r){gsub(/[{}[:space:]]/,"",spec);n=split(spec,a,",");for(i=1;i<=n;i++){if(a[i]~/^[0-9]+-[0-9]+$/){split(a[i],r,"-");if(wanted+0>=r[1]+0&&wanted+0<=r[2]+0)return 1}else if(a[i]~/^[0-9]+:[0-9]+$/){split(a[i],r,":");if(wanted+0>=r[1]+0&&wanted+0<=r[2]+0)return 1}else if(a[i]~/^[0-9]+$/&&a[i]+0==wanted+0)return 1}return 0}
    function has_port(line,proto,wanted,s,pos,spec,a){if(established_only(line))return 0;if(proto=="tcp"&&line!~/(^|[[:space:]])tcp[[:space:]]+dport([[:space:]]|$)/)return 0;if(proto=="udp"&&line!~/(^|[[:space:]])udp[[:space:]]+dport([[:space:]]|$)/)return 0;pos=index(line,proto " dport");if(!pos)return 0;s=substr(line,pos+length(proto " dport"));sub(/^[[:space:]]*/,"",s);if(substr(s,1,1)=="!"||substr(s,1,2)=="!=")return 0;if(substr(s,1,1)=="{"){if(index(s,"}")==0)return 0;spec=substr(s,2,index(s,"}")-2)}else{split(s,a,/[[:space:];]+/);spec=a[1]}return ports(spec,wanted)}
    BEGIN{table="";tf="";ck="";nr=0;input_seen=0;complex=0;input_chains=0}
    $1=="table"{tf=$2;tn=$3;gsub(/[{}]/,"",tn);table=tf ":" tn;ck="";next}
    $1=="chain"{cn=$2;gsub(/[{}]/,"",cn);ck=table ":" cn;exists[ck]=1;ctable[ck]=table;chain_seq[ck]=0;next}
    /^[[:space:]]*}[[:space:]]*$/{ck="";next}
    ck!=""{
      if(!family_matches(tf,wf))next
      if($0~/hook[[:space:]]+input/){input_seen=1;base[ck]=1;input_chains++;if($0~/policy[[:space:]]+(drop|reject)([[:space:];]|$)/)policy[ck]="DROP";else if($0~/policy[[:space:]]+accept([[:space:];]|$)/)policy[ck]="ACCEPT"}
      else{nr++;rules[nr]=$0;rc[nr]=ck;seq[nr]=chain_seq[ck]++}
    }
    END{
      if(!input_seen){print "UNKNOWN";exit}
      if(input_chains>1)complex=1
      for(c in base)reachable[c]=1
      for(pass=1;pass<=nr;pass++)for(i=1;i<=nr;i++)if(reachable[rc[i]]){t=target(rules[i]);if(t!=""){nc=ctable[rc[i]] ":" t;if(exists[nc]){if(jump_uncond(rules[i]))reachable[nc]=1;else complex=1}}}
      for(i=1;i<=nr;i++)if(reachable[rc[i]]){
        t=action(rules[i])
        if((t=="accept"||t=="drop"||t=="reject")&&has_port(rules[i],wp,p)){
          if(scoped(rules[i])){if(t=="accept"){ra=1;rac=rc[i];rai=seq[i]}else{rd=1;rdc=rc[i];rdi=seq[i]}}
          else if(t=="accept"){a=1;ac=rc[i];ai=seq[i]}else{d=1;dc=rc[i];di=seq[i]}
        }else if(terminal_uncond(rules[i])){if(t=="accept"){ba=1;bac=rc[i];bai=seq[i]}else{bd=1;bdc=rc[i];bdi=seq[i]}}
      }
      if(a&&d){if(ac==dc){if(ai<di)d=0;else a=0}else{print "UNKNOWN";exit}}
      if(a&&bd){if(ac==bdc){if(bdi<ai)a=0;else bd=0}else{print "UNKNOWN";exit}}
      if(d&&ba){if(dc==bac){if(bai<di)d=0;else ba=0}else{print "UNKNOWN";exit}}
      if(ra&&d){if(rac==dc&&rai<di){print "RESTRICTED";exit}else if(rac==dc)ra=0;else{print "UNKNOWN";exit}}
      if(a){print "ALLOWED";exit}
      if(d){print "BLOCKED";exit}
      if(ra){for(c in policy)if(policy[c]=="ACCEPT"){print "ALLOWED";exit};for(c in policy)if(policy[c]=="DROP"){print "RESTRICTED";exit}}
      for(c in policy)if(policy[c]=="ACCEPT"){if(bd){print "BLOCKED";exit};if(ba){print "ALLOWED";exit};print "ALLOWED";exit}
      for(c in policy)if(policy[c]=="DROP"){if(ba&&bd){if(bac==bdc){if(bai<bdi)print "ALLOWED";else print "BLOCKED"}else print "UNKNOWN";exit};if(ba){print "ALLOWED";exit};if(bd){print "BLOCKED";exit};if(complex){print "UNKNOWN";exit};print "BLOCKED";exit}
      print "UNKNOWN"
    }'
}

lfa_load_firewall_snapshots() {
  LFA_FIREWALL_SNAPSHOT_LOADED=true
  LFA_IPV4_RULES_AVAILABLE=false
  LFA_IPV6_RULES_AVAILABLE=false
  LFA_NFT_RULES_AVAILABLE=false
  LFA_IPV4_RULES=""
  LFA_IPV6_RULES=""
  LFA_NFT_RULES=""

  local version save_cmd dump
  if command -v iptables >/dev/null 2>&1; then
    version="$(iptables -V 2>/dev/null || true)"
    case "$version" in *"(legacy)"*) save_cmd=iptables-legacy-save ;; *) save_cmd=iptables-save ;; esac
    if ! command -v "$save_cmd" >/dev/null 2>&1; then save_cmd=iptables-save; fi
    if command -v "$save_cmd" >/dev/null 2>&1 && dump="$("$save_cmd" 2>/dev/null)"; then
      LFA_IPV4_RULES="$dump"
      LFA_IPV4_RULES_AVAILABLE=true
    fi
  fi
  if command -v ip6tables >/dev/null 2>&1; then
    version="$(ip6tables -V 2>/dev/null || true)"
    case "$version" in *"(legacy)"*) save_cmd=ip6tables-legacy-save ;; *) save_cmd=ip6tables-save ;; esac
    if ! command -v "$save_cmd" >/dev/null 2>&1; then save_cmd=ip6tables-save; fi
    if command -v "$save_cmd" >/dev/null 2>&1 && dump="$("$save_cmd" 2>/dev/null)"; then
      LFA_IPV6_RULES="$dump"
      LFA_IPV6_RULES_AVAILABLE=true
    fi
  fi
  if command -v nft >/dev/null 2>&1 && dump="$(nft list ruleset 2>/dev/null)"; then
    LFA_NFT_RULES="$dump"
    LFA_NFT_RULES_AVAILABLE=true
  fi
}

lfa_service_risk() {
  local process_lc port="$3"
  process_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$process_lc" in
    *mysqld*|*mariadbd*) printf '%s\n' "MySQL/MariaDB: permitir solo desde redes autorizadas." ; return ;;
    *redis*) printf '%s\n' "Redis: no exponer a redes no confiables; revisar autenticación y aislamiento." ; return ;;
    *snmpd*) printf '%s\n' "SNMP: limitar a sistemas de monitoreo autorizados." ; return ;;
    *vsftpd*|*proftpd*|*pure-ftpd*) printf '%s\n' "FTP: revisar exposición y preferir transferencia cifrada." ; return ;;
    *squid*) printf '%s\n' "Proxy: comprobar que no sea un proxy abierto." ; return ;;
    *smbd*|*samba*|*nmbd*) printf '%s\n' "SMB/Samba: limitar a LAN/VPN; no exponer a redes públicas." ; return ;;
    *named*|*dnsmasq*) printf '%s\n' "DNS: verificar recursión, transferencias de zona y alcance esperado." ; return ;;
    *sshd*) printf '%s\n' "SSH: revisar restricción de origen y autenticación." ; return ;;
    *httpd*|*nginx*|*apache*) printf '%s\n' "Web: confirmar que el sitio deba publicarse por esta interfaz." ; return ;;
    *openvpn*|*wireguard*) printf '%s\n' "VPN: validar protocolos, listener y clientes autorizados." ; return ;;
    *zabbix*) printf '%s\n' "Agente Zabbix: limitar a servidores/proxies autorizados." ; return ;;
    *ntpd*|*chronyd*) printf '%s\n' "NTP: validar clientes atendidos y riesgo de abuso/amplificación." ; return ;;
  esac
  case "$port" in
    21) printf '%s\n' "FTP: revisar exposición y cifrado." ;;
    22) printf '%s\n' "SSH: revisar acceso administrativo y restricción de origen." ;;
    23) printf '%s\n' "Telnet sin cifrado: exposición de alto riesgo." ;;
    53) printf '%s\n' "DNS: revisar recursión, transferencias de zona y alcance." ;;
    67|68) printf '%s\n' "DHCP: limitar a interfaces/redes donde presta servicio." ;;
    111|135|139|445) printf '%s\n' "RPC/SMB: normalmente debe limitarse a redes internas/VPN." ;;
    123) printf '%s\n' "NTP: validar alcance y mitigaciones contra abuso." ;;
    161|162|65531) printf '%s\n' "SNMP: limitar a sistemas de monitoreo autorizados." ;;
    3306|5432|1433|1521|27017) printf '%s\n' "Base de datos: no exponer a redes no autorizadas." ;;
    2375) printf '%s\n' "API Docker sin TLS: exposición de alto riesgo." ;;
    3128|8080) printf '%s\n' "Proxy/servicio alternativo: verificar que no permita acceso abierto." ;;
    3389|5900|5901) printf '%s\n' "Acceso remoto gráfico: limitar a redes administrativas/VPN." ;;
    6379) printf '%s\n' "Redis: no exponer a redes no confiables." ;;
    9200) printf '%s\n' "API Elasticsearch/OpenSearch: revisar autenticación y TLS." ;;
    *) printf '%s\n' "Confirmar que debe recibir conexiones desde redes externas/no confiables." ;;
  esac
}

lfa_family_port_state() {
  local family="$1" protocol="$2" port="$3"
  local ip_state=UNKNOWN nft_state=UNKNOWN ip_rules="" have_ip=false have_nft=false
  if [ "$LFA_FIREWALL_SNAPSHOT_LOADED" != true ]; then lfa_load_firewall_snapshots; fi
  case "$family" in
    ipv4) if [ "$LFA_IPV4_RULES_AVAILABLE" = true ]; then have_ip=true; ip_rules="$LFA_IPV4_RULES"; fi ;;
    ipv6) if [ "$LFA_IPV6_RULES_AVAILABLE" = true ]; then have_ip=true; ip_rules="$LFA_IPV6_RULES"; fi ;;
    *) printf '%s\n' UNKNOWN; return 0 ;;
  esac
  if [ "$have_ip" = true ]; then ip_state="$(lfa_iptables_text_state "$ip_rules" "$protocol" "$port")"; fi
  if [ "$LFA_NFT_RULES_AVAILABLE" = true ]; then have_nft=true; nft_state="$(lfa_nft_text_state "$LFA_NFT_RULES" "$family" "$protocol" "$port")"; fi
  if [ "$have_ip" = true ] && [ "$have_nft" = true ]; then
    if [ "$ip_state" = BLOCKED ] || [ "$nft_state" = BLOCKED ]; then printf '%s\n' BLOCKED
    elif [ "$ip_state" = UNKNOWN ] || [ "$nft_state" = UNKNOWN ]; then printf '%s\n' UNKNOWN
    elif [ "$ip_state" = RESTRICTED ] || [ "$nft_state" = RESTRICTED ]; then printf '%s\n' RESTRICTED
    elif [ "$ip_state" = ALLOWED ] && [ "$nft_state" = ALLOWED ]; then printf '%s\n' ALLOWED
    else printf '%s\n' UNKNOWN; fi
  elif [ "$have_ip" = true ]; then printf '%s\n' "$ip_state"
  elif [ "$have_nft" = true ]; then printf '%s\n' "$nft_state"
  else printf '%s\n' UNKNOWN; fi
}

lfa_service_label() {
  local process="$1" protocol="$2" port="$3" label=""
  case "$process" in
    ""|desconocido|unknown)
      ;;
    *)
      printf '%s\n' "$process"
      return 0
      ;;
  esac
  if command -v getent >/dev/null 2>&1; then
    label="$(getent services "$port/$protocol" 2>/dev/null | awk 'NR==1 {print $1; exit}')"
  fi
  [ -n "$label" ] || label="desconocido"
  printf '%s\n' "$label"
}

lfa_audit_listener_firewall() {
  local line protocol state recvq sendq local_addr peer rest port process service address families family assessment risk
  local sockets=0 checked=0 local_only=0 allowed=0 restricted=0 blocked=0 unknown=0 skipped=0
  local socket_output="" socket_source=""
  LFA_WARNINGS=0

  # ss is available on newer systems. netstat remains a read-only fallback for
  # legacy CentOS/RHEL 6 and minimal installs. Never use firewall write APIs.
  if command -v ss >/dev/null 2>&1; then
    if socket_output="$(ss -lntup 2>/dev/null)" && [ -n "$socket_output" ]; then
      socket_source=ss
    fi
  fi
  if [ -z "$socket_source" ] && command -v netstat >/dev/null 2>&1; then
    if socket_output="$(netstat -lntup 2>/dev/null)" && [ -n "$socket_output" ]; then
      socket_source=netstat
    fi
  fi
  if [ -z "$socket_source" ]; then
    echo "[WARN] Ni ss ni netstat entregaron sockets en escucha; no se puede inventariar ni correlacionar el firewall."
    LFA_WARNINGS=$((LFA_WARNINGS+1))
    return 0
  fi

  lfa_load_firewall_snapshots
  echo "LISTENERS TCP/UDP (incluye loopback; la exposición remota se evalúa por separado):"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in Netid\ *|State\ *|Proto\ *|Active\ *) continue ;; esac

    if [ "$socket_source" = ss ]; then
      IFS=' ' read -r protocol state recvq sendq local_addr peer rest <<< "$line"
      case "$protocol" in
        tcp|tcp6) [ "$state" = LISTEN ] || continue; protocol=tcp ;;
        udp|udp6) protocol=udp ;;
        *) skipped=$((skipped+1)); continue ;;
      esac
      process="$(printf '%s\n' "$line" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')"
      [ -n "$process" ] || process=desconocido
    else
      IFS=' ' read -r protocol recvq sendq local_addr peer state rest <<< "$line"
      case "$protocol" in
        tcp|tcp6)
          [ "$state" = LISTEN ] || continue
          protocol=tcp
          process="$rest"
          [ -n "$process" ] || process=desconocido
          ;;
        udp|udp6)
          protocol=udp
          process="$rest"
          [ -n "$process" ] || process=desconocido
          state=UNCONN
          ;;
        *) skipped=$((skipped+1)); continue ;;
      esac
    fi

    [ -n "$protocol" ] && [ -n "$local_addr" ] || { skipped=$((skipped+1)); continue; }
    port="$(printf '%s\n' "$local_addr" | awk -F: '{print $NF}')"
    case "$port" in ''|*[!0-9]*) skipped=$((skipped+1)); continue ;; esac

    sockets=$((sockets+1))
    address="$(printf '%s\n' "$local_addr" | sed 's/:[0-9][0-9]*$//')"
    service="$(lfa_service_label "$process" "$protocol" "$port")"
    printf '[LISTEN] %-4s/%-5s address=%-27s service=%s\n' "$protocol" "$port" "$local_addr" "$service"

    case "$address" in
      127.*|localhost|::1|'[::1]'|::ffff:127.*)
        local_only=$((local_only+1))
        printf '[LOCAL]  %s/%s en %s (%s): listener limitado a loopback; no se evalúa como exposición remota.\n' "$protocol" "$port" "$local_addr" "$service"
        continue
        ;;
    esac

    case "$address" in
      0.0.0.0) families=ipv4 ;;
      ::|'[::]') families=ipv6 ;;
      '*') families="ipv4 ipv6" ;;
      *:*) families=ipv6 ;;
      *.*) families=ipv4 ;;
      *) families="ipv4 ipv6" ;;
    esac

    for family in $families; do
      [ "$family" != ipv6 ] || [ -d /proc/sys/net/ipv6 ] || continue
      checked=$((checked+1))
      assessment="$(lfa_family_port_state "$family" "$protocol" "$port")"
      case "$assessment" in
        ALLOWED)
          allowed=$((allowed+1))
          LFA_WARNINGS=$((LFA_WARNINGS+1))
          risk="$(lfa_service_risk "$service" "$protocol" "$port")"
          printf '[WARN] ACCESO PERMITIDO / exposición potencial: %s/%s en %s; servicio=%s; familia=%s. Riesgo a revisar: %s\n' "$protocol" "$port" "$local_addr" "$service" "$family" "$risk"
          ;;
        RESTRICTED)
          restricted=$((restricted+1))
          LFA_WARNINGS=$((LFA_WARNINGS+1))
          risk="$(lfa_service_risk "$service" "$protocol" "$port")"
          printf '[WARN] ACCESO RESTRINGIDO/CONDICIONAL: %s/%s en %s; servicio=%s; familia=%s. Verificar orígenes/interfaces permitidos. Riesgo a revisar: %s\n' "$protocol" "$port" "$local_addr" "$service" "$family" "$risk"
          ;;
        BLOCKED)
          blocked=$((blocked+1))
          printf '[OK] BLOQUEADO por la evaluación INPUT disponible: %s/%s en %s; servicio=%s; familia=%s.\n' "$protocol" "$port" "$local_addr" "$service" "$family"
          ;;
        *)
          unknown=$((unknown+1))
          printf '[WARN] INDETERMINADO: %s/%s en %s; servicio=%s; familia=%s. No se considera protegido hasta revisar las reglas efectivas.\n' "$protocol" "$port" "$local_addr" "$service" "$family"
          ;;
      esac
    done
  done <<< "$socket_output"

  [ "$sockets" -gt 0 ] || echo "[INFO] No se encontraron sockets TCP/UDP en escucha."
  [ "$skipped" -eq 0 ] || echo "[INFO] Sockets omitidos por formato no reconocido: $skipped"
  if [ "$unknown" -gt 0 ]; then
    LFA_WARNINGS=$((LFA_WARNINGS+1))
    echo "[WARN] Hay listeners cuyo acceso no pudo verificarse con certeza; no deben considerarse protegidos hasta revisar las reglas efectivas."
  fi
  printf '[INFO] Correlación firewall/listeners (solo lectura): sockets=%s; familias evaluadas=%s; loopback=%s; acceso permitido/exposición potencial=%s; restringido/condicional=%s; bloqueado=%s; indeterminado=%s.\n' "$sockets" "$checked" "$local_only" "$allowed" "$restricted" "$blocked" "$unknown"
  echo "[INFO] No se modificaron CSF, Shorewall, firewalld, Imunify360, UFW, iptables, nftables, servicios ni configuración."
  return 0
}
