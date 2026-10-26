# Mapa de cobertura CIS — OrangeBox Linux-Hardening

**Fecha:** 2026-10-26  
**Rama de análisis:** `cis-mount-audit-and-status`  
**Fuente de inventario local:** `cis-benchmark-check.sh`  
**Resultado del inventario:** 143 checks locales `run_test`. Este archivo inventaría lo que el código verifica actualmente; no declara cumplimiento total ni equivalencia oficial uno a uno.

## Referencias CIS catalogadas

| Sistema | Referencia catalogada |
|---|---|
| RHEL 8 / AlmaLinux 8 / Oracle Linux 8 | Benchmark v4.0.0 |
| Rocky Linux 8 | Benchmark v3.0.0 |
| RHEL 9 / AlmaLinux 9 / Rocky Linux 9 / Oracle Linux 9 | Benchmark v3.0.0 |
| RHEL 10 | Benchmark v1.0.1 |
| AlmaLinux 10 / Rocky Linux 10 / Oracle Linux 10 | Benchmark v1.0.0 |
| CentOS / CentOS Stream | Sin equivalencia automática; verificar perfil de origen/versión y ciclo de soporte |

Las páginas oficiales catalogan estas versiones para las distribuciones mantenidas. CIS reportó en septiembre de 2026 una revisión grande de los benchmarks RHEL/AlmaLinux/Rocky Linux 9: 92 recomendaciones agregadas y 34 eliminadas o reestructuradas. Esto hace necesaria la trazabilidad exacta por versión; cambiar el número de versión en el script no basta.

Fuentes:
- RHEL: https://www.cisecurity.org/benchmark/red_hat_linux
- Perfil CIS RHEL 9 renderizado por ComplianceAsCode (incluye el mapeo de la recomendación 3.3.1 de forwarding): https://complianceascode.github.io/content-pages/rendered-policies/rhel9/cis_rhel9.html
- Nota de Red Hat sobre la separación entre perfiles journald/rsyslog en RHEL 9/10: https://access.redhat.com/articles/7146814
- AlmaLinux: https://www.cisecurity.org/benchmark/almalinuxos_linux
- Rocky Linux: https://www.cisecurity.org/benchmark/rocky_linux
- Oracle Linux: https://www.cisecurity.org/benchmark/oracle_linux
- Actualización CIS de septiembre de 2026: https://www.cisecurity.org/insights/blog/cis-benchmarks-september-2026-update

## Cobertura por dominio

| Sección local | Checks | Dominio | Módulo relacionado | Evaluación |
|---|---:|---|---|---|
| 1.1 | 29 | Filesystem, módulos y opciones de montaje | FS-hardening.sh; disable-usb-storage.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 1.2 | 1 | Gestión de paquetes y validación GPG | linux-hardening.sh (package-repos) | Inventariado; cotejo exacto con la versión oficial pendiente |
| 1.3 | 2 | AIDE/integridad de archivos | aide-install.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 1.4 | 2 | Contraseña y permisos de GRUB | grub-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 1.5 | 2 | Core dumps y backtraces | kernel-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 1.6 | 8 | Instalación, modo, política y servicios SELinux | selinux-secure-setup.sh (auditoría de solo lectura) | Inventariado; cotejo exacto con la versión oficial pendiente |
| 1.7 | 6 | MOTD, banners y permisos | configure-login-banners.sh; linux-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 2.1 | 1 | Sincronización horaria | configure-time-sync.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 2.2 | 17 | Servicios de red no requeridos | desintalar-servicios-sin-usar.sh (opt-in) | Inventariado; cotejo exacto con la versión oficial pendiente |
| 2.3 | 4 | Clientes de protocolos inseguros | desintalar-paquetes-sin-usar.sh (opt-in) | Inventariado; cotejo exacto con la versión oficial pendiente |
| 3.1 | 1 | Módulos de red (el checker verifica TIPC) | network-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 3.4 | 1 | Presencia de nftables (no evalúa por sí solo el ruleset efectivo) | audit-firewall-listeners.sh (solo lectura; cobertura CIS de firewall incompleta) | Inventariado; cotejo exacto con la versión oficial pendiente |
| 4.1 | 20 | Auditd, reglas, almacenamiento y acciones | auditd-hardening.sh; grub-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 5.1 | 9 | Cron/at, permisos y restricciones | cron-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 5.2 | 16 | Permisos y configuración SSH | ssh-hardening.sh; ssh-hardening-complete.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 5.3 | 5 | sudo, logging, timeout y su | sudo-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 5.5 | 4 | Complejidad, lockout, historial y hashing | password-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 5.6 | 4 | Caducidad/edad/inactividad de contraseñas | password-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 6.1 | 8 | Permisos de archivos sensibles | linux-hardening.sh; password-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 6.2 | 3 | Shadow, contraseñas vacías y UID 0 | linux-hardening.sh; password-hardening.sh | Inventariado; cotejo exacto con la versión oficial pendiente |
| 3.2 / 3.3 | 0 checks directos del verificador | Módulos de red y parámetros sysctl | `linux-hardening.sh`, `kernel-hardening.sh`, `network-hardening.sh` | El hardening cubre redirects IPv4 y ahora IPv6 (RHEL 9 CIS v3.0.0 3.3.5), source routing, `rp_filter`, SYN cookies, martians e IPv4/IPv6 forwarding. Forwarding y redirects se proponen con confirmación individual porque afectan routing/NAT/VPN/gateways/containers o rutas aprendidas por ICMPv6. Falta crear la batería de solo lectura del checker y validar el mapping por cada versión; el perfil público SSG asocia 3.3.1 a forwarding IPv4/IPv6 y 3.3.5 a aceptación de redirects. |
| CIS RHEL 9 v3.0.0: 6.2.1.4 / 6.2.2 / 6.2.3 (no es ID local) | 0 checks directos del verificador | Elección de journald/rsyslog y logging | `linux-hardening.sh`, `rsyslog-hardening.sh` | El baseline advierte si ambos servicios están activos en EL9/10, pero el checker CIS aún no cubre la configuración de logging por perfil; el stack debe elegirse/tailorearse sin deshabilitar colectores a ciegas. |

## Brechas relevantes y decisión de riesgo

| Brecha | Estado | Riesgo de producción | Decisión |
|---|---|---|---|
| Checks de montaje que heredaban opciones del filesystem padre | Corregido en esta rama mediante match exacto de TARGET | Podía dar falsos PASS y esconder controles de filesystem pendientes | Cambio de auditoría solo lectura; no modifica montajes |
| Forwarding IPv4/IPv6 | Añadido al baseline y al módulo `kernel-hardening.sh` como control opt-in | Deshabilitarlo puede romper routing, NAT, VPN, gateways y redes de contenedores; puede afectar también rutas IPv6 de uplink | `sysctl-safe` muestra el efecto y pide confirmación individual `[s/N]`; si no hay TTY, omite el cambio. IPv6 ausente en kernels legacy queda como N/A. |
| Redirects ICMPv6 | Añadidos al baseline y al módulo `kernel-hardening.sh` | Ignorarlos reduce el riesgo de cambios de ruta inducidos por terceros, pero puede afectar redes que dependan de Router Redirects | `sysctl-safe` explica el impacto y pide confirmación individual; kernels sin IPv6 quedan como N/A. |
| Journald y rsyslog activos a la vez | Añadida advertencia en el baseline para EL9/10; sin remediación automática | Desactivar uno puede perder forwarding remoto, ingestión de Wazuh o recepción/persistencia de logs; CIS ofrece rutas alternativas y requiere seleccionar el perfil | Solo lectura; se pide decisión operativa/tailoring, no se para ni deshabilita ningún servicio. |
| SELinux en bootloader | Corregido en esta rama: inspecciona `/proc/cmdline`, `grubby --info=ALL` y archivos BLS/GRUB/EFI; si no puede comprobar runtime y persistencia devuelve WARN | Habilitar SELinux Enforcing sobre un host configurado como Disabled puede romper servicios por labels/policies | El checker solo detecta; cualquier migración de modo debe seguir siendo opt-in y requerir análisis/ventana de mantenimiento |
| Core dumps | Corregido en esta rama para consultar `systemd-analyze cat-config systemd/coredump.conf` y considerar drop-ins | Desactivar almacenamiento/backtraces reduce datos útiles para post-mortem | Solo lectura; remediación sigue siendo una decisión operativa confirmada |
| Servicios no requeridos, paquetes clientes y módulos de filesystem | Módulos opt-in existentes; checker detecta presencia | Eliminar/deshabilitar DNS, correo, web, NFS, Samba, SNMP, clientes o módulos usados puede cortar una función legítima | Confirmación por acción y explicación de impacto; nunca eliminar solo por discrepancia con baseline genérico |
| Restricciones de montaje (`noexec`, `nodev`, `nosuid`) | `FS-hardening.sh` exige `--fix` y consentimiento | Puede romper instaladores, runtimes, aplicaciones que ejecutan temporales y cargas de hosting | Mantener prompt individual, backup de `fstab`, no hacer remount en auditoría |
| SSH, PAM, lockout, sudo y caducidad de cuentas | Módulos presentes, varios con consentimiento y backups | Puede bloquear acceso administrativo, MFA, túneles, integraciones de dominio o tareas automatizadas | Confirmación por parámetro/usuario; no editar PAM/authselect a ciegas ni aplicar aging masivo |
| auditd `single` / `halt`, GRUB y sincronización horaria | Módulos presentes; riesgo explicado en las rutas de aplicación | Puede detener el host, impedir arranque o afectar Kerberos/certificados/correlación de logs | Requiere confirmación explícita y contexto de recuperación/ventana de mantenimiento |
| Network `rp_filter`, IPv6 RA, namespaces y BPF | Controles presentes con descripciones en sysctl helper | Puede afectar tráfico asimétrico/VPN, rutas IPv6, contenedores rootless y observabilidad | Mantener confirmación individual; no tratar estos parámetros como universalmente seguros |

## Controles locales inventariados

Los identificadores y nombres siguientes son los que `cis-benchmark-check.sh` ejecuta hoy. **No están aún validados uno a uno contra cada PDF CIS y su nivel/perfil**; la columna de sección es la organización local del script.

| Control local | Check/function |
|---|---|
| 1.1.1.1 - squashfs deshabilitado | `check_squashfs` |
| 1.1.1.2 - udf deshabilitado | `check_udf` |
| 1.1.2.1 - /tmp particion separada | `check_tmp_partition` |
| 1.1.2.2 - /tmp nodev | `check_tmp_nodev` |
| 1.1.2.3 - /tmp noexec | `check_tmp_noexec` |
| 1.1.2.4 - /tmp nosuid | `check_tmp_nosuid` |
| 1.1.3.1 - /var particion separada | `check_var_partition` |
| 1.1.3.2 - /var nodev | `check_var_nodev` |
| 1.1.3.3 - /var nosuid | `check_var_nosuid` |
| 1.1.4.1 - /var/tmp particion separada | `check_var_tmp_partition` |
| 1.1.4.2 - /var/tmp noexec | `check_var_tmp_noexec` |
| 1.1.4.3 - /var/tmp nosuid | `check_var_tmp_nosuid` |
| 1.1.4.4 - /var/tmp nodev | `check_var_tmp_nodev` |
| 1.1.5.1 - /var/log particion separada | `check_var_log_partition` |
| 1.1.5.2 - /var/log nodev | `check_var_log_nodev` |
| 1.1.5.3 - /var/log noexec | `check_var_log_noexec` |
| 1.1.5.4 - /var/log nosuid | `check_var_log_nosuid` |
| 1.1.6.1 - /var/log/audit particion separada | `check_var_log_audit_partition` |
| 1.1.6.2 - /var/log/audit noexec | `check_var_log_audit_noexec` |
| 1.1.6.3 - /var/log/audit nodev | `check_var_log_audit_nodev` |
| 1.1.6.4 - /var/log/audit nosuid | `check_var_log_audit_nosuid` |
| 1.1.7.1 - /home particion separada | `check_home_partition` |
| 1.1.7.2 - /home nodev | `check_home_nodev` |
| 1.1.7.3 - /home nosuid | `check_home_nosuid` |
| 1.1.8.1 - /dev/shm particion separada | `check_dev_shm_partition` |
| 1.1.8.2 - /dev/shm nodev | `check_dev_shm_nodev` |
| 1.1.8.3 - /dev/shm noexec | `check_dev_shm_noexec` |
| 1.1.8.4 - /dev/shm nosuid | `check_dev_shm_nosuid` |
| 1.1.9 - USB storage deshabilitado | `check_usb_storage` |
| 1.2.2 - gpgcheck activado | `check_gpgcheck` |
| 1.3.1 - AIDE instalado | `check_aide` |
| 1.3.2 - Verificacion periodica AIDE | `check_aide_timer` |
| 1.4.1 - Contraseña de bootloader | `check_grub_password` |
| 1.4.2 - Permisos bootloader | `check_grub_permissions` |
| 1.5.1 - Almacenamiento core dumps | `check_coredump_storage` |
| 1.5.2 - Backtraces core dumps | `check_coredump_backtraces` |
| 1.6.1.1 - SELinux instalado | `check_selinux_installed` |
| 1.6.1.2 - SELinux habilitado en boot | `check_selinux_bootloader` |
| 1.6.1.3 - Politica SELinux | `check_selinux_policy` |
| 1.6.1.4 - Modo SELinux no deshabilitado | `check_selinux_mode` |
| 1.6.1.5 - Modo SELinux enforcing | `check_selinux_enforcing` |
| 1.6.1.6 - Servicios sin confinar | `check_unconfined_services` |
| 1.6.1.7 - SETroubleshoot | `check_setroubleshoot` |
| 1.6.1.8 - mcstrans | `check_mcstrans` |
| 1.7.1 - MOTD configurado | `check_motd` |
| 1.7.2 - Banner local | `check_issue` |
| 1.7.3 - Banner remoto | `check_issue_net` |
| 1.7.4 - Permisos MOTD | `check_motd_perms` |
| 1.7.5 - Permisos issue | `check_issue_perms` |
| 1.7.6 - Permisos issue.net | `check_issue_net_perms` |
| 2.1.1 - Sincronizacion de tiempo | `check_chrony` |
| 2.2.1 - X Window | `check_xwindow` |
| 2.2.2 - Avahi | `check_avahi` |
| 2.2.3 - CUPS | `check_cups` |
| 2.2.4 - DHCP server | `check_dhcp` |
| 2.2.5 - DNS server | `check_dns` |
| 2.2.6 - VSFTP server | `check_vsftpd` |
| 2.2.7 - TFTP server | `check_tftp_server` |
| 2.2.8 - Web server | `check_webserver` |
| 2.2.9 - IMAP/POP3 | `check_imap_pop3` |
| 2.2.10 - Samba | `check_samba` |
| 2.2.11 - HTTP proxy | `check_squid` |
| 2.2.12 - SNMP | `check_snmp` |
| 2.2.13 - Telnet server | `check_telnet_server` |
| 2.2.14 - dnsmasq | `check_dnsmasq` |
| 2.2.15 - MTA local | `check_mta_local` |
| 2.2.16 - NFS | `check_nfs` |
| 2.2.17 - rpcbind | `check_rpcbind` |
| 2.3.1 - Telnet client | `check_telnet_client` |
| 2.3.2 - LDAP client | `check_ldap_client` |
| 2.3.3 - TFTP client | `check_tftp_client` |
| 2.3.4 - FTP client | `check_ftp_client` |
| 3.1.3 - TIPC deshabilitado | `check_tipc` |
| 3.4.1.1 - nftables instalado | `check_nftables` |
| 4.1.1.1 - auditd instalado | `check_auditd_installed` |
| 4.1.1.2 - audit=1 en boot | `check_audit_boot` |
| 4.1.1.3 - audit_backlog_limit | `check_audit_backlog` |
| 4.1.1.4 - auditd habilitado | `check_auditd_enabled` |
| 4.1.2.1 - Tamano logs audit | `check_audit_log_size` |
| 4.1.2.2 - Logs no eliminados | `check_audit_log_keep` |
| 4.1.2.3 - Accion logs llenos | `check_audit_full_action` |
| 4.1.2.4 - Advertencia cuando espacio audit es bajo | `check_audit_low_space_warning` |
| 4.1.3.1 - audit sudoers | `check_audit_sudoers` |
| 4.1.3.2 - audit user emulation | `check_audit_user_emulation` |
| 4.1.3.4 - audit time changes | `check_audit_time` |
| 4.1.3.5 - audit network changes | `check_audit_network` |
| 4.1.3.8 - audit identity | `check_audit_identity` |
| 4.1.3.10 - audit mounts | `check_audit_mounts` |
| 4.1.3.11 - audit session | `check_audit_session` |
| 4.1.3.12 - audit logins | `check_audit_logins` |
| 4.1.3.13 - audit file deletion | `check_audit_delete` |
| 4.1.3.14 - audit MAC | `check_audit_mac` |
| 4.1.3.19 - audit modules | `check_audit_modules` |
| 4.1.3.20 - audit immutable | `check_audit_immutable` |
| 5.1.1 - cron habilitado | `check_cron_enabled` |
| 5.1.2 - permisos crontab | `check_crontab_perms` |
| 5.1.3 - permisos cron.hourly | `check_cron_hourly_perms` |
| 5.1.4 - permisos cron.daily | `check_cron_daily_perms` |
| 5.1.5 - permisos cron.weekly | `check_cron_weekly_perms` |
| 5.1.6 - permisos cron.monthly | `check_cron_monthly_perms` |
| 5.1.7 - permisos cron.d | `check_cron_d_perms` |
| 5.1.8 - cron restringido | `check_cron_restricted` |
| 5.1.9 - at restringido | `check_at_restricted` |
| 5.2.1 - permisos sshd_config | `check_sshd_perms` |
| 5.2.4 - acceso SSH limitado | `check_ssh_access` |
| 5.2.5 - LogLevel SSH | `check_ssh_loglevel` |
| 5.2.6 - PAM en SSH | `check_ssh_pam` |
| 5.2.7 - root login SSH | `check_ssh_root_login` |
| 5.2.8 - HostbasedAuthentication | `check_ssh_hostbased` |
| 5.2.9 - PermitEmptyPasswords | `check_ssh_empty_pass` |
| 5.2.10 - PermitUserEnvironment | `check_ssh_user_env` |
| 5.2.11 - IgnoreRhosts | `check_ssh_ignorerhosts` |
| 5.2.12 - X11 forwarding | `check_ssh_x11` |
| 5.2.13 - AllowTcpForwarding | `check_ssh_tcp_forward` |
| 5.2.15 - Banner SSH | `check_ssh_banner` |
| 5.2.16 - MaxAuthTries | `check_ssh_maxauth` |
| 5.2.18 - MaxSessions | `check_ssh_maxsessions` |
| 5.2.19 - LoginGraceTime | `check_ssh_grace_time` |
| 5.2.20 - Idle timeout | `check_ssh_idle_timeout` |
| 5.3.1 - sudo instalado | `check_sudo_installed` |
| 5.3.2 - sudo use_pty | `check_sudo_pty` |
| 5.3.3 - sudo logfile | `check_sudo_logfile` |
| 5.3.6 - sudo timeout | `check_sudo_timeout` |
| 5.3.7 - su restringido | `check_su_restricted` |
| 5.5.1 - requisitos contraseñas | `check_password_requirements` |
| 5.5.2 - lockout | `check_password_lockout` |
| 5.5.3 - reuso limitado | `check_password_reuse` |
| 5.5.4 - hash SHA-512 | `check_password_hashing` |
| 5.6.1.1 - expiracion 365 dias | `check_password_expiration` |
| 5.6.1.2 - dias minimos | `check_password_min_days` |
| 5.6.1.3 - dias advertencia | `check_password_warn_age` |
| 5.6.1.4 - bloqueo inactivo | `check_password_inactive` |
| 6.1.1 - permisos passwd | `check_passwd_perms` |
| 6.1.2 - permisos passwd- | `check_passwd_dash_perms` |
| 6.1.3 - permisos group | `check_group_perms` |
| 6.1.4 - permisos group- | `check_group_dash_perms` |
| 6.1.5 - permisos shadow | `check_shadow_perms` |
| 6.1.6 - permisos shadow- | `check_shadow_dash_perms` |
| 6.1.7 - permisos gshadow | `check_gshadow_perms` |
| 6.1.8 - permisos gshadow- | `check_gshadow_dash_perms` |
| 6.2.1 - shadow passwords | `check_shadowed_passwords` |
| 6.2.2 - sin contraseñas vacias | `check_shadow_empty` |
| 6.2.9 - UID 0 unico | `check_unique_uid0` |

## Próximas tareas

1. **P0:** validar CI de la rama `cis-mount-audit-and-status`; no integrar a `main` sin regresiones en verde.
2. **P1:** crear el mapping exacto recomendación→evidencia→módulo para cada distro/versión/nivel CIS, usando el documento completo del benchmark.
3. **P1:** añadir primero checks de solo lectura para 3.2/3.3 y 4.2, utilizando los módulos existentes como referencia y sin duplicar remediaciones.
4. **P1:** completar checks efectivos de GRUB password/permisos y otros controles de cuentas/archivos no cubiertos aún.
5. **P2:** para cada recomendación ausente, etiquetar impacto como bajo, condicionado o alto. Cambios de bajo riesgo pueden ser idempotentes tras validar; los que alteran autenticación, red, mounts, servicios o arranque deben pedir confirmación por acción e informar el impacto.
6. **P3:** mantener este mapa y `PROJECT-STATUS.md` en cada ciclo; no convertir el número de checks ni el porcentaje local en una promesa de cumplimiento CIS.

## Criterio de salida

Una recomendación se marca como implementada solo cuando el control CIS vigente está identificado, se comprueba el estado efectivo (runtime y persistencia cuando aplique), existe una prueba de regresión, y cualquier remediación sensible tiene backup y consentimiento explícito.