## Why

AI Usage Monitor todavía no puede observar un servidor Ollama local, por lo que los usuarios no tienen una forma unificada de confirmar que el servicio responde y qué modelos están cargados en memoria.

## What Changes

- Añadir `ollama` como un tipo de proveedor seleccionable en la configuración visual, deshabilitado por defecto.
- Consultar el endpoint público `GET /api/ps` de Ollama para obtener disponibilidad, número de modelos activos, consumo de memoria/VRAM por modelo y su hora de descarga cuando la API la publique.
- Permitir una URL base configurable, con `http://localhost:11434` como valor inicial y HTTP loopback habilitado por defecto; las instancias remotas seguirán requiriendo HTTPS salvo excepción explícita.
- Permitir opcionalmente una credencial Bearer almacenada de forma segura para servidores Ollama protegidos.
- No llamar a endpoints de generación ni inventar tokens, cuotas, costes o históricos: Ollama mostrará sólo la actividad observable a través de `/api/ps`.
- Extender el modelo normalizado con métricas puntuales de recursos y conteo de modelos, manteniendo compatibilidad con la configuración y caché existentes.

## Capabilities

### New Capabilities

- `ollama-local-monitoring`: Observación segura y fail-closed del estado del servidor Ollama y de los modelos cargados mediante `/api/ps`, con cobertura explícita y sin generar inferencias.

### Modified Capabilities

Ninguna. Los proveedores existentes conservan su contrato actual.

## Impact

- Dominio y serialización: nuevos tipos de métrica/unidad/alcance y sus valores JSON compatibles hacia atrás.
- Adaptadores y fábrica: nuevo `OllamaProvider`, análisis de `/api/ps`, prueba de conexión y capacidad reportada.
- Persistencia: `ProviderKind::Ollama` en carga/guardado y caché de snapshots.
- UI y documentación: opción Ollama en Preferencias, formularios simplificados, validación de URL loopback/HTTPS, pruebas, fixtures y documentación de cobertura limitada.
