# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x configure-time-sync.sh
```

# Script: configure-time-sync.sh

Script para configurar sincronizacion de tiempo segun CIS Benchmark secciones 2.2.1.1 y 2.2.1.2.

## Que hace este script

### 2.2.1.1 - Instalar sistema de sincronizacion
- Verifica si chrony o NTP estan instalados
- Instala chrony si no hay ninguno
- Elimina duplicados (solo debe haber un servicio)

### 2.2.1.2 - Configurar chrony
- Configura servidores NTP (time.google.com, pool.ntp.org)
- Configura chrony para ejecutar como usuario chrony
- Inicia y habilita el servicio

### Adicional
- Fuerza sincronizacion inmediata
- Verifica estado de sincronizacion
- En EL6 con el paquete `ntp`, detecta si ya existe una tarea cron que reinicie `ntpd`
- Si falta, `--fix` agrega `/etc/cron.d/orangebox-ntp-refresh` para reiniciarlo cada 6 horas; la auditoría normal solo informa y no modifica
- El resultado del reinicio programado se registra en syslog con la etiqueta `orangebox-ntp-refresh`

## Servidores NTP configurados

- time.google.com
- pool.ntp.org
- south-america.pool.ntp.org
- cl.pool.ntp.org

## Uso

```
chmod +x configure-time-sync.sh

./configure-time-sync.sh

./configure-time-sync.sh --fix

# Solo validar/instalar el refresco cron de ntpd legacy en EL6
./configure-time-sync.sh --refresh-only
```

## Opciones

- Sin opciones: modo verificación, no modifica el sistema.
- `--fix`: aplica las correcciones generales de sincronización de tiempo.
- `--refresh-only`: solo verifica/instala la tarea cron de refresco de `ntpd` para EL6 con el paquete `ntp`; no modifica `ntp.conf`, no instala paquetes y no intenta ajustar la hora en ese momento.

## Verificacion

```
chronyc tracking
ntpq -p
timedatectl status
```

## Forzar sincronizacion manual

```
chronyc makestep
ntpdate -u time.google.com
```

## Refresco periódico de ntpd en EL6

La tarea queda en `/etc/cron.d/orangebox-ntp-refresh` y se ejecuta a los minutos 17 de las horas 00, 06, 12 y 18. Antes de crearla, el script busca tareas existentes en `/etc/crontab`, `/etc/cron.d/`, los crontabs de usuarios y el crontab de root para evitar duplicados. No se instala en sistemas que usan chrony ni fuera de EL6.

Verificar la tarea:

```
cat /etc/cron.d/orangebox-ntp-refresh
grep orangebox-ntp-refresh /var/log/messages
ntpq -pn
```

Este reinicio programado es una mitigación operativa para el caso legacy reportado, no un reemplazo del diagnóstico del reloj del sistema, la plataforma virtual o la fuente NTP.

## Ver logs

```
journalctl -u chronyd -f
journalctl -u ntpd -f
```

## Backup

Los archivos de configuracion se respaldan en:
/root/time-backup-fecha/

- /etc/chrony.conf
- /etc/sysconfig/chronyd
- /etc/ntp.conf
- /etc/sysconfig/ntpd

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
