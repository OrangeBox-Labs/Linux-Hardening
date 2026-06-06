# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x selinux-secure-setup.sh
```

# Script: selinux-secure-setup.sh

## Autor

Felipe Roman
Web: www.orangebox.cl
Email: froman@orangebox.cl

### ¿SELinux? La herramienta que nadie entiende y por lo mismo casi nadie la usa.

Para muchos, SELinux es un dolor de cabeza: complejo, confuso, a veces lento y capaz de arruinarte un paso a producción un viernes en la tarde. Es una herramienta tremenda, pero mal configurada genera más problemas de los que soluciona.

Con este script quiero tratar de facilitarte un poco la vida. Va a analizar todo lo que pueda encontrar en tu servidor y va a configurar SELinux acorde a eso.

**Pero seamos sinceros:** no es fácil hacerlo perfecto. Si algo se nos pasa, tu servidor puede resentirse... o hasta morir en el intento. 

Por eso, el script DEJA SELinux en modo "permisivo" (solo mira y registra, no bloquea nada). Así puedes probar, ver los logs y asegurarte de que todo funciona. Una vez que verifiques que está todo bien, recién ahí puedes cambiarlo a "enforcing" manualmente.

**Y por favor, respalda tu servidor antes de ejecutar cualquier cosa. No digas que no te avisamos.**

¿SELinux afecta el rendimiento? La respuesta corta:

Sí, pero en el mundo real casi no lo notas. Como ir con una mochila liviana.

Te muestro con números (todas las unidades están en microsegundos o en porcentaje):

| Qué mide | Sin SELinux | Con SELinux | Diferencia |
|----------|-------------|-------------|------------|
| Abrir y cerrar un archivo | 11.0 µs | 14.0 µs | +27% |
| Consultar atributos de un archivo | 8.06 µs | 10.3 µs | +28% |
| Crear un archivo nuevo | 22.0 µs | 26.0 µs | +18% |
| Enviar un paquete UDP | 310 µs | 356 µs | +15% |
| Crear un proceso (fork) | 499 µs | 505 µs | +1% |

La mayoría de estas operaciones son MICROSEGUNDOS. O sea, ni te enteras.

Ejemplos del mundo real (aquí las unidades son minutos o peticiones por segundo):

| Escenario | Sin SELinux | Con SELinux | Qué significa |
|-----------|-------------|-------------|---------------|
| Compilar el kernel Linux | 11:14 min | 11:15 min | 1 minuto más en una hora. Nada |
| Servidor web bajo mucha carga | 1311 req/seg | 1160 req/seg | -11% (el peor caso) |
| Servidor web uso normal | 1231 req/seg | 1221 req/seg | -0.8% (insignificante) |
| Base de datos PostgreSQL | 100% base | 99-101% | ±1%. Ni se mueve |

La conclusión corta:

El rendimiento NO es excusa para desactivar SELinux. El costo real en un servidor típico es entre 1% y 5%. A cambio, blindas tu sistema.

Mi recomendación: No lo apagues, dejenlo al menos en modo "permisivo", para tener logs de que está pasando.


Script para configurar SELinux en modo PERMISIVO de forma segura.
> NO activa enforcing - es seguro de ejecutar.

## ADVERTENCIA

Este script NO activa SELinux en modo enforcing.
Configura SELinux en modo PERMISIVO, que:
- Registra denegaciones en logs
- NO bloquea ningun servicio
- Permite identificar que reglas necesita su sistema

## Que hace este script

1. Analiza denegaciones existentes en audit.log
2. Genera politicas a partir de denegaciones encontradas
3. Identifica servicios activos y sus puertos
4. Configura contextos SELinux para puertos detectados
5. Verifica contextos de directorios importantes
6. Configura SELinux en modo permisivo (persistente)
7. NO activa enforcing bajo ninguna circunstancia

## Requisitos

- Acceso root
- Sistemas RHEL / CentOS / Rocky / AlmaLinux

## Uso

PRIMERA EJECUCION (si SELinux esta disabled):
  - Configura SELinux=permissive en /etc/selinux/config
  - Crea backup de la configuracion
  - Solicita reinicio del sistema

SEGUNDA EJECUCION (despues del reinicio):
  - Verifica que SELinux esta activo en modo permisivo
  - Configura puertos por defecto (80,443,22,3306)
  - Configura contextos para servicios activos
  - Restaura contextos de directorios importantes

## Para generar politicas
```
ausearch -ts recent -m avc | audit2allow -M local_policy
semodule -i local_policy.pp
```

## Para activar enforcing (despues de semanas sin denegaciones)

# ADVERTENCIA IMPORTANTE

Activar SELinux en modo enforcing puede causar que servicios o configuraciones dejen de funcionar correctamente.
Incluso podría hacer que un servidor no arranque más después del reinicio o que no se puedan volver a loguear.

***** POR FAVOR HAGAN UN FULL RESPALDO ANTES DE ACTIVAR EL MODO ENFORCING *****

Posibles problemas:
- Servicios web (Apache, Nginx) pueden no arrancar
- Bases de datos pueden perder acceso
- Aplicaciones personalizadas pueden fallar
- Scripts de usuario pueden ser bloqueados
- Servicios de red pueden dejar de responder

```
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
reboot
```



## CIS 1.6.1.7 - SETroubleshoot

SETroubleshoot es un servicio que muestra notificaciones graficas de denegaciones SELinux.
En servidores sin interfaz grafica (X Window) es innecesario y puede:

- Filtrar informacion sensible de seguridad
- Consumir recursos del sistema
- Crear vulnerabilidades innecesarias

### Verificar si esta instalado

```
rpm -q setroubleshoot
```

### Eliminar manualmente

```
yum remove setroubleshoot -y

dnf remove setroubleshoot -y
```

## Breve guía para configurar SELinux 

# Manual: Solucion de bloqueos SELinux en modo permisivo

## 1. Verificar estado de SELinux

```
getenforce
```

Debe mostrar: Permissive (NO Enforcing)

Si muestra "Disabled", active primero:

```
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
reboot
```

## 2. Ver denegaciones de SELinux

Ver denegaciones recientes:
```
ausearch -ts recent -m avc
```

Ver solo las ultimas 10:
```
ausearch -ts recent -m avc | tail -20
```

Ver en tiempo real:
```
tail -f /var/log/audit/audit.log | grep denied
```

Ver denegaciones de un servicio especifico:
```
ausearch -ts recent -m avc | grep httpd
ausearch -ts recent -m avc | grep mysql
```

## 3. Entender una denegacion

```
type=AVC msg=audit(1234567890.123:456): avc:  denied  { read } for  pid=1234 comm="httpd" name="index.html" dev="dm-0" ino=123456 scontext=system_u:system_r:httpd_t:s0 tcontext=unconfined_u:object_r:var_t:s0 tclass=file
```

Interpretacion:
- denied { read } = Accion bloqueada (lectura)
- comm="httpd" = Proceso que intenta acceder
- scontext = Contexto del proceso (origen)
- tcontext = Contexto del archivo (destino)
- tclass = Tipo de objeto (archivo, directorio, puerto)

## 4. Generar politica automaticamente

```
ausearch -ts recent -m avc | audit2allow -M local_policy
```

Instalar el modulo:
```
semodule -i local_policy.pp
```

Verificar instalacion:
```
semodule -l | grep local_policy
```

## 5. Corregir contextos de archivos

Ver contexto actual:
```
ls -Z /var/www/html/index.html
```

Corregir contexto de un archivo:
```
restorecon -v /var/www/html/index.html
```

Corregir todo un directorio:
```
restorecon -Rv /var/www/html/
```

## 6. Configurar contextos persistentes

Agregar regla permanente:
```
semanage fcontext -a -t httpd_sys_content_t "/var/www/html(/.*)?"
```

Aplicar la regla:
```
restorecon -Rv /var/www/html/
```

Ver reglas agregadas:
```
semanage fcontext -l | grep httpd
```

## 7. Configurar puertos personalizados

Ejemplo: Apache en puerto 8080
```
semanage port -a -t http_port_t -p tcp 8080
```

Verificar:
```
semanage port -l | grep http_port_t
```

Reiniciar servicio:
```
systemctl restart httpd
```

## 8. Ejemplo practico completo

Problema: Apache no puede leer archivos en /data/web

Paso 1 - Ver contexto:
```
ls -Z /data/web
```

Paso 2 - Ver denegaciones:
```
ausearch -ts recent -m avc | grep httpd
```

Paso 3 - Cambiar contexto:
```
semanage fcontext -a -t httpd_sys_content_t "/data/web(/.*)?"
restorecon -Rv /data/web
```

Paso 4 - Generar politica si es necesario:
```
ausearch -ts recent -m avc | audit2allow -M httpd_data
semodule -i httpd_data.pp
```

Paso 5 - Verificar:
```
systemctl restart httpd
```

## 9. Limpiar politicas generadas

Listar modulos:
```
semodule -l
```

Eliminar modulo:
```
semodule -r local_policy
```

Verificar eliminacion:
```
semodule -l | grep local_policy
```

## 10. Comandos utiles de diagnostico

Ver contexto de procesos:
```
ps -eZ | grep httpd
```

Ver contexto de puertos:
```
semanage port -l | grep http
```

Ver booleans de SELinux:
```
getsebool -a | grep httpd
```

Cambiar boolean:
```
setsebool -P httpd_enable_cgi on
```

## 11. Resumen del flujo de trabajo

1. Asegurar que SELinux esta en permisivo: 
```
getenforce
```

2. Ejecutar su aplicacion/servicio

3. Ver denegaciones: 
```
ausearch -ts recent -m avc
```

4. Si es contexto de archivo -> restorecon
```
   restorecon -Rv /ruta/del/archivo
```

5. Si es puerto -> semanage port
```
   semanage port -a -t contexto -p tcp PUERTO
```

6. Si es otro tipo de denegacion -> audit2allow
```
   ausearch -ts recent -m avc | audit2allow -M mi_politica
   semodule -i mi_politica.pp
```

7. Probar de nuevo

8. Si funciona, pasar a enforcing (solo si ya no hay denegaciones)
```
   sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
   reboot
```

## Nota importante

Mientras este en modo permisivo, SELinux NO bloquea nada, solo registra.
Puede usar el sistema con normalidad mientras genera las politicas.
Solo cuando pase a enforcing comenzara a bloquear realmente.

## Licencia

MIT


---

**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs
