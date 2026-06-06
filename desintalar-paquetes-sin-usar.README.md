# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x desintalar-paquetes-sin-usar.README.md.sh
```

# Script: desintalar-paquetes-sin-usar.sh

Script para eliminar paquetes innecesarios y reducir la superficie de ataque del sistema.

## Que paquetes elimina

### SELinux (si no se usa)
- setroubleshoot, setroubleshoot-server, setroubleshoot-plugins
- mcstrans

### X Window (interfaz grafica - innecesaria en servidores)
- xorg-x11-server-Xorg, xorg-x11-utils, xorg-x11-xauth
- xorg-x11-server-common, xorg-x11-fonts, xorg-x11-drivers

### Servicios de red innecesarios
- avahi (descubrimiento de servicios)
- cups (impresion)
- dhcp (servidor DHCP)
- bind (servidor DNS)
- rpcbind, ypbind, ypserv

### Servicios de correo (si no se usa)
- sendmail, postfix, dovecot

### Herramientas de desarrollo (produccion)
- gcc, gcc-c++, make, automake, autoconf, cmake
- git, subversion
- kernel-devel, kernel-headers

### Herramientas de depuracion
- strace, ltrace, gdb, valgrind, systemtap, crash

### Compatibilidad y juegos
- compat-libstdc++-33, compat-db, compat-libcap1
- gnome-games, kdegames, fortune-mod

### Otros servicios inseguros o innecesarios
- telnet, telnet-server (inseguro)
- ftp, vsftpd, tftp (inseguro)
- nfs-utils, nfs-server (si no se usa)
- samba, samba-server (si no se usa)
- squid, httpd, nginx (si no se usa)
- mariadb, mysql, postgresql (si no se usa)

## Uso

```
chmod +x remove-unneeded-packages.sh

./remove-unneeded-packages.sh

./remove-unneeded-packages.sh --fix
```

## Opciones

sin opciones: Solo verificacion, no elimina nada
--fix o -f: Elimina los paquetes encontrados

## Precauciones

- Revise que NO necesita los paquetes antes de eliminar
- Especial cuidado con:
  - httpd, nginx (servidores web)
  - mariadb, mysql, postgresql (bases de datos)
  - postfix, sendmail (servicios de correo)
  - squid (proxy)

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
