cmake_minimum_required(VERSION 3.25)

project(ai_usage_monitor VERSION 0.1.1 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(Dependencies)

add_library(ai_usage_core STATIC
  src/config.cpp
  src/domain.cpp
  src/overlay.cpp
  src/presentation.cpp
  src/providers.cpp
  src/scheduler.cpp
  src/tooltip.cpp
)
target_include_directories(ai_usage_core PUBLIC include)
target_link_libraries(ai_usage_core PUBLIC nlohmann_json::nlohmann_json)

add_library(ai_usage_platform STATIC)
target_include_directories(ai_usage_platform PUBLIC include)
target_link_libraries(ai_usage_platform PUBLIC ai_usage_core)

if(WIN32)
  target_sources(ai_usage_platform PRIVATE
    src/platform/windows_platform.cpp
  )
  target_compile_definitions(ai_usage_platform PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE _WIN32_WINNT=0x0A00)
  target_link_libraries(ai_usage_platform PRIVATE winhttp crypt32 shell32 advapi32 user32)
else()
  find_package(CURL REQUIRED)
  target_sources(ai_usage_platform PRIVATE
    src/platform/linux_platform.cpp
  )
  target_link_libraries(ai_usage_platform PRIVATE CURL::libcurl pthread)
endif()

add_executable(ai-usage-monitor WIN32
  src/ui/app_icon.cpp
  src/ui/app.cpp
  src/ui/dashboard.cpp
  src/ui/overlay_frame.cpp
  src/ui/presentation.cpp
  src/ui/settings_dialog.cpp
  src/ui/tray_icon.cpp
)
if(WIN32)
  target_sources(ai-usage-monitor PRIVATE assets/application-icon.rc)
endif()
target_include_directories(ai-usage-monitor PRIVATE include src/ui assets)
target_link_libraries(ai-usage-monitor PRIVATE ai_usage_core ai_usage_platform wx::core wx::base)
target_compile_definitions(ai-usage-monitor PRIVATE AI_USAGE_VERSION="${PROJECT_VERSION}")
if(MSVC)
  # wxWidgets intentionally wraps several legacy CRT calls. Keep our own code
  # warning-clean while avoiding /WX failures originating in third-party headers.
  target_compile_definitions(ai-usage-monitor PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

function(ai_usage_strict target)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /WX /permissive- /utf-8 /EHsc)
  else()
    # Aggregate defaults are intentional throughout the domain request/value types.
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror -Wno-missing-field-initializers)
  endif()
endfunction()

ai_usage_strict(ai_usage_core)
ai_usage_strict(ai_usage_platform)
ai_usage_strict(ai-usage-monitor)

if(BUILD_TESTING)
  function(ai_usage_add_test_suite target suite)
    add_executable(${target} tests/test_main.cpp)
    target_include_directories(${target} PRIVATE include tests)
    target_compile_definitions(${target} PRIVATE
      AI_USAGE_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
      AI_USAGE_TEST_SUITE="${suite}"
    )
    target_link_libraries(${target} PRIVATE ai_usage_core ai_usage_platform)
    ai_usage_strict(${target})
    add_test(NAME ${target} COMMAND ${target})
  endfunction()

  ai_usage_add_test_suite(ai-usage-unit-tests unit)
  ai_usage_add_test_suite(ai-usage-fixture-tests fixture)
endif()

install(TARGETS ai-usage-monitor RUNTIME DESTINATION .)
install(FILES README.md LICENSE THIRD_PARTY_NOTICES.md DESTINATION .)

set(CPACK_PACKAGE_NAME "AIUsageMonitor")
set(CPACK_PACKAGE_VENDOR "Roviol")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_FILE_NAME "AIUsageMonitor-${PROJECT_VERSION}-${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
set(CPACK_GENERATOR "ZIP")
include(CPack)
