#!/bin/bash

# ==============================================
# Script: aide-install.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instala y configura AIDE (CIS 1.3.1 y 1.3.2)
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
# DETECTAR GESTOR DE PAQUETES
# ==============================================
detect_pkg_manager() {
  if command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  else
    echo ""
  fi
}

# ==============================================
# INSTALAR AIDE (CIS 1.3.1)
# ==============================================
install_aide() {
  echo -e "\n${YELLOW}[*] CIS 1.3.1 - Verificando AIDE...${NC}"

  if rpm -q aide &>/dev/null; then
    local aide_version=$(rpm -q aide)
    echo -e "${GREEN}[✓] AIDE ya esta instalado: $aide_version${NC}"
    return 0
  fi

  echo -e "${RED}[!] AIDE NO esta instalado${NC}"

  if [ "$AUTO_FIX" = true ]; then
    PKG_MANAGER=$(detect_pkg_manager)

    if [ -z "$PKG_MANAGER" ]; then
      echo -e "${RED}[!] No se encontro yum ni dnf${NC}"
      exit 1
    fi

    echo -e "${YELLOW}[*] Instalando AIDE con $PKG_MANAGER...${NC}"
    $PKG_MANAGER install aide -y

    if rpm -q aide &>/dev/null; then
      echo -e "${GREEN}[✓] AIDE instalado correctamente${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] No se pudo instalar AIDE${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}    Recomendacion: yum install aide o dnf install aide${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# INICIALIZAR BASE DE DATOS DE AIDE
# ==============================================
init_aide_db() {
  echo -e "\n${YELLOW}[*] Inicializando base de datos de AIDE...${NC}"

  if [ -f /var/lib/aide/aide.db.gz ]; then
    echo -e "${GREEN}[✓] Base de datos de AIDE ya existe${NC}"
    return 0
  fi

  if [ "$AUTO_FIX" = true ]; then
    echo -e "${YELLOW}[*] Ejecutando aide --init...${NC}"
    aide --init

    if [ -f /var/lib/aide/aide.db.new.gz ]; then
      mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
      echo -e "${GREEN}[✓] Base de datos de AIDE inicializada${NC}"
      FIXED=$((FIXED + 1))
    else
      echo -e "${RED}[!] No se pudo inicializar la base de datos${NC}"
    fi
  else
    echo -e "${YELLOW}    Recomendacion: aide --init${NC}"
    echo -e "${YELLOW}    Luego: mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# CONFIGURAR VERIFICACION PERIODICA (CIS 1.3.2)
# ==============================================
configure_periodic_check() {
  echo -e "\n${YELLOW}[*] CIS 1.3.2 - Configurando verificacion periodica de AIDE...${NC}"

  if crontab -u root -l 2>/dev/null | grep -q "aide --check"; then
    echo -e "${GREEN}[✓] Verificacion periodica ya configurada en cron${NC}"
    return 0
  fi

  echo -e "${RED}[!] No hay verificacion periodica de AIDE configurada${NC}"

  if [ "$AUTO_FIX" = true ]; then
    echo -e "${YELLOW}[*] Configurando verificacion diaria via cron...${NC}"
    (
      crontab -u root -l 2>/dev/null
      echo "0 5 * * * /usr/sbin/aide --check"
    ) | crontab -u root -
    echo -e "${GREEN}[✓] AIDE configurado para ejecutarse diariamente a las 5:00 AM${NC}"
    FIXED=$((FIXED + 1))
  else
    echo -e "${YELLOW}    Recomendacion: Agregar al crontab: 0 5 * * * /usr/sbin/aide --check${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Instalacion y Configuracion de AIDE${NC}"
  echo -e "${GREEN}  CIS 1.3.1 - 1.3.2${NC}"
  echo -e "${GREEN}============================================${NC}"

  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    AUTO_FIX=true
    echo -e "${YELLOW}[!] Modo automatico: se aplicaran correcciones sin preguntar${NC}"
    echo -e "${YELLOW}[!] 3 segundos para cancelar (Ctrl+C)...${NC}"
    sleep 3
  fi

  install_aide
  init_aide_db
  configure_periodic_check

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  RESUMEN${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "  • Configuraciones corregidas: ${GREEN}$FIXED${NC}"
  echo -e "  • Advertencias pendientes: ${YELLOW}$WARNINGS${NC}"
  echo -e "  • Para corregir ejecuta ./aide-install.sh --fix "
  echo -e "${GREEN}============================================${NC}"
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
