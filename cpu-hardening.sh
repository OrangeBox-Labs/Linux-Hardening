#!/bin/bash

# ==============================================
# Script: cpu-hardening.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Habilita protecciones CPU contra buffer overflow
#              CIS 1.5.2 - XD/NX support
#              NX (No eXecute) / XD (Execute Disable)
# ==============================================

# Colores para output
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$SCRIPT_DIR/lib/sysctl-safe.sh" ]; then
  # shellcheck source=lib/sysctl-safe.sh
  source "$SCRIPT_DIR/lib/sysctl-safe.sh"
else
  echo "[ERROR] Falta lib/sysctl-safe.sh; actualice el repositorio completo." >&2
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Contadores
FIXED=0
WARNINGS=0
AUTO_FIX=false

# ==============================================
# FUNCION PARA HACER BACKUP
# ==============================================
make_backup() {
  local file="$1"
  if [ -f "$file" ] && [ ! -f "${file}.bak.$(date +%Y%m%d)" ]; then
    cp "$file" "${file}.bak.$(date +%Y%m%d)"
    echo -e "${GREEN}[✓] Backup creado: ${file}.bak.$(date +%Y%m%d)${NC}"
  fi
}

# ==============================================
# 1. VERIFICAR SOPORTE XD/NX (CIS 1.5.2)
# ==============================================
check_nx_support() {
  echo -e "\n${YELLOW}[*] CIS 1.5.2 - Verificando soporte XD/NX...${NC}"

  # Verificar mediante dmesg
  if dmesg 2>/dev/null | grep -qi "NX.*protection.*active"; then
    echo -e "${GREEN}[✓] XD/NX protection activa en el kernel${NC}"
    return 0
  fi

  # Verificar mediante journalctl
  if journalctl 2>/dev/null | grep -qi "NX.*protection.*active"; then
    echo -e "${GREEN}[✓] XD/NX protection activa en el kernel${NC}"
    return 0
  fi

  # Verificar mediante cpuinfo
  if grep -qi "nx" /proc/cpuinfo 2>/dev/null; then
    echo -e "${GREEN}[✓] CPU soporta NX/XD (flag nx presente)${NC}"
    # La ausencia del mensaje de arranque no demuestra que NX esté deshabilitado.
    # El estado se marca como no confirmado en lugar de generar un falso positivo.
    echo -e "${YELLOW}[!] CPU soporta NX/XD, pero el log del kernel no confirma su estado activo; no se puede concluir que esté desactivado.${NC}"
    WARNINGS=$((WARNINGS + 1))
    NEED_FIX=0
  else
    echo -e "${RED}[!] CPU no soporta NX/XD o no esta disponible${NC}"
    NEED_FIX=0
  fi

  if [ $NEED_FIX -eq 1 ]; then
    echo -e "${RED}[!] XD/NX protection NO esta activa${NC}"

    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Verificando requisitos para activar NX/XD...${NC}"

      # Detectar arquitectura
      ARCH=$(uname -m)

      if [ "$ARCH" = "i686" ] || [ "$ARCH" = "i386" ]; then
        # Sistemas 32 bits necesitan PAE
        if ! grep -qi "pae" /proc/cpuinfo; then
          echo -e "${RED}[!] CPU no soporta PAE, no se puede activar NX/XD${NC}"
          echo -e "${YELLOW}    Requiere hardware con soporte PAE y kernel PAE${NC}"
          WARNINGS=$((WARNINGS + 1))
        else
          echo -e "${YELLOW}[*] Instalando kernel PAE para 32 bits...${NC}"
          if command -v yum &>/dev/null; then
            yum install kernel-PAE -y
            echo -e "${GREEN}[✓] Kernel PAE instalado. Se requiere reinicio.${NC}"
            FIXED=$((FIXED + 1))
          elif command -v dnf &>/dev/null; then
            dnf install kernel-PAE -y
            echo -e "${GREEN}[✓] Kernel PAE instalado. Se requiere reinicio.${NC}"
            FIXED=$((FIXED + 1))
          else
            echo -e "${RED}[!] No se pudo instalar kernel PAE${NC}"
          fi
        fi
      elif [ "$ARCH" = "x86_64" ]; then
        # Sistemas 64 bits soportan NX/XD nativamente
        echo -e "${RED}[!] Sistema 64 bits deberia tener NX/XD activo por defecto${NC}"
        echo -e "${YELLOW}    Verifique que la BIOS/UEFI tenga la opcion 'Execute Disable' habilitada${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: Activar NX/XD en BIOS y verificar kernel${NC}"
      if [ "$ARCH" = "x86_64" ]; then
        echo -e "${YELLOW}    Sistemas 64 bits: Verificar que 'nx' aparezca en /proc/cpuinfo${NC}"
      else
        echo -e "${YELLOW}    Sistemas 32 bits: Instalar kernel-PAE${NC}"
      fi
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# 2. VERIFICAR KERNEL EXEC-SHIELD
# ==============================================
check_exec_shield() {
  echo -e "\n${YELLOW}[*] Verificando Exec-Shield (protección adicional)...${NC}"
  if [ -f /proc/sys/kernel/exec-shield ]; then
    local exec_shield
    exec_shield="$(sysctl -n kernel.exec-shield 2>/dev/null || cat /proc/sys/kernel/exec-shield 2>/dev/null || true)"
    case "$exec_shield" in
      1|2) echo -e "${GREEN}[✓] Exec-Shield activo (valor: $exec_shield)${NC}" ;;
      *)
        if sysctl_safe_apply "kernel.exec-shield" "1" "Exec-Shield: activa la protección NX/XD heredada cuando el kernel la soporta." "/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf" "/var/backups/orangebox-cpu-hardening" "$AUTO_FIX" "" ""; then
          [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED + 1))
        else
          WARNINGS=$((WARNINGS + 1))
        fi
        ;;
    esac
  else
    echo -e "${YELLOW}[!] Exec-Shield no disponible (sistemas modernos usan NX/XD)${NC}"
  fi
}

# ==============================================
# 3. VERIFICAR ASLR (CIS 1.5.3)
# ==============================================
check_aslr() {
  echo -e "\n${YELLOW}[*] Verificando ASLR (Address Space Layout Randomization)...${NC}"
  local aslr_value
  aslr_value="$(sysctl -n kernel.randomize_va_space 2>/dev/null || true)"
  if [ -z "$aslr_value" ]; then
    echo -e "${YELLOW}[!] kernel.randomize_va_space no disponible${NC}"
    WARNINGS=$((WARNINGS + 1))
    return
  fi
  if [ "$aslr_value" = 2 ]; then
    echo -e "${GREEN}[✓] ASLR completo (valor: 2)${NC}"
    return
  fi
  if sysctl_safe_apply "kernel.randomize_va_space" "2" "ASLR: aleatoriza el espacio de direcciones de procesos y librerías." "/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf" "/var/backups/orangebox-cpu-hardening" "$AUTO_FIX" "" ""; then
    [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED + 1))
  else
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# 4. VERIFICAR RESTRICCION DE KERNEL PTRACE
# ==============================================
check_ptrace_scope() {
  echo -e "\n${YELLOW}[*] Verificando restricción ptrace...${NC}"
  local ptrace_value
  ptrace_value="$(sysctl -n kernel.yama.ptrace_scope 2>/dev/null || true)"
  if [ -z "$ptrace_value" ]; then
    echo -e "${YELLOW}[!] Yama ptrace no disponible (kernel sin soporte)${NC}"
    return
  fi
  case "$ptrace_value" in
    0)
      if sysctl_safe_apply "kernel.yama.ptrace_scope" "1" "Restringe ptrace a procesos permitidos; puede afectar depuración, gdb/strace y ciertos monitores." "/etc/sysctl.d/zzzzzzzz-orangebox-sysctl-overrides.conf" "/var/backups/orangebox-cpu-hardening" "$AUTO_FIX" "" ""; then
        [ "$SYSCTL_SAFE_CHANGED" = true ] && FIXED=$((FIXED + 1))
      else
        WARNINGS=$((WARNINGS + 1))
      fi
      ;;
    1) echo -e "${GREEN}[✓] ptrace restringido a procesos hijos (valor: 1)${NC}" ;;
    2) echo -e "${GREEN}[✓] ptrace restringido a root (valor: 2)${NC}" ;;
    3) echo -e "${GREEN}[✓] ptrace completamente restringido (valor: 3)${NC}" ;;
    *) echo -e "${YELLOW}[!] Valor ptrace_scope inesperado: $ptrace_value${NC}"; WARNINGS=$((WARNINGS + 1)) ;;
  esac
}

# ==============================================
# 5. VERIFICAR SMAP/SMUP (protecciones CPU modernas)
# ==============================================
check_smap_smep() {
  echo -e "\n${YELLOW}[*] Verificando protecciones CPU adicionales...${NC}"

  # Verificar SMAP (Supervisor Mode Access Prevention)
  if grep -qi "smap" /proc/cpuinfo 2>/dev/null; then
    echo -e "${GREEN}[✓] SMAP (Supervisor Mode Access Prevention) soportado${NC}"
  else
    echo -e "${YELLOW}[!] SMAP no soportado por la CPU${NC}"
  fi

  # Verificar SMEP (Supervisor Mode Execution Prevention)
  if grep -qi "smep" /proc/cpuinfo 2>/dev/null; then
    echo -e "${GREEN}[✓] SMEP (Supervisor Mode Execution Prevention) soportado${NC}"
  else
    echo -e "${YELLOW}[!] SMEP no soportado por la CPU${NC}"
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  CPU Hardening - Protecciones de Memoria${NC}"
  echo -e "${GREEN}  CIS 1.5.2, 1.5.3 y controles adicionales${NC}"
  echo -e "${GREEN}============================================${NC}"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    echo -e "${YELLOW}[!] Modo automatico: se aplicaran correcciones sin preguntar${NC}"
    echo -e "${YELLOW}[!] 3 segundos para cancelar (Ctrl+C)...${NC}"
    sleep 3
  fi

  check_nx_support
  check_exec_shield
  check_aslr
  check_ptrace_scope
  check_smap_smep

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  RESUMEN${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "  • Configuraciones corregidas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "${GREEN}============================================${NC}"

  if [ $WARNINGS -gt 0 ]; then
    echo -e "\n  • Para corregir ejecuta: ./cpu-hardening.sh --fix \n"
  fi

  if [ $FIXED -gt 0 ]; then
    echo -e "${YELLOW}[!] Se recomienda reiniciar el sistema para asegurar los cambios${NC}"
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
