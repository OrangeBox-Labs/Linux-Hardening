# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x aide-install.sh
```

# Script: aide-install.sh

Script para instalar y configurar AIDE (Advanced Intrusion Detection Environment) en sistemas Linux, basado en los controles CIS 1.3.1 y 1.3.2.

## Autor

- **Felipe Roman**
- Web: www.orangebox.cl
- Email: froman@orangebox.cl

## Que hace este script

- Verifica si AIDE esta instalado
- Si no esta instalado, lo instala usando yum o dnf
- Inicializa la base de datos de AIDE con `aide --init`
- Configura la base de datos definitiva
- Activa verificacion periodica via cron (diario a las 5:00 AM)
- No modifica repositorios ni configura fuentes externas

## Controles CIS

| CIS ID | Control | Descripcion |
|--------|---------|-------------|
| 1.3.1 | Install AIDE | Instala AIDE para monitoreo de integridad |
| 1.3.2 | Periodic AIDE Check | Configura verificacion diaria automatica |

## Requisitos

- Sistemas RHEL / CentOS / Rocky / AlmaLinux / Fedora
- Acceso root
- Repositorios configurados (se asume que el sistema funciona correctamente)

## Uso

```
chmod +x aide-install.sh
./aide-install.sh
./aide-install.sh --fix
```



**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura 
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs
