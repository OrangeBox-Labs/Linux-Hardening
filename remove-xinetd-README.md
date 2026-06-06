# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x remove-xinetd.sh
```

# Script: remove-xinetd.sh
Basado en CIS Benchmark seccion 2.1.1.

# Script para eliminar xinetd y servicios innecesarios.

## ¿Saben cuál ha sido el único servidor que me han hackeado en más de 20 años? El día que se me ocurrió publicar un servicio a través de inetd directo a la WAN. Nunca más. Si tienen inetd activo, háganme caso: quítenlo.

### ¿Por qué es un peligro exponer inetd o xinetd a internet? Te lo resumo corto:

1. Entran y son root (lo peor que te puede pasar)

Si el propio inetd/xinetd tiene una vulnerabilidad (y las ha tenido), un atacante puede ejecutar código en tu servidor con todos los poderes. O sea, toman el control total. Fin del cuento.

2. Se saltan tu firewall sin pedir permiso

Hay vulnerabilidades viejas pero conocidas donde, si tienes activado cierto servicio interno (tcpmux-server), el atacante puede entrar por el puerto 1 y acceder a todo lo que maneja xinetd, ignorando completamente tus reglas de firewall. Pensabas que solo entraban desde tu red local? Pues no.

3. Te tiran el servidor con un simple ataque (DoS)

Un atacante puede explotar una vulnerabilidad y hacer que xinetd o el servicio que maneja se caiga. Tus servicios web, SSH o lo que tengas quedan inaccesibles. Adiós disponibilidad.

4. Servicios viejos y chantas

Xinetd/inetd suelen levantar servicios antiguos como Telnet o rsh. Telnet manda las contraseñas en texto plano (cualquiera con un sniffer las ve) y rsh se autentica con una confianza que es un chiste. Si tienes algo así expuesto, es como dejar la llave puesta en la puerta.

5. Dejas info sensible al alcance de cualquiera

En versiones viejas de algunas distribuciones, xinetd creaba archivos con permisos 666 (todos los usuarios del sistema podían leer y escribir). Si un atacante logra entrar con un usuario básico, se encuentra con un festín de archivos para mirar o modificar.

La moraleja de todo esto:

Exponer inetd/xinetd a internet no es como exponer un servidor web moderno. Es abrir la puerta de tu casa con un candado oxidado y además poner un cartelito que dice "patada fuerte para abrir".

Por eso el mantra en seguridad es: si ves inetd o xinetd, lo matas. No hay vuelta que darle.


## Que hace este script

### 2.1.1 - Eliminar xinetd
- Elimina el paquete xinetd
- Detiene y deshabilita el servicio
- Elimina inetd (alternativa antigua)

### Adicional
- Detecta servicios legacy activos (telnet, rsh, rlogin, tftp)
- Verifica puertos inseguros abiertos

## Que elimina

- xinetd (superdaemon)
- Servicios xinetd: chargen, daytime, discard, echo, time
- Servicios legacy: telnet, rsh, rlogin, rexec, tftp, finger, talk

## Por que es importante

xinetd gestiona multiples servicios de red. Muchos de estos servicios:
- Son inseguros (telnet, rsh, rlogin)
- No son necesarios en servidores modernos
- Aumentan la superficie de ataque

## Uso
```
chmod +x remove-xinetd.sh

./remove-xinetd.sh

./remove-xinetd.sh --fix
```

## Opciones

sin opciones o --fix: Aplica las correcciones
--check: Solo verificacion

## Verificacion manual

```
rpm -qa | grep xinetd
systemctl status xinetd
ss -tlnp | grep -E ':(23|513|514|69|79)'
```

## Si necesita xinetd para algun servicio especifico, asegúense de haber aplicado todo el resto de los scripts de hardening
## y por el amor de dios!, no publiquen ese servicio directo a internet. 

- No ejecutes este script
- O comenta la seccion remove_xinetd en el script
- Asegurese de deshabilitar servicios no necesarios dentro de xinetd

## Backup

Los archivos de configuracion se respaldan en:
/root/xinetd-backup-fecha/

## Para restaurar xinetd

yum install xinetd -y
cp /root/xinetd-backup-fecha/xinetd.conf /etc/
cp -r /root/xinetd-backup-fecha/xinetd.d/* /etc/xinetd.d/
systemctl start xinetd

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
