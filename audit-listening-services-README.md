# Auditoría de servicios en escucha

audit-listening-services.sh es un inventario **estrictamente de solo lectura** de sockets TCP y UDP locales.

## Uso

    ./audit-listening-services.sh
    ./audit-listening-services.sh --check

Requiere root para intentar mostrar los procesos propietarios. No instala ni elimina paquetes, no detiene servicios y no modifica el firewall.

## Qué muestra

- Protocolo, estado del socket, puerto y dirección local.
- Proceso informado por ss, cuando está disponible.
- Categoría orientativa derivada primero del proceso real y no solamente del número de puerto.
- Alcance del bind: loopback, todas las interfaces o una IP específica.

La clasificación contempla procesos frecuentes de SSH, FTP, DNS, RPC/NFS, web, correo, bases de datos, monitoreo y servicios habituales de cPanel/Imunify. Los sockets propiedad de systemd se señalan como activación por socket cuando corresponde y requieren identificar la unidad de destino. Un proceso no reconocido queda como NO_CLASIFICADO; no se sugiere eliminar paquetes basándose en el puerto.

## Interpretación y límites

Un bind a 0.0.0.0, [::] o * significa que el proceso escucha en todas las interfaces locales de esa familia. **No demuestra que sea accesible desde Internet**. La accesibilidad también depende de CSF, Imunify360, el backend de firewall activo, rutas, reglas del proveedor y firewalls externos.

Esta utilidad no modifica ni reconcilia reglas de firewall. Para revisar CSF, Imunify360 y backends iptables/nftables/legacy, ejecute:

    ./network-hardening.sh --check

Estas comprobaciones son diagnósticas; no reemplazan una prueba desde un host externo ni la revisión de la política de acceso esperada para cada servidor.
