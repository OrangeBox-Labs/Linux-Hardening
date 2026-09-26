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
