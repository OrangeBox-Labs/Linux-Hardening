# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x password-hardening.sh
```

# Script: password-hardening.sh

Script para configurar hardening de politicas de contraseñas segun CIS Benchmark secciones 5.4.1 a 5.4.8 y mejores practicas de seguridad.

**Compatibilidad:** RHEL 7,8,9,10 (CentOS, AlmaLinux, Rocky Linux)

## Importancia del hardening de contraseñas

Las contraseñas son la primera linea de defensa contra accesos no autorizados. Politicas debiles de contraseñas son la principal causa de breaches de seguridad. Un atacante con una contraseña debil o facil de adivinar puede obtener acceso completo al sistema.

Les dejo un video que hicimos de como funcionan los ataques por fuerza bruta y como protegerse de ellos.

[![Ver video en YouTube](https://img.youtube.com/vi/YskRMwCzpYQ/hqdefault.jpg)](https://youtu.be/YskRMwCzpYQ)

*Haz clic en la imagen para ver el video en YouTube*


## Que hace este script

### CIS 5.4.1 - Requisitos de creacion de contraseñas (pwquality.conf)

Configura el modulo pam_pwquality.so que valida la fortaleza de las contraseñas.

**Parametros configurados:**

| Parametro | Valor | Descripcion |
|-----------|-------|-------------|
| minlen | 14 | Longitud minima de la contraseña |
| minclass | 4 | Clases minimas de caracteres (mayuscula, minuscula, numero, especial) |

**Que previene:**
- Contraseñas debiles como "123456", "password", "admin123"
- Ataques de diccionario
- Fuerza bruta efectiva

**Como puede ser explotado si no se configura:**
- Un atacante puede adivinar contraseñas comunes en segundos
- Usuarios pueden usar "password" o "123456" como contraseña
- La efectividad de ataques de fuerza bruta aumenta dramaticamente

### CIS 5.4.2 - Lockout por intentos fallidos (pam_faillock.so)

Bloquea temporalmente una cuenta despues de multiples intentos fallidos de login.

**Parametros configurados:**

| Parametro | Valor | Descripcion |
|-----------|-------|-------------|
| deny | 5 | Intentos fallidos antes de bloquear |
| unlock_time | 900 | Tiempo de bloqueo en segundos (15 minutos) |

**Que previene:**
- Ataques de fuerza bruta automatizados
- Adivinacion de contraseñas por prueba y error

**Como puede ser explotado si no se configura:**
- Un atacante puede probar millones de contraseñas sin restricciones
- Scripts automatizados pueden atacar cuentas indefinidamente
- Puede realizar 1000+ intentos por segundo contra el sistema

### CIS 5.4.3 - Algoritmo de hash SHA-512

Configura el algoritmo de hash para almacenar contraseñas de forma segura.

**Que previene:**
- Recuperacion de contraseñas desde archivos shadow robados
- Ataques de tablas rainbow
- Cracking de hashes debiles (MD5)

**Como puede ser explotado si no se configura:**
- Si se usa MD5, un atacante puede crackear hashes en minutos usando GPUs
- Tablas rainbow permiten revertir hashes MD5 instantaneamente
- Contraseñas debiles son triviales de descifrar

### CIS 5.4.4 - Limitar reuso de contraseñas (remember)

Previene que los usuarios reutilicen contraseñas antiguas.

**Parametros configurados:**
- remember=5 (recordar las ultimas 5 contraseñas)

**Que previene:**
- Reciclaje de contraseñas comprometidas
- Usuarios alternando entre 2 contraseñas

**Como puede ser explotado si no se configura:**
- Un usuario puede rotar entre "Password123", "Password1234", "Password12345" y volver a la original sin restricciones
- Si un atacante obtiene un hash de contraseña y logra crackearlo, el usuario podría seguir usando la misma contraseña vulnerable por meses
- En auditorías de cumplimiento (PCI-DSS, ISO 27001), la falta de control de reuso es una no-conformidad grave
- Usuarios descuidados pueden tener la misma contraseña por años, aumentando la ventana de exposición si esta se filtra
- Sin limitar el reuso, implementar expiración de contraseñas (PASS_MAX_DAYS) es casi inútil, porque el usuario volverá a la misma contraseña apenas pueda

---

**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs
