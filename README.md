# Linux Server Hardening Scripts

Colección de scripts para hardening de servidores Linux basados en estándares de seguridad como CIS Benchmarks.

## 📋 Descripción

Este repositorio contiene scripts automatizados para endurecer la configuración de seguridad de servidores Linux. Los scripts están diseñados para ser ejecutados en entornos de producción después de pruebas adecuadas.

## 🖥️ Distribuciones Compatibles

| Distribución | Versiones | Estado |
|--------------|-----------|--------|
| **RHEL / CentOS** | 7, 8, 9 | ✅ Probado |
| **Rocky Linux / AlmaLinux** | 8, 9 | ✅ Compatible |
| **Ubuntu Server** | 20.04, 22.04, 24.04 | ✅ Compatible |
| **Debian** | 11, 12 | ✅ Compatible |
| **Oracle Linux** | 7, 8, 9 | ⚠️ No probado |

## 📦 Scripts Disponibles

| Script | Enfoque | CIS Benchmark |
|--------|---------|---------------|
| `hardening_filesystems.sh` | Hardening de sistema de archivos | 1.1.x |
| `fix_cramfs.sh` | Deshabilitar sistemas de archivos obsoletos | 1.1.1.1 |
| `fix_modules.sh` | Deshabilitar módulos del kernel no usados | 1.1.x |

## 🚀 Uso Rápido

```bash
# Clonar el repositorio
git clone https://github.com/tu-usuario/hardening-scripts.git
cd hardening-scripts

# Dar permisos de ejecución
chmod +x *.sh

# Ejecutar en modo verificación (solo lectura)
./hardening_filesystems.sh

# Ejecutar en modo automático (aplica correcciones)
./hardening_filesystems.sh --fix

