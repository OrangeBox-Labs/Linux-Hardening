# Linux Hardening Scripts

**Diseñado y desarrollado por Felipe Román**  
**Web: [www.orangebox.cl](https://www.orangebox.cl)**

Scripts de hardening para servidores Linux basados en estándares de cyberseguridad CIS Benchmarks.

## ¡Bienvenido a los scripts de hardening de OrangeBox Labs!

Hola a todos,

Les comparto una colección de scripts para hacer hardening de seguridad en sus servidores Linux. Están pensados para que sean:

- Fáciles de usar: Todos siguen el mismo formato y están escritos en Bash.
- 100% transparentes: Pueden ver el código, modificarlo y adaptarlo a sus necesidades. 
- En constante evolución: Vamos a seguir subiendo más scripts, así que pasen de vez en cuando a mirar.

"Tiramos toda la carne a la parrilla" ¡No guardamos secretos!, creemos que la seguridad se construye entre todos, con código abierto y sin vueltas.

## Requisito previo (no es opcional)

Los scripts de hardening asumen que tu Linux está instalado **como Dios manda**. Si no, pueden fallar o no proteger del todo.

Te dejo este video donde instalamos un servidor Linux seguro paso a paso. **Haz esto primero**.

[![Instalación de Linux segura - Video obligatorio](https://img.youtube.com/vi/utOnUELYFC0/hqdefault.jpg)](https://youtu.be/utOnUELYFC0)

*Haz clic en la imagen para ver el video*

Después de verlo y aplicarlo, recién ahí ejecuta los scripts.


### ¿Dónde encontrar más?

No solo vivimos de scripts. Tenemos un par de lugares donde seguimos hablando de seguridad y servidores:

- 📝 **El blog**: Acá escribimos con más detalle sobre hardening, Zero Trust, instalaciones seguras y todo acerca de Infraestructura y servidores.
  → https://www.orangebox.cl/blog/

- 🎥 **YouTube**: Subimos videos mostrando ataques y cómo defenderte. guías y recomendaciones.
  → https://www.youtube.com/@OrangeBoxLinux

- 🌐 **WEB**: Nuestra empresa!
  → https://www.orangebox.cl

Si necesitan algo en particular o tienen una idea para mejorar estos scripts, déjennos un comentario en nuestro canal de YouTube. Allí también encontrarán varios videos explicando cómo se hacen algunos ataques y, lo más importante, cómo protegerse de ellos.


Gracias por ser parte de esta comunidad! 

— Felipe Román
  www.orangebox.cl


## Scripts Disponibles

| Script | Función | README |
|--------|---------|--------|
| `cis-benchmark-check.sh` | Prueba de cumplimiento CIS, con mitigaciones| [README](cis-benchmark-check-README.md) |
| `ssh-hardening.sh` | Hardening de SSH basado en CIS| [README](ssh-hardening-README.md) |
| `ssh-hardening-complete.sh` | Hardening de SSH basado en ssh-audit| [README](ssh-hardening-complete-README.md) |
| `password-hardening.sh` | Políticas de contraseñas | [README](password-hardening-README.md) |
| `grub-hardening.sh` | Hardening para GRUB | [README](grub-hardening-README.md) |
| `FS-hardening.sh` | Sistema de archivos | [README](FS-hardening.README.md) |
| `sudo-hardening.sh` | Hardening de sudo | [README](sudo-hardening-README.md) |
| `auditd-hardening.sh` | Auditoría del sistema | [README](auditd-hardening-README.md) |
| `selinux-secure-setup.sh` | Configuración SELinux | [README](selinux-secure-setup-README.md) |
| `kernel-hardening.sh` | Parámetros de kernel | [README](kernel-hardening-README.md) |
| `network-hardening.sh` | Hardening de red | [README](network-hardening-README.md) |
| `cron-hardening.sh` | Restricción de cron | [README](cron-hardening-README.md) |
| `disable-usb-storage.sh` | Deshabilitar USB | [README](disable-usb-storage.README.md) |
| `cpu-hardening.sh` | Mitigaciones CPU | [README](cpu-hardening-README.md) |
| `rsyslog-hardening.sh` | Hardening de logs | [README](rsyslog-hardening-README.md) |
| `configure-time-sync.sh` | Sincronización horaria | [README](configure-time-sync-README.md) |
| `configure-login-banners.sh` | Banners de login | [README](configure-login-banners-README.md) |
| `aide-install.sh` | Monitor de integridad | [README](aide-install-README.md) |
| `generate-iptables-rules.sh` | Reglas iptables | [README](generate-iptables-rules-README.md) |
| `audit-listening-services.sh` | Auditoría de servicios | [README](audit-listening-services-README.md) |
| `desintalar-paquetes-sin-usar.sh` | Limpieza de paquetes | [README](desintalar-paquetes-sin-usar.README.md) |
| `desintalar-servicios-sin-usar.sh` | Limpieza de servicios | [README](desintalar-servicios-sin-usar-README.md) |
| `remove-xinetd.sh` | Eliminar xinetd | [README](remove-xinetd-README.md) |
| `remove-gui-hardening.sh` | Eliminar GUI | [README](remove-gui-hardening-README.md) |

## Uso Básico

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x *.sh
```

# Verificación (modo solo lectura)
```
./ssh-hardening.sh
```

# Aplicar cambios
```
./ssh-hardening.sh --fix
```


## Distribuciones Compatibles

| Distribución | Versiones | Estado |
|--------------|-----------|--------|
| Red Hat Enterprise Linux (RHEL) | 7, 8, 9 | Probado |
| CentOS | 7, 8 | Probado |
| Rocky Linux | 8, 9 | Probado |
| AlmaLinux | 8, 9 | Probado |
| Fedora | 38, 39, 40 | Compatible |

**NOTA IMPORTANTE:** Estos scripts NO son compatibles con Debian, Ubuntu o derivados debido a diferencias fundamentales en:
- Sistema de autenticación PAM (archivos y sintaxis diferentes)
- Gestión de paquetes (apt vs yum/dnf)
- Sistema de seguridad (AppArmor vs SELinux)
- Ubicación de archivos de configuración


## Licencia

MIT

