## Why

Quien usa varias herramientas de IA no dispone de una vista local, discreta y unificada para saber cuánto ha consumido, qué cuota o saldo conserva y cuándo se actualizará cada límite. Se necesita una aplicación visual que permanezca en segundo plano con un coste mínimo de CPU y memoria, reutilice los clientes ya autenticados cuando exista una interfaz soportada y pueda llevarse a otra máquina sin instalar un runtime.

## What Changes

- Crear una aplicación de escritorio orientada primero a Windows, sin ventana de consola, que se ejecute desde un único binario portable y mantenga un icono en el área de notificación.
- Mostrar en el tooltip del icono un resumen compacto del estado agregado, la antigüedad de los datos y alertas de proveedores.
- Abrir con clic un dashboard simple con uso, cuota/saldo restante, ventanas de límite, próximo reinicio y estado de Claude, Codex y endpoints OpenAI-compatible.
- Permitir activar o desactivar proveedores, detectar las instalaciones locales de Claude Code y Codex, configurar un preset DeepSeek o un endpoint OpenAI-compatible, proteger credenciales, probar conexiones y elegir la frecuencia de refresco.
- Usar por defecto un refresco de 5 minutos, permitir refresco manual y aplicar timeouts, backoff con jitter y conservación del último dato válido para evitar consumo y tráfico innecesarios.
- Añadir una opción persistente `Siempre visible` para el dashboard, independiente del funcionamiento en segundo plano.
- Distinguir métricas obtenidas del proveedor, métricas calculadas localmente y métricas no disponibles; nunca inventar una cuota restante cuando la interfaz del proveedor no la exponga.
- Implementar Codex mediante su app-server oficial para límites y actividad de tokens; implementar DeepSeek mediante su endpoint oficial de saldo; permitir adaptadores configurables para APIs OpenAI-compatible. La integración de Claude ejecutará exclusivamente `claude /usage` de forma local y no interactiva, sin API administrativa ni prompt al modelo.
- Diseñar un núcleo C++ portable y adaptadores de plataforma. Entregar Windows como objetivo obligatorio y preparar Linux como objetivo de compilación adicional con empaquetado portable por plataforma; no se promete un mismo ejecutable para ambos sistemas operativos.
- Incluir mediciones automatizadas del tamaño del artefacto, consumo en reposo, CPU ociosa, tiempo de inicio y tráfico de refresco como criterios de aceptación de la cualidad “ultra liviano”.

## Capabilities

### New Capabilities

- `provider-usage-monitoring`: Obtención, normalización, refresco, caché y representación honesta de uso, cuota, saldo y disponibilidad para Codex, Claude y APIs OpenAI-compatible/DeepSeek.
- `tray-dashboard`: Comportamiento del icono de estado, tooltip, dashboard visual, refresco manual, estados de error y modo siempre visible.
- `provider-configuration`: Detección y configuración de proveedores, credenciales seguras, frecuencia de refresco, prueba de conexión y persistencia portable.
- `portable-desktop-distribution`: Compilación sin consola ni runtimes externos, límites verificables de recursos y paquetes portables separados para Windows y Linux.

### Modified Capabilities

Ninguna; el repositorio no contiene capacidades previas.

## Impact

- Se crea desde cero el código fuente, pruebas, assets, configuración CMake y automatización de empaquetado.
- El binario interactuará con procesos locales instalados (`codex` y opcionalmente `claude`) y con HTTPS para los proveedores configurados.
- En Windows se usarán APIs nativas de notificación, ventanas, almacenamiento de secretos y ejecución oculta de procesos. Linux requerirá adaptadores equivalentes para escritorio, secretos y system tray, además de un formato portable propio como AppImage.
- Las integraciones quedan condicionadas por las capacidades reales de cada cuenta: Codex con autenticación ChatGPT puede exponer porcentajes y actividad; DeepSeek expone saldo; Claude y endpoints genéricos pueden devolver sólo subconjuntos. La interfaz deberá hacer visible esa cobertura.
