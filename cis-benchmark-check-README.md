# Script: cis-benchmark-check.sh

La joya de la corona!. Verificador de cumplimiento CIS Benchmark para RHEL/CentOS/Rocky/AlmaLinux

Script que verifica el cumplimiento de los estándares de seguridad CIS Benchmark en servidores Linux. Compatible mit RHEL 7,8,9,10 y todas sus derivadas.

## Autor

Felipe Roman
Web: https://www.orangebox.cl
Email: froman@orangebox.cl

---

## ¿Qué es esto?

Este script nació de la necesidad, a muchos servidores no se les puede instalar absolutamente nada, por que instalar herramientas como lynis y oscap es imposible, y revisar punto por punto a mano es un dolor. Le puse sangre, sudor y tokens para crear una herramienta que verifica el estado de seguridad de tus servidores Linux según los estándares CIS Benchmark y además te dice como mitigar las fallas que encuentra. 

Sabemos que existen herramientas como Lynis y OpenSCAP, y son excelentes. Pero este script tiene sus propias ventajas:

| Ventaja | Descripción |
|---------|-------------|
| Ligero | No requiere instalación de dependencias complejas. Solo bash y comandos estándar del sistema |
| Español | Todos los mensajes, descripciones y recomendaciones están en español, sin traducciones automáticas |
| Mitigaciones incluidas | Cada test FAIL o WARN incluye una recomendación clara de cómo solucionarlo |
| Reporte legible | Genera un archivo de log con colores y formato fácil de leer, tanto en pantalla como en archivo |
| Enfocado en RHEL | Diseñado específicamente para RHEL y derivados, no es un "para todo" genérico |
| Rápido | Ejecuta ~150 tests en segundos, sin escaneos pesados |
| Idempotente | Solo verifica, no modifica nada. Puedes ejecutarlo cuantas veces quieras sin miedo |
| 100% Bash | Fácil de modificar, extender o adaptar a tus necesidades específicas |

---

## ¿Qué hace este script?

El script ejecuta un subconjunto de controles basado en CIS Benchmark, organizado en las siguientes secciones. La cantidad de pruebas implementadas no implica cobertura completa ni certificación de cumplimiento del benchmark oficial.

**Importante:** las etiquetas numéricas que aparecen en los resultados son referencias locales históricas. No están validadas uno a uno contra los IDs de todos los benchmarks oficiales vigentes, cuyas recomendaciones y numeración varían por versión y perfil. Consulta [CIS-COVERAGE-MAP.md](CIS-COVERAGE-MAP.md) para ver el inventario local y las brechas de trazabilidad. No uses el porcentaje de este script como porcentaje oficial de cumplimiento CIS.

Los controles de `gpgcheck`, `max_log_file`, las acciones de `auditd` y `rpcbind` verifican directivas activas y valores utilizables; una línea comentada o la mera presencia de un paquete no cuenta como evidencia suficiente. El control que actúa al llenarse el disco se separa del aviso cuando el espacio es bajo. Estas comprobaciones siguen siendo un subconjunto local, no una evaluación CIS completa por versión.

| Sección | Descripción |
|---------|-------------|
| 1.1 | Configuración del sistema de archivos (particiones, opciones de montaje) |
| 1.2 | Gestión de paquetes (gpgcheck, repositorios) |
| 1.3 | AIDE (monitor de integridad) |
| 1.4 | Bootloader (contraseña de GRUB, permisos) |
| 1.5 | Core dumps (almacenamiento y backtraces) |
| 1.6 | SELinux (instalación, modo, política, servicios) |
| 1.7 | Banners de advertencia (MOTD, issue, issue.net) |
| 2.1 | Sincronización de tiempo (chrony) |
| 2.2 | Servicios especiales (X Window, Avahi, CUPS, DHCP, DNS, etc.) |
| 2.3 | Clientes inseguros (telnet, LDAP, TFTP, FTP) |
| 3.1 | Parámetros de red (TIPC) |
| 3.4 | Firewall (nftables) |
| 4.1 | Auditd (instalación, configuración, reglas) |
| 5.1 | Cron y At (permisos, restricciones) |
| 5.2 | SSH (permisos, algoritmos, timeout, root login, etc.) |
| 5.3 | Sudo (instalación, configuración, timeout) |
| 5.5 | Políticas de contraseñas (requisitos, lockout, reuso, hashing) |
| 5.6 | Expiración de contraseñas (max días, min días, advertencia, bloqueo) |
| 6.1 | Permisos de archivos (/etc/passwd, /etc/shadow, /etc/group, etc.) |
| 6.2 | Cuentas de usuario (shadow passwords, UID 0 único) |

---

## Colores y su significado

| Color | Significado |
|-------|-------------|
| Verde | Test SUPERADO - La configuración es correcta |
| Amarillo | Advertencia - Mejorable, no crítico pero recomendado |
| Rojo | Fallo CRÍTICO - Requiere atención inmediata |
| Azul | Información - Títulos y secciones |

---

## Referencias CIS versionadas

El script identifica el sistema y muestra una referencia CIS conocida, pero la cobertura local sigue siendo parcial. El porcentaje impreso corresponde solo a las pruebas implementadas por OrangeBox, no al total de controles oficiales. El mapa se documenta en cis-profile-versions.md.

Versiones catalogadas a 26 de octubre de 2026:
- RHEL 8: 4.0.0; RHEL 9: 3.0.0; RHEL 10: 1.0.1.
- AlmaLinux 8: 4.0.0; AlmaLinux 9: 3.0.0; AlmaLinux 10: 1.0.0.
- Rocky Linux 8/9: 3.0.0; Rocky Linux 10: 1.0.0.
- Oracle Linux 8: 4.0.0; Oracle Linux 9: 3.0.0; Oracle Linux 10: 1.0.0.
- CentOS Linux/Stream: no se le asigna automáticamente un benchmark actual de RHEL como si fuera equivalente.

## Requisitos

- Sistema operativo: RHEL, AlmaLinux, Rocky Linux, Oracle Linux o CentOS/Stream EL 7–10 (según controles disponibles; CentOS 6 usa auditorías legacy separadas).
- Usuario: root (o sudo con permisos completos).
- Dependencias: Solo comandos estándar del sistema (no requiere instalación adicional).

---

## Uso
```
chmod +x cis-benchmark-check.sh
sudo ./cis-benchmark-check.sh
cat reporte_orangebox_cis_benchmark.log
```

El script muestra el progreso en pantalla con colores y genera un archivo de reporte en el mismo directorio.

---

## Salida del script

En pantalla (colores):

============================================
  Herramienta de Verificacion CIS Benchmark
  Para RHEL/CentOS/Rocky/AlmaLinux 7,8,9,10
============================================

[*] Test: 5.2.7 - Asegurar login root deshabilitado en SSH
[PASS] 5.2.7 - Asegurar login root deshabilitado en SSH

[*] Test: 5.2.12 - Asegurar X11 forwarding deshabilitado
[FAIL] 5.2.12 - Asegurar X11 forwarding deshabilitado
  X11Forwarding: yes (debe ser no)
  Mitigacion: Configurar /etc/ssh/sshd_config: X11Forwarding no. Reiniciar sshd

En el archivo de log (sin colores):

============================================
  VERIFICACION CIS BENCHMARK COMPLETADA
============================================

RESUMEN FINAL:
  • Tests PASADOS: 120
  • Tests FALLADOS (CRITICOS): 15
  • Tests WARNING: 8
  • Total tests: 143

Porcentaje de cumplimiento: 83%

---

## Ejemplo de mitigación

Cuando el script encuentra un fallo, te dice exactamente cómo arreglarlo:

[FAIL] 5.2.16 - Asegurar MaxAuthTries 4 o menos
  MaxAuthTries: 6 (debe ser <=4)
  Mitigacion: Configurar /etc/ssh/sshd_config: MaxAuthTries 4. Reiniciar sshd

---

## Comparativa con otras herramientas

| Característica | cis-benchmark-check.sh | Lynis | OpenSCAP |
|----------------|------------------------|-------|----------|
| Instalación | Ninguna (bash puro) | Requiere paquete | Requiere paquete |
| Tiempo de ejecución | 10-30 segundos | 1-3 minutos | 5-15 minutos |
| Reporte en español | Sí | No (inglés) | No (inglés) |
| Mitigaciones incluidas | Sí | No | Parcial |
| Enfoque en RHEL | Total | Multi-plataforma | Sí |
| Facilidad de modificación | Alta (bash puro) | Media | Baja (XML/SCAP) |
| Peso | 200 KB | 2 MB | 10-50 MB |

---

## Limitaciones conocidas

1. No corrige automáticamente - Solo verifica, no modifica el sistema
2. Audit rules - Las reglas de audit pueden no mostrarse si el sistema está en modo inmutable

---

## Notas importantes

- Ejecutar como root - Muchos tests requieren acceso root para leer configuraciones
- Reporte persistente - El archivo de log se crea en el directorio actual
- No destructivo - El script solo LEE configuraciones, nunca las modifica
- SELinux en enforcing - Si SELinux está en enforcing, algunas reglas de audit pueden no mostrarse con auditctl -l, el script busca en los archivos de configuración como fallback

---

## Personalización

El script es fácil de modificar. Puedes:

1. Agregar más tests - Solo define una nueva función y agrégala al main()
2. Cambiar los umbrales - Modifica las comparaciones (ej: cambiar 4 intentos de SSH por 3)
3. Ignorar tests específicos - Comenta la línea run_test correspondiente
4. Cambiar colores - Modifica las variables RED, GREEN, etc.

---

## Solución de problemas

El script no detecta reglas de audit que sí existen

Las reglas de audit pueden estar en modo inmutable. El script busca tanto en auditctl -l como en los archivos de configuración.

El script marca UID 0 como duplicado con sync/shutdown/halt

Estas son cuentas de sistema válidas. El script las ignora automáticamente.

El script no ve cambios en SSH que ya hice

El script usa sshd -T que muestra la configuración activa. Si no ves tus cambios, reinicia sshd: systemctl restart sshd

---

## Licencia

MIT — Libre de usar, modificar y compartir.

---

## ¿Quieres más contenido?

🔹 Blog: https:/www.orangebox.cl/blog — Artículos técnicos de seguridad
🔹 YouTube: https://www.youtube.com/@OrangeBoxLinux - Guias y tutoriales
🔹 GitHub: https://github.com/OrangeBox-Labs/ — Más scripts open-source

— Felipe Román, OrangeBox Labs
