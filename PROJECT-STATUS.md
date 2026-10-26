# Estado del proyecto — OrangeBox Linux-Hardening

**Fecha de revisión:** 2026-10-26  
**Rama base observada:** `main` — commit `707daa5f6c587acfb97d98d4d709362c9949d160`  
**Rama de trabajo para este análisis:** `cis-mount-audit-and-status`  
**Estado global:** **EN DESARROLLO** — controles operacionales amplios ya existen; la cobertura CIS completa y la validación final siguen pendientes.

Este documento es el tablero operativo del repositorio. No confundir “módulo implementado” con “cumplimiento completo de CIS”: el verificador local es un subconjunto y no certifica cumplimiento.

El inventario por sección de los 143 checks locales, los dominios que no tienen checks directos y la evaluación inicial de impacto se mantiene en [CIS-COVERAGE-MAP.md](CIS-COVERAGE-MAP.md). Ese inventario local todavía no es el mapping uno a uno contra cada recomendación oficial.

## Resumen ejecutivo

| Área | Estado | Qué existe / qué falta |
|---|---|---|
| Baseline `linux-hardening.sh` | Implementado; validación continua | Auditoría predeterminada, `--fix` interactivo, controles de kernel/red, SSH, sudo, PAM/passwords, auditd, cron, GRUB, filesystem, logs, SELinux y banners. Revisar que el comportamiento efectivo y el reporte sean correctos en cada plataforma soportada. |
| Helper `lib/sysctl-safe.sh` | Implementado | Inventaría valores activos/persistentes, detecta conflictos, respalda y solicita consentimiento individual para cambios. Algunas opciones pueden afectar tracing, namespaces, routing, IPv6 y observabilidad. |
| SSH y hardening avanzado | Implementado; pruebas/compatibilidad pendientes | Preflight de configuración efectiva, backup, validación sintáctica, comprobación de valores y rollback. Cambios de autenticación, forwarding y algoritmos deben seguir pidiendo autorización individual. |
| Kernel y red | Implementado; validación CIS pendiente | ASLR, ptrace, BPF sin privilegios, namespaces, core dumps, SYN cookies, backlog, redirects, source routing y reverse-path filtering. El baseline y el módulo independiente ahora auditan forwarding IPv4/IPv6 y solo proponen deshabilitarlo con confirmación individual; puede romper routing/NAT/VPN/gateways/containers. |
| Filesystem | Implementado; validación CIS pendiente | Opciones de montaje, `hidepid`, módulos no usados y autofs; auditoría por defecto y confirmación para restricciones. No asumir que `noexec`, `nodev` o `nosuid` sirven igual para todas las cargas de trabajo. |
| Auditd | Implementado; revisión operacional pendiente | Reglas y configuración, rotación/retención, espacio, acciones de fallo e inmutabilidad. `single`/ `halt` pueden interrumpir el servidor; toda aplicación debe explicar el riesgo y exigir confirmación. |
| Password/PAM y sudo | Implementado parcialmente | Comprobaciones de calidad, hashing, lockout, historial, permisos y sudo. PAM/authselect no se debe reescribir a ciegas; preservamos políticas de caducidad para evitar bloquear cuentas/servicios existentes. |
| Cron/at, GRUB, rsyslog y sincronización horaria | Módulos presentes; revisión y validación en curso | Las listas allow/deny pueden parar tareas, GRUB puede impedir el arranque, logging puede perder destinos/recepción y un cambio de hora puede afectar Kerberos, certificados y correlación. Mantener confirmación y backup. |
| Auditoría de listeners/firewall | Implementado; solo lectura | Inventario TCP/UDP, proceso/servicio y contraste con reglas INPUT de gestores/backends conocidos. No modifica reglas ni decide qué puertos cerrar. |
| Verificador `cis-benchmark-check.sh` | **Parcial** | 143 controles locales implementados. Cubre partes de filesystem, paquetes, AIDE, GRUB, core dumps, SELinux, servicios, tiempo, auditd, cron, SSH, sudo, PAM/passwords, permisos y cuentas. No equivale a las recomendaciones completas del benchmark vigente. |
| Catálogo CIS | Catalogado; trazabilidad control a control pendiente | Hay referencias para RHEL, AlmaLinux, Rocky Linux y Oracle Linux 8–10. CentOS/Stream no se equipara automáticamente a un perfil RHEL. Falta asociar cada control local a la recomendación y versión exactas, distinguir aplicabilidad y registrar controles no cubiertos/no aplicables. |
| Pruebas y CI | Implementados; resultado de esta rama aún no confirmado | El workflow ejecuta sintaxis Bash, regresiones operacionales y smoke tests en CentOS 6/7 y AlmaLinux 8/9/10. El cambio de este análisis añade una prueba de mountpoints, pero debe confirmarse CI en verde antes de integrarlo en `main`. |

## Matriz de cobertura CIS local

| Dominio del benchmark | Cobertura actual del repositorio | Estado del verificador CIS |
|---|---|---|
| Filesystem, particiones y opciones de montaje | `FS-hardening.sh` cubre más rutas y opciones que el verificador | Parcial. Se detectó un falso positivo: `findmnt --kernel /ruta` puede devolver el filesystem padre. La rama de trabajo lo reemplaza por coincidencia exacta de mountpoint y agrega una regresión automatizada. |
| Gestión de paquetes y repositorios | Baseline comprueba `gpgcheck` global y conflictos por repositorio | Parcial; no debe aprobar por directivas comentadas ni ignorar overrides. |
| Integridad de archivos | Instalador/configuración de AIDE; Wazuh FIM puede cubrir una función similar | Parcial. Se valida ejecución periódica; AIDE sigue siendo opcional y exige consentimiento por posible solapamiento/costo. Los checks de core dumps ahora leen `systemd-analyze cat-config` para considerar drop-ins; si no pueden resolver la precedencia, no conceden PASS. |
| Bootloader y core dumps | Módulos GRUB/kernel presentes | Parcial. El control SELinux de arranque ahora revisa `/proc/cmdline`, `grubby --info=ALL` y fuentes BLS/GRUB/EFI; si no puede comprobar runtime y persistencia, devuelve WARN en vez de PASS. La trazabilidad de otros controles de GRUB/permisos sigue pendiente. |
| SELinux | Auditoría separada y controles en el baseline; el módulo dedicado de setup es de solo lectura | Parcial. El modo efectivo es importante; hay que validar contexto runtime, configuración persistente y argumentos de arranque sin habilitar Enforcing a ciegas. |
| Servicios y clientes no requeridos | Auditoría de servicios más módulos de eliminación optativos | Parcial. Nunca quitar/deshabilitar DNS, web, correo, NFS, Samba, SNMP u otros componentes solo por no coincidir con un baseline genérico: confirmar que no son necesarios. |
| Red y firewall | Sysctl y módulo de red; auditoría independiente de listeners/firewall | Parcial en CIS. La auditoría de firewall es solo lectura y no reemplaza una evaluación completa de reglas/políticas de nftables según el perfil de CIS. |
| Auditd y logging | Módulos auditd/rsyslog y controles de retención/espacio | Parcial. Falta trazabilidad uno a uno con todas las recomendaciones aplicables y comprobar el comportamiento real de reglas y acciones de disco lleno. |
| Cron/at, SSH, sudo, PAM/passwords | Módulos específicos, muchos con confirmación por cambio | Parcial. Revisar referencias exactas por versión; las recomendaciones de cuentas/caducidad pueden chocar con automatizaciones y políticas de hosting. |
| Permisos de archivos y cuentas | El verificador cubre un subconjunto de archivos/UIDs | Parcial; falta demostrar cobertura exhaustiva de todos los objetos/recomendaciones de la versión catalogada. |
| Resto de recomendaciones por versión | Sin matriz completa de trazabilidad aún | Pendiente de comparación contra el benchmark completo de cada distribución, versión y perfil. |

## Cambios de esta revisión

- [x] Contrastado el mapa local de versiones con la publicación CIS disponible: RHEL 8/9/10, AlmaLinux 8/9/10, Rocky Linux 8/9/10 y Oracle Linux 8/9/10 están catalogados localmente; no asignar una referencia RHEL a CentOS/Stream por defecto.
- [x] Confirmado que el verificador tiene **143 funciones/controles locales**, por lo que su porcentaje solo describe ese subconjunto.
- [x] Añadido `CIS-COVERAGE-MAP.md` con el inventario de 143 checks por sección y el listado de secciones CIS sin checks directos en el informe actual (3.2/3.3 y 4.2).
- [x] Identificado riesgo de falso PASS en checks de mountpoints: una consulta de montaje para una ruta puede devolver la partición que contiene esa ruta, aunque no sea un mountpoint dedicado.
- [x] Añadido a la rama de trabajo un helper que exige coincidencia exacta del punto de montaje y obtiene opciones del mountpoint exacto.
- [x] Añadida la prueba `tests/test_cis_mountpoint_exact.sh` y conectada al workflow de CI.
- [x] Corregido otro falso PASS de SELinux en bootloader: se valida el kernel activo y fuentes persistentes BLS/GRUB/EFI; evidencia incompleta queda en WARN.
- [x] Core dumps ahora se evalúa con `systemd-analyze cat-config` y reconoce overrides; cuando la precedencia de drop-ins no puede resolverse, el resultado queda en WARN.
- [x] Añadida `tests/test_cis_effective_config.sh` para probar overrides efectivos y detección de argumentos de arranque, y conectada al workflow.
- [x] Añadido hardening opt-in de forwarding IPv4/IPv6 al baseline y al módulo `kernel-hardening.sh`: solo cambia con confirmación individual del helper sysctl y explicación de impacto; se omite sin TTY.
- [ ] Ejecutar/confirmar todos los tests y compatibilidad; el resultado de CI para la rama de trabajo aún no está verificado.
- [ ] Integrar los cambios de esta rama en `main` tras validar CI y revisar diff.

## Siguiente trabajo priorizado

1. **P0 — Confirmar CI de esta rama y revisar el diff.** No integrar si falla sintaxis o cualquier prueba de regresión.
2. **P1 — Construir una matriz de trazabilidad CIS por distribución/versión.** Por cada recomendación: ID y versión exacta, nivel/perfil cuando aplique, evidencia verificada, módulo responsable, estado `implementado/parcial/pendiente/N/A`, y razón de cualquier excepción. En CIS RHEL 9 v3.0.0, la recomendación 3.3.1 cubre forwarding IPv4/IPv6; se agregó con confirmación por su impacto operativo. La numeración equivalente en otros perfiles aún debe verificarse.
3. **P1 — Corregir evidencias CIS que puedan dar falso PASS.** Montajes exactos, SELinux runtime/persistencia y core dumps con overrides están corregidos en la rama; queda validar CI y continuar con evidencias de GRUB/permisos, AIDE activo y opciones PAM/SSH efectivas.
4. **P1 — Completar controles faltantes de bajo impacto.** Añadir primero verificaciones de solo lectura y pruebas; no cambiar la configuración durante una auditoría.
5. **P2 — Aplicar cambios CIS de bajo riesgo de forma idempotente.** Mantener backup, comprobación efectiva y no tocar cuando ya cumple.
6. **P2 — Cambios con riesgo operativo.** Incluirlos solo con mensaje breve sobre efecto e impacto, confirmación individual por terminal y omisión segura sin TTY. Especial atención a SSH/MFA/forwarding, PAM/lockout, GRUB, montajes `noexec`, bloqueo de módulos, SELinux, firewall, cron/at, `rp_filter`, IPv6 RA, user namespaces/BPF, y acciones de auditd `single`/ `halt`.
7. **P3 — Mantener actualizados el catálogo y este tablero.** Un cambio de versión del benchmark exige revalidar IDs y no solo cambiar la cadena de versión.

## Criterios para marcar una tarea terminada

Una tarea pasa a **terminada** cuando el comportamiento está implementado, los cambios sensibles tienen descripción/confirmación/backup y rollback cuando corresponda, existen pruebas de regresión, los entrypoints conservan su modo ejecutable y CI queda en verde. Un archivo presente, una directiva comentada o un paquete instalado no cuentan como evidencia de cumplimiento.

## Fuentes CIS

- RHEL: https://www.cisecurity.org/benchmark/red_hat_linux
- AlmaLinux: https://www.cisecurity.org/benchmark/almalinuxos_linux
- Rocky Linux: https://www.cisecurity.org/benchmark/rocky_linux
- Oracle Linux: https://www.cisecurity.org/benchmark/oracle_linux
- Actualización CIS de septiembre de 2026: https://www.cisecurity.org/insights/blog/cis-benchmarks-september-2026-update
