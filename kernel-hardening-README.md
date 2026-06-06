# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x kernel-hardening.sh
```

# Script: kernel-hardening.sh

Script para aplicar hardening del kernel y limites del sistema en Linux para evitar que ataques como bombas fork o procesos escapados puedan colapsar nuestro servidor.

## Autor

- Felipe Roman
- Web: www.orangebox.cl
- Email: froman@orangebox.cl

## Que previene cada parametro
### ASLR (CIS 1.5.3)

Address Space Layout Randomization: Aleatoriza las direcciones de memoria de procesos y librerias, dificultando ataques que requieren conocer direcciones especificas de memoria.

Verificacion manual:

```
sysctl kernel.randomize_va_space
```

### Core Dumps (CIS 1.5.1)

- fs.suid_dumpable = 0: Evita que programas con privilegios (setuid) generen archivos core dump que podrian contener informacion sensible como contraseñas o claves
- hard core = 0: Impide la generacion de archivos core dump que podrian ser analizados por un atacante para obtener informacion del sistema

### Limites de recursos

- nproc = 1024: Evita que un usuario o proceso malicioso consuma todos los procesos del sistema (fork bomb)
- nofile = 65536: Previene que un proceso agote los descriptores de archivo del sistema
- maxlogins = 10: Limita el numero de sesiones simultaneas por usuario, previene ataques de fuerza bruta via multiples terminales

### Seguridad del kernel

- kernel.dmesg_restrict = 1: Impide que usuarios no root vean mensajes del kernel que podrian revelar informacion del sistema
- kernel.kptr_restrict = 2: Oculta direcciones de memoria del kernel, dificultando ataques de explotacion de memoria
- kernel.randomize_va_space = 2: Activa ASLR (Address Space Layout Randomization), dificulta ataques de desbordamiento de buffer
- kernel.yama.ptrace_scope = 1: Restringe el uso de ptrace, previene que procesos no autorizados inspeccionen otros procesos
- vm.mmap_min_addr = 65536: Previene ataques de NULL pointer dereference que podrian ejecutar codigo malicioso

### Proteccion del filesystem

- fs.protected_fifos = 1: Evita escritura en archivos FIFO en directorios world-writable, previene ataques DoS
- fs.protected_hardlinks = 1: Previene creacion de hardlinks a archivos que no pertenecen al usuario
- fs.protected_symlinks = 1: Previene race conditions con enlaces simbolicos en directorios world-writable

### Hardening de red

- net.ipv4.conf.all.accept_redirects = 0: Previene ataques de redireccion ICMP que podrian desviar trafico
- net.ipv4.conf.all.send_redirects = 0: Evita que el sistema sea usado como nodo de redireccion en ataques MITM
- net.ipv4.tcp_syncookies = 1: Previene ataques SYN flood que agotan la cola de conexiones

## Valores por defecto antes de aplicar el script

Para verificar los valores actuales de cada parametro antes de ejecutar el script:

```
sysctl fs.suid_dumpable
sysctl kernel.dmesg_restrict
sysctl kernel.kptr_restrict
sysctl kernel.randomize_va_space
sysctl kernel.yama.ptrace_scope
sysctl vm.mmap_min_addr
sysctl fs.protected_fifos
sysctl fs.protected_hardlinks
sysctl fs.protected_symlinks
sysctl net.ipv4.conf.all.accept_redirects
sysctl net.ipv4.conf.all.send_redirects
sysctl net.ipv4.tcp_syncookies

ulimit -a
cat /etc/security/limits.conf | grep -v "^#"
```

## Rangos recomendados y como modificar

### Parametros de kernel (sysctl)

```
fs.suid_dumpable: rango 0-2, valor recomendado 0
kernel.dmesg_restrict: rango 0-1, valor recomendado 1
kernel.kptr_restrict: rango 0-2, valor recomendado 2
kernel.randomize_va_space: rango 0-2, valor recomendado 2
kernel.yama.ptrace_scope: rango 0-3, valor recomendado 1
vm.mmap_min_addr: rango 0-65536, valor recomendado 65536
fs.protected_fifos: rango 0-2, valor recomendado 1
fs.protected_hardlinks: rango 0-1, valor recomendado 1
fs.protected_symlinks: rango 0-1, valor recomendado 1
net.ipv4.tcp_syncookies: rango 0-2, valor recomendado 1
```

### Limites de recursos (limits.conf)

```
nproc: rango 100-65536, valor recomendado 1024
nofile: rango 1024-1048576, valor recomendado 65536
maxlogins: rango 3-100, valor recomendado 10
core: rango 0-unlimited, valor recomendado 0
```

## Como modificar parametros

### Opcion A: Editar el archivo generado por el script

```
vim /etc/sysctl.d/99-cis-hardening.conf
```

### Opcion B: Cambiar un parametro especifico temporalmente

```
sysctl -w kernel.dmesg_restrict=0
```

### Opcion C: Cambiar un parametro permanentemente

```
echo "kernel.dmesg_restrict = 0" >> /etc/sysctl.d/99-cis-hardening.conf
sysctl -p /etc/sysctl.d/99-cis-hardening.conf
```

### Opcion D: Cambiar limites de recursos

```
vim /etc/security/limits.conf
```

## Advertencias de compatibilidad

- Servidores de bases de datos: nproc=1024 puede ser bajo, aumentar a 65536
- Contenedores Docker: ptrace_scope=1 afecta debugging, cambiar a 0 dentro del contenedor
- Aplicaciones Java: nofile=65536 puede ser alto, mantener no afecta
- Entornos con debug: ptrace_scope=1 impide gdb/strace, cambiar temporalmente a 0
- Routing dinamico: accept_redirects=0 puede afectar, mantener en 1 si usa RIP/BGP

## Verificacion post-ejecucion
```
sysctl -a 2>/dev/null | grep -E "fs.suid_dumpable|kernel.dmesg_restrict|kernel.randomize_va_space|net.ipv4.tcp_syncookies"
ulimit -a
journalctl -xe | grep -i "sysctl\|limit"
```

## Base de Referencia

- CIS Benchmark para CentOS Linux 7 version 3.1.2
- NIST SP 800-123
- NSA Linux hardening guides
- Red Hat Enterprise Linux Security Guide

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
