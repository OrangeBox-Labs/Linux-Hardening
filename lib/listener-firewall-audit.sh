#!/usr/bin/env bash
# Auditoría de solo lectura: contrasta sockets expuestos con políticas INPUT.
# Nunca ejecuta comandos que modifiquen reglas ni servicios de firewall.

lfa_iptables_text_state() {
  local dump="$1" protocol="$2" port="$3"
  printf '%s\n' "$dump" | awk -v wp="$protocol" -v p="$port" '
    function target(line,a,n,i) { n=split(line,a,/[[:space:]]+/); for(i=1;i<n;i++) if(a[i]=="-j"||a[i]=="-g") return a[i+1]; return "" }
    function builtin(t) { return t ~ /^(ACCEPT|DROP|REJECT|RETURN|QUEUE|NFQUEUE|LOG|ULOG|DNAT|SNAT|MASQUERADE|REDIRECT|NOTRACK|CT|MARK|CONNMARK|TRACE|CHECKSUM|SECMARK|CONNSECMARK)$/ }
    function jump_uncond(line,t) { t=target(line); return t!=""&&!builtin(t)&&line ~ /^-A [^[:space:]]+ -[jg] [^[:space:]]+[[:space:]]*$/ }
    function terminal_uncond(line,t) {
      t=target(line)
      if(t=="DROP"||t=="RETURN"||t=="ACCEPT") return line ~ ("^-A [^[:space:]]+ -j " t "[[:space:]]*$")
      if(t=="REJECT") return line ~ /^-A [^[:space:]]+ -j REJECT([[:space:]]+--reject-with[[:space:]]+[[:alnum:]_-]+)?[[:space:]]*$/
      return 0
    }
    function port_spec(spec,wanted,a,n,i,pair) {
      gsub(/[{}[:space:]]/,"",spec); n=split(spec,a,",")
      for(i=1;i<=n;i++) {
        if(a[i] ~ /^[0-9]+:[0-9]+$/) { split(a[i],pair,":"); if(wanted+0>=pair[1]+0&&wanted+0<=pair[2]+0)return 1 }
        else if(a[i] ~ /^[0-9]+-[0-9]+$/) { split(a[i],pair,"-"); if(wanted+0>=pair[1]+0&&wanted+0<=pair[2]+0)return 1 }
        else if(a[i] ~ /^[0-9]+$/&&a[i]+0==wanted+0)return 1
      }
      return 0
    }
    function has_port(line,proto,wanted,a,n,i,rp,spec) {
      if(line ~ /(^|[[:space:]])(-s|--source|-d|--destination|-i|--in-interface|-o|--out-interface|--match-set)([[:space:]]|$)/) return 0
      n=split(line,a,/[[:space:]]+/); rp=""
      for(i=1;i<n;i++)if(a[i]=="-p"){rp=a[i+1];break}
      if(rp!=proto&&!(proto=="tcp"&&rp=="6")&&!(proto=="udp"&&rp=="17"))return 0
      for(i=1;i<=n;i++) {
        if(a[i]=="--dport"||a[i]=="--dports"||a[i]=="--destination-port"||a[i]=="--destination-ports") {
          if(i<n&&port_spec(a[i+1],wanted))return 1
        } else if(a[i] ~ /^--dport=/) { spec=a[i];sub(/^--dport=/,"",spec);if(port_spec(spec,wanted))return 1 }
        else if(a[i] ~ /^--dports=/) { spec=a[i];sub(/^--dports=/,"",spec);if(port_spec(spec,wanted))return 1 }
      }
      return 0
    }
    BEGIN { in_filter=0; nr=0; policy=""; seen=0 }
    $0=="*filter" { in_filter=1;next }
    $0=="COMMIT" { in_filter=0;next }
    !in_filter { next }
    $1 ~ /^:/ { c=$1;sub(/^:/,"",c);exists[c]=1;if(c=="INPUT"){seen=1;policy=$2};next }
    $1=="-A" { nr++;rules[nr]=$0;rc[nr]=$2 }
    END {
      if(!seen){print "UNKNOWN";exit}
      if(policy=="DROP"||policy=="REJECT"){print "CONTROLLED";exit}
      reachable["INPUT"]=1
      for(pass=1;pass<=nr;pass++)for(i=1;i<=nr;i++)if(reachable[rc[i]]&&jump_uncond(rules[i])){t=target(rules[i]);if(exists[t])reachable[t]=1}
      for(c in reachable)for(i=1;i<=nr;i++)if(rc[i]==c&&terminal_uncond(rules[i])){t=target(rules[i]);if(t=="DROP"||t=="REJECT"){print "CONTROLLED";exit};if(t=="ACCEPT"||t=="RETURN")break}
      for(i=1;i<=nr;i++)if(reachable[rc[i]]&&has_port(rules[i],wp,p)){print "CONTROLLED";exit}
      if(policy=="ACCEPT")print "UNCONTROLLED";else print "UNKNOWN"
    }'
}

lfa_nft_text_state() {
  local rules="$1" family="$2" protocol="$3" port="$4"
  printf '%s\n' "$rules" | awk -v wf="$family" -v wp="$protocol" -v p="$port" '
    function target(line,a,n,i){n=split(line,a,/[[:space:]]+/);for(i=1;i<n;i++)if(a[i]=="jump"||a[i]=="goto")return a[i+1];return ""}
    function family_matches(tf,wf){return tf=="inet"||(wf=="ipv4"&&tf=="ip")||(wf=="ipv6"&&tf=="ip6")}
    function strip_counter(s){sub(/^[[:space:]]*/,"",s);sub(/^counter packets [0-9]+ bytes [0-9]+[[:space:]]*/,"",s);return s}
    function jump_uncond(line,s){s=strip_counter(line);return s~/^(jump|goto)[[:space:]]+[[:alnum:]_.-]+[[:space:]]*$/}
    function terminal_uncond(line,s){s=strip_counter(line);return s~/^drop[[:space:]]*;?$/||s~/^reject([[:space:]]+with[[:space:]].*)?;?$/}
    function has_restriction(line){return line~/((^|[[:space:]])(ip saddr|ip daddr|ip6 saddr|ip6 daddr|iifname|oifname|ether saddr|ether daddr)([[:space:]]|$))/}
    function port_spec(spec,wanted,a,n,i,pair){gsub(/[{}[:space:]]/,"",spec);n=split(spec,a,",");for(i=1;i<=n;i++){if(a[i]~/^[0-9]+-[0-9]+$/){split(a[i],pair,"-");if(wanted+0>=pair[1]+0&&wanted+0<=pair[2]+0)return 1}else if(a[i]~/^[0-9]+:[0-9]+$/){split(a[i],pair,":");if(wanted+0>=pair[1]+0&&wanted+0<=pair[2]+0)return 1}else if(a[i]~/^[0-9]+$/&&a[i]+0==wanted+0)return 1}return 0}
    function has_port(line,proto,wanted,s,pos,spec,a) {
      if(has_restriction(line)||line!~/(^|[[:space:]])(accept|drop|reject|jump|goto|return)([[:space:];]|$)/)return 0
      if(proto=="tcp"&&line!~/(^|[[:space:]])tcp[[:space:]]+dport([[:space:]]|$)/)return 0
      if(proto=="udp"&&line!~/(^|[[:space:]])udp[[:space:]]+dport([[:space:]]|$)/)return 0
      pos=index(line,proto " dport");if(!pos)return 0
      s=substr(line,pos+length(proto " dport"));sub(/^[[:space:]]*/,"",s)
      if(substr(s,1,1)=="!"||substr(s,1,2)=="!=")return 0
      if(substr(s,1,1)=="{"){if(index(s,"}")==0)return 0;spec=substr(s,2,index(s,"}")-2)}
      else{split(s,a,/[[:space:]]+/);spec=a[1]}
      return port_spec(spec,wanted)
    }
    BEGIN{table="";tf="";ck="";nr=0;input_seen=0}
    $1=="table"{tf=$2;tn=$3;gsub(/[{}]/,"",tn);table=tf ":" tn;ck="";next}
    $1=="chain"{cn=$2;gsub(/[{}]/,"",cn);ck=table ":" cn;exists[ck]=1;ctable[ck]=table;cfamily[ck]=tf;next}
    /^[[:space:]]*}[[:space:]]*$/ {ck="";next}
    ck!="" {
      if(!family_matches(tf,wf))next
      if($0~/hook[[:space:]]+input/){input_seen=1;base[ck]=1;if($0~/policy[[:space:]]+(drop|reject)([[:space:];]|$)/){found_control=1;exit}}
      else{nr++;rules[nr]=$0;rc[nr]=ck}
    }
    END{
      if(found_control){print "CONTROLLED";exit}
      if(!input_seen){print "UNKNOWN";exit}
      for(c in base)reachable[c]=1
      for(pass=1;pass<=nr;pass++)for(i=1;i<=nr;i++)if(reachable[rc[i]]){t=target(rules[i]);nc=ctable[rc[i]] ":" t;if(t!=""&&jump_uncond(rules[i])&&exists[nc])reachable[nc]=1}
      for(c in reachable)for(i=1;i<=nr;i++)if(rc[i]==c&&terminal_uncond(rules[i])){print "CONTROLLED";exit}
      for(i=1;i<=nr;i++)if(reachable[rc[i]]&&has_port(rules[i],wp,p)){print "CONTROLLED";exit}
      print "UNCONTROLLED"
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

lfa_family_port_state() {
  local family="$1" protocol="$2" port="$3"
  local ip_state=UNKNOWN nft_state=UNKNOWN ip_rules=""
  if [ "${LFA_FIREWALL_SNAPSHOT_LOADED:-false}" != true ]; then
    lfa_load_firewall_snapshots
  fi
  case "$family" in
    ipv4) [ "$LFA_IPV4_RULES_AVAILABLE" = true ] && ip_rules="$LFA_IPV4_RULES" ;;
    ipv6) [ "$LFA_IPV6_RULES_AVAILABLE" = true ] && ip_rules="$LFA_IPV6_RULES" ;;
    *) printf '%s\n' UNKNOWN; return 0 ;;
  esac
  if [ -n "$ip_rules" ]; then
    ip_state="$(lfa_iptables_text_state "$ip_rules" "$protocol" "$port")"
  fi
  if [ "$LFA_NFT_RULES_AVAILABLE" = true ]; then
    nft_state="$(lfa_nft_text_state "$LFA_NFT_RULES" "$family" "$protocol" "$port")"
  fi
  if [ "$ip_state" = CONTROLLED ] || [ "$nft_state" = CONTROLLED ]; then
    printf '%s\n' CONTROLLED
  elif [ "$ip_state" = UNCONTROLLED ] || [ "$nft_state" = UNCONTROLLED ]; then
    printf '%s\n' UNCONTROLLED
  else
    printf '%s\n' UNKNOWN
  fi
}

lfa_audit_listener_firewall() {
  local line protocol state recvq sendq local_addr peer rest port process families family assessment
  local sockets=0 checked=0 controlled=0 unprotected=0 unknown=0 skipped=0
  LFA_WARNINGS=0
  if ! command -v ss >/dev/null 2>&1; then
    echo "[INFO] ss no está disponible; no se puede correlacionar listeners con INPUT. Firewall intacto."
    return 0
  fi
  local socket_output
  if ! socket_output="$(ss -H -lntup 2>/dev/null)"; then
    echo "[INFO] No se pudo consultar ss; no se puede verificar la cobertura INPUT. Firewall intacto."
    return 0
  fi
  lfa_load_firewall_snapshots
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    IFS=' ' read -r protocol state recvq sendq local_addr peer rest <<< "$line"
    [ -n "$protocol" ] && [ -n "$local_addr" ] || { skipped=$((skipped+1));continue; }
    port="${local_addr##*:}"
    [[ "$port" =~ ^[0-9]+$ ]] || { skipped=$((skipped+1));continue; }
    process="$(printf '%s\n' "$line" | sed -n 's/.*users:((\"//;t got;b;:got s/\".*//;p')"
    [ -n "$process" ] || process=desconocido
    sockets=$((sockets+1))
    case "$local_addr" in 127.*:*|localhost:*|'[::1]:'*|'::1:'*) continue ;; esac
    case "$local_addr" in
      '0.0.0.0:'*) families="ipv4" ;;
      '[::]:'*|'::: '*|':::'*) families="ipv6" ;;
      '*:'*) families="ipv4 ipv6" ;;
      *)
        if [[ "$local_addr" == *"["* || "$(printf '%s' "$local_addr" | tr -cd ':' | wc -c)" -gt 1 ]]; then families="ipv6"; else families="ipv4"; fi
        ;;
    esac
    for family in $families; do
      [ "$family" != ipv6 ] || [ -d /proc/sys/net/ipv6 ] || continue
      assessment="$(lfa_family_port_state "$family" "$protocol" "$port")"
      case "$assessment" in
        CONTROLLED) controlled=$((controlled+1));checked=$((checked+1)) ;;
        UNCONTROLLED)
          unprotected=$((unprotected+1));checked=$((checked+1));LFA_WARNINGS=$((LFA_WARNINGS+1))
          printf '[WARN] Servicio escuchando sin control INPUT detectado: %s/%s en %s (%s), familia %s. Revisar reglas efectivas; no se aplican cambios.\n' "$protocol" "$port" "$local_addr" "$process" "$family"
          ;;
        *)
          unknown=$((unknown+1))
          printf '[INFO] Control INPUT indeterminado para %s/%s en %s (%s), familia %s; no se genera WARN sin evidencia suficiente.\n' "$protocol" "$port" "$local_addr" "$process" "$family"
          ;;
      esac
    done
  done <<< "$socket_output"
  [ "$sockets" -gt 0 ] || echo "[INFO] No se encontraron sockets TCP/UDP en escucha."
  [ "$skipped" -eq 0 ] || echo "[INFO] Sockets omitidos por formato no reconocido: $skipped"
  printf '[INFO] Auditoría de listeners/INPUT: sockets=%s; familias verificadas=%s; controladas=%s; sin control detectado=%s; indeterminadas=%s.\n' "$sockets" "$checked" "$controlled" "$unprotected" "$unknown"
  echo "[INFO] Solo lectura: no se modificaron CSF, Imunify360, iptables, nftables ni servicios."
  return 0
}
