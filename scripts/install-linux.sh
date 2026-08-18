#!/usr/bin/env bash
# Compila (o reutiliza un build existente) e instala AI Usage Monitor para el
# usuario actual: binario en ~/.local/share, lanzador en el menú, icono y
# autostart de sesión. Es seguro volver a ejecutarlo tras cambios en el
# código: reconstruye de forma incremental y sobreescribe la instalación
# anterior.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
preset="linux-release"
build_dir="$root/build/$preset"

app_id="ai-usage-monitor"
install_dir="$HOME/.local/share/$app_id"
bin_dir="$HOME/.local/bin"
desktop_dir="$HOME/.local/share/applications"
icon_dir="$HOME/.local/share/icons/hicolor/512x512/apps"
autostart_dir="$HOME/.config/autostart"

skip_build=0
run_tests=0
start_now=0
uninstall=0

for arg in "$@"; do
  case "$arg" in
    --skip-build) skip_build=1 ;;
    --test) run_tests=1 ;;
    --start) start_now=1 ;;
    --uninstall) uninstall=1 ;;
    -h|--help)
      cat <<'EOF'
Uso: scripts/install-linux.sh [opciones]

  --skip-build   No compilar; usar el binario ya presente en build/linux-release
  --test         Ejecutar ctest tras compilar
  --start        Lanzar la aplicación al terminar la instalación
  --uninstall    Quitar la instalación y el autostart, y salir
  -h, --help     Mostrar esta ayuda
EOF
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg" >&2
      exit 1
      ;;
  esac
done

if [ "$uninstall" -eq 1 ]; then
  pkill -f "$install_dir/bin/$app_id" 2>/dev/null || true
  rm -rf "$install_dir"
  rm -f "$bin_dir/$app_id" "$desktop_dir/$app_id.desktop" "$autostart_dir/$app_id.desktop" \
        "$icon_dir/$app_id.png"
  command -v gtk-update-icon-cache >/dev/null 2>&1 && \
    gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
  echo "Desinstalado."
  exit 0
fi

if [ "$skip_build" -eq 0 ]; then
  echo "==> Configurando ($preset)"
  cmake --preset "$preset"
  echo "==> Compilando"
  cmake --build --preset "$preset" --parallel
fi

if [ "$run_tests" -eq 1 ]; then
  echo "==> Ejecutando pruebas"
  ctest --preset "$preset" --output-on-failure
fi

built_bin="$build_dir/$app_id"
if [ ! -x "$built_bin" ]; then
  echo "No se encontró el binario compilado en $built_bin" >&2
  exit 1
fi

echo "==> Instalando en $install_dir"
mkdir -p "$install_dir/bin" "$bin_dir" "$desktop_dir" "$icon_dir" "$autostart_dir"
install -m755 "$built_bin" "$install_dir/bin/$app_id"
install -m644 "$root/packaging/linux/$app_id.png" "$icon_dir/$app_id.png"
ln -sf "$install_dir/bin/$app_id" "$bin_dir/$app_id"

menu_desktop="$desktop_dir/$app_id.desktop"
cat > "$menu_desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AI Usage Monitor
Comment=Monitor de uso de proveedores de IA desde la bandeja del sistema
Exec=$install_dir/bin/$app_id
Icon=$app_id
Categories=Utility;Monitor;
Terminal=false
StartupNotify=false
EOF

autostart_desktop="$autostart_dir/$app_id.desktop"
cat > "$autostart_desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AI Usage Monitor
Comment=Monitor de uso de proveedores de IA desde la bandeja del sistema
Exec=$install_dir/bin/$app_id
Icon=$app_id
Categories=Utility;Monitor;
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
Hidden=false
EOF

command -v gtk-update-icon-cache >/dev/null 2>&1 && \
  gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "Aviso: $bin_dir no está en tu PATH. Añádelo en ~/.bashrc o similar para poder ejecutar '$app_id' desde la terminal." ;;
esac

echo "==> Instalación completa."
echo "    Binario:    $install_dir/bin/$app_id"
echo "    Lanzador:   $menu_desktop"
echo "    Autostart:  $autostart_desktop"
echo "    Se abrirá automáticamente en el próximo inicio de sesión."
echo "    Para reinstalar tras cambios en el código: vuelve a ejecutar este script."
echo "    Para desinstalar: scripts/install-linux.sh --uninstall"

if [ "$start_now" -eq 1 ]; then
  echo "==> Iniciando la aplicación"
  nohup "$install_dir/bin/$app_id" >/dev/null 2>&1 &
  disown
fi
