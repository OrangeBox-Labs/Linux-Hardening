# Script: post-install.sh

**Configuración base para servidores Linux recién instalados**

Script interactivo que prepara lo básico de servidores RHEL 8/9/10 y derivados (Rocky, AlmaLinux, Oracle Linux) dejándolos listos para aplicar el hardening de seguridad. Incluye verificaciones pre-vuelo de LVM y particiones separadas, instalación de repositorios, herramientas esenciales y configuraciones de seguridad base.

## Autor

**Felipe Roman**  
Web: https://www.orangebox.cl  
Email: froman@orangebox.cl

---

## ¿Qué hace este script?

El script realiza una configuración base para servidores recién instalados, preguntando paso a paso qué quiere hacer el administrador.

### Verificaciones pre-vuelo (lo primero que se ejecuta)

| Verificación | Qué comprueba | Por qué es crítica |
|--------------|---------------|-------------------|
| LVM | Si el sistema usa LVM | Sin LVM no se pueden redimensionar particiones ni hacer snapshots en caliente |
| Particiones separadas | /home, /var, /var/log, /tmp, /opt | Previene DoS por llenado de logs o datos de usuarios en la partición root |

Si alguna de estas verificaciones falla, el script alerta con un mensaje claro y pregunta si se quiere continuar igualmente (se puede forzar con --override).

### Configuraciones que aplica

| Configuración | Qué hace | Beneficio |
|--------------|----------|-----------|
| Repositorios EPEL | Instala EPEL release | Acceso a paquetes adicionales no incluidos en RHEL base |
| SELinux permisivo | setenforce 0 + configuración persistente | Permite auditar sin bloquear, ideal para servidores de aplicación |
| IPv6 deshabilitado | Agrega ipv6.disable=1 a GRUB | Reduce superficie de ataque y evita problemas de resolución DNS |
| Herramientas base | vim, rsync, net-tools | Esenciales para cualquier administración básica |

### Herramientas opcionales (pregunta una por una)

| Grupo | Herramientas | Para qué sirven |
|-------|--------------|-----------------|
| GIT | git | Clonar repositorios de scripts (incluyendo Linux-Hardening) |
| Red y diagnóstico | tcpdump, nmap, nmap-ncat, iftop, iptraf-ng, bind-utils, traceroute, whois, arping | Diagnosticar problemas de red, escanear puertos, capturar tráfico |
| Monitoreo básico | htop, iotop, sysstat, snmpd | Monitoreo de CPU, memoria, I/O de disco, estadísticas históricas (sar) |
| Monitoreo avanzado | btop, glances, ncdu, nethogs, lm_sensors, smartmontools, iftop, bmon | Herramientas visuales, análisis de disco, temperatura, salud de discos |

### Configuración de hostname y red (solo modo interactivo)

| Configuración | Qué pregunta |
|---------------|--------------|
| Hostname | Si se quiere cambiar el nombre del servidor |
| Red | Interfaz a configurar, DHCP o IP manual, gateway, DNS |

### Actualización del sistema

| Opción | Qué hace |
|--------|----------|
| Update | Pregunta si se quiere ejecutar dnf/yum update -y |

---

## Modos de ejecución

| Modo | Comando | Comportamiento |
|------|---------|----------------|
| Verificación | ./post-install.sh | Solo muestra el estado del sistema, NO aplica cambios |
| Interactivo | ./post-install.sh | Pregunta antes de cada acción (es el modo por defecto) |
| Automático | ./post-install.sh --fix | Responde "sí" a todas las preguntas, sin interacción |
| Override | ./post-install.sh --override | Ignora advertencias de LVM y particiones |
| Automático + Override | ./post-install.sh --fix --override | Modo automático ignorando advertencias |

---

## Requisitos

- Sistema operativo: RHEL 8, 9, 10 o derivados (Rocky Linux, AlmaLinux, Oracle Linux)
- Usuario: root (o sudo con permisos completos)
- Conexión a internet: Necesaria para instalar paquetes y actualizar

---

## Uso
```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x post-install.sh
```

Ejecutar de forma interactiva (recomendado para servidores nuevos):
```
./post-install.sh
```

Ejecutar de forma automática (sin preguntar):
```
./post-install.sh --fix
```

Ejecutar ignorando advertencias de LVM/particiones:
```
./post-install.sh --override
```

Ejecutar en modo automático ignorando advertencias:
```
./post-install.sh --fix --override
```

---

## Verificación post-ejecución

```
getenforce
```
# Debe mostrar: Permissive

```
grep ipv6.disable=1 /etc/default/grub
```
# Debe mostrar: ipv6.disable=1

```
hostname
```

```
nmcli device status
ip addr show
```

```
which htop glances nethogs
```

---

## Solución de problemas

El script se queja por falta de LVM:
```
./post-install.sh --override
```

El script se queja por particiones no separadas:
```
./post-install.sh --override
```

Error de conexión a internet al instalar paquetes:
```
ping -c 4 8.8.8.8
```

---

## Personalización

Puedes modificar el script para agregar o quitar herramientas:

1. Agregar una herramienta: Edita la función install_essentials() y añade el nombre del paquete
2. Cambiar preguntas: Modifica los mensajes en ask_yes_no()
3. Ajustar umbrales: Cambia los valores en las verificaciones de particiones

---

## Limitaciones conocidas

1. No modifica /etc/fstab automáticamente para nuevas particiones (solo advierte)
2. El cambio de IPv6 requiere reinicio para aplicarse completamente
3. No configura firewalld/iptables (debe hacerse por separado)

---

## Notas importantes

- Ejecutar como root - Todas las configuraciones requieren privilegios de administrador
- Reinicio recomendado - Especialmente después de deshabilitar IPv6 y actualizar el kernel
- Backup automático - El script NO hace backup de configuraciones (se puede agregar manualmente)

---

## Enlaces de interés

Linux-Hardening Repositorio: https://github.com/OrangeBox-Labs/Linux-Hardening
CIS Benchmarks: https://www.cisecurity.org/benchmark/red_hat_linux
Guías de hardening de ssh-audit: https://www.ssh-audit.com/hardening_guides.html

---

## Licencia

MIT — Libre de usar, modificar y compartir.

---

## ¿Quieres más contenido?

🔹 **Blog**: [https://www.orangebox.cl/blog/](https://www.orangebox.cl/blog/)
🔹 **YouTube**: [https://www.youtube.com/@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux)
🔹 **GitHub**: [https://github.com/OrangeBox-Labs](https://github.com/OrangeBox-Labs)

— Felipe Román, OrangeBox 
