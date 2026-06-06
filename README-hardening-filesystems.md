# Script: hardening_filesystems.sh

## Descripcion General

Este script aplica hardening a nivel de sistema de archivos (Filesystem) en servidores Linux basado en las recomendaciones del CIS Benchmark (secciones 1.1.x). El objetivo es reducir la superficie de ataque del sistema mediante la deshabilitacion de sistemas de archivos no usados y la configuracion segura de puntos de montaje criticos.

## Que hace este script?

### 1. Deshabilita sistemas de archivos no usados

- cramfs (CIS 1.1.1.1): Sistema de archivos comprimido obsoleto
- squashfs (CIS 1.1.1.2): Sistema de archivos comprimido para sistemas embebidos
- udf (CIS 1.1.1.3): Formato de discos opticos
- freevxfs (CIS 1.1.1.4): Sistema de archivos Unix V7 obsoleto
- jffs2 (CIS 1.1.1.5): Para dispositivos flash
- hfs / hfsplus (CIS 1.1.1.6/7): Sistemas de archivos de Mac

### 2. Verifica particiones separadas

- /tmp (CIS 1.1.10): Evita ejecucion de codigo malicioso
- /var/tmp (CIS 1.1.5): Evita persistencia de codigo malicioso
- /var/log (CIS 1.1.6): Evita saturacion o manipulacion de logs
- /var/log/audit (CIS 1.1.7): Protege evidencia de auditoria
- /home (CIS 1.1.13): Controla ejecucion de scripts de usuario
- /boot (CIS 1.1.9): Protege kernel y bootloader
- /opt (custom): Aplicaciones de terceros

### 3. Aplica opciones de montaje seguras

- noexec: Impide la ejecucion de binarios en la particion
- nodev: Evita la creacion de dispositivos especiales
- nosuid: Bloquea el uso de binarios SUID/SGID

### 4. Configura /dev/shm con opciones seguras

Aplica noexec, nodev, nosuid a la memoria compartida.

### 5. Aplica sticky bit en directorios world-writable

Evita que usuarios eliminen archivos de otros en directorios como /tmp.

### 6. Verifica espacio en /var (prevencion DoS)

Monitorea espacio disponible para evitar ataques por saturacion de logs.

### 7. Configura hidepid=2 en /proc (opcional)

Impide que usuarios vean procesos de otros.

## Distribuciones Compatibles

- CentOS / RHEL 7, 8, 9 (Probado)
- Rocky Linux / AlmaLinux 8, 9 (Probado)
- Ubuntu Server 20.04, 22.04, 24.04 (Verificar rutas)
- Debian 11, 12 (Verificar rutas)

## Como Usar

Ejecutar solo verificacion:
./hardening_filesystems.sh

Ejecutar con correcciones automaticas:
./hardening_filesystems.sh --fix

## Ejemplo de Salida

============================================
  Hardening de Filesystem - CIS Benchmark
============================================

[*] Deshabilitando sistemas de archivos no usados...
[✓] cramfs deshabilitado
[✓] squashfs deshabilitado

[*] Verificando particiones separadas...
[✓] /tmp montado correctamente con: rw,nosuid,nodev,noexec
[!] /var/log NO es una particion separada

[*] Configurando /dev/shm...
[✓] /dev/shm ya tiene opciones seguras

============================================
  RESUMEN DE HARDENING
============================================
  Configuraciones corregidas: 7
  Advertencias pendientes: 1
============================================

## Precauciones

1. No deshabilitar vfat en sistemas con boot EFI
2. noexec en /home puede romper Wine, Steam o scripts de usuario
3. noexec en /var puede afectar compilacion de paquetes
4. El remontaje en caliente puede tener efectos inmediatos

## Referencias

- CIS CentOS Linux 7 Benchmark v3.1.2
- NIST SP 800-123
- Linux Kernel Module Security

## Licencia

MIT
