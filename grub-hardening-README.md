# script `grub-hardening.sh`

Este script hace un hardening de seguridad del bootloader GRUB y agrega parámetros de seguridad al kernel de Linux. Aquí te explico qué hace cada parte.

> [!WARNING]
> - OJO!: Primero apliquen los cambios con --fix y reinicien y prueben, si todo sale bien, pongan password al GRUB, NO ANTES! 
> - OJO!: Estos cambios pueden hacer que el sistema no bootee, es probable que tengan que editar algunos parámetros directo en el GRUB durante el arranque para rescatar la maquina 
> - OJO!: Si olvidan la password de GRUB, van a necesitar arrancar la maquina con un disco de rescate (el mismo con el que instalaron esa versión de Linux), y reparar el condoro.

## Autor

Felipe Roman
Web: https://www.orangebox.cl
Email: froman@orangebox.cl

---

# Instalación
```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
```
---

## 🔐 1.4.1 - Contraseña de bootloader

**Qué hace:** Verifica si hay una contraseña configurada para proteger GRUB.

**Por qué es importante:** Sin contraseña, cualquiera con acceso físico al servidor puede:
- Arrancar en modo de recuperación (single user mode) y obtener acceso root sin contraseña
- Agregar parámetros como `init=/bin/bash` para saltarse la autenticación
- Deshabilitar SELinux agregando `selinux=0` al arranque
- Ver logs o modificar la configuración del sistema sin restricciones

**Cómo se arregla:** El script recomienda ejecutar `grub2-setpassword` manualmente (por seguridad, no lo hace automático).

---

## 📁 1.4.2 - Permisos de archivos GRUB

**Qué hace:** Verifica que `/boot/grub2/grub.cfg` y `/boot/grub2/user.cfg` tengan permisos 600 (solo root puede leer/escribir).

**Por qué es importante:** Si un usuario no root puede leer `grub.cfg`, podría ver los parámetros de arranque o información del sistema. Si puede modificarlo, podría agregar parámetros maliciosos.

**Cómo se arregla:** El script corrige los permisos automáticamente con `chmod 600`.

---

## 📝 4.1.1.2 - audit=1 en boot

**Qué hace:** Agrega el parámetro `audit=1` a la línea de arranque del kernel.

**Por qué es importante:** Sin `audit=1`, los procesos que arrancan ANTES que el servicio `auditd` (como el propio kernel, systemd, y servicios tempranos) NO son auditados.

| Sin audit=1 | Con audit=1 |
|-------------|-------------|
| Modificaciones del kernel no registradas | Todas las acciones del kernel se auditan |
| Ataques durante el arranque pasan desapercibidos | Se registran incluso en etapas tempranas |
| Evidencia forense perdida | Trazabilidad completa desde el inicio |

**Cómo se arregla:** El script agrega automáticamente `audit=1` a `GRUB_CMDLINE_LINUX`.

---

## 📊 4.1.1.3 - audit_backlog_limit=8192

**Qué hace:** Agrega el parámetro `audit_backlog_limit=8192` al kernel.

**Por qué es importante:** Durante el arranque, se generan muchos eventos de auditoría. Si el backlog (cola de eventos) es muy pequeño (default 64), los eventos se descartan. Esto puede causar:

- Pérdida de evidencia de auditoría
- Eventos críticos que no se registran
- Dificultad para investigar incidentes de seguridad

Con `8192` se asegura que no se pierdan eventos durante el arranque.

**Cómo se arregla:** El script agrega automáticamente `audit_backlog_limit=8192` a `GRUB_CMDLINE_LINUX`.

---

## 🛡️ 1.6.1.2 - SELinux no deshabilitado en boot

**Qué hace:** Verifica que NO existan los parámetros `selinux=0` o `enforcing=0` en la línea de arranque.

**Por qué es importante:** Si alguien agregó `selinux=0`, SELinux está completamente desactivado. Si agregó `enforcing=0`, SELinux está en modo permisivo (solo registra, no bloquea). Un atacante con acceso físico podría agregar estos parámetros para desactivar completamente la seguridad del sistema.

**Cómo se arregla:** El script elimina automáticamente `selinux=0` y `enforcing=0` de `GRUB_CMDLINE_LINUX`.

---

## ⚙️ Parámetros adicionales de seguridad del kernel

| Parámetro | Qué hace | Por qué es importante |
|-----------|----------|----------------------|
| `slab_nomerge` | Evita que el kernel combine objetos de memoria similares (slabs) | Previene ataques de "heap spraying" donde un atacante adivina direcciones de memoria |
| `page_alloc.shuffle=1` | Mezcla aleatoriamente las páginas de memoria | Dificulta que un atacante prediga dónde se asignarán las estructuras de memoria |
| `randomize_kstack_offset=on` | Aleatoriza la ubicación de la pila del kernel en cada syscall | Previene ataques de desbordamiento de pila en el kernel |

**Cómo se arregla:** El script agrega automáticamente estos parámetros a `GRUB_CMDLINE_LINUX`.

---

## Resumen de los parámetros que se agregan

Al final, la línea de arranque queda con algo como:

```
`GRUB_CMDLINE_LINUX="... audit=1 audit_backlog_limit=8192 slab_nomerge page_alloc.shuffle=1 randomize_kstack_offset=on"`
```

---

## Flujo del script

1. Verifica si hay contraseña de GRUB → Si no, recomienda `grub2-setpassword`
2. Verifica permisos de archivos GRUB (deben ser 600) → Si no, los corrige
3. Verifica `audit=1` → Si no, lo agrega
4. Verifica `audit_backlog_limit=8192` → Si no, lo agrega
5. Verifica que no existan `selinux=0` o `enforcing=0` → Si existen, los elimina
6. Verifica parámetros adicionales (`slab_nomerge`, etc.) → Si no, los agrega
7. Regenera la configuración de GRUB (`grub2-mkconfig`)
8. Recomienda reiniciar para aplicar cambios

---

## Mitigaciones incluidas

| Test | Si falla, la mitigación es |
|------|---------------------------|
| Contraseña GRUB | Ejecutar `grub2-setpassword` |
| Permisos | `chmod 600` y `chown root:root` |
| `audit=1` | Agrega automáticamente el parámetro |
| `audit_backlog_limit` | Agrega automáticamente el parámetro |
| `selinux=0` / `enforcing=0` | Elimina automáticamente el parámetro |
| Parámetros adicionales | Los agrega automáticamente |

---

## Modos de ejecución

| Comando | Qué hace |
|---------|----------|
| `./grub-hardening.sh` | Solo VERIFICA, muestra lo que hay que corregir |
| `./grub-hardening.sh --fix` | Aplica las correcciones y regenera GRUB |
| `./grub-hardening.sh --help` | Muestra la ayuda |

---

## ¿Qué riesgos tiene?

| Riesgo | Explicación |
|--------|-------------|
| **Parámetros incompatibles** | Algunos kernels antiguos no soportan `randomize_kstack_offset=on`. Si el sistema no arranca, usar el backup |
| **Contraseña olvidada** | Si olvidas la contraseña de GRUB, necesitas acceso físico para recuperar el sistema |
| **Regeneración de GRUB** | Si hay configuraciones personalizadas en `grub.cfg`, se perderán al regenerar |

Por eso el script hace BACKUP automático de todos los archivos antes de modificarlos.


---

## Licencia

MIT — Libre de usar, modificar y compartir.

---

## ¿Quieres más contenido?

🔹 Blog: https:/www.orangebox.cl/blog — Artículos técnicos de seguridad
🔹 YouTube: https://www.youtube.com/@OrangeBoxLinux - Guias y tutoriales
🔹 GitHub: https://github.com/OrangeBox-Labs/ — Más scripts open-source

— Felipe Román, OrangeBox Labs

