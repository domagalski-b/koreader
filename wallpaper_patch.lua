-- 2-simpleui-homescreen-wallpaper-v7-fullscreen.lua
-- Standalone homescreen wallpaper patch for SimpleUI.
-- Places ONE fullscreen wallpaper behind the already wrapped homescreen
-- (content + bottom bar) and clears the white fills that were blocking it.

local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local OverlapGroup = require("ui/widget/overlapgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local lfs = require("libs/libkoreader-lfs")

local installed = false
local tries = 0
local max_tries = 20

local function log(msg)
    print("[SUI wallpaper v7] " .. tostring(msg))
end

local function get_bg_path()
    local base = "/mnt/onboard/.adds/koreader/images/backgrounds/"
    local is_night = false
    if rawget(_G, "G_reader_settings") then
        pcall(function()
            is_night = G_reader_settings:isTrue("night_mode")
        end)
    end

    local candidate = is_night and (base .. "homescreen_bg_night.png")
                              or  (base .. "homescreen_bg.png")
    if lfs.attributes(candidate, "mode") == "file" then
        return candidate
    end

    if is_night then
        local fallback = base .. "homescreen_bg.png"
        if lfs.attributes(fallback, "mode") == "file" then
            return fallback
        end
    end

    return nil
end

local function render_bg_widget(bg_path, sw, sh)
    local ok_render, RenderImage = pcall(require, "ui/renderimage")
    if not ok_render or not RenderImage then
        log("ui/renderimage unavailable")
        return nil
    end

    local ok_bb, bg_bb = pcall(function()
        return RenderImage:renderImageFile(bg_path, false, nil, nil)
    end)
    if not ok_bb or not bg_bb then
        log("failed to render image: " .. tostring(bg_path))
        return nil
    end

    return ImageWidget:new{
        image = bg_bb,
        width = sw,
        height = sh,
        scale_factor = 1,
    }
end

local function clear_homescreen_body_whites(inst)
    local overlap = inst and inst._navbar_container and inst._navbar_container[1]
    if not overlap then return end

    local outer = overlap[1]
    local content_widget = outer and outer[1] or nil

    if outer then outer.background = nil end
    if content_widget then content_widget.background = nil end
end

local function clear_navbar_whites(inst)
    local container = inst and inst._navbar_container
    if not container then return end

    -- In homescreen/navbar layout from sui_core.wrapWithNavbar:
    -- [1] content overlap, [2] separator, [3] bar, [4] bottom pad, [5] topbar(optional)
    local bar = inst._navbar_bar or container[3]
    local bot_pad = container[4]

    if bar then
        bar.background = nil
        bar.bgcolor = nil
    end
    if bot_pad then
        bot_pad.background = nil
        bot_pad.bgcolor = nil
    end

    -- The outer wrapper returned by wrapWithNavbar is self[1] before we wrap it.
    local wrapped = inst[1]
    if wrapped then
        wrapped.background = nil
        wrapped.bgcolor = nil
    end
end

local function apply_fullscreen_wallpaper(inst)
    if not inst or inst._sui_wallpaper_v7_applied then
        return
    end

    local bg_path = get_bg_path()
    if not bg_path then
        log("no wallpaper file found")
        return
    end

    local original = inst[1]
    if not original then
        log("no root widget on homescreen instance")
        return
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()

    clear_homescreen_body_whites(inst)
    clear_navbar_whites(inst)

    local bg_widget = render_bg_widget(bg_path, sw, sh)
    if not bg_widget then return end

    local wrapped = OverlapGroup:new{
        allow_mirroring = false,
        dimen = Geom:new{ w = sw, h = sh },
        bg_widget,
        FrameContainer:new{
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = nil,
            dimen = Geom:new{ w = sw, h = sh },
            original,
        },
    }

    inst[1] = wrapped
    inst._sui_wallpaper_v7_applied = true
    log("fullscreen wallpaper applied")
end

local function patch_instance(inst)
    if type(inst) ~= "table" or inst._wallpaper_patch_v7_instance then
        return
    end
    if type(inst.onShow) ~= "function" then
        log("instance has no onShow")
        return
    end

    local old_onShow = inst.onShow
    inst.onShow = function(self, ...)
        local ret = old_onShow(self, ...)
        pcall(function()
            apply_fullscreen_wallpaper(self)
            UIManager:setDirty(self, "ui")
        end)
        return ret
    end

    inst._wallpaper_patch_v7_instance = true
    log("instance patched")
end

local function install_patch()
    if installed then
        return true
    end

    local ok_hs, Homescreen = pcall(require, "sui_homescreen")
    if not ok_hs or type(Homescreen) ~= "table" or type(Homescreen.show) ~= "function" then
        return false
    end

    if Homescreen._wallpaper_patch_v7_applied then
        installed = true
        return true
    end

    local original_show = Homescreen.show

    local function get_upvalue_by_name(fn, wanted)
        local i = 1
        while true do
            local name, value = debug.getupvalue(fn, i)
            if not name then return nil end
            if name == wanted then return value end
            i = i + 1
        end
    end

    local HomescreenWidget = get_upvalue_by_name(original_show, "HomescreenWidget")
    if type(HomescreenWidget) ~= "table" or type(HomescreenWidget.new) ~= "function" then
        log("could not extract HomescreenWidget upvalue")
        return false
    end

    Homescreen.show = function(on_qa_tap, on_goal_tap)
        if Homescreen._instance then
            UIManager:close(Homescreen._instance)
            Homescreen._instance = nil
        end

        local w = HomescreenWidget:new{
            _on_qa_tap          = on_qa_tap,
            _on_goal_tap        = on_goal_tap,
            _cached_books_state = Homescreen._cached_books_state,
            _current_page       = Homescreen._current_page or 1,
        }

        patch_instance(w)

        Homescreen._instance = w
        UIManager:show(w)
    end

    Homescreen._wallpaper_patch_v7_applied = true
    installed = true
    log("installed")

    if Homescreen._instance then
        patch_instance(Homescreen._instance)
    end

    return true
end

local function try_install_later()
    tries = tries + 1
    if install_patch() then
        return
    end
    if tries >= max_tries then
        log("giving up after " .. tostring(tries) .. " tries")
        return
    end
    UIManager:scheduleIn(1, try_install_later)
end

pcall(function()
    UIManager:scheduleIn(1, try_install_later)
end)
