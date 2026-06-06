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
                         SISTEMA DE ACCESO CONTROLADO
                        Hardening por: www.orangebox.cl
*******************************************************************************

Este servidor ha sido endurecido siguiendo estandares de seguridad CIS Benchmark.
El acceso no autorizado esta estrictamente prohibido.

CUALQUIER INTENTO DE ACCESO NO AUTORIZADO SERA:
- Registrado y monitoreado
- Reportado a las autoridades competentes
- Utilizado con fines legales

AL INGRESAR ACEPTA:
- Las condiciones de uso del sistema
- Que su actividad puede ser monitoreada las 24/7
- Que la informacion obtenida es confidencial
- Que los intentos no autorizados seran penalizados

*******************************************************************************

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
