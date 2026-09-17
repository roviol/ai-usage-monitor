## Context

El dashboard usa un área con scroll y un sizer vertical para las tarjetas de proveedores. Ya existe una lógica responsive para la barra superior, pero no para la retícula de tarjetas.

## Goals

- Aprovechar el ancho disponible con una retícula de tarjetas.
- Mantener al menos una columna en pantallas compactas.
- Evitar scroll cuando el contenido cabe en la ventana.

## Non-Goals

- Cambiar proveedores, datos ni lógica de refresco.
- Rehacer el dashboard completo ni introducir una dependencia nueva.

## Approach

Usaremos una retícula basada en `wxFlexGridSizer` para distribuir las tarjetas de proveedor. El número de columnas se calculará a partir del ancho útil de la ventana y del ancho mínimo de tarjeta. Cuando cambie el ancho, el dashboard reconstruirá o reorganizará la retícula conservando el orden de proveedores y su accesibilidad. El área con scroll se conserva como respaldo para pantallas pequeñas, pero desaparece cuando el contenido cabe.

## Risks / Trade-offs

- Las tarjetas con mucho contenido pueden hacer que las columnas se desalineen; se mitigará con anchos expandibles y revisión visual.
- Puede ser necesario ajustar el número de columnas con pruebas en varios tamaños y temas.
