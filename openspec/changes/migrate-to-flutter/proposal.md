## Why

El proyecto actual está implementado en C++20 con wxWidgets y una capa de plataforma propia (WinHTTP/Win32 y libcurl/POSIX). Mantener esa base exige código nativo distinto por plataforma, empaquetado manual y pruebas de UI frágiles. Se necesita una segunda implementación en Flutter, conviviendo con la actual, que reproduzca la funcionalidad de forma exacta para poder comparar ambas aplicaciones y validar la paridad antes de reemplazar la base C++.

## What Changes

- Crear una nueva aplicación Flutter de escritorio en `flutter_app/`, sin eliminar la aplicación C++ actual, que sirva como referencia de comparación.
- Reproducir con paridad funcional exacta: proveedores y parsers, métricas, errores, scheduler con backoff, caché y datos obsoletos, dashboard, tarjetas responsivas, bandeja de sistema, tooltip, configuración/validación, secretos y overlay minimalista.
- Compartir el mismo contrato de datos en disco (`settings.json` y `cache.json`, mismos nombres de campo, valores y reglas de validación) para que ambas aplicaciones puedan abrir la misma configuración.
- Implementar en Flutter los equivalentes de plataforma: HTTP sin redirecciones con límite de 1 MiB y política de URL, ejecución de procesos con timeout y cancelación, almacén de secretos por usuario, instancia única y activación, y bandeja del sistema.
- Mantener las diferencias de plataforma ya definidas: en Windows bloqueo/click-through, supresión a pantalla completa y atajo global `Ctrl+Alt+U`; en Linux overlay sin esas capacidades.
- Añadir un arnés de verificación de paridad que compare salidas normalizadas (snapshots, tooltips, textos de overlay y archivos persistidos) contra la aplicación de referencia.
- Permitir variación de aspecto (colores, tipografía y widgets nativos de Flutter), pero no de funcionalidad, textos de estado ni comportamiento.
- **BREAKING** (solo para el nuevo árbol): `flutter_app/` introduce un segundo conjunto de dependencias, build y empaquetado; el binario C++ y su empaquetado actual permanecen intactos.

## Capabilities

### New Capabilities
- `flutter-desktop-application`: arranque, instancia única, rutas de datos, dashboard con tarjetas y retícula responsiva, modo siempre visible, cerrar-a-bandeja, icono de bandeja, menú y tooltip, atención al tema y ciclo de vida.
- `flutter-provider-monitoring`: adaptadores Codex, Claude, DeepSeek, OpenAI-compatible y Ollama (local y nube), contrato de métricas y errores, normalización, scheduler con backoff/jitter, refresco manual, caché y semántica de datos obsoletos.
- `flutter-settings-storage`: esquema y compatibilidad de `settings.json`/`cache.json`, defaults por tipo, validación, rutas portable vs perfil de usuario, almacén de secretos por plataforma y política de URL segura.
- `flutter-minimal-overlay`: overlay minimalista en Windows y Linux con proyección de filas, opacidad, arrastre y anclaje a esquinas, bloqueo/click-through (Windows), supresión a pantalla completa (Windows), atajo global y temporización de cuentas atrás.
- `flutter-parity-verification`: pruebas de contrato y arnés de comparación que demuestran paridad funcional con la aplicación C++ de referencia.

### Modified Capabilities
- Ninguna. La migración no cambia los requisitos de comportamiento existentes; la nueva aplicación debe satisfacerlos, y la paridad se declara como capacidades nuevas.

## Impact

- Se añade `flutter_app/` con proyecto Flutter (Dart), `pubspec.yaml`, integraciones de escritorio y sus pruebas; no se modifica el núcleo C++ salvo, si hace falta, documentación que describa cómo comparar.
- Nuevas dependencias de Flutter para bandeja, ventanas/overlay, atajos globales, secretos y FFI nativo; requieren toolchains de Windows y Linux.
- El formato de `settings.json`/`cache.json` y las rutas `data/`, `%LOCALAPPDATA%\AIUsageMonitor` y `$XDG_DATA_HOME/ai-usage-monitor` se convierten en contrato compartido entre ambas aplicaciones.
- Riesgos de paridad en: ejecución y cancelación de procesos (árbol de procesos), DPAPI/Secret Service vía Flutter, regiones redondeadas y click-through nativo del overlay, y detección de pantalla completa.
