SimpleUI Custom Look (KOReader Plugin)

A lightweight KOReader plugin that unifies multiple SimpleUI visual tweaks into a single, stable solution.

Originally developed as a set of standalone patches, this project has been refactored into a plugin to improve reliability, maintainability, and compatibility with future updates.

⸻

✨ Features

This plugin applies the following UI improvements to KOReader SimpleUI:

🖼 Homescreen

* Fullscreen wallpaper support across all sections
* Seamless background continuation (no breaks between modules)

🔽 Navigation Bar

* Removes bottom navigation indicator
* Hides separator line above navbar

📊 Reading Stats

* Fully transparent reading stats module
* Preserves layout and typography

💬 Quote Module

* Removes white background behind:
    * quote text
    * author text
* Uses custom AlphaTextBoxWidget for proper transparency rendering

⸻

🚀 Why a Plugin?

The original approach used multiple .lua patches placed in the patches/ directory.

This worked, but had limitations:

* patches could break silently after updates
* difficult to manage multiple files
* some features (like quote transparency) require plugin-level context

The plugin approach provides:

* controlled loading via KOReader plugin system
* better error isolation (one module failing won’t break everything)
* support for custom widgets (required for quote transparency)
* cleaner structure and easier future updates

⸻

📦 Installation

1. Download the latest release
2. Extract the folder:
    simpleui_custom_look_v2.koplugin
3. Copy it to your KOReader plugins/ directory
4. Remove old patches from:
    koreader/patches/
5. Restart KOReader

⸻

⚠️ Important Notes

* Do NOT use this plugin together with the old patch files — they may conflict
* Designed specifically for KOReader SimpleUI
* If SimpleUI internals change in future updates, adjustments may be required

⸻

🧩 Structure

simpleui_custom_look.koplugin/
├── main.lua
├── quote_patch.lua
├── reading_stats_patch.lua
├── navbar_indicator_patch.lua
├── navbar_separator_patch.lua
├── wallpaper_patch.lua
└── widgets/
└── alphatextboxwidget.lua

⸻

🛠 Development Notes

* Quote transparency required replacing TextBoxWidget with a custom AlphaTextBoxWidget
* This could not be reliably achieved with standard patches
* Final solution leverages plugin context and controlled widget rendering

⸻

🔄 Migration from Patches

If you were previously using:

* 2-simpleui-homescreen-wallpaper-*.lua
* 2-simpleui-navbar-*.lua
* 2-simpleui-reading-stats-*.lua
* quote-related patches

Replace all of them with this plugin.

⸻

📌 Status

Stable — actively used in daily setup

Future updates may include:

* compatibility with new KOReader releases
* optional UI refinements

⸻

🙌 Credits

* KOReader community for inspiration and patch ideas
* Appearance plugin for initial direction on quote transparency
* Iterative testing and real-world usage refinement
