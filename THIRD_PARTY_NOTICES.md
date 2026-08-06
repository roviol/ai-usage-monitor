# Third-party notices

AI Usage Monitor embeds the following pinned components in release builds:

- wxWidgets 3.3.2 — wxWindows Library Licence 3.1 (GPL-compatible with the
  binary-distribution exception), copyright wxWidgets contributors.
  Source: <https://github.com/wxWidgets/wxWidgets/releases/tag/v3.3.2>
- JSON for Modern C++ 3.12.0 — MIT License, copyright Niels Lohmann.
  Source: <https://github.com/nlohmann/json/releases/tag/v3.12.0>

On Linux the program dynamically uses system libcurl and GTK libraries under
their respective distribution licences. Optional `secret-tool` is invoked as a
separate process and is not redistributed. Release source archives retain the
complete upstream licence texts in each dependency's source tree.
