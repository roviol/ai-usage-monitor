#pragma once

#include "ai_usage/presentation.h"

#include <wx/button.h>
#include <wx/control.h>
#include <wx/panel.h>
#include <wx/stattext.h>

namespace ai_usage::ui {

enum class StatusTone { Neutral, Accent, Success, Warning, Error };
enum class ButtonTone { Primary, Secondary, Destructive };

struct PresentationTheme {
  bool dark{false};
  wxColour canvas;
  wxColour surface;
  wxColour elevated;
  wxColour text;
  wxColour mutedText;
  wxColour border;
  wxColour accent;
  wxColour focus;
  wxColour success;
  wxColour warning;
  wxColour error;
  wxColour onAccent;
  wxFont titleFont;
  wxFont sectionFont;
  wxFont metricFont;
  wxFont bodyFont;
  int spaceXs{4};
  int spaceSm{8};
  int spaceMd{12};
  int spaceLg{18};
  int radius{10};
};

PresentationTheme ResolveTheme(wxWindow* window);
void ApplyTheme(wxWindow* root, const PresentationTheme& theme);
void StyleButton(wxButton* button, const PresentationTheme& theme, ButtonTone tone);

class ModernPanel : public wxPanel {
 public:
  ModernPanel(wxWindow* parent, const PresentationTheme& theme, bool elevated = false);
  void SetPresentationTheme(const PresentationTheme& theme);

 private:
  void OnPaint(wxPaintEvent& event);
  PresentationTheme theme_;
  bool elevated_{false};
};

class StatusPill final : public wxControl {
 public:
  StatusPill(wxWindow* parent, const wxString& text, StatusTone tone, const PresentationTheme& theme);
  void SetPresentationTheme(const PresentationTheme& theme);

 private:
  void OnPaint(wxPaintEvent& event);
  void OnFocus(wxFocusEvent& event);
  wxColour ToneColour() const;
  wxString text_;
  StatusTone tone_{StatusTone::Neutral};
  PresentationTheme theme_;
};

class ProgressTrack final : public wxControl {
 public:
  ProgressTrack(wxWindow* parent, int value, const wxString& accessibleLabel, const PresentationTheme& theme);
  void SetPresentationTheme(const PresentationTheme& theme);

 private:
  void OnPaint(wxPaintEvent& event);
  void OnFocus(wxFocusEvent& event);
  int value_{0};
  PresentationTheme theme_;
};

class SemanticNotice final : public ModernPanel {
 public:
  SemanticNotice(wxWindow* parent, const wxString& text, StatusTone tone, const PresentationTheme& theme);
  void SetText(const wxString& text);
  void SetTone(StatusTone tone);
  void SetPresentationTheme(const PresentationTheme& theme);

 private:
  StatusTone tone_{StatusTone::Neutral};
  PresentationTheme theme_;
  wxStaticText* label_{nullptr};
};

}  // namespace ai_usage::ui
