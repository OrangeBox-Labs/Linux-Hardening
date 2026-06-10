# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x rsyslog-hardening.sh
```

# Script: rsyslog-hardening.sh

Script para configurar rsyslog y journald segun CIS Benchmark secciones 4.2.1 a 4.2.3.

## Importancia de los logs y logs remotos en la seguridad

Los logs (registros) son la memoria del servidor. Registran quien accedio, que hizo, cuando lo hizo y desde donde. Sin logs, es imposible saber que paso durante un incidente de seguridad.

Un atacante que compromete un servidor normalmente intentara borrar los logs locales para cubrir sus huellas. Por eso es fundamental tener logs remotos: copiar los logs a otro servidor (servidor de logs central) donde el atacante no pueda acceder.

Con logs remotos se puede:
- Detectar un ataque en curso
- Investigar como entro el atacante
- Saber que informacion fue comprometida
- Cumplir con normativas de seguridad (PCI DSS, ISO 27001)
- Tener evidencia legal en caso de juicio

Sin logs remotos, si un atacante borra los logs locales, no quedara registro de su actividad.

## Opción --remote: Configuración de envío de logs remoto

El script permite configurar el envío de logs a un servidor centralizado de logs separadamente del hardening base.

### Sintaxis

| Comando | Descripción |
|---------|-------------|
| `./rsyslog-hardening.sh --remote <IP>` | Envío por UDP al puerto 514 (default) |
| `./rsyslog-hardening.sh --remote <IP> <PORT>` | Envío por UDP con puerto personalizado |
| `./rsyslog-hardening.sh --remote <IP> tcp` | Envío por TCP al puerto 514 |
| `./rsyslog-hardening.sh --remote <IP> <PORT> tcp` | Envío por TCP con puerto personalizado |

### Ejemplos

# Configurar envío a servidor remoto por UDP
```
./rsyslog-hardening.sh --remote 192.168.1.100
```

# Configurar envío a servidor remoto por TCP con puerto 5514
```
./rsyslog-hardening.sh --remote 192.168.1.100 5514 tcp
```

# Primero aplicar hardening base, luego configurar remoto
```
./rsyslog-hardening.sh --fix && ./rsyslog-hardening.sh --remote 10.0.0.1
```


### Formatos de envio

| Formato | Protocolo | Ejemplo | Uso |
|---------|-----------|---------|-----|
| *.* @host:514 | UDP | *.* @192.168.1.100:514 | Rapido, menos confiable |
| *.* @@host:514 | TCP | *.* @@192.168.1.100:514 | Mas confiable, mas lento |
| *.* @@host:6514 | TCP con TLS | *.* @@192.168.1.100:6514 | Seguro, requiere certificados |

### Configurar servidor de logs central

En el servidor que recibira los logs, editar /etc/rsyslog.conf y descomentar:

$ModLoad imtcp
$InputTCPServerRun 514

Luego:
```
systemctl restart rsyslog
```

> No olviden abrir el puerto TCP 514 en su firewall.

## Que hace este script

### 4.2.1.1 - Instalar rsyslog
Verifica e instala rsyslog

### 4.2.1.2 - Habilitar rsyslog
Configura rsyslog para iniciar automaticamente y asegura que este corriendo

### 4.2.1.3 - Permisos de archivos de log
Configura:
- $FileCreateMode 0640 (archivos de log)
- $DirCreateMode 0750 (directorios de log)
- $Umask 0027 (mascara de permisos)

Esto asegura que solo root y usuarios autorizados puedan leer los logs.

### 4.2.1.4 - Envio a host remoto
Configura el envio de logs a un servidor central si se solicita

### 4.2.1.5 - Aceptacion de logs remotos
Detecta si el sistema esta configurado como servidor de logs

### 4.2.2.1 - Journald a rsyslog
Configura ForwardToSyslog=yes para que journald envie logs a rsyslog

### 4.2.2.2 - Compresion de archivos
Configura Compress=yes para comprimir archivos grandes

### 4.2.2.3 - Almacenamiento persistente
Configura Storage=persistent para guardar logs en disco

### 4.2.3 - Permisos de logs
Verifica y corrige permisos de archivos .log

## Uso
```
chmod +x rsyslog-hardening.sh

./rsyslog-hardening.sh

./rsyslog-hardening.sh --fix
```

## Verificacion

```
systemctl status rsyslog
tail -f /var/log/messages
journalctl -xe
```

## Verificar envio de logs remotos

```
grep "^[^#].*@.*" /etc/rsyslog.conf
ss -tunap | grep 514
```

## Backup

Las configuraciones se respaldan en /root/rsyslog-backup-fecha/

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
