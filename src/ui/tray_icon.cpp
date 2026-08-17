#include "ui.h"

#include "ai_usage/tooltip.h"

#include <wx/image.h>
#include <wx/menu.h>

namespace ai_usage::ui {
namespace {

enum MenuId {
  ShowDashboard = wxID_HIGHEST + 100,
  RefreshAll,
  ToggleOverlayVisibility,
  ToggleOverlayLock,
  OpenSettings,
  ExitApplication
};

wxColour HealthColour(Health health) {
  switch (health) {
    case Health::Healthy: return wxColour(46, 125, 50);
    case Health::Partial: return wxColour(249, 168, 37);
    case Health::Error: return wxColour(198, 40, 40);
    case Health::Disabled: return wxColour(96, 125, 139);
  }
  return *wxBLACK;
}

}  // namespace

TrayIcon::TrayIcon(VoidCallback show, VoidCallback refresh, VoidCallback settings, VoidCallback exit,
                   VoidCallback toggleOverlayVisibility, VoidCallback toggleOverlayLock,
                   OverlayStateCallback overlayState)
    : show_(std::move(show)), refresh_(std::move(refresh)), settings_(std::move(settings)),
      exit_(std::move(exit)), toggleOverlayVisibility_(std::move(toggleOverlayVisibility)),
      toggleOverlayLock_(std::move(toggleOverlayLock)), overlayState_(std::move(overlayState)) {
  Bind(wxEVT_TASKBAR_LEFT_UP, &TrayIcon::OnActivate, this);
  Bind(wxEVT_MENU, [this](wxCommandEvent&) { show_(); }, ShowDashboard);
  Bind(wxEVT_MENU, [this](wxCommandEvent&) { refresh_(); }, RefreshAll);
  Bind(wxEVT_MENU, [this](wxCommandEvent&) {
    if (toggleOverlayVisibility_) toggleOverlayVisibility_();
  }, ToggleOverlayVisibility);
  Bind(wxEVT_MENU, [this](wxCommandEvent&) {
    if (toggleOverlayLock_) toggleOverlayLock_();
  }, ToggleOverlayLock);
  Bind(wxEVT_MENU, [this](wxCommandEvent&) { settings_(); }, OpenSettings);
  Bind(wxEVT_MENU, [this](wxCommandEvent&) { exit_(); }, ExitApplication);
  available_ = SetIcon(MakeStatusIcon(Health::Disabled), wxS("AI Usage Monitor · sin datos"));
}

wxMenu* TrayIcon::CreatePopupMenu() {
  auto* menu = new wxMenu();
  menu->Append(ShowDashboard, "Abrir dashboard");
  menu->Append(RefreshAll, "Refrescar todo");
#if defined(_WIN32) || defined(__linux__)
  const auto overlay = overlayState_ ? overlayState_() : OverlayState{};
  auto* visibility = menu->Append(ToggleOverlayVisibility,
                                  overlay.visible ? "Ocultar overlay" : "Mostrar overlay");
  visibility->Enable(overlay.enabled);
#ifdef _WIN32
  auto* lock = menu->Append(ToggleOverlayLock,
                            overlay.locked ? "Desbloquear overlay" : "Bloquear clics");
  lock->Enable(overlay.enabled);
#endif
#endif
  menu->Append(OpenSettings, wxS("Configuración"));
  menu->AppendSeparator();
  menu->Append(ExitApplication, "Salir");
  return menu;
}

wxIcon TrayIcon::MakeStatusIcon(Health health) const {
  constexpr int size = 32;
  wxImage image(size, size, true);
  image.InitAlpha();
  const auto colour = HealthColour(health);
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      const int dx = x - size / 2;
      const int dy = y - size / 2;
      const bool inside = dx * dx + dy * dy <= 13 * 13;
      image.SetRGB(x, y, colour.Red(), colour.Green(), colour.Blue());
      image.SetAlpha(x, y, inside ? 255 : 0);
    }
  }
  wxBitmap bitmap(image);
  wxIcon icon;
  icon.CopyFromBitmap(bitmap);
  return icon;
}

void TrayIcon::SetSnapshots(const std::vector<ProviderSnapshot>& snapshots) {
  snapshots_ = snapshots;
  available_ = SetIcon(MakeStatusIcon(AggregateHealth(snapshots_)),
                       wxString::FromUTF8(ComposeTooltip(snapshots_, Clock::now())));
}

void TrayIcon::OnActivate(wxTaskBarIconEvent&) { show_(); }

}  // namespace ai_usage::ui
