# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x audit-listening-services.sh
```

# Script: audit-listening-services.sh

Script para auditar que servicios hay en escucha en nuestro servidor y sugerir acciones segun CIS 2.4.

## Que hace este script

1. Muestra todos los puertos en escucha (LISTEN)
2. Identifica el servicio y paquete asociado
3. Sugiere que hacer: ELIMINAR, CONFIGURAR LOCAL, MANTENER, REVISAR
4. Muestra conexiones establecidas activas
5. Lista servicios habilitados al arranque
6. Genera comandos sugeridos para corregir

## Uso

```
chmod +x audit-listening-services.sh

./audit-listening-services.sh
```

## Servicios identificados

| Puerto | Servicio | Accion sugerida |
|--------|----------|-----------------|
| 21 | FTP | ELIMINAR (inseguro) |
| 22 | SSH | MANTENER (necesario) |
| 23 | Telnet | ELIMINAR (inseguro) |
| 25 | SMTP | CONFIGURAR LOCAL |
| 53 | DNS | ELIMINAR (si no es servidor DNS) |
| 80/443 | HTTP/HTTPS | ELIMINAR (si no es servidor web) |
| 110/143/993/995 | Correo | ELIMINAR (si no es servidor correo) |
| 139/445 | Samba | ELIMINAR |
| 389 | LDAP | ELIMINAR |
| 3306 | MySQL | ELIMINAR (si no es BD) |
| 5432 | PostgreSQL | ELIMINAR (si no es BD) |
| 3128 | Squid | ELIMINAR |

## Comandos utiles

```
systemctl stop <servicio>
systemctl disable <servicio>
yum remove <paquete>
systemctl mask <servicio>
```

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
