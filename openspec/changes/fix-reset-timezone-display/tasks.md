## 1. Parser de Claude con zona IANA

- [x] 1.1 Extender `ParseClaudeReset` para capturar el sufijo opcional de zona IANA `(Continent/City)` en la línea `resets …` de Claude
- [x] 1.2 Convertir la hora de pared al instante absoluto usando la zona capturada (fijar `TZ`, `tzset`, `mktime`, restaurar `TZ` y repetir `tzset`), con fallback a la zona del sistema cuando la línea no publica zona
- [x] 1.3 Validar la zona capturada (formato `Xxx/Yyy` o `Xxx`) y conservar el rechazo cerrado de fechas/horas imposibles

## 2. Presentación del dashboard

- [x] 2.1 Renderizar `ObservationLabel` y `MetricMetadata` en la zona horaria del sistema con `wxDateTime` local explícito (sin `MakeUTC`)
- [x] 2.2 Añadir a `MetricMetadata` el tiempo restante con `FormatResetCountdown(metric.resetsAt, Clock::now())` separado por `  ·  ` tras la hora
- [x] 2.3 Mostrar `reiniciando` junto a la hora alcanzada cuando el reinicio ya pasó, sin cuenta atrás negativa

## 3. Pruebas

- [x] 3.1 Actualizar `TestClaudeParser` con un caso de zona del sistema distinta a la publicada (p. ej. TZ=America/New_York con línea `America/Santo_Domingo`) verificando el epoch correcto
- [x] 3.2 Añadir caso del parser sin sufijo de zona que conserva el comportamiento actual (hora del sistema)
- [x] 3.3 Añadir prueba de `MetricMetadata`: texto `Reinicia <hora local> · reinicia en Xm` con reloj falso, incluyendo `reiniciando` para reinicio pasado
- [x] 3.4 Ejecutar `ctest --preset linux-release` y verificar suite en verde con las zonas de prueba alternadas