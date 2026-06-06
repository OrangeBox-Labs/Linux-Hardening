#!/bin/bash

# ==============================================
# Script: disable-usb-storage.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Deshabilita USB Storage (CIS 1.1.24)
# ==============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Contadores
FIXED=0
WARNINGS=0
AUTO_FIX=false

# ==============================================
# DESHABILITAR USB STORAGE (CIS 1.1.24)
# ==============================================
disable_usb_storage() {
  local CONF_FILE="/etc/modprobe.d/usb_storage.conf"

  echo -e "\n${YELLOW}[*] CIS 1.1.24 - Deshabilitando USB Storage...${NC}"

  # Verificar si usb-storage esta cargado
  if lsmod | grep -q "^usb-storage"; then
    echo -e "${RED}[!] usb-storage esta CARGADO${NC}"
    NEED_FIX=1
  else
    echo -e "${GREEN}[✓] usb-storage no esta cargado${NC}"
    NEED_FIX=0
  fi

  # Verificar si ya esta deshabilitado
  if modprobe -n -v usb-storage 2>/dev/null | grep -q "install /bin/true"; then
    echo -e "${GREEN}[✓] usb-storage ya esta deshabilitado${NC}"
    NEED_FIX=0
  else
    echo -e "${RED}[!] usb-storage NO esta deshabilitado${NC}"
    NEED_FIX=1
  fi

  if [ $NEED_FIX -eq 1 ]; then
    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Deshabilitando usb-storage...${NC}"
      echo "# Deshabilitar USB Storage por seguridad (CIS 1.1.24)" >"$CONF_FILE"
      echo "install usb-storage /bin/true" >>"$CONF_FILE"
      rmmod usb-storage 2>/dev/null
      echo -e "${GREEN}[✓] usb-storage deshabilitado${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${YELLOW}    Recomendacion: Crear $CONF_FILE con 'install usb-storage /bin/true'${NC}"
      echo -e "${YELLOW}    Luego ejecutar: rmmod usb-storage${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Deshabilitar USB Storage - CIS 1.1.24${NC}"
  echo -e "${GREEN}============================================${NC}"

  # Procesar argumentos
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    echo -e "${YELLOW}[!] Modo automatico: se aplicaran correcciones sin preguntar${NC}"
    echo -e "${YELLOW}[!] 3 segundos para cancelar (Ctrl+C)...${NC}"
    sleep 3
  fi

  # Ejecutar funcion
  disable_usb_storage

  # Resumen final
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  RESUMEN${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "  • Configuraciones corregidas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"

  echo -e "${GREEN}============================================${NC}"
}

# Ejecutar como root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
