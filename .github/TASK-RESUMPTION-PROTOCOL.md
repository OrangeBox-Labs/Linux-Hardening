# Protocolo de continuidad de tareas — OrangeBox Linux-Hardening

Este protocolo es la instrucción operativa duradera para trabajar en este repositorio cuando una conversación, conexión o sesión pueda terminar inesperadamente. Se debe leer **antes de empezar o reanudar una tarea de modificación del repositorio**.

## Archivos fuente de verdad

- **`.task-status.md` — estado mutable de la tarea activa.** Debe permitir que otra sesión identifique de inmediato el objetivo, los pendientes reales, las decisiones, los límites, la evidencia y la siguiente acción exacta.
- **`.task-journal.md` — historial append-only.** Se agregan eventos al final y se preservan todas las entradas anteriores. No reemplaza el estado ni Git.
- **`WORKPLAN.md` — plan de trabajo duradero del proyecto.** Contiene líneas de trabajo generales, no el detalle operativo de cada tarea activa.
- **`PROJECT-STATUS.md` / documentación temática — estado de largo plazo.** Actualizar cuando la tarea afecte el estado global, cobertura, arquitectura o riesgos del proyecto.
- **Git, PRs y CI — evidencia verificable.** La descripción en un archivo nunca sustituye comprobar el branch/commit real, el diff y los resultados de las pruebas.

No guardar credenciales, tokens, claves privadas, datos de clientes, datos personales sensibles ni logs sin redactar en estos archivos. Preferir un resumen y una referencia a la ubicación segura de la evidencia.

## Cuándo iniciar un registro

Al recibir una petición que implique trabajo en el repositorio, antes de hacer cambios sustantivos:

1. Leer `.task-status.md`, revisar las últimas entradas de `.task-journal.md` y comprobar la rama/HEAD/PR/CI en GitHub.
2. Si hay una tarea activa, decidir si la nueva petición es una continuación, una corrección urgente de esa tarea o una tarea independiente. No sobrescribir silenciosamente una tarea activa: registrar la relación, pausar la anterior si es necesario o crear una tarea en cola con prioridad explícita.
3. Si no hay tarea activa, asignar un ID único `OB-LH-YYYYMMDD-NNN`, donde la secuencia diaria se determina revisando el journal. Registrar la solicitud en términos concretos y los criterios de aceptación.
4. Crear/actualizar `.task-status.md` con alcance, exclusiones, archivos candidatos (si se conocen), riesgos, decisiones, pruebas, rama y punto de partida. Añadir un evento `task_started` al journal.
5. Abrir una rama de trabajo desde el `main` verificado para cambios que deban revisarse. No usar commits en `main` como atajo para una tarea de código; la actualización administrativa de estado, después de verificar el proceso del repositorio, también debe ser auditable.

Preguntas sencillas sin cambios de repositorio no requieren crear una tarea. Si la petición afecta el repositorio pero su alcance aún no se puede definir completamente, registrar lo que sí se sabe y mantener los puntos desconocidos como pendientes en lugar de inventar decisiones.

## Contrato de `.task-status.md`

Para una tarea activa debe contener, como mínimo:

- Estado: `IN_PROGRESS`, `BLOCKED`, `PAUSED` o `READY_FOR_REVIEW`.
- ID, objetivo, solicitud original resumida y criterios de aceptación.
- Repositorio, rama base, rama de trabajo, commit base, último HEAD verificado, PR si existe y estado del CI para el HEAD correspondiente.
- Contexto técnico mínimo que evita repetir exploración: rutas, funciones, decisiones, comportamiento observado, ambiente y limitaciones de herramientas.
- Alcance y exclusiones; riesgos/impacto y restricciones de seguridad.
- Decisiones/hipótesis, separadas entre verificadas y pendientes de confirmar.
- Lista **solo de trabajo pendiente**. No dejar pasos completados marcados como [x] en esa lista.
- Pruebas previstas, pruebas ejecutadas con resultado y evidencia; distinguir pruebas locales de CI.
- Bloqueadores y dependencias.
- **Siguiente acción exacta**, escrita como un verbo y un objeto verificable; evitar frases vagas como “seguir trabajando”.
- Último checkpoint: qué terminó, qué cambió, qué sigue y último commit/PR/CI conocido.

Para `IDLE`, declarar explícitamente que no hay tarea activa, conservar el ID/título de la última tarea cerrada y el checkpoint final, dejar la lista de pendientes vacía y explicar cómo iniciar la siguiente tarea. No borrar el estado por completo; el último checkpoint es útil para retomar contexto.

## Regla de actualización tipo journal

Actualizar el registro tras cada bloque coherente —por ejemplo, un hallazgo confirmado, una función corregida, una prueba añadida, un test fallido/corregido o un PR/CI completado— y antes de cambiar de contexto o de depender de más trabajo.

Cuando se completa un pendiente:

1. Verificar el resultado (diff/archivo/test/CI según aplique).
2. Agregar al final de `.task-journal.md` un evento con fecha, tarea, paso que terminó, resultado, archivos/commit/evidencia, decisiones nuevas y siguiente acción.
3. Retirar ese paso del bloque de pendientes de `.task-status.md`. No es necesario conservar una lista de casillas completadas dentro del estado: el journal es ese historial.
4. Reescribir el siguiente checkpoint y la siguiente acción exacta del estado.
5. Guardar las actualizaciones en Git para que el punto de recuperación sobreviva a la pérdida del chat.

Si la conexión puede cortarse entre los pasos 2 y 3, al reanudar compara los eventos finales del journal con los pendientes: si hay evidencia suficiente de finalización, reconcilia el estado; no dupliques ni inventes la entrada. Para eventos que cambian el resultado, no borrar la historia: añadir una entrada de corrección que referencie la anterior.

Registrar también fallos útiles: prueba, comando o job que falló (sin secretos), error concreto, causa confirmada o hipótesis, corrección aplicada y si se volvió a ejecutar. Nunca registrar una prueba como aprobada antes de obtener su resultado.

## Cómo reanudar tras interrupción o límite del chat

Al comenzar una nueva conversación o recuperar un trabajo:

1. Abrir `.task-status.md` desde el branch declarado; si el archivo indica un branch que ya no existe, buscar la tarea por ID en `.task-journal.md` y comprobar las ramas/PRs actuales.
2. Leer el final del journal, no solo el primer evento.
3. Consultar en GitHub el branch/HEAD actual, cambios del PR, checks/CI y si el PR ya fue integrado/cerrado. No confiar únicamente en SHA copiados en documentos.
4. Contrastar el último checkpoint con el estado real de Git; comprobar los archivos concretos antes de repetir trabajo.
5. Si el estado está `BLOCKED`, resolver o describir el bloqueador; si está `PAUSED`, confirmar si la petición actual retoma esa tarea; si está `READY_FOR_REVIEW`, comprobar el CI del HEAD exacto y revisar diff.
6. Continuar desde **Siguiente acción exacta**, completando un paso a la vez. No volver a hacer preguntas ya resueltas en el estado/journal; si faltan datos materiales, hacer una sola pregunta concreta o dejar la ambigüedad registrada mientras avanza el trabajo independiente.
7. No declarar finalización hasta que los criterios de aceptación estén verificados. Al cerrar, registrar `task_completed`, archivar la evidencia final en el journal y cambiar el archivo de estado a `IDLE`.

Orden para resolver discrepancias: evidencia real de GitHub/Git > eventos históricos del journal > estado/checkpoint > plan general > mensajes antiguos de la conversación. Si una fuente contradice otra, documentar la discrepancia y verificarla.

## GitHub y herramientas de edición

En flujos donde el repositorio se edita mediante la Contents API:

- Leer el archivo y su SHA de contenido justo antes de actualizarlo; escribir de manera secuencial archivos iguales.
- Registrar commit SHA después de cada bloque importante. No asumir que SHA de contenido y commit son lo mismo.
- La edición por Contents API sustituye el archivo completo: el journal debe incluir todo el historial anterior y una entrada nueva al final. Revisar que el contenido previo se conserve.
- Un test no ejecutado localmente se debe etiquetar como no ejecutado. Para GitHub Actions registrar run ID, HEAD SHA, estado/conclusión y jobs relevantes.
- No afirmar que un cambio está en `main` hasta verificar que el PR está merged y leer de nuevo el archivo de `main`.
- Mantener el branch/PR como pendiente mientras CI esté en cola o rojo. Solo integrar con revisión del diff y CI en verde para el HEAD exacto, salvo que el usuario indique otra política del repositorio.

## Cierre obligatorio

Al terminar cada tarea:

- criterios de aceptación comprobados;
- lista de pendientes vacía;
- journal con `task_completed` y la evidencia final;
- `.task-status.md` en `IDLE`, con última tarea, commit/PR/CI y resumen de límites restantes;
- actualizar `WORKPLAN.md` y `PROJECT-STATUS.md` solamente cuando el alcance o el estado global del proyecto lo amerite;
- respuesta final al usuario con enlaces al PR/commit y resumen honesto de lo hecho y lo pendiente.

Este mecanismo es manualmente mantenido por el asistente/colaborador en cada cambio, respaldado por Git y comprobado por CI. No pretende ejecutar tareas en background ni reemplaza el control de versiones.
