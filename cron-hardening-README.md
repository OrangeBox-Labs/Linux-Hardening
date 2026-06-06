# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x cron-hardening.sh
```

# Script: cron-hardening.sh

Script para configurar hardening de cron y at segun CIS Benchmark secciones 5.1.1 a 5.1.8.

## Importancia del hardening de cron

Cron es el servicio que ejecuta tareas programadas automaticamente (backups, rotacion de logs, monitoreo, etc.). Si un atacante puede modificar las tareas de cron, puede ejecutar codigo malicioso periodicamente.

Los permisos incorrectos en los archivos de cron permiten que usuarios no autorizados agreguen tareas maliciosas. Por eso es fundamental:
- Restringir quien puede programar tareas (solo root)
- Asegurar permisos estrictos en archivos de cron
- Eliminar archivos de denegacion obsoletos

## Que hace este script

### 5.1.1 - Habilitar y ejecutar cron
El servicio cron debe estar activo para ejecutar tareas del sistema (rotacion de logs, analisis de seguridad, etc.). Si no se usa cron, se puede desinstalar.

### 5.1.2 - Permisos de /etc/crontab
El archivo principal de cron debe tener permisos 600 (solo lectura/escritura para root)

### 5.1.3 - Permisos de /etc/cron.hourly
Directorio para tareas que se ejecutan cada hora. Permisos 700 (solo root puede acceder)

### 5.1.4 - Permisos de /etc/cron.daily
Directorio para tareas diarias. Permisos 700

### 5.1.5 - Permisos de /etc/cron.weekly
Directorio para tareas semanales. Permisos 700

### 5.1.6 - Permisos de /etc/cron.monthly
Directorio para tareas mensuales. Permisos 700

### 5.1.7 - Permisos de /etc/cron.d
Directorio para archivos de cron adicionales. Permisos 700

### 5.1.8 - Restringir usuarios de cron
Elimina /etc/cron.deny y crea /etc/cron.allow con solo usuario root. Solo root podra programar tareas.

### 5.1.9 - Restringir usuarios de at
Elimina /etc/at.deny y crea /etc/at.allow con solo usuario root. Solo root podra usar el comando 'at'.

## Uso

```
chmod +x cron-hardening.sh

./cron-hardening.sh

./cron-hardening.sh --fix
```

## Verificacion

```
systemctl status crond
ls -la /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d
cat /etc/cron.allow
cat /etc/at.allow
```

## Para agregar un usuario adicional a cron

```
echo "usuario" >> /etc/cron.allow
```

## Para eliminar cron completamente (si no se usa)

```
yum remove cronie -y
```

## Backup

Las configuraciones se respaldan en /root/cron-backup-fecha/

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
