# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x FS-hardening.README.md.sh
```

# Script: FS-hardening.sh

## Descripcion General

Este script aplica hardening a nivel de sistema de archivos (Filesystem) en servidores Linux basado en las recomendaciones del CIS Benchmark (secciones 1.1.x). El objetivo es reducir la superficie de ataque del sistema mediante la deshabilitacion de sistemas de archivos no usados y la configuracion segura de puntos de montaje criticos para evitar la ejecución de codigo no deseado y el escalado de privilegios.

## Que hace este script?

### 1. Deshabilita sistemas de archivos no usados

| Modulo | CIS ID | Por que deshabilitar? |
|--------|--------|----------------------|
| cramfs | 1.1.1.1 | Sistema de archivos comprimido obsoleto |
| squashfs | 1.1.1.2 | Sistema de archivos comprimido para sistemas embebidos |
| udf | 1.1.1.3 | Formato de discos opticos no necesario en servidores |
| freevxfs | 1.1.1.4 | Sistema de archivos Unix V7 obsoleto |
| jffs2 | 1.1.1.5 | Para dispositivos flash (sistemas embebidos) |
| hfs | 1.1.1.6 | Sistema de archivos de Mac (no necesario en Linux) |
| hfsplus | 1.1.1.7 | Sistema de archivos de Mac (no necesario en Linux) |

### 2. Verifica particiones separadas para directorios criticos

| Directorio | CIS ID | Riesgo si no esta separado |
|------------|--------|---------------------------|
| /tmp | 1.1.10 | Ejecucion de codigo malicioso |
| /var/tmp | 1.1.5 | Persistencia de codigo malicioso |
| /var/log | 1.1.6 | saturacion o manipulacion de logs |
| /var/log/audit | 1.1.7 | Perdida de evidencia de auditoria |
| /home | 1.1.13 | Ejecucion de scripts de usuario no controlados |
| /boot | 1.1.9 | Manipulacion del kernel o bootloader |
| /opt | custom | Aplicaciones de terceros |

### 3. Aplica opciones de montaje seguras

| Opcion | Funcion |
|--------|---------|
| noexec | Impide la ejecucion de binarios en la particion |
| nodev | Evita la creacion de dispositivos especiales |
| nosuid | Bloquea el uso de binarios SUID/SGID |

### 4. Configura /dev/shm con opciones seguras

Aplica noexec, nodev, nosuid a la memoria compartida.

### 5. Aplica sticky bit en directorios world-writable

Evita que usuarios eliminen archivos de otros en directorios como /tmp.

### 6. Verifica espacio en /var (prevencion DoS)

Monitorea espacio disponible para evitar ataques por saturacion de logs.

### 7. Configura hidepid=2 en /proc (opcional)

Impide que usuarios vean procesos de otros.

## Distribuciones Compatibles

| Distribucion | Versiones | Notas |
|--------------|-----------|-------|
| CentOS / RHEL | 7, 8, 9 | Probado |
| Rocky Linux / AlmaLinux | 8, 9 | Probado |
| Ubuntu Server | 20.04, 22.04, 24.04 | Verificar rutas |
| Debian | 11, 12 | Verificar rutas |

## Como Usar

Solo verificacion (no hace cambios):
```
./FS-hardening.sh
```

Verificacion y correccion automatica:
```
./FS-hardening.sh --fix
```

## Ejemplo de Salida

============================================
  Hardening de Filesystem - CIS Benchmark
============================================

[*] Deshabilitando sistemas de archivos no usados...
[✓] cramfs deshabilitado
[✓] squashfs deshabilitado
[✓] udf deshabilitado

[*] Verificando particiones separadas...
[✓] /tmp montado correctamente con: rw,nosuid,nodev,noexec
[!] /var/log NO es una particion separada
    Recomendacion: Configurar particion separada para /var/log

[*] Configurando /dev/shm...
[✓] /dev/shm ya tiene opciones seguras

[*] Verificando sticky bit...
[✓] Todos los directorios world-writable tienen sticky bit

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


---

**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs
