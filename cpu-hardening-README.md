# Instalación

```
git clone https://github.com/OrangeBox-Labs/Linux-Hardening.git
cd Linux-Hardening
chmod +x cpu-hardening.sh
```

# Script: cpu-hardening.sh

Script para habilitar protecciones de memoria de la CPU contra ataques de buffer overflow.

## Autor

- **Felipe Roman**
- Web: www.orangebox.cl
- Email: froman@orangebox.cl

## Que previene cada parametro

### XD/NX Support (CIS 1.5.2)

La proteccion NX (No eXecute) en procesadores AMD o XD (Execute Disable) en Intel evita que codigo malicioso se ejecute en areas de memoria que deberian contener solo datos. Esto previene ataques de buffer overflow y ejecucion de codigo arbitrario.

| Tecnologia | Descripcion |
|------------|-------------|
| NX (AMD) | No eXecute - previene ejecucion en paginas de memoria |
| XD (Intel) | Execute Disable - previene ejecucion en paginas de memoria |
| XN (ARM) | eXecute Never - equivalente en arquitectura ARM |

### Exec-Shield

Proteccion adicional de Red Hat que complementa NX/XD para sistemas 32 bits.

### ASLR (CIS 1.5.3)

Address Space Layout Randomization: Aleatoriza las direcciones de memoria de procesos y librerias, dificultando ataques que requieren conocer direcciones especificas de memoria.

### ptrace_scope

Restringe el uso de ptrace, impidiendo que procesos no autorizados inspeccionen o manipulen otros procesos.

### SMAP / SMEP

Protecciones de CPU modernas (Intel Broadwell+, AMD Zen+) que previenen que el kernel ejecute codigo de usuario o acceda a memoria de usuario.

## Requisitos

- Acceso root
- Para sistemas 32 bits: CPU con soporte PAE
- Para sistemas 64 bits: Soporte nativo
- BIOS/UEFI con opcion "Execute Disable" habilitada

## Verificacion manual previa

Verificar soporte de protecciones en la CPU:

# Verificar flags de CPU
```
grep nx /proc/cpuinfo
grep smap /proc/cpuinfo
grep smep /proc/cpuinfo
```

# Verificar estado actual
```
cat /proc/sys/kernel/randomize_va_space
cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
dmesg | grep -i "NX.*protection"
```


---

**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs
