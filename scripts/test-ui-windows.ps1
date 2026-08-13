param(
  [string]$Executable = (Join-Path $PSScriptRoot '..\build\windows-release\ai-usage-monitor.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class AiUsageNativeUi {
  public delegate bool EnumProc(IntPtr window, IntPtr state);

  [StructLayout(LayoutKind.Sequential)]
  public struct Rect { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct Point { public int X, Y; }

  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr state);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr state);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int length);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder text, int length);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr word, IntPtr data);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr word, IntPtr data);
  [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr word, IntPtr data, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr word, StringBuilder data);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr word, string data);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr window, string text);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr window);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr window);
  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
  [DllImport("user32.dll", EntryPoint = "GetClassLongPtrW")] static extern IntPtr GetClassLongPtr(IntPtr window, int index);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr window, bool altTab);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint first, uint second, bool attach);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr window);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] static extern bool GetLayeredWindowAttributes(IntPtr window, out uint colour, out byte alpha, out uint flags);

  public static long ExtendedStyle(IntPtr window) { return GetWindowLongPtr(window, -20).ToInt64(); }
  public static bool HasApplicationIcon(IntPtr window) {
    foreach (int kind in new int[] { 1, 0, 2 }) {
      if (SendMessage(window, 0x007F, new IntPtr(kind), IntPtr.Zero) != IntPtr.Zero) return true;
    }
    return GetClassLongPtr(window, -14) != IntPtr.Zero || GetClassLongPtr(window, -34) != IntPtr.Zero;
  }
  public static int LayeredAlpha(IntPtr window) {
    uint colour, flags;
    byte alpha;
    return GetLayeredWindowAttributes(window, out colour, out alpha, out flags) ? alpha : -1;
  }
  public static void Click() {
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
  public static IntPtr WindowAt(int x, int y) { return WindowFromPoint(new Point { X = x, Y = y }); }
  public static bool ForceForeground(IntPtr window) {
    uint ignored;
    uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), out ignored);
    uint currentThread = GetCurrentThreadId();
    AttachThreadInput(currentThread, foregroundThread, true);
    ShowWindow(window, 5);
    BringWindowToTop(window);
    bool result = SetForegroundWindow(window);
    AttachThreadInput(currentThread, foregroundThread, false);
    return result;
  }

  public static IntPtr[] Children(IntPtr parent) {
    var result = new List<IntPtr>();
    EnumChildWindows(parent, (window, state) => { result.Add(window); return true; }, IntPtr.Zero);
    return result.ToArray();
  }

  public static IntPtr[] TopLevelFor(uint processId) {
    var result = new List<IntPtr>();
    EnumWindows((window, state) => {
      uint owner;
      GetWindowThreadProcessId(window, out owner);
      if (owner == processId) result.Add(window);
      return true;
    }, IntPtr.Zero);
    return result.ToArray();
  }

  public static string Text(IntPtr window) {
    var value = new StringBuilder(512);
    GetWindowText(window, value, value.Capacity);
    return value.ToString();
  }

  public static string ClassName(IntPtr window) {
    var value = new StringBuilder(128);
    GetClassName(window, value, value.Capacity);
    return value.ToString();
  }

  public static string ControlText(IntPtr window) {
    int length = SendMessage(window, 0x000E, IntPtr.Zero, IntPtr.Zero).ToInt32();
    var value = new StringBuilder(length + 1);
    SendMessage(window, 0x000D, new IntPtr(value.Capacity), value);
    return value.ToString();
  }

  public static void SetControlText(IntPtr window, string value) {
    SendMessage(window, 0x000C, IntPtr.Zero, value);
  }
}
'@

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Get-ChildrenByText([IntPtr]$Parent) {
  $result = @{}
  foreach ($window in [AiUsageNativeUi]::Children($Parent)) {
    $label = [AiUsageNativeUi]::Text($window)
    if ($label -and -not $result.ContainsKey($label)) { $result[$label] = $window }
  }
  return $result
}

function Assert-Within([IntPtr]$Child, [AiUsageNativeUi+Rect]$ParentRect, [string]$Name) {
  $rect = New-Object AiUsageNativeUi+Rect
  Assert-True ([AiUsageNativeUi]::GetWindowRect($Child, [ref]$rect)) "No se obtuvo la geometria de $Name"
  Assert-True ($rect.Left -ge $ParentRect.Left -and $rect.Right -le $ParentRect.Right) "$Name queda recortado horizontalmente"
  Assert-True ($rect.Top -ge $ParentRect.Top -and $rect.Bottom -le $ParentRect.Bottom) "$Name queda recortado verticalmente"
}

function Assert-StableWindowTitles([uint32]$ProcessId) {
  $titles = @()
  foreach ($window in [AiUsageNativeUi]::TopLevelFor($ProcessId)) {
    $title = [AiUsageNativeUi]::Text($window)
    if (-not [string]::IsNullOrWhiteSpace($title)) { $titles += $title }
  }
  Assert-True ($titles.Count -gt 0) 'La aplicacion no expuso ningun titulo nativo identificable.'
  foreach ($marker in @('Codex', 'Claude', 'DeepSeek', 'cuenta@example.com', '28%', '54%', '72%',
                         '42.50', 'reinicia', 'Actualizando cuotas')) {
    foreach ($title in $titles) {
      Assert-True (-not $title.Contains($marker)) "El titulo nativo '$title' expuso el dato dinamico '$marker'."
    }
  }
  return $titles
}

$process = $null
try {
  $refreshLabel = "$([char]0x21BB)  Refrescar todo"
  $configurationLabel = "Configuraci$([char]0x00F3)n"
  $connectionLabel = "Conexi$([char]0x00F3)n"
  $verificationLabel = "Verificaci$([char]0x00F3)n"
  $testConnectionLabel = "Probar conexi$([char]0x00F3)n"
  $claudeSessionLabel = "Claude sesi$([char]0x00F3)n usado"
  $resolvedExecutable = (Resolve-Path $Executable).Path
  $env:AI_USAGE_UI_FIXTURES = '1'
  $env:AI_USAGE_UI_OVERLAY = '1'
  $env:AI_USAGE_UI_THEME = 'light'
  $env:AI_USAGE_DATA_DIR = Join-Path (Split-Path $resolvedExecutable) 'ui-smoke-data'
  New-Item -ItemType Directory -Force -Path $env:AI_USAGE_DATA_DIR | Out-Null
  $initialSettings = '{"schemaVersion":1,"refreshMinutes":5,"alwaysOnTop":false,"overlay":{"enabled":true,"visible":true,"opacity":78,"locked":false,"corner":"top-right","monitor":"","margin":12,"suppressFullscreen":true},"providers":[]}'
  Set-Content -LiteralPath (Join-Path $env:AI_USAGE_DATA_DIR 'settings.json') -Value $initialSettings -Encoding UTF8
  $process = Start-Process -FilePath $resolvedExecutable -PassThru
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 200
    $process.Refresh()
    if ($process.HasExited -or $process.MainWindowHandle -ne 0) { break }
  }
  Assert-True (-not $process.HasExited -and $process.MainWindowHandle -ne 0) 'El dashboard no inicio.'
  $dashboardWindow = $process.MainWindowHandle
  Assert-True ([AiUsageNativeUi]::HasApplicationIcon($dashboardWindow)) 'El dashboard no expuso el icono de aplicacion.'

  [AiUsageNativeUi]::SetWindowPos($dashboardWindow, [IntPtr]::Zero, 80, 60, 460, 700, 0x40) | Out-Null
  Start-Sleep -Milliseconds 700
  $dashboardRect = New-Object AiUsageNativeUi+Rect
  [AiUsageNativeUi]::GetWindowRect($dashboardWindow, [ref]$dashboardRect) | Out-Null
  $dashboard = Get-ChildrenByText $dashboardWindow
  foreach ($label in @($refreshLabel, $configurationLabel, 'Siempre visible', 'Codex', '28%',
                        'Ventana semanal', $claudeSessionLabel)) {
    Assert-True $dashboard.ContainsKey($label) "Falta el control o texto '$label' en el dashboard."
  }
  foreach ($label in @($refreshLabel, $configurationLabel, 'Siempre visible')) {
    Assert-Within $dashboard[$label] $dashboardRect $label
  }

  $overlay = [IntPtr]::Zero
  foreach ($window in [AiUsageNativeUi]::TopLevelFor([uint32]$process.Id)) {
    $candidateStyle = [AiUsageNativeUi]::ExtendedStyle($window)
    if ([AiUsageNativeUi]::Text($window) -eq 'AI Usage Monitor' -and
        ($candidateStyle -band 0x80) -ne 0 -and ($candidateStyle -band 0x08000000) -ne 0) {
      $overlay = $window
    }
  }
  Assert-True ($overlay -ne [IntPtr]::Zero -and [AiUsageNativeUi]::IsWindowVisible($overlay)) 'El overlay no apareció.'
  $overlayText = [AiUsageNativeUi]::Text($overlay)
  Assert-True ($overlayText -eq 'AI Usage Monitor') "Titulo nativo inesperado para el overlay: '$overlayText'."
  $initialTitles = @(Assert-StableWindowTitles ([uint32]$process.Id))
  Assert-True ($initialTitles -contains 'AI Usage Monitor') 'No se encontro el titulo conciso de la aplicacion.'
  $liveSettings = Get-Content -LiteralPath (Join-Path $env:AI_USAGE_DATA_DIR 'settings.json') -Raw | ConvertFrom-Json
  Assert-True ($liveSettings.overlay.suppressFullscreen) 'La supresión de pantalla completa no quedó activa en el fixture.'
  $style = [AiUsageNativeUi]::ExtendedStyle($overlay)
  Assert-True (($style -band 0x80) -ne 0 -and ($style -band 0x08000000) -ne 0 -and ($style -band 0x40000) -eq 0) 'El overlay no conserva estilos tool-window/no-activate.'
  $defaultAlpha = [AiUsageNativeUi]::LayeredAlpha($overlay)
  Assert-True ($defaultAlpha -ge 195 -and $defaultAlpha -le 201) "Opacidad inicial inesperada: $defaultAlpha"
  $overlayRect = New-Object AiUsageNativeUi+Rect
  [AiUsageNativeUi]::GetWindowRect($overlay, [ref]$overlayRect) | Out-Null
  [AiUsageNativeUi]::SetCursorPos([int](($overlayRect.Left + $overlayRect.Right) / 2), [int](($overlayRect.Top + $overlayRect.Bottom) / 2)) | Out-Null
  [AiUsageNativeUi]::SendMessage($overlay, 0x02A1, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  $hoverAlpha = [AiUsageNativeUi]::LayeredAlpha($overlay)
  Assert-True ($hoverAlpha -ge 242) "La opacidad no aumentó al pasar el puntero por el overlay desbloqueado: $hoverAlpha."
  [AiUsageNativeUi]::SetCursorPos(5, 5) | Out-Null
  Start-Sleep -Milliseconds 300

  [AiUsageNativeUi]::PostMessage($overlay, 0x0312, [IntPtr]0xA117, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 200
  Assert-True (([AiUsageNativeUi]::ExtendedStyle($overlay) -band 0x20) -ne 0) 'Ctrl+Alt+U no activó el modo click-through.'
  [AiUsageNativeUi]::PostMessage($overlay, 0x0312, [IntPtr]0xA117, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 200
  Assert-True (([AiUsageNativeUi]::ExtendedStyle($overlay) -band 0x20) -eq 0) 'Ctrl+Alt+U no recuperó el overlay.'

  $underlying = New-Object System.Windows.Forms.Form
  $underlying.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $underlying.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $underlying.TopMost = $true
  $underlying.Bounds = [System.Drawing.Rectangle]::new($overlayRect.Left, $overlayRect.Top,
                                                        $overlayRect.Right - $overlayRect.Left,
                                                        $overlayRect.Bottom - $overlayRect.Top)
  $underlying.BackColor = [System.Drawing.Color]::White
  $underlying.Show()
  $underlying.Activate()
  [System.Windows.Forms.Application]::DoEvents()
  [AiUsageNativeUi]::SetWindowPos($overlay, [IntPtr](-1), 0, 0, 0, 0, 0x13) | Out-Null
  [AiUsageNativeUi]::PostMessage($overlay, 0x0312, [IntPtr]0xA117, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 200
  $testX = [int](($overlayRect.Left + $overlayRect.Right) / 2)
  $testY = [int](($overlayRect.Top + $overlayRect.Bottom) / 2)
  Assert-True (([AiUsageNativeUi]::ExtendedStyle($overlay) -band 0x20) -ne 0) 'El overlay no estaba bloqueado para probar click-through.'
  Assert-True ([AiUsageNativeUi]::WindowAt($testX, $testY) -eq $underlying.Handle) 'El hit-test click-through no alcanzó la ventana inferior.'
  [AiUsageNativeUi]::PostMessage($overlay, 0x0312, [IntPtr]0xA117, [IntPtr]::Zero) | Out-Null
  $underlying.Close()
  $underlying.Dispose()

  $fullscreen = New-Object System.Windows.Forms.Form
  $fullscreen.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
  $fullscreen.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $fullscreen.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $fullscreen.Show()
  [AiUsageNativeUi]::SetWindowPos($fullscreen.Handle, [IntPtr]::Zero, 0, 0,
                                  [AiUsageNativeUi]::GetSystemMetrics(0),
                                  [AiUsageNativeUi]::GetSystemMetrics(1), 0x40) | Out-Null
  $fullscreen.Activate()
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 500
  $fullscreenRect = New-Object AiUsageNativeUi+Rect
  [AiUsageNativeUi]::GetWindowRect($fullscreen.Handle, [ref]$fullscreenRect) | Out-Null
  $foregroundTest = [AiUsageNativeUi]::GetForegroundWindow()
  $fullscreenWasTested = $foregroundTest -eq $fullscreen.Handle
  if ($fullscreenWasTested) {
    Start-Sleep -Milliseconds 300
    Assert-True (-not [AiUsageNativeUi]::IsWindowVisible($overlay)) 'El overlay no se ocultó ante la ventana de pantalla completa.'
  } else {
    Write-Warning "La política de foreground de Windows impidió la prueba integrada de pantalla completa; la geometría se valida en unit tests."
  }
  $fullscreen.Close()
  $fullscreen.Dispose()
  Start-Sleep -Milliseconds 500
  if ($fullscreenWasTested) {
    Assert-True ([AiUsageNativeUi]::IsWindowVisible($overlay)) 'El overlay no reapareció al salir de pantalla completa.'
  }

  $foregroundBeforeRefresh = [AiUsageNativeUi]::GetForegroundWindow()
  [AiUsageNativeUi]::PostMessage($dashboard[$refreshLabel], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 200
  Assert-True ([AiUsageNativeUi]::GetForegroundWindow() -eq $foregroundBeforeRefresh) 'Actualizar snapshots hizo que el overlay robara el foco.'
  $updatedTitles = @(Assert-StableWindowTitles ([uint32]$process.Id))
  Assert-True ($updatedTitles -contains 'AI Usage Monitor') 'El titulo conciso cambio despues de actualizar snapshots.'
  [AiUsageNativeUi]::PostMessage($dashboard['Siempre visible'], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  [AiUsageNativeUi]::PostMessage($dashboard[$configurationLabel], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Seconds 1

  $dialog = [IntPtr]::Zero
  foreach ($window in [AiUsageNativeUi]::TopLevelFor([uint32]$process.Id)) {
    if ([AiUsageNativeUi]::Text($window) -like "$configurationLabel*") { $dialog = $window }
  }
  Assert-True ($dialog -ne [IntPtr]::Zero) 'Preferencias no se abrio mediante activacion nativa.'
  Assert-True ([AiUsageNativeUi]::HasApplicationIcon($dialog)) 'Preferencias no expuso el icono de aplicacion.'
  [AiUsageNativeUi]::SetWindowPos($dialog, [IntPtr]::Zero, 120, 40, 620, 740, 0x40) | Out-Null
  Start-Sleep -Milliseconds 700
  $preferences = Get-ChildrenByText $dialog
  foreach ($label in @('Preferencias generales', 'Overlay minimalista', 'Habilitar', 'Mostrar', 'Bloquear clics',
                        'Ocultar al usar una aplicación a pantalla completa', 'Proveedores', $connectionLabel, $verificationLabel,
                        $testConnectionLabel, 'Abrir carpeta', 'Cancelar', 'Guardar cambios')) {
    Assert-True $preferences.ContainsKey($label) "Falta '$label' en Preferencias."
  }

  $listBox = [AiUsageNativeUi]::Children($dialog) |
    Where-Object { [AiUsageNativeUi]::ClassName($_) -eq 'ListBox' } |
    Select-Object -First 1
  Assert-True ($null -ne $listBox) 'No se encontro la navegacion de proveedores.'
  [AiUsageNativeUi]::PostMessage($listBox, 0x0100, [IntPtr]0x28, [IntPtr]::Zero) | Out-Null
  [AiUsageNativeUi]::PostMessage($listBox, 0x0101, [IntPtr]0x28, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 300
  $selectedProvider = [AiUsageNativeUi]::SendMessage($listBox, 0x0188, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
  Assert-True ($selectedProvider -eq 1) 'La navegacion no selecciono el segundo proveedor.'

  $claudeName = [AiUsageNativeUi]::Children($dialog) |
    Where-Object { [AiUsageNativeUi]::ClassName($_) -eq 'Edit' -and [AiUsageNativeUi]::ControlText($_) -eq 'Claude' } |
    Select-Object -First 1
  $editValues = [AiUsageNativeUi]::Children($dialog) |
    Where-Object { [AiUsageNativeUi]::ClassName($_) -eq 'Edit' } |
    ForEach-Object { [AiUsageNativeUi]::ControlText($_) }
  Assert-True ($null -ne $claudeName) "Cambiar a Claude no actualizo el editor: $($editValues -join ', ')"
  [AiUsageNativeUi]::SetControlText($claudeName, 'Claude editado')
  Assert-True ([AiUsageNativeUi]::ControlText($claudeName) -eq 'Claude editado') 'No se pudo preparar la edicion pendiente.'
  [AiUsageNativeUi]::PostMessage($dialog, 0x0015, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 300
  Assert-True ([AiUsageNativeUi]::ControlText($claudeName) -eq 'Claude editado') 'El cambio de tema perdio una edicion pendiente.'

  [AiUsageNativeUi]::PostMessage($preferences[$testConnectionLabel], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 300
  $process.Refresh()
  Assert-True (-not $process.HasExited) 'La prueba de conexion cerro inesperadamente la aplicacion.'
  [AiUsageNativeUi]::PostMessage($preferences['Cancelar'], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 300
  $process.Refresh()
  Assert-True (-not $process.HasExited) 'Cancelar Preferencias cerro el dashboard.'

  $savedSettings = Get-Content -LiteralPath (Join-Path $env:AI_USAGE_DATA_DIR 'settings.json') -Raw | ConvertFrom-Json
  Assert-True ($savedSettings.overlay.visible -and $savedSettings.overlay.opacity -eq 78 -and
               $savedSettings.overlay.suppressFullscreen) 'Las preferencias del overlay no se conservaron correctamente.'

  $queryResult = [IntPtr]::Zero
  $querySent = [AiUsageNativeUi]::SendMessageTimeout($dashboardWindow, 0x0011, [IntPtr]::Zero, [IntPtr]::Zero,
                                                     0x0002, 2000, [ref]$queryResult)
  Assert-True ($querySent -ne [IntPtr]::Zero) 'La consulta de fin de sesion no respondio dentro del limite.'
  Assert-True ($queryResult -ne [IntPtr]::Zero) 'La aplicacion veto la consulta de fin de sesion de Windows.'
  Start-Sleep -Milliseconds 200
  $process.Refresh()
  Assert-True (-not $process.HasExited) 'La fase consultiva termino la aplicacion antes de la confirmacion de Windows.'
  Assert-StableWindowTitles ([uint32]$process.Id) | Out-Null

  $cancelResult = [IntPtr]::Zero
  $cancelSent = [AiUsageNativeUi]::SendMessageTimeout($dashboardWindow, 0x0016, [IntPtr]::Zero, [IntPtr]::Zero,
                                                      0x0002, 2000, [ref]$cancelResult)
  Assert-True ($cancelSent -ne [IntPtr]::Zero) 'No se pudo simular la cancelacion del fin de sesion.'
  [AiUsageNativeUi]::PostMessage($dashboard[$refreshLabel], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 200
  $process.Refresh()
  Assert-True (-not $process.HasExited) 'La aplicacion no continuo operativa tras cancelar el fin de sesion.'

  [AiUsageNativeUi]::PostMessage($dashboardWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 200
  $process.Refresh()
  Assert-True (-not $process.HasExited) 'Cerrar normalmente el dashboard termino la aplicacion residente.'
  Assert-True (-not [AiUsageNativeUi]::IsWindowVisible($dashboardWindow)) 'Cerrar normalmente el dashboard no lo oculto.'
  [AiUsageNativeUi]::ForceForeground($dashboardWindow) | Out-Null
  Assert-True ([AiUsageNativeUi]::IsWindowVisible($dashboardWindow)) 'No se pudo restaurar el dashboard para probar el fin de sesion.'
  Assert-True ([AiUsageNativeUi]::IsWindowVisible($overlay)) 'El overlay no permanecio activo antes del fin de sesion.'

  $finalQueryResult = [IntPtr]::Zero
  $finalQuerySent = [AiUsageNativeUi]::SendMessageTimeout($dashboardWindow, 0x0011, [IntPtr]::Zero, [IntPtr]::Zero,
                                                          0x0002, 2000, [ref]$finalQueryResult)
  Assert-True ($finalQuerySent -ne [IntPtr]::Zero -and $finalQueryResult -ne [IntPtr]::Zero) 'La consulta final de sesion no fue aceptada.'
  Assert-True ([AiUsageNativeUi]::PostMessage($dashboardWindow, 0x0016, [IntPtr]1, [IntPtr]::Zero)) 'No se pudo confirmar el fin de sesion.'
  Assert-True ($process.WaitForExit(5000)) 'La aplicacion no termino dentro de 5 segundos tras WM_ENDSESSION.'

  Write-Output 'Windows UI smoke test passed: stable titles, overlay behavior, settings, close-to-tray and session shutdown lifecycle.'
}
finally {
  if ($process) {
    $process.Refresh()
    if (-not $process.HasExited) { Stop-Process -Id $process.Id }
  }
}
