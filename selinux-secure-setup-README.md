# Auditoría de estado de SELinux

Por política operacional OrangeBox, este script es exclusivamente de **solo lectura**.

Comprueba el modo en ejecución mediante `getenforce` cuando está disponible y lee `SELINUX=` desde `/etc/selinux/config`. Informa si SELinux está `Enforcing`, `Permissive` o `Disabled`, pero nunca cambia el modo, edita la configuración, modifica contextos, elimina paquetes ni solicita reinicios.

## Uso

```bash
./selinux-secure-setup.sh
```

El módulo `selinux-setup` de `linux-hardening.sh` está bloqueado por la misma política. Si es necesario cambiar SELinux, debe realizarse mediante un procedimiento operativo independiente que no forme parte del hardening automatizado.
