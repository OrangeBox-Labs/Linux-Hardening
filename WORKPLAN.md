# Plan de trabajo persistente — OrangeBox Linux-Hardening

Última actualización: 2026-10-27
Rama de referencia: `main`
Commit de partida en `main`: `707daa5f6c587acfb97d98d4d709362c9949d160`
Rama de trabajo para auditoría CIS/estado: `cis-mount-audit-and-status` (fusionada mediante PR #20)

Este archivo es el punto de reanudación del trabajo. Actualizar estados y commit de referencia al terminar cada bloque coherente.


## Control de tareas entre sesiones

Antes de iniciar o continuar una tarea de modificación del repositorio, usar el control oculto:

1. Leer [`.task-status.md`](.task-status.md) para ver la tarea activa y el siguiente paso exacto.
2. Leer las últimas entradas de [`.task-journal.md`](.task-journal.md) y comprobar en GitHub el branch, HEAD, PR y CI actuales.
3. Seguir [`.github/TASK-RESUMPTION-PROTOCOL.md`](.github/TASK-RESUMPTION-PROTOCOL.md) para registrar decisiones, evidencia y checkpoints. Los pasos completados se retiran de los pendientes y se guardan como eventos históricos.
4. Cerrar cada tarea dejando `.task-status.md` en estado `IDLE` con la última tarea cerrada, la evidencia final y ninguna tarea pendiente.

El control está validado por `tests/test_task_state.sh` y el workflow `.github/workflows/task-state-check.yml`. No guardar secretos ni datos sensibles en el estado o el journal.

## Objetivo y reglas invariables

- El alcance es exclusivamente **hardening de un Linux genérico**. No crear perfiles por aplicación, servicio o combinaciones de software.
- `linux-hardening.sh` sin `--fix` hace auditoría de solo lectura: muestra cada control, el objetivo recomendado, el valor/estado real y si cumple.
- `linux-hardening.sh --fix` es totalmente automático: asume sí a las propuestas, manteniendo preflight, backups, validación y rollback. Las descripciones deben resumir qué protege cada parámetro y su riesgo operacional.
- Si no existe una terminal interactiva, un cambio sensible debe omitirse, no aprobarse automáticamente.
- Los módulos de hardening no inspeccionan ni modifican CSF, iptables/nftables, Shorewall, Imunify ni otros firewalls. El inventario firewall/listeners es una herramienta independiente, solo de lectura.
- SELinux solo se informa en `linux-hardening.sh`; pasar a Permissive corresponde exclusivamente a `selinux-secure-setup.sh`, que no se invoca desde el baseline.
- `logrotate-hardening.sh` aplica `compress` y `rotate 5` a `/etc/logrotate.conf` y los archivos regulares de `/etc/logrotate.d`, sin confirmación, con backup y validación.
- No editar ciegamente PAM/authselect, no deshabilitar funcionalidades sin explicar impacto, no descargar módulos de kernel en caliente si pueden estar en uso y no forzar cambios de fecha/contraseñas que puedan bloquear operaciones.
- No considerar un comentario, un archivo presente o un paquete instalado como evidencia de que un control está activo. Comprobar la configuración efectiva cuando la interfaz disponible lo permita.
- Preservar permisos Git: entrypoints ejecutables deben seguir en modo `100755`; pruebas, librerías y documentación normalmente en `100644`.
- Mantener cambios acotados y regresiones automatizadas. Una tarea solo pasa a “terminada” tras pruebas y CI en verde.

## Estado

### Completado en este ciclo, CI verde e integrado en `main`

- [x] Restaurar y preservar modos ejecutables en los entrypoints modificados.
- [x] Corregir la comprobación de controles CIS de calidad de contraseñas para exigir reglas PAM activas y valores efectivos, sin modificar PAM automáticamente.
- [x] Hacer que la verificación de AIDE reconozca mecanismos de programación soportados y no acepte únicamente la presencia de un archivo.
- [x] Hacer que el control de `gpgcheck` compruebe una directiva activa y contemple overrides activos de repositorios.
- [x] Mejorar la comprobación de `max_log_file` de auditd para exigir un número activo positivo.
- [x] Diferenciar la acción de auditd ante disco lleno de las advertencias de bajo espacio, explicando el riesgo de `single`/`halt`.
- [x] Revisar rpcbind comprobando servicio y socket, sin dar por cumplido el control solo porque aparezca una unidad.
- [x] Cambiar `FS-hardening.sh` a auditoría por defecto y `--fix` explícito; pedir aprobación individual para restricciones de montaje, `hidepid=2`, bloqueo de módulos y deshabilitación de autofs; no descargar módulos cargados en caliente.
- [x] Añadir al baseline principal los controles `kernel.yama.ptrace_scope`, `vm.mmap_min_addr`, `kernel.unprivileged_bpf_disabled` y `user.max_user_namespaces`, usando la ruta de validación/confirmación de sysctl.
- [x] Añadir pruebas iniciales para los comportamientos de filesystem y calidad del verificador CIS.
- [x] CI run `40402752036` pasó todos los jobs (sintaxis, regresiones y compatibility smoke en CentOS 6/7 + AlmaLinux 8/9/10) para el árbol del PR #20 antes de integrarlo.
- [x] PR #20 integrado mediante squash en `main` como commit `0b90e3bebf8cee1f2917eef66242e45ced3fad27`; el resto del trabajo CIS pendiente queda en este plan y `PROJECT-STATUS.md`.

### Auditoría CIS / estado del repositorio — 2026-10-26

- [x] Contrastar el mapa de benchmarks CIS catalogados para RHEL, AlmaLinux, Rocky Linux y Oracle Linux 8–10 con las páginas públicas de CIS; CentOS/Stream permanece sin equivalencia automática.
- [x] Confirmar que `cis-benchmark-check.sh` implementa 143 comprobaciones locales: el resultado debe describirse como subconjunto y no como cumplimiento completo del benchmark.
- [x] Detectar un falso PASS en las comprobaciones de montaje: `findmnt --kernel /ruta` podía devolver el filesystem padre y hacer creer que la ruta tenía montaje dedicado/opciones propias.
- [x] Añadir en la rama `cis-mount-audit-and-status` helpers de mountpoint exacto, prueba unitaria con `findmnt` simulado y ejecución desde el workflow CI.
- [x] Alinear el comentario de versión del baseline con `SCRIPT_VERSION=1.4.26` y enlazar el tablero `PROJECT-STATUS.md` desde README.
- [x] Validar sintaxis y ejecutar las pruebas CIS/nuevas regresiones en la rama (CI run `40402578862`, commit `e64b2825357f9479e9e9537802a973a0adb613be`).
- [x] Confirmar la matriz CI CentOS 6/7 + AlmaLinux 8/9/10 para ese commit.
- [x] Revisar el diff final y comprobar que el CI más reciente del PR estaba en verde antes de integrarlo.
- [ ] Elaborar trazabilidad recomendación por recomendación para cada perfil CIS catalogado. Priorizar recomendaciones añadidas/reorganizadas en las revisiones CIS 3.0.0 de RHEL/AlmaLinux/Rocky 9. Añadir tests de lectura CIS para sysctl de red y logging; elegir/tailorear el perfil journald o rsyslog sin deshabilitar colectores automáticamente.
- [x] Corregir en la rama el control SELinux de arranque para revisar kernel activo y fuentes BLS/GRUB/EFI, y los checks de core dumps para resolver `systemd-analyze cat-config`/drop-ins; evidencia incompleta queda en WARN.
- [x] Añadida `tests/test_cis_effective_config.sh` para verificar overrides de systemd y argumentos de arranque, y conectada al workflow.
- [x] Añadido `CIS-COVERAGE-MAP.md`, inventario de los 143 checks locales por sección y secciones sin checks directos en el informe (3.2/3.3 y 4.2); el mapping recomendación oficial→control local sigue pendiente.
- [x] Enlazados `PROJECT-STATUS.md` y `CIS-COVERAGE-MAP.md` desde README para retomar el trabajo sin depender del historial del chat.
- [x] Añadidos al baseline y a `kernel-hardening.sh` los controles CIS de forwarding IPv4/IPv6. Cada valor se aplica solo con confirmación individual y explicación del riesgo para routing/NAT/VPN/gateways/containers; IPv6 no disponible en kernels legacy queda N/A.
- [x] Añadidos los controles de redirects ICMPv6 al baseline y `kernel-hardening.sh`, con explicación de impacto sobre rutas y confirmación por parámetro; kernels sin IPv6 muestran N/A.
- [x] Añadida auditoría de la coexistencia `systemd-journald`/`rsyslog` en EL9/10. Si ambos están activos advierte del posible conflicto de perfil CIS, pero no detiene ni deshabilita los servicios.
- [ ] Continuar revisando permisos GRUB, AIDE activo, opciones efectivas de PAM/SSH y controles CIS dependientes de la versión.

### En curso

- [x] Verificar que `--fix` sea totalmente automático en todos los módulos y caminos de confirmación, conservando preflight, backups, validaciones y rollback.
- [x] Verificar auditd con `ROTATE`, `SYSLOG`, `SUSPEND`; sin `keep_logs`, `email`, `halt` ni reglas SELinux; no activar `-e 2` hasta validar las reglas en memoria.
- [ ] Verificar logrotate: `compress` y `rotate 5` en `logrotate.conf` y todos los archivos regulares de `logrotate.d`, backup, rollback y validación `logrotate -d`, sin preguntas.
- [ ] Verificar que el módulo de red gestione solo sysctl y módulos del kernel, y que firewalls permanezcan completamente fuera del hardening.
- [x] Verificar filesystem: mantener `noexec` en `/var`, agregarlo a `/home` y no proponer `hidepid=2`; SELinux solo informativo en el baseline y herramienta Permissive independiente.
- [ ] Ejecutar CI de sintaxis/regresión y compatibilidad CentOS 6/7 y AlmaLinux 8/9/10. Después probar `--audit` y `--fix` de forma controlada en AlmaLinux 10.2 antes de integrar.

### Validación final pendiente

- [x] Ejecutar `bash -n` sobre todos los scripts modificados (CI run `40402578862`).
- [x] Ejecutar las regresiones nuevas y las existentes (incluye mountpoint, coredump/SELinux, policy guards, SSH avanzado y consentimiento de forwarding).
- [x] Confirmar CI para CentOS 6/7 y AlmaLinux 8/9/10 (CI run `40402578862`).
- [x] Integrar los cambios mediante PR #20 (squash commit `0b90e3bebf8cee1f2917eef66242e45ced3fad27`) después de CI en verde.
- [x] Verificar que los entrypoints conserven `100755` mediante el paso automatizado de CI.
- [x] Actualizar este plan con el último CI verde conocido y mantener como precondición de integración que el run más reciente esté verde.
- [ ] Actualizar este archivo con el commit final y las limitaciones que sigan abiertas.

## Punto de reanudación

Al retomar, primero consultar el HEAD de `main` y los últimos workflows de GitHub. No asumir que el commit de partida sigue siendo HEAD. Continuar por **“En curso”**, actualizar este plan junto con cada bloque coherente y no dar por finalizada la tarea mientras CI no esté verificado.
