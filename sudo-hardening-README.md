# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x sudo-hardening.sh
```

# Script: sudo-hardening.sh

Script para configurar hardening de sudo según CIS Benchmark secciones 5.2.x y mejores prácticas de seguridad.

**Compatibilidad:** RHEL 7,8,9,10 (CentOS, Rocky Linux, AlmaLinux)

## Por qué es importante endurecer sudo

sudo es la puerta que permite a usuarios normales ejecutar comandos con privilegios de root. Si no la proteges bien, un atacante que comprometa una cuenta de usuario normal puede escalar privilegios y tomar el control total del servidor. Un solo sudo mal configurado puede ser el talón de Aquiles de tu infraestructura.

#### Timeout de autenticacion
Configura `Defaults timestamp_timeout=5`

**Que hace:** Reduce el tiempo que sudo recuerda la contraseña de 15 minutos a 5 minutos.

**Por que es importante:** Si un usuario se aleja de su terminal, un atacante tiene menos tiempo para usar sus privilegios sudo.

#### Reseteo de variables de entorno
Configura `Defaults env_reset`

**Que hace:** Limpia las variables de entorno antes de ejecutar comandos con sudo.

**Por que es importante:** Previene que un atacante pueda inyectar variables de entorno maliciosas (como LD_PRELOAD) que podrian ejecutar codigo arbitrario.

## Verificacion de sintaxis

El script valida la sintaxis de /etc/sudoers con `visudo -c` despues de cada cambio. Si hay errores, restaura el backup automaticamente.

## Uso
```
chmod +x sudo-hardening.sh

./sudo-hardening.sh

./sudo-hardening.sh --fix
```

## Verificacion post-ejecucion

```
visudo -c
sudo -l
cat /etc/sudoers | grep -E 'use_pty|logfile|timestamp_timeout|env_reset'
tail -f /var/log/sudo.log
```

## Comandos de sudo utiles

# Ver que comandos puede ejecutar el usuario actual
```
sudo -l
```

# Ejecutar comando y ver log
```
sudo whoami
tail -1 /var/log/sudo.log
```

## Para agregar un usuario a sudo

```
echo "usuario ALL=(ALL) ALL" >> /etc/sudoers.d/usuario
visudo -c
```

## Backup

Las configuraciones se respaldan en /root/sudo-backup-fecha/

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
