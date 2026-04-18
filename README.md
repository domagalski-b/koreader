## SimpleUI Wallpaper / Navbar Patches

These patches were made for KOReader SimpleUI to allow a fullscreen homescreen wallpaper with a clean bottom bar.

### Included patches

- `2-simpleui-homescreen-wallpaper-v1-fullscreen.lua`  
  Main wallpaper patch.

- `2-simpleui-homescreen-wallpaper-v7-fullscreen.lua`  
  Extends the homescreen wallpaper across the full screen, including the bottom navigation area.

- `2-simpleui-navbar-indicator-off-v2.lua`  
  Removes the moving black navbar indicator strip.

- `2-simpleui-navbar-separator-hide.lua`  
  Hides the thin separator line above the bottom navbar.

- `2-simpleui-reading-stats-transparent-v6`  
  Makes the reading stats cards transparent.


### Result

Together, these patches allow:
- one continuous wallpaper across the full homescreen
- no black selector strip in the bottom navbar
- no separator line above the navbar
- transparent stats module

### Notes

These patches were built against the current SimpleUI structure and may need adjustment after future SimpleUI updates.
Use them together, and disable older experimental navbar patches.
