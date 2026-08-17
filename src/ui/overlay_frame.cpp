#include "ui.h"

#include "app_icon.h"

#ifdef _WIN32

#include <wx/dcbuffer.h>
#include <wx/display.h>

#include <windows.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <sstream>

namespace ai_usage::ui {
namespace {

constexpr int RecoveryHotkeyId = 0xA117;
constexpr UINT OverlayForegroundEventMessage = WM_APP + 0x55;

struct MonitorData {
  HMONITOR handle{nullptr};
  RECT monitor{};
  RECT work{};
  std::string id;
  bool primary{false};
};

MinimalOverlayFrame* activeOverlay = nullptr;

std::string Utf8(const wchar_t* value) {
  return wxString(value).ToStdString(wxConvUTF8);
}

BOOL CALLBACK CollectMonitor(HMONITOR handle, HDC, LPRECT, LPARAM data) {
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(handle, &info)) return TRUE;
  auto* monitors = reinterpret_cast<std::vector<MonitorData>*>(data);
  monitors->push_back({handle, info.rcMonitor, info.rcWork, Utf8(info.szDevice),
                       (info.dwFlags & MONITORINFOF_PRIMARY) != 0});
  return TRUE;
}

std::vector<MonitorData> Monitors() {
  std::vector<MonitorData> result;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor, reinterpret_cast<LPARAM>(&result));
  return result;
}

MonitorData ResolveMonitor(std::string_view requested) {
  auto monitors = Monitors();
  if (monitors.empty()) {
    return {nullptr, {}, {0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)}, {}, true};
  }
  std::vector<std::string> ids;
  std::string primary;
  for (const auto& monitor : monitors) {
    ids.push_back(monitor.id);
    if (monitor.primary) primary = monitor.id;
  }
  const auto selected = SelectOverlayMonitor(requested, ids, primary);
  const auto found = std::find_if(monitors.begin(), monitors.end(), [&selected](const auto& monitor) {
    return monitor.id == selected;
  });
  return found == monitors.end() ? monitors.front() : *found;
}

MonitorData MonitorAtWindow(HWND window) {
  const auto handle = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  const auto monitors = Monitors();
  const auto found = std::find_if(monitors.begin(), monitors.end(), [handle](const auto& monitor) {
    return monitor.handle == handle;
  });
  return found == monitors.end() ? ResolveMonitor({}) : *found;
}

void CALLBACK OnWinEvent(HWINEVENTHOOK, DWORD event, HWND window, LONG objectId, LONG, DWORD, DWORD) {
  if (event == EVENT_OBJECT_LOCATIONCHANGE && objectId != OBJID_WINDOW) return;
  if (window == nullptr) return;
  if (activeOverlay != nullptr) {
    PostMessageW(reinterpret_cast<HWND>(activeOverlay->GetHandle()), OverlayForegroundEventMessage, 0, 0);
  }
}

wxColour Blend(const wxColour& first, const wxColour& second, double amount) {
  const auto channel = [amount](unsigned char left, unsigned char right) {
    return static_cast<unsigned char>(std::lround(left * (1.0 - amount) + right * amount));
  };
  return {channel(first.Red(), second.Red()), channel(first.Green(), second.Green()),
          channel(first.Blue(), second.Blue())};
}

}  // namespace

MinimalOverlayFrame::MinimalOverlayFrame(OverlaySettings settings, SettingsCallback settingsChanged)
    : wxFrame(nullptr, wxID_ANY, "AI Usage Monitor", wxDefaultPosition, wxSize(360, 120),
              wxBORDER_NONE | wxFRAME_NO_TASKBAR | wxSTAY_ON_TOP),
      settings_(std::move(settings)),
      settingsChanged_(std::move(settingsChanged)),
      countdownTimer_(this) {
  ApplyApplicationIcon(*this);
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  SetName("Overlay de cuotas de IA");
  Bind(wxEVT_PAINT, &MinimalOverlayFrame::OnPaint, this);
  Bind(wxEVT_LEFT_DOWN, &MinimalOverlayFrame::OnMouseDown, this);
  Bind(wxEVT_MOTION, &MinimalOverlayFrame::OnMouseMove, this);
  Bind(wxEVT_LEFT_UP, &MinimalOverlayFrame::OnMouseUp, this);
  Bind(wxEVT_ENTER_WINDOW, &MinimalOverlayFrame::OnMouseEnter, this);
  Bind(wxEVT_LEAVE_WINDOW, &MinimalOverlayFrame::OnMouseLeave, this);
  Bind(wxEVT_TIMER, &MinimalOverlayFrame::OnCountdown, this);
  Bind(wxEVT_DISPLAY_CHANGED, &MinimalOverlayFrame::OnDisplayChanged, this);
  activeOverlay = this;
  ApplyNativeStyles();
  ApplyOpacity();
  RegisterRecoveryHotkey();
  InstallForegroundHooks();
  ReprojectAndResize();
  if (settings_.visible) ShowOverlay();
}

MinimalOverlayFrame::~MinimalOverlayFrame() { Shutdown(); }

void MinimalOverlayFrame::SetSnapshots(const std::vector<ProviderSnapshot>& snapshots) {
  snapshots_ = snapshots;
  ReprojectAndResize();
}

void MinimalOverlayFrame::ApplySettings(const OverlaySettings& settings) {
  const bool visibilityChanged = settings_.visible != settings.visible;
  const bool suppressionChanged = settings_.suppressFullscreen != settings.suppressFullscreen;
  settings_ = settings;
  settings_.opacity = NormalizeOverlayOpacity(settings_.opacity);
  settings_.margin = NormalizeOverlayMargin(settings_.margin);
  ApplyNativeStyles();
  ApplyOpacity();
  ReprojectAndResize();
  if (visibilityChanged) {
    if (settings_.visible) ShowOverlay(); else Hide();
  }
  if (suppressionChanged) HandleForegroundEvent();
}

void MinimalOverlayFrame::ShowOverlay() {
  settings_.visible = true;
  HandleForegroundEvent();
  if (!suppressed_) {
    ShowWindow(reinterpret_cast<HWND>(GetHandle()), SW_SHOWNOACTIVATE);
    SetWindowPos(reinterpret_cast<HWND>(GetHandle()), HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
  PersistSettings();
}

void MinimalOverlayFrame::HideOverlay() {
  settings_.visible = false;
  suppressed_ = false;
  Hide();
  PersistSettings();
}

void MinimalOverlayFrame::ToggleLock() {
  settings_.locked = !settings_.locked;
  ApplyNativeStyles();
  ApplyOpacity(false);
  SetHelpText(settings_.locked ? wxString{} : GetName());
  PersistSettings();
  Refresh(false);
}

void MinimalOverlayFrame::ApplyNativeStyles() {
  const auto window = reinterpret_cast<HWND>(GetHandle());
  auto styles = GetWindowLongPtrW(window, GWL_EXSTYLE);
  styles |= WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED;
  styles &= ~static_cast<LONG_PTR>(WS_EX_APPWINDOW);
  if (settings_.locked) styles |= WS_EX_TRANSPARENT;
  else styles &= ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT);
  SetWindowLongPtrW(window, GWL_EXSTYLE, styles);
  SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void MinimalOverlayFrame::ApplyOpacity(bool hovered) {
  const int opacity = hovered && !settings_.locked ? std::max(95, settings_.opacity) : settings_.opacity;
  const auto alpha = static_cast<BYTE>(NormalizeOverlayOpacity(opacity) * 255 / 100);
  SetLayeredWindowAttributes(reinterpret_cast<HWND>(GetHandle()), 0, alpha, LWA_ALPHA);
}

void MinimalOverlayFrame::UpdateRoundedRegion() {
  const int radius = FromDIP(14);
  const auto size = GetSize();
  const auto region = CreateRoundRectRgn(0, 0, size.x + 1, size.y + 1, radius, radius);
  SetWindowRgn(reinterpret_cast<HWND>(GetHandle()), region, TRUE);
}

void MinimalOverlayFrame::ReprojectAndResize(bool reanchor) {
  const auto monitor = ResolveMonitor(settings_.monitor);
  const int workHeight = monitor.work.bottom - monitor.work.top;
  const int headerHeight = FromDIP(34);
  const int rowHeight = FromDIP(52);
  const int overflowHeight = FromDIP(26);
  const int padding = FromDIP(10);
  const auto capacity = OverlayRowCapacity(workHeight, headerHeight + padding, rowHeight);
  projection_ = ProjectOverlayRows(snapshots_, Clock::now(), capacity);
  int height = headerHeight + padding + static_cast<int>(projection_.rows.size()) * rowHeight;
  if (projection_.hiddenCount > 0) height += overflowHeight;
  height = std::max(height, FromDIP(68));
  height = std::min(height, static_cast<int>(std::floor(workHeight * 0.4)));
  SetSize(wxSize(FromDIP(360), height));
  UpdateRoundedRegion();

  std::ostringstream summary;
  summary << "Overlay de uso. ";
  for (const auto& row : projection_.rows) {
    summary << row.providerName << ", " << row.label << ", " << row.value;
    if (!row.resetText.empty()) summary << ", " << row.resetText;
    if (!row.statusText.empty()) summary << ", " << row.statusText;
    summary << ". ";
  }
  if (projection_.hiddenCount > 0) summary << projection_.hiddenCount << " cuotas adicionales.";
  if (!settings_.locked) SetHelpText(wxString::FromUTF8(summary.str()));
  if (reanchor) AnchorToSavedCorner();
  ScheduleCountdown();
  Refresh(false);
}

void MinimalOverlayFrame::AnchorToSavedCorner() {
  const auto monitor = ResolveMonitor(settings_.monitor);
  settings_.monitor = monitor.id;
  const auto size = GetSize();
  const int margin = FromDIP(settings_.margin);
  int x = monitor.work.left + margin;
  int y = monitor.work.top + margin;
  if (settings_.corner == OverlayCorner::TopRight || settings_.corner == OverlayCorner::BottomRight) {
    x = monitor.work.right - size.x - margin;
  }
  if (settings_.corner == OverlayCorner::BottomLeft || settings_.corner == OverlayCorner::BottomRight) {
    y = monitor.work.bottom - size.y - margin;
  }
  x = std::clamp(x, static_cast<int>(monitor.work.left), static_cast<int>(monitor.work.right - size.x));
  y = std::clamp(y, static_cast<int>(monitor.work.top), static_cast<int>(monitor.work.bottom - size.y));
  SetWindowPos(reinterpret_cast<HWND>(GetHandle()), HWND_TOPMOST, x, y, size.x, size.y, SWP_NOACTIVATE);
}

void MinimalOverlayFrame::SnapToNearestCorner() {
  const auto monitor = MonitorAtWindow(reinterpret_cast<HWND>(GetHandle()));
  const auto rect = GetRect();
  const int margin = FromDIP(settings_.margin);
  settings_.corner = NearestOverlayCorner(rect.x, rect.y, rect.width, rect.height, monitor.work.left,
                                          monitor.work.top, monitor.work.right, monitor.work.bottom, margin);
  settings_.monitor = monitor.id;
  AnchorToSavedCorner();
  PersistSettings();
}

void MinimalOverlayFrame::ScheduleCountdown() {
  countdownTimer_.Stop();
  const auto now = Clock::now();
  const auto next = NextOverlayCountdownUpdate(projection_.rows, now);
  if (!next.has_value()) return;
  const auto delay = std::max(std::chrono::milliseconds{1},
                              std::chrono::duration_cast<std::chrono::milliseconds>(*next - now));
  const auto bounded = std::min<std::int64_t>(delay.count(), std::numeric_limits<int>::max());
  countdownTimer_.StartOnce(static_cast<int>(bounded));
}

void MinimalOverlayFrame::PersistSettings() {
  if (settingsChanged_ && !shuttingDown_) settingsChanged_(settings_);
}

void MinimalOverlayFrame::OnPaint(wxPaintEvent&) {
  wxAutoBufferedPaintDC dc(this);
  const auto theme = ResolveTheme(this);
  const auto size = GetClientSize();
  dc.SetBackground(wxBrush(theme.surface));
  dc.Clear();
  dc.SetPen(*wxTRANSPARENT_PEN);
  dc.SetBrush(wxBrush(theme.surface));
  dc.DrawRoundedRectangle(0, 0, size.x, size.y, FromDIP(theme.radius));

  const int padding = FromDIP(12);
  int y = FromDIP(9);
  dc.SetFont(theme.sectionFont);
  dc.SetTextForeground(theme.text);
  dc.DrawText("Uso de IA", padding, y);
  dc.SetFont(theme.bodyFont);
  const wxString lockText = settings_.locked ? wxS("bloqueado") : wxS("mover");
  const auto lockSize = dc.GetTextExtent(lockText);
  dc.SetTextForeground(theme.mutedText);
  dc.DrawText(lockText, size.x - padding - lockSize.x, y);
  y = FromDIP(36);

  const int rowHeight = FromDIP(52);
  for (const auto& row : projection_.rows) {
    const wxString provider = wxString::FromUTF8(row.providerName);
    const wxString label = wxString::FromUTF8(row.label);
    const wxString value = wxString::FromUTF8(row.value);
    dc.SetFont(theme.bodyFont.Bold());
    dc.SetTextForeground(theme.text);
    dc.DrawText(provider + wxS("  ·  ") + label, padding, y);
    dc.SetFont(theme.bodyFont);
    const auto valueSize = dc.GetTextExtent(value);
    dc.DrawText(value, size.x - padding - valueSize.x, y);

    const int detailsY = y + FromDIP(21);
    wxString detail = wxString::FromUTF8(row.resetText);
    if (!row.statusText.empty()) {
      if (!detail.empty()) detail += wxS("  ·  ");
      detail += wxString::FromUTF8(row.statusText);
    }
    const auto detailSize = dc.GetTextExtent(detail);
    if (row.usedPercent.has_value()) {
      const int trackWidth = std::max(FromDIP(72), size.x - padding * 3 - detailSize.x);
      dc.SetPen(*wxTRANSPARENT_PEN);
      dc.SetBrush(wxBrush(Blend(theme.border, theme.surface, 0.25)));
      dc.DrawRoundedRectangle(padding, detailsY + FromDIP(4), trackWidth, FromDIP(5), FromDIP(3));
      dc.SetBrush(wxBrush(theme.accent));
      dc.DrawRoundedRectangle(padding, detailsY + FromDIP(4),
                              static_cast<int>(std::lround(trackWidth * *row.usedPercent / 100.0)),
                              FromDIP(5), FromDIP(3));
    }
    dc.SetTextForeground(row.statusText.starts_with("error") ? theme.error : theme.mutedText);
    dc.DrawText(detail, size.x - padding - detailSize.x, detailsY);
    y += rowHeight;
  }
  if (projection_.rows.empty() && projection_.hiddenCount == 0) {
    dc.SetFont(theme.bodyFont);
    dc.SetTextForeground(theme.mutedText);
    dc.DrawText("Esperando métricas", padding, y + FromDIP(5));
  } else if (projection_.hiddenCount > 0) {
    dc.SetFont(theme.bodyFont.Bold());
    dc.SetTextForeground(theme.mutedText);
    dc.DrawText("+ " + std::to_string(projection_.hiddenCount) + " cuotas", padding, y);
  }
}

void MinimalOverlayFrame::OnMouseDown(wxMouseEvent& event) {
  if (settings_.locked) return;
  dragging_ = true;
  dragOrigin_ = ClientToScreen(event.GetPosition());
  windowOrigin_ = GetPosition();
  CaptureMouse();
}

void MinimalOverlayFrame::OnMouseMove(wxMouseEvent& event) {
  if (!dragging_ || !event.Dragging() || !event.LeftIsDown()) return;
  const auto current = ClientToScreen(event.GetPosition());
  const auto delta = current - dragOrigin_;
  SetWindowPos(reinterpret_cast<HWND>(GetHandle()), HWND_TOPMOST, windowOrigin_.x + delta.x,
               windowOrigin_.y + delta.y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
}

void MinimalOverlayFrame::OnMouseUp(wxMouseEvent&) {
  if (!dragging_) return;
  dragging_ = false;
  if (HasCapture()) ReleaseMouse();
  SnapToNearestCorner();
}

void MinimalOverlayFrame::OnMouseEnter(wxMouseEvent&) { ApplyOpacity(true); }

void MinimalOverlayFrame::OnMouseLeave(wxMouseEvent&) { ApplyOpacity(false); }

void MinimalOverlayFrame::OnCountdown(wxTimerEvent&) {
  const auto updated = ProjectOverlayRows(snapshots_, Clock::now(),
                                          projection_.rows.size() + (projection_.hiddenCount > 0 ? 1U : 0U));
  bool changed = updated.rows.size() != projection_.rows.size();
  if (!changed) {
    for (std::size_t index = 0; index < updated.rows.size(); ++index) {
      if (updated.rows[index].resetText != projection_.rows[index].resetText) {
        changed = true;
        break;
      }
    }
  }
  projection_ = updated;
  if (changed) Refresh(false);
  ScheduleCountdown();
}

void MinimalOverlayFrame::OnDisplayChanged(wxDisplayChangedEvent& event) {
  event.Skip();
  ReprojectAndResize();
}

void MinimalOverlayFrame::RegisterRecoveryHotkey() {
  if (hotkeyAvailable_) return;
  hotkeyAvailable_ = ::RegisterHotKey(reinterpret_cast<HWND>(GetHandle()), RecoveryHotkeyId,
                                      MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'U') != FALSE;
  hotkeyWarning_ = hotkeyAvailable_ ? std::string{}
                                    : "Ctrl+Alt+U ya está registrado por otra aplicación; use el menú de bandeja.";
}

void MinimalOverlayFrame::UnregisterRecoveryHotkey() {
  if (!hotkeyAvailable_) return;
  ::UnregisterHotKey(reinterpret_cast<HWND>(GetHandle()), RecoveryHotkeyId);
  hotkeyAvailable_ = false;
}

void MinimalOverlayFrame::InstallForegroundHooks() {
  if (!settings_.suppressFullscreen || foregroundHook_ != nullptr) return;
  activeOverlay = this;
  foregroundHook_ = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr, OnWinEvent,
                                    0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
  locationHook_ = SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_LOCATIONCHANGE, nullptr, OnWinEvent,
                                  0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
}

void MinimalOverlayFrame::RemoveForegroundHooks() {
  if (foregroundHook_ != nullptr) UnhookWinEvent(reinterpret_cast<HWINEVENTHOOK>(foregroundHook_));
  if (locationHook_ != nullptr) UnhookWinEvent(reinterpret_cast<HWINEVENTHOOK>(locationHook_));
  foregroundHook_ = nullptr;
  locationHook_ = nullptr;
}

void MinimalOverlayFrame::HandleForegroundEvent() {
  if (shuttingDown_) return;
  if (!settings_.suppressFullscreen) {
    RemoveForegroundHooks();
    suppressed_ = false;
    if (settings_.visible) ShowWindow(reinterpret_cast<HWND>(GetHandle()), SW_SHOWNOACTIVATE);
    return;
  }
  InstallForegroundHooks();
  HandleForegroundWindow(GetForegroundWindow());
}

void MinimalOverlayFrame::HandleForegroundWindow(void* foregroundWindow) {
  const auto foreground = reinterpret_cast<HWND>(foregroundWindow);
  const auto overlayWindow = reinterpret_cast<HWND>(GetHandle());
  bool fullscreen = false;
  if (foreground != nullptr && foreground != overlayWindow && IsWindowVisible(foreground) && !IsIconic(foreground)) {
    RECT foregroundRect{};
    if (GetWindowRect(foreground, &foregroundRect)) {
      const auto target = ResolveMonitor(settings_.monitor);
      fullscreen = CoversOverlayMonitor(foregroundRect.left, foregroundRect.top, foregroundRect.right,
                                        foregroundRect.bottom, target.monitor.left, target.monitor.top,
                                        target.monitor.right, target.monitor.bottom);
    }
  }
  if (fullscreen != suppressed_) {
    suppressed_ = fullscreen;
    if (suppressed_) Hide();
    else if (settings_.visible) ShowWindow(overlayWindow, SW_SHOWNOACTIVATE);
  }
}

void MinimalOverlayFrame::Shutdown() {
  if (shuttingDown_) return;
  shuttingDown_ = true;
  countdownTimer_.Stop();
  RemoveForegroundHooks();
  UnregisterRecoveryHotkey();
  if (activeOverlay == this) activeOverlay = nullptr;
  Hide();
}

WXLRESULT MinimalOverlayFrame::MSWWindowProc(WXUINT message, WXWPARAM wParam, WXLPARAM lParam) {
  if (message == OverlayForegroundEventMessage) {
    HandleForegroundEvent();
    return 0;
  }
  if (message == WM_HOTKEY && static_cast<int>(wParam) == RecoveryHotkeyId) {
    ToggleLock();
    return 0;
  }
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  if (message == WM_NCHITTEST && settings_.locked) return HTTRANSPARENT;
  if (message == WM_MOUSEMOVE && !settings_.locked) {
    TRACKMOUSEEVENT tracking{};
    tracking.cbSize = sizeof(tracking);
    tracking.dwFlags = TME_LEAVE;
    tracking.hwndTrack = reinterpret_cast<HWND>(GetHandle());
    TrackMouseEvent(&tracking);
    ApplyOpacity(true);
  }
  if (message == WM_MOUSEHOVER && !settings_.locked) {
    ApplyOpacity(true);
    return 0;
  }
  if (message == WM_MOUSELEAVE) ApplyOpacity(false);
  if (message == WM_DPICHANGED) {
    const auto* suggested = reinterpret_cast<RECT*>(lParam);
    SetWindowPos(reinterpret_cast<HWND>(GetHandle()), HWND_TOPMOST, suggested->left, suggested->top,
                 suggested->right - suggested->left, suggested->bottom - suggested->top, SWP_NOACTIVATE);
    CallAfter([this] { ReprojectAndResize(); });
    return 0;
  }
  return wxFrame::MSWWindowProc(message, wParam, lParam);
}

}  // namespace ai_usage::ui

#elif defined(__linux__)

#include <wx/dcbuffer.h>
#include <wx/display.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <sstream>

namespace ai_usage::ui {
namespace {

struct MonitorData {
  int index{-1};
  wxRect monitor{};
  wxRect work{};
  std::string id;
  bool primary{false};
};

wxColour Blend(const wxColour& first, const wxColour& second, double amount) {
  const auto channel = [amount](unsigned char left, unsigned char right) {
    return static_cast<unsigned char>(std::lround(left * (1.0 - amount) + right * amount));
  };
  return {channel(first.Red(), second.Red()), channel(first.Green(), second.Green()),
          channel(first.Blue(), second.Blue())};
}

std::vector<MonitorData> Monitors() {
  std::vector<MonitorData> result;
  const unsigned count = wxDisplay::GetCount();
  for (unsigned index = 0; index < count; ++index) {
    const wxDisplay display(index);
    MonitorData data;
    data.index = static_cast<int>(index);
    data.monitor = display.GetGeometry();
    data.work = display.GetClientArea();
    data.primary = display.IsPrimary();
    const auto name = display.GetName().ToStdString(wxConvUTF8);
    data.id = name.empty() ? ("display-" + std::to_string(index)) : name;
    result.push_back(std::move(data));
  }
  if (result.empty()) {
    MonitorData fallback;
    fallback.index = 0;
    fallback.monitor = wxRect(0, 0, 1920, 1080);
    fallback.work = fallback.monitor;
    fallback.primary = true;
    fallback.id = "display-0";
    result.push_back(fallback);
  }
  return result;
}

MonitorData ResolveMonitor(std::string_view requested) {
  const auto monitors = Monitors();
  std::vector<std::string> ids;
  std::string primary;
  for (const auto& monitor : monitors) {
    ids.push_back(monitor.id);
    if (monitor.primary) primary = monitor.id;
  }
  const auto selected = SelectOverlayMonitor(requested, ids, primary);
  const auto found = std::find_if(monitors.begin(), monitors.end(), [&selected](const auto& monitor) {
    return monitor.id == selected;
  });
  return found == monitors.end() ? monitors.front() : *found;
}

MonitorData MonitorAtPoint(const wxPoint& point) {
  const int index = wxDisplay::GetFromPoint(point);
  if (index == wxNOT_FOUND) return ResolveMonitor({});
  const auto monitors = Monitors();
  const auto found = std::find_if(monitors.begin(), monitors.end(),
                                  [index](const auto& monitor) { return monitor.index == index; });
  return found == monitors.end() ? ResolveMonitor({}) : *found;
}

}  // namespace

MinimalOverlayFrame::MinimalOverlayFrame(OverlaySettings settings, SettingsCallback settingsChanged)
    : wxFrame(nullptr, wxID_ANY, "AI Usage Monitor", wxDefaultPosition, wxSize(360, 120),
              wxBORDER_NONE | wxFRAME_NO_TASKBAR | wxSTAY_ON_TOP),
      settings_(std::move(settings)),
      settingsChanged_(std::move(settingsChanged)),
      countdownTimer_(this) {
  ApplyApplicationIcon(*this);
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  SetName("Overlay de cuotas de IA");
  Bind(wxEVT_PAINT, &MinimalOverlayFrame::OnPaint, this);
  Bind(wxEVT_LEFT_DOWN, &MinimalOverlayFrame::OnMouseDown, this);
  Bind(wxEVT_MOTION, &MinimalOverlayFrame::OnMouseMove, this);
  Bind(wxEVT_LEFT_UP, &MinimalOverlayFrame::OnMouseUp, this);
  Bind(wxEVT_ENTER_WINDOW, &MinimalOverlayFrame::OnMouseEnter, this);
  Bind(wxEVT_LEAVE_WINDOW, &MinimalOverlayFrame::OnMouseLeave, this);
  Bind(wxEVT_TIMER, &MinimalOverlayFrame::OnCountdown, this);
  Bind(wxEVT_DISPLAY_CHANGED, &MinimalOverlayFrame::OnDisplayChanged, this);
  ApplyOpacity();
  ReprojectAndResize();
  if (settings_.visible) ShowOverlay();
}

MinimalOverlayFrame::~MinimalOverlayFrame() { Shutdown(); }

void MinimalOverlayFrame::SetSnapshots(const std::vector<ProviderSnapshot>& snapshots) {
  snapshots_ = snapshots;
  ReprojectAndResize();
}

void MinimalOverlayFrame::ApplySettings(const OverlaySettings& settings) {
  const bool visibilityChanged = settings_.visible != settings.visible;
  settings_ = settings;
  settings_.opacity = NormalizeOverlayOpacity(settings_.opacity);
  settings_.margin = NormalizeOverlayMargin(settings_.margin);
  ApplyOpacity();
  ReprojectAndResize();
  if (visibilityChanged) {
    if (settings_.visible) ShowOverlay(); else Hide();
  }
}

void MinimalOverlayFrame::ShowOverlay() {
  settings_.visible = true;
  Show();
  Raise();
  PersistSettings();
}

void MinimalOverlayFrame::HideOverlay() {
  settings_.visible = false;
  Hide();
  PersistSettings();
}

void MinimalOverlayFrame::ApplyOpacity(bool hovered) {
  const int opacity = hovered ? std::max(95, settings_.opacity) : settings_.opacity;
  const auto alpha = static_cast<unsigned char>(NormalizeOverlayOpacity(opacity) * 255 / 100);
  SetTransparent(alpha);
}

void MinimalOverlayFrame::ReprojectAndResize(bool reanchor) {
  const auto monitor = ResolveMonitor(settings_.monitor);
  const int workHeight = monitor.work.GetHeight();
  const int headerHeight = FromDIP(34);
  const int rowHeight = FromDIP(52);
  const int overflowHeight = FromDIP(26);
  const int padding = FromDIP(10);
  const auto capacity = OverlayRowCapacity(workHeight, headerHeight + padding, rowHeight);
  projection_ = ProjectOverlayRows(snapshots_, Clock::now(), capacity);
  int height = headerHeight + padding + static_cast<int>(projection_.rows.size()) * rowHeight;
  if (projection_.hiddenCount > 0) height += overflowHeight;
  height = std::max(height, FromDIP(68));
  height = std::min(height, static_cast<int>(std::floor(workHeight * 0.4)));
  SetSize(wxSize(FromDIP(360), height));

  std::ostringstream summary;
  summary << "Overlay de uso. ";
  for (const auto& row : projection_.rows) {
    summary << row.providerName << ", " << row.label << ", " << row.value;
    if (!row.resetText.empty()) summary << ", " << row.resetText;
    if (!row.statusText.empty()) summary << ", " << row.statusText;
    summary << ". ";
  }
  if (projection_.hiddenCount > 0) summary << projection_.hiddenCount << " cuotas adicionales.";
  SetHelpText(wxString::FromUTF8(summary.str()));
  if (reanchor) AnchorToSavedCorner();
  ScheduleCountdown();
  Refresh(false);
}

void MinimalOverlayFrame::AnchorToSavedCorner() {
  const auto monitor = ResolveMonitor(settings_.monitor);
  settings_.monitor = monitor.id;
  const auto size = GetSize();
  const int margin = FromDIP(settings_.margin);
  const int workLeft = monitor.work.GetX();
  const int workTop = monitor.work.GetY();
  const int workRight = monitor.work.GetX() + monitor.work.GetWidth();
  const int workBottom = monitor.work.GetY() + monitor.work.GetHeight();
  int x = workLeft + margin;
  int y = workTop + margin;
  if (settings_.corner == OverlayCorner::TopRight || settings_.corner == OverlayCorner::BottomRight) {
    x = workRight - size.x - margin;
  }
  if (settings_.corner == OverlayCorner::BottomLeft || settings_.corner == OverlayCorner::BottomRight) {
    y = workBottom - size.y - margin;
  }
  x = std::clamp(x, workLeft, workRight - size.x);
  y = std::clamp(y, workTop, workBottom - size.y);
  Move(x, y);
}

void MinimalOverlayFrame::SnapToNearestCorner() {
  const auto monitor = MonitorAtPoint(GetPosition());
  const auto rect = GetRect();
  const int margin = FromDIP(settings_.margin);
  const int workRight = monitor.work.GetX() + monitor.work.GetWidth();
  const int workBottom = monitor.work.GetY() + monitor.work.GetHeight();
  settings_.corner = NearestOverlayCorner(rect.x, rect.y, rect.width, rect.height, monitor.work.GetX(),
                                          monitor.work.GetY(), workRight, workBottom, margin);
  settings_.monitor = monitor.id;
  AnchorToSavedCorner();
  PersistSettings();
}

void MinimalOverlayFrame::ScheduleCountdown() {
  countdownTimer_.Stop();
  const auto now = Clock::now();
  const auto next = NextOverlayCountdownUpdate(projection_.rows, now);
  if (!next.has_value()) return;
  const auto delay = std::max(std::chrono::milliseconds{1},
                              std::chrono::duration_cast<std::chrono::milliseconds>(*next - now));
  const auto bounded = std::min<std::int64_t>(delay.count(), std::numeric_limits<int>::max());
  countdownTimer_.StartOnce(static_cast<int>(bounded));
}

void MinimalOverlayFrame::PersistSettings() {
  if (settingsChanged_ && !shuttingDown_) settingsChanged_(settings_);
}

void MinimalOverlayFrame::OnPaint(wxPaintEvent&) {
  wxAutoBufferedPaintDC dc(this);
  const auto theme = ResolveTheme(this);
  const auto size = GetClientSize();
  dc.SetBackground(wxBrush(theme.surface));
  dc.Clear();
  dc.SetPen(*wxTRANSPARENT_PEN);
  dc.SetBrush(wxBrush(theme.surface));
  dc.DrawRoundedRectangle(0, 0, size.x, size.y, FromDIP(theme.radius));

  const int padding = FromDIP(12);
  int y = FromDIP(9);
  dc.SetFont(theme.sectionFont);
  dc.SetTextForeground(theme.text);
  dc.DrawText("Uso de IA", padding, y);
  y = FromDIP(36);

  const int rowHeight = FromDIP(52);
  for (const auto& row : projection_.rows) {
    const wxString provider = wxString::FromUTF8(row.providerName);
    const wxString label = wxString::FromUTF8(row.label);
    const wxString value = wxString::FromUTF8(row.value);
    dc.SetFont(theme.bodyFont.Bold());
    dc.SetTextForeground(theme.text);
    dc.DrawText(provider + wxS("  ·  ") + label, padding, y);
    dc.SetFont(theme.bodyFont);
    const auto valueSize = dc.GetTextExtent(value);
    dc.DrawText(value, size.x - padding - valueSize.x, y);

    const int detailsY = y + FromDIP(21);
    wxString detail = wxString::FromUTF8(row.resetText);
    if (!row.statusText.empty()) {
      if (!detail.empty()) detail += wxS("  ·  ");
      detail += wxString::FromUTF8(row.statusText);
    }
    const auto detailSize = dc.GetTextExtent(detail);
    if (row.usedPercent.has_value()) {
      const int trackWidth = std::max(FromDIP(72), size.x - padding * 3 - detailSize.x);
      dc.SetPen(*wxTRANSPARENT_PEN);
      dc.SetBrush(wxBrush(Blend(theme.border, theme.surface, 0.25)));
      dc.DrawRoundedRectangle(padding, detailsY + FromDIP(4), trackWidth, FromDIP(5), FromDIP(3));
      dc.SetBrush(wxBrush(theme.accent));
      dc.DrawRoundedRectangle(padding, detailsY + FromDIP(4),
                              static_cast<int>(std::lround(trackWidth * *row.usedPercent / 100.0)),
                              FromDIP(5), FromDIP(3));
    }
    dc.SetTextForeground(row.statusText.starts_with("error") ? theme.error : theme.mutedText);
    dc.DrawText(detail, size.x - padding - detailSize.x, detailsY);
    y += rowHeight;
  }
  if (projection_.rows.empty() && projection_.hiddenCount == 0) {
    dc.SetFont(theme.bodyFont);
    dc.SetTextForeground(theme.mutedText);
    dc.DrawText("Esperando métricas", padding, y + FromDIP(5));
  } else if (projection_.hiddenCount > 0) {
    dc.SetFont(theme.bodyFont.Bold());
    dc.SetTextForeground(theme.mutedText);
    dc.DrawText("+ " + std::to_string(projection_.hiddenCount) + " cuotas", padding, y);
  }
}

void MinimalOverlayFrame::OnMouseDown(wxMouseEvent& event) {
  dragging_ = true;
  dragOrigin_ = ClientToScreen(event.GetPosition());
  windowOrigin_ = GetPosition();
  CaptureMouse();
}

void MinimalOverlayFrame::OnMouseMove(wxMouseEvent& event) {
  if (!dragging_ || !event.Dragging() || !event.LeftIsDown()) return;
  const auto current = ClientToScreen(event.GetPosition());
  const auto delta = current - dragOrigin_;
  Move(windowOrigin_.x + delta.x, windowOrigin_.y + delta.y);
}

void MinimalOverlayFrame::OnMouseUp(wxMouseEvent&) {
  if (!dragging_) return;
  dragging_ = false;
  if (HasCapture()) ReleaseMouse();
  SnapToNearestCorner();
}

void MinimalOverlayFrame::OnMouseEnter(wxMouseEvent&) { ApplyOpacity(true); }

void MinimalOverlayFrame::OnMouseLeave(wxMouseEvent&) { ApplyOpacity(false); }

void MinimalOverlayFrame::OnCountdown(wxTimerEvent&) {
  const auto updated = ProjectOverlayRows(snapshots_, Clock::now(),
                                          projection_.rows.size() + (projection_.hiddenCount > 0 ? 1U : 0U));
  bool changed = updated.rows.size() != projection_.rows.size();
  if (!changed) {
    for (std::size_t index = 0; index < updated.rows.size(); ++index) {
      if (updated.rows[index].resetText != projection_.rows[index].resetText) {
        changed = true;
        break;
      }
    }
  }
  projection_ = updated;
  if (changed) Refresh(false);
  ScheduleCountdown();
}

void MinimalOverlayFrame::OnDisplayChanged(wxDisplayChangedEvent& event) {
  event.Skip();
  ReprojectAndResize();
}

void MinimalOverlayFrame::Shutdown() {
  if (shuttingDown_) return;
  shuttingDown_ = true;
  countdownTimer_.Stop();
  Hide();
}

}  // namespace ai_usage::ui

#endif
