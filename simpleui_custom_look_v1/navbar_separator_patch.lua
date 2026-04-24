-- 2-simpleui-navbar-separator-hide.lua
-- Hide the thin separator strip by disabling the actual LineWidget draw.
-- Use with:
--   2-simpleui-homescreen-wallpaper-v7-fullscreen.lua
--   2-simpleui-navbar-indicator-off-v2.lua
-- Disable the other separator/navbar experiments.

local UIManager = require("ui/uimanager")

local installed = false
local tries = 0
local max_tries = 20

local function log(msg)
    print("[SUI navbar separator hide] " .. tostring(msg))
end

local function install_patch()
    if installed then return true end

    local ok, Core = pcall(require, "sui_core")
    if not ok or type(Core) ~= "table" then
        return false
    end
    if type(Core.wrapWithNavbar) ~= "function" then
        return false
    end
    if Core._navbar_separator_hide_applied then
        installed = true
        return true
    end

    local old_wrap = Core.wrapWithNavbar

    Core.wrapWithNavbar = function(...)
        local navbar_container, wrapper, bar, topbar, bar_idx, topbar_on, topbar_idx = old_wrap(...)

        pcall(function()
            -- In your uploaded sui_core.lua, navbar_container children are:
            -- [1] content
            -- [2] sep_line   <- LineWidget we want to disable
            -- [3] bar
            -- [4] bot_pad
            if type(navbar_container) == "table" then
                local sep = navbar_container[2]
                if type(sep) == "table" then
                    sep.style = "none"
                    if sep.dimen then
                        sep.dimen.h = 0
                    end
                    sep.background = nil
                    sep.bgcolor = nil
                end
            end
        end)

        return navbar_container, wrapper, bar, topbar, bar_idx, topbar_on, topbar_idx
    end

    Core._navbar_separator_hide_applied = true
    installed = true
    log("installed")
    return true
end

local function try_install_later()
    tries = tries + 1
    if install_patch() then return end
    if tries >= max_tries then
        log("giving up after " .. tostring(tries) .. " tries")
        return
    end
    UIManager:scheduleIn(1, try_install_later)
end

pcall(function()
    UIManager:scheduleIn(1, try_install_later)
end)
