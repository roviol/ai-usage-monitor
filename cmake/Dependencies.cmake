include(FetchContent)

option(AI_USAGE_OFFLINE "Require dependencies to exist in FETCHCONTENT_BASE_DIR" OFF)
set(FETCHCONTENT_QUIET OFF)
if(AI_USAGE_OFFLINE)
  set(FETCHCONTENT_FULLY_DISCONNECTED ON)
endif()

set(wxBUILD_SHARED OFF CACHE BOOL "" FORCE)
set(wxBUILD_MONOLITHIC OFF CACHE BOOL "" FORCE)
set(wxBUILD_SAMPLES OFF CACHE BOOL "" FORCE)
set(wxBUILD_TESTS OFF CACHE BOOL "" FORCE)
set(wxBUILD_DEMOS OFF CACHE BOOL "" FORCE)
set(wxBUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
set(wxUSE_WEBVIEW OFF CACHE BOOL "" FORCE)
set(wxUSE_MEDIACTRL OFF CACHE BOOL "" FORCE)
set(wxUSE_OPENGL OFF CACHE BOOL "" FORCE)
set(wxUSE_RIBBON OFF CACHE BOOL "" FORCE)
set(wxUSE_PROPGRID OFF CACHE BOOL "" FORCE)
set(wxUSE_RICHTEXT OFF CACHE BOOL "" FORCE)
set(wxUSE_STC OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
  wxWidgets
  URL https://github.com/wxWidgets/wxWidgets/releases/download/v3.3.2/wxWidgets-3.3.2.tar.bz2
  URL_HASH SHA256=50a28cb668de47b0e006cd6ebed8cf4f76c1cac6116fb3c978c44478219103f2
  TLS_VERIFY TRUE
)

FetchContent_Declare(
  nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
  URL_HASH SHA256=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa
  TLS_VERIFY TRUE
)

FetchContent_MakeAvailable(wxWidgets nlohmann_json)
