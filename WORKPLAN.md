# Plan de trabajo persistente — OrangeBox Linux-Hardening

Última actualización: 2026-10-26
Rama de referencia: `main`
Commit de partida en `main`: `707daa5f6c587acfb97d98d4d709362c9949d160`
Rama de trabajo para auditoría CIS/estado: `cis-mount-audit-and-status`

Este archivo es el punto de reanudación del trabajo. Actualizar estados y commit de referencia al terminar cada bloque coherente.

## Objetivo y reglas invariables

- El alcance es exclusivamente **hardening de un Linux genérico**. No crear perfiles por aplicación, servicio o combinaciones de software.
- `linux-hardening.sh` sin `--fix` hace auditoría de solo lectura: muestra cada control, el objetivo recomendado, el valor/estado real y si cumple.
- `linux-hardening.sh --fix` aplica únicamente controles pendientes; cualquier parámetro que pueda cortar conectividad, bloquear una cuenta, detener un servicio, romper cargas de trabajo o impedir el arranque debe explicar qué hace, describir el riesgo y pedir confirmación antes de cambiarlo.
- Si no existe una terminal interactiva, un cambio sensible debe omitirse, no aprobarse automáticamente.
- No modificar reglas de firewall ni vaciar/cambiar políticas de firewall desde los scripts de auditoría de listeners. El inventario y la comparación de listeners con el firewall son de solo lectura.
- No editar ciegamente PAM/authselect, no deshabilitar funcionalidades sin explicar impacto, no descargar módulos de kernel en caliente si pueden estar en uso y no forzar cambios de fecha/contraseñas que puedan bloquear operaciones.
- No considerar un comentario, un archivo presente o un paquete instalado como evidencia de que un control está activo. Comprobar la configuración efectiva cuando la interfaz disponible lo permita.
- Preservar permisos Git: entrypoints ejecutables deben seguir en modo `100755`; pruebas, librerías y documentación normalmente en `100644`.
- Mantener cambios acotados y regresiones automatizadas. Una tarea solo pasa a “terminada” tras pruebas y CI en verde.

## Estado

### Completado en este ciclo, sujeto a la validación final de CI

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
- [ ] Confirmar CI de los cambios de este ciclo; el seguimiento vigente está en «Auditoría CIS / estado del repositorio» más abajo.

### Auditoría CIS / estado del repositorio — 2026-10-26

- [x] Contrastar el mapa de benchmarks CIS catalogados para RHEL, AlmaLinux, Rocky Linux y Oracle Linux 8–10 con las páginas públicas de CIS; CentOS/Stream permanece sin equivalencia automática.
- [x] Confirmar que `cis-benchmark-check.sh` implementa 143 comprobaciones locales: el resultado debe describirse como subconjunto y no como cumplimiento completo del benchmark.
- [x] Detectar un falso PASS en las comprobaciones de montaje: `findmnt --kernel /ruta` podía devolver el filesystem padre y hacer creer que la ruta tenía montaje dedicado/opciones propias.
- [x] Añadir en la rama `cis-mount-audit-and-status` helpers de mountpoint exacto, prueba unitaria con `findmnt` simulado y ejecución desde el workflow CI.
- [x] Alinear el comentario de versión del baseline con `SCRIPT_VERSION=1.4.26` y enlazar el tablero `PROJECT-STATUS.md` desde README.
- [ ] Validar la sintaxis de los archivos modificados y ejecutar las pruebas CIS en esta rama.
- [ ] Confirmar CI completo y compatibilidad CentOS 6/7 + AlmaLinux 8/9/10; no integrar en `main` antes de comprobarlo.
- [ ] Elaborar trazabilidad recomendación por recomendación para cada perfil CIS catalogado. Priorizar recomendaciones añadidas/reorganizadas en las revisiones CIS 3.0.0 de RHEL/AlmaLinux/Rocky 9.
- [ ] Corregir otros falsos PASS pendientes en GRUB/BLS/argumentos efectivos, core dumps con overrides, SELinux runtime/persistencia y restantes controles dependientes de la versión.

### En curso

- [ ] Revisar el orquestador `linux-hardening.sh`: el flujo global debe auditar primero los módulos complementarios, explicar su riesgo y después invocar sus modos `--fix` correctos sin duplicar confirmaciones ni omitir controles.
- [ ] Revisar `auditd-hardening.sh`: cada parámetro/configuración y cada operación con impacto debe indicar efecto y riesgo y pedir aprobación; respaldar archivos antes de cambios. En especial, `admin_space_left_action=halt`, instalación de paquetes, inicio/reinicio de auditd y reglas inmutables pueden causar interrupción o dificultar recuperación.
- [ ] Revisar `cron-hardening.sh`: permisos y listas allow/deny pueden impedir tareas de usuarios, hosting o cPanel; confirmar cada restricción antes de aplicarla y comprobar resultado real.
- [ ] Revisar `grub-hardening.sh`: respaldar configuración; explicar que la regeneración de GRUB y los parámetros de arranque pueden impedir el boot y normalmente requieren consola/reinicio; confirmar individualmente y validar antes de terminar.
- [ ] Revisar `rsyslog-hardening.sh`: cambios de persistencia y reinicios de logging deben explicar uso de disco, flujo de logs y riesgo de perder recepción/forwarding.
- [ ] Revisar `ssh-hardening.sh` y `ssh-hardening-complete.sh`: validar con `sshd -t`/`sshd -T`, backup y rollback; evitar perder acceso remoto y explicar impacto de root-login, algoritmos, forwarding, timeout y reinicio/recarga.
- [ ] Revisar `sudo-hardening.sh` y `password-hardening.sh`: confirmar parámetros individualmente, preservar backups originales, no modificar PAM/authselect a ciegas y proteger cuentas administrativas.
- [ ] Revisar `network-hardening.sh` y `kernel-hardening.sh`: cada sysctl/módulo debe exponer efecto e impacto; preservar forwarding/rutas/VPN/IPv6; un control que no existe en ese kernel debe salir como N/A, no como FAIL.
- [ ] Revisar el resto de módulos invocados por el baseline para que los cambios sean verdaderamente opt-in por confirmación, no por perfiles de aplicaciones, y que la auditoría no modifique el sistema.

### Validación final pendiente

- [ ] Ejecutar `bash -n` sobre todos los scripts modificados.
- [ ] Ejecutar las regresiones nuevas y las existentes.
- [ ] Confirmar CI para CentOS 6/7 y AlmaLinux 8/9/10.
- [ ] Verificar el árbol Git y que todos los entrypoints conserven `100755`.
- [ ] Actualizar este archivo con el commit final y las limitaciones que sigan abiertas.

## Punto de reanudación

Al retomar, primero consultar el HEAD de `main` y los últimos workflows de GitHub. No asumir que el commit de partida sigue siendo HEAD. Continuar por **“En curso”**, actualizar este plan junto con cada bloque coherente y no dar por finalizada la tarea mientras CI no esté verificado.
