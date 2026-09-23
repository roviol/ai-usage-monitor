## MODIFIED Requirements

### Requirement: Retícula responsive para proveedores
El dashboard SHALL organizar las tarjetas de proveedores en una retícula responsive que utilice el espacio horizontal disponible. El número de columnas SHALL aumentar cuando el ancho útil de la ventana crezca y SHALL mantener al menos una columna en pantallas compactas. Las horas mostradas en las tarjetas (observación y reinicio de cuota) SHALL renderizarse en la zona horaria del sistema, y cada métrica con hora de reinicio SHALL mostrar además el tiempo restante hasta ese reinicio formateado como cuenta atrás.

#### Scenario: Ventana amplia
- **WHEN** la ventana se amplía y hay suficientes tarjetas
- **THEN** el dashboard muestra más de una columna y aprovecha el ancho disponible en lugar de apilar las tarjetas

#### Scenario: Ventana compacta
- **WHEN** la ventana se reduce al ancho compacto
- **THEN** el dashboard vuelve a una columna legible sin recortar el contenido de las tarjetas

#### Scenario: Contenido cabe en pantalla
- **WHEN** todas las tarjetas caben dentro del área visible
- **THEN** el dashboard no presenta scroll innecesario

#### Scenario: Hora de reinicio en la zona del sistema
- **WHEN** una métrica publica una hora de reinicio y el sistema está en una zona horaria dada
- **THEN** la tarjeta muestra la hora de reinicio convertida a la zona horaria del sistema, no a la zona en que el proveedor la publicó

#### Scenario: Hora de observación en la zona del sistema
- **WHEN** la tarjeta muestra la hora de la última observación
- **THEN** la hora corresponde al reloj local del sistema, no a una zona distinta

#### Scenario: Tiempo restante junto a la hora de reinicio
- **WHEN** una métrica tiene una hora de reinicio futura
- **THEN** la tarjeta muestra junto a la hora el tiempo restante con el mismo formato que el overlay (`reinicia en 5m`, `reinicia en 1h 5m`, `reinicia en 1d 6h`, `reinicia en <1m`)

#### Scenario: Reinicio ya alcanzado
- **WHEN** la hora de reinicio es anterior al momento actual
- **THEN** la tarjeta muestra la hora alcanzada y el marcador `reiniciando` en lugar de una cuenta atrás negativa