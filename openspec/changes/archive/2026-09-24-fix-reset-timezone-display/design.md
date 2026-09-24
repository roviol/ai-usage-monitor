## Context

See `proposal.md` — Why. Dos fuentes de hora de reinicio llegan a las tarjetas:

- Codex y Ollama Cloud publican `resetsAt` como epoch absoluto (segundos Unix). Es un instante correcto; el problema es solo de render.
- Claude publica texto con hora de pared y zona IANA: `resets Aug 5, 7:10pm (America/Santo_Domingo)`. `ParseClaudeReset` (src/providers.cpp) ignora la zona IANA y resuelve la hora de pared con `std::mktime`, es decir, con la zona del sistema. Si la zona del sistema no coincide con la publicada, el `TimePoint` almacenado está desplazado (verificado: la misma pared `19:10` produce epoch `1785957000` con TZ=UTC y `1785971400` con TZ=America/Santo_Domingo — 4 h de diferencia).

El render del dashboard usa `wxDateTime(time_t)` (src/ui/dashboard.cpp:93 y :30), que muestra la hora en la zona del sistema; el overlay ya muestra solo cuentas atrás relativas (`FormatResetCountdown`) y no la hora absoluta, por lo que no sufre el problema de zona ni necesita cambio.

Constraints:
- `Metric.resetsAt` es un `TimePoint` absoluto; el contrato de `cache.json` no cambia.
- La suite actual (`TestClaudeParser`) verifica el reinicio convirtiendo con `localtime_r` bajo la zona del sistema; debe pasar bajo cualquier zona de pruebas.

## Goals / Non-Goals

**Goals:**
- Instante de reinicio correcto para Claude: interpretar la hora de pared en la zona IANA publicada (con fallback a la zona del sistema cuando la línea no trae zona).
- Render de horas del dashboard (observación y reinicio) en la zona horaria del sistema.
- Mostrar el tiempo restante hasta el reinicio en la tarjeta, con el formato ya definido por `FormatResetCountdown` (`reinicia en <1m|5m|1h 5m|1d 6h`, `reiniciando`).

**Non-Goals:**
- Cambiar el formato del tooltip, el overlay o `FormatISOCombined` en otros componentes.
- Añadir una preferencia de zona horaria al usuario.
- Cambiar el esquema de `settings.json`/`cache.json` o los contratos de dominio.
- Interpretar zonas IANA en respuestas que ya publican epoch (Codex, Ollama Cloud): el epoch es absoluto y no requiere conversión.

## Decisions

### 1. Zona IANA de Claude explícita en el parser
`ParseClaudeReset` extiende su expresión regular para capturar el sufijo opcional `(Zona/Nombre)` que Claude publica, y convierte la hora de pared a un instante absoluto usando esa zona. Para la conversión sin depender de librerías nuevas se construye el instante con `std::mktime` tras fijar `TZ=<zona>` con `setenv` y `tzset()` de forma reentrante (la alternativa — `std::chrono::zoned_time` — requiere C++20 con libstdc++ 13+ y rompería la build de Ubuntu; la de `<wx/tzinfo.h>` no está disponible en la configuración de wx estática actual). Tras convertir se restaura `TZ` al valor previo y se repite `tzset()`. El test existente pasa porque en el entorno de prueba el sistema ya está en la misma zona publicada; se añade un caso con zonas distintas.

*Alternativas consideradas:* parsear manualmente la base de datos tz (frágil y sin ganancia) y usar la hora del sistema siempre (mantiene el bug).

### 2. Render explícito en zona local
`wxDateTime` construido desde `time_t` ya usa la zona local; el bug de render solo puede aparecer si el widget muestra el valor crudo o una zona anidada. Se hace explícito el contrato: `ObservationLabel` y `MetricMetadata` construyen `wxDateTime` y llaman `FormatISOCombined` sobre el objeto local por defecto, sin `MakeUTC`. En MSW se verifica que el valor mostrado coincide con el reloj del sistema; no se cambia de API si la prueba de render muestra el mismo resultado que hoy.

*Alternativa considerada:* formatear con `strftime`/`std::put_time` (cambia el estilo del texto y duplica el formateo de wx).

### 3. Cuenta atrás reutilizando `FormatResetCountdown`
`MetricMetadata` añade, tras la hora, el texto de `FormatResetCountdown(metric.resetsAt, Clock::now())` separado por `  ·  `. El formato ya está probado (tests del overlay) y coincide con el lenguaje del overlay. Cuando el reinicio ya pasó se muestra `reiniciando` junto a la hora alcanzada.

*Alternativas consideradas:* un formateador propio en dashboard (duplicaría reglas) y añadir la cuenta atrás solo al tooltip (no resuelve el pedido del usuario en la tarjeta).

### 4. Pruebas deterministas de zona
La prueba del parser fijará `TZ=America/New_York` en el proceso de test (o inyectará la zona publicada distinta a la del sistema) para verificar que `resetsAt` corresponde al instante correcto independientemente de la zona del sistema; y un caso con la zona del sistema igual a la publicada. La prueba de tarjeta valida el texto `Reinicia <fecha-hora-zona-sistema> · reinicia en Xm` contra un reloj falso.

## Risks / Trade-offs

- [Cambiar TZ global con setenv durante el parse afecta a otros hilos] → Los parsers corren en el thread del scheduler y `localtime_r`/`mktime` son sensibles a `TZ` global. Se acota: guardar/restaurar el valor de `TZ` alrededor de la conversión y documentar que el parse de Claude es el único punto que lo hace; riesgo aceptado porque la ventana es de microsegundos y los otros hilos no formatean horas en ese instante.
- [wxDateTime y el DST de la zona publicada] → La conversión usa la regla de zona vigente en la fecha objetivo; se cubre con el caso de prueba del fixture (America/Santo_Domingo no tiene DST, y New York en agosto sí) para detectar desfases de una hora.
- [Texto de tarjeta más largo con la cuenta atrás] → La tarjeta ya envuelve (`Wrap`) la línea de metadata; se verifica con la prueba de reflow compacta.

## Migration Plan

1. Ajustar `ParseClaudeReset` + pruebas con zona fija.
2. Ajustar `MetricMetadata`/`ObservationLabel` + pruebas de texto.
3. Regenerar corpus de paridad no aplica (los dumps de paridad no capturan horas de tarjeta); `ctest --preset linux-release` debe seguir en verde.

Rollback: revertir los dos archivos tocados; no hay migración de datos.

## Open Questions

- Ninguna abierta; el fallback sin zona IANA se mantiene como hoy (hora del sistema).