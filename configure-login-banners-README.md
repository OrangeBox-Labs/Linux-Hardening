# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x configure-login-banners.sh
```

# Script: configure-login-banners.sh

Script para configurar banners de advertencia de login segun CIS Benchmark secciones 1.7.1 a 1.7.7.

## Que configura

### Archivos de banner
- /etc/motd - Mensaje del dia (se muestra despues del login exitoso)
- /etc/issue - Banner para login local (consola fisica)
- /etc/issue.net - Banner para login remoto (SSH, telnet)

### Permisos
- 644 (root:root) para los tres archivos
- Configuracion de Banner en SSH (/etc/ssh/sshd_config)

## Banner configurado

*******************************************************************************
                         SISTEMA DE ACCESO RESTRINGIDO
                           www.orangebox.cl
*******************************************************************************

Solo usuarios autorizados pueden acceder a este sistema.
El acceso o uso no autorizado esta prohibido.

La actividad realizada en este sistema puede ser registrada y revisada
conforme a las politicas de la organizacion y a la legislacion aplicable.
Si no cuenta con autorizacion, desconectese inmediatamente.

*******************************************************************************

El texto del banner es deliberadamente generico: no informa el estado de SELinux
ni enumera el firewall, herramientas de integridad o mecanismos de deteccion.

## Mensaje posterior al login (MOTD dinámico)

El banner se muestra desde /etc/profile.d/99-orangebox-motd.sh en shells interactivas. Incluye logotipo OrangeBox, aviso de acceso restringido, IP remota SSH cuando existe SSH_CONNECTION, IP local del servidor, uptime normalizado, carga promedio de 1/5/15 minutos y kernel activo.

/etc/motd se deja vacío para evitar duplicar el banner. Un archivo estático no puede conocer la IP remota específica de cada sesión. El perfil no se ejecuta para SFTP ni para comandos SSH no interactivos; el aviso previo de /etc/issue.net sigue aplicando.

Si FIGlet está disponible con la fuente small, se utiliza el logotipo coloreado. En modo --fix, si falta, se intenta instalar desde los repositorios ya configurados; si la instalación falla o no existe la fuente, se muestra el ASCII integrado. No se habilitan repositorios automáticamente ni se ejecuta una actualización completa del sistema.

## Backup

Los archivos existentes se respaldan en:
/root/banners-backup-fecha/

Para restaurar:
```
cp /root/banners-backup-fecha/motd.bak /etc/motd
cp /root/banners-backup-fecha/issue.bak /etc/issue
cp /root/banners-backup-fecha/issue.net.bak /etc/issue.net
```

## Uso

```
chmod +x configure-login-banners.sh

./configure-login-banners.sh

./configure-login-banners.sh --fix
```

## Opciones

sin opciones: Solo verificacion, no aplica cambios
--fix o -f: Aplica las configuraciones y crea backup

## Verificacion

```
cat /etc/motd
cat /etc/issue
cat /etc/issue.net
stat /etc/motd /etc/issue /etc/issue.net
grep Banner /etc/ssh/sshd_config
```

## Prueba

Login local: login (desde consola)
Login remoto: ssh localhost

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
