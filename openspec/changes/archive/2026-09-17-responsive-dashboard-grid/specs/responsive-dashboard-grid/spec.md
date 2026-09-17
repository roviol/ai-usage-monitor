## Purpose

Define el comportamiento responsive del dashboard para aprovechar el espacio disponible y evitar scroll innecesario.

## ADDED Requirements

### Requirement: Retícula responsive para proveedores
El dashboard SHALL organizar las tarjetas de proveedores en una retícula responsive que utilice el espacio horizontal disponible. El número de columnas SHALL aumentar cuando el ancho útil de la ventana crezca y SHALL mantener al menos una columna en pantallas compactas.

#### Scenario: Ventana amplia
- **WHEN** la ventana se amplía y hay suficientes tarjetas
- **THEN** el dashboard muestra más de una columna y aprovecha el ancho disponible en lugar de apilar las tarjetas

#### Scenario: Ventana compacta
- **WHEN** la ventana se reduce al ancho compacto
- **THEN** el dashboard vuelve a una columna legible sin recortar el contenido de las tarjetas

#### Scenario: Contenido cabe en pantalla
- **WHEN** todas las tarjetas caben dentro del área visible
- **THEN** el dashboard no presenta scroll innecesario

### Requirement: Accesibilidad y comportamiento consistente
La retícula SHALL conservar el orden lógico de los proveedores, permitir navegación por teclado y mantener las etiquetas de accesibilidad existentes. El cambio de diseño MUST NOT alterar los datos mostrados ni el comportamiento de refresco.

#### Scenario: Navegación por teclado
- **WHEN** el usuario navega con el teclado entre tarjetas
- **THEN** el orden de enfoque sigue el orden lógico de los proveedores y cada tarjeta conserva su nombre accesible

#### Scenario: Cambio de tema
- **WHEN** el usuario cambia entre tema claro y oscuro
- **THEN** la retícula mantiene la legibilidad y el contraste en ambas tarjetas y fondo
