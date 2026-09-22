# OrangeBox - Mitigacion del quartet LPE de kernel 2026

## Vulnerabilidades cubiertas

Este script cubre las cuatro vulnerabilidades de kernel publicadas en septiembre de 2026:

| CVE | Nombre | Subsistema | Mitigacion principal |
|---|---|---|---|
| CVE-2026-80844 | DirtyAH6 | IPv6 AH6 / XFRM | bloquear ah6 y restringir user namespaces |
| CVE-2026-81000 | TUNderflow | TUN/TAP | bloquear tun cuando no se necesita y restringir user namespaces |
| CVE-2026-68121 | PPPoEject | PPPoE | bloquear pppoe y restringir user namespaces |
| CVE-2026-74469 | DiagSpill | SCTP / sctp_diag | bloquear sctp y sctp_diag |

Las cuatro permiten corrupcion de memoria en el kernel bajo las condiciones descritas por el investigador. Las tres primeras tienen una ruta de explotacion local basada en user namespaces sin privilegios; DiagSpill no depende de user namespaces. Red Hat clasifica actualmente las cuatro como afectando RHEL 7, 8, 9 y 10 y, al 21 de septiembre de 2026, el boletin sigue en investigacion mientras se aceleran los fixes. citeturn646843view0

## Por que no comparamos el numero de version del kernel

RHEL y derivados suelen incorporar correcciones mediante backports. Por eso un numero de version upstream aparentemente antiguo no implica por si solo que el kernel del vendor siga vulnerable.

El script revisa el changelog del paquete RPM correspondiente al kernel en ejecucion y busca las cuatro referencias CVE. Si las cuatro aparecen, el script considera que los fixes estan documentados en ese kernel y no aplica mitigaciones adicionales.

Si el changelog no permite verificar el estado, el script trata el estado como desconocido y aplica la mitigacion conservadora cuando se usa --fix.

## CentOS Stream 8 y AlmaLinux 8

### CentOS Stream 8

CentOS Stream 8 alcanzo EOL el 31 de mayo de 2024 y no recibe actualizaciones de seguridad. Por lo tanto no debe esperarse un nuevo kernel de CentOS Stream 8 que incorpore estas correcciones. citeturn281334search0turn281334search5

### AlmaLinux 8

AlmaLinux 8 mantiene soporte de seguridad hasta 2029. Por lo tanto no corresponde asumir que AlmaLinux 8 quedara sin parche solamente por ser EL8; debe verificarse el kernel distribuido por AlmaLinux cuando el fix sea publicado. citeturn281334search1turn281334search14

El script esta pensado justamente para este escenario: si el kernel del vendor todavia no contiene los cuatro fixes, aplica mitigacion y permite retirar esa mitigacion posteriormente cuando el kernel ya este corregido.

## Mitigaciones

Red Hat indica actualmente dos mecanismos:

1. Bloquear los modulos afectados:
   - ah6
   - tun
   - pppoe
   - sctp
   - sctp_diag

2. Deshabilitar user namespaces sin privilegios mediante:

~~~
sysctl -w user.max_user_namespaces=0
~~~

La segunda medida cubre DirtyAH6, TUNderflow y PPPoEject, pero no cubre DiagSpill. Red Hat advierte que bloquear modulos puede romper funcionalidad asociada y que deshabilitar user namespaces puede afectar contenedores, sandboxes y otros workloads. citeturn646843view0

## Politica del script

El modo conservador bloquea:

~~~
ah6
pppoe
sctp
sctp_diag
~~~

y deshabilita:

~~~
user.max_user_namespaces=0
~~~

tun queda fuera del modo conservador porque es habitual en VPN, OpenVPN/WireGuard, contenedores y networking de usuariospace. Para bloquearlo:

~~~
./kernel-lpe-2026-mitigation.sh --fix --block-tun
~~~

O bien:

~~~
./kernel-lpe-2026-mitigation.sh --strict
~~~

que bloquea los cinco modulos.

## Uso

Auditoria sin cambios:

~~~
chmod +x kernel-lpe-2026-mitigation.sh
./kernel-lpe-2026-mitigation.sh --check
~~~

Aplicar mitigacion conservadora:

~~~
./kernel-lpe-2026-mitigation.sh --fix
~~~

Incluir TUN/TAP:

~~~
./kernel-lpe-2026-mitigation.sh --fix --block-tun
~~~

Bloquear los cinco modulos:

~~~
./kernel-lpe-2026-mitigation.sh --strict
~~~

## Importante sobre modulos ya cargados

El script no descarga modulos automaticamente.

Si ah6, pppoe, sctp, sctp_diag o tun ya estan cargados, el script escribe igualmente el bloqueo persistente y marca que es necesario reiniciar para que el bloqueo sea efectivo.

Si un modulo aparece como builtin, modprobe.d no puede deshabilitarlo. En ese caso la correccion requiere un kernel que contenga el fix del vendor.

## Archivos modificados

Con --fix puede crear:

~~~
/etc/sysctl.d/99-orangebox-kernel-lpe-2026.conf
/etc/modprobe.d/orangebox-kernel-lpe-2026.conf
~~~

Los archivos preexistentes se respaldan bajo:

~~~
/var/lib/orangebox/kernel-lpe-2026/backups/
~~~

## Principio de operacion

El script no intenta reemplazar el kernel, recompilarlo ni aplicar cherry-picks de commits upstream. El kernel CVE team recomienda actualizar a un kernel estable que incluya los fixes y desaconseja cherry-pickear cambios individuales como metodo normal de despliegue. citeturn923145search7turn923145search11

La mitigacion existe para los equipos que temporalmente no pueden instalar el kernel corregido.

## Advertencias

Antes de bloquear tun, pppoe, sctp o sctp_diag debe verificarse si el host necesita esa funcionalidad.

Casos tipicos que requieren especial cuidado:

- OpenVPN / WireGuard y otras VPN basadas en TUN/TAP.
- Plataformas de contenedores.
- Telefonia o telecomunicaciones que utilicen SCTP.
- IPv6 IPsec con AH6.
- Sistemas que necesiten PPPoE.

Red Hat señala especificamente estas dependencias en su boletin de seguridad. citeturn646843view0

## Autor

Felipe Roman / OrangeBox Labs

https://www.orangebox.cl
