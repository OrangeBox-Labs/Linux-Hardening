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

### 3.3.4 - Loggear paquetes sospechosos (Martians)

**👽 Martian**: Un paquete que llegó de una dirección IP que no debería existir en tu red. Tu servidor lo mira y dice "esto es marciano" y lo bota.

> ⚠️ **Ojo**: Loggear martians puede llenar /var en minutos. Mejor tener una partición separada o vas a amanecer con el disco lleno de basura espacial.

Parametros modificados:
```
  net.ipv4.conf.all.log_martians = 1
  net.ipv4.conf.default.log_martians = 1
```

Que previene: Registra en /var/log/messages los paquetes con direcciones origen no validas (spoofing). Permite detectar intentos de ataque.

Impacto: Se generan entradas en los logs. No afecta el funcionamiento normal. Los logs pueden revisarse con: grep -i 'martian' /var/log/messages

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
  net.ipv4.conf.all.rp_filter = 1
  net.ipv4.conf.default.rp_filter = 1
```

Que previene: Ataques de spoofing donde un atacante envia paquetes con IP de origen falsa. El kernel verifica que el paquete llegue por la interfaz que usaria para responder.

Impacto: El sistema descarta paquetes que llegan por una interfaz que no es la correcta segun la tabla de enrutamiento.

⚠️ ADVERTENCIA: Puede causar problemas si su red utiliza enrutamiento asimetrico (BGP, OSPF). En ese caso, mantener rp_filter = 0 o 2.

### 3.3.8 - Habilitar SYN Cookies

Parametros modificados:
```
  net.ipv4.tcp_syncookies = 1
```

Que previene: Ataques de denial of service por inundacion SYN (SYN flood). El atacante envia muchas solicitudes de conexion sin completarlas, agotando la cola del sistema.

Impacto: Cuando la cola de conexiones pendientes se llena, el kernel usa SYN cookies para seguir aceptando conexiones legitimas. No afecta el rendimiento normal.

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

Para restaurar backup: cp /root/network-backup-fecha/sysctl.conf /etc/sysctl.d/99-network-hardening.conf

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
