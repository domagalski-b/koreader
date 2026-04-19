-- 2-simpleui-reading-stats-transparent-v6.lua
-- Targeted Reading Stats transparency patch.
-- Removes white card fills and borders by patching the actual local card builders.

local UIManager = require("ui/uimanager")

local installed = false
local tries = 0
local max_tries = 20

local function scrub(widget, depth)
    depth = depth or 0
    if depth > 10 or type(widget) ~= "table" then
        return
    end

    -- FrameContainer behavior from KOReader core:
    -- background=nil disables fill, bordersize=0 removes border.
    widget.background = nil
    widget.bgcolor = nil
    if widget.bordersize ~= nil then widget.bordersize = 0 end
    if widget.border_size ~= nil then widget.border_size = 0 end
    if widget.color ~= nil then widget.color = nil end
    if widget.radius ~= nil then widget.radius = 0 end
    if widget.corner_radius ~= nil then widget.corner_radius = 0 end

    for _, v in pairs(widget) do
        if type(v) == "table" then
            scrub(v, depth + 1)
        end
    end
end

local function wrap_local_builder(fn)
    if type(fn) ~= "function" then return fn end
    return function(...)
        local w = fn(...)
        pcall(function() scrub(w) end)
        return w
    end
end

local function replace_upvalue_by_name(fn, wanted, repl)
    local i = 1
    while true do
        local name, value = debug.getupvalue(fn, i)
        if not name then return false end
        if name == wanted then
            debug.setupvalue(fn, i, repl(value))
            return true
        end
        i = i + 1
    end
end

local function install_patch()
    if installed then return true end

    local ok, Mod = pcall(require, "desktop_modules/module_reading_stats")
    if not ok or type(Mod) ~= "table" or type(Mod.build) ~= "function" then
        return false
    end
    if Mod._transparent_patch_v6_applied then
        installed = true
        return true
    end

    -- Patch the actual local helper functions used by M.build.
    replace_upvalue_by_name(Mod.build, "buildStatCardWidget", wrap_local_builder)
    replace_upvalue_by_name(Mod.build, "buildStatFlatWidget", wrap_local_builder)
    replace_upvalue_by_name(Mod.build, "buildStatListCell", wrap_local_builder)

    -- Also wrap M.build itself as a safety net.
    local old_build = Mod.build
    Mod.build = function(...)
        local w = old_build(...)
        pcall(function() scrub(w) end)
        return w
    end

    Mod._transparent_patch_v6_applied = true
    installed = true
    return true
end

local function try_install_later()
    tries = tries + 1
    if install_patch() then return end
    if tries >= max_tries then return end
    UIManager:scheduleIn(1, try_install_later)
end

pcall(function()
    UIManager:scheduleIn(1, try_install_later)
end)
