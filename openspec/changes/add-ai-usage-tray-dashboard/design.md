## Context

El repositorio contiene únicamente la raíz OpenSpec; la aplicación se diseñará desde cero. El usuario trabaja principalmente en Windows y ya tiene `codex` y `claude`, pero quiere consultar su consumo sin abrir terminales y sin mantener un runtime de Python, JavaScript, Java o .NET.

El 5 de agosto de 2026 se verificó este ambiente:

- OpenSpec CLI 1.5.0.
- Visual Studio Community 2022 17.14 en `E:\Program Files\Microsoft Visual Studio\2022\Community`, workload VC++ x64, compilador MSVC 19.44, Windows SDK 10 y CMake 3.31.6. El Developer Command Prompt expone el compilador correctamente; CMake y `cl` no están en el `PATH` global.
- Rust 1.94 y Go 1.26.1 también están instalados, pero no aportan una ventaja suficiente sobre C++ para el tamaño, los controles nativos y la reutilización directa de APIs Win32.
- Codex CLI 0.146.0 y Claude Code 2.1.221 son detectables.
- El host está listo para compilar Windows. No se pudo validar un ambiente Linux local: WSL devolvió acceso denegado y Docker no está instalado; Linux deberá verificarse en CI o en otro host.

Las pruebas locales confirman que Codex app-server ofrece `account/rateLimits/read` y `account/usage/read`, DeepSeek ofrece `GET /user/balance`, y Claude Code 2.1.221 acepta `claude /usage` con stdout redirigido y termina sin sesión interactiva. “OpenAI-compatible” describe normalmente la inferencia, no una API universal de facturación, por lo que el modelo de datos debe admitir cobertura parcial.

## Goals / Non-Goals

**Goals:**

- Producir un ejecutable Windows GUI x64 pequeño, sin consola y sin runtime externo, que permanezca prácticamente inactivo entre refrescos.
- Unificar métricas heterogéneas sin ocultar su alcance, unidad, fuente ni antigüedad.
- Ofrecer icono de tray, tooltip útil, dashboard simple, configuración visual y modo siempre visible.
- Reutilizar la autenticación de Codex y Claude a través de sus clientes, sin leer ni copiar directamente sus tokens.
- Mantener el núcleo, las pruebas y la mayor parte de la UI compartidos para generar también un paquete Linux portable.
- Hacer medibles el tamaño, memoria, CPU ociosa, inicio y tráfico.

**Non-Goals:**

- Interceptar o actuar como proxy de todas las llamadas de IA.
- Reemplazar los dashboards de facturación, comprar créditos, canjear resets o cambiar planes.
- Usar endpoints privados, extraer credenciales de los archivos de los clientes o presentar estimaciones como cuotas oficiales.
- Prometer idénticas métricas para proveedores que no ofrecen APIs equivalentes.
- Entregar el mismo archivo binario para Windows y Linux, soporte macOS o autoactualización en la primera versión.

## Decisions

### 1. C++20, CMake y wxWidgets 3.3.x con enlace estático en Windows

El proyecto usará C++20 y CMake Presets. wxWidgets aporta controles nativos, `wxTaskBarIcon`, temporizadores, accesibilidad básica y una base compartida Windows/Linux. Se fijará una versión exacta con checksum y se compilarán sólo los componentes requeridos; MSVC usará runtime `/MT` y subsistema `WINDOWS`.

Alternativas consideradas: Win32 puro produciría el binario mínimo, pero duplicaría casi toda la UI de Linux; FLTK es más pequeño, pero no tiene un tray moderno común; Qt aumenta considerablemente el paquete; Rust/Slint, Go/Fyne, Tauri y Avalonia añaden tamaño, toolchain o runtime sin mejorar la integración requerida.

### 2. Arquitectura por puertos y adaptadores

El código se dividirá en:

- `domain`: `ProviderSnapshot`, `Metric`, estados, unidades, procedencia y reglas de agregación; sin dependencias de UI.
- `providers`: adaptadores Codex, Claude, DeepSeek y OpenAI-compatible tras una interfaz `IUsageProvider`.
- `services`: scheduler, backoff, caché, configuración, composición del tooltip y coordinación de refrescos.
- `platform`: procesos ocultos, HTTP/TLS, secretos, single-instance y métricas de recursos para Win32 y Linux.
- `ui`: tray, dashboard y diálogo de configuración en wxWidgets.

Esto permite probar el dominio y los proveedores con fixtures, además de reemplazar una integración cuando cambie un cliente.

### 3. Modelo normalizado con cobertura y procedencia explícitas

Cada métrica tendrá tipo, valor decimal seguro, unidad, alcance (`rolling-window`, `day`, `billing-period`, `lifetime`), inicio/reinicio si aplica, instante de observación y procedencia (`provider-reported`, `locally-observed`, `derived`). La ausencia será un estado (`unsupported`, `unauthorized`, `unavailable`), no cero. Un snapshot conservará por separado salud actual y último dato válido.

El dashboard no forzará una falsa equivalencia: una tarjeta puede mostrar porcentaje de ventana para Codex o Claude y saldo monetario para DeepSeek.

### 4. Integraciones por proveedor

- **Codex:** ejecutar `codex app-server` oculto y bajo demanda, inicializar JSON-RPC/JSONL y consultar `account/read`, `account/rateLimits/read` y `account/usage/read`. Se usará la sesión ya gestionada por Codex; no se leerá `auth.json`. El proceso terminará al completar el refresco.
- **Claude suscripción:** ejecutar exclusivamente `claude /usage` como proceso oculto con stdout redirigido, stdin vacío, timeout y cancelación. No se usará `--print`, PTY/ConPTY ni una API administrativa directa. Sólo se aceptarán líneas de porcentaje reconocidas por fixtures; ante cambios de formato se fallará de forma cerrada y nunca se enviará un prompt al modelo.
- **DeepSeek:** el preset usará `GET /user/balance`; mostrará saldo disponible. El consumo sólo se derivará si el usuario configura un presupuesto inicial y se etiquetará `derived`.
- **OpenAI-compatible genérico:** comprobar salud con `/models` y admitir URLs opcionales de uso/saldo junto con JSON Pointers configurables. No se asumirá que `/usage` o `/billing` existen. Se limitarán método, tamaño de respuesta y campos para evitar convertir la configuración en un cliente HTTP arbitrario.

### 5. Scheduler conservador y caché atómica

El intervalo predeterminado será 5 minutos, configurable entre 1 y 60 minutos. El scheduler será dirigido por temporizadores y no hará polling continuo. Refrescos del mismo proveedor se coalescerán; cada operación tendrá timeout de 10 segundos. Fallos transitorios aplicarán backoff exponencial con jitter hasta 60 minutos, respetando `Retry-After`; una acción manual podrá intentar una vez sin crear concurrencia duplicada.

El último snapshot válido se escribirá de forma atómica junto a la configuración y se cargará al inicio como `stale` hasta refrescar. El caché no contendrá credenciales.

### 6. UI resident-first y estados compactos

Al iniciar se crea el tray y el dashboard permanece oculto. El icono representa `ok`, `stale/partial`, `error/auth` o `disabled/no-data`. El tooltip se compondrá por prioridad y respetará el límite efectivo de Windows de 127 caracteres; siempre incluirá antigüedad o estado si no caben todas las cifras.

Un clic abre o enfoca una única ventana. El dashboard contiene una tarjeta por proveedor, última actualización, métricas disponibles y errores accionables. Cerrar la ventana la oculta; sólo `Salir` en el menú termina el proceso. `Siempre visible` se persiste y aplica mediante el estilo top-most de la plataforma.

### 7. Configuración portable y secretos ligados al usuario

`settings.json` y `cache.json` vivirán en un directorio `data` junto al ejecutable cuando sea escribible; si no, se usará el directorio de datos del usuario y la UI indicará el modo activo. Las escrituras serán atómicas y el esquema tendrá versión.

En Windows, API keys se cifrarán con DPAPI para el usuario actual; en Linux se preferirá Secret Service y, si no está disponible, la clave sólo podrá mantenerse durante la sesión o recibirse por variable de entorno. Copiar el programa no copiará credenciales utilizables: se deberán reingresar. Logs y mensajes redactarán secretos y cabeceras de autorización.

Sólo se aceptará HTTPS, salvo HTTP en loopback habilitado explícitamente. Los redirects no reenviarán autenticación a otro origen, se usará el trust store del sistema y las respuestas tendrán límite de 1 MiB.

### 8. Distribución y presupuestos verificables

Windows generará un solo `ai-usage-monitor.exe` x64 Release, sin DLL del proyecto ni consola. Objetivos de aceptación: máximo 15 MiB, working set ocioso máximo 35 MiB tras 60 segundos, CPU ociosa promedio máximo 0.2% durante 5 minutos, inicio del tray máximo 750 ms en el host de referencia y cero red entre refrescos.

Linux generará un AppImage x86_64 separado, con integración de tray dependiente del soporte StatusNotifier/AppIndicator del escritorio. Objetivos: máximo 45 MiB y RSS ocioso máximo 50 MiB. También podrá producirse un ELF dinámico más pequeño para distribuciones con wxGTK.

Los umbrales se comprobarán en CI/release; si una dependencia los rompe, el release falla o el presupuesto se revisa explícitamente en la especificación, no de forma silenciosa.

## Risks / Trade-offs

- [Claude no ofrece una API pública uniforme para cuota de suscripción] → Mantener el puente CLI como opt-in, versionado y fail-closed; mostrar cobertura parcial y priorizar futuras salidas estructuradas oficiales.
- [Cambios en protocolos o JSON externos] → Fixtures por versión, validación estricta, límites de respuesta y estado `unsupported` en lugar de crash o valores incorrectos.
- [“OpenAI-compatible” no implica facturación compatible] → Preset DeepSeek y mappings explícitos; nunca sondear rutas privadas adivinadas.
- [AppImage con GTK es mayor que el `.exe`] → Presupuestos distintos, dependencias recortadas y ELF dinámico alternativo.
- [El tray de GNOME puede requerir extensión] → Detectar indisponibilidad, documentarla y permitir abrir el dashboard como aplicación normal.
- [DPAPI/Secret Service reduce portabilidad de credenciales] → Mantener portable el programa y los ajustes no secretos; pedir reautenticación al moverlo.
- [Refrescos simultáneos elevan CPU/red brevemente] → Pool con concurrencia máxima dos, procesos efímeros, coalescing y backoff.
- [Una ventana top-most puede resultar intrusiva] → Opción desactivada por defecto, visible en el dashboard y reversible de inmediato.

## Migration Plan

1. Crear el esqueleto CMake, fijar dependencias y validar un binario GUI vacío en Windows.
2. Implementar dominio, caché y configuración versionada sin migración previa (`schemaVersion: 1`).
3. Añadir tray/dashboard y adaptadores con fixtures antes de conectar cuentas reales.
4. Producir un release Windows portable y ejecutar pruebas funcionales, de seguridad y presupuestos.
5. Habilitar Linux tras pasar la matriz CI wxGTK/AppImage y documentar los escritorios probados.

El rollback consiste en cerrar y borrar la carpeta portable; no se instala servicio ni se modifica la autenticación de los clientes. Si se usó el fallback de datos del usuario, la UI ofrecerá `Abrir carpeta de datos` para eliminarla manualmente. Cambios futuros de esquema escribirán backup antes de migrar y podrán volver al último archivo válido.

## Open Questions

- Durante la implementación se debe ejecutar un spike contra Claude Code 2.1.221 para determinar si existe una salida estructurada pública de `/usage`; el puente PTY sólo se activa si no la hay y sus pruebas son estables.
- La matriz inicial de Linux debe elegir escritorios soportados (propuesta: Ubuntu LTS con GNOME + AppIndicator y KDE Plasma); otros escritorios quedarán best-effort.
- El nombre final, icono y licencia del proyecto deben fijarse antes del primer paquete firmado.
