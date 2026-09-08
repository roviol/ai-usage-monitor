#pragma once

#include "ai_usage/config.h"
#include "ai_usage/overlay.h"
#include "ai_usage/platform.h"
#include "ai_usage/scheduler.h"
#include "presentation.h"

#include <wx/app.h>
#include <wx/checkbox.h>
#include <wx/choice.h>
#include <wx/dialog.h>
#include <wx/display.h>
#include <wx/frame.h>
#include <wx/listbox.h>
#include <wx/panel.h>
#include <wx/scrolwin.h>
#include <wx/spinctrl.h>
#include <wx/stattext.h>
#include <wx/taskbar.h>
#include <wx/textctrl.h>
#include <wx/timer.h>

#include <functional>
#include <map>
#include <memory>
#include <thread>

namespace ai_usage::ui {

class DashboardFrame final : public wxFrame {
 public:
  using VoidCallback = std::function<void()>;
  using TopCallback = std::function<void(bool)>;

  DashboardFrame(VoidCallback refreshAll, VoidCallback openSettings, TopCallback alwaysOnTop);
  void SetSnapshots(const std::vector<ProviderSnapshot>& snapshots);
  void ApplyAlwaysOnTop(bool enabled);
  void EnableTrayFallback();

 private:
  void RebuildCards();
  void ApplyPresentationTheme();
  void UpdateResponsiveLayout();
  void OnSystemColourChanged(wxSysColourChangedEvent& event);
  void OnSize(wxSizeEvent& event);
  void OnClose(wxCloseEvent& event);

  VoidCallback refreshAll_;
  VoidCallback openSettings_;
  TopCallback alwaysOnTop_;
  std::vector<ProviderSnapshot> snapshots_;
  wxPanel* cardsPanel_{nullptr};
  wxBoxSizer* cardsSizer_{nullptr};
  ModernPanel* appBar_{nullptr};
  wxBoxSizer* appBarSizer_{nullptr};
  wxStaticText* title_{nullptr};
  wxPanel* appActions_{nullptr};
  wxButton* refreshButton_{nullptr};
  wxButton* settingsButton_{nullptr};
  wxCheckBox* alwaysOnTopCheck_{nullptr};
  SemanticNotice* environmentNotice_{nullptr};
  PresentationTheme theme_;
  bool compactLayout_{false};
};

class SettingsDialog final : public wxDialog {
 public:
  SettingsDialog(wxWindow* parent, Settings& settings, const DataPaths& paths, IHttpClient& http,
                 IProcessRunner& process, ISecretStore& secrets, std::string overlayHotkeyStatus = {});

 private:
  void BuildUi();
  void ApplyPresentationTheme();
  void UpdateResponsiveLayout();
  void OnSystemColourChanged(wxSysColourChangedEvent& event);
  void OnSize(wxSizeEvent& event);
  void LoadSelected();
  void SaveSelected();
  void UpdateFieldVisibility();
  void OnForgetKeys(wxCommandEvent& event);
  void OnKindChanged(wxCommandEvent& event);
  void OnSelect(wxCommandEvent& event);
  void OnAdd(wxCommandEvent& event);
  void OnRemove(wxCommandEvent& event);
  void OnTest(wxCommandEvent& event);
  void OnOpenData(wxCommandEvent& event);
  void OnAccept(wxCommandEvent& event);
  void RefreshList(int selection = -1);

  Settings& settings_;
  Settings working_;
  const DataPaths& paths_;
  IHttpClient& http_;
  IProcessRunner& process_;
  ISecretStore& secrets_;
  int selected_{-1};
  ProviderKind editorKind_{ProviderKind::OpenAiCompatible};
  wxListBox* providers_{nullptr};
  wxChoice* addKind_{nullptr};
  wxTextCtrl* name_{nullptr};
  wxChoice* kind_{nullptr};
  wxCheckBox* enabled_{nullptr};
  wxTextCtrl* executable_{nullptr};
  wxStaticText* executableLabel_{nullptr};
  wxTextCtrl* baseUrl_{nullptr};
  wxStaticText* baseUrlLabel_{nullptr};
  wxTextCtrl* apiKey_{nullptr};
  wxStaticText* apiKeyLabel_{nullptr};
  wxTextCtrl* cloudKey_{nullptr};
  wxStaticText* cloudKeyLabel_{nullptr};
  wxTextCtrl* usagePath_{nullptr};
  wxStaticText* usagePathLabel_{nullptr};
  wxTextCtrl* balancePath_{nullptr};
  wxStaticText* balancePathLabel_{nullptr};
  wxTextCtrl* budget_{nullptr};
  wxStaticText* budgetLabel_{nullptr};
  wxTextCtrl* mappings_{nullptr};
  wxStaticText* mappingsLabel_{nullptr};
  wxCheckBox* loopback_{nullptr};
  wxCheckBox* persistKey_{nullptr};
  wxButton* forgetKeys_{nullptr};
  SemanticNotice* secretStorageNotice_{nullptr};
  wxSpinCtrl* refreshMinutes_{nullptr};
  wxCheckBox* alwaysOnTop_{nullptr};
#if defined(_WIN32) || defined(__linux__)
  wxCheckBox* overlayEnabled_{nullptr};
  wxCheckBox* overlayVisible_{nullptr};
  wxSpinCtrl* overlayOpacity_{nullptr};
  wxChoice* overlayCorner_{nullptr};
#ifdef _WIN32
  wxCheckBox* overlayLocked_{nullptr};
  wxCheckBox* overlaySuppressFullscreen_{nullptr};
  wxStaticText* overlayShortcutStatus_{nullptr};
#endif
#endif
  SemanticNotice* testResult_{nullptr};
  SemanticNotice* validationResult_{nullptr};
  ModernPanel* globalPanel_{nullptr};
  ModernPanel* navigationPanel_{nullptr};
  ModernPanel* connectionSection_{nullptr};
  ModernPanel* usageSection_{nullptr};
  ModernPanel* securitySection_{nullptr};
  wxScrolledWindow* editorScroll_{nullptr};
  wxBoxSizer* contentSizer_{nullptr};
  wxButton* openDataButton_{nullptr};
  wxButton* addButton_{nullptr};
  wxButton* removeButton_{nullptr};
  wxButton* testButton_{nullptr};
  wxButton* okButton_{nullptr};
  wxButton* cancelButton_{nullptr};
  PresentationTheme theme_;
  std::string overlayHotkeyStatus_;
  bool compactLayout_{false};
};

class TrayIcon final : public wxTaskBarIcon {
 public:
  using VoidCallback = std::function<void()>;
  struct OverlayState {
    bool enabled{false};
    bool visible{false};
    bool locked{true};
  };
  using OverlayStateCallback = std::function<OverlayState()>;
  TrayIcon(VoidCallback show, VoidCallback refresh, VoidCallback settings, VoidCallback exit,
           VoidCallback toggleOverlayVisibility = {}, VoidCallback toggleOverlayLock = {},
           OverlayStateCallback overlayState = {});
  void SetSnapshots(const std::vector<ProviderSnapshot>& snapshots);
  bool IsAvailable() const { return available_; }
  wxMenu* CreatePopupMenu() override;

 private:
  wxIcon MakeStatusIcon(Health health) const;
  void OnActivate(wxTaskBarIconEvent& event);
  VoidCallback show_;
  VoidCallback refresh_;
  VoidCallback settings_;
  VoidCallback exit_;
  VoidCallback toggleOverlayVisibility_;
  VoidCallback toggleOverlayLock_;
  OverlayStateCallback overlayState_;
  std::vector<ProviderSnapshot> snapshots_;
  bool available_{false};
};

#if defined(_WIN32) || defined(__linux__)
class MinimalOverlayFrame final : public wxFrame {
 public:
  using SettingsCallback = std::function<void(const OverlaySettings&)>;

  MinimalOverlayFrame(OverlaySettings settings, SettingsCallback settingsChanged);
  ~MinimalOverlayFrame() override;
  void SetSnapshots(const std::vector<ProviderSnapshot>& snapshots);
  void ApplySettings(const OverlaySettings& settings);
  void ShowOverlay();
  void HideOverlay();
  void Shutdown();
  bool IsOverlayVisible() const { return settings_.visible; }
#ifdef _WIN32
  void ToggleLock();
  void HandleForegroundEvent();
  bool IsLocked() const { return settings_.locked; }
  bool HotkeyAvailable() const { return hotkeyAvailable_; }
  const std::string& HotkeyWarning() const { return hotkeyWarning_; }

 protected:
  WXLRESULT MSWWindowProc(WXUINT message, WXWPARAM wParam, WXLPARAM lParam) override;
#endif

 private:
  void ReprojectAndResize(bool reanchor = true);
  void AnchorToSavedCorner();
  void SnapToNearestCorner();
  void ApplyOpacity(bool hovered = false);
#ifdef _WIN32
  void ApplyNativeStyles();
  void UpdateRoundedRegion();
  void RegisterRecoveryHotkey();
  void UnregisterRecoveryHotkey();
  void InstallForegroundHooks();
  void RemoveForegroundHooks();
  void HandleForegroundWindow(void* foregroundWindow);
#endif
  void ScheduleCountdown();
  void PersistSettings();
  void OnPaint(wxPaintEvent& event);
  void OnMouseDown(wxMouseEvent& event);
  void OnMouseMove(wxMouseEvent& event);
  void OnMouseUp(wxMouseEvent& event);
  void OnMouseEnter(wxMouseEvent& event);
  void OnMouseLeave(wxMouseEvent& event);
  void OnCountdown(wxTimerEvent& event);
  void OnDisplayChanged(wxDisplayChangedEvent& event);

  OverlaySettings settings_;
  SettingsCallback settingsChanged_;
  std::vector<ProviderSnapshot> snapshots_;
  OverlayProjection projection_;
  wxTimer countdownTimer_;
  wxPoint dragOrigin_;
  wxPoint windowOrigin_;
  bool dragging_{false};
  bool shuttingDown_{false};
#ifdef _WIN32
  bool suppressed_{false};
  bool hotkeyAvailable_{false};
  std::string hotkeyWarning_;
  void* foregroundHook_{nullptr};
  void* locationHook_{nullptr};
#endif
};
#endif

class MonitorApp final : public wxApp {
 public:
  bool OnInit() override;
  int OnExit() override;
  void ShowDashboard();
  void OpenSettings();
  void RefreshAll();
  void ExitApplication();

 private:
  void EnsureDefaults();
  void RebuildProviders();
  void ReceiveSnapshot(ProviderSnapshot snapshot);
  void PublishSnapshots();
  void MarkRefreshing(const std::string& providerId);
  void ShutdownRuntime();
  void StopActivationWatcher();
#ifdef _WIN32
  void OnQueryEndSession(wxCloseEvent& event);
  void ToggleOverlayLock();
#endif
#if defined(_WIN32) || defined(__linux__)
  void ApplyOverlaySettings();
  void ToggleOverlayVisibility();
#endif

  DataPaths paths_;
  Settings settings_;
  std::unique_ptr<IHttpClient> http_;
  std::unique_ptr<IProcessRunner> process_;
  std::unique_ptr<ISecretStore> secrets_;
  std::unique_ptr<RefreshScheduler> scheduler_;
  std::unique_ptr<ISingleInstanceSignal> instanceSignal_;
  std::unique_ptr<DashboardFrame> dashboard_;
  std::unique_ptr<TrayIcon> tray_;
#if defined(_WIN32) || defined(__linux__)
  std::unique_ptr<MinimalOverlayFrame> overlay_;
#endif
  std::map<std::string, ProviderSnapshot> snapshots_;
  std::jthread activationThread_;
  bool exiting_{false};
};

}  // namespace ai_usage::ui
