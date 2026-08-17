#include "ui.h"

#include <wx/filename.h>
#include <wx/stdpaths.h>
#include <wx/utils.h>

#include <algorithm>
#include <fstream>

namespace ai_usage::ui {
namespace {

std::vector<ProviderSnapshot> UiFixtureSnapshots() {
  const auto now = Clock::now();
  const auto metric = [](std::string value, std::string label, std::chrono::hours reset) {
    return Metric{MetricKind::UsedPercent, std::move(value), MetricUnit::Percent, MetricScope::RollingWindow,
                  Provenance::CliBridge, Availability::Available, Clock::now() + reset, std::nullopt,
                  std::move(label)};
  };
  ProviderSnapshot codex{"fixture-codex", "Codex", ProviderKind::Codex, now, Freshness::Fresh, Health::Healthy};
  codex.accountLabel = "cuenta@example.com";
  codex.metrics.push_back(metric("28", "Ventana de 5 horas", std::chrono::hours{2}));
  codex.metrics.push_back(metric("54", "Ventana semanal", std::chrono::hours{48}));
  auto imminent = metric("66", "Cuota por reiniciar", std::chrono::hours{0});
  imminent.resetsAt = now + std::chrono::seconds{35};
  codex.metrics.push_back(std::move(imminent));
  auto elapsed = metric("91", "Cuota reiniciando", std::chrono::hours{0});
  elapsed.resetsAt = now - std::chrono::seconds{2};
  codex.metrics.push_back(std::move(elapsed));

  ProviderSnapshot claude{"fixture-claude", "Claude", ProviderKind::ClaudeSubscription, now,
                          Freshness::Fresh, Health::Partial};
  claude.metrics.push_back(metric("72", "Claude sesión usado", std::chrono::hours{1}));
  claude.metrics.push_back(metric("46", "Claude semana usado", std::chrono::hours{25}));
  claude.error = ProviderError{"refreshing", "Actualizando cuotas de Claude…", true, std::nullopt};

  ProviderSnapshot deepseek{"fixture-deepseek", "DeepSeek", ProviderKind::DeepSeek, now,
                            Freshness::Fresh, Health::Healthy};
  deepseek.metrics.push_back(Metric{MetricKind::Balance, "42.50", MetricUnit::USD, MetricScope::CurrentBalance,
                                    Provenance::ProviderReported, Availability::Available, std::nullopt, std::nullopt,
                                    "Saldo disponible"});

  ProviderSnapshot stale{"fixture-stale", "Equipo", ProviderKind::OpenAiCompatible,
                         now - std::chrono::minutes{18}, Freshness::Stale, Health::Error};
  stale.metrics.push_back(metric("83", "Cuota mensual usada", std::chrono::hours{96}));
  stale.error = ProviderError{"timeout", "No se pudo actualizar; se conservan los últimos datos válidos.", true,
                              std::nullopt};

  ProviderSnapshot noData{"fixture-empty", "Proveedor nuevo", ProviderKind::OpenAiCompatible, TimePoint{},
                          Freshness::NoData, Health::Partial};
  noData.error = ProviderError{"waiting", "Esperando la primera actualización.", true, std::nullopt};

  ProviderSnapshot unavailable{"fixture-error", "Servicio externo", ProviderKind::OpenAiCompatible, now,
                               Freshness::NoData, Health::Error};
  unavailable.error = ProviderError{"unauthorized", "Revise la credencial configurada.", false, std::nullopt};
  return {std::move(codex), std::move(claude), std::move(deepseek), std::move(stale), std::move(noData),
          std::move(unavailable)};
}

std::optional<std::string> DefaultExecutableCommand(ProviderKind kind) {
  if (kind == ProviderKind::Codex) return "codex";
  if (kind == ProviderKind::ClaudeSubscription) return "claude";
  return std::nullopt;
}

bool MakeDiscoveredExecutableReferencesPortable(Settings& settings) {
  bool changed = false;
  for (auto& provider : settings.providers) {
    const auto command = DefaultExecutableCommand(provider.kind);
    if (!command.has_value()) continue;
    const auto portable = MakeExecutableReferencePortable(*command, provider.executable,
                                                          DiscoverExecutable(*command));
    if (portable != provider.executable) {
      provider.executable = portable;
      changed = true;
    }
  }
  return changed;
}

}  // namespace

bool MonitorApp::OnInit() {
  if (!wxApp::OnInit()) return false;
  SetAppName("AIUsageMonitor");
  SetExitOnFrameDelete(false);
#ifdef _WIN32
  Bind(wxEVT_QUERY_END_SESSION, &MonitorApp::OnQueryEndSession, this);
#endif
  const auto executable = std::filesystem::path(wxStandardPaths::Get().GetExecutablePath().ToStdWstring());
  paths_ = ResolveDataPaths(executable);
  const bool firstRun = !std::filesystem::exists(paths_.settings);
  instanceSignal_ = CreatePlatformSingleInstanceSignal(paths_.root);
  if (instanceSignal_->IsAnotherRunning()) {
    instanceSignal_->SignalActivation();
    return false;
  }
  (void)instanceSignal_->ConsumeActivation();

  const auto loaded = LoadSettings(paths_);
  settings_ = loaded.settings;
  wxString fixtureValue;
  const bool fixtureMode = wxGetEnv("AI_USAGE_UI_FIXTURES", &fixtureValue) && fixtureValue == "1";
  if (!fixtureMode) {
    const bool portableReferencesChanged = MakeDiscoveredExecutableReferencesPortable(settings_);
    EnsureDefaults();
    if (portableReferencesChanged) SaveSettings(paths_, settings_);
  }
  http_ = CreatePlatformHttpClient();
  process_ = CreatePlatformProcessRunner();
  secrets_ = CreatePlatformSecretStore();
  for (auto& snapshot : LoadCache(paths_)) snapshots_[snapshot.providerId] = std::move(snapshot);

  dashboard_ = std::make_unique<DashboardFrame>(
      [this] { RefreshAll(); }, [this] { OpenSettings(); }, [this](bool enabled) {
        settings_.alwaysOnTop = enabled;
        SaveSettings(paths_, settings_);
        dashboard_->ApplyAlwaysOnTop(enabled);
      });
  dashboard_->ApplyAlwaysOnTop(settings_.alwaysOnTop);
#if defined(_WIN32) || defined(__linux__)
  wxString overlayFixtureValue;
  if (fixtureMode && wxGetEnv("AI_USAGE_UI_OVERLAY", &overlayFixtureValue) && overlayFixtureValue == "1") {
    settings_.overlay.enabled = true;
    settings_.overlay.visible = true;
    settings_.overlay.locked = false;
  }
  ApplyOverlaySettings();
#endif
  tray_ = std::make_unique<TrayIcon>(
      [this] { ShowDashboard(); }, [this] { RefreshAll(); }, [this] { OpenSettings(); }, [this] { ExitApplication(); }
#if defined(_WIN32) || defined(__linux__)
      , [this] { ToggleOverlayVisibility(); },
#ifdef _WIN32
      [this] { ToggleOverlayLock(); },
#else
      TrayIcon::VoidCallback{},
#endif
      [this] {
        return TrayIcon::OverlayState{settings_.overlay.enabled, settings_.overlay.visible,
                                      settings_.overlay.locked};
      }
#endif
  );
  if (!tray_->IsAvailable()) dashboard_->EnableTrayFallback();
  scheduler_ = std::make_unique<RefreshScheduler>([this](const ProviderSnapshot& snapshot) {
    wxTheApp->CallAfter([this, snapshot] { ReceiveSnapshot(snapshot); });
  });
  if (fixtureMode) {
    settings_.providers.clear();
    snapshots_.clear();
    auto fixtureSnapshots = UiFixtureSnapshots();
    for (auto snapshot : fixtureSnapshots) {
      ProviderConfig config;
      config.id = snapshot.providerId;
      config.name = snapshot.displayName;
      config.kind = snapshot.kind;
      config.enabled = true;
      settings_.providers.push_back(std::move(config));
      snapshots_[snapshot.providerId] = std::move(snapshot);
    }
    PublishSnapshots();
    ShowDashboard();
  } else {
    RebuildProviders();
    PublishSnapshots();
  }
  {
    std::ofstream ready(paths_.root / "ready.signal", std::ios::binary | std::ios::trunc);
    ready << "ready";
  }
  activationThread_ = std::jthread([this](std::stop_token stop) {
    while (!stop.stop_requested()) {
      const bool activated = instanceSignal_->WaitForActivation(std::chrono::milliseconds::max());
      if (activated && !stop.stop_requested()) {
        wxTheApp->CallAfter([this] {
          if (!exiting_) ShowDashboard();
        });
      }
    }
  });
  if (firstRun && !fixtureMode) CallAfter([this] { OpenSettings(); });
  return true;
}

void MonitorApp::EnsureDefaults() {
  if (!settings_.providers.empty()) return;
  if (const auto codex = DiscoverExecutable("codex"); codex.has_value()) {
    settings_.providers.push_back(ProviderConfig{"codex", "Codex", ProviderKind::Codex, true, "codex"});
  }
  if (const auto claude = DiscoverExecutable("claude"); claude.has_value()) {
    settings_.providers.push_back(ProviderConfig{"claude", "Claude", ProviderKind::ClaudeSubscription, true, "claude"});
  }
  ProviderConfig deepSeek;
  deepSeek.id = "deepseek";
  deepSeek.name = "DeepSeek";
  deepSeek.kind = ProviderKind::DeepSeek;
  deepSeek.baseUrl = "https://api.deepseek.com";
  deepSeek.balancePath = "/user/balance";
  settings_.providers.push_back(std::move(deepSeek));
  SaveSettings(paths_, settings_);
}

void MonitorApp::RebuildProviders() {
  scheduler_->Stop();
  std::vector<std::unique_ptr<IUsageProvider>> providers;
  for (const auto& config : settings_.providers) {
    if (!config.enabled) continue;
    auto runtimeConfig = config;
    if (const auto command = DefaultExecutableCommand(config.kind); command.has_value()) {
      if (runtimeConfig.executable.empty()) runtimeConfig.executable = *command;
      if (!runtimeConfig.executable.has_parent_path()) {
        if (const auto found = DiscoverExecutable(runtimeConfig.executable.string()); found.has_value()) {
          runtimeConfig.executable = *found;
        }
      }
    }
    providers.push_back(CreateProvider(runtimeConfig, *http_, *process_, *secrets_));
  }
  scheduler_->SetProviders(std::move(providers));
  scheduler_->SetInterval(std::chrono::minutes{settings_.refreshMinutes});
  scheduler_->Start();
  scheduler_->RefreshAll();
}

void MonitorApp::ReceiveSnapshot(ProviderSnapshot snapshot) {
  const auto found = snapshots_.find(snapshot.providerId);
  if (snapshot.health == Health::Error && found != snapshots_.end() && !found->second.metrics.empty()) {
    auto stale = found->second;
    stale.freshness = Freshness::Stale;
    stale.health = Health::Error;
    stale.error = snapshot.error;
    snapshots_[snapshot.providerId] = std::move(stale);
  } else {
    snapshots_[snapshot.providerId] = std::move(snapshot);
  }
  PublishSnapshots();
  std::vector<ProviderSnapshot> cache;
  for (const auto& [id, value] : snapshots_) {
    (void)id;
    if (!value.metrics.empty()) cache.push_back(value);
  }
  try { SaveCache(paths_, cache); } catch (...) {}
}

void MonitorApp::PublishSnapshots() {
  std::vector<ProviderSnapshot> ordered;
  for (const auto& config : settings_.providers) {
    const auto found = snapshots_.find(config.id);
    if (found != snapshots_.end()) {
      ordered.push_back(found->second);
    } else {
      ProviderSnapshot snapshot;
      snapshot.providerId = config.id;
      snapshot.displayName = config.name;
      snapshot.kind = config.kind;
      snapshot.health = config.enabled ? Health::Partial : Health::Disabled;
      snapshot.freshness = Freshness::NoData;
      if (config.enabled) snapshot.error = ProviderError{"waiting", "Esperando primera actualización", true, std::nullopt};
      ordered.push_back(std::move(snapshot));
    }
  }
  dashboard_->SetSnapshots(ordered);
  if (tray_) tray_->SetSnapshots(ordered);
#if defined(_WIN32) || defined(__linux__)
  if (overlay_) overlay_->SetSnapshots(ordered);
#endif
}

void MonitorApp::ShowDashboard() {
  if (!dashboard_) return;
  dashboard_->Show();
  dashboard_->Restore();
  dashboard_->Raise();
  dashboard_->SetFocus();
}

void MonitorApp::OpenSettings() {
  const auto previousProviders = settings_.providers;
  const int previousRefresh = settings_.refreshMinutes;
  std::string overlayHotkeyStatus;
#ifdef _WIN32
  if (overlay_) {
    overlayHotkeyStatus = overlay_->HotkeyAvailable()
                              ? "Atajo de recuperación: Ctrl+Alt+U · disponible"
                              : overlay_->HotkeyWarning();
  }
#endif
  SettingsDialog dialog(dashboard_.get(), settings_, paths_, *http_, *process_, *secrets_,
                        std::move(overlayHotkeyStatus));
  if (dialog.ShowModal() == wxID_OK) {
    dashboard_->ApplyAlwaysOnTop(settings_.alwaysOnTop);
#if defined(_WIN32) || defined(__linux__)
    ApplyOverlaySettings();
#endif
    if (previousProviders != settings_.providers || previousRefresh != settings_.refreshMinutes) {
      RebuildProviders();
    }
    PublishSnapshots();
  }
}

#if defined(_WIN32) || defined(__linux__)
void MonitorApp::ApplyOverlaySettings() {
  if (!settings_.overlay.enabled) {
    if (overlay_) {
      overlay_->Shutdown();
      auto* frame = overlay_.release();
      frame->Destroy();
    }
    return;
  }
  if (!overlay_) {
    overlay_ = std::make_unique<MinimalOverlayFrame>(settings_.overlay, [this](const OverlaySettings& overlay) {
      settings_.overlay = overlay;
      try { SaveSettings(paths_, settings_); } catch (...) {}
    });
  } else {
    overlay_->ApplySettings(settings_.overlay);
  }
}

void MonitorApp::ToggleOverlayVisibility() {
  if (!overlay_) return;
  if (overlay_->IsOverlayVisible()) overlay_->HideOverlay();
  else overlay_->ShowOverlay();
}
#endif

#ifdef _WIN32
void MonitorApp::ToggleOverlayLock() {
  if (overlay_) overlay_->ToggleLock();
}
#endif

void MonitorApp::MarkRefreshing(const std::string& providerId) {
  const auto config = std::find_if(settings_.providers.begin(), settings_.providers.end(),
                                   [&providerId](const ProviderConfig& value) { return value.id == providerId; });
  if (config == settings_.providers.end() || !config->enabled) return;
  auto& snapshot = snapshots_[providerId];
  snapshot.providerId = config->id;
  snapshot.displayName = config->name;
  snapshot.kind = config->kind;
  snapshot.health = Health::Partial;
  if (!snapshot.metrics.empty()) snapshot.freshness = Freshness::Stale;
  snapshot.error = ProviderError{"refreshing", "Actualizando…", true, std::nullopt};
}

void MonitorApp::RefreshAll() {
  if (!scheduler_) return;
  for (const auto& provider : settings_.providers) MarkRefreshing(provider.id);
  PublishSnapshots();
  scheduler_->RefreshAll();
}

void MonitorApp::StopActivationWatcher() {
  if (!activationThread_.joinable()) return;
  activationThread_.request_stop();
  instanceSignal_->SignalActivation();
  activationThread_.join();
}

void MonitorApp::ShutdownRuntime() {
  if (exiting_) return;
  exiting_ = true;
  StopActivationWatcher();
  if (!paths_.root.empty()) {
    std::error_code error;
    std::filesystem::remove(paths_.root / "ready.signal", error);
  }
  if (scheduler_) scheduler_->Stop();
#if defined(_WIN32) || defined(__linux__)
  if (overlay_) overlay_->Shutdown();
#endif
  if (tray_) tray_->RemoveIcon();
}

void MonitorApp::ExitApplication() {
  if (exiting_) return;
  ShutdownRuntime();
#if defined(_WIN32) || defined(__linux__)
  if (overlay_) {
    auto* frame = overlay_.release();
    frame->Destroy();
  }
#endif
  tray_.reset();
  if (dashboard_) {
    auto* frame = dashboard_.release();
    frame->Destroy();
  }
  ExitMainLoop();
}

int MonitorApp::OnExit() {
  ShutdownRuntime();
  return wxApp::OnExit();
}

#ifdef _WIN32
void MonitorApp::OnQueryEndSession(wxCloseEvent& event) {
  if (event.CanVeto()) event.Veto(false);
  // Handling the query here prevents wxWidgets from forwarding it to each
  // top-level window, where the dashboard's normal close-to-tray behavior
  // would veto the Windows session shutdown. Cleanup starts only after
  // Windows confirms the end of the session.
}
#endif

}  // namespace ai_usage::ui

wxIMPLEMENT_APP(ai_usage::ui::MonitorApp);
