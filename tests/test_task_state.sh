#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
STATE="$ROOT_DIR/.task-status.md"
JOURNAL="$ROOT_DIR/.task-journal.md"
PROTOCOL="$ROOT_DIR/.github/TASK-RESUMPTION-PROTOCOL.md"

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

for file in "$STATE" "$JOURNAL" "$PROTOCOL"; do
  [ -s "$file" ] || fail "falta archivo de continuidad vacío/ausente: ${file#"$ROOT_DIR"/}"
done

grep -Fq '# Estado de tarea' "$STATE" || fail "el estado no tiene encabezado reconocido"
grep -Eq '^- \*\*Estado:\*\* .*(IDLE|IN_PROGRESS|BLOCKED|PAUSED|READY_FOR_REVIEW)' "$STATE" ||
  fail "el estado debe declarar un lifecycle state permitido"
grep -Eq '^- \*\*ID de tarea:\*\* .*OB-LH-[0-9]{8}-[0-9]{3}' "$STATE" ||
  fail "falta un ID de tarea estable con formato OB-LH-YYYYMMDD-NNN"
grep -Fq 'Siguiente acción exacta' "$STATE" || fail "el estado debe identificar la siguiente acción exacta"
grep -Fq '## Decisiones tomadas' "$STATE" || fail "el estado debe conservar decisiones relevantes"
grep -Fq '## Último checkpoint' "$STATE" || fail "el estado debe conservar un checkpoint"
grep -Fq '## Reglas de integridad' "$JOURNAL" || fail "el journal no declara sus reglas de integridad"
grep -Fq '## Entradas' "$JOURNAL" || fail "el journal no tiene sección de entradas"
grep -Eq '^### [0-9]{4}-[0-9]{2}-[0-9]{2} — OB-LH-[0-9]{8}-[0-9]{3} — ' "$JOURNAL" ||
  fail "el journal no contiene entradas fechadas con ID de tarea"
grep -Fq '## Cómo reanudar tras interrupción o límite del chat' "$PROTOCOL" ||
  fail "el protocolo no define recuperación después de una interrupción"
grep -Fq '## Regla de actualización tipo journal' "$PROTOCOL" ||
  fail "el protocolo no define cómo actualizar y retirar pendientes"

state_value="$(sed -n 's/^- \*\*Estado:\*\* //p' "$STATE" | sed 's/^[^A-Z_]*//; s/[^A-Z_].*$//')"
pending_block="$(sed -n '/^## Pendientes de la tarea activa$/,/^## Decisiones tomadas$/p' "$STATE")"
case "$state_value" in
  IN_PROGRESS|BLOCKED|PAUSED|READY_FOR_REVIEW)
    printf '%s\n' "$pending_block" | grep -Fq -- '- [ ] ' ||
      fail "hay una tarea activa pero no quedan pendientes explícitos"
    if printf '%s\n' "$pending_block" | grep -Fq -- '- [x] '; then
      fail "los pasos completados no deben permanecer en la lista activa; moverlos al journal"
    fi
    ;;
  IDLE)
    # Aceptar ambas formulaciones explícitas de inactividad usadas por el estado.
    grep -Eq 'No hay tarea activa|Tarea activa:[[:space:]]*Ninguna([.]|$)' "$STATE" ||
      fail "IDLE debe declarar explícitamente que no hay tarea activa"
    if printf '%s\n' "$pending_block" | grep -Fq -- '- [ ] '; then
      fail "IDLE no puede conservar pasos pendientes"
    fi
    ;;
esac

grep -Fq 'append-only' "$PROTOCOL" || fail "el protocolo debe preservar el journal como historial acumulativo"
grep -Fq '.task-status.md' "$PROTOCOL" || fail "el protocolo debe indicar el archivo de estado fuente de verdad"
pass "estado, journal y protocolo presentes y consistentes"
