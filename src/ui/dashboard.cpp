#include "ui.h"

#include "app_icon.h"

#include "ai_usage/tooltip.h"

#include <wx/button.h>
#include <wx/checkbox.h>
#include <wx/datetime.h>
#include <wx/panel.h>
#include <wx/scrolwin.h>
#include <wx/sizer.h>
#include <wx/stattext.h>

#include <algorithm>
#include <cmath>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wx/msw/private.h>
#endif

namespace ai_usage::ui {
namespace {

wxString ObservationLabel(const ProviderSnapshot& snapshot) {
  if (snapshot.observedAt == TimePoint{}) return wxS("Sin actualización");
  const auto value = Clock::to_time_t(snapshot.observedAt);
  wxDateTime time(value);
  wxString freshness;
  switch (snapshot.freshness) {
    case Freshness::Fresh: freshness = wxS("Datos actuales"); break;
    case Freshness::Stale: freshness = wxS("Datos anteriores"); break;
    case Freshness::NoData: freshness = wxS("Sin datos"); break;
  }
  return time.FormatISOCombined(' ') + wxS("  ·  ") + freshness;
}

wxString HealthLabel(Health health) {
  switch (health) {
    case Health::Healthy: return wxS("✓ Conectado");
    case Health::Partial: return wxS("! Información parcial");
    case Health::Error: return wxS("× Error");
    case Health::Disabled: return wxS("— Deshabilitado");
  }
  return wxS("— Desconocido");
}

StatusTone HealthTone(Health health) {
  switch (health) {
    case Health::Healthy: return StatusTone::Success;
    case Health::Partial: return StatusTone::Warning;
    case Health::Error: return StatusTone::Error;
    case Health::Disabled: return StatusTone::Neutral;
  }
  return StatusTone::Neutral;
}

wxString ProvenanceLabel(Provenance provenance) {
  switch (provenance) {
    case Provenance::ProviderReported: return wxS("Reportado por el proveedor");
    case Provenance::CliBridge: return wxS("Obtenido del CLI local");
    case Provenance::LocallyObserved: return wxS("Observado localmente");
    case Provenance::Derived: return wxS("Calculado localmente");
  }
  return wxS("Origen desconocido");
}

int PercentValue(const Metric& metric) {
  try {
    const auto value = std::stod(metric.value);
    if (!std::isfinite(value)) return 0;
    return std::clamp(static_cast<int>(std::lround(value)), 0, 100);
  } catch (...) {
    return 0;
  }
}

void RefreshTree(wxWindow* window) {
  if (window == nullptr) return;
  window->Refresh(true);
  for (auto* child : window->GetChildren()) RefreshTree(child);
}

wxString MetricLabel(const Metric& metric) {
  return wxString::FromUTF8(metric.label.empty() ? ToString(metric.kind) : metric.label);
}

wxString MetricMetadata(const Metric& metric) {
  wxString metadata;
  if (metric.resetsAt.has_value()) {
    wxDateTime reset(Clock::to_time_t(*metric.resetsAt));
    metadata = wxS("Reinicia ") + reset.FormatISOCombined(' ');
  }
  if (metric.provenance != Provenance::ProviderReported) {
    if (!metadata.empty()) metadata += wxS("  ·  ");
    metadata += ProvenanceLabel(metric.provenance);
  }
  return metadata;
}

class ProviderCard final : public ModernPanel {
 public:
  ProviderCard(wxWindow* parent, const ProviderSnapshot& snapshot, const PresentationTheme& theme)
      : ModernPanel(parent, theme), snapshot_(snapshot), theme_(theme) {
    SetName(wxS("Tarjeta de proveedor ") + wxString::FromUTF8(snapshot.displayName));
    Build();
  }

 private:
  wxStaticText* Text(const wxString& value, const wxFont& font, const wxColour& colour) {
    auto* text = new wxStaticText(this, wxID_ANY, value);
    text->SetFont(font);
    text->SetForegroundColour(colour);
    text->SetBackgroundColour(theme_.surface);
    return text;
  }

  void AddMetric(wxBoxSizer* root, const Metric& metric) {
    if (metric.kind == MetricKind::RemainingPercent) return;
    auto* metricPanel = new ModernPanel(this, theme_, true);
    metricPanel->SetName(wxS("Métrica ") + MetricLabel(metric));
    auto* layout = new wxBoxSizer(wxVERTICAL);
    auto* label = new wxStaticText(metricPanel, wxID_ANY, MetricLabel(metric));
    label->SetFont(theme_.bodyFont.Bold());
    label->SetForegroundColour(theme_.mutedText);
    label->SetBackgroundColour(theme_.elevated);
    layout->Add(label, 0, wxLEFT | wxRIGHT | wxTOP, theme_.spaceMd);

    const auto formatted = wxString::FromUTF8(FormatMetric(metric));
    auto* value = new wxStaticText(metricPanel, wxID_ANY, formatted);
    value->SetFont(metric.unit == MetricUnit::Percent ? theme_.metricFont : theme_.sectionFont);
    value->SetForegroundColour(theme_.text);
    value->SetBackgroundColour(theme_.elevated);
    value->SetName(MetricLabel(metric) + wxS(" ") + formatted);
    layout->Add(value, 0, wxLEFT | wxRIGHT | wxTOP, theme_.spaceMd);

    if (metric.availability == Availability::Available && metric.unit == MetricUnit::Percent) {
      const auto accessible = MetricLabel(metric) + wxS(": ") + formatted + wxS(" usado");
      auto* progress = new ProgressTrack(metricPanel, PercentValue(metric), accessible, theme_);
      layout->Add(progress, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, theme_.spaceMd);
    }
    const auto metadata = MetricMetadata(metric);
    if (!metadata.empty()) {
      auto* detail = new wxStaticText(metricPanel, wxID_ANY, metadata);
      detail->SetForegroundColour(theme_.mutedText);
      detail->SetBackgroundColour(theme_.elevated);
      detail->Wrap(FromDIP(320));
      layout->Add(detail, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, theme_.spaceMd);
    }
    layout->AddSpacer(theme_.spaceMd);
    metricPanel->SetSizer(layout);
    root->Add(metricPanel, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceLg);
  }

  void Build() {
    auto* root = new wxBoxSizer(wxVERTICAL);
    auto* header = new wxBoxSizer(wxHORIZONTAL);
    auto* name = Text(wxString::FromUTF8(snapshot_.displayName), theme_.sectionFont, theme_.text);
    header->Add(name, 1, wxALIGN_CENTER_VERTICAL);
    header->Add(new StatusPill(this, HealthLabel(snapshot_.health), HealthTone(snapshot_.health), theme_), 0,
                wxALIGN_CENTER_VERTICAL | wxLEFT, theme_.spaceMd);
    root->Add(header, 0, wxEXPAND | wxALL, theme_.spaceLg);

    auto* observed = Text(ObservationLabel(snapshot_), theme_.bodyFont, theme_.mutedText);
    root->Add(observed, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceLg);
    if (!snapshot_.accountLabel.empty()) {
      auto* account = Text(wxS("Cuenta  ·  ") + wxString::FromUTF8(snapshot_.accountLabel), theme_.bodyFont,
                           theme_.mutedText);
      root->Add(account, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceLg);
    }

    const auto visible = [](const Metric& metric) { return metric.kind != MetricKind::RemainingPercent; };
    if (std::none_of(snapshot_.metrics.begin(), snapshot_.metrics.end(), visible)) {
      root->Add(new SemanticNotice(this, wxS("— Métricas no disponibles"), StatusTone::Neutral, theme_), 0,
                wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceLg);
    }
    for (const auto& metric : snapshot_.metrics) AddMetric(root, metric);
    if (snapshot_.error.has_value()) {
      const auto message = snapshot_.error->code == "refreshing"
                               ? wxS("↻ ") + wxString::FromUTF8(snapshot_.error->message)
                               : wxS("Atención  ·  ") + wxString::FromUTF8(snapshot_.error->message);
      const auto tone = snapshot_.error->code == "refreshing" ? StatusTone::Accent : StatusTone::Error;
      root->Add(new SemanticNotice(this, message, tone, theme_), 0,
                wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceLg);
    }
    SetSizer(root);
  }

  ProviderSnapshot snapshot_;
  PresentationTheme theme_;
};

}  // namespace

DashboardFrame::DashboardFrame(VoidCallback refreshAll, VoidCallback openSettings, TopCallback alwaysOnTop)
    : wxFrame(nullptr, wxID_ANY, "AI Usage Monitor", wxDefaultPosition, wxSize(680, 620), wxDEFAULT_FRAME_STYLE),
      refreshAll_(std::move(refreshAll)), openSettings_(std::move(openSettings)), alwaysOnTop_(std::move(alwaysOnTop)) {
  ApplyApplicationIcon(*this);
  SetMinSize(wxSize(FromDIP(440), FromDIP(390)));
  theme_ = ResolveTheme(this);
  SetBackgroundColour(theme_.canvas);
  auto* root = new wxBoxSizer(wxVERTICAL);

  appBar_ = new ModernPanel(this, theme_);
  appBar_->SetName("Barra principal");
  appBarSizer_ = new wxBoxSizer(wxHORIZONTAL);
  title_ = new wxStaticText(appBar_, wxID_ANY, "Uso de IA");
  title_->SetName("Uso de IA");
  title_->SetFont(theme_.titleFont);
  title_->SetForegroundColour(theme_.text);
  title_->SetBackgroundColour(theme_.surface);
  appBarSizer_->Add(title_, 1, wxEXPAND | wxALL | wxALIGN_CENTER_VERTICAL, theme_.spaceLg);

  appActions_ = new wxPanel(appBar_);
  appActions_->SetBackgroundColour(theme_.surface);
  auto* actions = new wxBoxSizer(wxHORIZONTAL);
  refreshButton_ = new wxButton(appActions_, wxID_ANY, wxS("↻  Refrescar todo"));
  refreshButton_->SetName("Refrescar todo");
  refreshButton_->SetToolTip("Actualizar todos los proveedores habilitados");
  refreshButton_->Bind(wxEVT_BUTTON, [this](wxCommandEvent&) { refreshAll_(); });
  StyleButton(refreshButton_, theme_, ButtonTone::Primary);
  actions->Add(refreshButton_, 0, wxALL, theme_.spaceXs);
  settingsButton_ = new wxButton(appActions_, wxID_ANY, wxS("Configuración"));
  settingsButton_->SetName(wxS("Configuración"));
  settingsButton_->Bind(wxEVT_BUTTON, [this](wxCommandEvent&) { openSettings_(); });
  StyleButton(settingsButton_, theme_, ButtonTone::Secondary);
  actions->Add(settingsButton_, 0, wxALL, theme_.spaceXs);
  alwaysOnTopCheck_ = new wxCheckBox(appActions_, wxID_ANY, "Siempre visible");
  alwaysOnTopCheck_->SetName("Siempre visible");
  alwaysOnTopCheck_->SetToolTip("Mantener este dashboard por encima de ventanas normales");
  alwaysOnTopCheck_->SetForegroundColour(theme_.text);
  alwaysOnTopCheck_->SetBackgroundColour(theme_.surface);
  alwaysOnTopCheck_->Bind(wxEVT_CHECKBOX, [this](wxCommandEvent&) { alwaysOnTop_(alwaysOnTopCheck_->GetValue()); });
  actions->Add(alwaysOnTopCheck_, 0, wxALIGN_CENTER_VERTICAL | wxALL, theme_.spaceSm);
  appActions_->SetSizer(actions);
  appBarSizer_->Add(appActions_, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceMd);
  appBar_->SetSizer(appBarSizer_);
  root->Add(appBar_, 0, wxEXPAND | wxALL, theme_.spaceMd);

  environmentNotice_ = new SemanticNotice(
      this, wxS("! Este escritorio no ofrece una bandeja compatible. El dashboard seguirá disponible como ventana normal."),
      StatusTone::Warning, theme_);
  environmentNotice_->SetName("Aviso de bandeja no disponible");
  environmentNotice_->Hide();
  root->Add(environmentNotice_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);

  auto* scroll = new wxScrolledWindow(this, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxVSCROLL | wxBORDER_NONE);
  scroll->SetName("Lista de proveedores");
  scroll->SetBackgroundColour(theme_.canvas);
  scroll->SetScrollRate(0, FromDIP(12));
  cardsPanel_ = scroll;
  cardsSizer_ = new wxBoxSizer(wxVERTICAL);
  cardsPanel_->SetSizer(cardsSizer_);
  root->Add(scroll, 1, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  SetSizer(root);
  Bind(wxEVT_CLOSE_WINDOW, &DashboardFrame::OnClose, this);
  Bind(wxEVT_SYS_COLOUR_CHANGED, &DashboardFrame::OnSystemColourChanged, this);
  Bind(wxEVT_SIZE, &DashboardFrame::OnSize, this);
  UpdateResponsiveLayout();
}

void DashboardFrame::SetSnapshots(const std::vector<ProviderSnapshot>& snapshots) {
  snapshots_ = snapshots;
  RebuildCards();
}

void DashboardFrame::ApplyAlwaysOnTop(bool enabled) {
  alwaysOnTopCheck_->SetValue(enabled);
#ifdef _WIN32
  SetWindowPos(GetHwnd(), enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
#else
  long style = GetWindowStyleFlag();
  if (enabled) style |= wxSTAY_ON_TOP;
  else style &= ~wxSTAY_ON_TOP;
  SetWindowStyleFlag(style);
#endif
}

void DashboardFrame::EnableTrayFallback() {
  environmentNotice_->Show();
  Layout();
  Show();
  Raise();
}

void DashboardFrame::ApplyPresentationTheme() {
  theme_ = ResolveTheme(this);
  SetBackgroundColour(theme_.canvas);
  appBar_->SetPresentationTheme(theme_);
  title_->SetFont(theme_.titleFont);
  title_->SetForegroundColour(theme_.text);
  title_->SetBackgroundColour(theme_.surface);
  appActions_->SetBackgroundColour(theme_.surface);
  StyleButton(refreshButton_, theme_, ButtonTone::Primary);
  StyleButton(settingsButton_, theme_, ButtonTone::Secondary);
  alwaysOnTopCheck_->SetForegroundColour(theme_.text);
  alwaysOnTopCheck_->SetBackgroundColour(theme_.surface);
  environmentNotice_->SetPresentationTheme(theme_);
  cardsPanel_->SetBackgroundColour(theme_.canvas);
  RebuildCards();
  Layout();
  Refresh();
}

void DashboardFrame::UpdateResponsiveLayout() {
  const auto logicalWidth = ToDIP(GetClientSize()).x;
  const bool compact = UseCompactLayout(logicalWidth);
  if (compact == compactLayout_) return;
  compactLayout_ = compact;
  appBarSizer_->Clear(false);
  appBarSizer_->SetOrientation(compact ? wxVERTICAL : wxHORIZONTAL);
  appBarSizer_->Add(title_, compact ? 0 : 1,
                    (compact ? wxEXPAND | wxLEFT | wxRIGHT | wxTOP
                             : wxEXPAND | wxALL | wxALIGN_CENTER_VERTICAL),
                    theme_.spaceLg);
  appBarSizer_->Add(appActions_, 0,
                    compact ? wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM
                            : wxALIGN_CENTER_VERTICAL | wxRIGHT,
                    compact ? theme_.spaceLg : theme_.spaceMd);
  appActions_->GetSizer()->Layout();
  appBar_->Layout();
  Layout();
}

void DashboardFrame::OnSystemColourChanged(wxSysColourChangedEvent& event) {
  event.Skip();
  ApplyPresentationTheme();
}

void DashboardFrame::OnSize(wxSizeEvent& event) {
  UpdateResponsiveLayout();
  cardsPanel_->Layout();
  cardsPanel_->FitInside();
  RefreshTree(appBar_);
  RefreshTree(cardsPanel_);
  Refresh(true);
  event.Skip();
}

void DashboardFrame::RebuildCards() {
  Freeze();
  cardsSizer_->Clear(true);
  if (snapshots_.empty()) {
    cardsSizer_->Add(new SemanticNotice(cardsPanel_, wxS("— No hay proveedores configurados. Abra Configuración."),
                                        StatusTone::Neutral, theme_),
                     0, wxEXPAND | wxALL, theme_.spaceSm);
  }
  for (const auto& snapshot : snapshots_) {
    cardsSizer_->Add(new ProviderCard(cardsPanel_, snapshot, theme_), 0, wxEXPAND | wxALL, theme_.spaceSm);
  }
  cardsPanel_->Layout();
  cardsPanel_->FitInside();
  Layout();
  Thaw();
}

void DashboardFrame::OnClose(wxCloseEvent& event) {
  if (event.CanVeto()) {
    event.Veto();
    Hide();
  } else {
    event.Skip();
  }
}

}  // namespace ai_usage::ui
