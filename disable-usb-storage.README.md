# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x disable-usb-storage.README.md.sh
```

# Script: disable-usb-storage.sh

Script para deshabilitar USB Storage en sistemas Linux basado en el control CIS 1.1.24.

## Autor

- **Felipe Roman**
- Web: www.orangebox.cl
- Email: froman@orangebox.cl

## Que hace este script

Deshabilita el modulo `usb-storage` del kernel para prevenir el uso de dispositivos de almacenamiento USB, reduciendo la superficie de ataque fisica y posibles inyecciones de malware a nuestro servidor de manera física.

## Controles CIS

| CIS ID | Control | Descripcion |
|--------|---------|-------------|
| 1.1.24 | Disable USB Storage | Previene la carga del modulo usb-storage |

## Requisitos

- Sistemas RHEL / CentOS / Rocky / AlmaLinux
- Acceso root
- Kernel con soporte para modulos

## Uso

```
chmod +x disable-usb-storage.sh
./disable-usb-storage.sh
./disable-usb-storage.sh --fix
```


---

**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs
