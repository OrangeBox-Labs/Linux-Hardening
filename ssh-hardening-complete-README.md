# Script: ssh-hardening-complete.sh

Hardening completo de SSH basado en ssh-audit

Script para auditar y hacer hardening de seguridad para la configuración de SSH en servidores Linux, basado en las recomendaciones de ssh-audit.com. Compatible con RHEL/CentOS/Rocky/AlmaLinux 7, 8 y 9.

Este script necesita tener instalado ssh-audit. Una vez que lo tengas, se va a encargar de aplicar todos los arreglos que puede, con lo que se sabe hasta la fecha de la última actualización. O sea, deja el SSH lo más blindado posible según el conocimiento actual (8 de jun 2026)

## Autor

Felipe Roman
Web: https://www.orangebox.cl
Email: froman@orangebox.cl

---

## ¿Qué hace este script?

Este script analiza tu configuración actual de SSH usando ssh-audit y aplica las correcciones necesarias para cumplir con las mejores prácticas de seguridad.

### Modo verificación (recomendado primero)

./ssh-hardening-complete.sh

Muestra:
- Problemas críticos [fail] en rojo
- Advertencias [warn] en amarillo
- Recomendaciones de ssh-audit
- Configuración actual de SSH
- Qué se aplicaría con --fix

### Modo automático

./ssh-hardening-complete.sh --fix

Aplica todas las correcciones:
- Regenera claves SSH (RSA 4096, ED25519)
- Elimina moduli Diffie-Hellman menores a 3071 bits
- Configura algoritmos seguros (sin curvas NIST, sin SHA-1)
- Deshabilita opciones inseguras
- Configura throttling de conexiones

---

## Requisitos previos

Instalar ssh-audit:
dnf install epel-release -y
dnf install ssh-audit -y

Compatibilidad:
- RHEL 7, 8, 9
- CentOS 7, 8
- Rocky Linux 8, 9
- AlmaLinux 8, 9
- Oracle Linux 8, 9

---

## Qué corrige

| Área | Acción |
|------|--------|
| Claves | Regenera RSA (4096) y ED25519, deshabilita ECDSA, DSA, RSA-3072 |
| Moduli DH | Elimina moduli < 3071 bits |
| KEX | Remueve ecdh-nistp*, diffie-hellman-group14-sha1, group-exchange-sha1 |
| Cifrados | chacha20-poly1305, AES-GCM, AES-CTR (sin CBC) |
| MACs | Solo ETM (encrypt-then-MAC), sin HMAC-SHA1 |
| Opciones | Deshabilita root con clave, X11Forwarding, TCP forwarding |
| Timeouts | ClientAliveInterval 300, MaxAuthTries 4, LoginGraceTime 60 |
| Throttling | 10 conexiones/10 segundos por IP (firewalld, RHEL 8/9) |

---

## Qué NO hace

- No deshabilita login root por clave (lo deja, pero se recomienda deshabilitar manualmente si usas solo clave)
- No modifica reglas de firewall existentes (solo agrega throttling)
- No desinstala paquetes (solo configura SSH)

---

## Uso

1. Ver que se va a cambiar
```
   ./ssh-hardening-complete.sh
```

2. Aplicar los cambios
```
   ./ssh-hardening-complete.sh --fix
```

3. Verificar resultado
```
   ssh-audit localhost
```

---

## Backup automático

Antes de aplicar cambios, el script crea un backup en:

/root/ssh-backup-YYYYMMDD-HHMMSS/

Contiene:
- /etc/ssh/sshd_config
- /etc/ssh/moduli (si existe)

---

## Verificación post-ejecución

Validar sintaxis:
```
sshd -t
```

Ver configuración activa:
```
sshd -T | grep -E "kexalgorithms|ciphers|macs|hostkeyalgorithms"
```

Auditar nuevamente:
```
ssh-audit localhost
```

Ver logs:
```
tail -f /var/log/secure | grep sshd
```

---

## Posibles problemas

El throttling no funciona
Si no usas firewalld, las reglas de throttling no se aplicarán. En RHEL 7 no se aplican.

Cliente antiguo no puede conectar
Algoritmos modernos pueden no ser compatibles con clientes SSH muy antiguos. Verificar con:
```
ssh -Q kex
ssh -Q cipher
ssh -Q mac
```

Error al regenerar claves
Si el sistema tiene selinux enforcing, puede bloquear el acceso a las nuevas claves:
```
restorecon -Rv /etc/ssh/
```

---

## Ejemplo de salida (modo verificación)
```
./ssh-hardening-complete.sh
```

============================================
  SSH Hardening Complete - sshaudit.com
============================================

🔍 MODO VERIFICACIÓN - No se aplicarán cambios
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[*] Analisis actual de ssh-audit:

=== KEY EXCHANGE ALGORITHMS ===
  ❌ FAIL: (kex) ecdh-sha2-nistp256 -- [fail] using elliptic curves...
  ❌ FAIL: (kex) ecdh-sha2-nistp384 -- [fail] using elliptic curves...
  ⚠️ WARN: (kex) diffie-hellman-group14-sha256 -- [warn] 2048-bit modulus...

=== RECOMENDACIONES ===
  ➖ REMOVER: -ecdh-sha2-nistp256 -- kex algorithm to remove
  ➖ REMOVER: -ssh-rsa -- key algorithm to remove
  ➖ REMOVER: -hmac-sha1 -- mac algorithm to remove

📋 LO QUE SE APLICARA CON --fix:
  1. Regeneracion de claves SSH...
  2. Eliminacion de moduli Diffie-Hellman...
  3. Configuracion de algoritmos seguros...
  4. Hardening adicional...
  5. Throttling de conexiones (firewalld)

Para aplicar las correcciones, ejecute: ./ssh-hardening-complete.sh --fix

---

## Enlaces de interés

ssh-audit.com
ssh-audit en GitHub: github.com/jtesta/ssh-audit
CIS Benchmarks para SSH: www.cisecurity.org/benchmark/red_hat_linux

---

## Licencia

MIT — Libre de usar, modificar y compartir.

---

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source


— Felipe Román, OrangeBox Labs
