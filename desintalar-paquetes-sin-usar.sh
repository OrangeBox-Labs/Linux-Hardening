# ==============================================
# FUNCION PARA SIMULAR ELIMINACION Y CAPTURAR DEPENDENCIAS
# ==============================================
simulate_and_capture_deps() {
  local package="$1"
  local tx_file=""
  local deps=""

  # Ejecutar remove con --assumeno para generar archivo de transaccion
  if command -v dnf &>/dev/null; then
    dnf remove "$package" -y --assumeno 2>&1 >/dev/null
    tx_file=$(ls -t /tmp/dnf_save_tx.*.dnftx 2>/dev/null | head -1)
  elif command -v yum &>/dev/null; then
    yum remove "$package" -y --assumeno 2>&1 >/dev/null
    tx_file=$(ls -t /tmp/yum_save_tx.*.yumtx 2>/dev/null | head -1)
  fi

  # Parsear el archivo de transaccion
  if [ -f "$tx_file" ]; then
    # Intentar diferentes formatos de parseo
    # Formato 1: mbr: nombre,version,release,arch,reponame,size
    deps=$(grep "^mbr:" "$tx_file" | cut -d',' -f1 | sed 's/^mbr: //' | sort -u)

    # Si no se encontraron dependencias, intentar otro formato
    if [ -z "$deps" ]; then
      # Formato 2: (linea con "Removing:" o "Erasing:")
      deps=$(grep -E "^(Removing|Erasing):" "$tx_file" | awk '{print $2}' | sort -u)
    fi

    # Si aun no hay dependencias, intentar con el comando directamente
    if [ -z "$deps" ]; then
      if command -v dnf &>/dev/null; then
        deps=$(dnf remove "$package" -y --assumeno 2>&1 | grep -E "^\s+removing" | awk '{print $2}' | sort -u)
      elif command -v yum &>/dev/null; then
        deps=$(yum remove "$package" -y --assumeno 2>&1 | grep -E "^\s+removing" | awk '{print $2}' | sort -u)
      fi
    fi

    rm -f "$tx_file"
  else
    # Si no se genero archivo, usar el comando directamente
    if command -v dnf &>/dev/null; then
      deps=$(dnf remove "$package" -y --assumeno 2>&1 | grep -E "^\s+removing" | awk '{print $2}' | sort -u)
    elif command -v yum &>/dev/null; then
      deps=$(yum remove "$package" -y --assumeno 2>&1 | grep -E "^\s+removing" | awk '{print $2}' | sort -u)
    fi
  fi

  echo "$deps"
}
