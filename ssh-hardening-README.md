# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x ssh-hardening.sh
```

# Script: ssh-hardening.sh

Script para configurar hardening de SSH según CIS Benchmark secciones 5.3.1 a 5.3.21 y mejores practicas.

**Compatibilidad:** OpenSSH 7.4+ (RHEL 7, 8, 9, 10, CentOS 7, AlmaLinux, Rocky Linux)

## Importancia del hardening de SSH

SSH es la puerta de entrada principal a cualquier servidor. Es el servicio mas expuesto y el primer objetivo de los atacantes. Un servidor sin hardening de SSH es como una casa con la puerta principal sin cerrar.

Los ataques mas comunes contra SSH incluyen:
- Fuerza bruta (probar miles de contraseñas)
- Ataques de diccionario
- Explotacion de vulnerabilidades en versiones antiguas
- Intercepcion de sesiones (si no se usa cifrado fuerte)

El hardening de SSH reduce drasticamente la superficie de ataque.

> Para ejecutar esto de manera segura, si lo están haciendo de manera remota, NO se desconecten y vuelvan a conectar para probar si funcionó (podrían quedarse afuera), en vez de desconectarse, abran una nueva conexión de SSH para probar, si no funciona, pueden corregir errores desde la que dejaron abierta. 

## Que hace este script

### Permisos (CIS 5.3.1)
- Permisos 600 para /etc/ssh/sshd_config (solo root puede leer/escribir)

### 5.3.2 - Limitar acceso SSH
Permite especificar que usuarios o grupos pueden acceder por SSH.
Recomendado: AllowUsers admin usuario1

### 5.3.3 - LogLevel
Configura LogLevel INFO para registrar intentos de login fallidos y exitosos.

### 5.3.4 - X11 Forwarding
Deshabilita X11Forwarding. El reenvio de interfaz grafica no es necesario en servidores y aumenta riesgo.

### 5.3.5 - MaxAuthTries
Limita a 4 intentos de autenticacion por conexion. Previene fuerza bruta.

### 5.3.6 - IgnoreRhosts
Habilita IgnoreRhosts yes. Ignora archivos .rhosts (obsoletos e inseguros).

### 5.3.7 - HostbasedAuthentication
Deshabilita HostbasedAuthentication. Autenticacion basada en hosts es insegura.

### 5.3.8 - PermitRootLogin
Deshabilita login root. Obliga a usar usuario normal y luego sudo. Es la medida mas importante.

### 5.3.9 - PermitEmptyPasswords
Deshabilita contraseñas vacias. Nunca permitir acceso sin contraseña.

### 5.3.10 - PermitUserEnvironment
Deshabilita PermitUserEnvironment. Evita que usuarios carguen variables de entorno maliciosas.

### 5.3.11 - Ciphers (Cifrado)
Configura algoritmos de cifrado fuertes:
aes256-ctr, aes192-ctr, aes128-ctr

### 5.3.12 - MACs (Message Authentication Codes)
Configura algoritmos MAC fuertes:
hmac-sha2-512, hmac-sha2-256

### 5.3.13 - KexAlgorithms (Intercambio de claves)
Configura algoritmos de intercambio de claves seguros:
curve25519-sha256, curve25519-sha256@libssh.org, diffie-hellman-group16-sha512, diffie-hellman-group18-sha512, diffie-hellman-group-exchange-sha256

### 5.3.14 - Idle Timeout
Configura ClientAliveInterval 300 (5 minutos) y ClientAliveCountMax 0.
Desconecta sesiones inactivas automaticamente.

### 5.3.15 - LoginGraceTime
Configura LoginGraceTime 60 (1 minuto para completar login).

### 5.3.16 - Warning Banner
Configura Banner /etc/issue.net para mostrar advertencia legal antes del login.

### 5.3.17 - PAM
Habilita UsePAM yes para usar autenticacion PAM (integracion con sistema).

### 5.3.18 - AllowTcpForwarding
Deshabilita AllowTcpForwarding. Previene que usuarios usen el servidor como proxy.

### 5.3.19 - MaxStartups
Configura MaxStartups 10:30:60 para limitar conexiones simultaneas incompletas.

### 5.3.20 - MaxSessions
Configura MaxSessions 10 para limitar sesiones multiplexadas por conexion.

### Adicional - Protecciones extra
- Deshabilita compresion (previene ataques de canal lateral)
- Deshabilita GSSAPI y Kerberos authentication (si no se usan)
- Configura algoritmos de clave publica modernos segun version de OpenSSH

## Compatibilidad entre versiones de OpenSSH

El script detecta automaticamente la version de OpenSSH y aplica la directiva correcta:

| OpenSSH | RHEL | Directiva de algoritmos de clave |
|---------|------|----------------------------------|
| 7.4 - 8.x | RHEL 7, 8 | PubkeyAcceptedKeyTypes |
| 9.x+ | RHEL 9, 10 | PubkeyAcceptedAlgorithms |

**Algoritmos de clave publica configurados:**
ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,rsa-sha2-512,rsa-sha2-256

## Resumen rapido de parametros

| Parametro | Valor | Que previene |
|-----------|-------|--------------|
| PermitRootLogin | no | Atacante necesita usuario y contraseña |
| MaxAuthTries | 4 | Limita intentos de fuerza bruta |
| ClientAliveInterval | 300 | Desconecta sesiones inactivas |
| X11Forwarding | no | Evita reenvio de interfaz grafica |
| AllowTcpForwarding | no | Evita uso como proxy |
| LogLevel | INFO | Registra intentos sospechosos |
| Compression | no | Previene ataques de canal lateral |

## Uso
```
chmod +x ssh-hardening.sh
```

# Modo verificacion (solo muestra lo que cambiaria)
```
./ssh-hardening.sh
```

# Modo automatico (aplica los cambios)
```
./ssh-hardening.sh --fix
```
# o
```
./ssh-hardening.sh -f
```

## Antes de ejecutar

IMPORTANTE: Asegurese de tener:
1. Un usuario con sudo configurado (porque se deshabilitara login root)
2. Conexion SSH activa en otra terminal (por si algo falla)
3. Backup de /etc/ssh/sshd_config (el script lo hace automaticamente)

Recomendacion: Ejecute primero en modo verificacion para ver que cambios se aplicaran:

```
./ssh-hardening.sh
```

Luego aplique los cambios:

```
./ssh-hardening.sh --fix
```

## Verificacion post-ejecucion

# Ver configuracion activa
```
sshd -T
```

# Verificar sintaxis
```
sshd -t
```

# Ver servicio
```
systemctl status sshd
```
# o en sistemas mas antiguos
```
service sshd status
```

# Ver logs
```
tail -f /var/log/secure | grep sshd
```

# Ver version de OpenSSH
```
ssh -V
```

## Solucion de problemas

### Error: "Bad configuration option: PubkeyAcceptedAlgorithms"

Causa: OpenSSH version antigua (RHEL 7/8) no soporta esta directiva.

Solucion: El script ya detecta automaticamente la version y usa la directiva correcta. Si aun asi tiene problemas, verifique:

# Ver version de OpenSSH
```
ssh -V
```

# Ver directivas soportadas
```
sshd -T | grep -i pubkey
```

### Si queda bloqueado

Si se bloquea, desde la consola del servidor (no SSH) o desde otra sesion activa:

```
cp /root/ssh-backup-YYYYMMDD-HHMMSS/sshd_config /etc/ssh/sshd_config
systemctl restart sshd
```

### Ver error especifico

# Esto mostrara exactamente que linea causa problema
```
sshd -t
```

## Backup

Las configuraciones se respaldan en /root/ssh-backup-fecha-hora/

Backup incluye:
- /etc/ssh/sshd_config
- /etc/ssh/sshd_config.d/ (si existe)

## Notas adicionales

- El script NO modifica PasswordAuthentication - eso debe configurarse manualmente si se desea deshabilitar contraseñas y usar solo claves SSH
- Se recomienda combinar este hardening con:
  - Fail2ban para proteger contra fuerza bruta
  - Claves SSH en lugar de contraseñas
  - Autenticacion de dos factores (2FA/MFA)

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
