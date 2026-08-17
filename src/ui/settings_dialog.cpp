#include "ui.h"

#include "app_icon.h"

#include "ai_usage/providers.h"

#include <wx/button.h>
#include <wx/filepicker.h>
#include <wx/msgdlg.h>
#include <wx/sizer.h>
#include <wx/statline.h>
#include <wx/utils.h>
#include <wx/weakref.h>

#include <chrono>
#include <sstream>
#include <thread>

namespace ai_usage::ui {
namespace {

constexpr int AddProviderId = wxID_HIGHEST + 200;
constexpr int RemoveProviderId = wxID_HIGHEST + 201;
constexpr int TestProviderId = wxID_HIGHEST + 202;
constexpr int OpenDataId = wxID_HIGHEST + 203;

const wxArrayString& KindLabels() {
  static const wxArrayString labels{"Codex", "Claude /usage local", "DeepSeek", "OpenAI-compatible"};
  return labels;
}

ProviderKind KindFromIndex(int index) {
  switch (index) {
    case 0: return ProviderKind::Codex;
    case 1: return ProviderKind::ClaudeSubscription;
    case 2: return ProviderKind::DeepSeek;
    default: return ProviderKind::OpenAiCompatible;
  }
}

int IndexFromKind(ProviderKind kind) {
  switch (kind) {
    case ProviderKind::Codex: return 0;
    case ProviderKind::ClaudeSubscription: return 1;
    case ProviderKind::DeepSeek: return 2;
    case ProviderKind::OpenAiCompatible: return 3;
  }
  return 3;
}

std::string NewId(ProviderKind kind) {
  const auto ticks = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now().time_since_epoch()).count();
  return ToString(kind) + "-" + std::to_string(ticks);
}

wxTextCtrl* AddTextRow(wxWindow* parent, wxFlexGridSizer* grid, const wxString& label, long style = 0,
                       wxStaticText** labelControl = nullptr) {
  auto* text = new wxStaticText(parent, wxID_ANY, label);
  if (labelControl != nullptr) *labelControl = text;
  grid->Add(text, 0, wxALIGN_CENTER_VERTICAL | wxALL, 4);
  auto* control = new wxTextCtrl(parent, wxID_ANY, {}, wxDefaultPosition, wxDefaultSize, style);
  grid->Add(control, 1, wxEXPAND | wxALL, 4);
  return control;
}

void RefreshTree(wxWindow* window) {
  if (window == nullptr) return;
  window->Refresh(true);
  for (auto* child : window->GetChildren()) RefreshTree(child);
}

}  // namespace

SettingsDialog::SettingsDialog(wxWindow* parent, Settings& settings, const DataPaths& paths, IHttpClient& http,
                               IProcessRunner& process, ISecretStore& secrets, std::string overlayHotkeyStatus)
    : wxDialog(parent, wxID_ANY, wxS("Configuración · AI Usage Monitor"), wxDefaultPosition, wxSize(880, 700),
               wxDEFAULT_DIALOG_STYLE | wxRESIZE_BORDER),
      settings_(settings), working_(settings), paths_(paths), http_(http), process_(process), secrets_(secrets),
      overlayHotkeyStatus_(std::move(overlayHotkeyStatus)) {
  ApplyApplicationIcon(*this);
  SetMinSize(wxSize(FromDIP(540), FromDIP(500)));
  theme_ = ResolveTheme(this);
  BuildUi();
  RefreshList(working_.providers.empty() ? -1 : 0);
}

void SettingsDialog::BuildUi() {
  SetBackgroundColour(theme_.canvas);
  auto* root = new wxBoxSizer(wxVERTICAL);

  globalPanel_ = new ModernPanel(this, theme_);
  globalPanel_->SetName("Preferencias generales");
  auto* global = new wxBoxSizer(wxVERTICAL);
  auto* globalTitle = new wxStaticText(globalPanel_, wxID_ANY, "Preferencias generales");
  globalTitle->SetFont(theme_.sectionFont);
  global->Add(globalTitle, 0, wxLEFT | wxRIGHT | wxTOP, theme_.spaceLg);
  auto* preferenceRow = new wxBoxSizer(wxHORIZONTAL);
  preferenceRow->Add(new wxStaticText(globalPanel_, wxID_ANY, "Refresco (minutos)"), 0,
                     wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceSm);
  refreshMinutes_ = new wxSpinCtrl(globalPanel_, wxID_ANY);
  refreshMinutes_->SetRange(1, 60);
  refreshMinutes_->SetValue(working_.refreshMinutes);
  refreshMinutes_->SetName("Intervalo de refresco en minutos");
  preferenceRow->Add(refreshMinutes_, 0, wxRIGHT, theme_.spaceLg);
  alwaysOnTop_ = new wxCheckBox(globalPanel_, wxID_ANY, "Siempre visible");
  alwaysOnTop_->SetValue(working_.alwaysOnTop);
  alwaysOnTop_->SetName("Siempre visible");
  preferenceRow->Add(alwaysOnTop_, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceLg);
  preferenceRow->AddStretchSpacer();
  preferenceRow->Add(new wxStaticText(globalPanel_, wxID_ANY,
                                      paths_.portable ? wxS("Datos · portable") : wxS("Datos · perfil de usuario")),
                     0, wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceSm);
  openDataButton_ = new wxButton(globalPanel_, OpenDataId, "Abrir carpeta");
  openDataButton_->SetName("Abrir carpeta de datos");
  preferenceRow->Add(openDataButton_, 0, wxALIGN_CENTER_VERTICAL);
  global->Add(preferenceRow, 0, wxEXPAND | wxALL, theme_.spaceLg);
  globalPanel_->SetSizer(global);
  root->Add(globalPanel_, 0, wxEXPAND | wxALL, theme_.spaceMd);

#if defined(_WIN32) || defined(__linux__)
  auto* overlayPanel = new ModernPanel(this, theme_);
#ifdef _WIN32
  overlayPanel->SetName("Overlay minimalista de Windows");
#else
  overlayPanel->SetName("Overlay minimalista de Linux");
#endif
  auto* overlaySizer = new wxBoxSizer(wxVERTICAL);
  auto* overlayTitle = new wxStaticText(overlayPanel, wxID_ANY, "Overlay minimalista");
  overlayTitle->SetFont(theme_.sectionFont);
  overlaySizer->Add(overlayTitle, 0, wxLEFT | wxRIGHT | wxTOP, theme_.spaceLg);
  auto* overlayRow = new wxBoxSizer(wxHORIZONTAL);
  overlayEnabled_ = new wxCheckBox(overlayPanel, wxID_ANY, "Habilitar");
  overlayEnabled_->SetValue(working_.overlay.enabled);
  overlayVisible_ = new wxCheckBox(overlayPanel, wxID_ANY, "Mostrar");
  overlayVisible_->SetValue(working_.overlay.visible);
  overlayRow->Add(overlayEnabled_, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceLg);
  overlayRow->Add(overlayVisible_, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceLg);
#ifdef _WIN32
  overlayLocked_ = new wxCheckBox(overlayPanel, wxID_ANY, "Bloquear clics");
  overlayLocked_->SetValue(working_.overlay.locked);
  overlayRow->Add(overlayLocked_, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceLg);
#endif
  overlayRow->Add(new wxStaticText(overlayPanel, wxID_ANY, "Opacidad"), 0,
                  wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceSm);
  overlayOpacity_ = new wxSpinCtrl(overlayPanel, wxID_ANY);
  overlayOpacity_->SetRange(50, 100);
  overlayOpacity_->SetValue(working_.overlay.opacity);
  overlayOpacity_->SetName("Opacidad del overlay en porcentaje");
  overlayRow->Add(overlayOpacity_, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceLg);
  overlayRow->Add(new wxStaticText(overlayPanel, wxID_ANY, "Esquina"), 0,
                  wxALIGN_CENTER_VERTICAL | wxRIGHT, theme_.spaceSm);
  const wxArrayString cornerLabels{"Superior izquierda", "Superior derecha", "Inferior izquierda",
                                   "Inferior derecha"};
  overlayCorner_ = new wxChoice(overlayPanel, wxID_ANY, wxDefaultPosition, wxDefaultSize, cornerLabels);
  overlayCorner_->SetSelection(static_cast<int>(working_.overlay.corner));
  overlayRow->Add(overlayCorner_, 0, wxALIGN_CENTER_VERTICAL);
  overlaySizer->Add(overlayRow, 0, wxEXPAND | wxALL, theme_.spaceLg);
#ifdef _WIN32
  overlaySuppressFullscreen_ = new wxCheckBox(overlayPanel, wxID_ANY,
                                               "Ocultar al usar una aplicación a pantalla completa");
  overlaySuppressFullscreen_->SetValue(working_.overlay.suppressFullscreen);
  overlaySizer->Add(overlaySuppressFullscreen_, 0, wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceLg);
  wxString shortcut = wxS("Atajo de recuperación: Ctrl+Alt+U");
  if (!overlayHotkeyStatus_.empty()) shortcut = wxString::FromUTF8(overlayHotkeyStatus_);
  overlayShortcutStatus_ = new wxStaticText(overlayPanel, wxID_ANY, shortcut);
  overlayShortcutStatus_->SetName("Estado del atajo global Ctrl Alt U");
  overlaySizer->Add(overlayShortcutStatus_, 0, wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceLg);
#endif
  overlayPanel->SetSizer(overlaySizer);
  root->Add(overlayPanel, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
#endif

  contentSizer_ = new wxBoxSizer(wxHORIZONTAL);
  navigationPanel_ = new ModernPanel(this, theme_);
  navigationPanel_->SetName(wxS("Navegación de proveedores"));
  auto* left = new wxBoxSizer(wxVERTICAL);
  auto* providersTitle = new wxStaticText(navigationPanel_, wxID_ANY, "Proveedores");
  providersTitle->SetFont(theme_.sectionFont);
  left->Add(providersTitle, 0, wxALL, theme_.spaceLg);
  providers_ = new wxListBox(navigationPanel_, wxID_ANY);
  providers_->SetName("Lista de proveedores");
  left->Add(providers_, 1, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  addKind_ = new wxChoice(navigationPanel_, wxID_ANY, wxDefaultPosition, wxDefaultSize, KindLabels());
  addKind_->SetName("Tipo de proveedor nuevo");
  addKind_->SetSelection(2);
  left->Add(addKind_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceSm);
  addButton_ = new wxButton(navigationPanel_, AddProviderId, "Agregar");
  addButton_->SetName("Agregar proveedor");
  removeButton_ = new wxButton(navigationPanel_, RemoveProviderId, "Eliminar");
  removeButton_->SetName("Eliminar proveedor");
  auto* leftButtons = new wxBoxSizer(wxHORIZONTAL);
  leftButtons->Add(addButton_, 1, wxRIGHT, theme_.spaceXs);
  leftButtons->Add(removeButton_, 1, wxLEFT, theme_.spaceXs);
  left->Add(leftButtons, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  navigationPanel_->SetSizer(left);
  navigationPanel_->SetMinSize(wxSize(FromDIP(230), -1));
  contentSizer_->Add(navigationPanel_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);

  editorScroll_ = new wxScrolledWindow(this, wxID_ANY, wxDefaultPosition, wxDefaultSize,
                                       wxVSCROLL | wxBORDER_NONE);
  editorScroll_->SetName("Editor de proveedor");
  editorScroll_->SetBackgroundColour(theme_.canvas);
  editorScroll_->SetScrollRate(0, FromDIP(12));
  auto* form = new wxBoxSizer(wxVERTICAL);

  auto* identitySection = new ModernPanel(editorScroll_, theme_, true);
  auto* identity = new wxBoxSizer(wxVERTICAL);
  auto* identityTitle = new wxStaticText(identitySection, wxID_ANY, "Identidad y cliente local");
  identityTitle->SetFont(theme_.sectionFont);
  identity->Add(identityTitle, 0, wxALL, theme_.spaceMd);
  auto* grid = new wxFlexGridSizer(2, 5, 5);
  grid->AddGrowableCol(1, 1);
  name_ = AddTextRow(identitySection, grid, "Nombre:");
  name_->SetName("Nombre del proveedor");
  grid->Add(new wxStaticText(identitySection, wxID_ANY, "Tipo:"), 0, wxALIGN_CENTER_VERTICAL | wxALL, 4);
  kind_ = new wxChoice(identitySection, wxID_ANY, wxDefaultPosition, wxDefaultSize, KindLabels());
  kind_->SetName("Tipo de proveedor");
  grid->Add(kind_, 1, wxEXPAND | wxALL, 4);
  executable_ = AddTextRow(identitySection, grid, "Ejecutable:", 0, &executableLabel_);
  executable_->SetName("Ejecutable del cliente");
  identity->Add(grid, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  identitySection->SetSizer(identity);
  form->Add(identitySection, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);

  connectionSection_ = new ModernPanel(editorScroll_, theme_, true);
  auto* connection = new wxBoxSizer(wxVERTICAL);
  auto* connectionTitle = new wxStaticText(connectionSection_, wxID_ANY, wxS("Conexión"));
  connectionTitle->SetFont(theme_.sectionFont);
  connection->Add(connectionTitle, 0, wxALL, theme_.spaceMd);
  auto* connectionGrid = new wxFlexGridSizer(2, 5, 5);
  connectionGrid->AddGrowableCol(1, 1);
  baseUrl_ = AddTextRow(connectionSection_, connectionGrid, "URL base:", 0, &baseUrlLabel_);
  baseUrl_->SetName("URL base");
  apiKey_ = AddTextRow(connectionSection_, connectionGrid, "API key:", wxTE_PASSWORD, &apiKeyLabel_);
  apiKey_->SetName("API key");
  apiKey_->SetHint(wxS("Vacío conserva la clave protegida actual"));
  connection->Add(connectionGrid, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  connectionSection_->SetSizer(connection);
  form->Add(connectionSection_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);

  usageSection_ = new ModernPanel(editorScroll_, theme_, true);
  auto* usage = new wxBoxSizer(wxVERTICAL);
  auto* usageTitle = new wxStaticText(usageSection_, wxID_ANY, "Uso y mappings");
  usageTitle->SetFont(theme_.sectionFont);
  usage->Add(usageTitle, 0, wxALL, theme_.spaceMd);
  auto* usageGrid = new wxFlexGridSizer(2, 5, 5);
  usageGrid->AddGrowableCol(1, 1);
  usagePath_ = AddTextRow(usageSection_, usageGrid, "Ruta de uso:", 0, &usagePathLabel_);
  balancePath_ = AddTextRow(usageSection_, usageGrid, "Ruta de saldo:", 0, &balancePathLabel_);
  budget_ = AddTextRow(usageSection_, usageGrid, "Presupuesto opcional:", 0, &budgetLabel_);
  mappings_ = AddTextRow(usageSection_, usageGrid, "Mappings JSON Pointer:", wxTE_MULTILINE, &mappingsLabel_);
  mappings_->SetName("Mappings JSON Pointer");
  mappings_->SetMinSize(wxSize(-1, FromDIP(72)));
  mappings_->SetHint("balance_usd=/data/balance\ntotal_tokens=/usage/total");
  usage->Add(usageGrid, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  usageSection_->SetSizer(usage);
  form->Add(usageSection_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);

  securitySection_ = new ModernPanel(editorScroll_, theme_, true);
  auto* security = new wxBoxSizer(wxVERTICAL);
  auto* securityTitle = new wxStaticText(securitySection_, wxID_ANY, "Disponibilidad y seguridad");
  securityTitle->SetFont(theme_.sectionFont);
  security->Add(securityTitle, 0, wxALL, theme_.spaceMd);
  enabled_ = new wxCheckBox(securitySection_, wxID_ANY, "Proveedor habilitado");
  enabled_->SetName("Proveedor habilitado");
  persistKey_ = new wxCheckBox(securitySection_, wxID_ANY, "Guardar clave en almacenamiento seguro");
  persistKey_->SetName("Guardar clave en almacenamiento seguro");
  persistKey_->SetValue(secrets_.PersistentAvailable());
  persistKey_->Enable(secrets_.PersistentAvailable());
  loopback_ = new wxCheckBox(securitySection_, wxID_ANY, wxS("Permitir HTTP sólo para loopback"));
  loopback_->SetName(wxS("Permitir HTTP sólo para loopback"));
  security->Add(enabled_, 0, wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  security->Add(loopback_, 0, wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  security->Add(persistKey_, 0, wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  secretStorageNotice_ = new SemanticNotice(
      securitySection_,
      wxS("! Secret Service no está disponible. La clave sólo se conservará mientras esta aplicación permanezca abierta."),
      StatusTone::Warning, theme_);
  security->Add(secretStorageNotice_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  securitySection_->SetSizer(security);
  form->Add(securitySection_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);

  auto* testSection = new ModernPanel(editorScroll_, theme_, true);
  auto* testing = new wxBoxSizer(wxVERTICAL);
  auto* testTitle = new wxStaticText(testSection, wxID_ANY, wxS("Verificación"));
  testTitle->SetFont(theme_.sectionFont);
  testing->Add(testTitle, 0, wxALL, theme_.spaceMd);
  testButton_ = new wxButton(testSection, TestProviderId, wxS("Probar conexión"));
  testButton_->SetName(wxS("Probar conexión"));
  testing->Add(testButton_, 0, wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  testResult_ = new SemanticNotice(testSection, "", StatusTone::Accent, theme_);
  testResult_->Hide();
  testing->Add(testResult_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  validationResult_ = new SemanticNotice(testSection, "", StatusTone::Error, theme_);
  validationResult_->Hide();
  testing->Add(validationResult_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  testSection->SetSizer(testing);
  form->Add(testSection, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  editorScroll_->SetSizer(form);
  contentSizer_->Add(editorScroll_, 1, wxEXPAND | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  root->Add(contentSizer_, 1, wxEXPAND);

  auto* buttons = new wxBoxSizer(wxHORIZONTAL);
  buttons->AddStretchSpacer();
  cancelButton_ = new wxButton(this, wxID_CANCEL, "Cancelar");
  cancelButton_->SetName(wxS("Cancelar configuración"));
  okButton_ = new wxButton(this, wxID_OK, "Guardar cambios");
  okButton_->SetName(wxS("Guardar configuración"));
  buttons->Add(cancelButton_, 0, wxRIGHT, theme_.spaceSm);
  buttons->Add(okButton_, 0);
  root->Add(buttons, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  SetSizer(root);
  SetAffirmativeId(wxID_OK);
  SetEscapeId(wxID_CANCEL);

  providers_->Bind(wxEVT_LISTBOX, &SettingsDialog::OnSelect, this);
  kind_->Bind(wxEVT_CHOICE, [this](wxCommandEvent&) { UpdateFieldVisibility(); });
  Bind(wxEVT_BUTTON, &SettingsDialog::OnAdd, this, AddProviderId);
  Bind(wxEVT_BUTTON, &SettingsDialog::OnRemove, this, RemoveProviderId);
  Bind(wxEVT_BUTTON, &SettingsDialog::OnTest, this, TestProviderId);
  Bind(wxEVT_BUTTON, &SettingsDialog::OnOpenData, this, OpenDataId);
  Bind(wxEVT_BUTTON, &SettingsDialog::OnAccept, this, wxID_OK);
  Bind(wxEVT_SYS_COLOUR_CHANGED, &SettingsDialog::OnSystemColourChanged, this);
  Bind(wxEVT_SIZE, &SettingsDialog::OnSize, this);
  ApplyPresentationTheme();
  UpdateResponsiveLayout();
}

void SettingsDialog::ApplyPresentationTheme() {
  theme_ = ResolveTheme(this);
  SetBackgroundColour(theme_.canvas);
  editorScroll_->SetBackgroundColour(theme_.canvas);
  ApplyTheme(this, theme_);
  StyleButton(openDataButton_, theme_, ButtonTone::Secondary);
  StyleButton(addButton_, theme_, ButtonTone::Primary);
  StyleButton(removeButton_, theme_, ButtonTone::Destructive);
  StyleButton(testButton_, theme_, ButtonTone::Secondary);
  StyleButton(cancelButton_, theme_, ButtonTone::Secondary);
  StyleButton(okButton_, theme_, ButtonTone::Primary);
  secretStorageNotice_->SetPresentationTheme(theme_);
  testResult_->SetPresentationTheme(theme_);
  validationResult_->SetPresentationTheme(theme_);
  Layout();
  Refresh();
}

void SettingsDialog::UpdateResponsiveLayout() {
  const bool compact = UseCompactLayout(ToDIP(GetClientSize()).x);
  if (compact == compactLayout_) return;
  compactLayout_ = compact;
  contentSizer_->Clear(false);
  contentSizer_->SetOrientation(compact ? wxVERTICAL : wxHORIZONTAL);
  navigationPanel_->SetMinSize(compact ? wxSize(-1, FromDIP(190)) : wxSize(FromDIP(230), -1));
  contentSizer_->Add(navigationPanel_, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  contentSizer_->Add(editorScroll_, 1, wxEXPAND | wxRIGHT | wxBOTTOM, theme_.spaceMd);
  editorScroll_->FitInside();
  Layout();
}

void SettingsDialog::OnSystemColourChanged(wxSysColourChangedEvent& event) {
  event.Skip();
  ApplyPresentationTheme();
}

void SettingsDialog::OnSize(wxSizeEvent& event) {
  UpdateResponsiveLayout();
  editorScroll_->Layout();
  editorScroll_->FitInside();
  RefreshTree(globalPanel_);
  RefreshTree(navigationPanel_);
  RefreshTree(editorScroll_);
  Refresh(true);
  event.Skip();
}

void SettingsDialog::RefreshList(int selection) {
  providers_->Clear();
  for (const auto& provider : working_.providers) {
    providers_->Append(wxString::FromUTF8(provider.name) +
                       (provider.enabled ? wxString(wxS(" ✓")) : wxString{}));
  }
  if (selection >= 0 && selection < static_cast<int>(working_.providers.size())) {
    selected_ = selection;
    providers_->SetSelection(selection);
    LoadSelected();
  } else {
    selected_ = -1;
  }
}

void SettingsDialog::LoadSelected() {
  if (selected_ < 0 || selected_ >= static_cast<int>(working_.providers.size())) return;
  const auto& provider = working_.providers[static_cast<std::size_t>(selected_)];
  name_->SetValue(wxString::FromUTF8(provider.name));
  kind_->SetSelection(IndexFromKind(provider.kind));
  enabled_->SetValue(provider.enabled);
  executable_->SetValue(provider.executable.wstring());
  baseUrl_->SetValue(wxString::FromUTF8(provider.baseUrl));
  apiKey_->Clear();
  persistKey_->SetValue(!provider.encryptedApiKey.starts_with("session:") && secrets_.PersistentAvailable());
  if (!provider.encryptedApiKey.empty()) {
    try {
      (void)secrets_.Unprotect(provider.encryptedApiKey);
      apiKey_->SetHint("Credencial protegida guardada; vacio la conserva");
    } catch (...) {
      apiKey_->SetHint("La credencial no puede descifrarse; vuelva a introducirla");
    }
  } else {
    apiKey_->SetHint("Introduzca una clave; puede guardarla o usarla solo en esta sesion");
  }
  usagePath_->SetValue(wxString::FromUTF8(provider.usagePath));
  balancePath_->SetValue(wxString::FromUTF8(provider.balancePath));
  budget_->SetValue(provider.budget.has_value() ? wxString::FromUTF8(*provider.budget) : wxString{});
  std::string mappings;
  for (const auto& [name, pointer] : provider.jsonPointers) mappings += name + "=" + pointer + "\n";
  mappings_->SetValue(wxString::FromUTF8(mappings));
  loopback_->SetValue(provider.allowLoopbackHttp);
  testResult_->SetText("");
  testResult_->Hide();
  validationResult_->SetText("");
  validationResult_->Hide();
  UpdateFieldVisibility();
}

void SettingsDialog::SaveSelected() {
  if (selected_ < 0 || selected_ >= static_cast<int>(working_.providers.size())) return;
  auto& provider = working_.providers[static_cast<std::size_t>(selected_)];
  provider.name = name_->GetValue().ToStdString(wxConvUTF8);
  provider.kind = KindFromIndex(kind_->GetSelection());
  provider.enabled = enabled_->GetValue();
  provider.executable = std::filesystem::path(executable_->GetValue().ToStdWstring());
  provider.baseUrl = baseUrl_->GetValue().ToStdString(wxConvUTF8);
  const auto plainKey = apiKey_->GetValue().ToStdString(wxConvUTF8);
  if (!plainKey.empty()) {
    provider.encryptedApiKey = persistKey_->GetValue() && secrets_.PersistentAvailable()
                                   ? secrets_.Protect(plainKey)
                                   : secrets_.ProtectSession(plainKey);
  }
  provider.usagePath = usagePath_->GetValue().ToStdString(wxConvUTF8);
  provider.balancePath = balancePath_->GetValue().ToStdString(wxConvUTF8);
  const auto budget = budget_->GetValue().ToStdString(wxConvUTF8);
  provider.budget = budget.empty() ? std::nullopt : std::optional<std::string>{budget};
  provider.jsonPointers.clear();
  std::istringstream lines(mappings_->GetValue().ToStdString(wxConvUTF8));
  std::string line;
  while (std::getline(lines, line)) {
    const auto equals = line.find('=');
    if (equals != std::string::npos && equals > 0 && equals + 1 < line.size()) {
      provider.jsonPointers[line.substr(0, equals)] = line.substr(equals + 1);
    }
  }
  provider.allowLoopbackHttp = loopback_->GetValue();
}

void SettingsDialog::UpdateFieldVisibility() {
  const auto selectedKind = KindFromIndex(kind_->GetSelection());
  const bool local = selectedKind == ProviderKind::Codex || selectedKind == ProviderKind::ClaudeSubscription;
  const bool http = selectedKind == ProviderKind::DeepSeek || selectedKind == ProviderKind::OpenAiCompatible;
  const bool generic = selectedKind == ProviderKind::OpenAiCompatible;
  const auto showRow = [](wxStaticText* label, wxWindow* control, bool show) {
    label->Show(show);
    control->Show(show);
  };
  showRow(executableLabel_, executable_, local);
  showRow(baseUrlLabel_, baseUrl_, http);
  showRow(apiKeyLabel_, apiKey_, http);
  showRow(usagePathLabel_, usagePath_, generic);
  showRow(balancePathLabel_, balancePath_, selectedKind == ProviderKind::DeepSeek || generic);
  showRow(budgetLabel_, budget_, selectedKind == ProviderKind::DeepSeek);
  showRow(mappingsLabel_, mappings_, generic);
  loopback_->Show(http);
  persistKey_->Show(http);
  secretStorageNotice_->Show(http && !secrets_.PersistentAvailable());
  connectionSection_->Show(http);
  usageSection_->Show(selectedKind == ProviderKind::DeepSeek || generic);
  editorScroll_->FitInside();
  Layout();
}

void SettingsDialog::OnSelect(wxCommandEvent& event) {
  SaveSelected();
  selected_ = event.GetSelection();
  LoadSelected();
}

void SettingsDialog::OnAdd(wxCommandEvent&) {
  SaveSelected();
  const auto selectedKind = KindFromIndex(addKind_->GetSelection());
  ProviderConfig provider;
  provider.kind = selectedKind;
  provider.id = NewId(selectedKind);
  provider.name = KindLabels()[IndexFromKind(selectedKind)].ToStdString(wxConvUTF8);
  if (selectedKind == ProviderKind::DeepSeek) {
    provider.baseUrl = "https://api.deepseek.com";
    provider.balancePath = "/user/balance";
  }
  if (selectedKind == ProviderKind::Codex) {
    const auto path = DiscoverExecutable("codex");
    if (path.has_value()) provider.executable = "codex";
  }
  if (selectedKind == ProviderKind::ClaudeSubscription) {
    const auto path = DiscoverExecutable("claude");
    if (path.has_value()) provider.executable = "claude";
  }
  working_.providers.push_back(std::move(provider));
  RefreshList(static_cast<int>(working_.providers.size() - 1));
}

void SettingsDialog::OnRemove(wxCommandEvent&) {
  if (selected_ < 0) return;
  working_.providers.erase(working_.providers.begin() + selected_);
  RefreshList(working_.providers.empty() ? -1 : std::min(selected_, static_cast<int>(working_.providers.size() - 1)));
}

void SettingsDialog::OnTest(wxCommandEvent&) {
  SaveSelected();
  if (selected_ < 0) return;
  const auto config = working_.providers[static_cast<std::size_t>(selected_)];
  if (!config.baseUrl.empty() && !IsSafeEndpointUrl(config.baseUrl, config.allowLoopbackHttp)) {
    testResult_->SetTone(StatusTone::Error);
    testResult_->SetText(wxS("× URL rechazada: use HTTPS o HTTP loopback habilitado."));
    testResult_->Show();
    editorScroll_->FitInside();
    return;
  }
  testResult_->SetTone(StatusTone::Accent);
  testResult_->SetText(wxS("↻ Probando…"));
  testResult_->Show();
  editorScroll_->FitInside();
  wxWeakRef<SettingsDialog> weak(this);
  auto* const http = &http_;
  auto* const process = &process_;
  auto* const secrets = &secrets_;
  std::thread([weak, config, http, process, secrets] {
    ConnectionTestResult result;
    try {
      auto provider = CreateProvider(config, *http, *process, *secrets);
      result = provider->TestConnection();
    } catch (const std::exception& error) {
      result = {false, {}, error.what()};
    }
    std::vector<std::string> sensitive;
    if (!config.encryptedApiKey.empty()) {
      try { sensitive.push_back(secrets->Unprotect(config.encryptedApiKey)); } catch (...) {}
    }
    result.message = RedactSecrets(result.message, sensitive);
    if (!result.capabilities.detail.empty()) result.message += " | " + result.capabilities.detail;
    wxTheApp->CallAfter([weak, result] {
      if (weak) {
        weak->testResult_->SetTone(result.success ? StatusTone::Success : StatusTone::Error);
        weak->testResult_->SetText((result.success ? wxS("✓ ") : wxS("× Error: ")) +
                                   wxString::FromUTF8(result.message));
        weak->testResult_->Show();
        weak->editorScroll_->FitInside();
        weak->Layout();
      }
    });
  }).detach();
}

void SettingsDialog::OnOpenData(wxCommandEvent&) { wxLaunchDefaultApplication(paths_.root.wstring()); }

void SettingsDialog::OnAccept(wxCommandEvent&) {
  try {
    validationResult_->SetText("");
    validationResult_->Hide();
    SaveSelected();
    working_.refreshMinutes = refreshMinutes_->GetValue();
    working_.alwaysOnTop = alwaysOnTop_->GetValue();
#if defined(_WIN32) || defined(__linux__)
    working_.overlay.enabled = overlayEnabled_->GetValue();
    working_.overlay.visible = overlayVisible_->GetValue();
    working_.overlay.opacity = overlayOpacity_->GetValue();
    working_.overlay.corner = static_cast<OverlayCorner>(overlayCorner_->GetSelection());
#ifdef _WIN32
    working_.overlay.locked = overlayLocked_->GetValue();
    working_.overlay.suppressFullscreen = overlaySuppressFullscreen_->GetValue();
#endif
#endif
    for (const auto& provider : working_.providers) {
      if (provider.enabled &&
          (provider.kind == ProviderKind::Codex || provider.kind == ProviderKind::ClaudeSubscription) &&
          provider.executable.empty()) {
        throw std::runtime_error("Seleccione un ejecutable compatible para " + provider.name + ".");
      }
      if ((provider.kind == ProviderKind::DeepSeek || provider.kind == ProviderKind::OpenAiCompatible) &&
          provider.baseUrl.empty()) {
        throw std::runtime_error("La URL base es obligatoria para " + provider.name + ".");
      }
      if (!provider.baseUrl.empty() && !IsSafeEndpointUrl(provider.baseUrl, provider.allowLoopbackHttp)) {
        throw std::runtime_error("La URL de " + provider.name + " debe usar HTTPS o loopback explícito.");
      }
      for (const auto& [name, pointer] : provider.jsonPointers) {
        (void)name;
        if (pointer.empty() || pointer.front() != '/') throw std::runtime_error("Los JSON Pointer deben comenzar con '/'.");
      }
    }
    const auto validation = ValidateSettings(working_);
    if (validation.has_value()) throw std::runtime_error(*validation);
    SaveSettings(paths_, working_);
    settings_ = working_;
    EndModal(wxID_OK);
  } catch (const std::exception& error) {
    validationResult_->SetTone(StatusTone::Error);
    validationResult_->SetText(wxS("× ") + wxString::FromUTF8(error.what()));
    validationResult_->Show();
    editorScroll_->FitInside();
    Layout();
    wxMessageBox(wxString::FromUTF8(error.what()), wxS("Configuración inválida"), wxOK | wxICON_ERROR, this);
  }
}

}  // namespace ai_usage::ui
