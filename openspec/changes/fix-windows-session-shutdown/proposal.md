## Why

En Windows, el cierre normal del dashboard se interpreta como "ocultar en la bandeja" y veta el evento consultivo que el sistema envía antes de cerrar sesión, apagar o reiniciar. Como resultado, AI Usage Monitor aparece como aplicación bloqueante y requiere cierre forzado; además, el título nativo dinámico del overlay expone el resumen completo de uso en la pantalla de bloqueo del apagado.

## What Changes

- Distinguir el cierre ordinario del dashboard del cierre de sesión solicitado por Windows, permitiendo apagar, reiniciar o cerrar sesión sin confirmación ni intervención manual.
- Ejecutar una terminación única y acotada que detenga refrescos, procesos hijos, observadores, temporizadores, hooks, atajos y el icono de bandeja durante el fin de sesión.
- Mantener títulos nativos estables y concisos para las ventanas de la aplicación, sin incluir cuotas, proveedores, cuentas, reinicios ni otros datos de uso.
- Conservar la información dinámica donde corresponde: contenido visual y accesible del overlay, dashboard y tooltip de bandeja.
- Añadir cobertura automatizada y una comprobación nativa de Windows para cierre de sesión y títulos de ventana.

## Capabilities

### New Capabilities

- `windows-session-lifecycle`: Comportamiento de AI Usage Monitor ante cierre de sesión, apagado o reinicio de Windows, incluida la identificación concisa y no sensible de sus ventanas nativas.

### Modified Capabilities

Ninguna.

## Impact

- Afecta el ciclo de vida de `MonitorApp`, el cierre del dashboard y la ventana nativa del overlay en `src/ui`.
- Amplía las pruebas unitarias y de interfaz nativa de Windows, incluidos los scripts de humo existentes.
- No cambia protocolos de proveedores, formatos de configuración o caché, credenciales, intervalos de refresco ni comportamiento de cierre ordinario hacia la bandeja.
- No introduce dependencias nuevas ni cambios incompatibles para el usuario.
