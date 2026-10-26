# Estado del proyecto — OrangeBox Linux-Hardening

**Fecha de revisión:** 2026-10-26  
**Integración:** cambios de esta revisión fusionados en `main` mediante PR #20, squash commit `0b90e3bebf8cee1f2917eef66242e45ced3fad27`.  
**Rama de trabajo original:** `cis-mount-audit-and-status` (PR cerrado y fusionado).  
**Estado global:** **EN DESARROLLO** — CI de la revisión pasó; sigue pendiente completar la trazabilidad CIS recomendación por recomendación y ampliar la cobertura directa del verificador.

Este documento es el tablero operativo del repositorio. No confundir “módulo implementado” con “cumplimiento completo de CIS”: el verificador local es un subconjunto y no certifica cumplimiento.

El inventario por sección de los 143 checks locales, los dominios que no tienen checks directos y la evaluación inicial de impacto se mantiene en [CIS-COVERAGE-MAP.md](CIS-COVERAGE-MAP.md). Ese inventario local todavía no es el mapping uno a uno contra cada recomendación oficial.

## Resumen ejecutivo

| Área | Estado | Qué existe / qué falta |
|---|---|---|
| Baseline `linux-hardening.sh` | Implementado; validación continua | Auditoría predeterminada, `--fix` interactivo, controles de kernel/red, SSH, sudo, PAM/passwords, auditd, cron, GRUB, filesystem, logs, SELinux y banners. Revisar que el comportamiento efectivo y el reporte sean correctos en cada plataforma soportada. |
| Helper `lib/sysctl-safe.sh` | Implementado | Inventaría valores activos/persistentes, detecta conflictos, respalda y solicita consentimiento individual para cambios. Algunas opciones pueden afectar tracing, namespaces, routing, IPv6 y observabilidad. |
| SSH y hardening avanzado | Implementado; pruebas/compatibilidad pendientes | Preflight de configuración efectiva, backup, validación sintáctica, comprobación de valores y rollback. Cambios de autenticación, forwarding y algoritmos deben seguir pidiendo autorización individual. |
| Kernel y red | Implementado; validación CIS pendiente | ASLR, ptrace, BPF sin privilegios, namespaces, core dumps, SYN cookies, backlog, redirects, source routing y reverse-path filtering. El baseline y el módulo independiente auditan forwarding IPv4/IPv6 y redirects ICMPv6; el primero solo se deshabilita con confirmación individual (puede romper routing/NAT/VPN/gateways/containers) y los redirects explican el posible efecto en rutas aprendidas por ICMPv6. |
| Filesystem | Implementado; validación CIS pendiente | Opciones de montaje, `hidepid`, módulos no usados y autofs; auditoría por defecto y confirmación para restricciones. No asumir que `noexec`, `nodev` o `nosuid` sirven igual para todas las cargas de trabajo. |
| Auditd | Implementado; revisión operacional pendiente | Reglas y configuración, rotación/retención, espacio, acciones de fallo e inmutabilidad. `single`/ `halt` pueden interrumpir el servidor; toda aplicación debe explicar el riesgo y exigir confirmación. |
| Password/PAM y sudo | Implementado parcialmente | Comprobaciones de calidad, hashing, lockout, historial, permisos y sudo. PAM/authselect no se debe reescribir a ciegas; preservamos políticas de caducidad para evitar bloquear cuentas/servicios existentes. |
| Cron/at, GRUB, rsyslog y sincronización horaria | Módulos presentes; revisión y validación en curso | Las listas allow/deny pueden parar tareas, GRUB puede impedir el arranque, logging puede perder destinos/recepción y un cambio de hora puede afectar Kerberos, certificados y correlación. El baseline ahora avisa si `journald` y `rsyslog` están activos juntos en EL9/10; no deshabilita ninguno porque podría cortar forwarding, Wazuh o recepción de logs. |
| Auditoría de listeners/firewall | Implementado como herramienta independiente; solo lectura | Exclusiva de `audit-firewall-listeners.sh`; no se ejecuta desde `linux-hardening.sh` ni `network-hardening.sh`. Inventario TCP/UDP, proceso/servicio y contraste con reglas INPUT de gestores/backends conocidos. No modifica reglas ni decide qué puertos cerrar. |
| Verificador `cis-benchmark-check.sh` | **Parcial** | 143 controles locales implementados. Cubre partes de filesystem, paquetes, AIDE, GRUB, core dumps, SELinux, servicios, tiempo, auditd, cron, SSH, sudo, PAM/passwords, permisos y cuentas. No equivale a las recomendaciones completas del benchmark vigente. |
| Catálogo CIS | Catalogado; trazabilidad control a control pendiente | Hay referencias para RHEL, AlmaLinux, Rocky Linux y Oracle Linux 8–10. CentOS/Stream no se equipara automáticamente a un perfil RHEL. Falta asociar cada control local a la recomendación y versión exactas, distinguir aplicabilidad y registrar controles no cubiertos/no aplicables. |
| Pruebas y CI | Validado en verde e integrado | PR #20 se integró mediante squash en `main` como commit `0b90e3bebf8cee1f2917eef66242e45ced3fad27`. El último CI del árbol del PR, run `40402752036`, pasó sintaxis/regresiones y los seis jobs de compatibilidad CentOS 6/7 + AlmaLinux 8/9/10. Repetir CI antes de integrar futuros cambios de código. |

## Matriz de cobertura CIS local

| Dominio del benchmark | Cobertura actual del repositorio | Estado del verificador CIS |
|---|---|---|
| Filesystem, particiones y opciones de montaje | `FS-hardening.sh` cubre más rutas y opciones que el verificador | Parcial. Se detectó un falso positivo: `findmnt --kernel /ruta` puede devolver el filesystem padre. La rama de trabajo lo reemplaza por coincidencia exacta de mountpoint y agrega una regresión automatizada. |
| Gestión de paquetes y repositorios | Baseline comprueba `gpgcheck` global y conflictos por repositorio | Parcial; no debe aprobar por directivas comentadas ni ignorar overrides. |
| Integridad de archivos | Instalador/configuración de AIDE; Wazuh FIM puede cubrir una función similar | Parcial. Se valida ejecución periódica; AIDE sigue siendo opcional y exige consentimiento por posible solapamiento/costo. Los checks de core dumps ahora leen `systemd-analyze cat-config` para considerar drop-ins; si no pueden resolver la precedencia, no conceden PASS. |
| Bootloader y core dumps | Módulos GRUB/kernel presentes | Parcial. El control SELinux de arranque ahora revisa `/proc/cmdline`, `grubby --info=ALL` y fuentes BLS/GRUB/EFI; si no puede comprobar runtime y persistencia, devuelve WARN en vez de PASS. La trazabilidad de otros controles de GRUB/permisos sigue pendiente. |
| SELinux | Auditoría separada y controles en el baseline; el módulo dedicado de setup es de solo lectura | Parcial. El modo efectivo es importante; hay que validar contexto runtime, configuración persistente y argumentos de arranque sin habilitar Enforcing a ciegas. |
| Servicios y clientes no requeridos | Auditoría de servicios más módulos de eliminación optativos | Parcial. Nunca quitar/deshabilitar DNS, web, correo, NFS, Samba, SNMP u otros componentes solo por no coincidir con un baseline genérico: confirmar que no son necesarios. |
| Hardening de red | `network-hardening.sh` audita/aplica sus controles sysctl y módulos; exige autorización explícita para cambios con Shorewall activo. El inventario/correlación de firewall y listeners se ejecuta solo con `audit-firewall-listeners.sh`. | Parcial en CIS. La auditoría separada es de solo lectura y no reemplaza una evaluación completa de reglas/políticas de nftables según el perfil de CIS. |
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
- [x] Añadidos al baseline y al módulo `kernel-hardening.sh` los controles de redirects ICMPv6 (RHEL 9 CIS v3.0.0 3.3.5), con explicación y confirmación individual; sin IPv6 quedan como N/A.
- [x] Añadida auditoría de elección del stack journald/rsyslog en EL9/10. Si ambos están activos, advierte que debe elegirse/tailorearse el perfil y no detiene, deshabilita ni reinicia los servicios desde esa comprobación.
- [x] El checker CIS ahora advierte en pantalla y reporte que las etiquetas numéricas locales son históricas; no garantiza equivalencia uno a uno con IDs oficiales de cada versión. El coverage map explica esa brecha.
- [x] El último código funcional del commit `45d3cd2f5d2c658556bcc3ab9ed8fbd9d5b92e2c` pasó CI run `40402420319`: sintaxis, regresiones y compatibility smoke en CentOS 6/7 + AlmaLinux 8/9/10.
- [x] Confirmar CI verde en todos los jobs en el commit `e64b2825357f9479e9e9537802a973a0adb613be` (run `40402578862`). La revisión de compatibilidad incluye CentOS 6/7 y AlmaLinux 8/9/10.
- [x] Revisar el diff final y validar CI verde para el árbol del PR.
- [x] Integrar los cambios vía PR #20 squash en `main` (commit `0b90e3bebf8cee1f2917eef66242e45ced3fad27`).

## Siguiente trabajo priorizado

1. **P0 — CI y revisión completados.** PR #20 quedó integrado después de CI verde en el run `40402752036`; mantener la regla de no integrar cambios futuros con el pipeline rojo.
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
