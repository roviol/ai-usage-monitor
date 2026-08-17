#include "app_icon.h"

#include "application_icon_64_png.h"

#include <wx/bitmap.h>
#include <wx/icon.h>
#include <wx/iconbndl.h>
#include <wx/image.h>
#include <wx/toplevel.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include "application_icon_resource.h"
#endif

namespace ai_usage::ui {
namespace {

wxIcon EmbeddedApplicationIcon() {
  if (!wxImage::FindHandler(wxBITMAP_TYPE_PNG)) wxImage::AddHandler(new wxPNGHandler());
  const auto bitmap = wxBitmap::NewFromPNGData(application_icon_64_png,
                                                sizeof(application_icon_64_png));
  wxIcon icon;
  if (bitmap.IsOk()) icon.CopyFromBitmap(bitmap);
  return icon;
}

wxIconBundle LoadApplicationIcons() {
  wxIconBundle icons;
#ifdef _WIN32
  constexpr int sizes[] = {16, 24, 32, 48, 64, 128, 256};
  for (const int size : sizes) {
    const auto handle = reinterpret_cast<HICON>(
        ::LoadImageW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APPLICATION_ICON),
                     IMAGE_ICON, size, size, LR_DEFAULTCOLOR));
    if (handle == nullptr) continue;

    wxIcon icon;
    if (icon.CreateFromHICON(reinterpret_cast<WXHICON>(handle))) {
      icons.AddIcon(icon);
    } else {
      ::DestroyIcon(handle);
    }
  }
#endif
  if (icons.IsEmpty()) {
    const auto embedded = EmbeddedApplicationIcon();
    if (embedded.IsOk()) icons.AddIcon(embedded);
  }
  return icons;
}

}  // namespace

void ApplyApplicationIcon(wxTopLevelWindow& window) {
  const auto icons = LoadApplicationIcons();
  if (!icons.IsEmpty()) window.SetIcons(icons);
}

}  // namespace ai_usage::ui
