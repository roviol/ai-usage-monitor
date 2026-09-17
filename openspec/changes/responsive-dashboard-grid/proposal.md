## Why

El dashboard actual apila las tarjetas en una sola columna y depende del scroll incluso cuando la ventana ampliada tiene espacio disponible. Esto desaprovecha pantallas grandes y dificulta comparar proveedores de un vistazo.

## What Changes

- Reemplazar el apilado vertical del área de proveedores por una retícula responsive.
- Ajustar el número de columnas según el ancho útil de la ventana, con al menos una columna en pantallas compactas.
- Mantener la navegación con teclado y el soporte de accesibilidad existentes en las tarjetas.
- Evitar scroll innecesario cuando todo el contenido cabe en el área visible.
- Conservar el comportamiento actual en anchos compactos y respetar el tema claro/oscuro.

## Capabilities

### New Capabilities
- `responsive-dashboard-grid`: Controla la presentación responsive del dashboard y su retícula de tarjetas.

### Modified Capabilities

## Impact

- Afecta principalmente a la construcción del dashboard en `src/ui/dashboard.cpp` y al diseño responsive existente.
- Puede requerir pruebas de interfaz para validar la distribución y comportamiento en distintos anchos.
- No cambia proveedores, datos, configuración ni contratos de red.
