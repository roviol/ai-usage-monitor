## Why

El dashboard muestra la hora del reinicio de cuota en una zona horaria distinta a la del sistema y no indica cuánto falta para ese reinicio. Los parsers tratan la hora en texto de Claude (y en general la hora en pantalla del dashboard) como hora del sistema cuando los proveedores la publican en su propia zona horaria (la línea de Claude incluye la zona IANA, p. ej. `America/Santo_Domingo`, y el app-server de Codex publica epoch absoluto). Con una zona del sistema distinta, `ParseClaudeReset` interpreta la hora de pared con `mktime` del sistema y el resultado queda desplazado; además, la tarjeta solo muestra la hora absoluta, obligando al usuario a calcular mentalmente cuánto falta.

## What Changes

- Mostrar la hora de reinicio y la hora de observación en la zona horaria del sistema del usuario (render consistente con el reloj local en todas las plataformas).
- Respetar la zona IANA que publica Claude en su línea de reinicio (`resets Aug 5, 7:10pm (America/Santo_Domingo)`): convertir esa hora de pared a un instante absoluto usando la zona indicada, no la del sistema.
- Mostrar junto a la hora de reinicio el tiempo restante formateado (`reinicia en 5m`, `reinicia en 1h 5m`, `reinicia en 1d 6h`, `reinicia en <1m`, `reiniciando`) reutilizando `FormatResetCountdown`.
- Mantener el texto del overlay (cuentas atrás relativas) sin cambios: el fix afecta a la presentación absoluta de la tarjeta y al instante almacenado.

## Capabilities

### New Capabilities

Ninguna.

### Modified Capabilities

- `responsive-dashboard-grid`: las tarjetas del dashboard muestran la hora de reinicio en la zona del sistema y añaden el tiempo restante hasta el reinicio junto a la hora; la hora de observación se muestra en la zona del sistema.

## Impact

- `src/providers.cpp`: `ParseClaudeReset` debe interpretar la hora de pared en la zona IANA publicada por Claude (fallback: zona del sistema cuando no hay zona entre paréntesis).
- `src/ui/dashboard.cpp`: `MetricMetadata` y `ObservationLabel` renderizan con la zona del sistema y añaden la cuenta atrás relativa para las métricas con `resetsAt`.
- `tests/test_main.cpp`: la prueba del parser de Claude debe fijar una zona de sistema distinta a la publicada para verificar la conversión; nuevas aserciones para el formato con cuenta atrás.
- Sin cambios de esquema en `settings.json`/`cache.json` ni de la API de dominio (`Metric.resetsAt` sigue siendo un instante absoluto).