## Context

AI Usage Monitor es una aplicación wxWidgets residente: cerrar el dashboard normalmente lo oculta y mantiene activos la bandeja y el scheduler. En Windows, wxWidgets procesa `WM_QUERYENDSESSION` recorriendo las ventanas superiores y llamando `Close()` antes de permitir el fin de sesión. `DashboardFrame::OnClose` veta todo cierre vetable para implementar el comportamiento residente, por lo que también veta apagar, reiniciar o cerrar sesión.

El overlay agrava la experiencia al reconstruir su título nativo con nombres de proveedores, valores de cuota, estados y reinicios. Windows usa el título de una ventana para identificar una aplicación que demora el apagado, de modo que muestra ese resumen completo en lugar de una identidad estable de la aplicación. El contenido dinámico sí es útil dentro del overlay y como descripción accesible, pero no como identidad nativa.

## Goals / Non-Goals

**Goals:**

- Permitir siempre el cierre de sesión, apagado o reinicio solicitado por Windows, independientemente de qué ventanas estén visibles.
- Conservar el cierre ordinario del dashboard como ocultación hacia la bandeja.
- Liberar una sola vez los recursos residentes cuando Windows confirma el fin de sesión o el usuario elige Salir.
- Usar títulos nativos estables que identifiquen la aplicación sin publicar datos dinámicos de uso.
- Cubrir el comportamiento con una prueba nativa que reproduzca los mensajes de sesión sin apagar el equipo de pruebas.

**Non-Goals:**

- Añadir confirmaciones, guardado interactivo o capacidad de cancelar el apagado.
- Cambiar la obtención de métricas, el scheduler, los formatos persistidos o las preferencias del overlay.
- Cambiar el comportamiento de sesión de Linux u otros entornos de escritorio.
- Eliminar el resumen visual o la descripción accesible de las cuotas.

## Decisions

### 1. Aceptar la consulta de fin de sesión en `MonitorApp`

En Windows, `MonitorApp` manejará `wxEVT_QUERY_END_SESSION` a nivel de aplicación y aceptará el evento sin delegarlo al manejador predeterminado de wxWidgets que llama `Close()` en cada ventana superior. La fase consultiva no iniciará la terminación ni ocultará o destruirá ventanas, porque otro proceso todavía puede cancelar el cierre de sesión.

Esto separa explícitamente el cierre del sistema del `wxEVT_CLOSE_WINDOW` ordinario del dashboard. Detectar el caso dentro de `DashboardFrame::OnClose` fue descartado porque tanto un clic normal en la X como el `Close(false)` usado durante la consulta llegan como cierres vetables y el frame no tiene una señal fiable del origen.

### 2. Centralizar la limpieza final en una ruta idempotente

Se extraerá una operación privada de terminación, protegida por el estado `exiting_`, que detenga el observador de instancia única, elimine `ready.signal`, detenga el scheduler y sus procesos hijos, y desactive temporizador, hooks y hotkey del overlay. `ExitApplication` reutilizará esa operación antes de retirar la bandeja y destruir las ventanas; `OnExit`, invocado por el manejo normal de `wxEVT_END_SESSION` de wxWidgets, también la reutilizará.

No se ejecutará UI modal ni persistencia opcional durante `wxEVT_END_SESSION`. Se conservará el manejador final predeterminado de wxWidgets para que ejecute `OnExit` y termine el proceso conforme al ciclo de vida de Windows. Duplicar una ruta independiente para apagado fue descartado porque aumenta el riesgo de doble `join`, doble destrucción o recursos que sólo se liberan en una de las salidas.

### 3. Separar identidad nativa de contenido dinámico

El dashboard conservará `AI Usage Monitor` y el overlay usará también un título nativo fijo y conciso de la aplicación. `ReprojectAndResize` dejará de llamar `SetTitle` con el resumen de snapshots. La proyección seguirá alimentando el pintado del overlay y su descripción accesible cuando esté desbloqueado; el dashboard y la bandeja seguirán siendo los equivalentes textuales accesibles cuando el overlay esté bloqueado.

Mantener una versión truncada o parcialmente anonimizada del resumen en el título fue descartado: seguiría mezclando una identidad que Windows puede mostrar fuera de contexto con datos que cambian frecuentemente y podría filtrar nombres configurables de proveedores o cuentas.

### 4. Extender la prueba de interfaz nativa de Windows

El fixture de `scripts/test-ui-windows.ps1` enumerará los títulos superiores del proceso y comprobará que permanecen estables después de publicar métricas, sin nombres de proveedores, cuentas, porcentajes ni textos de reinicio. Al final de la prueba enviará `WM_QUERYENDSESSION` y exigirá una respuesta afirmativa sin cerrar el proceso; después enviará `WM_ENDSESSION` confirmado y verificará que el proceso termine dentro de un tiempo acotado. La prueba se realizará con dashboard y overlay activos para reproducir la configuración que expone el fallo.

El evento final se probará al final del script porque termina deliberadamente el proceso. No se intentará automatizar un apagado real del host, lo cual sería destructivo e inadecuado para CI.

## Risks / Trade-offs

- [La consulta se acepta y luego Windows cancela el apagado] → No iniciar limpieza durante `wxEVT_QUERY_END_SESSION`; la aplicación continúa operativa sin reconstruir recursos.
- [La terminación explícita y `OnExit` recorren la misma limpieza] → Hacer la operación idempotente y cubrir llamadas repetidas.
- [Un refresco o proceso hijo está activo al finalizar la sesión] → Cancelarlo mediante `RefreshScheduler::Stop` y la limpieza de árbol ya existente, sin esperar interacción ni mostrar diálogos.
- [Quitar el resumen del título reduce información para tecnología de asistencia] → Mantener nombre, ayuda/descripción accesible y equivalentes textuales en dashboard y bandeja; comprobar que sólo cambia la identidad nativa.
- [La simulación de mensajes no reproduce toda la interfaz de apagado de Windows] → Usarla como regresión determinista y complementar con una comprobación manual de apagado/reinicio en el empaquetado de Windows.

## Migration Plan

No hay migración de datos. La corrección se distribuye en el siguiente ejecutable de Windows y es reversible restaurando el manejo y los títulos anteriores; configuración y caché existentes permanecen compatibles.

## Open Questions

Ninguna para iniciar la implementación.
