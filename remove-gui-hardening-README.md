# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x remove-gui-hardening.sh
```

# Script: remove-gui-hardening.sh

Script para eliminar interfaz grafica y aplicar hardening en servidores Linux reduciendo la superficie atacable.
Basado en CIS Benchmark secciones 1.8.1 a 1.8.4.

## Que hace este script

### 1.8.1 - Eliminar GNOME Display Manager
- Elimina GDM y otros display managers (LightDM, SDDM)
- Elimina grupos de paquetes de GNOME Desktop

### 1.8.2 - Configurar banner de GDM (si se mantiene GUI)
- Configura mensaje de advertencia en pantalla de login
- El banner incluye "Autorizado por: www.orangebox.cl"

### 1.8.3 - Deshabilitar muestra de ultimo usuario
- Evita que se muestre el ultimo usuario que inicio sesion

### 1.8.4 - Deshabilitar XDMCP
- Deshabilita protocolo inseguro X Display Manager Control Protocol

### Adicional
- Elimina paquetes de X Window System
- Cambia sistema a modo texto (runlevel 3)

## Que elimina

- GDM, LightDM, SDDM (display managers)
- Xorg, X11, X Window System
- GNOME Desktop, KDE, Plasma
- Paquetes graficos innecesarios

## Uso

```
chmod +x remove-gui-hardening.sh

./remove-gui-hardening.sh

./remove-gui-hardening.sh --fix
```

## Opciones

sin opciones o --fix: Aplica las correcciones
--check: Solo verificacion

## Advertencia

Este script eliminara la interfaz grafica permanentemente.
Despues de ejecutarlo, solo tendra acceso por consola o SSH.
Haga backup de datos importantes antes de ejecutar.

## Despues de ejecutar

```
systemctl get-default
```
# Debe mostrar: multi-user.target

## Para restaurar modo grafico

```
systemctl set-default graphical.target
yum install gdm -y
systemctl start gdm
```

## Backup

Los archivos de configuracion se respaldan en:
/root/gui-backup-fecha/

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
