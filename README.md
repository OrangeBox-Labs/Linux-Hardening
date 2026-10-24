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

`--auto` aplica únicamente los controles seguros del baseline (banners/MOTD y Bash: historial con fecha/hora y prompt por rol) y omite controles críticos. Los módulos omitidos se revisan en modo auditoría, sin aplicar cambios.

El aviso legal genérico completo se instala en `/etc/issue` y `/etc/issue.net`; el banner SSH se valida con `sshd -t` y se recarga sin reiniciar el daemon. `/etc/motd` muestra un mensaje breve posterior al login para evitar repetir el aviso. Ninguno de los banners enumera controles defensivos ni revela el estado de SELinux.

El prompt se vuelve a fijar antes de cada indicador para evitar que otros perfiles reemplacen `PS1`. Muestra la hora en formato `HH:MM:SS`, el usuario, el hostname completo y el directorio; root aparece en rojo con `#` y los usuarios normales en verde con `$`.

### Módulos especializados del repositorio

El orquestador permite seleccionar funciones de `aide-install.sh`, `auditd-hardening.sh`, `bash-hardening.sh`, `cis-benchmark-check.sh`, `configure-time-sync.sh`, `cpu-hardening.sh`, `cron-hardening.sh`, `FS-hardening.sh`, `grub-hardening.sh`, `kernel-hardening.sh`, `kernel-lpe-2026-mitigation.sh`, `network-hardening.sh`, `password-hardening.sh`, `post-install.sh`, `remove-xinetd.sh`, `remove-gui-hardening.sh`, `rsyslog-hardening.sh`, `selinux-secure-setup.sh`, `ssh-hardening.sh`, `ssh-hardening-complete.sh` y `sudo-hardening.sh`. Los scripts interactivos de eliminación de paquetes/servicios requieren selección manual y no forman parte de la auditoría agregada.

### Controles de alto riesgo

| Módulo/script | Riesgo operacional que debe evaluarse |
|---|---|
| `generate-iptables-rules.sh` | Genera scripts que vacían reglas iptables y establecen `INPUT DROP`; puede cortar SSH y contradecir las políticas de Shorewall. El orquestador bloquea ese módulo y el generador se niega a ejecutarse si Shorewall está activo. |
| `network-hardening.sh` | Cambia sysctl de red y bloquea módulos. En un firewall puede afectar enrutamiento asimétrico, VPN o protocolos requeridos. Si detecta Shorewall, no aplica cambios salvo que se indique explícitamente `--allow-shorewall`. |
| `ssh-hardening.sh` / `ssh-hardening-complete.sh` | Cambian parámetros de autenticación o algoritmos; clientes antiguos, automatizaciones y el acceso root pueden dejar de funcionar. |
| `FS-hardening.sh` | Puede remontar directorios con opciones restrictivas, cambiar `/proc` a `hidepid=2`, bloquear módulos y deshabilitar autofs. Puede afectar monitoreo, procesos que inspeccionan otras cuentas y aplicaciones. |
| `cron-hardening.sh` | Puede crear `cron.allow` y `at.allow` restringidos a root; esto puede impedir cron de usuarios de hosting o tareas administradas por cPanel. |
| `selinux-secure-setup.sh` | Puede activar SELinux y ejecutar `restorecon -R` sobre árboles grandes como `/etc`, `/var`, `/usr` y `/home`; etiquetas personalizadas y servicios pueden verse afectados. |
| `grub-hardening.sh` / `kernel-hardening.sh` / `kernel-lpe-2026-mitigation.sh` | Cambian parámetros de arranque, sysctl o bloquean módulos/namespaces. Algunos efectos requieren reinicio y pueden afectar contenedores, VPN y aplicaciones. |
| `rsyslog-hardening.sh` / `auditd-hardening.sh` | Reinician servicios de logging o amplían la auditoría; hay que revisar destinos, retención, volumen de eventos y reglas personalizadas. |
| `configure-time-sync.sh` | Puede retirar el paquete NTP, instalar chrony o corregir la hora de golpe. Un salto temporal puede afectar certificados, autenticación y correlación de logs. |
| `bash-hardening.sh` | Su modo completo añade un trap DEBUG para registrar comandos; puede elevar el volumen de logs y capturar argumentos sensibles. El baseline utiliza una implementación más acotada para historia y prompt. |
| `post-install.sh` | Está pensado para preparación inicial de sistemas y contiene acciones que no deben ejecutarse ciegamente sobre un servidor existente, incluida la desactivación de SELinux. Desde el orquestador se permite solo auditoría. |
| `desintalar-paquetes-sin-usar.sh` / `desintalar-servicios-sin-usar.sh` / `remove-gui-hardening.sh` / `remove-xinetd.sh` | Pueden eliminar paquetes, dependencias o servicios. No deben ejecutarse sin revisar inventario y plan de reversión. |

**Para un firewall remoto como un host administrado con Shorewall:** crea un snapshot, confirma acceso por consola fuera de banda, ejecuta la auditoría, y aplica primero solo banners/Bash. Evalúa los módulos de red, SSH, SELinux y GRUB por separado; no combines un generador de iptables con Shorewall.

La opción `--allow-risky` no sustituye una revisión de cambios ni garantiza compatibilidad. El orquestador crea respaldos para los archivos que modifica directamente, pero los módulos especializados mantienen sus propios mecanismos y limitaciones de reversión.
