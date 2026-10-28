# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x network-hardening.sh
```

# Script: network-hardening.sh

Script para aplicar hardening de red segun CIS Benchmark secciones 3.2.x, 3.3.x y 3.4.x.
NO modifica reglas de firewall, solo configura parametros del kernel para su comportamiento ante estos ataques y deshabilita algunos modulos potencialmente peligrosos.

## Uso

```
chmod +x network-hardening.sh

./network-hardening.sh

./network-hardening.sh --fix
```

## Opciones

sin opciones o --fix: Aplica las correcciones
--check: Solo verificacion (no aplica cambios)

## Que hace cada control

### 3.2.2 - Deshabilitar envio de redirecciones ICMP

Parametros modificados:
  net.ipv4.conf.all.send_redirects = 0
  net.ipv4.conf.default.send_redirects = 0

Que previene: Un atacante que comprometa el sistema no podra usarlo para redirigir trafico de red hacia sus propios equipos (ataques MITM - Man In The Middle).

Impacto: El sistema no enviara mensajes ICMP Redirect. Esto es seguro porque un servidor normal no necesita actuar como router.

### 3.3.1 - Deshabilitar paquetes con enrutamiento origen

Parametros modificados:
```
  net.ipv4.conf.all.accept_source_route = 0
  net.ipv4.conf.default.accept_source_route = 0
  net.ipv6.conf.all.accept_source_route = 0
  net.ipv6.conf.default.accept_source_route = 0
```

Que previene: Un atacante no puede especificar la ruta que deben seguir los paquetes para saltar medidas de seguridad (ataques de spoofing y redireccion).

Impacto: El sistema ignora cualquier informacion de enrutamiento incluida en los paquetes. Comportamiento normal para un servidor que no realiza funciones de routing.

### 3.3.3 - Deshabilitar redirecciones ICMP seguras

Parametros modificados:
```
  net.ipv4.conf.all.secure_redirects = 0
  net.ipv4.conf.default.secure_redirects = 0
```

Que previene: Incluso si un gateway esta en la lista de gateways conocidos, si es comprometido no podra modificar la tabla de enrutamiento del sistema.

Impacto: El sistema ignora redirecciones ICMP incluso de gateways confiables. Previene que un router legitimo pero comprometido redirija trafico.

### 3.3.4 - Registro de paquetes sospechosos (Martians)

**Política OrangeBox: desactivado por defecto.** Registrar paquetes con direcciones de origen no enrutables puede generar un volumen excesivo de logs y consumir espacio rápidamente en servidores con tráfico alto.

El script conserva `net.ipv4.conf.all.log_martians = 0` y `net.ipv4.conf.default.log_martians = 0`. Si un servidor necesita esta telemetría para una investigación concreta, debe habilitarse como excepción operativa explícita y con límites/retención de logs revisados; no se activa como parte del baseline general.
### 3.3.5 - Ignorar peticiones ICMP broadcast

Parametros modificados:
```
  net.ipv4.icmp_echo_ignore_broadcasts = 1
```

Que previene: Ataques Smurf donde un atacante envia ICMP echo a direcciones broadcast y amplifica el trafico hacia la victima.

Impacto: El sistema no responde a pings enviados a direcciones broadcast. Completamente seguro para un servidor.

### 3.3.6 - Ignorar respuestas ICMP falsas

Parametros modificados:
```
  net.ipv4.icmp_ignore_bogus_error_responses = 1
```

Que previene: Que logs del sistema se llenen con respuestas ICMP que no cumplen con el estandar RFC-1122.

Impacto: El kernel no registra respuestas ICMP mal formadas. Evita que un atacante llene el disco con logs inutiles.

### 3.3.7 - Habilitar filtrado de ruta inversa (rp_filter)

Parametros modificados:
```
  net.ipv4.conf.all.rp_filter = 1 (servidor no-router)
  net.ipv4.conf.default.rp_filter = 1 (servidor no-router)
```

Si `net.ipv4.ip_forward=1`, el script usa `rp_filter=2` (modo loose) para reducir el riesgo de descartar tráfico legítimo en firewalls o rutas asimétricas. En el orquestador, este control se aplica solo después de confirmación individual en modo `--fix` interactivo; `--fix --auto` lo deja en auditoría.

Que previene: Ataques de spoofing donde un atacante envia paquetes con IP de origen falsa. El kernel verifica que el paquete llegue por la interfaz que usaria para responder.

Impacto: El sistema descarta paquetes que llegan por una interfaz que no es la correcta segun la tabla de enrutamiento.

⚠️ ADVERTENCIA: Puede causar problemas si su red utiliza enrutamiento asimetrico (BGP, OSPF). En ese caso, mantener rp_filter = 0 o 2.

### 3.3.8 - Habilitar SYN Cookies y revisar las colas TCP

Parametros que propone el baseline:
```
  net.ipv4.tcp_syncookies = 1
  net.ipv4.tcp_max_syn_backlog = 4096
  net.core.somaxconn = 4096
```

El baseline **no modifica automáticamente** `net.ipv4.tcp_synack_retries` ni `net.ipv4.tcp_syn_retries`. Estos parámetros controlan los reintentos TCP y su valor adecuado depende de la tolerancia a pérdida/latencia, del patrón de conexiones y de la política del proveedor (por ejemplo, cPanel/CloudLinux). Se preservan los valores existentes; cualquier ajuste debe tratarse como tuning independiente, respaldado por métricas y validación operativa.

Que previene: `tcp_syncookies=1` permite al kernel usar SYN cookies cuando la cola de conexiones pendientes se desborda; los parámetros de backlog ajustan las colas de conexiones pendientes y completadas.

Impacto: No se debe asumir que un valor de backlog es óptimo para todas las cargas. Revise contadores TCP, límites de las aplicaciones y uso de recursos antes de cambiar valores. SYN cookies son un mecanismo de respaldo ante el desbordamiento de la cola, no un sustituto de diagnosticar una sobrecarga causada por tráfico legítimo.

### 3.3.9 - Deshabilitar anuncios de router IPv6

Parametros modificados (si IPv6 esta habilitado):
```
  net.ipv6.conf.all.accept_ra = 0
  net.ipv6.conf.default.accept_ra = 0
```

Que previene: Un atacante en la red local puede enviar anuncios de router (Router Advertisements) maliciosos para redirigir el trafico IPv6.

Impacto: El sistema ignora cualquier anuncio de router IPv6. El administrador debe configurar rutas estaticas si son necesarias.

### 3.4.1 - Deshabilitar DCCP

Modulo afectado: dccp (Datagram Congestion Control Protocol)

Que previene: Reducir superficie de ataque eliminando protocolos no utilizados. DCCP se usa para streaming multimedia (voz, video).

Impacto: No afecta a servidores estandar. Si alguna aplicacion necesita DCCP, dejara de funcionar.

### 3.4.2 - Deshabilitar SCTP

Modulo afectado: sctp (Stream Control Transmission Protocol)

Que previene: Reducir superficie de ataque eliminando protocolos no utilizados. SCTP se usa en telefonia IP (SIGTRAN, VoIP).

Impacto: No afecta a servidores estandar. Si alguna aplicacion necesita SCTP (ej. servidor de telefonia), dejara de funcionar.

## Verificacion post-ejecucion

Verificar parametros del kernel:

```
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.conf.all.accept_source_route
sysctl net.ipv4.conf.all.secure_redirects
sysctl net.ipv4.conf.all.log_martians
sysctl net.ipv4.tcp_syncookies
sysctl net.ipv4.conf.all.rp_filter
```

Verificar modulos deshabilitados:

```
lsmod | grep -E 'dccp|sctp'
```

Verificar logs de martians:

```
grep -i 'martian' /var/log/messages
```

## Conflictos de firewall

El script tambien verifica si hay multiples firewalls activos (firewalld, nftables, iptables). Tener mas de uno activo puede causar conflictos.

No modifica las reglas de firewall. Solo informa si hay conflictos.

## Backup

Las configuraciones se respaldan en /root/network-backup-fecha/

Los cambios aprobados de sysctl se centralizan en `/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf`, compartido con los demás módulos OrangeBox y ordenado para tener alta precedencia. El script inventaría las definiciones existentes y pide confirmación por parámetro si el valor activo o persistente es distinto; los perfiles de Google Cloud, cPanel y CloudLinux se conservan sin editar. Si `/etc/sysctl.conf` contiene una asignación conflictiva, se consulta explícitamente antes de actualizar solo esa asignación.

Para restaurar un backup, copia el archivo correspondiente desde el directorio `/root/network-backup-fecha/` y valida los valores antes de recargar sysctl.

## Autor

Felipe Roman
Web: www.orangebox.cl
Email: froman@orangebox.cl

## Licencia

MIT


---

**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs
