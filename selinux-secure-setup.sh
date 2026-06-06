#!/bin/bash

# ==============================================
# Script: selinux-secure-setup.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Configuracion SEGURA de SELinux en modo permisivo
#              Si SELinux esta disabled, lo habilita y pide reinicio
# ==============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;208m'
BLUE='\033[0;34m'
NC='\033[0m'

# Contadores
FIXED=0
WARNINGS=0

# Archivo de marca para segunda fase
FLAG_FILE="/root/.selinux_setup_done"

# ==============================================
# NOTA DE RESPONSABILIDAD
# ==============================================
show_liability_notice() {
  echo -e "\n${GREEN}================================================================================${NC}"
  echo -e "${GREEN}                         AVISO LEGAL Y DESCARGO DE RESPONSABILIDAD${NC}"
  echo -e "${ORANGE}                                        OrangeBox${NC}"
  echo -e "${GREEN}================================================================================${NC}"
  echo -e "${GREEN}"
  echo -e "Este script se proporciona \"TAL CUAL\" (AS IS), sin garantias de ningun tipo."
  echo -e "${NC}"
  echo -e "${GREEN}================================================================================${NC}"
  echo -e "${GREEN}"
  echo -e "                     ESTE SCRIPT USA MODO PERMISIVO, NO ENFORCING"
  echo -e "${NC}"
  echo -e "${GREEN}Por defecto, este script configura SELinux en MODO PERMISIVO, lo que significa que:${NC}"
  echo -e "- NO se bloqueara ningun servicio"
  echo -e "- Solo se registraran las denegaciones en logs"
  echo -e "- El sistema seguira funcionando como hasta ahora"
  echo -e ""
  echo -e "El modo ENFORCING NO se activa automaticamente en ningun caso."
  echo -e ""
  echo -e "${GREEN}================================================================================${NC}"
  echo -e "${YELLOW}RIESGOS CONOCIDOS (aun en modo permisivo):${NC}"
  echo -e "- Posibles problemas de contexto en archivos"
  echo -e "- Algunas aplicaciones pueden comportarse diferente"
  echo -e "- Los logs pueden llenarse de denegaciones"
  echo -e ""
  echo -e "${GREEN}================================================================================${NC}"
  echo -e "${RED}EL AUTOR NO SE HACE RESPONSABLE POR:${NC}"
  echo -e "- Danos directos, indirectos, incidentales o consecuentes"
  echo -e "- Perdida de datos o interrupcion del servicio"
  echo -e ""
  echo -e "${GREEN}================================================================================${NC}"
  echo -e "${YELLOW}RECOMENDACIONES ANTES DE EJECUTAR:${NC}"
  echo -e "1. HAGA UN BACKUP COMPLETO (snapshot en VMware recomendado)"
  echo -e "2. PRUEBE EN ENTORNO NO PRODUCTIVO primero"
  echo -e "3. ASEGURE ACCESO FISICO O IPMI al servidor"
  echo -e ""
  echo -e "${GREEN}================================================================================${NC}"
  echo -e "${YELLOW}Pulse Ctrl+C ahora para cancelar, o presione Enter para continuar...${NC}"
  read -r
}

# ==============================================
# VERIFICAR SI ES PRIMERA O SEGUNDA FASE
# ==============================================
check_phase() {
  if [ -f "$FLAG_FILE" ]; then
    return 1 # Segunda fase - ya se reinicio
  else
    return 0 # Primera fase - aun no se reinicia
  fi
}

# ==============================================
# VERIFICAR ESTADO ACTUAL DE SELINUX
# ==============================================
check_selinux_status() {
  echo -e "\n${BLUE}[*] Verificando estado actual de SELinux...${NC}"

  if command -v getenforce &>/dev/null; then
    current_mode=$(getenforce 2>/dev/null)
    echo -e "  Modo actual: $current_mode"

    if [ "$current_mode" = "Disabled" ]; then
      echo -e "${RED}[!] SELinux esta DESHABILITADO.${NC}"
      echo -e "${YELLOW}    Se configurara en modo permisivo y se requerira reinicio.${NC}"
      return 1
    elif [ "$current_mode" = "Enforcing" ]; then
      echo -e "${YELLOW}[!] SELinux esta en enforcing. Se cambiara a permisivo.${NC}"
      return 0
    elif [ "$current_mode" = "Permissive" ]; then
      echo -e "${GREEN}[✓] SELinux ya esta en modo permisivo${NC}"
      return 0
    fi
  fi
  return 0
}

# ==============================================
# HABILITAR SELINUX EN MODO PERMISIVO (PRIMERA FASE)
# ==============================================
enable_selinux_permissive() {
  echo -e "\n${BLUE}[*] HABILITANDO SELinux en modo permisivo...${NC}"

  # Backup de configuracion
  BACKUP_DIR="/root/selinux-bkp-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  cp /etc/selinux/config "$BACKUP_DIR/" 2>/dev/null
  echo -e "${GREEN}[✓] Backup guardado en: $BACKUP_DIR${NC}"

  # Cambiar a permisivo en el archivo
  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

  # Verificar cambio
  new_config=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
  if [ "$new_config" = "permissive" ]; then
    echo -e "${GREEN}[✓] SELinux configurado a permisivo (requiere reinicio)${NC}"

    # Crear archivo de marca para segunda fase
    echo "$BACKUP_DIR" >"$FLAG_FILE"
    echo "PHASE=2" >>"$FLAG_FILE"

    return 0
  else
    echo -e "${RED}[!] No se pudo configurar SELinux${NC}"
    return 1
  fi
}

# ==============================================
# SEGUNDA FASE: CONFIGURAR CONTEXTOS Y POLITICAS
# ==============================================
phase2_configure() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  SEGUNDA FASE - Configuracion de SELinux${NC}"
  echo -e "${GREEN}============================================${NC}"

  # Leer backup dir del archivo de marca
  if [ -f "$FLAG_FILE" ]; then
    BACKUP_DIR=$(head -1 "$FLAG_FILE")
    echo -e "${GREEN}[✓] Backup encontrado: $BACKUP_DIR${NC}"
  fi

  # Verificar que SELinux esta activo
  current_mode=$(getenforce 2>/dev/null)
  if [ "$current_mode" != "Permissive" ]; then
    echo -e "${RED}[!] SELinux no esta en modo permisivo. Modo actual: $current_mode${NC}"
    exit 1
  fi

  echo -e "${GREEN}[✓] SELinux esta activo en modo permisivo${NC}"

  # Configurar puertos por defecto
  echo -e "\n${BLUE}[*] Configurando puertos por defecto...${NC}"
  semanage port -a -t http_port_t -p tcp 80 2>/dev/null && echo -e "${GREEN}[✓] Puerto 80 configurado como http_port_t${NC}"
  semanage port -a -t http_port_t -p tcp 443 2>/dev/null && echo -e "${GREEN}[✓] Puerto 443 configurado como http_port_t${NC}"
  semanage port -a -t ssh_port_t -p tcp 22 2>/dev/null && echo -e "${GREEN}[✓] Puerto 22 configurado como ssh_port_t${NC}"
  semanage port -a -t mysqld_port_t -p tcp 3306 2>/dev/null && echo -e "${GREEN}[✓] Puerto 3306 configurado como mysqld_port_t${NC}"

  # Verificar servicios activos y asignar contextos
  echo -e "\n${BLUE}[*] Verificando servicios activos...${NC}"

  if systemctl is-active --quiet httpd 2>/dev/null; then
    echo -e "${GREEN}[✓] Apache detectado - configurando contextos${NC}"
    semanage fcontext -a -t httpd_sys_content_t "/var/www(/.*)?" 2>/dev/null
    restorecon -R /var/www 2>/dev/null
  fi

  if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null; then
    echo -e "${GREEN}[✓] MySQL/MariaDB detectado - configurando contextos${NC}"
    semanage fcontext -a -t mysqld_db_t "/var/lib/mysql(/.*)?" 2>/dev/null
    restorecon -R /var/lib/mysql 2>/dev/null
  fi

  if systemctl is-active --quiet postgresql 2>/dev/null; then
    echo -e "${GREEN}[✓] PostgreSQL detectado - configurando contextos${NC}"
    semanage fcontext -a -t postgresql_db_t "/var/lib/pgsql(/.*)?" 2>/dev/null
    restorecon -R /var/lib/pgsql 2>/dev/null
  fi

  # Restaurar contextos generales
  echo -e "\n${BLUE}[*] Restaurando contextos SELinux...${NC}"
  restorecon -R /etc 2>/dev/null
  restorecon -R /var 2>/dev/null
  restorecon -R /usr 2>/dev/null
  restorecon -R /home 2>/dev/null
  echo -e "${GREEN}[✓] Contextos restaurados${NC}"

  # Eliminar archivo de marca
  rm -f "$FLAG_FILE"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  CONFIGURACION COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}RESUMEN:${NC}"
  echo -e "  SELinux esta en modo PERMISIVO"
  echo -e "  No se bloqueara ningun servicio"
  echo -e "  Los contextos han sido configurados"
  echo -e "\n${YELLOW}COMANDOS UTILES:${NC}"
  echo -e "  Ver estado: getenforce"
  echo -e "  Ver denegaciones: ausearch -ts recent -m avc"
  echo -e "  Ver en tiempo real: tail -f /var/log/audit/audit.log | grep denied"
  echo -e "\n${YELLOW}PARA GENERAR POLITICAS:${NC}"
  echo -e "  ausearch -ts recent -m avc | audit2allow -M local_policy"
  echo -e "  semodule -i local_policy.pp"
  echo -e "\n${YELLOW}BACKUP:${NC}"
  echo -e "  Configuracion guardada en: $BACKUP_DIR"
  echo -e "${GREEN}============================================${NC}"
}
# ==============================================
# DESINSTALAR SETROUBLESHOOT (CIS 1.6.1.7)
# ==============================================
remove_setroubleshoot() {
  echo -e "\n${BLUE}[*] CIS 1.6.1.7 - Verificando SETroubleshoot...${NC}"

  if rpm -q setroubleshoot &>/dev/null; then
    local version=$(rpm -q setroubleshoot)
    echo -e "${RED}[!] SETroubleshoot esta instalado: $version${NC}"
    echo -e "${YELLOW}    SETroubleshoot es un servicio innecesario en servidores${NC}"
    echo -e "${YELLOW}    Puede filtrar informacion de SELinux y consumir recursos${NC}"

    if [ "$AUTO_FIX" = true ]; then
      echo -e "${YELLOW}[*] Eliminando setroubleshoot...${NC}"
      yum remove setroubleshoot -y 2>/dev/null || dnf remove setroubleshoot -y 2>/dev/null

      # Verificar eliminacion
      if ! rpm -q setroubleshoot &>/dev/null; then
        echo -e "${GREEN}[✓] setroubleshoot eliminado correctamente${NC}"
        FIXED=$((FIXED + 1))
      else
        echo -e "${RED}[!] No se pudo eliminar setroubleshoot${NC}"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      echo -e "${YELLOW}    Recomendacion: yum remove setroubleshoot -y${NC}"
      echo -e "${YELLOW}    O: dnf remove setroubleshoot -y${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    echo -e "${GREEN}[✓] SETroubleshoot no esta instalado${NC}"
  fi
}

# ==============================================
# FUNCION PRINCIPAL
# ==============================================
main() {
  # Verificar si estamos en segunda fase (despues de reinicio)
  if check_phase && [ -f "$FLAG_FILE" ]; then
    # Segunda fase - ya se reinicio
    phase2_configure
    exit 0
  fi

  # Primera fase - mostrar advertencia
  show_liability_notice

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  SELinux Setup - Modo Permisivo Seguro${NC}"
  echo -e "${GREEN}============================================${NC}"

  # Verificar estado de SELinux
  check_selinux_status
  NEEDS_REBOOT=$?

  if [ $NEEDS_REBOOT -eq 1 ]; then
    echo -e "\n${YELLOW}============================================${NC}"
    echo -e "${YELLOW}  SE REQUIERE CONFIGURAR SELINUX Y REINICIAR${NC}"
    echo -e "${YELLOW}============================================${NC}"

    enable_selinux_permissive

    echo -e "\n${YELLOW}============================================${NC}"
    echo -e "${YELLOW}  SE REQUIERE REINICIO${NC}"
    echo -e "${YELLOW}============================================${NC}"
    echo -e "${YELLOW}Despues del reinicio, ejecute el mismo script nuevamente:${NC}"
    echo -e "  ./selinux-secure-setup.sh"
    echo -e ""
    echo -e "El script continuara automaticamente con la configuracion de contextos."
    echo -e "${YELLOW}============================================${NC}"

    read -p "¿Reiniciar ahora? (s/N): " reboot_confirm
    if [[ "$reboot_confirm" =~ ^[Ss]$ ]]; then
      echo -e "${YELLOW}[*] Reiniciando sistema...${NC}"
      sleep 3
      reboot
    else
      echo -e "${YELLOW}[!] Reinicio cancelado. Ejecute manualmente despues.${NC}"
      echo -e "${YELLOW}[!] Al reiniciar, ejecute: ./selinux-secure-setup.sh${NC}"
    fi
  else
    # SELinux ya esta activo, remover setroubleshoot
    remove_setroubleshoot
    # SELinux ya esta activo, ir directo a segunda fase
    phase2_configure
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
