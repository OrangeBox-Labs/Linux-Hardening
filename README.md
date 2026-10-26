# OrangeBox · Linux Hardening

> Scripts Bash de hardening y seguridad para servidores Linux Enterprise basados en CIS Benchmarks.

[![OrangeBox IT Services](https://img.shields.io/badge/OrangeBox-IT%20Services-ff6a00?style=for-the-badge)](https://www.orangebox.cl/)
[![Bash](https://img.shields.io/badge/Bash-tooling-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![CIS](https://img.shields.io/badge/CIS-security-0073c6?style=for-the-badge)](https://www.cisecurity.org/)

## Hardening de Linux con Bash y CIS Benchmarks

Colección de scripts de **Linux hardening** desarrollados por **OrangeBox IT Services** para asegurar servidores Linux Enterprise de forma reproducible, transparente y auditable.

El proyecto cubre **SSH, sudo, PAM, passwords, auditd, SELinux, kernel, filesystem, GRUB, red, cron, rsyslog, servicios, AIDE, sincronización horaria, firewalls y mitigaciones de seguridad**.

La idea es simple: código visible, comportamiento explícito y herramientas que un administrador Linux pueda revisar antes de aplicarlas.

> **Primero comprobar. Después preguntar. Finalmente cambiar.**

## 🚀 ¿Qué hay de nuevo?

Linux-Hardening está evolucionando hacia algo más útil que una colección de scripts que modifican archivos porque sí.

La filosofía actual de OrangeBox es bastante simple: **primero comprobar, después preguntar y finalmente cambiar**. El baseline incorpora controles de idempotencia, preflight de configuración efectiva, auditorías de solo lectura y políticas especiales para ambientes donde romper SSH a las 3 de la mañana no es precisamente una feature.

### Cambios recientes del baseline y los módulos

| Script / componente | Cambios y mejoras documentadas |
|---|---|
| `linux-hardening.sh` | Baseline 1.4.10, detección y persistencia SYSCTL legacy, parser de listeners compatible con CentOS 6 y verificación syslog sin journald. |
| `bash-hardening.sh` | Prompt con FQDN, prompt por rol, historial por usuario, permisos `0600`, recuperación de bindings Emacs/Readline, timeout de sesión y controles sobre operaciones comunes del historial. |
| `network-hardening.sh` | Hardening sysctl de red, SYN flood, `rp_filter`, detección de firewalls y auditoría de cobertura INPUT sin modificar reglas del firewall. |
| `audit-listening-services.sh` | Inventario de listeners TCP/UDP por proceso y dirección, orientado a distinguir servicios locales de exposición real. |
| `lib/listener-firewall-audit.sh` | Correlación de listeners no-loopback con políticas y reglas de filtrado verificables. Solo lectura. |
| `lib/firewall-detect.sh` | Detección de backends y escenarios como firewalld, nftables, iptables, CSF, Imunify360 y Shorewall. |
| `lib/sysctl-safe.sh` | Inventario de valores activos/persistentes, detección de conflictos, overrides centralizados y confirmación individual antes de cambios. |
| `kernel-hardening.sh` | Políticas explícitas para `fs.suid_dumpable`, `kernel.dmesg_restrict` y `kernel.kptr_restrict`. |
| `kernel-lpe-2026-mitigation.sh` | Mitigaciones específicas para escenarios LPE recientes, separadas del hardening general. |
| `ssh-hardening.sh` | Preflight de configuración efectiva antes de modificar parámetros SSH. |
| `ssh-hardening-complete.sh` | Hardening SSH avanzado con la misma política de comprobación previa y aplicación conservadora. |
| `sudo-hardening.sh` | `use_pty` requiere confirmación específica y se omite en hosts cPanel. |
| `auditd-hardening.sh` | Auditoría reforzada y separación entre comprobación y aplicación. |
| `rsyslog-hardening.sh` | Evita reconfigurar o preguntar cuando journald ya cumple el objetivo. |
| `aide-install.sh` | AIDE es opcional y requiere consentimiento en `--fix`; se advierte posible solapamiento con Wazuh FIM. |
| `selinux-secure-setup.sh` | Auditoría de solo lectura. No cambia modo, configuración, contextos, paquetes ni reinicia el sistema. |
| `cron-hardening.sh` | Política conservadora con `cron.allow`/`at.allow` para evitar romper cPanel y otros entornos de hosting. |
| `FS-hardening.sh` | Controles sobre filesystem, montajes, `hidepid`, módulos y autofs con advertencias de impacto operacional. |
| `grub-hardening.sh` | Hardening de arranque con advertencias por cambios que pueden requerir reinicio. |
| `configure-time-sync.sh` | Configuración de sincronización horaria con advertencia sobre cambios bruscos de tiempo y servicios dependientes. |
| `cpu-hardening.sh` | Mitigaciones relacionadas con CPU y uso del helper seguro de sysctl. |
| `remove-xinetd.sh` | Eliminación de componente legacy como módulo separado del baseline principal. |
| `remove-gui-hardening.sh` | Reducción opcional de superficie de ataque eliminando componentes GUI. |
| `generate-iptables-rules.sh` | Módulo de alto riesgo; no forma parte del flujo automático y puede cortar acceso remoto si se usa incorrectamente. |
| `post-install.sh` | Preparación inicial; queda fuera de la auditoría agregada porque puede instalar paquetes o modificar configuración incluso sin `--fix`. |
| `cis-benchmark-check.sh` | Benchmark CIS independiente de la auditoría operacional de los módulos. |
| `linux-hardening-audit.sh` | Auditoría agregada de solo lectura; no ejecuta `--fix` ni mezcla su resultado con el porcentaje CIS. |

## 🧠 Hardening idempotente

Los módulos principales comprueban primero si el sistema ya cumple el objetivo.

Si un parámetro ya está correcto, se muestra `[OK]` y no se vuelve a modificar ni se solicita autorización innecesaria.

Esto permite ejecutar las comprobaciones repetidamente sin convertir cada ejecución en una aventura.

## 🔐 SSH con preflight

Los módulos de SSH verifican primero la configuración efectiva. Si los controles ya cumplen, no se solicita confirmación. Si existen cambios pendientes, el sistema evalúa primero si puede aplicarlos de forma segura.

Esto reduce el riesgo de modificar SSH sin necesidad y evita el clásico:

> "Funcionaba hasta que ejecuté el script."

## 🧱 Kernel, sysctl y SYN flood

Los controles sysctl distinguen entre valor activo, persistente, configuración existente, configuración conflictiva y estados que no pueden verificarse con seguridad.

Los cambios pendientes pueden requerir confirmación individual.

Política OrangeBox para los controles principales:

```text
fs.suid_dumpable = 0
kernel.dmesg_restrict = 1
```

Para `kernel.kptr_restrict`, los valores activos `1` o `2` se consideran seguros y se conservan. Solo un valor `0` propone cambio a `1`, siguiendo la confirmación individual del modo `--fix`.

La protección SYN flood revisa:

```text
net.ipv4.tcp_syncookies
net.ipv4.tcp_max_syn_backlog
net.core.somaxconn
```

El baseline no modifica automáticamente `net.ipv4.tcp_synack_retries` ni `net.ipv4.tcp_syn_retries`, porque esos parámetros dependen de latencia, pérdida, aplicaciones y política operacional.

Porque sí: el kernel también tiene derecho a no recibir tuning de TikTok.

## 🌐 Auditoría de firewall

El inventario de sockets identifica protocolo, dirección, puerto, proceso y servicio cuando la información está disponible.

La auditoría puede correlacionar listeners no-loopback con las políticas y reglas que se puedan verificar en:

- firewalld
- nftables
- iptables / iptables-nft
- CSF
- Imunify360
- Shorewall

Esta auditoría es **estrictamente de solo lectura**. No elimina ni modifica reglas, servicios o configuraciones de firewall y no decide si un puerto permitido debería estar expuesto.

Si el backend no puede interpretarse con certeza, el sistema informa `INFO` en vez de asumir que el puerto está desprotegido.

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

`/etc/motd` queda vacío para evitar duplicados. El perfil `/etc/profile.d/99-orangebox-motd.sh` muestra solo datos útiles al abrir una shell interactiva: IP interna del servidor, uptime normalizado, load average de 1/5/15 minutos y fecha/hora. No repite el logo ni el aviso de seguridad. FIGlet pertenece al banner previo al login: en modo `--fix` se intenta instalar desde repositorios ya configurados y, si falla, se genera el logo ASCII de fallback.

El banner SSH se valida con `sshd -t` y se recarga sin reiniciar el daemon.

Los banners no enumeran controles defensivos ni revelan el estado de SELinux.

## 🛡️ SELinux

`selinux-secure-setup.sh` funciona como auditoría de solo lectura.

Por política OrangeBox, el proyecto no cambia automáticamente:

- modo Enforcing/Permissive
- `/etc/selinux/config`
- contextos
- paquetes SELinux
- reinicios

Primero se revisa. Después decide el administrador.

## 🧩 AIDE y Wazuh

AIDE es opcional. Durante `./linux-hardening.sh --fix`, si no está instalado, se solicita autorización antes de instalarlo y configurar la base.

El sistema informa la posible coexistencia con Wazuh FIM para evitar duplicar controles sin una razón clara.

`--fix --auto` no instala AIDE.

## 📋 Scripts

| Script | Área |
|---|---|
| `linux-hardening.sh` | Baseline 1.4.10, detección y persistencia SYSCTL legacy, parser de listeners compatible con CentOS 6 y verificación syslog sin journald. |
| `linux-hardening-audit.sh` | Auditoría agregada |
| `cis-benchmark-check.sh` | Benchmark CIS independiente |
| `post-install.sh` | Preparación inicial |
| `bash-hardening.sh` | Bash, profiles e historial |
| `ssh-hardening.sh` | Hardening SSH |
| `ssh-hardening-complete.sh` | Hardening avanzado SSH |
| `password-hardening.sh` | Contraseñas y políticas PAM |
| `sudo-hardening.sh` | sudo |
| `auditd-hardening.sh` | Auditoría |
| `selinux-secure-setup.sh` | Auditoría SELinux de solo lectura |
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
```

Modo de revisión previa sin aplicar cambios delicados.

### Aplicar de forma interactiva

```bash
./linux-hardening.sh --fix
```

Primero comprueba los valores efectivos y persistentes. Kernel y SYN flood solicitan confirmación por parámetro; sudo utiliza su confirmación específica; journald solo pregunta si necesita cambios.

Si los valores ya cumplen, muestra `[OK]` sin pedir autorizaciones redundantes ni reescribirlos.

### Aplicación automática conservadora

```bash
./linux-hardening.sh --fix --auto
```

Aplica únicamente banners/MOTD y Bash con historial ilimitado. Los controles delicados, incluidos kernel y SYN flood, permanecen en auditoría.

### Módulos especializados

El orquestador permite seleccionar módulos de AIDE, auditd, Bash, sincronización horaria, CPU, cron, filesystem, GRUB, kernel, mitigación LPE, red, passwords, xinetd, GUI, rsyslog, SELinux, SSH y sudo.

El benchmark CIS se ejecuta por separado.

Los scripts de eliminación de paquetes/servicios requieren selección manual. `post-install.sh` queda fuera del orquestador porque no dispone de una ruta de auditoría de solo lectura y puede instalar paquetes o modificar configuración incluso sin `--fix`.

La opción `--module selinux-setup` está bloqueada por política porque SELinux se mantiene como auditoría de solo lectura.

## ⚠️ Controles de alto riesgo

| Módulo/script | Riesgo operacional |
|---|---|
| `generate-iptables-rules.sh` | Puede vaciar reglas iptables y establecer `INPUT DROP`, cortando SSH. No debe combinarse con Shorewall. |
| `kernel` / `synflood` / `network-full` | Cambios de kernel/red pueden afectar VPN, forwarding, rutas asimétricas y aplicaciones. `--auto` los deja en auditoría. |
| `ssh-hardening.sh` / `ssh-hardening-complete.sh` | Pueden afectar clientes antiguos, automatizaciones y métodos de autenticación. |
| `FS-hardening.sh` | Opciones restrictivas, `hidepid`, módulos y autofs pueden afectar monitoreo y aplicaciones. |
| `cron-hardening.sh` | Restricciones de cron/at pueden romper tareas de usuarios o cPanel. |
| `grub-hardening.sh` | Cambios de arranque pueden requerir reinicio y dejar un sistema inaccesible si se aplican incorrectamente. |
| `kernel-hardening.sh` / `kernel-lpe-2026-mitigation.sh` | Pueden cambiar sysctl, módulos o comportamiento del kernel. Validar contenedores, VPN y aplicaciones. |
| `auditd-hardening.sh` / `rsyslog-hardening.sh` | Pueden aumentar volumen de logs o afectar reglas y destinos existentes. |
| `configure-time-sync.sh` | Cambios bruscos de hora pueden afectar certificados, autenticación y correlación de logs. |
| `bash-hardening.sh` | Logging de comandos puede elevar volumen de logs y capturar argumentos sensibles. |
| Scripts de eliminación | Pueden eliminar dependencias, paquetes o servicios necesarios. Revisar inventario y reversión. |

Si el servidor es remoto, usa snapshot y consola fuera de banda antes de aplicar controles de red, SSH, filesystem, kernel o firewall.

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

El banner de shell se genera al abrir una shell interactiva desde `/etc/profile.d/99-orangebox-motd.sh`. Muestra únicamente IP interna del servidor, uptime calculado desde `/proc/uptime`, load average desde `/proc/loadavg` y fecha/hora local. No muestra logo, IP remota ni aviso de seguridad.

FIGlet se usa para generar el logo estático del banner previo a la autenticación. Durante `--fix`, si FIGlet o la fuente `small` no están disponibles, se intenta instalar desde los repositorios ya configurados. No se habilitan repositorios ni se actualiza el sistema completo. Si no puede instalarse, `/etc/issue` y `/etc/issue.net` reciben un logo ASCII embebido. El uptime y la carga del panel de shell se obtienen de `/proc`, compatibles con CentOS 6.


### Limitación de la IP remota antes del login

El `Banner` estándar de OpenSSH envía el contenido estático de `/etc/issue.net`; no expande una variable distinta por conexión. Por eso el aviso previo al login no puede imprimir la IP concreta del cliente usando solamente ese archivo. La IP de origen debe verificarse en los registros de autenticación SSH. El panel de shell muestra la IP interna del servidor a la que se conectó el cliente.


### Compatibilidad adicional con CentOS/RHEL 6

El auditor de listeners consulta `ss -lntup` sin depender de la opción `-H` no disponible en algunas versiones antiguas y usa `netstat -lntup` como alternativa cuando `ss` no entrega datos. Las cabeceras se ignoran y las direcciones IPv4 no se clasifican como IPv6.

En CentOS/RHEL 6, la persistencia de los parámetros sysctl apunta a `/etc/sysctl.conf`; no se crea `/etc/sysctl.d`. Cada modificación sigue requiriendo confirmación por parámetro. La comprobación de logs verifica `rsyslog` en lugar de exigir `systemd-journald` en ese sistema legacy.
