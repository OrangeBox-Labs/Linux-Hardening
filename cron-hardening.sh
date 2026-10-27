#!/bin/bash

OB_COMPAT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -r "$OB_COMPAT_DIR/lib/service-compat.sh" ]; then
  # shellcheck source=lib/service-compat.sh
  . "$OB_COMPAT_DIR/lib/service-compat.sh"
else
  echo "[ERROR] Falta lib/service-compat.sh; actualice el repositorio completo." >&2
  exit 1
fi

# ==============================================
# Script: cron-hardening.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Hardening de cron y at segun CIS Benchmark
#              CIS 5.1.1 - 5.1.9
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIXED=0
WARNINGS=0
AUTO_FIX=false

BACKUP_DIR="/root/cron-backup-$(date +%Y%m%d-%H%M%S)-${BASHPID}"

# ==============================================
# FUNCION PARA MOSTRAR AYUDA
# ==============================================
confirm_cron_change() {
  if [ "${ORANGEBOX_ASSUME_YES:-0}" = "1" ]; then printf "[AUTO-YES] %s\n" "${1:-cambio}"; return 0; fi
  local control="$1" effect="$2" answer=""
  echo -e "\n$YELLOW[CONFIRMACIÓN REQUERIDA]$NC $control"
  echo "Qué hace/riesgo: $effect"
  if [ "$AUTO_FIX" != true ]; then return 1; fi
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo -e "$YELLOW[WARN] No hay terminal interactiva; se omite el cambio por seguridad.$NC"
    return 1
  fi
  printf '¿Aplicar este cambio? [s/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "$answer" in
    s|S|si|SI|Si|sí|Sí|SÍ) return 0 ;;
    *) echo -e "$BLUE[INFO] Cambio rechazado; se conserva el estado actual.$NC"; return 1 ;;
  esac
}

show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0            - Modo verificación (solo muestra lo que hay que corregir)"
  echo "  $0 --fix      - Modo automático (aplica las correcciones)"
  echo "  $0 -f         - Modo automático (versión corta)"
  echo ""
  echo -e "${GREEN}EJEMPLO:${NC}"
  echo "  # Ver qué cambios se aplicarían"
  echo "  ./cron-hardening.sh"
  echo ""
  echo "  # Aplicar los cambios"
  echo "  ./cron-hardening.sh --fix"
  echo ""
}

make_backup() {
  if ! mkdir -p "$BACKUP_DIR" || ! chmod 700 "$BACKUP_DIR"; then
    echo -e "${RED}[ERROR] No se pudo preparar el backup $BACKUP_DIR; no se modifica cron/at.${NC}" >&2
    return 1
  fi
  local mode file backup source_hash backup_hash
  mode="$(stat -c '%a' "$BACKUP_DIR" 2>/dev/null || true)"
  if [ "$mode" != 700 ]; then
    echo -e "${RED}[ERROR] No se pudo verificar el modo 0700 del backup de cron/at.${NC}" >&2
    return 1
  fi
  for file in /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d /etc/cron.allow /etc/cron.deny /etc/at.allow /etc/at.deny; do
    [ -e "$file" ] || [ -L "$file" ] || continue
    if [ -L "$file" ]; then
      echo -e "${RED}[ERROR] $file es un enlace simbólico; no se modifica cron/at sin un backup seguro.${NC}" >&2
      return 1
    fi
    if ! cp -a "$file" "$BACKUP_DIR/"; then
      echo -e "${RED}[ERROR] No se pudo respaldar $file; no se modifica cron/at.${NC}" >&2
      return 1
    fi
    backup="$BACKUP_DIR/$(basename "$file")"
    if [ -f "$file" ]; then
      command -v sha256sum >/dev/null 2>&1 || { echo -e "${RED}[ERROR] sha256sum no está disponible para verificar $file; no se modifica cron/at.${NC}" >&2; return 1; }
      source_hash="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
      backup_hash="$(sha256sum "$backup" 2>/dev/null | awk '{print $1}')"
      if [ -z "$source_hash" ] || [ -z "$backup_hash" ] || [ "$source_hash" != "$backup_hash" ]; then
        echo -e "${RED}[ERROR] El backup de $file no coincide con el original; no se modifica cron/at.${NC}" >&2
        return 1
      fi
    elif [ -d "$file" ] && [ ! -d "$backup" ]; then
      echo -e "${RED}[ERROR] No se verificó el directorio de backup de $file; no se modifica cron/at.${NC}" >&2
      return 1
    fi
    if [ -L "$file" ] && [ "$(readlink "$file" 2>/dev/null || true)" != "$(readlink "$backup" 2>/dev/null || true)" ]; then
      echo -e "${RED}[ERROR] El backup del enlace $file no coincide; no se modifica cron/at.${NC}" >&2
      return 1
    fi
  done
  echo -e "${GREEN}[✓] Backup de cron/at verificado en: $BACKUP_DIR${NC}"
}

# ==============================================
# FUNCIONES DE VERIFICACION (solo chequean, no modifican)
# ==============================================

check_cron_enabled() {
  echo -e "\n${BLUE}[*] CIS 5.1.1 - Verificando servicio cron...${NC}"
  local rc

  if ob_service_is_enabled crond; then
    echo -e "${GREEN}[✓] crond habilitado${NC}"
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then
      echo -e "${YELLOW}[!] No se pudo determinar si crond está habilitado${NC}"
    else
      echo -e "${RED}[!] crond no habilitado${NC}"
    fi
    WARNINGS=$((WARNINGS + 1))
  fi

  if ob_service_is_active crond; then
    echo -e "${GREEN}[✓] crond corriendo${NC}"
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then
      echo -e "${YELLOW}[!] No se pudo determinar si crond está corriendo${NC}"
    else
      echo -e "${RED}[!] crond no corriendo${NC}"
    fi
    WARNINGS=$((WARNINGS + 1))
  fi
}
check_permissions() {
  local file="$1"
  local perms="$2"
  local owner="$3"
  local group="$4"
  local description="$5"

  if [ ! -e "$file" ]; then
    echo -e "${YELLOW}[!] $file no existe${NC}"
    return 1
  fi

  local current_perms=$(stat -c "%a" "$file" 2>/dev/null)
  local current_owner=$(stat -c "%U" "$file" 2>/dev/null)
  local current_group=$(stat -c "%G" "$file" 2>/dev/null)

  local ok=true

  if [ "$current_perms" != "$perms" ]; then
    echo -e "${RED}[!] $description permisos: $current_perms (debe ser $perms)${NC}"
    ok=false
  else
    echo -e "${GREEN}[✓] $description permisos correctos: $current_perms${NC}"
  fi

  if [ "$current_owner" != "$owner" ]; then
    echo -e "${RED}[!] $description propietario: $current_owner (debe ser $owner)${NC}"
    ok=false
  else
    echo -e "${GREEN}[✓] $description propietario correcto: $current_owner${NC}"
  fi

  if [ "$current_group" != "$group" ]; then
    echo -e "${RED}[!] $description grupo: $current_group (debe ser $group)${NC}"
    ok=false
  else
    echo -e "${GREEN}[✓] $description grupo correcto: $current_group${NC}"
  fi

  if [ "$ok" = false ]; then
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_user_restriction() {
  local allow_file="$1"
  local deny_file="$2"
  local service="$3"

  echo -e "\n${BLUE}[*] Verificando restriccion de usuarios para $service...${NC}"

  if [ -f "$deny_file" ]; then
    echo -e "${RED}[!] $deny_file existe - debe eliminarse${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] $deny_file no existe${NC}"
  fi

  if [ ! -f "$allow_file" ]; then
    echo -e "${RED}[!] $allow_file no existe - debe crearse${NC}"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "${GREEN}[✓] $allow_file existe${NC}"
    if ! grep -q "^root$" "$allow_file"; then
      echo -e "${RED}[!] root no esta en $allow_file${NC}"
      WARNINGS=$((WARNINGS + 1))
    fi
    # CIS 5.1.8 y 5.1.9 piden permisos 640
    check_permissions "$allow_file" "640" "root" "root" "Archivo $allow_file"
  fi
}

# ==============================================
# FUNCION ADICIONAL: VERIFICAR PERMISOS DE LOGS DE CRON
# ==============================================
check_cron_log_permissions() {
  echo -e "\n${BLUE}[*] Verificando permisos de logs de cron...${NC}"

  local cron_log="/var/log/cron"

  if [ ! -f "$cron_log" ]; then
    echo -e "${YELLOW}[!] $cron_log no existe${NC}"
    return 0
  fi

  local current_perms=$(stat -c "%a" "$cron_log" 2>/dev/null)
  local current_owner=$(stat -c "%U" "$cron_log" 2>/dev/null)
  local current_group=$(stat -c "%G" "$cron_log" 2>/dev/null)

  if { [ "$current_perms" = "640" ] || [ "$current_perms" = "600" ]; } && [ "$current_owner" = "root" ] && [ "$current_group" = "root" ]; then
    echo -e "${GREEN}[✓] $cron_log permisos correctos: $current_perms root:root${NC}"
  else
    echo -e "${RED}[!] $cron_log permisos: $current_perms $current_owner:$current_group (debe ser 640 root:root)${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ==============================================
# FUNCION ADICIONAL: VERIFICAR TAREAS CRON NO AUTORIZADAS
# ==============================================
check_unauthorized_crons() {
  echo -e "\n${BLUE}[*] Verificando tareas cron del sistema...${NC}"
  echo -e "${YELLOW}    Esta es una verificacion informativa - no se corregira automaticamente${NC}"

  local system_crons=(
    "/etc/crontab"
    "/etc/cron.d"
    "/etc/cron.hourly"
    "/etc/cron.daily"
    "/etc/cron.weekly"
    "/etc/cron.monthly"
  )

  for cron_path in "${system_crons[@]}"; do
    if [ -d "$cron_path" ]; then
      local files=$(find "$cron_path" -type f 2>/dev/null | wc -l)
      if [ $files -gt 0 ]; then
        echo -e "  ${GREEN}→${NC} $cron_path: $files archivos"
      fi
    elif [ -f "$cron_path" ]; then
      echo -e "  ${GREEN}→${NC} $cron_path: existe"
    fi
  done

  echo -e "\n${YELLOW}    Recomendacion: Revise manualmente los archivos de cron en busca de tareas no autorizadas${NC}"
}

# ==============================================
# FUNCIONES DE APLICACION (modifican el sistema)
# ==============================================

apply_cron_enabled() {
  local rc effect
  ob_service_is_enabled crond
  rc=$?
  case "$rc" in
    0) echo -e "$GREEN[OK] crond ya está habilitado al arranque$NC" ;;
    1)
      effect="Habilita crond para que ejecute tareas programadas después de cada arranque. Comprueba que el servidor deba ofrecer cron; habilitarlo puede hacer que tareas existentes vuelvan a ejecutarse."
      if confirm_cron_change "habilitar crond al arranque" "$effect"; then
        if ob_service_enable crond; then echo -e "$GREEN[✓] crond habilitado$NC"; FIXED=$((FIXED + 1)); else echo -e "$RED[!] No se pudo habilitar crond$NC"; WARNINGS=$((WARNINGS + 1)); fi
      else WARNINGS=$((WARNINGS + 1)); fi
      ;;
    *) echo -e "$YELLOW[WARN] Estado de inicio de crond no verificable; no se modifica.$NC"; WARNINGS=$((WARNINGS + 1)) ;;
  esac

  ob_service_is_active crond
  rc=$?
  case "$rc" in
    0) echo -e "$GREEN[OK] crond ya está activo$NC" ;;
    1)
      effect="Inicia el demonio que ejecuta tareas cron pendientes. Esto puede disparar tareas existentes y generar carga o efectos de aplicaciones; verifica los crontabs antes de activarlo."
      if confirm_cron_change "iniciar crond ahora" "$effect"; then
        if ob_service_start crond; then echo -e "$GREEN[✓] crond iniciado$NC"; FIXED=$((FIXED + 1)); else echo -e "$RED[!] No se pudo iniciar crond$NC"; WARNINGS=$((WARNINGS + 1)); fi
      else WARNINGS=$((WARNINGS + 1)); fi
      ;;
    *) echo -e "$YELLOW[WARN] Estado de ejecución de crond no verificable; no se modifica.$NC"; WARNINGS=$((WARNINGS + 1)) ;;
  esac
}

apply_permissions() {
  local file="$1" perms="$2" owner="$3" group="$4" description="$5"
  local current_perms="" current_owner="" current_group="" effect="" failed=false
  [ -e "$file" ] || return 1
  current_perms="$(stat -c "%a" "$file" 2>/dev/null || true)"
  current_owner="$(stat -c "%U" "$file" 2>/dev/null || true)"
  current_group="$(stat -c "%G" "$file" 2>/dev/null || true)"

  if [ "$current_perms" = "$perms" ] && [ "$current_owner" = "$owner" ] && [ "$current_group" = "$group" ]; then
    echo -e "$GREEN[OK] $description: $current_perms $current_owner:$current_group$NC"
    return 0
  fi

  effect="Cambiaría $file de $current_perms $current_owner:$current_group a $perms $owner:$group. Protege configuraciones y tareas programadas; permisos más restrictivos pueden impedir que usuarios o procesos no-root lean/accedan a ese fichero o directorio."
  if ! confirm_cron_change "ajustar permisos/propiedad de $file" "$effect"; then
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if [ "$current_perms" != "$perms" ] && ! chmod "$perms" "$file"; then failed=true; fi
  if { [ "$current_owner" != "$owner" ] || [ "$current_group" != "$group" ]; } && ! chown "$owner:$group" "$file"; then failed=true; fi
  if [ "$failed" = false ] &&
     [ "$(stat -c "%a" "$file" 2>/dev/null)" = "$perms" ] &&
     [ "$(stat -c "%U:%G" "$file" 2>/dev/null)" = "$owner:$group" ]; then
    echo -e "$GREEN[✓] $description corregido: $perms $owner:$group$NC"
    FIXED=$((FIXED + 1))
  else
    echo -e "$RED[!] No se pudo validar la corrección de $file$NC"
    WARNINGS=$((WARNINGS + 1))
  fi
}

apply_user_restriction() {
  local allow_file="$1" deny_file="$2" service="$3" effect="" allow_ready=false
  echo -e "\n${BLUE}[*] Restricción de usuarios para $service${NC}"

  # Establish the allow-list first. Never remove a deny-list before the more
  # restrictive allow-list has been created and verified.
  if [ ! -f "$allow_file" ]; then
    effect="Crea $allow_file con solo root. En sistemas que respetan allow, limita quién puede crear tareas cron/at. Riesgo: las cuentas de servicio, usuarios de hosting o automatizaciones que no sean de root pueden perder la capacidad de programar tareas."
    if confirm_cron_change "crear $allow_file con solo root" "$effect"; then
      if printf '%s\n' root > "$allow_file" &&
         chmod 640 "$allow_file" &&
         chown root:root "$allow_file" &&
         grep -qx 'root' "$allow_file"; then
        echo -e "$GREEN[✓] $allow_file creado con root (0640 root:root)$NC"
        FIXED=$((FIXED + 1))
        allow_ready=true
      else
        rm -f "$allow_file"
        echo -e "$RED[!] No se pudo crear/verificar $allow_file; no se tocará $deny_file$NC"
        WARNINGS=$((WARNINGS + 1))
        return 1
      fi
    else
      WARNINGS=$((WARNINGS + 1))
      echo "[INFO] Se conserva $deny_file; no se eliminará mientras no haya un allow-list verificado."
      return 0
    fi
  else
    if grep -qx 'root' "$allow_file"; then
      allow_ready=true
    else
      effect="Añade root a la lista permitida existente sin quitar usuarios ya autorizados. Riesgo: cambia qué cuentas pueden administrar tareas, pero conserva las entradas existentes."
      if confirm_cron_change "agregar root a $allow_file" "$effect"; then
        if printf '%s\n' root >> "$allow_file" && grep -qx 'root' "$allow_file"; then
          echo -e "$GREEN[✓] root agregado a $allow_file$NC"
          FIXED=$((FIXED + 1))
          allow_ready=true
        else
          echo -e "$RED[!] No se pudo validar root en $allow_file$NC"
          WARNINGS=$((WARNINGS + 1))
        fi
      else
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
    apply_permissions "$allow_file" "640" "root" "root" "Archivo $allow_file"
  fi

  if [ "$allow_ready" != true ]; then
    echo -e "$YELLOW[WARN] $allow_file no permite confirmar que root está autorizado; se conserva $deny_file sin cambios.$NC"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi

  if [ -f "$deny_file" ]; then
    effect="Elimina $deny_file después de verificar $allow_file. La allow-list pasa a ser la política explícita. Riesgo: confirma que las cuentas/servicios que deben programar tareas estén incluidas en $allow_file antes de aceptar."
    if confirm_cron_change "eliminar $deny_file (allow-list ya verificado)" "$effect"; then
      if rm -f "$deny_file"; then
        echo -e "$GREEN[✓] $deny_file eliminado después de verificar $allow_file$NC"
        FIXED=$((FIXED + 1))
      else
        echo -e "$RED[!] No se pudo eliminar $deny_file$NC"
        WARNINGS=$((WARNINGS + 1))
      fi
    else
      WARNINGS=$((WARNINGS + 1))
      echo "[INFO] Se conserva $deny_file; la allow-list verificada permanece activa."
    fi
  fi
}

apply_cron_log_permissions() {
  local cron_log="/var/log/cron" perms owner_group effect
  [ -f "$cron_log" ] || return 0
  perms="$(stat -c "%a" "$cron_log" 2>/dev/null || true)"
  owner_group="$(stat -c "%U:%G" "$cron_log" 2>/dev/null || true)"
  if { [ "$perms" = "640" ] || [ "$perms" = "600" ]; } && [ "$owner_group" = "root:root" ]; then
    echo -e "$GREEN[OK] $cron_log permisos $perms $owner_group$NC"
    return 0
  fi
  effect="Restringe la lectura del log de cron a root y al grupo propietario. Puede afectar agentes de monitorización o recolectores de logs que dependan de permisos/grupos actuales."
  if confirm_cron_change "ajustar $cron_log a 0640 root:root" "$effect"; then
    if chmod 640 "$cron_log" && chown root:root "$cron_log" &&
       [ "$(stat -c "%a" "$cron_log" 2>/dev/null)" = "640" ] &&
       [ "$(stat -c "%U:%G" "$cron_log" 2>/dev/null)" = "root:root" ]; then
      echo -e "$GREEN[✓] $cron_log protegido$NC"
      FIXED=$((FIXED + 1))
    else
      echo -e "$RED[!] No se pudo validar el hardening de $cron_log$NC"
      WARNINGS=$((WARNINGS + 1))
    fi
  else WARNINGS=$((WARNINGS + 1)); fi
}

main() {

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Cron Hardening - CIS 5.1.x${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Modo ayuda
  if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
  fi

  # Modo verificación (sin --fix)
  if [ "$1" != "--fix" ] && [ "$1" != "-f" ]; then
    echo -e "${YELLOW}🔍 MODO VERIFICACIÓN - No se aplicarán cambios${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    show_usage
    echo -e "\n${YELLOW}Estado actual del sistema:${NC}\n"

    check_cron_enabled
    check_cron_permissions
    check_cron_restriction
    check_at_restriction
    check_cron_log_permissions
    check_unauthorized_crons

    echo -e "\n${GREEN}============================================${NC}"
    echo -e "${GREEN}  VERIFICACIÓN COMPLETADA${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "${YELLOW}Advertencias encontradas: $WARNINGS${NC}"
    echo -e "\n${BLUE}Para aplicar las correcciones, ejecute: $0 --fix${NC}"
    exit 0
  fi

  # Modo automático (--fix o -f)
  if [ "$1" = "--fix" ] || [ "$1" = "-f" ]; then
    echo -e "${YELLOW}🔧 MODO AUTOMÁTICO - Aplicando correcciones...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Confirm the rollback copy before touching cron/at configuration.
    if ! make_backup; then
      echo -e "${RED}[ERROR] Backup de cron/at falló; se aborta antes de aplicar cambios.${NC}" >&2
      exit 1
    fi

    # Aplicar cambios
    apply_cron_enabled
    apply_cron_permissions
    apply_user_restriction "/etc/cron.allow" "/etc/cron.deny" "cron"
    apply_user_restriction "/etc/at.allow" "/etc/at.deny" "at"
    apply_cron_log_permissions

    # Permisos y allow/deny no requieren reiniciar crond; evitar interrupciones innecesarias.
    echo -e "\n$BLUE[INFO] No se reinicia crond: los cambios de permisos y allow/deny no requieren recarga del servicio.$NC"

    # Resumen
    echo -e "\n${GREEN}============================================${NC}"
    echo -e "${GREEN}  CRON HARDENING COMPLETADO${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo -e "${YELLOW}Correcciones aplicadas: $FIXED${NC}"
    echo -e "${YELLOW}Backup disponible en: $BACKUP_DIR${NC}"

    echo -e "\n${GREEN}============================================${NC}"
    echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
    echo -e "${GREEN}  📺 https://www.youtube.com/@OrangeBoxLinux${NC}"
    echo -e "${GREEN}============================================${NC}"
    exit 0
  fi
}

# ==============================================
# DECLARACION DE FUNCIONES ADICIONALES
# ==============================================

check_cron_permissions() {
  echo -e "\n${BLUE}[*] Verificando permisos de archivos cron...${NC}"
  check_permissions "/etc/crontab" "600" "root" "root" "/etc/crontab"
  check_permissions "/etc/cron.hourly" "700" "root" "root" "/etc/cron.hourly"
  check_permissions "/etc/cron.daily" "700" "root" "root" "/etc/cron.daily"
  check_permissions "/etc/cron.weekly" "700" "root" "root" "/etc/cron.weekly"
  check_permissions "/etc/cron.monthly" "700" "root" "root" "/etc/cron.monthly"
  check_permissions "/etc/cron.d" "700" "root" "root" "/etc/cron.d"
}

check_cron_restriction() {
  check_user_restriction "/etc/cron.allow" "/etc/cron.deny" "cron"
}

check_at_restriction() {
  check_user_restriction "/etc/at.allow" "/etc/at.deny" "at"
}

apply_cron_permissions() {
  echo -e "\n${BLUE}[*] Aplicando permisos de archivos cron...${NC}"
  apply_permissions "/etc/crontab" "600" "root" "root" "/etc/crontab"
  apply_permissions "/etc/cron.hourly" "700" "root" "root" "/etc/cron.hourly"
  apply_permissions "/etc/cron.daily" "700" "root" "root" "/etc/cron.daily"
  apply_permissions "/etc/cron.weekly" "700" "root" "root" "/etc/cron.weekly"
  apply_permissions "/etc/cron.monthly" "700" "root" "root" "/etc/cron.monthly"
  apply_permissions "/etc/cron.d" "700" "root" "root" "/etc/cron.d"
}

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Este script debe ejecutarse como root${NC}"
  exit 1
fi

main "$@"
