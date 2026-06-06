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
```

## Opciones

sin opciones o --fix: Aplica las correcciones
--check: Solo verificacion

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
