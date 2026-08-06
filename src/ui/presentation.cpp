#include "presentation.h"

#include <wx/button.h>
#include <wx/dcbuffer.h>
#include <wx/settings.h>
#include <wx/sizer.h>
#include <wx/utils.h>

#include <algorithm>
#include <cmath>

namespace ai_usage::ui {
namespace {

PresentationRgb ToRgb(const wxColour& colour) { return {colour.Red(), colour.Green(), colour.Blue()}; }

wxColour FromRgb(PresentationRgb colour) { return wxColour(colour.red, colour.green, colour.blue); }

wxColour Readable(wxColour preferred, wxColour background) {
  return FromRgb(EnsureTextContrast(ToRgb(preferred), ToRgb(background)));
}

wxColour Blend(const wxColour& first, const wxColour& second, double amount) {
  const auto channel = [amount](int left, int right) {
    return std::clamp(static_cast<int>(std::lround(left + (right - left) * amount)), 0, 255);
  };
  return wxColour(channel(first.Red(), second.Red()), channel(first.Green(), second.Green()),
                  channel(first.Blue(), second.Blue()));
}

wxColour Tone(const PresentationTheme& theme, StatusTone tone) {
  switch (tone) {
    case StatusTone::Accent: return theme.accent;
    case StatusTone::Success: return theme.success;
    case StatusTone::Warning: return theme.warning;
    case StatusTone::Error: return theme.error;
    case StatusTone::Neutral: return theme.mutedText;
  }
  return theme.mutedText;
}

}  // namespace

PresentationTheme ResolveTheme(wxWindow* window) {
  PresentationTheme theme;
  const auto systemBackground = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW);
  const auto systemText = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
  theme.dark = RelativeLuminance(ToRgb(systemBackground)) < 0.35;
  wxString forcedTheme;
  if (wxGetEnv("AI_USAGE_UI_THEME", &forcedTheme)) {
    if (forcedTheme.CmpNoCase("dark") == 0) theme.dark = true;
    if (forcedTheme.CmpNoCase("light") == 0) theme.dark = false;
  }
  if (theme.dark) {
    theme.canvas = wxColour(15, 19, 28);
    theme.surface = wxColour(24, 30, 42);
    theme.elevated = wxColour(31, 39, 54);
    theme.text = wxColour(238, 242, 250);
    theme.mutedText = wxColour(173, 183, 201);
    theme.border = wxColour(54, 65, 84);
    theme.accent = wxColour(124, 139, 255);
    theme.focus = wxColour(154, 166, 255);
    theme.success = wxColour(73, 190, 132);
    theme.warning = wxColour(244, 184, 74);
    theme.error = wxColour(247, 112, 124);
  } else {
    theme.canvas = wxColour(244, 247, 252);
    theme.surface = wxColour(255, 255, 255);
    theme.elevated = wxColour(249, 251, 255);
    theme.text = wxColour(24, 32, 48);
    theme.mutedText = wxColour(88, 101, 124);
    theme.border = wxColour(218, 225, 237);
    theme.accent = wxColour(74, 91, 214);
    theme.focus = wxColour(62, 84, 232);
    theme.success = wxColour(28, 126, 82);
    theme.warning = wxColour(157, 96, 10);
    theme.error = wxColour(190, 48, 65);
  }
  if (!systemBackground.IsOk() || !systemText.IsOk()) {
    theme.canvas = theme.dark ? wxColour(15, 19, 28) : wxColour(244, 247, 252);
    theme.text = theme.dark ? wxColour(238, 242, 250) : wxColour(24, 32, 48);
  }
  theme.text = Readable(theme.text, theme.surface);
  theme.mutedText = Readable(theme.mutedText, theme.surface);
  theme.onAccent = Readable(wxColour(255, 255, 255), theme.accent);
  const auto base = window != nullptr ? window->GetFont() : wxSystemSettings::GetFont(wxSYS_DEFAULT_GUI_FONT);
  theme.bodyFont = base;
  theme.titleFont = base.Bold().Scale(1.45F);
  theme.sectionFont = base.Bold().Scale(1.08F);
  theme.metricFont = base.Bold().Scale(1.65F);
  if (window != nullptr) {
    theme.spaceXs = window->FromDIP(4);
    theme.spaceSm = window->FromDIP(8);
    theme.spaceMd = window->FromDIP(12);
    theme.spaceLg = window->FromDIP(18);
    theme.radius = window->FromDIP(10);
  }
  return theme;
}

void ApplyTheme(wxWindow* root, const PresentationTheme& theme) {
  if (root == nullptr) return;
  root->SetForegroundColour(theme.text);
  if (auto* notice = dynamic_cast<SemanticNotice*>(root); notice != nullptr) {
    notice->SetPresentationTheme(theme);
  } else if (auto* panel = dynamic_cast<ModernPanel*>(root); panel != nullptr) {
    panel->SetPresentationTheme(theme);
  } else if (dynamic_cast<wxPanel*>(root) != nullptr) {
    root->SetBackgroundColour(theme.canvas);
  } else if (dynamic_cast<wxStaticText*>(root) != nullptr && root->GetParent() != nullptr) {
    root->SetBackgroundColour(root->GetParent()->GetBackgroundColour());
  }
  for (auto* child : root->GetChildren()) ApplyTheme(child, theme);
  root->Refresh();
}

void StyleButton(wxButton* button, const PresentationTheme& theme, ButtonTone tone) {
  if (button == nullptr) return;
  wxColour background = theme.elevated;
  wxColour foreground = theme.text;
  if (tone == ButtonTone::Primary) {
    background = theme.accent;
    foreground = theme.onAccent;
  } else if (tone == ButtonTone::Destructive) {
    background = Blend(theme.error, theme.surface, theme.dark ? 0.72 : 0.9);
    foreground = theme.error;
  }
  button->SetBackgroundColour(background);
  button->SetForegroundColour(foreground);
  button->SetFont(theme.bodyFont.Bold());
  button->SetMinSize(wxSize(-1, button->FromDIP(34)));
}

ModernPanel::ModernPanel(wxWindow* parent, const PresentationTheme& theme, bool elevated)
    : wxPanel(parent, wxID_ANY), theme_(theme), elevated_(elevated) {
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  SetPresentationTheme(theme);
  Bind(wxEVT_PAINT, &ModernPanel::OnPaint, this);
}

void ModernPanel::SetPresentationTheme(const PresentationTheme& theme) {
  theme_ = theme;
  SetForegroundColour(theme.text);
  SetBackgroundColour(elevated_ ? theme.elevated : theme.surface);
  Refresh();
}

void ModernPanel::OnPaint(wxPaintEvent&) {
  wxAutoBufferedPaintDC dc(this);
  dc.SetBackground(wxBrush(GetParent() != nullptr ? GetParent()->GetBackgroundColour() : theme_.canvas));
  dc.Clear();
  const auto rectangle = GetClientRect();
  dc.SetPen(wxPen(theme_.border));
  dc.SetBrush(wxBrush(elevated_ ? theme_.elevated : theme_.surface));
  dc.DrawRoundedRectangle(rectangle.x, rectangle.y, std::max(0, rectangle.width - 1),
                          std::max(0, rectangle.height - 1), theme_.radius);
}

StatusPill::StatusPill(wxWindow* parent, const wxString& text, StatusTone tone, const PresentationTheme& theme)
    : wxControl(parent, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxBORDER_NONE | wxWANTS_CHARS),
      text_(text), tone_(tone), theme_(theme) {
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  SetName(text);
  SetToolTip(text);
  SetMinSize(wxSize(GetTextExtent(text).GetWidth() + FromDIP(24), FromDIP(26)));
  Bind(wxEVT_PAINT, &StatusPill::OnPaint, this);
  Bind(wxEVT_SET_FOCUS, &StatusPill::OnFocus, this);
  Bind(wxEVT_KILL_FOCUS, &StatusPill::OnFocus, this);
}

void StatusPill::SetPresentationTheme(const PresentationTheme& theme) { theme_ = theme; Refresh(); }

wxColour StatusPill::ToneColour() const { return Tone(theme_, tone_); }

void StatusPill::OnPaint(wxPaintEvent&) {
  wxAutoBufferedPaintDC dc(this);
  dc.SetBackground(wxBrush(GetParent()->GetBackgroundColour()));
  dc.Clear();
  const auto tone = ToneColour();
  const auto fill = Blend(tone, theme_.surface, theme_.dark ? 0.78 : 0.88);
  auto rectangle = GetClientRect();
  rectangle.Deflate(1);
  dc.SetPen(wxPen(HasFocus() ? theme_.focus : Blend(tone, theme_.border, 0.55), HasFocus() ? 2 : 1));
  dc.SetBrush(wxBrush(fill));
  dc.DrawRoundedRectangle(rectangle, FromDIP(12));
  dc.SetFont(theme_.bodyFont.Bold());
  dc.SetTextForeground(Readable(tone, fill));
  const auto extent = dc.GetTextExtent(text_);
  dc.DrawText(text_, (GetClientSize().x - extent.x) / 2, (GetClientSize().y - extent.y) / 2);
}

void StatusPill::OnFocus(wxFocusEvent& event) { Refresh(); event.Skip(); }

ProgressTrack::ProgressTrack(wxWindow* parent, int value, const wxString& accessibleLabel,
                             const PresentationTheme& theme)
    : wxControl(parent, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxBORDER_NONE | wxWANTS_CHARS),
      value_(std::clamp(value, 0, 100)), theme_(theme) {
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  SetName(accessibleLabel);
  SetToolTip(accessibleLabel);
  SetMinSize(wxSize(FromDIP(140), FromDIP(14)));
  Bind(wxEVT_PAINT, &ProgressTrack::OnPaint, this);
  Bind(wxEVT_SET_FOCUS, &ProgressTrack::OnFocus, this);
  Bind(wxEVT_KILL_FOCUS, &ProgressTrack::OnFocus, this);
}

void ProgressTrack::SetPresentationTheme(const PresentationTheme& theme) { theme_ = theme; Refresh(); }

void ProgressTrack::OnPaint(wxPaintEvent&) {
  wxAutoBufferedPaintDC dc(this);
  dc.SetBackground(wxBrush(GetParent()->GetBackgroundColour()));
  dc.Clear();
  auto rectangle = GetClientRect();
  rectangle.Deflate(HasFocus() ? 2 : 1);
  if (HasFocus()) {
    dc.SetPen(wxPen(theme_.focus, 2));
    dc.SetBrush(*wxTRANSPARENT_BRUSH);
    dc.DrawRoundedRectangle(rectangle, rectangle.height / 2.0);
    rectangle.Deflate(2);
  }
  dc.SetPen(*wxTRANSPARENT_PEN);
  dc.SetBrush(wxBrush(theme_.border));
  dc.DrawRoundedRectangle(rectangle, rectangle.height / 2.0);
  auto fill = rectangle;
  fill.width = static_cast<int>(std::lround(rectangle.width * value_ / 100.0));
  if (fill.width > 0) {
    dc.SetBrush(wxBrush(value_ >= 90 ? theme_.error : value_ >= 70 ? theme_.warning : theme_.accent));
    dc.DrawRoundedRectangle(fill, rectangle.height / 2.0);
  }
}

void ProgressTrack::OnFocus(wxFocusEvent& event) { Refresh(); event.Skip(); }

SemanticNotice::SemanticNotice(wxWindow* parent, const wxString& text, StatusTone tone,
                               const PresentationTheme& theme)
    : ModernPanel(parent, theme, true), tone_(tone), theme_(theme) {
  auto* layout = new wxBoxSizer(wxHORIZONTAL);
  label_ = new wxStaticText(this, wxID_ANY, text);
  label_->SetName(text);
  label_->SetForegroundColour(Readable(Tone(theme, tone), theme.elevated));
  label_->Wrap(FromDIP(320));
  layout->Add(label_, 1, wxALL | wxALIGN_CENTER_VERTICAL, theme.spaceMd);
  SetSizer(layout);
}

void SemanticNotice::SetText(const wxString& text) { label_->SetLabel(text); label_->SetName(text); Layout(); }

void SemanticNotice::SetTone(StatusTone tone) {
  tone_ = tone;
  label_->SetForegroundColour(Readable(Tone(theme_, tone_), theme_.elevated));
  Refresh();
}

void SemanticNotice::SetPresentationTheme(const PresentationTheme& theme) {
  theme_ = theme;
  ModernPanel::SetPresentationTheme(theme);
  label_->SetForegroundColour(Readable(Tone(theme, tone_), theme.elevated));
}

}  // namespace ai_usage::ui
