# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x generate-iptables-rules.sh
```

# Script: generate-iptables-rules.sh

Script interactivo que genera un archivo de reglas iptables personalizado, !una manera fácil de configurar y comenzar un firewall muy potente si no sabes como manejar iptables!, puedes basarte en las reglas que crea y desde ahí construir tu propio firewall.

## Que hace este script

1. Detecta puertos en escucha (excluyendo SSH)
2. Pregunta que puertos desea permitir en el firewall
3. Genera script en /root/iptables.sh con reglas de firewall
4. Genera script en /root/ip6tables.sh para IPv6

## SSH SIEMPRE PERMITIDO
Cuando era un mozuelo, levanté un hermoso firewall en un servidor remoto en producción... pero dejé cerrado el puerto 22, me quedé afuera de inmediato.
Cosas que uno jamás olvidará...

SSH (puerto 22) siempre esta permitido e incluye protecciones anti-DDoS: 
- Maximo 4 conexiones nuevas por minuto por IP
- Maximo 10 conexiones nuevas por segundo globales

## Protecciones incluidas

### Anti-DDoS
- SYN flood: limitado a 20 por segundo
- Conexiones nuevas: 10 por minuto por IP
- Paquetes invalidos y fragmentados bloqueados

### Hardening TCP
- Bloqueo de null packets
- Bloqueo de XMAS packets
- Bloqueo de syn-flood packets

### Connection Tracking
Permite conexiones establecidas y relacionadas

### ICMP (Ping)
Ping permitido desde cualquier origen

## Uso

```
chmod +x generate-iptables-rules.sh

./generate-iptables-rules.sh
```

## Aplicar reglas

```
sh /root/iptables.sh
sh /root/ip6tables.sh
systemctl enable iptables ip6tables
```

## Verificar reglas

```
iptables -L -n -v
iptables -L -n -v | grep -E "ACCEPT|DROP"
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
