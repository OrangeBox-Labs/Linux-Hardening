# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x desintalar-servicios-sin-usar.sh
```

# Script: remove-unnecessary-services.sh

Script interactivo para eliminar servicios innecesarios y reducir la superficie de ataque del sistema.
Basado en CIS Benchmark secciones 2.2.2 a 2.3.5.

## Modo de uso

El script sigue este flujo para cada paquete:

1. Verifica si el paquete esta instalado
2. Muestra informacion y pregunta si desea eliminarlo
3. Simula la eliminacion con `yum remove --assumeno`
4. Parsea el archivo de transaccion generado para obtener exactamente que paquetes se eliminaran
5. Muestra la lista completa de dependencias
6. Pide confirmacion final antes de proceder

Este metodo es rapido y preciso porque yum/dnf ya calculan las dependencias internamente.

```
chmod +x remove-unnecessary-services.sh

./remove-unnecessary-services.sh
```

## Que servicios revisa

### Servidores de red (CIS 2.2.2 - 2.2.17)

| Paquete | CIS ID | Descripcion |
|---------|--------|-------------|
| xorg-x11-server* | 2.2.2 | Interfaz grafica X Window |
| avahi-autoipd | 2.2.3 | Descubrimiento de servicios mDNS |
| cups | 2.2.4 | Servidor de impresion |
| dhcp | 2.2.5 | Servidor DHCP |
| openldap-servers | 2.2.6 | Servidor LDAP |
| bind | 2.2.7 | Servidor DNS |
| vsftpd | 2.2.8 | Servidor FTP |
| httpd | 2.2.9 | Servidor web HTTP |
| dovecot | 2.2.10 | Servidor IMAP/POP3 |
| samba | 2.2.11 | Servidor Samba/CIFS |
| squid | 2.2.12 | Proxy HTTP |
| net-snmp | 2.2.13 | SNMP |
| ypserv | 2.2.14 | Servidor NIS |
| telnet-server | 2.2.15 | Servidor Telnet |
| nfs-utils | 2.2.16 | Servidor NFS |
| rpcbind | 2.2.17 | RPC bind |

### Clientes inseguros (CIS 2.3.1 - 2.3.5)

| Paquete | CIS ID | Descripcion |
|---------|--------|-------------|
| ypbind | 2.3.1 | Cliente NIS |
| rsh | 2.3.2 | Cliente RSH |
| talk | 2.3.3 | Cliente Talk |
| telnet | 2.3.4 | Cliente Telnet |
| openldap-clients | 2.3.5 | Cliente LDAP |


## Verificacion post-ejecucion

```
systemctl list-units --type=service | grep running
ss -tlnp
rpm -qa | grep -E '(httpd|dhcp|bind|vsftpd|samba|squid)'
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
