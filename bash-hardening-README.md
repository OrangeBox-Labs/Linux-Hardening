# 🛡️ bash-hardening.sh


Script de hardening para Bash que fortalece la seguridad del shell y el entorno de usuario en sistemas Linux. Configura historial con fecha/hora, prompt mejorado, timeout de sesión, umask segura, alias útiles, auditoría en syslog y protecciones adicionales.

## Tabla de Contenidos

- Características
- Requisitos
- Instalación
- Uso
- Qué Hace Este Script
- Estructura del Script
- Archivos que Modifica
- Personalización
- Solución de Problemas
- Referencias
- Licencia

## Características

- Sin dependencias externas - usa solo herramientas base del sistema
- Modo verificación - muestra qué cambios se aplicarían sin modificarlo
- Modo automático - aplica todas las correcciones de una vez
- Backup automático - guarda copia de seguridad antes de modificar
- Compatible con RHEL/CentOS/Rocky/AlmaLinux/Oracle 7,8,9,10
- Auditoría de comandos - envía todos los comandos a syslog
- Historial por usuario - almacena historial segregado en /var/log/bash_history
- Timeout de sesión - cierra sesiones inactivas
- Prompt personalizado - muestra hora, usuario, hostname y directorio

## Requisitos

| Requisito | Detalle |
|-----------|---------|
| Sistema Operativo | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux 7/8/9/10 |
| Privilegios | Root (sudo o acceso directo) |
| Dependencias | Ninguna - usa herramientas base del sistema |
| Bash | Versión 4.0 o superior |

## Instalación

### Instalación Rápida

# Descargar el script
```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x auditd-hardening.sh
```

# Ejecutar como root
```
sudo ./bash-hardening.sh
```

## Uso

### Sintaxis

```
./bash-hardening.sh [OPCIÓN]
```

### Opciones

| Opción | Descripción |
|--------|-------------|
| (sin opción) | Modo verificación - solo muestra lo que hay que corregir |
| --fix o -f | Modo automático - aplica todas las correcciones |
| --help o -h | Muestra la ayuda |

### Ejemplos

# Ver qué cambios se aplicarían (modo seguro)
```
./bash-hardening.sh
```

# Aplicar todas las correcciones
```
./bash-hardening.sh --fix
```

# Versión corta
```
./bash-hardening.sh -f
```

# Ver ayuda
```
./bash-hardening.sh --help
```

## Qué Hace Este Script

### 1. Configuración de Profile (/etc/profile.d/orangebox.sh)

- Muestra banner de OrangeBox al inicio de sesión
- Muestra información de conexión (IP, usuario, fecha/hora)
- Configura prompt personalizado con formato [HH:MM] usuario@hostname directorio $
- Activa HISTTIMEFORMAT para historial con fecha/hora
- Configura timeout de sesión inactiva (15 minutos / 10 minutos para root)
- Establece umask segura (027)
- Hace el historial inmutable con readonly HISTFILE

### 2. Alias Avanzados (/etc/profile.d/aliases.sh)

| Categoría | Alias | Función |
|-----------|-------|---------|
| Navegación | .., ..., ...., ~ | Navegación rápida por directorios |
| ls mejorado | ls, ll, la, l | Listado con colores y formatos |
| grep mejorado | grep, egrep, fgrep | Búsqueda con colores |
| Comandos legibles | df, du, free, ping | Salida legible para humanos |
| Confirmaciones | cp, mv, rm, mkdir | Pregunta antes de sobrescribir |
| Historial | h, hg | Ver historial reciente o buscar |
| Sistema | ps, ports, myip | Monitoreo rápido |
| Logs | syslog, secure, audit | Tailing de logs comunes |

### 3. Auditoría a Syslog (/etc/profile.d/syslog_history.sh)

- Captura todos los comandos ejecutados por cualquier usuario
- Envía cada comando a syslog con nivel local1.notice
- Registra usuario, directorio de trabajo y comando ejecutado
- Configura /var/log/bash_commands.log para almacenar los logs

### 4. Historial Seguro por Usuario (/etc/profile.d/history_secure.sh)

- Crea archivos de historial individuales en /var/log/bash_history/
- Formato: /var/log/bash_history/NOMBRE_USUARIO.history
- Permisos seguros (640) para evitar acceso no autorizado
- Separa el historial de root del de usuarios regulares

### 5. Configuración de Root (/root/.bashrc)

- Prompt en color rojo para identificar fácilmente sesiones root
- Timeout más estricto (10 minutos)
- Tamaños de historial aumentados (20000 en memoria, 100000 en disco)
- Alias con confirmaciones obligatorias

### 6. Configuración para Nuevos Usuarios (/etc/skel/.bashrc)

- Todos los nuevos usuarios heredan la configuración de hardening
- Timeout de 15 minutos para usuarios regulares
- Umask 027 por defecto

### 7. Deshabilitar Ctrl+Alt+Del

- Previene reinicios accidentales o maliciosos
- Enmascara el target ctrl-alt-del.target de systemd

## Estructura del Script

bash-hardening.sh
│
├── Variables Globales
│   ├── Colores para output (RED, GREEN, YELLOW, BLUE, NC)
│   ├── Contadores (FIXED, WARNINGS)
│   ├── AUTO_FIX flag
│   └── BACKUP_DIR con timestamp
│
├── Funciones de Configuración
│   ├── show_usage() - Muestra ayuda
│   ├── make_backup() - Crea backup antes de modificar
│   ├── configure_profile() - Configura /etc/profile.d/orangebox.sh
│   ├── configure_aliases() - Configura /etc/profile.d/aliases.sh
│   ├── configure_syslog_history() - Configura auditoría a syslog
│   ├── configure_secure_history() - Configura historial por usuario
│   ├── configure_root_bashrc() - Configura /root/.bashrc
│   ├── configure_skel() - Configura /etc/skel/.bashrc
│   └── disable_ctrl_alt_del() - Deshabilita Ctrl+Alt+Del
│
├── Funciones de Reporte
│   ├── check_status() - Muestra estado actual
│   └── show_summary() - Muestra resumen final
│
└── Main
    ├── Verificación de root
    ├── Procesamiento de argumentos
    └── Ejecución secuencial de funciones

## Archivos que Modifica

| Archivo | Propósito |
|---------|-----------|
| /etc/profile.d/orangebox.sh | Banner, prompt, timeout, umask |
| /etc/profile.d/aliases.sh | Alias de comandos |
| /etc/profile.d/syslog_history.sh | Envío de comandos a syslog |
| /etc/profile.d/history_secure.sh | Historial por usuario |
| /root/.bashrc | Configuración específica para root |
| /etc/skel/.bashrc | Configuración para nuevos usuarios |
| /etc/rsyslog.d/30-bash.conf | Configuración de logging |
| /var/log/bash_history/ | Directorio de historiales por usuario |
| /var/log/bash_commands.log | Log de comandos ejecutados |

## Personalización

### Variables configurables al inicio del script

BASHRC_SYSTEM="/etc/bashrc"
PROFILE_D="/etc/profile.d/orangebox.sh"
ALIASES_D="/etc/profile.d/aliases.sh"
HISTORY_SYSLOG="/etc/profile.d/syslog_history.sh"
HISTORY_SECURE="/etc/profile.d/history_secure.sh"
BASHRC_ROOT="/root/.bashrc"
SKEL_BASHRC="/etc/skel/.bashrc"
RSYSLOG_CONF="/etc/rsyslog.d/30-bash.conf"

### Timeouts configurables

Para usuarios regulares: TMOUT=900 (15 minutos)
Para usuario root: TMOUT=600 (10 minutos)

### Tamaños de historial

Usuarios regulares: HISTSIZE=10000, HISTFILESIZE=50000
Usuario root: HISTSIZE=20000, HISTFILESIZE=100000

## Solución de Problemas

### Los cambios no se ven en la sesión actual

```
Aplicar los cambios manualmente:
source /etc/profile.d/orangebox.sh
source /etc/profile.d/aliases.sh
source ~/.bashrc
```

### Los comandos no se registran en syslog

Verificar que rsyslog esté corriendo:
```
systemctl status rsyslog
```

Reiniciar rsyslog:
```
systemctl restart rsyslog
```

### El timeout no funciona

Verificar que TMOUT esté configurado como readonly:
```
echo $TMOUT
readonly | grep TMOUT
```

## Referencias

### Documentación Oficial

- GNU Bash Reference Manual - https://www.gnu.org/software/bash/manual/
- Linux man pages - https://man7.org/linux/man-pages/
- systemd documentation - https://www.freedesktop.org/wiki/Software/systemd/

### Hardening y Seguridad

- CIS Benchmarks - https://www.cisecurity.org/benchmark/
- NIST Security Guidelines - https://csrc.nist.gov/
- Red Hat Security Guide - https://access.redhat.com/documentation/security/

### Recursos OrangeBox

- Sitio Web - https://www.orangebox.cl
- YouTube - https://www.youtube.com/@OrangeBoxLinux

## Licencia

MIT License

Copyright (c) 2025 Felipe Roman - OrangeBox Labs

Permiso concedido gratuitamente a cualquier persona que obtenga una copia de este software y los archivos de documentación asociados, para utilizar el Software sin restricción, incluyendo sin limitación los derechos de usar, copiar, modificar, fusionar, publicar, distribuir, sublicenciar y/o vender copias del Software.

---

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox
