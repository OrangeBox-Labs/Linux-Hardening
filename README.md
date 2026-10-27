# OrangeBox · Linux Hardening

> Scripts Bash de hardening y seguridad para servidores Linux Enterprise basados en CIS Benchmarks.

[![OrangeBox IT Services](https://img.shields.io/badge/OrangeBox-IT%20Services-ff6a00?style=for-the-badge)](https://www.orangebox.cl/)
[![Bash](https://img.shields.io/badge/Bash-tooling-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![CIS](https://img.shields.io/badge/CIS-security-0073c6?style=for-the-badge)](https://www.cisecurity.org/)

## Hardening de Linux con Bash y CIS Benchmarks

Colección de scripts de **Linux hardening** desarrollados por **OrangeBox IT Services** para asegurar servidores Linux Enterprise de forma reproducible, transparente y auditable.

El hardening cubre **SSH, sudo, PAM, contraseñas, auditd, kernel, filesystem/montajes, GRUB, sysctl de red, cron, rsyslog, servicios, AIDE, sincronización horaria y mitigaciones**. SELinux se informa, pero se cambia únicamente mediante su herramienta dedicada; la auditoría de firewalls/listeners es independiente y de solo lectura.

La idea es simple: código visible, comportamiento explícito y herramientas que un administrador Linux pueda revisar antes de aplicarlas.

> **Auditoría sin cambios. `--fix` automático con preflight, respaldos, validación y rollback.**

## 🚀 ¿Qué hay de nuevo?

Linux-Hardening está evolucionando hacia algo más útil que una colección de scripts que modifican archivos porque sí.

La filosofía de OrangeBox es separar claramente auditoría y aplicación. `--audit` no modifica el sistema; `--fix` asume sí a las propuestas de los módulos seleccionados, pero conserva preflight, respaldos, validaciones y rollback. El baseline informa SELinux y no invoca su herramienta dedicada. Los módulos de hardening nunca detectan ni modifican firewalls.

El estado detallado del proyecto está en [PROJECT-STATUS.md](PROJECT-STATUS.md), y el inventario de controles presentes/ausentes por dominio está en [CIS-COVERAGE-MAP.md](CIS-COVERAGE-MAP.md). El verificador CIS local implementa un subconjunto de controles; su porcentaje no representa cobertura completa ni certificación CIS.

### Continuidad de tareas y recuperación de sesión

El trabajo del repositorio tiene un checkpoint independiente del chat:

- [`.task-status.md`](.task-status.md): tarea activa, pendientes reales, contexto técnico, decisiones, riesgos, pruebas y siguiente acción exacta.
- [`.task-journal.md`](.task-journal.md): historial acumulativo; los hitos se agregan al final y no se borran.
- [`.github/TASK-RESUMPTION-PROTOCOL.md`](.github/TASK-RESUMPTION-PROTOCOL.md): procedimiento obligatorio para comenzar, actualizar, pausar, reanudar y cerrar tareas.

Al iniciar o retomar una tarea de este repositorio, lee primero el estado, después las últimas entradas del journal y luego verifica en GitHub branch/commit/PR/CI. Al completar un paso, registra evidencia en el journal y retíralo de la lista de pendientes; no mantengas tareas terminadas en esa lista. El workflow [Task state consistency](.github/workflows/task-state-check.yml) verifica la estructura de estos archivos en CI.

### Cambios recientes del baseline y los módulos

| Script / componente | Cambios y mejoras documentadas |
|---|---|
| `linux-hardening.sh` | Baseline 1.4.26: auditoría predeterminada de controles corregibles con estados `[OK]`/`[WARN]` y resumen de correctos, pendientes y errores. |
| `bash-hardening.sh` | Prompt con FQDN, prompt por rol, historial por usuario, permisos `0600`, recuperación de bindings Emacs/Readline, timeout de sesión y controles sobre operaciones comunes del historial. |
| `network-hardening.sh` | Hardening de sysctl de red, SYN flood, `rp_filter` y módulos del kernel. No inspecciona ni modifica firewalls. |
| `audit-listening-services.sh` | Inventario de listeners TCP/UDP por proceso y dirección, orientado a distinguir servicios locales de exposición real. |
| `audit-firewall-listeners.sh` | Auditoría independiente de gestores, backends, sockets y reglas INPUT. Solo lectura; fuera del flujo del baseline. |
| `lib/listener-firewall-audit.sh` | Biblioteca de correlación de listeners no-loopback con políticas y reglas verificables. Solo lectura. |
| `lib/firewall-detect.sh` | Detección de backends y escenarios como firewalld, nftables, iptables, CSF, Imunify360 y Shorewall. |
| `lib/sysctl-safe.sh` | Inventario de valores activos/persistentes, detección de conflictos, overrides centralizados y aprobación automática de cambios bajo `--fix`. |
| `kernel-hardening.sh` | Políticas explícitas para `fs.suid_dumpable`, `kernel.dmesg_restrict`, `kernel.kptr_restrict` y forwarding IPv4/IPv6 con confirmación individual. |
| `kernel-lpe-2026-mitigation.sh` | Mitigaciones específicas para escenarios LPE recientes, separadas del hardening general. |
| `ssh-hardening.sh` | Preflight de configuración efectiva antes de modificar parámetros SSH. |
| `ssh-hardening-complete.sh` | Hardening SSH avanzado con la misma política de comprobación previa y aplicación conservadora. |
| `sudo-hardening.sh` | Preflight de sudoers; `use_pty` se omite en cPanel y `--fix` aprueba automáticamente los cambios propuestos. |
| `auditd-hardening.sh` | Reglas persistentes verificadas antes de inmutabilidad; conserva rotación `ROTATE`, `space_left_action=SYSLOG` y `admin_space_left_action=SUSPEND`. |
| `rsyslog-hardening.sh` | Configura persistencia de journald cuando corresponde; no fuerza `ForwardToSyslog=yes` y reinicia servicios automáticamente tras cambios aplicados. |
| `logrotate-hardening.sh` | Normaliza `compress` y `rotate 5` en `/etc/logrotate.conf` y todos los archivos regulares de `/etc/logrotate.d`, con backup y validación. |
| `aide-install.sh` | AIDE es opcional y se ejecuta por selección explícita; bajo `--fix` las propuestas se aprueban automáticamente y se advierte el posible solapamiento con Wazuh FIM. |
| `selinux-secure-setup.sh` | Herramienta independiente para cambiar explícitamente a Permissive con confirmación, respaldo de `/etc/selinux/config` y sin reinicio automático. No se ejecuta desde el baseline. |
| `cron-hardening.sh` | Política conservadora con `cron.allow`/`at.allow` para evitar romper cPanel y otros entornos de hosting. |
| `FS-hardening.sh` | Controles de filesystem, montajes, módulos y autofs. No activa `hidepid=2`, para mantener la compatibilidad con Zabbix. |
| `grub-hardening.sh` | Hardening de arranque con advertencias por cambios que pueden requerir reinicio. |
| `configure-time-sync.sh` | Configuración de sincronización horaria con advertencia sobre cambios bruscos de tiempo y servicios dependientes. |
| `cpu-hardening.sh` | Mitigaciones relacionadas con CPU y uso del helper seguro de sysctl. |
| `remove-xinetd.sh` | Eliminación de componente legacy como módulo separado del baseline principal. |
| `remove-gui-hardening.sh` | Reducción opcional de superficie de ataque eliminando componentes GUI. |
| `generate-iptables-rules.sh` | Herramienta independiente fuera del baseline. No la invocan `linux-hardening.sh` ni `network-hardening.sh`. |
| `post-install.sh` | Preparación inicial; queda fuera de la auditoría agregada porque puede instalar paquetes o modificar configuración incluso sin `--fix`. |
| `cis-benchmark-check.sh` | Benchmark CIS independiente de la auditoría operacional de los módulos. |
| `linux-hardening-audit.sh` | Auditoría agregada de solo lectura; no ejecuta `--fix` ni mezcla su resultado con el porcentaje CIS. |

## 🧠 Hardening idempotente

El baseline global audita SSH, Bash, contraseñas/PAM, sudo, kernel, sysctl de red, auditd, cron/at, USB storage, GRUB, filesystem/montajes, rsyslog/journald y el estado de SELinux. No incluye la herramienta dedicada de SELinux ni operaciones de firewall. También ejecuta el módulo de rotación/compresión de logs. Cada módulo conserva su propio resumen.

Al ejecutar `--fix`, el orquestador transmite aprobación automática a los módulos: no pregunta por cada cambio. Los módulos mantienen preflight, respaldos, validaciones y rollback. `--fix` puede cambiar SSH, sysctl, montajes, auditoría, logging y políticas de cuentas; ejecuta primero `--audit` y revisa sus resultados. `--auto` se conserva como alias de `--fix`.

La sincronización horaria se evalúa en el baseline global, pero no se reconfigura con `--fix` general, porque modificar ntpd/chronyd puede afectar autenticación Kerberos/Samba AD, certificados y correlación temporal. Solo se trata si se selecciona explícitamente `--module time-sync --fix`.

Los módulos principales comprueban primero si el sistema ya cumple el objetivo.

Si un parámetro ya está correcto, se muestra `[OK]` y no se vuelve a modificar ni se solicita autorización innecesaria.

Esto permite ejecutar las comprobaciones repetidamente sin convertir cada ejecución en una aventura.

## 🔐 SSH con preflight

El módulo SSH siempre muestra los estados `[OK]` y `[WARN]` de los nueve controles del baseline en la auditoría compacta; no oculta los pendientes cuando no puede usar el directorio de drop-ins.

En `--fix`, los cambios propuestos se aprueban automáticamente y se intenta primero el drop-in únicamente si `sshd_config` lo incluye antes de cualquier bloque `Match`. Si esa vía no está disponible, el script crea un bloque gestionado al inicio de `/etc/ssh/sshd_config`, con backup previo. Después valida la sintaxis con `sshd -t`, comprueba los valores efectivos y recarga `sshd`; si la validación o la recarga falla, intenta revertir el cambio. No sobrescribe un drop-in existente.

Cuando no puede modificar los archivos con seguridad, la salida indica el motivo específico y muestra las directivas pendientes, dónde colocarlas y cómo validar/recargar SSH manualmente. Mantén abierta la sesión actual y prueba una segunda conexión antes de cerrar.

Esto evita dejar un mensaje genérico de “se mantiene en auditoría” sin explicar qué bloqueó la aplicación ni cómo resolverlo.

## 🧱 Kernel, sysctl y SYN flood

Los controles sysctl distinguen entre valor activo, persistente, configuración existente, configuración conflictiva y estados que no pueden verificarse con seguridad.

En auditoría se explican los cambios pendientes; en `--fix` se aplican automáticamente tras las validaciones correspondientes.

Los parámetros de forwarding IPv4/IPv6 ahora también se auditan en el baseline y el módulo de kernel independiente. El objetivo CIS es deshabilitarlos, pero **no se fuerzan automáticamente**: cambiar `net.ipv4.ip_forward` o `net.ipv6.conf.all.forwarding` puede interrumpir routing, NAT, VPN, gateways y redes de contenedores. En `--fix`, los parámetros propuestos se aprueban automáticamente tras el preflight; el modo auditoría permite revisar el impacto antes de aplicarlos. Si IPv4 forwarding se conserva, el baseline usa `rp_filter=2` (modo flexible) para reducir descartes de tráfico asimétrico.


Política OrangeBox para los controles principales:

```text
fs.suid_dumpable = 0
kernel.dmesg_restrict = 1
```

Para `kernel.kptr_restrict`, los valores activos `1` o `2` se consideran seguros y se conservan. Solo un valor `0` propone cambio a `1`; `--fix` aplica automáticamente la propuesta tras las validaciones.

La protección SYN flood revisa:

```text
net.ipv4.tcp_syncookies
net.ipv4.tcp_max_syn_backlog
net.core.somaxconn
```

El baseline no modifica automáticamente `net.ipv4.tcp_synack_retries` ni `net.ipv4.tcp_syn_retries`, porque esos parámetros dependen de latencia, pérdida, aplicaciones y política operacional.

El hardening también audita `net.ipv6.conf.{all,default}.accept_redirects`. Ignorar redirects ICMPv6 reduce cambios de ruta inducidos por terceros, pero puede afectar redes que dependan de ellos. `--fix` aplica automáticamente las propuestas; si el kernel no expone IPv6, se informa N/A.

Porque sí: el kernel también tiene derecho a no recibir tuning de TikTok.

## 🌐 Auditoría de firewall

Ejecuta esta función por separado:

```bash
./audit-firewall-listeners.sh
```

Esta auditoría ya no forma parte de `linux-hardening.sh` ni se mezcla con sus pendientes de hardening. El inventario identifica protocolo, dirección, puerto, proceso y servicio cuando la información está disponible.

El informe distingue actividad confirmada de mera instalación y presenta un gestor activo solo cuando existe evidencia observable. Detecta CSF, Shorewall, firewalld, el servicio nftables, iptables-services, UFW, backends iptables-nft/legacy y cadenas de integración de Imunify360. Si detecta varios gestores a la vez o ve reglas sin poder atribuirlas, lo advierte en vez de elegir uno a ciegas. Lista todos los listeners TCP/UDP, incluidos los locales, identifica el proceso/servicio cuando la información está disponible y contrasta cada listener remoto por protocolo, puerto y familia con las reglas INPUT legibles.

Los resultados se separan en cuatro estados:

- **Acceso permitido / exposición potencial:** hay una ruta de aceptación o la política efectiva deja pasar el tráfico; no significa que el servicio sea vulnerable, pero sí que debe validarse su exposición.
- **Acceso restringido/condicional:** se detectó una regla de permiso condicionada por origen, interfaz u otro alcance reconocible.
- **Bloqueado:** se identificó una política/regla de bloqueo que cubre el servicio.
- **Indeterminado:** la semántica o combinación de reglas no se puede resolver con certeza; no se presenta como protegido.

El auditor puede asociar riesgos típicos por proceso/puerto —por ejemplo, base de datos, Redis, SMB, FTP, SNMP, proxy, SSH o agentes de monitoreo— para ayudar a priorizar la revisión. Estas indicaciones son contextuales, no una afirmación automática de vulnerabilidad.

Esta función es **estrictamente de solo lectura**: nunca crea, elimina, modifica, habilita, reinicia ni recarga reglas, gestores o servicios de firewall. No intenta decidir ni aplicar qué puertos deberían estar abiertos.

No es:

> "Vi un puerto y me dio ansiedad, así que lo cerré."

## 🐚 Bash Hardening

El hardening de Bash incorpora:

- hostname FQDN
- prompt por usuario/rol
- hora en el prompt
- bindings Emacs/Readline
- historial por usuario
- permisos `0600`
- `HISTTIMEFORMAT`
- `histappend`
- timeout de sesión
- logging mediante syslog

El prompt permite identificar rápidamente una sesión root frente a una sesión normal.

El logging de comandos tiene una advertencia importante: **los argumentos de línea de comandos pueden contener secretos**. No deben pasarse contraseñas, tokens u otros secretos como argumentos cuando esta captura esté habilitada.

La protección del historial es de mejor esfuerzo y no constituye un mecanismo antimanipulación. Para auditoría resistente a alteraciones se recomienda una arquitectura de logging controlada/remota y los mecanismos apropiados de auditd.

## ⏱️ Timeout de sesiones

Las shells interactivas de usuarios distintos de `root` utilizan:

```text
TMOUT=120
```

El timeout es de 120 segundos de inactividad.

Las shells root eliminan el `TMOUT` heredado y el mecanismo no se aplica a shells no interactivas.

## 🧾 MOTD y banners

El proyecto diferencia claramente:

### Antes del login

`/etc/issue` y `/etc/issue.net` contienen el logo OrangeBox centrado (FIGlet generado al aplicar, o ASCII de fallback) y el aviso legal/de seguridad antes de la autenticación. El título y la web se centran en un ancho fijo de 79 columnas; los párrafos tienen una sangría uniforme.

### Después del login

`/etc/motd` queda vacío para evitar duplicados. El perfil `/etc/profile.d/99-orangebox-motd.sh` muestra primero el logo FIGlet (o ASCII de fallback) y luego la ficha de sesión en este orden: fecha/hora, IP externa, IP interna, IP del cliente, uptime, `Load`, RAM usada y swap usada en filas consecutivas y alineadas, y usuario efectivo al final. RAM y swap se muestran como cantidad usada/total en GiB y porcentaje; es una lectura del momento en que se abre la sesión, no un promedio histórico. RAM usa `MemAvailable` cuando existe y un cálculo compatible con kernels legacy como alternativa; si no hay swap configurada se indica expresamente. La IP externa se consulta con `curl` (o `wget`) a `ifconfig.me` con timeout máximo de 2 segundos; si no hay conectividad o la respuesta no es una IPv4 válida, muestra `No disponible`. Usa la misma paleta ANSI para todos los usuarios y no duplica el aviso de seguridad previo al login. En modo `--fix` se intenta instalar FIGlet desde repositorios ya configurados; no se habilitan repositorios ni se actualiza el sistema completo.

El banner SSH se valida con `sshd -t` y se recarga sin reiniciar el daemon.

Los banners no enumeran controles defensivos ni revelan el estado de SELinux.

## 🛡️ SELinux

`linux-hardening.sh` solo informa el estado runtime y persistente de SELinux. No cambia el modo, la configuración, los contextos ni los paquetes, y no ejecuta la herramienta dedicada.

Para cambiar explícitamente a Permissive, usa `./selinux-secure-setup.sh --fix`. La herramienta independiente solicita confirmación, respalda `/etc/selinux/config`, aplica `setenforce 0` si corresponde y no reinicia automáticamente. Si SELinux está Disabled o el kernel lo desactiva con `selinux=0`, se requiere planificación adicional.

## 🧩 AIDE y Wazuh

AIDE es opcional y no se instala por defecto en la ejecución global. Si seleccionas el módulo dedicado con `--module aide --fix`, `--fix` aprueba automáticamente la instalación/configuración propuesta tras el preflight.

El sistema informa la posible coexistencia con Wazuh FIM para evitar duplicar controles sin una razón clara.

`--auto` es un alias de `--fix`; AIDE solo se trata cuando se selecciona su módulo dedicado.

## 📋 Scripts

| Script | Área |
|---|---|
| `linux-hardening.sh` | Baseline 1.4.26; reporte de todos los controles corregibles, con estado y resumen. |
| `audit-firewall-listeners.sh` | Auditoría independiente de firewall y listeners, estrictamente de solo lectura. |
| `linux-hardening-audit.sh` | Auditoría agregada |
| `cis-benchmark-check.sh` | Benchmark CIS independiente |
| `post-install.sh` | Preparación inicial |
| `bash-hardening.sh` | Bash, profiles e historial |
| `ssh-hardening.sh` | Hardening SSH |
| `ssh-hardening-complete.sh` | Hardening avanzado SSH |
| `password-hardening.sh` | Contraseñas y políticas PAM |
| `sudo-hardening.sh` | sudo |
| `auditd-hardening.sh` | Auditoría |
| `selinux-secure-setup.sh` | Herramienta independiente: cambia a Permissive con confirmación y backup; no forma parte del baseline |
| `kernel-hardening.sh` | Kernel |
| `kernel-lpe-2026-mitigation.sh` | Mitigaciones LPE |
| `network-hardening.sh` | Red y sysctl |
| `FS-hardening.sh` | Sistema de archivos |
| `grub-hardening.sh` | GRUB |
| `cron-hardening.sh` | cron/at |
| `rsyslog-hardening.sh` | Logs |
| `aide-install.sh` | Integridad de archivos |
| `audit-listening-services.sh` | Servicios escuchando |
| `generate-iptables-rules.sh` | Generación de firewall; alto riesgo |
| `configure-time-sync.sh` | Sincronización horaria |
| `cpu-hardening.sh` | Mitigaciones CPU |
| `remove-xinetd.sh` | Eliminación de xinetd |
| `remove-gui-hardening.sh` | Reducción de superficie GUI |
| `disable-usb-storage.sh` | Control opcional de USB |
| `desintalar-paquetes-sin-usar.sh` | Limpieza de paquetes |
| `desintalar-servicios-sin-usar.sh` | Limpieza de servicios |
| `configure-login-banners.sh` | Banners de acceso |

## 🔎 Auditoría de módulos de hardening

Ejecutar:

```bash
./linux-hardening-audit.sh
```

Este programa consulta las comprobaciones operacionales de los módulos, fuerza `--check` donde corresponde y nunca pasa `--fix`.

No calcula ni incorpora el porcentaje CIS, no ejecuta `cis-benchmark-check.sh` y no crea backups ni reportes persistentes.

Los módulos de preparación, eliminación interactiva de paquetes/servicios y generación destructiva de reglas de firewall quedan excluidos.

## 🏆 Benchmark CIS independiente

El benchmark CIS es una evaluación separada de los chequeos operacionales de los módulos.

Ejecuta:

```bash
./cis-benchmark-check.sh
```

El porcentaje CIS proviene exclusivamente de los controles de `cis-benchmark-check.sh`. No se mezcla con advertencias, recomendaciones o estados internos de otros scripts.

Esto permite distinguir entre:

**"Cumple el benchmark CIS"**

y

**"Los controles operacionales de este servidor están actualmente correctos."**

No son exactamente lo mismo.

## 🚦 Orquestador unificado: `linux-hardening.sh`

### Auditar

```bash
./linux-hardening.sh
# Equivalente explícito
./linux-hardening.sh --audit
```

Muestra todos los controles del baseline con su estado individual: `[OK]` conforme, `[WARN]` pendiente o que requiere revisión, y `[N/A]` cuando no aplica a la plataforma o está excluido por política. Incluye los nueve parámetros SSH (cada uno se marca no verificable si no hay configuración/daemon utilizable) y el banner SSH, `sudoers`/`use_pty`, cada sysctl disponible y cada control IPv6 no aplicable, SYN flood, `Storage=persistent` y `/var/log/journal`, los cuatro archivos de banners/MOTD, cada control del perfil Bash (timeout, historial, protección frente a borrado, timestamp, permisos, Readline, FQDN, prompt y `PROMPT_COMMAND`), los dotfiles de historial (si son enlaces simbólicos se inspeccionan en auditoría pero no se reemplazan automáticamente; marcador, `HISTSIZE`, `HISTFILESIZE`, `HISTCONTROL`, `HISTIGNORE`, `histappend`, `HISTFILE` readonly/fallback y reglas `PROMPT_COMMAND`), los overrides en perfiles externos y el include de `/etc/bashrc`. Si falla la generación de temporales, los controles afectados aparecen igualmente como no verificables, no se omiten. También informa el estado opcional de AIDE (paquete, base y cron diario a las 05:00); la instalación se selecciona explícitamente. El resumen separa controles correctos, no aplicables, pendientes y errores. La auditoría no cambia archivos ni servicios. Firewall y listeners se auditan por separado con `./audit-firewall-listeners.sh` y `./audit-listening-services.sh`.

### Aplicar cambios automáticamente

```bash
./linux-hardening.sh --fix
```

Primero ejecuta los preflight de configuración efectiva. Después asume sí a las propuestas de los módulos seleccionados; valida cada cambio, respalda los archivos y revierte cuando una validación falla. No vuelve a preguntar por reinicios o recargas necesarios para aplicar cambios ya aprobados.

Si los valores ya cumplen, muestra `[OK]` sin pedir autorizaciones redundantes ni reescribirlos.

### Alias de compatibilidad

`./linux-hardening.sh --auto` equivale a `./linux-hardening.sh --fix`. Ambos asumen sí a las propuestas; revisa antes la salida de `--audit` y asegura un respaldo y una vía de recuperación.

### Módulos especializados

El orquestador permite seleccionar módulos de AIDE, auditd, Bash, sincronización horaria, CPU, cron, filesystem, GRUB, kernel, logrotate, mitigación LPE, sysctl de red, passwords, xinetd, GUI, rsyslog, SSH y sudo. SELinux se informa en el baseline; su herramienta independiente no forma parte de la selección global.

El benchmark CIS se ejecuta por separado.

Los scripts de eliminación de paquetes/servicios requieren selección manual. `post-install.sh` queda fuera del orquestador porque no dispone de una ruta de auditoría de solo lectura y puede instalar paquetes o modificar configuración incluso sin `--fix`.

SELinux no es un módulo de aplicación del baseline. El estado se informa; el cambio a Permissive se hace exclusivamente con la herramienta independiente `selinux-secure-setup.sh`.

## ⚠️ Controles de alto riesgo

| Módulo/script | Riesgo operacional |
|---|---|
| `generate-iptables-rules.sh` | Herramienta independiente de alto riesgo, fuera del baseline; puede vaciar reglas y establecer `INPUT DROP`. Este hardening nunca la ejecuta. |
| `kernel` / `synflood` / `network-full` | Cambios de kernel/sysctl pueden afectar VPN, forwarding, NAT, gateways, redes de contenedores, rutas asimétricas y aplicaciones. `--fix` aplica automáticamente las propuestas; revisa `--audit` antes. El módulo de red no toca firewalls. |
| `ssh-hardening.sh` / `ssh-hardening-complete.sh` | Pueden afectar clientes antiguos, automatizaciones y métodos de autenticación. |
| `FS-hardening.sh` | Opciones restrictivas de montaje, módulos y autofs pueden afectar aplicaciones. Se evita `hidepid=2` por compatibilidad con Zabbix. |
| `cron-hardening.sh` | Restricciones de cron/at pueden romper tareas de usuarios o cPanel. |
| `grub-hardening.sh` | Cambios de arranque pueden requerir reinicio y dejar un sistema inaccesible si se aplican incorrectamente. |
| `kernel-hardening.sh` / `kernel-lpe-2026-mitigation.sh` | Pueden cambiar sysctl, módulos o comportamiento del kernel. Forwarding IPv4/IPv6 queda detrás de confirmación individual porque puede interrumpir routing/NAT/VPN/gateways/containers. Validar rutas y consola de recuperación. |
| `auditd-hardening.sh` / `rsyslog-hardening.sh` | Pueden aumentar volumen de logs o afectar reglas y destinos existentes. |
| `configure-time-sync.sh` | Cambios bruscos de hora pueden afectar certificados, autenticación y correlación de logs. |
| `bash-hardening.sh` | Logging de comandos puede elevar volumen de logs y capturar argumentos sensibles. |
| Scripts de eliminación | Pueden eliminar dependencias, paquetes o servicios necesarios. Revisar inventario y reversión. |

Si el servidor es remoto, usa snapshot y consola fuera de banda antes de aplicar cambios automáticos de SSH, sysctl, filesystem, kernel o GRUB. Los firewalls están fuera del alcance del hardening.

## 🧪 Compatibilidad

El repositorio está orientado principalmente a **RHEL, CentOS, Rocky Linux, AlmaLinux y Fedora**.

La compatibilidad exacta depende de cada script. El proyecto no está diseñado como una colección genérica para Debian/Ubuntu: muchas políticas utilizan herramientas, PAM, SELinux, paquetes y rutas propias del ecosistema Red Hat.

### Matriz de pruebas

| Entorno | Propósito |
|---|---|
| CentOS 6 | Compatibilidad con generaciones antiguas |
| CentOS 7 | Compatibilidad con generaciones antiguas |
| AlmaLinux 8 | Validación RHEL-like actual |
| AlmaLinux 9 | Validación RHEL-like actual |
| AlmaLinux 10 | Validación RHEL-like actual |

Esta matriz es una **prueba de humo**, no una certificación completa de compatibilidad con cada versión de RHEL. No reproduce por sí sola el kernel del host, arranque, servicios activos, firewalls reales, cPanel/CloudLinux ni los efectos de `--fix`.

## 🔐 Seguridad antes de ejecutar

Los scripts de hardening modifican configuración del sistema.

**Prueba primero en laboratorio, snapshot o una máquina de validación.**

Antes de aplicar cambios revisa:

1. Acceso SSH y consola de emergencia.
2. Dependencias de las aplicaciones.
3. Firewall activo y proveedor de firewall.
4. cPanel/CloudLinux/Wazuh u otras plataformas instaladas.
5. Monitoreo y logging.
6. Backup y procedimiento de rollback.
7. Impacto esperado de cada módulo.

No todos los controles son adecuados para todos los servidores.

## 📚 Recursos OrangeBox

- Web: https://www.orangebox.cl/
- Blog técnico: https://www.orangebox.cl/blog/
- YouTube: https://www.youtube.com/@OrangeBoxLinux
- GitHub: https://github.com/OrangeBox-Labs

## 🔍 SEO / temas relacionados

Linux hardening, Linux security, Linux server hardening, RHEL hardening, Red Hat hardening, Rocky Linux security, Rocky Linux hardening, AlmaLinux security, AlmaLinux hardening, CentOS hardening, Fedora security, CIS Benchmark Linux, CIS hardening, SSH hardening, sudo hardening, SELinux security, auditd Linux, kernel hardening, filesystem hardening, GRUB hardening, firewall Linux, firewall hardening, Linux server security, seguridad servidores Linux, hardening servidores Linux, ciberseguridad Linux, infraestructura Linux empresarial, seguridad Linux Chile, OrangeBox Linux.

## 🏢 OrangeBox IT Services

**Felipe Román · OrangeBox IT Services**

Enterprise Linux · Linux Security · Hardening · CIS Benchmarks · RHEL · Rocky Linux · AlmaLinux · CentOS · Fedora

https://www.orangebox.cl/

## 🤝 Open Source

Este proyecto es open source y está pensado para que otros administradores Linux puedan revisar, adaptar y mejorar los controles.

Si encuentras un problema, incompatibilidad o una forma mejor de hacer un control, abre un issue o pull request.

Y si una mejora evita que alguien pierda acceso SSH en producción, probablemente sea una mejora bastante buena.

---

**MIT License**

Copyright (c) 2025 Felipe Roman - OrangeBox Labs


## MOTD dinámico por sesión

El banner de shell se genera al abrir una shell interactiva desde `/etc/profile.d/99-orangebox-motd.sh`. Muestra primero el logo FIGlet (o ASCII de fallback) y debajo fecha/hora local, IP externa, IP interna, IP del cliente, uptime desde `/proc/uptime`, seguida por las filas de `Load`, RAM usada y swap usada. La memoria se muestra como usada/total en GiB y porcentaje, calculada al inicio de sesión; no representa un promedio histórico. Se usa `MemAvailable` si el kernel lo expone y un fallback de compatibilidad para kernels antiguos; si no hay swap configurada se muestra `No configurada`. La IP externa se obtiene con `curl` o `wget` contra `ifconfig.me`, con timeout de hasta 2 segundos; ante fallo de red o una respuesta inválida muestra `No disponible`. La línea de usuario efectivo cierra la ficha. La fecha/hora aparece una sola vez, y el color de la ficha es uniforme para root y usuarios normales. El aviso de acceso restringido permanece en `/etc/issue` y `/etc/issue.net` antes de autenticar.

FIGlet se usa para generar el logo estático del banner previo a la autenticación. Durante `--fix`, si FIGlet o la fuente `small` no están disponibles, se intenta instalar desde los repositorios ya configurados. No se habilitan repositorios ni se actualiza el sistema completo. Si no puede instalarse, `/etc/issue` y `/etc/issue.net` reciben un logo ASCII embebido. El uptime y la carga del panel de shell se obtienen de `/proc`, compatibles con CentOS 6.


### Limitación de la IP remota antes del login

El `Banner` estándar de OpenSSH envía el contenido estático de `/etc/issue.net`; no expande una variable distinta por conexión. Por eso el aviso previo al login no puede imprimir la IP concreta del cliente usando solamente ese archivo. La IP de origen debe verificarse en los registros de autenticación SSH. El panel de shell muestra la IP interna del servidor a la que se conectó el cliente.


### Compatibilidad adicional con CentOS/RHEL 6

El auditor de listeners consulta `ss -lntup` sin depender de la opción `-H` no disponible en algunas versiones antiguas y usa `netstat -lntup` como alternativa cuando `ss` no entrega datos. Las cabeceras se ignoran y las direcciones IPv4 no se clasifican como IPv6.

En CentOS/RHEL 6, la persistencia de los parámetros sysctl apunta a `/etc/sysctl.conf`; no se crea `/etc/sysctl.d`. Cada modificación sigue requiriendo confirmación por parámetro. La comprobación de logs verifica `rsyslog` en lugar de exigir `systemd-journald` en ese sistema legacy.


### Auditoría legacy CentOS/RHEL 6

Las comprobaciones reconocen el stack SysV de `auditd` y `ntpd`, el archivo de GRUB legacy `/boot/grub/grub.conf` y la ausencia esperada de `update-crypto-policies` en EL6/EL7. Los parámetros sysctl que no existen en el kernel quedan como información de incompatibilidad y no como controles corregibles. Estas comprobaciones son de solo lectura; no activan servicios ni alteran el arranque.

En CentOS/RHEL 6 el control de PAM busca `pam_tally2`, mientras que las versiones modernas siguen comprobando `pam_faillock`. La comprobación no edita archivos PAM ni activa mecanismos de bloqueo.
