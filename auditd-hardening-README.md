# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x auditd-hardening.sh
```

# Script: auditd-hardening.sh

Script para configurar auditd segun CIS Benchmark secciones 4.1.1 a 4.1.18.

# auditd - Servicio de Auditoria de Seguridad

## Que es auditd?

auditd es un servicio que vigila y registra todo lo que pasa en el servidor.
Es como una "camara de seguridad" que graba las acciones importantes.

## Por que es importante?

Si alguien intenta atacar el servidor o hacer algo prohibido, auditd lo registra.
Sirve para:
- Detectar intentos de hackeo
- Saber quien hizo que cambio
- Investigar incidentes de seguridad
- Cumplir con normas de seguridad

## Que registra auditd?

| Evento | Ejemplo |
|--------|---------|
| Accesos al sistema | Alguien inicio sesion |
| Cambios de archivos | Editar /etc/passwd |
| Cambios de permisos | chmod 777 a un archivo |
| Intentos fallidos | Escribir mal una contraseña |
| Comandos ejecutados | sudo rm -rf / (borraria todo) |
| Cambios de fecha/hora | Modificar el reloj del sistema |

## Como ver los registros

Ver eventos recientes:
ausearch -ts recent

Ver resumen del dia:
aureport -ts today

Ver logs en tiempo real:
tail -f /var/log/audit/audit.log

## Estado del servicio

Verificar si esta corriendo:
systemctl status auditd

## Este script configura

- Tamaño maximo de logs: 50 MB
- Rotar los logs al alcanzar el tamaño configurado; la retención se controla aparte
- Registrar avisos de espacio bajo y suspender la escritura al alcanzar el umbral administrativo crítico
- Reglas persistentes OrangeBox para registrar eventos críticos
- Aplicar la inmutabilidad (`-e 2`) solamente después de validar las reglas cargadas

## Que NO hace auditd

No evita ataques (solo los registra)
No consume muchos recursos (es liviano)
No reemplaza al firewall

## Que hace este script

### 4.1.1.1 - Instalar auditd
Verifica e instala audit y audit-libs

### 4.1.1.2 - Habilitar auditd
Configura auditd para iniciar automaticamente y asegura que este corriendo

### 4.1.1.3 - Tamaño de logs
Configura max_log_file = 50 MB

### 4.1.1.4 - Rotación de logs
Configura `max_log_file_action = ROTATE`. La retención se administra con la política operativa del servidor.

### 4.1.1.5 - Acciones por falta de espacio
Configura `space_left_action = SYSLOG` y `admin_space_left_action = SUSPEND`; no apaga el host automáticamente.

### Reglas de auditoria (4.1.2.x)

| Control | Eventos monitoreados |
|---------|---------------------|
| 4.1.2.1 | Modificaciones de fecha/hora |
| 4.1.2.2 | Modificaciones de usuario/grupo |
| 4.1.2.3 | Modificaciones de red |
| 4.1.2.4 | Modificaciones de MAC/SELinux |
| 4.1.2.5 | Eventos de login/logout |
| 4.1.2.6 | Informacion de sesion |
| 4.1.2.7 | Cambios de permisos (chmod, chown) |
| 4.1.2.8 | Intentos fallidos de acceso |
| 4.1.2.9 | Eventos de montaje |
| 4.1.2.10 | Eliminacion de archivos |
| 4.1.2.11 | Cambios en sudoers |
| 4.1.2.12 | Comandos ejecutados con sudo |
| 4.1.2.13 | Carga/descarga de modulos del kernel |
| 4.1.2.14 | Configuracion inmutable (protege reglas) |

## Uso

chmod +x auditd-hardening.sh

./auditd-hardening.sh

./auditd-hardening.sh --fix

## Recuperación de reglas inmutables

En RHEL/AlmaLinux/Rocky/CentOS 7–10, `--fix` respalda primero la configuración y comprueba las reglas cargadas en memoria. Si el kernel ya está en `enabled 2` y faltan reglas, prepara `/etc/audit/rules.d/98-orangebox-baseline.rules` y devuelve código `3` para indicar que se requiere un reinicio controlado. No reinicia el servidor automáticamente. En la ventana de mantenimiento, revise los archivos `*.rules`, confirme que `-e 2` quede al final y reinicie.

Después del arranque, valide:

```bash
auditctl -s
auditctl -l
systemctl --no-pager --full status auditd
ausearch -ts recent
aureport -ts today
```

El código `3` significa que hay una acción de mantenimiento pendiente; no debe interpretarse como hardening completado.

## Verificacion

auditctl -l
ausearch -ts recent
aureport -ts today

## Logs de auditoria

/var/log/audit/audit.log

## Autor

Felipe Roman
Web: www.orangebox.cl
Email: froman@orangebox.cl

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
