# OrangeBox · Linux Hardening

> Scripts Bash de hardening y seguridad para servidores Linux Enterprise basados en CIS Benchmarks.

[![OrangeBox IT Services](https://img.shields.io/badge/OrangeBox-IT%20Services-ff6a00?style=for-the-badge)](https://www.orangebox.cl/)
[![Bash](https://img.shields.io/badge/Bash-tooling-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![CIS](https://img.shields.io/badge/CIS-security-0073c6?style=for-the-badge)](https://www.cisecurity.org/)

## Hardening de Linux con Bash y CIS Benchmarks

Colección de scripts de **Linux hardening** desarrollados por **OrangeBox IT Services** para asegurar servidores Linux Enterprise de forma reproducible, transparente y auditable.

El proyecto cubre áreas como **SSH, sudo, PAM, passwords, auditd, SELinux, kernel, filesystem, GRUB, red, cron, rsyslog, servicios, AIDE, sincronización horaria y mitigaciones de seguridad**.

La idea es simple: código visible, comportamiento explícito y herramientas que un administrador Linux pueda revisar antes de aplicarlas.

## Filosofía

**Infraestructura antes que magia.**

Los scripts:

- están escritos principalmente en Bash
- muestran exactamente qué cambios realizan
- separan verificación de aplicación cuando corresponde
- evitan dependencias innecesarias
- están pensados para administradores Linux

## Requisito previo

El hardening debe aplicarse sobre un sistema Linux correctamente instalado y configurado.

Para una instalación segura de Linux puedes revisar nuestros materiales:

- Blog: https://www.orangebox.cl/blog/
- YouTube: https://www.youtube.com/@OrangeBoxLinux
- Web: https://www.orangebox.cl/

## Scripts

| Script | Área |
|---|---|
| `post-install.sh` | Preparación inicial del servidor |
| `bash-hardening.sh` | Bash, profiles e historial |
| `cis-benchmark-check.sh` | Verificación CIS |
| `ssh-hardening.sh` | Hardening de SSH |
| `ssh-hardening-complete.sh` | Hardening avanzado de SSH |
| `password-hardening.sh` | Políticas de contraseñas |
| `grub-hardening.sh` | GRUB |
| `FS-hardening.sh` | Sistema de archivos |
| `sudo-hardening.sh` | sudo |
| `auditd-hardening.sh` | Auditoría |
| `selinux-secure-setup.sh` | SELinux |
| `kernel-hardening.sh` | Kernel |
| `network-hardening.sh` | Red |
| `cron-hardening.sh` | cron |
| `rsyslog-hardening.sh` | Logs |
| `aide-install.sh` | Integridad |
| `audit-listening-services.sh` | Servicios escuchando |
| `generate-iptables-rules.sh` | Firewall |
| `configure-time-sync.sh` | Sincronización horaria |

La auditoría de sockets identifica TCP y UDP por proceso y dirección de escucha, sin sugerir eliminar paquetes a partir del puerto. En modo `./network-hardening.sh --check`, el diagnóstico compara los frontends iptables y revisa rulesets seleccionados y legacy para detectar integración de Imunify360; esas comprobaciones son de solo lectura y no editan reglas del firewall. El modo `--fix` del módulo de red aplica sus controles de kernel/protocolos, pero tampoco administra reglas del firewall.

## Uso básico

Clonar:

```bash
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x *.sh
```

Ejecutar una verificación:

```bash
./ssh-hardening.sh
```

Aplicar cambios:

```bash
./ssh-hardening.sh --fix
```

## Plataformas

El repositorio está orientado principalmente a **Red Hat Enterprise Linux (RHEL), CentOS, Rocky Linux, AlmaLinux y Fedora**.

La compatibilidad exacta depende de cada script. Revisa siempre el README individual antes de ejecutarlo.

El proyecto no está diseñado como una colección genérica para Debian/Ubuntu: muchas políticas utilizan herramientas, PAM, SELinux, paquetes y rutas propias del ecosistema Red Hat.

## Seguridad y compatibilidad

Los scripts de hardening modifican configuración del sistema. **Prueba primero en laboratorio, snapshot o una máquina de validación.**

No todos los controles son adecuados para todos los servidores. Revisa dependencias de aplicaciones, autenticación, acceso remoto, monitoreo y gestión antes de aplicar cambios.

## OrangeBox IT Services

**Felipe Román · OrangeBox IT Services**

Enterprise Linux · Linux Security · Hardening · CIS Benchmarks · RHEL · Rocky Linux · AlmaLinux · CentOS · Fedora

https://www.orangebox.cl/

### Keywords

Linux hardening, Linux security, CIS Benchmark, CIS hardening, RHEL hardening, Red Hat hardening, Rocky Linux hardening, AlmaLinux hardening, CentOS hardening, Fedora hardening, SSH hardening, sudo hardening, SELinux, auditd, kernel hardening, filesystem hardening, GRUB hardening, firewall hardening, Bash security, server hardening, Linux Enterprise, OrangeBox.

## Auditoría de módulos de hardening (solo lectura)

La auditoría agregada de módulos se ejecuta con:

```bash
./linux-hardening-audit.sh
```

Este programa consulta las comprobaciones operacionales de los módulos, fuerza `--check` en red, filesystem y mitigación LPE, y nunca pasa `--fix`. No calcula ni incorpora el porcentaje CIS, no ejecuta `cis-benchmark-check.sh` y no crea backups ni reportes persistentes. Los módulos de preparación, eliminación interactiva de paquetes/servicios, configuración de SELinux sin modo de auditoría garantizado y generación destructiva de reglas de firewall quedan excluidos.

## Benchmark CIS independiente

El benchmark CIS es una evaluación separada de los chequeos operacionales de los módulos. Ejecuta únicamente:

```bash
./cis-benchmark-check.sh
```

El resultado y el porcentaje de cumplimiento CIS provienen exclusivamente de los controles de `cis-benchmark-check.sh`. No se suman ni se mezclan con advertencias, recomendaciones o estados internos que reportan otros scripts.

Para **aplicar hardening**, usa `linux-hardening.sh --fix`. Sin `--fix`, el orquestador principal conserva su modo de revisión previa sin aplicar cambios. La opción antigua `--module repo-audit` se rechaza y muestra la ruta del auditor separado.

## Orquestador unificado: `linux-hardening.sh`

`linux-hardening.sh` es el punto de entrada para el baseline y los scripts especializados del repositorio. El comportamiento está diseñado para que una ejecución global no modifique a ciegas la red ni la autenticación de un servidor remoto.

### Uso recomendado

Auditar el baseline interno sin aplicar cambios:

```bash
./linux-hardening.sh
```

Aplicar cambios de forma interactiva:

```bash
./linux-hardening.sh --fix
```

Este modo aplica banners corporativos y la configuración de Bash, y luego explica cada control clasificado como riesgoso y pregunta si se quiere aplicar. Si respondes No, el control no modifica el sistema; cuando hay un modo de auditoría seguro definido, se ejecuta. Si no lo hay, el módulo se omite sin cambios.

Para ejecución automática y conservadora, sin preguntas:

```bash
./linux-hardening.sh --fix --auto
```

`--auto` aplica únicamente banners/MOTD y Bash con historial ilimitado. Los controles delicados —incluidos los cambios sysctl de kernel y SYN flood— se revisan en auditoría y no se aplican. En modo interactivo `--fix`, cada control delicado pregunta por separado, explica qué cambiará y qué impacto operacional puede tener; responder No o no disponer de TTY deja ese control sin modificar.

El aviso legal genérico completo se instala en `/etc/issue` y `/etc/issue.net`; el banner SSH se valida con `sshd -t` y se recarga sin reiniciar el daemon. `/etc/motd` muestra un mensaje breve posterior al login para evitar repetir el aviso. Ninguno de los banners enumera controles defensivos ni revela el estado de SELinux.

El prompt se vuelve a fijar antes de cada indicador para evitar que otros perfiles reemplacen `PS1`. Muestra la hora en formato `HH:MM:SS`, el usuario, el hostname completo y el directorio; root aparece en rojo con `#` y los usuarios normales en verde con `$`.

### Módulos especializados del repositorio

El orquestador permite seleccionar funciones de `aide-install.sh`, `auditd-hardening.sh`, `bash-hardening.sh`, `configure-time-sync.sh`, `cpu-hardening.sh`, `cron-hardening.sh`, `FS-hardening.sh`, `grub-hardening.sh`, `kernel-hardening.sh`, `kernel-lpe-2026-mitigation.sh`, `network-hardening.sh`, `password-hardening.sh`, `remove-xinetd.sh`, `remove-gui-hardening.sh`, `rsyslog-hardening.sh`, `selinux-secure-setup.sh`, `ssh-hardening.sh`, `ssh-hardening-complete.sh` y `sudo-hardening.sh`. El benchmark `cis-benchmark-check.sh` se ejecuta por separado y no forma parte del selector de módulos de hardening. Los scripts interactivos de eliminación de paquetes/servicios requieren selección manual y no forman parte de la auditoría agregada. `post-install.sh` queda fuera del orquestador y de la auditoría agregada porque no dispone de una ruta de auditoría de solo lectura y puede instalar paquetes o modificar la configuración incluso sin `--fix`. `selinux-secure-setup.sh` también se excluye de `linux-hardening-audit.sh` porque su ejecución normal puede modificar `/etc/selinux/config` y pedir un reinicio; solo debe ejecutarse mediante selección explícita y confirmación.

**AIDE es opcional:** en el flujo interactivo `./linux-hardening.sh --fix`, si no está instalado se pregunta antes de instalarlo y configurar la base y la verificación diaria. El mensaje explica que AIDE compara una base de integridad y que puede solaparse con Wazuh FIM. `--fix --auto` no instala AIDE.

### Controles de alto riesgo

| Módulo/script | Riesgo operacional que debe evaluarse |
|---|---|
| `generate-iptables-rules.sh` | Genera scripts que vacían reglas iptables y establecen `INPUT DROP`; puede cortar SSH y contradecir las políticas de Shorewall. El orquestador bloquea ese módulo y el generador se niega a ejecutarse si Shorewall está activo. |
| `kernel` / `synflood` / `network-full` | Los perfiles base de kernel y SYN flood piden confirmación en `--fix` interactivo. `--auto` los deja en auditoría. `network-full` además bloquea módulos de protocolos y requiere autorización explícita para actuar con Shorewall; puede afectar VPN, rutas asimétricas o aplicaciones que usen esos protocolos. El código preserva `net.ipv4.ip_forward` y adapta `rp_filter` cuando detecta forwarding IPv4. |
| `ssh-hardening.sh` / `ssh-hardening-complete.sh` | Cambian parámetros de autenticación o algoritmos; clientes antiguos, automatizaciones y el acceso root pueden dejar de funcionar. |
| `FS-hardening.sh` | Puede remontar directorios con opciones restrictivas, cambiar `/proc` a `hidepid=2`, bloquear módulos y deshabilitar autofs. Puede afectar monitoreo, procesos que inspeccionan otras cuentas y aplicaciones. |
| `cron-hardening.sh` | Puede crear `cron.allow` y `at.allow` restringidos a root; esto puede impedir cron de usuarios de hosting o tareas administradas por cPanel. |
| `selinux-secure-setup.sh` | Puede activar SELinux y ejecutar `restorecon -R` sobre árboles grandes como `/etc`, `/var`, `/usr` y `/home`; etiquetas personalizadas y servicios pueden verse afectados. |
| `grub-hardening.sh` / `kernel-hardening.sh` / `kernel-lpe-2026-mitigation.sh` | Cambian parámetros de arranque, sysctl o bloquean módulos/namespaces. Algunos efectos requieren reinicio y pueden afectar contenedores, VPN y aplicaciones. |
| `rsyslog-hardening.sh` / `auditd-hardening.sh` | Reinician servicios de logging o amplían la auditoría; hay que revisar destinos, retención, volumen de eventos y reglas personalizadas. |
| `configure-time-sync.sh` | Puede retirar el paquete NTP, instalar chrony o corregir la hora de golpe. Un salto temporal puede afectar certificados, autenticación y correlación de logs. |
| `bash-hardening.sh` | Su modo completo añade un trap DEBUG para registrar comandos; puede elevar el volumen de logs y capturar argumentos sensibles. El baseline utiliza una implementación más acotada para historia y prompt. |
| `post-install.sh` | Está pensado para preparación inicial; puede instalar paquetes, habilitar servicios y modificar configuración incluso sin `--fix`. Se omite del orquestador y no forma parte de `linux-hardening-audit.sh`. |
| `desintalar-paquetes-sin-usar.sh` / `desintalar-servicios-sin-usar.sh` / `remove-gui-hardening.sh` / `remove-xinetd.sh` | Pueden eliminar paquetes, dependencias o servicios. No deben ejecutarse sin revisar inventario y plan de reversión. |

**Para un firewall remoto como un host administrado con Shorewall:** crea un snapshot y confirma acceso por consola fuera de banda. Usa `--fix` interactivo para que kernel/SYN flood soliciten autorización individual, revisa el resumen de cada cambio y comprueba las rutas después de aplicarlo. `--fix --auto` no aplica esos controles delicados. El código preserva `net.ipv4.ip_forward` y usa `rp_filter=2` si detecta forwarding IPv4; no combines un generador de iptables con Shorewall.

La opción `--allow-risky` no sustituye una revisión de cambios ni garantiza compatibilidad. El orquestador crea respaldos para los archivos que modifica directamente, pero los módulos especializados mantienen sus propios mecanismos y limitaciones de reversión.


## Gestión segura de parámetros sysctl (v1.4.0)

Los scripts que modifican sysctl usan ahora `lib/sysctl-safe.sh` para inventariar definiciones activas antes de cambiar parámetros. Se comprueba el valor activo y se recorren, línea a línea, las asignaciones en:

- `/etc/sysctl.conf`
- `/etc/sysctl.d/*.conf`
- `/run/sysctl.d/*.conf`
- `/usr/local/lib/sysctl.d/*.conf`
- `/usr/lib/sysctl.d/*.conf`
- `/lib/sysctl.d/*.conf`

Se ignoran las líneas comentadas y se muestran archivo, número de línea y valor encontrado. Si el valor activo y el persistente ya coinciden con el objetivo, se conserva sin añadir duplicados. Si el valor activo es distinto, o existe una asignación persistente incompatible, muestra los valores, las ubicaciones y una descripción breve del impacto; solicita confirmación individual antes de cambiar el valor. Si no hay terminal interactiva o se responde que no, el parámetro se omite.

Ejemplo de ejecución:

```text
[SYSCTL][CONFLICTO] net.ipv4.conf.all.secure_redirects ya tiene definiciones persistentes diferentes.
  Qué cambia: Controla redirecciones ICMP consideradas seguras desde gateways conocidos...
  Valor activo: 1 | Valor propuesto: 0
  Definiciones detectadas (los archivos existentes no se modifican):
    - /etc/sysctl.d/60-gce-network-security.conf:25 = 1
¿Confirmas aplicar net.ipv4.conf.all.secure_redirects=0 y añadir/actualizar el override...? [y/N]
```

Los parámetros aprobados se centralizan en `/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf`, un perfil de alta precedencia compartido por el hardening de kernel, red, CPU y mitigación LPE. El script no edita los perfiles de Google Cloud, cPanel, CloudLinux ni otros proveedores. Excepción: si una asignación conflictiva está en `/etc/sysctl.conf` (que puede procesarse después de `sysctl.d`), solo se actualiza esa asignación después de confirmación explícita y con respaldo. El perfil central existente solo se modifica si contiene el marcador de propiedad OrangeBox. Revise siempre el impacto antes de aceptar; los valores de red pueden afectar routing asimétrico, IPv6, colas TCP o servicios que dependan de ellos.

**Importante:** el modo auditoría sigue sin modificar el sistema. En modo fix, los parámetros que ya estén definidos con el mismo valor no se duplican; los conflictos se consultan por parámetro, no como una aprobación global de todo el bloque.
