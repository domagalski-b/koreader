--[[
Merged patch: Visual Overhaul folders/series + Real Books single-book rendering.
Use this file alone. Do not enable the original Visual Overhaul or Real Books patches at the same time.

Merge policy:
- Visual Overhaul: folder cards, underline/cover behavior, virtual series grouping, series badge creation.
- Real Books: single-book ratio/scale, book thickness/spine/page lines, progress badge.
- Book title/meta strip from Visual Overhaul disabled so book covers can use more space.
]]

--[[ Visual overhaul: stretched rounded covers, folder covers, series badges,
     progress bars, percent badges, pages badges, dogear icons, virtual series folders.
     Merges: 2--covers.lua, 2-cover-overlays.lua, 2-automatic-book-series.lua ]]
--

local ok, err = pcall(function()

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local IconWidget = require("ui/widget/iconwidget")
local userpatch = require("userpatch")
local util = require("util")

local _ = require("gettext")
local Screen = Device.screen
local logger = require("logger")

--========================== [[Debug]] ==================================================
local DEBUG_ICONS = false  -- set false to silence custom-icon diagnostics
--=======================================================================================

--========================== [[Cover preferences]] ======================================
local aspect_ratio = 2 / 3          -- adjust aspect ratio of folder cover
local stretch_limit = 18            -- adjust the stretching limit
local fill = false                  -- set true to fill the entire cell ignoring aspect ratio
local file_count_size = 12          -- font size of the file count badge
local folder_font_size = 16         -- font size of the folder name
local folder_border = 0.5           -- thickness of folder border
local folder_name = true            -- set to false to remove folder title from the center
--======================================================================================

--========================== [[Pages badge preferences]] ================================
local pages_cfg = {
    font_size = 0.40,                             -- smaller pages badge text
    text_color = Blitbuffer.COLOR_WHITE,          -- Choose your desired color
    border_thickness = 0,                         -- Adjust from 0 to 5
    border_corner_radius = 8,                    -- Adjust from 0 to 20
    border_color = Blitbuffer.COLOR_DARK_GRAY,    -- Choose your desired color
    background_color = Blitbuffer.COLOR_GRAY_3,   -- Choose your desired color
    move_from_border = 1,                         -- used for lower placement logic
}

--========================== [[Percent badge preferences]] ==============================
local percent_cfg = {
    text_size = 0.22,   -- smaller percent badge text
    move_on_x = -12,     -- keep closer to corner
    move_on_y = -6,     -- slightly higher
    badge_w = 42,       -- smaller badge width
    badge_h = 24,       -- smaller badge height
    bump_up = 1,        -- Adjust text position
}

--========================== [[Series badge preferences]] ===============================
local series_cfg = {
    font_size = 10,                                          -- Adjust from 0 to 1
    border_thickness = 1,                                    -- Adjust from 0 to 5
    border_corner_radius = 12,                                -- Adjust from 0 to 20
    text_color = Blitbuffer.colorFromString("#000000"),      -- Choose your desired color
    border_color = Blitbuffer.colorFromString("#000000"),    -- Choose your desired color
    background_color = Blitbuffer.COLOR_GRAY_E,              -- Choose your desired color
}

--========================== [[Title strip preferences]] ==================================
local title_cfg = {
    font_size = 12,
    meta_font_size = 10,
    max_lines = 2,
    padding = 2,
    text_color = Blitbuffer.COLOR_BLACK,
    meta_color = Blitbuffer.COLOR_DARK_GRAY,
    card_gap = 2,
}

--========================== [[Focus border preferences]] =================================
local focus_cfg = {
    border_width = 12,
    color = Blitbuffer.COLOR_BLACK,
}

--========================== [[Progress bar preferences]] ===============================
local bar_cfg = {
    H = Screen:scaleBySize(6),                              -- bar height
    RADIUS = Screen:scaleBySize(2),                         -- rounded ends
    INSET_X = Screen:scaleBySize(4),                        -- from inner cover edges
    INSET_Y = Screen:scaleBySize(10),                       -- from bottom inner edge
    GAP_TO_ICON = Screen:scaleBySize(8),                    -- gap before corner icon
    TRACK_COLOR = Blitbuffer.colorFromString("#F4F0EC"),     -- bar color
    FILL_COLOR = Blitbuffer.colorFromString("#555555"),      -- fill color
    ABANDONED_COLOR = Blitbuffer.colorFromString("#C0C0C0"), -- fill when abandoned/paused
    BORDER_W = Screen:scaleBySize(0.4),                     -- border width around track (0 to disable)
    BORDER_COLOR = Blitbuffer.COLOR_BLACK,                   -- border color
    MIN_PERCENT = 0.01,                                     -- hide bar below this (2%)
    NEAR_COMPLETE_PERCENT = 0.98,                           -- treat as complete above this (97%)
}
--=======================================================================================

local FolderCover = {
    name = ".cover",
    exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
}

local Folder = {
    face = {
        border_size = 1,
        alpha = 0.75,
        nb_items_font_size = file_count_size,
        nb_items_margin = Screen:scaleBySize(5),
        dir_max_font_size = folder_font_size,
    },
}

--========================== [[New badge preferences]] ================================
local new_badge_cfg = {
    max_age_days = 30,
    badge_w = 55,
    badge_h = 30,
    inset_x = -10,
    inset_y = 2,
}

-- ============================================================================
-- Custom icon directories
-- ============================================================================
do
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")

    local dbg = DEBUG_ICONS and logger.info or function() end

    local icons_dirs = userpatch.getUpValue(IconWidget.init, "ICONS_DIRS")
    local icons_path = userpatch.getUpValue(IconWidget.init, "ICONS_PATH")

    dbg("[custom-icons] getDataDir():", DataStorage:getDataDir())
    dbg("[custom-icons] getFullDataDir():", tostring(DataStorage:getFullDataDir()))
    dbg("[custom-icons] lfs.currentdir():", lfs.currentdir())
    dbg("[custom-icons] icons_dirs upvalue:", icons_dirs and ("table, #" .. #icons_dirs) or "nil")
    dbg("[custom-icons] icons_path upvalue:", icons_path and "table" or "nil")

    if icons_dirs then
        dbg("[custom-icons] Original ICONS_DIRS:")
        for i, d in ipairs(icons_dirs) do
            dbg("[custom-icons]   [" .. i .. "]", d)
        end

        local data_dir = DataStorage:getFullDataDir()
        if not data_dir then
            logger.warn("[custom-icons] getFullDataDir() returned nil, falling back to getDataDir()")
            data_dir = DataStorage:getDataDir()
        end
        local variant_subdir = Device:hasColorScreen() and "icons-colours" or "icons-bw"
        local variant_dir = data_dir .. "/icons/" .. variant_subdir
        local all_dir     = data_dir .. "/icons/all"

        dbg("[custom-icons] hasColorScreen:", tostring(Device:hasColorScreen()))
        dbg("[custom-icons] variant_dir:", variant_dir)
        dbg("[custom-icons] all_dir:", all_dir)

        local all_mode = lfs.attributes(all_dir, "mode")
        dbg("[custom-icons] lfs.attributes(all_dir):", tostring(all_mode))
        if all_mode == "directory" then
            table.insert(icons_dirs, 1, all_dir)
        end

        local variant_mode = lfs.attributes(variant_dir, "mode")
        dbg("[custom-icons] lfs.attributes(variant_dir):", tostring(variant_mode))
        if variant_mode == "directory" then
            table.insert(icons_dirs, 1, variant_dir)
        end

        -- Clear cached icon paths so lookups use the new directories.
        if icons_path then
            local cleared = 0
            for k in pairs(icons_path) do
                icons_path[k] = nil
                cleared = cleared + 1
            end
            dbg("[custom-icons] Cleared", cleared, "cached icon paths")
        end

        dbg("[custom-icons] Final ICONS_DIRS:")
        for i, d in ipairs(icons_dirs) do
            dbg("[custom-icons]   [" .. i .. "]", d)
        end
    else
        logger.warn("[custom-icons] Could not get ICONS_DIRS upvalue from IconWidget.init")
    end
end

local function svg_widget(icon)
    local widget = IconWidget:new{ icon = icon, alpha = true }
    if DEBUG_ICONS then
        logger.info("[custom-icons] svg_widget('" .. icon .. "') -> file:", widget and widget.file or "nil")
    end
    return widget
end

local icons = { tl = "rounded.corner.tl", tr = "rounded.corner.tr", bl = "rounded.corner.bl", br = "rounded.corner.br" }
local corners = {}
for k, name in pairs(icons) do
    corners[k] = svg_widget(name)
    if not corners[k] then
        logger.warn("Failed to load SVG icon: " .. tostring(name))
    end
end

local function findCover(dir_path)
    local path = dir_path .. "/" .. FolderCover.name
    for _, ext in ipairs(FolderCover.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then return fname end
    end
end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local function getMenuItem(menu, ...)
    local function findItem(sub_items, texts)
        local find = {}
        for _, text in ipairs(type(texts) == "table" and texts or { texts }) do
            find[text] = true
        end
        for _, item in ipairs(sub_items) do
            local text = item.text or (item.text_func and item.text_func())
            if text and find[text] then return item end
        end
    end

    local sub_items, item
    for _, texts in ipairs { ... } do
        sub_items = (item or menu).sub_item_table
        if not sub_items then return end
        item = findItem(sub_items, texts)
        if not item then return end
    end
    return item
end

local function toKey(...)
    local keys = {}
    for _, key in pairs { ... } do
        if type(key) == "table" then
            table.insert(keys, "table")
            for k, v in pairs(key) do
                table.insert(keys, tostring(k))
                table.insert(keys, tostring(v))
            end
        else
            table.insert(keys, tostring(key))
        end
    end
    return table.concat(keys, "")
end

local function paintCorners(bb, x, y, w, h)
    local TL, TR, BL, BR = corners.tl, corners.tr, corners.bl, corners.br
    if not (TL and TR and BL and BR) then return end

    local function _sz(widget)
        if widget.getSize then
            local s = widget:getSize()
            return s.w, s.h
        end
        if widget.getWidth then
            return widget:getWidth(), widget:getHeight()
        end
        return 0, 0
    end

    local tlw, tlh = _sz(TL)
    local trw, trh = _sz(TR)
    local blw, blh = _sz(BL)
    local brw, brh = _sz(BR)

    if TL.paintTo then TL:paintTo(bb, x, y) else bb:blitFrom(TL, x, y) end
    if TR.paintTo then TR:paintTo(bb, x + w - trw, y) else bb:blitFrom(TR, x + w - trw, y) end
    if BL.paintTo then BL:paintTo(bb, x, y + h - blh) else bb:blitFrom(BL, x, y + h - blh) end
    if BR.paintTo then BR:paintTo(bb, x + w - brw, y + h - brh) else bb:blitFrom(BR, x + w - brw, y + h - brh) end
end

local function paintTopCorners(bb, x, y, w, h)
    local TL, TR = corners.tl, corners.tr
    if not (TL and TR) then return end
    local function _sz(widget)
        if widget.getSize then local s = widget:getSize(); return s.w, s.h end
        if widget.getWidth then return widget:getWidth(), widget:getHeight() end
        return 0, 0
    end
    local tlw, tlh = _sz(TL)
    local trw, trh = _sz(TR)
    if TL.paintTo then TL:paintTo(bb, x, y) else bb:blitFrom(TL, x, y) end
    if TR.paintTo then TR:paintTo(bb, x + w - trw, y) else bb:blitFrom(TR, x + w - trw, y) end
end

local function getAspectRatioAdjustedDimensions(width, height, border_size)
    local available_w = width - 2 * border_size
    local available_h = height - 2 * border_size
    local ratio = fill and (available_w / available_h) or aspect_ratio

    local frame_w, frame_h
    if available_w / available_h > ratio then
        frame_h = available_h
        frame_w = available_h * ratio
    else
        frame_w = available_w
        frame_h = available_w / ratio
    end

    return { w = frame_w + 2 * border_size, h = frame_h + 2 * border_size }
end

local orig_FileChooser_getListItem = FileChooser.getListItem
local CACHE_MAX = 2000
local cached_list = {}
local cached_list_count = 0
function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
    if not cached_list[key] then
        if cached_list_count >= CACHE_MAX then
            cached_list = {}
            cached_list_count = 0
        end
        cached_list[key] = orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
        cached_list_count = cached_list_count + 1
    end
    return cached_list[key]
end

-- Icon constants for browser-up-folder compatibility
local Icon = {
    home = "home",
    up = BD.mirroredUILayout() and "back.top.rtl" or "back.top",
}

-- State for persisting virtual folder across refreshes
local current_series_group = nil

if not IconWidget.patched_new_status_icons then
    IconWidget.patched_new_status_icons = true

    local originalIconWidgetNew = IconWidget.new

    function IconWidget:new(o)
        local corner_icons = {
            "dogear.reading",
            "dogear.abandoned",
            "dogear.abandoned.rtl",
            "dogear.complete",
            "dogear.complete.rtl",
            "star.white",
        }

        for _, icon_name in ipairs(corner_icons) do
            if o.icon == icon_name then
                o.alpha = true
                break
            end
        end

        return originalIconWidgetNew(self, o)
    end
end

-- ============================================================================
-- Callback scope
-- ============================================================================

local function patchVisualOverhaul(plugin)
    local AlphaContainer = require("ui/widget/container/alphacontainer")
    local BookInfoManager = require("bookinfomanager")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local TitleBar = require("ui/widget/titlebar")
    local TopContainer = require("ui/widget/container/topcontainer")
    local lfs = require("libs/libkoreader-lfs")
    local VerticalSpan = require("ui/widget/verticalspan")
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem or MosaicMenuItem.patched_visual_overhaul then return end
    MosaicMenuItem.patched_visual_overhaul = true

    -- Compute title strip height (reused in init, update, paintTo)
    local title_face = Font:getFace("cfont", title_cfg.font_size)
    local _sample = TextWidget:new{ text = "Ag", face = title_face }
    local title_line_h = _sample:getSize().h
    _sample:free()
    local title_strip_h = title_line_h * title_cfg.max_lines + Screen:scaleBySize(title_cfg.padding)
    local card_gap_px = Screen:scaleBySize(title_cfg.card_gap)

    -- StretchingImageWidget + debug.setupvalue
    local max_img_w, max_img_h

    if not MosaicMenuItem.patched_aspect_ratio then
        MosaicMenuItem.patched_aspect_ratio = true

        local local_ImageWidget
        local n = 1
        while true do
            local name, value = debug.getupvalue(MosaicMenuItem.update, n)
            if not name then break end
            if name == "ImageWidget" then
                local_ImageWidget = value
                break
            end
            n = n + 1
        end

        if not local_ImageWidget then
            logger.warn("Could not find ImageWidget in MosaicMenuItem.update closure")
        else
            local StretchingImageWidget = local_ImageWidget:extend({})
            StretchingImageWidget.init = function(self)
                if local_ImageWidget.init then local_ImageWidget.init(self) end
                if not max_img_w and not max_img_h then return end

                self.scale_factor = nil
                self.stretch_limit_percentage = stretch_limit

                local ratio = fill and (max_img_w / max_img_h) or aspect_ratio
                if max_img_w / max_img_h > ratio then
                    self.height = max_img_h
                    self.width = max_img_h * ratio
                else
                    self.width = max_img_w
                    self.height = max_img_w / ratio
                end
            end

            debug.setupvalue(MosaicMenuItem.update, n, StretchingImageWidget)
        end
    end

    -- Settings definitions
    local function BooleanSetting(text, name, default)
        local s = { text = text }
        s.get = function()
            local setting = BookInfoManager:getSetting(name)
            if default then return not setting end
            return setting
        end
        s.toggle = function() return BookInfoManager:toggleSetting(name) end
        return s
    end

    local settings = {
        name_centered = BooleanSetting(_("Folder name centered"), "folder_name_centered", true),
        show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", folder_name),
    }

    -- Series grouping toggle
    local series_setting_name = "automatic_series_grouping_enabled"
    local function isSeriesEnabled()
        return true
    end

    local function setSeriesEnabled(enabled)
        BookInfoManager:saveSetting(series_setting_name, enabled and "Y" or "N")
    end

    -- Capture originals before any overrides
    local orig_init = MosaicMenuItem.init
    local orig_paintTo = MosaicMenuItem.paintTo
    local orig_free = MosaicMenuItem.free
    local orig_update = MosaicMenuItem.update

    -- Corner mark size for progress bar (extract before wrapping paintTo)
    local corner_mark_size = userpatch.getUpValue(orig_paintTo, "corner_mark_size")
        or Screen:scaleBySize(24)

    local function I(v)
        return math.floor(v + 0.5)
    end

    -- MosaicMenuItem.init -- ONE override
    function MosaicMenuItem:init()
        -- [covers] capture max_img_w/max_img_h
        if self.width and self.height then
            local border_size = Size.border.thin
            max_img_w = self.width - 2 * border_size
            max_img_h = self.height - 2 * border_size
        end
        if orig_init then orig_init(self) end

        -- [overlays] build series badge
        if self.is_directory or self.file_deleted then return end

        local bookinfo = BookInfoManager:getBookInfo(self.filepath, false)
        if bookinfo and bookinfo.series and bookinfo.series_index then
            self.series_index = bookinfo.series_index

            local series_text = TextWidget:new{
                text = "#" .. self.series_index,
                face = Font:getFace("cfont", series_cfg.font_size),
                bold = true,
                fgcolor = series_cfg.text_color,
            }

            local series_text_size = series_text:getSize()
            local series_badge_d = math.max(series_text_size.w, series_text_size.h) + Screen:scaleBySize(1)

            self.series_badge = FrameContainer:new{
                linesize = Screen:scaleBySize(2),
                radius = math.floor(series_badge_d / 2),
                color = series_cfg.border_color,
                bordersize = series_cfg.border_thickness,
                background = series_cfg.background_color,
                padding = 0,
                margin = 0,
                CenterContainer:new{
                    dimen = { w = series_badge_d, h = series_badge_d },
                    series_text,
                },
            }

            self._series_text = series_text
            self.has_series_badge = true
        end
    end

    -- MosaicMenuItem.update -- ONE override
    function MosaicMenuItem:update(...)
        orig_update(self, ...)

        -- [pages] Capture page count from sidecar (BookList cache, no new I/O)
        self.pages = nil
        if self.filepath and not self.is_directory and not self.file_deleted then
            local book_info = self.menu.getBookInfo(self.filepath)
            if book_info and book_info.pages then
                self.pages = book_info.pages
            end
        end

        -- [new] Flag recently added, unread books
        self._is_new = false
        if self.filepath and not self.is_directory and not self.file_deleted
            and not self.percent_finished and not self.been_opened then
            local attr = lfs.attributes(self.filepath)
            if attr and attr.modification then
                local age_days = (os.time() - attr.modification) / 86400
                if age_days <= new_badge_cfg.max_age_days then
                    self._is_new = true
                end
            end
        end

        -- [title] Shrink CenterContainer so cover sits in top portion; store title/meta for paintTo
        if false and self._has_cover_image and not self.is_directory and not self.file_deleted then
            local bookinfo = BookInfoManager:getBookInfo(self.filepath, false)
            local has_meta = bookinfo and not bookinfo.ignore_meta
            local title_text = (has_meta and bookinfo.title) or self.text
            if title_text then
                local existing = self._underline_container[1]  -- CenterContainer{FrameContainer{image}}
                if existing and existing.dimen then
                    existing.dimen.h = self.height - title_strip_h - card_gap_px
                end
                self._cover_frame = existing and existing[1]
                if self._cover_frame then
                    self._cover_frame.bordersize = 0
                end

                -- Build secondary line: series (#N) or author
                local meta_line
                if has_meta then
                    if bookinfo.series then
                        meta_line = bookinfo.series
                        if bookinfo.series_index then
                            meta_line = meta_line .. " #" .. bookinfo.series_index
                        end
                    elseif bookinfo.authors then
                        meta_line = bookinfo.authors
                    end
                end

                local strip_content_h = title_strip_h - Screen:scaleBySize(title_cfg.padding)
                local title_max_h = meta_line and (title_line_h * 2) or strip_content_h
                local meta_max_h = meta_line and (strip_content_h - title_max_h) or 0

                if self._title_widget then
                    self._title_widget:free(true)
                end
                self._title_widget = TextBoxWidget:new{
                    text = BD.auto(title_text),
                    face = Font:getFace("cfont", title_cfg.font_size),
                    width = self.width - Screen:scaleBySize(8),
                    alignment = "center",
                    fgcolor = title_cfg.text_color,
                    height = title_max_h,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                }

                if self._meta_widget then
                    self._meta_widget:free(true)
                    self._meta_widget = nil
                end
                if meta_line and meta_max_h > 0 then
                    self._meta_widget = TextBoxWidget:new{
                        text = BD.auto(meta_line),
                        face = Font:getFace("cfont", title_cfg.meta_font_size),
                        width = self.width - Screen:scaleBySize(8),
                        alignment = "center",
                        fgcolor = title_cfg.meta_color,
                        height = meta_max_h,
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    }
                end
            end
        end

        -- [covers] folder cover logic
        if not self._foldercover_processed and not self.menu.no_refresh_covers and self.do_cover_image then
            if not (self.entry.is_file or self.entry.file) and self.mandatory then
                local dir_path = self.entry and self.entry.path
                if dir_path then
                    self._foldercover_processed = true

                    local cover_file = findCover(dir_path)
                    if cover_file then
                        local success, w, h = pcall(function()
                            local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                            tmp_img:_render()
                            local orig_w = tmp_img:getOriginalWidth()
                            local orig_h = tmp_img:getOriginalHeight()
                            tmp_img:free()
                            return orig_w, orig_h
                        end)
                        if success then
                            self:_setFolderCover { file = cover_file, w = w, h = h }
                            return
                        end
                    end

                    self.menu._dummy = true
                    local entries = self.menu:genItemTableFromPath(dir_path)
                    self.menu._dummy = false
                    if entries then
                        for _, entry in ipairs(entries) do
                            if entry.is_file or entry.file then
                                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched
                                   and not bookinfo.ignore_cover and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                                    self:_setFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        -- [series] series group cover logic
        if self.entry and self.entry.is_series_group and not self._seriescover_processed and self.do_cover_image then
            self._seriescover_processed = true

            local series_items = self.entry.series_items
            if series_items and #series_items > 0 then
                if not self.mandatory then
                    self.mandatory = tostring(#series_items) .. " \u{F016}"
                end

                for _, book_entry in ipairs(series_items) do
                    if book_entry.path then
                        local bookinfo = BookInfoManager:getBookInfo(book_entry.path, true)
                        if bookinfo
                            and bookinfo.cover_bb
                            and bookinfo.has_cover
                            and bookinfo.cover_fetched
                            and not bookinfo.ignore_cover
                            and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                            if self._setFolderCover then
                                self:_setFolderCover({
                                    data = bookinfo.cover_bb,
                                    w = bookinfo.cover_w,
                                    h = bookinfo.cover_h
                                })
                            end
                            break
                        end
                    end
                end
            end
        end

        -- Shrink directory widget for items without folder covers (go-up item, uncovered folders)
        -- so they vertically align with folder cards that use cover_h.
        -- Widget tree: FrameContainer{ OverlapGroup{ CenterContainer, BottomContainer } }
        if self.is_directory and not self._folder_frame_dimen then
            local existing = self._underline_container and self._underline_container[1]
            if existing then
                local cover_h = self.height - title_strip_h - card_gap_px
                local margin = existing.margin or 0
                local padding = existing.padding or 0
                local bs = existing.bordersize or 0
                local inner_h = cover_h - (margin + padding + bs) * 2

                existing.height = cover_h
                if existing.dimen then existing.dimen.h = cover_h end

                local overlap = existing[1]  -- OverlapGroup
                if overlap and overlap.dimen then
                    overlap.dimen.h = inner_h
                    for _, child in ipairs(overlap) do
                        if child.dimen then child.dimen.h = inner_h end
                    end
                end
            end
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        local border_size = 0
        local cover_h = self.height - title_strip_h - card_gap_px
        local frame_dimen = getAspectRatioAdjustedDimensions(self.width, cover_h, border_size)
        local image_width = frame_dimen.w - 2 * border_size
        local image_height = frame_dimen.h - 2 * border_size

        local image = img.file and
            ImageWidget:new { file = img.file, width = image_width, height = image_height, stretch_limit_percentage = stretch_limit } or
            ImageWidget:new { image = img.data, width = image_width, height = image_height, stretch_limit_percentage = stretch_limit }

        local image_widget = FrameContainer:new {
            padding = 0, bordersize = border_size, image, overlap_align = "center",
        }

        local image_size = image:getSize()

        -- Compute item count for nbitems badge and meta line
        local item_count = 0
        if self.mandatory then
            local count_str = self.mandatory:match("(%d+)")
            if count_str then item_count = tonumber(count_str) end
        end

        -- Build folder title/meta widgets for card layout (painted in paintTo)
        if self._folder_title_widget then
            self._folder_title_widget:free(true)
            self._folder_title_widget = nil
        end
        if self._folder_meta_widget then
            self._folder_meta_widget:free(true)
            self._folder_meta_widget = nil
        end

        if settings.show_folder_name.get() then
            local text = self.text
            if text:match("/$") then text = text:sub(1, -2) end
            text = BD.directory(capitalize(text))

            local strip_content_h = title_strip_h - Screen:scaleBySize(title_cfg.padding)
            local title_max_h = strip_content_h
            local meta_max_h = 0

            self._folder_title_widget = TextBoxWidget:new{
                text = text,
                face = Font:getFace("cfont", title_cfg.font_size),
                width = self.width - Screen:scaleBySize(8),
                alignment = "center",
                bold = true,
                fgcolor = title_cfg.text_color,
                height = title_max_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            }

            if false and item_count > 0 and meta_max_h > 0 then
                local meta_text = tostring(item_count) .. " " .. (item_count == 1 and _("book") or _("books"))
                self._folder_meta_widget = TextBoxWidget:new{
                    text = meta_text,
                    face = Font:getFace("cfont", title_cfg.meta_font_size),
                    width = self.width - Screen:scaleBySize(8),
                    alignment = "center",
                    fgcolor = title_cfg.meta_color,
                    height = meta_max_h,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                }
            end
        end

        local nbitems_widget

        if item_count > 0 then
            local nbitems = TextWidget:new {
                text = tostring(item_count),
                face = Font:getFace("cfont", Folder.face.nb_items_font_size),
                bold = true, padding = 0
            }

            local nb_size = math.max(nbitems:getSize().w, nbitems:getSize().h)
            nbitems_widget = BottomContainer:new {
                dimen = frame_dimen,
                RightContainer:new {
                    dimen = {
                        w = frame_dimen.w - Folder.face.nb_items_margin,
                        h = nb_size + Folder.face.nb_items_margin * 2,
                    },
                    FrameContainer:new {
                        padding = 2, bordersize = Folder.face.border_size,
                        radius = math.ceil(nb_size), background = Blitbuffer.COLOR_GRAY_E,
                        CenterContainer:new { dimen = { w = nb_size, h = nb_size }, nbitems },
                    },
                },
                overlap_align = "center",
            }
        else
            nbitems_widget = VerticalSpan:new { width = 0 }
        end

        self._folder_frame_dimen = frame_dimen
        self._folder_image_size = image_size

        local widget = CenterContainer:new {
            dimen = { w = self.width, h = cover_h },
            CenterContainer:new {
                dimen = { w = self.width, h = cover_h },
                OverlapGroup:new {
                    dimen = frame_dimen,
                    image_widget,
                    nbitems_widget,
                },
            },
        }

        if self._underline_container[1] then
            self._underline_container[1]:free()
        end
        self._underline_container[1] = widget
    end

    function MosaicMenuItem:_getTextBox(dimen)
        local text = self.text
        if text:match("/$") then text = text:sub(1, -2) end
        text = BD.directory(capitalize(text))

        local available_height = dimen.h
        local dir_font_size = Folder.face.dir_max_font_size
        local directory

        while true do
            if directory then directory:free(true) end
            directory = TextBoxWidget:new {
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then break end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end
        return directory
    end

    -- MosaicMenuItem.paintTo -- ONE override
    local _dbg_paint_seen = {}
    function MosaicMenuItem:paintTo(bb, x, y)
        orig_paintTo(self, bb, x, y)

        -- One-shot per-file debug dump (only first paintTo per filepath)
        if DEBUG_ICONS and self.filepath and not _dbg_paint_seen[self.filepath] then
            _dbg_paint_seen[self.filepath] = true
            local fname = self.filepath:match("[^/]+$") or self.filepath
            logger.info("[custom-icons] paintTo:", fname,
                "| is_dir:", tostring(self.is_directory),
                "| deleted:", tostring(self.file_deleted),
                "| status:", tostring(self.status),
                "| pct:", tostring(self.percent_finished),
                "| opened:", tostring(self.been_opened),
                "| hint:", tostring(self.do_hint_opened),
                "| bookinfo_found:", tostring(self.bookinfo_found),
                "| menu:", tostring(self.menu and self.menu.name))
            local t = self[1] and self[1][1] and self[1][1][1]
            logger.info("[custom-icons]   target:", tostring(t),
                "| target.dimen:", tostring(t and t.dimen))
        end

        -- [covers] Folder path
        if self._folder_frame_dimen and self._folder_image_size then
            if not (self.entry.is_file or self.entry.file) then
                local frame_dimen = self._folder_frame_dimen
                local image_size = self._folder_image_size
                local cover_h = self.height - title_strip_h - card_gap_px
                local fx = x + math.floor((self.width - frame_dimen.w) / 2)
                local fy = y + math.floor((cover_h - frame_dimen.h) / 2)
                local image_x = fx + math.floor((frame_dimen.w - image_size.w) / 2)
                local image_y = fy + math.floor((frame_dimen.h - image_size.h) / 2)

                -- Draw stacked bars above folder cover
                local BAR_FILLS     = { Blitbuffer.COLOR_GRAY_5, Blitbuffer.COLOR_GRAY_9, Blitbuffer.COLOR_GRAY_D }
                local BAR_BORDERS   = { Blitbuffer.COLOR_GRAY_1, Blitbuffer.COLOR_GRAY_5, Blitbuffer.COLOR_GRAY_9 }
                local BAR_BORDER_W  = 1
                local BAR_HEIGHT    = Screen:scaleBySize(2)
                local BAR_SPACING   = Screen:scaleBySize(2)
                local COVER_GAP     = Screen:scaleBySize(3)
                local BAR_RATIOS    = { 0.84, 0.74, 0.64 }

                local center_x = image_x + math.floor(image_size.w / 2)
                local current_y = image_y - COVER_GAP - BAR_HEIGHT

                for i = 1, #BAR_RATIOS do
                    local bar_w = math.floor(image_size.w * BAR_RATIOS[i])
                    local bar_x = center_x - math.floor(bar_w / 2)
                    local bar_y = current_y
                    bb:paintRect(bar_x, bar_y, bar_w, BAR_HEIGHT, BAR_FILLS[i])
                    bb:paintBorder(bar_x, bar_y, bar_w, BAR_HEIGHT, BAR_BORDER_W, BAR_BORDERS[i])
                    current_y = bar_y - BAR_HEIGHT - BAR_SPACING
                end

                -- White fill from below cover to cell bottom
                local fill_top = fy + frame_dimen.h
                local fill_h = self.height - (fill_top - y)
                if fill_h > 0 then
                    bb:paintRect(image_x, fill_top, image_size.w, fill_h, Blitbuffer.COLOR_WHITE)
                end

                -- Dark grey border around cover
                local cover_border_w = Screen:scaleBySize(folder_border)
                bb:paintBorder(image_x, image_y, image_size.w - 1, image_size.h, cover_border_w, Blitbuffer.COLOR_DARK_GRAY, 0, false)

                paintCorners(bb, image_x, image_y, image_size.w, image_size.h)

                -- Folder title below cover
                if self._folder_title_widget then
                    local strip_top = y + self.height - title_strip_h
                    local tw = self._folder_title_widget:getSize().w
                    local title_x = x + math.floor((self.width - tw) / 2)
                    self._folder_title_widget:paintTo(bb, title_x, strip_top)

                    if self._folder_meta_widget then
                        local mw = self._folder_meta_widget:getSize().w
                        local meta_x = x + math.floor((self.width - mw) / 2)
                        local meta_y = strip_top + self._folder_title_widget:getSize().h
                        self._folder_meta_widget:paintTo(bb, meta_x, meta_y)
                    end
                end
                return
            end
        end

        -- [covers] Book path
        if self.is_directory or self.file_deleted then return end
        local target = self._cover_frame or (self[1] and self[1][1] and self[1][1][1])
        if not target or not target.dimen then return end

        local cover_area_h = self._title_widget and (self.height - title_strip_h - card_gap_px) or self.height
        local fx = x + math.floor((self.width - target.dimen.w) / 2)
        local fy = y + math.floor((cover_area_h - target.dimen.h) / 2)
        local fw, fh = target.dimen.w, target.dimen.h

        -- [merged] Single-book visuals are handled by the Real Books layer below.
        -- Keep Visual Overhaul for folder cards + virtual series grouping only.
        do return end

        -- [covers] Border around cover (inset 1px so corner masks fully cover it)
        local cover_border = Screen:scaleBySize(0.5)
        bb:paintBorder(fx, fy, fw - 1, fh, cover_border, Blitbuffer.COLOR_DARK_GRAY, 0, false)

        -- [card] White fill from below cover to cell bottom (gap + text area)
        if self._title_widget then
            local fill_top = y + cover_area_h
            local fill_h = self.height - cover_area_h
            bb:paintRect(fx, fill_top, fw, fill_h, Blitbuffer.COLOR_WHITE)
        end

        paintCorners(bb, fx, fy, fw, fh)

        -- [overlays] Progress bar (hidden below MIN_PERCENT and at/above NEAR_COMPLETE_PERCENT)
        local pf = self.percent_finished
        local _has_bar = pf and self.status ~= "complete"
            and pf >= bar_cfg.MIN_PERCENT and pf < bar_cfg.NEAR_COMPLETE_PERCENT
        local bar_bottom_y  -- y coordinate of bottom edge of bar (used by pages badge)
        if _has_bar then
            local bar_w = math.max(1, math.floor(fw * 0.64))
            local bar_h = bar_cfg.H
            local bar_x = I(fx + Screen:scaleBySize(4))
            local bar_y = I(fy + math.floor(fh * 8 / 10))

            bb:paintRoundedRect(
                bar_x - bar_cfg.BORDER_W, bar_y - bar_cfg.BORDER_W,
                bar_w + 2 * bar_cfg.BORDER_W, bar_h + 2 * bar_cfg.BORDER_W,
                bar_cfg.BORDER_COLOR, bar_cfg.RADIUS + bar_cfg.BORDER_W
            )
            bb:paintRoundedRect(bar_x, bar_y, bar_w, bar_h, bar_cfg.TRACK_COLOR, bar_cfg.RADIUS)

            local p = math.max(0, math.min(1, pf))
            local fw_w = math.max(1, math.floor(bar_w * p + 0.5))
            local fill_color = (self.status == "abandoned") and bar_cfg.ABANDONED_COLOR or bar_cfg.FILL_COLOR
            bb:paintRoundedRect(bar_x, bar_y, fw_w, bar_h, fill_color, bar_cfg.RADIUS)

            bar_bottom_y = bar_y + bar_h
        end

        -- [overlays] Status icons (dogear at bottom-right)
        -- Treat books at/above NEAR_COMPLETE_PERCENT as visually complete
        local effective_status = self.status
        if pf and pf >= bar_cfg.NEAR_COMPLETE_PERCENT and effective_status ~= "complete" and effective_status ~= "abandoned" then
            effective_status = "complete"
        end

        local _show_dogear = effective_status == "complete"
            or effective_status == "abandoned"
            or (
                self.percent_finished
                and (
                    (self.do_hint_opened and self.been_opened)
                    or self.menu.name == "history"
                    or self.menu.name == "collections"
                )
            )
        if DEBUG_ICONS and self.filepath and _dbg_paint_seen[self.filepath] == true then
            _dbg_paint_seen[self.filepath] = "logged"
            local fname = self.filepath:match("[^/]+$") or self.filepath
            logger.info("[custom-icons] dogear?", tostring(_show_dogear), "for", fname)
        end
        if _show_dogear then
            local icon_corner_mark_size = math.floor(math.min(self.width, self.height) / 8)

            local icon_ix, icon_iy

            local icon_inset_x = Screen:scaleBySize(4)
            if BD.mirroredUILayout() then
                icon_ix = math.floor((self.width - fw) / 2) + icon_inset_x
            else
                icon_ix = self.width - math.ceil((self.width - fw) / 2) - icon_corner_mark_size - icon_inset_x
            end
            local corner_inset = Screen:scaleBySize(8)
            icon_iy = cover_area_h - math.ceil((cover_area_h - fh) / 2) - icon_corner_mark_size - corner_inset

            local mark

            if effective_status == "abandoned" then
                mark = IconWidget:new({
                    icon = BD.mirroredUILayout() and "dogear.abandoned.rtl" or "dogear.abandoned",
                    width = icon_corner_mark_size,
                    height = icon_corner_mark_size,
                    alpha = true,
                })
            elseif effective_status == "complete" then
                mark = IconWidget:new({
                    icon = BD.mirroredUILayout() and "dogear.complete.rtl" or "dogear.complete",
                    width = icon_corner_mark_size,
                    height = icon_corner_mark_size,
                    alpha = true,
                })
            else
                mark = IconWidget:new({
                    icon = "dogear.reading",
                    rotation_angle = BD.mirroredUILayout() and 270 or 0,
                    width = icon_corner_mark_size,
                    height = icon_corner_mark_size,
                    alpha = true,
                })
            end

            if mark then
                mark:paintTo(bb, x + icon_ix, y + icon_iy)
            end
        end

        -- [overlays] Pages badge (bottom-left, non-complete books)
        local _show_pages = not self.is_directory and not self.file_deleted
            and self.status ~= "complete"
        if DEBUG_ICONS and self.filepath and _dbg_paint_seen[self.filepath] == "logged" then
            _dbg_paint_seen[self.filepath] = "done"
            local fname = self.filepath:match("[^/]+$") or self.filepath
            logger.info("[custom-icons] pages_gate?", tostring(_show_pages), "for", fname,
                "| is_dir:", tostring(self.is_directory),
                "| deleted:", tostring(self.file_deleted),
                "| status:", tostring(self.status),
                "| opened:", tostring(self.been_opened),
                "| self.pages:", tostring(self.pages))
        end
        if _show_pages then
            -- Source 1: sidecar pages (accurate for all opened books; set in update)
            local page_count = self.pages
            -- Source 2: BookInfoManager DB (works for unread PDF/DjVu, nil for EPUBs)
            if not page_count and self.filepath then
                local bookinfo = BookInfoManager:getBookInfo(self.filepath, false)
                if bookinfo and bookinfo.pages then
                    page_count = bookinfo.pages
                end
            end

            if page_count then
                local pages_corner_mark_size = Screen:scaleBySize(10)
                local page_text = page_count .. " p."
                local pfont_size = math.floor(pages_corner_mark_size * pages_cfg.font_size)

                local pages_text = TextWidget:new({
                    text = page_text,
                    face = Font:getFace("cfont", pfont_size),
                    alignment = "left",
                    fgcolor = pages_cfg.text_color,
                    bold = true,
                    padding = 2,
                })

                local pages_badge = FrameContainer:new({
                    linesize = Screen:scaleBySize(2),
                    radius = Screen:scaleBySize(pages_cfg.border_corner_radius),
                    color = pages_cfg.border_color,
                    bordersize = pages_cfg.border_thickness,
                    background = pages_cfg.background_color,
                    padding = Screen:scaleBySize(2),
                    margin = 0,
                    pages_text,
                })

                local cover_left = x + math.floor((self.width - fw) / 2)
                local cover_bottom = y + cover_area_h - math.floor((cover_area_h - fh) / 2)
                local badge_w, badge_h = pages_badge:getSize().w, pages_badge:getSize().h

                local pos_x_badge = cover_left + Screen:scaleBySize(4)
                local pos_y_badge
                if _has_bar and bar_bottom_y then
                    pos_y_badge = bar_bottom_y + Screen:scaleBySize(3)
                else
                    pos_y_badge = cover_bottom - badge_h - Screen:scaleBySize(4)
                end

                pages_badge:paintTo(bb, pos_x_badge, pos_y_badge)
            end
        end

        -- [overlays] Percent badge (top-right, in-progress books)
        if not self.is_directory and self.status ~= "complete" and self.percent_finished then
            if
                (self.do_hint_opened and self.been_opened)
                or self.menu.name == "history"
                or self.menu.name == "collections"
            then
                local pct_corner_mark_size = Screen:scaleBySize(20)
                local percent_text = string.format("%d%%", math.floor(self.percent_finished * 100))
                local pct_font_size = math.floor(pct_corner_mark_size * percent_cfg.text_size)
                local percent_widget = TextWidget:new({
                    text = percent_text,
                    font_size = pct_font_size,
                    face = Font:getFace("cfont", pct_font_size),
                    alignment = "center",
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    bold = true,
                    max_width = pct_corner_mark_size,
                    truncate_with_ellipsis = true,
                })

                local PBADGE_W = Screen:scaleBySize(percent_cfg.badge_w)
                local PBADGE_H = Screen:scaleBySize(percent_cfg.badge_h)
                local PINSET_X = Screen:scaleBySize(percent_cfg.move_on_x)
                local PINSET_Y = Screen:scaleBySize(percent_cfg.move_on_y)
                local TEXT_PAD = Screen:scaleBySize(6)

                local pfx = x + math.floor((self.width - fw) / 2)
                local pfy = y + math.floor((cover_area_h - fh) / 2)
                local pfw = fw

                local percent_badge_icon = IconWidget:new({ icon = "percent.badge", alpha = true })
                percent_badge_icon.width = PBADGE_W
                percent_badge_icon.height = PBADGE_H

                local bx = pfx + pfw - PBADGE_W - PINSET_X
                local by = pfy + PINSET_Y
                bx, by = math.floor(bx), math.floor(by)

                percent_badge_icon:paintTo(bb, bx, by)
                percent_widget.alignment = "center"
                percent_widget.truncate_with_ellipsis = false
                percent_widget.max_width = PBADGE_W - 2 * TEXT_PAD

                local ts = percent_widget:getSize()
                local tx = bx + math.floor((PBADGE_W - ts.w) / 2)
                local ty = by + math.floor((PBADGE_H - ts.h) / 2) - Screen:scaleBySize(percent_cfg.bump_up)
                percent_widget:paintTo(bb, math.floor(tx), math.floor(ty))
            end
        end

        -- [overlays] Series badge (top-left)
        if self.has_series_badge and self.series_badge then
            local sbadge_x = fx + Screen:scaleBySize(2)
            local sbadge_y = fy + Screen:scaleBySize(2)
            self.series_badge:paintTo(bb, sbadge_x, sbadge_y)
        end

        -- [overlays] New badge (top-left, recently added unread books)
        if self._is_new then
            local NBADGE_W = Screen:scaleBySize(new_badge_cfg.badge_w)
            local NBADGE_H = Screen:scaleBySize(new_badge_cfg.badge_h)

            local new_badge_icon = IconWidget:new({ icon = "new", alpha = true })
            new_badge_icon.width = NBADGE_W
            new_badge_icon.height = NBADGE_H

            local cover_left = x + math.floor((self.width - fw) / 2)
            local cover_top = y + math.floor((cover_area_h - fh) / 2)
            local ninset_x = Screen:scaleBySize(new_badge_cfg.inset_x)
            local ninset_y = Screen:scaleBySize(new_badge_cfg.inset_y)

            new_badge_icon:paintTo(bb, cover_left + ninset_x, cover_top + ninset_y)
        end

        -- [title] Paint title and meta text below the cover image
        if self._title_widget and target and target.dimen then
            local strip_top = y + self.height - title_strip_h
            local tw = self._title_widget:getSize().w
            local th = self._title_widget:getSize().h
            local title_x = x + math.floor((self.width - tw) / 2)
            self._title_widget:paintTo(bb, title_x, strip_top)

            if self._meta_widget then
                local mw = self._meta_widget:getSize().w
                local meta_x = x + math.floor((self.width - mw) / 2)
                local meta_y = strip_top + th
                self._meta_widget:paintTo(bb, meta_x, meta_y)
            end
        end


    end

    function MosaicMenuItem:onFocus()
        self._focused = true
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end

    function MosaicMenuItem:onUnfocus()
        self._focused = false
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end

    -- MosaicMenuItem.free
    if orig_free then
        function MosaicMenuItem:free()
            if self._series_text then
                self._series_text:free(true)
                self._series_text = nil
            end

            if self.series_badge then
                self.series_badge:free(true)
                self.series_badge = nil
            end

            self.series_index = nil
            self.has_series_badge = nil
            self._cover_frame = nil

            if self._title_widget then
                self._title_widget:free(true)
                self._title_widget = nil
            end

            if self._meta_widget then
                self._meta_widget:free(true)
                self._meta_widget = nil
            end

            if self._folder_title_widget then
                self._folder_title_widget:free(true)
                self._folder_title_widget = nil
            end
            if self._folder_meta_widget then
                self._folder_meta_widget:free(true)
                self._folder_meta_widget = nil
            end

            orig_free(self)
        end
    end

    -- AutomaticSeries methods
    local function isDirectory(item)
        return item.is_directory or (item.attr and item.attr.mode == "directory") or item.mode == "directory"
    end

    local AutomaticSeries = {}

    function AutomaticSeries:processItemTable(item_table, file_chooser)
        if not file_chooser or not item_table then return end

        if file_chooser.show_current_dir_for_hold then return end

        logger.dbg("AutomaticSeries: Processing Items")

        local collate, collate_id = file_chooser:getCollate()
        local reverse = G_reader_settings:isTrue("reverse_collate")
        local sort_func = file_chooser:getSortingFunction(collate, reverse)
        local mixed = G_reader_settings:isTrue("collate_mixed") and collate.can_collate_mixed

        local is_name_sort = (collate_id == "strcoll" or collate_id == "natural" or collate_id == "title")

        local series_map = {}
        local processed_list = {}

        local book_count = 0
        local non_series_book_count = 0

        for _, item in ipairs(item_table) do
            if item.is_go_up then
                table.insert(processed_list, item)
            else
                if not item.sort_percent then item.sort_percent = 0 end
                if not item.percent_finished then item.percent_finished = 0 end
                if not item.opened then item.opened = false end

                local is_file = item.is_file
                local series_handled = false

                if is_file and item.path then
                    book_count = book_count + 1

                    local doc_props = item.doc_props or BookInfoManager:getDocProps(item.path)
                    if doc_props and doc_props.series and doc_props.series ~= "\u{FFFF}" then
                        local series_name = doc_props.series

                        item._series_index = doc_props.series_index or 0

                        if not series_map[series_name] then
                            logger.dbg("AutomaticSeries: Found series", series_name)

                            local group_attr = {}
                            if item.attr then
                                for k, v in pairs(item.attr) do group_attr[k] = v end
                            end
                            group_attr.mode = "directory"

                            local group_item = {
                                text = series_name,
                                is_file = false,
                                is_directory = true,
                                path = (item.path:match("(.*/)") or item.path) .. series_name,
                                is_series_group = true,
                                series_items = { item },
                                attr = group_attr,
                                mode = "directory",
                                sort_percent = item.sort_percent,
                                percent_finished = item.percent_finished,
                                opened = item.opened,
                                doc_props = item.doc_props or {
                                    series = series_name,
                                    series_index = 0,
                                    display_title = series_name,
                                },
                                suffix = item.suffix,
                            }
                            series_map[series_name] = group_item
                            table.insert(processed_list, group_item)
                            group_item._list_index = #processed_list
                        else
                            table.insert(series_map[series_name].series_items, item)
                        end
                        series_handled = true
                    else
                        non_series_book_count = non_series_book_count + 1
                    end
                end

                if not series_handled then
                    table.insert(processed_list, item)
                end
            end
        end

        logger.dbg("AutomaticSeries: Done grouping.")

        local series_count = 0
        for _ in pairs(series_map) do
            series_count = series_count + 1
            if series_count > 1 then break end
        end

        if series_count == 1 and non_series_book_count == 0 and book_count > 0 then
            logger.dbg("AutomaticSeries: Skipping - all books from same series")
            return
        end

        for _, group in pairs(series_map) do
            if #group.series_items == 1 then
                if group._list_index and processed_list[group._list_index] == group then
                    local single_book = group.series_items[1]
                    processed_list[group._list_index] = single_book
                end
            else
                group.mandatory = tostring(#group.series_items) .. " \u{F016}"
                table.sort(group.series_items, function(a, b)
                    return (a._series_index or 0) < (b._series_index or 0)
                end)
            end
        end

        local final_table = {}

        if mixed then
            if is_name_sort then
                local up_item
                local to_sort = {}
                for _, item in ipairs(processed_list) do
                    if item.is_go_up then up_item = item else table.insert(to_sort, item) end
                end
                local ok, err = pcall(table.sort, to_sort, sort_func)
                if not ok then
                    logger.warn("AutomaticSeries: Sort failed, using unsorted list:", err)
                end

                if up_item then table.insert(final_table, up_item) end
                for _, item in ipairs(to_sort) do table.insert(final_table, item) end
            else
                final_table = processed_list
            end
        else
            local dirs = {}
            local files = {}
            local up_item

            for _, item in ipairs(processed_list) do
                if item.is_go_up then
                    up_item = item
                elseif isDirectory(item) then
                    table.insert(dirs, item)
                else
                    table.insert(files, item)
                end
            end

            local ok, err = pcall(table.sort, dirs, sort_func)
            if not ok then
                logger.warn("AutomaticSeries: Sort failed, using unsorted list:", err)
            end

            if up_item then table.insert(final_table, up_item) end
            for _, d in ipairs(dirs) do table.insert(final_table, d) end
            for _, f in ipairs(files) do table.insert(final_table, f) end
        end

        logger.dbg("AutomaticSeries: Done sorting.")

        for k in pairs(item_table) do item_table[k] = nil end
        for i, v in ipairs(final_table) do item_table[i] = v end
    end

    function AutomaticSeries:openSeriesGroup(file_chooser, group_item)
        if not file_chooser then
            return
        end

        local items = group_item.series_items

        local parent_path = file_chooser.path

        current_series_group = {
            series_name = group_item.text,
            parent_path = parent_path,
        }

        logger.dbg("AutomaticSeries: Opening series:", group_item.text)

        local is_browser_up_folder_enabled = file_chooser._changeLeftIcon ~= nil
            and G_reader_settings:readSetting("filemanager_hide_up_folder", false)

        items.is_in_series_view = true
        items.parent_path = parent_path

        file_chooser:switchItemTable(nil, items, nil, nil, group_item.text)

        if is_browser_up_folder_enabled then
            file_chooser:_changeLeftIcon(Icon.up, function() file_chooser:onFolderUp() end)
        end
    end

    local function exitVirtualFolderIfNeeded(file_chooser)
        if file_chooser and file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            local parent_path = file_chooser.item_table.parent_path
            if parent_path then
                logger.dbg("AutomaticSeries: Exiting virtual folder, returning to parent path:", parent_path)
                if current_series_group then
                    current_series_group.should_restore_focus = true
                end
                file_chooser:changeToPath(parent_path)
                return true
            end
        end
        return false
    end

    -- FileChooser hooks
    local old_setSubTitle = TitleBar.setSubTitle
    TitleBar.setSubTitle = function(self, subtitle, no_refresh)
        if current_series_group then
            return old_setSubTitle(self, current_series_group.series_name, no_refresh)
        end
        return old_setSubTitle(self, subtitle, no_refresh)
    end

    local old_updateItems = FileChooser.updateItems
    local old_onMenuSelect = FileChooser.onMenuSelect
    local old_onFolderUp = FileChooser.onFolderUp
    local old_changeToPath = FileChooser.changeToPath
    local old_refreshPath = FileChooser.refreshPath
    local old_goHome = FileChooser.goHome
    local old_switchItemTable = FileChooser.switchItemTable

    FileChooser.switchItemTable = function(file_chooser, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
        if isSeriesEnabled() and new_item_table and not new_item_table.is_in_series_view then
            AutomaticSeries:processItemTable(new_item_table, file_chooser)
        end

        return old_switchItemTable(file_chooser, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
    end

    FileChooser.goHome = function(file_chooser)
        if file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            if current_series_group then
                current_series_group.should_restore_focus = true
            end

            local parent_path = file_chooser.item_table.parent_path
            local home_dir = G_reader_settings:readSetting("home_dir") or require("device").home_dir

            if parent_path and home_dir and parent_path == home_dir then
                file_chooser:changeToPath(parent_path)
                return true
            end
        end
        return old_goHome(file_chooser)
    end

    FileChooser.refreshPath = function(file_chooser)
        old_refreshPath(file_chooser)
        if isSeriesEnabled() and current_series_group then
            local series_name = current_series_group.series_name
            for _, item in ipairs(file_chooser.item_table) do
                if item.is_series_group and item.text == series_name then
                    AutomaticSeries:openSeriesGroup(file_chooser, item)
                    break
                end
            end
        end
    end

    FileChooser.onFolderUp = function(file_chooser)
        if exitVirtualFolderIfNeeded(file_chooser) then
            return true
        end
        return old_onFolderUp(file_chooser)
    end

    FileChooser.onMenuSelect = function(file_chooser, item)
        if isSeriesEnabled() and item.is_series_group then
            AutomaticSeries:openSeriesGroup(file_chooser, item)
            return true
        end

        return old_onMenuSelect(file_chooser, item)
    end

    FileChooser.changeToPath = function(file_chooser, path, ...)
        if file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            local parent_path = file_chooser.item_table.parent_path
            if parent_path and path and (path:match("/%.%.") or path:match("^%.%.")) then
                path = parent_path
            end
            if current_series_group then
                current_series_group.should_restore_focus = true
            end
        else
            current_series_group = nil
        end

        return old_changeToPath(file_chooser, path, ...)
    end

    FileChooser.updateItems = function(file_chooser, ...)
        if not isSeriesEnabled() then
            current_series_group = nil
            return old_updateItems(file_chooser, ...)
        end

        if not file_chooser.item_table or #file_chooser.item_table == 0 then
            return old_updateItems(file_chooser, ...)
        end

        if file_chooser.item_table.is_in_series_view then
            return old_updateItems(file_chooser, ...)
        end

        if current_series_group and current_series_group.should_restore_focus
           and file_chooser.item_table and #file_chooser.item_table > 0 then
            logger.dbg("AutomaticSeries: Looking for series to restore focus:", current_series_group.series_name)
            for index, item in ipairs(file_chooser.item_table) do
                if item.is_series_group and item.text == current_series_group.series_name then
                    logger.dbg("AutomaticSeries: Found series group at index:", index)
                    local page = math.ceil(index / file_chooser.perpage)
                    local select_number = ((index - 1) % file_chooser.perpage) + 1
                    file_chooser.page = page
                    file_chooser.path_items[file_chooser.path] = index
                    current_series_group = nil
                    return old_updateItems(file_chooser, select_number)
                end
            end
            current_series_group = nil
        end

        return old_updateItems(file_chooser, ...)
    end

    -- plugin.addToMainMenu -- ONE override
    local orig_addToMainMenu = plugin.addToMainMenu
    function plugin:addToMainMenu(menu_items)
        orig_addToMainMenu(self, menu_items)

        -- [covers] inject folder-name settings into Mosaic submenu
        if menu_items.filebrowser_settings then
            local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
            if item then
                item.sub_item_table[#item.sub_item_table].separator = true
                for i, setting in pairs(settings) do
                    if not getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"), setting.text) then
                        table.insert(item.sub_item_table, {
                            text = setting.text,
                            checked_func = function() return setting.get() end,
                            callback = function()
                                setting.toggle()
                                self.ui.file_chooser:updateItems()
                            end,
                        })
                    end
                end
            end

            -- [series] inject "Group book series into folders" toggle
            local already_added = false
            for _, sub_item in ipairs(menu_items.filebrowser_settings.sub_item_table) do
                if sub_item._automatic_series_menu_item then
                    already_added = true
                    break
                end
            end

            if not already_added then
                table.insert(menu_items.filebrowser_settings.sub_item_table, {
                    text = _("Group book series into folders"),
                    separator = true,
                    checked_func = isSeriesEnabled,
                    callback = function()
                        setSeriesEnabled(not isSeriesEnabled())
                        if self.ui and self.ui.file_chooser then
                            self.ui.file_chooser:refreshPath()
                        end
                    end,
                    _automatic_series_menu_item = true,
                })
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchVisualOverhaul)

end)
if not ok then
    local logger = require("logger")
    logger.warn("PATCH FAILED: 2--visual-overhaul:", tostring(err))
end

-- ============================================================================
-- Real Books layer below: single-book renderer and its settings menu.
-- ============================================================================

--[[
User patch: Show a semi-transparent vertical label on the left side
of each cover in mosaic view, rotated 90°.
Lines above cover are dynamic based on page count (configurable).

Label text options:
  • filename        – filename without extension (default)
  • title           – metadata title
  • author_title    – "Author – Title"
  • title_author    – "Title – Author"

Cover shape options (independent of spine label enabled state):
  • cover_scale_pct – scale cover up/down as % of its natural size (50–150)
  • aspect_enabled  – enforce a target aspect ratio on every cover
  • aspect_ratio_w/h – ratio W : H (e.g. 2, 3 → 2:3 portrait)
Settings exposed under: Settings → AI Slop Settings

Installation:
  Copy this file to:  koreader/patches/2-real-books.lua
--]]

-- ── defaults ──────────────────────────────────────────────────────────────────
local DEFAULTS = {
    enabled        = true,
    direction      = "up",
    text_mode      = "filename",
    alpha          = 0.80,
    font_size      = 16,
    font_bold      = true,
    font_face      = "NotoSerif",
    dark_mode      = true,
    text_shear     = 30,  -- stored as integer (0 to 100), divided by 100 at use
    padding        = 2,
    page_thickness = 2,
    page_spacing   = 1,
    lines_enabled_2 = true,
    lines_enabled_3 = true,
    lines_enabled_4 = true,
    lines_enabled_5 = true,
    lines_enabled_6 = true,
    lines_enabled_7 = false,
    lines_enabled_8 = false,
    lines_enabled_9 = false,
    lines_enabled_10 = false,
    page_range_2   = 100,
    page_range_3   = 200,
    page_range_4   = 350,
    page_range_5   = 500,
    page_range_6   = 700,
    page_range_7   = 900,
    page_range_8   = 1200,
    page_range_9   = 1500,
    epub_bytes_per_page = 2048,    -- ~2KB per page
    pdf_kb_per_page     = 100,     -- ~100KB per page
    cbz_kb_per_page     = 500,     -- ~500KB per page
    -- cover shape
    cover_scale_pct  = 95,         -- % of natural cover size (50–100)
    aspect_enabled   = false,      -- enforce target aspect ratio
    aspect_ratio_w   = 2,          -- ratio width part
    aspect_ratio_h   = 3,          -- ratio height part
    spine_width_pct       = 100,   -- spine width multiplier % (100–200)
    line_color            = "GRAY_9", -- page count line color (named palette key)
    page_line_length_pct  = 102,   -- page count lines length as % of cover width (10–150)
    progress_badge_enabled = true, -- show quarter-circle progress badge at bottom-right of cover
}

-- ── requires ──────────────────────────────────────────────────────────────────
local FileChooser      = require("ui/widget/filechooser")
local FileManagerMenu  = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local Blitbuffer       = require("ffi/blitbuffer")
local Font             = require("ui/font")
local TextWidget       = require("ui/widget/textwidget")
local CenterContainer  = require("ui/widget/container/centercontainer")
local Geom             = require("ui/geometry")
local userpatch        = require("userpatch")
local util             = require("util")
local logger           = require("logger")

if FileChooser._mosaic_vlabel_patched then return end
FileChooser._mosaic_vlabel_patched = true

-- ── DPI scale helper ──────────────────────────────────────────────────────────
-- Returns the ratio of device DPI to the 160 DPI reference baseline.
-- Font sizes divided by this value stay physically the same size across DPIs.
local function getDPIScale()
    local ok, Screen = pcall(require, "device/screen")
    if not ok or not Screen then return 1 end
    local dpi = Screen:getDPI()
    if not dpi or dpi <= 0 then return 1 end
    return dpi / 160
end

-- ── settings helpers ──────────────────────────────────────────────────────────
local function getCfg()
    return G_reader_settings:readSetting("mosaic_vlabel") or {}
end
local function get(key)
    local cfg = getCfg()
    if cfg[key] ~= nil then return cfg[key] end
    return DEFAULTS[key]
end
local function set(key, value)
    local cfg = getCfg()
    cfg[key] = value
    G_reader_settings:saveSetting("mosaic_vlabel", cfg)
    _item_cache = {}  -- any setting change invalidates the render cache
end

-- ── cached strip width (invalidated when font_size changes via menu) ──────────
local _strip_w_cache = nil
local _strip_w_key   = nil
local function getStripW(item_w)
    local fs  = get("font_size")
    local swp = get("spine_width_pct")
    local key = fs .. (item_w or 0) .. swp
    if _strip_w_cache and _strip_w_key == key then return _strip_w_cache end
    local pad = get("padding")
    local tw = TextWidget:new{ text = "A", face = Font:getFace("cfont", fs) }
    local font_h = tw:getSize().h
    tw:free()
    local max_w = math.floor((font_h + 2 * pad) * 0.75)
    if item_w and item_w > 0 then
        local scaled = math.floor(item_w * 0.15)
        _strip_w_cache = math.floor(math.min(max_w, scaled) * swp / 100)
    else
        _strip_w_cache = math.floor(max_w * swp / 100)
    end
    _strip_w_key = key
    return _strip_w_cache
end

-- ── module-level font map (constant, avoids rebuilding on every paintTo) ──────
local FONT_MAP = {
    NotoSerif            = { regular = "NotoSerif-Italic.ttf",                   bold = "NotoSerif-BoldItalic.ttf"          },
    NotoSerifRegular     = { regular = "NotoSerif-Regular.ttf",                  bold = "NotoSerif-Bold.ttf"                },
    NotoSans             = { regular = "NotoSans-Italic.ttf",                    bold = "NotoSans-BoldItalic.ttf"           },
    NotoSansRegular      = { regular = "NotoSans-Regular.ttf",                   bold = "NotoSans-Bold.ttf"                 },
    NotoNaskhArabic      = { regular = "NotoNaskhArabic-Regular.ttf",            bold = "NotoNaskhArabic-Bold.ttf"          },
    NotoSansArabicUI     = { regular = "NotoSansArabicUI-Regular.ttf",           bold = "NotoSansArabicUI-Bold.ttf"         },
    NotoSansBengaliUI    = { regular = "NotoSansBengaliUI-Regular.ttf",          bold = "NotoSansBengaliUI-Bold.ttf"        },
    NotoSansCJKsc        = { regular = "NotoSansCJKsc-Regular.otf",              bold = "NotoSansCJKsc-Regular.otf"         },
    NotoSansDevanagariUI = { regular = "NotoSansDevanagariUI-Regular.ttf",       bold = "NotoSansDevanagariUI-Bold.ttf"     },
    Symbols              = { regular = "symbols.ttf",                            bold = "symbols.ttf"                      },
    FreeSans             = { regular = "freefont/FreeSans.ttf",                  bold = "freefont/FreeSans.ttf"             },
    FreeSerif            = { regular = "freefont/FreeSerif.ttf",                 bold = "freefont/FreeSerif.ttf"            },
    DroidSansMono        = { regular = "droid/DroidSansMono.ttf",                bold = "droid/DroidSansMono.ttf"           },
}


-- ── page line color map ────────────────────────────────────────────────────────
local LINE_COLOR_MAP = {
    { key = "GRAY_1",      label = "Gray 1  (darkest)",  color = function() return Blitbuffer.COLOR_GRAY_1      end },
    { key = "GRAY_2",      label = "Gray 2",             color = function() return Blitbuffer.COLOR_GRAY_2      end },
    { key = "GRAY_3",      label = "Gray 3",             color = function() return Blitbuffer.COLOR_GRAY_3      end },
    { key = "GRAY_4",      label = "Gray 4  (default)",  color = function() return Blitbuffer.COLOR_GRAY_4      end },
    { key = "GRAY_5",      label = "Gray 5",             color = function() return Blitbuffer.COLOR_GRAY_5      end },
    { key = "GRAY_6",      label = "Gray 6",             color = function() return Blitbuffer.COLOR_GRAY_6      end },
    { key = "GRAY_7",      label = "Gray 7",             color = function() return Blitbuffer.COLOR_GRAY_7      end },
    { key = "DARK_GRAY",   label = "Dark gray",          color = function() return Blitbuffer.COLOR_DARK_GRAY   end },
    { key = "GRAY_9",      label = "Gray 9",             color = function() return Blitbuffer.COLOR_GRAY_9      end },
    { key = "GRAY",        label = "Gray  (mid)",        color = function() return Blitbuffer.COLOR_GRAY        end },
    { key = "LIGHT_GRAY",  label = "Light gray",         color = function() return Blitbuffer.COLOR_LIGHT_GRAY  end },
}
local function getLineColor()
    local key = get("line_color")
    for _, entry in ipairs(LINE_COLOR_MAP) do
        if entry.key == key then return entry.color() end
    end
    return Blitbuffer.COLOR_GRAY_4  -- fallback
end

-- ── BIM cover-dims cache (filepath → {cw, ch} in thumbnail pixels) ────────────
-- Avoids repeated SQLite queries for the same book within a session.
local _bim_dims_cache = {}

-- ── per-item render cache ──────────────────────────────────────────────────────
-- Key: filepath .. "|" .. item_w .. "x" .. item_h
-- Value: {left_off, top_off, cover_w, cover_h, name, num_lines}
-- Populated on first render of each item; cleared on folder navigation.
-- Makes select-mode repaints and menu-behind-grid repaints essentially free.
local _item_cache = {}

local function itemCacheKey(filepath, item_w, item_h)
    return (filepath or "") .. "|" .. item_w .. "x" .. item_h
end

-- Call this whenever settings change that affect geometry or text
local function invalidateItemCache()
    _item_cache = {}
    _bim_dims_cache = {}
end

-- ── BookInfoManager lazy grab ─────────────────────────────────────────────────
local _BookInfoManager
local function getBIM()
    if not _BookInfoManager then
        local ok, bim = pcall(require, "bookinfomanager")
        if ok and bim then
            _BookInfoManager = bim
        else
            local ok2, MosaicMenu = pcall(require, "mosaicmenu")
            if ok2 and MosaicMenu then
                local MM = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
                if MM and MM.update then
                    _BookInfoManager = userpatch.getUpValue(MM.update, "BookInfoManager")
                end
            end
        end
    end
    return _BookInfoManager
end

-- ── label text resolver ───────────────────────────────────────────────────────
local function getLabelText(self)
    local mode = get("text_mode")
    local raw  = self.filepath or self.text or ""

    if mode == "filename" then
        local _, filename = util.splitFilePathName(raw)
        return util.splitFileNameSuffix(filename)
    end

    local bim = getBIM()
    if bim then
        local ok, bookinfo = pcall(function()
            return bim:getBookInfo(raw, false)
        end)
        if ok and bookinfo then
            local title  = (bookinfo.title  and bookinfo.title  ~= "") and bookinfo.title  or nil
            local author = (bookinfo.authors and bookinfo.authors ~= "") and bookinfo.authors or nil
            if mode == "title" then
                return title or (function()
                    local _, fn = util.splitFilePathName(raw)
                    return util.splitFileNameSuffix(fn)
                end)()
            elseif mode == "author_title" then
                if author and title then return author .. " – " .. title
                elseif title        then return title
                elseif author       then return author end
            elseif mode == "title_author" then
                if title and author then return title .. " – " .. author
                elseif title        then return title
                elseif author       then return author end
            end
        end
    end

    local _, filename = util.splitFilePathName(raw)
    return util.splitFileNameSuffix(filename)
end

-- ── page count → line count ───────────────────────────────────────────────────
local _lines_cache = {}

-- ── reading-progress cache (filepath → {percent, is_finished}) ────────────────
local _progress_cache = {}

local function getPageCount(filepath)
    if not filepath then return nil end

    -- highest priority: explicit page count in filename e.g. "Book Title p234.epub"
    local fname = filepath:match("([^/]+)$") or ""
    local p = fname:match("[Pp](%d+)%.")
    if p then return tonumber(p) end

    local DocSettings = require("docsettings")
    local ok, docinfo = pcall(DocSettings.open, DocSettings, filepath)
    if ok and docinfo and docinfo.data then
        local pages = nil
        if docinfo.data.doc_pages and docinfo.data.doc_pages > 0 then
            pages = docinfo.data.doc_pages
        elseif docinfo.data.stats and docinfo.data.stats.pages and docinfo.data.stats.pages ~= 0 then
            pages = docinfo.data.stats.pages
        end
        docinfo:close()
        if pages then return pages end
    end

    local bim = getBIM()
    if bim then
        local ok2, bookinfo = pcall(function() return bim:getBookInfo(filepath, false) end)
        if ok2 and bookinfo then
            if bookinfo.nb_pages and bookinfo.nb_pages > 0 then return bookinfo.nb_pages end
        end
    end

    local ext = filepath:match("%.(%w+)$")
    if ext then ext = ext:lower() end
    local f = io.open(filepath, "rb")
    if f then
        local size = f:seek("end")
        f:close()
        if size and size > 0 then
            if ext == "epub" then
                return math.max(1, math.floor(size / get("epub_bytes_per_page"))), false
            elseif ext == "cbz" or ext == "cbr" then
                return math.max(1, math.floor(size / (get("cbz_kb_per_page") * 1024))), false
            elseif ext == "pdf" then
                return math.max(1, math.floor(size / (get("pdf_kb_per_page") * 1024))), false
            end
        end
    end

    return nil
end

local function getNumLines(filepath)
    if not filepath then return 2 end
    if _lines_cache[filepath] then return _lines_cache[filepath] end

    local pages = getPageCount(filepath)
    if not pages then return 4 end

    local max_lines = 10
    local ranges = {
        get("page_range_2"),
        get("page_range_3"),
        get("page_range_4"),
        get("page_range_5"),
        get("page_range_6"),
        get("page_range_7"),
        get("page_range_8"),
        get("page_range_9"),
    }

    local n = max_lines
    for i = 1, max_lines - 1 do
        local tier = i + 1
        if get("lines_enabled_" .. tier) == false then goto continue end
        if pages <= (ranges[i] or math.huge) then
            n = tier
            break
        end
        ::continue::
    end
    while n > 2 and get("lines_enabled_" .. n) == false do
        n = n - 1
    end

    _lines_cache[filepath] = n
    return n
end

-- ── reading-progress resolver ─────────────────────────────────────────────────
-- Returns (percent_int_or_nil, is_finished_bool).
-- percent is 0-100; nil means the book has never been opened / no recorded progress.
-- 0 means opened and percent_finished is present but rounds to 0.
local function getReadingProgress(filepath)
    if not filepath then return nil, false end
    if _progress_cache[filepath] then
        return _progress_cache[filepath].percent, _progress_cache[filepath].is_finished
    end

    local DocSettings = require("docsettings")
    local ok, docinfo = pcall(DocSettings.open, DocSettings, filepath)
    if not ok or not docinfo or not docinfo.data then
        _progress_cache[filepath] = { percent = nil, is_finished = false }
        return nil, false
    end

    -- finished status (set when user marks book complete)
    local is_finished = false
    if docinfo.data.summary and docinfo.data.summary.status then
        local s = docinfo.data.summary.status
        is_finished = (s == "complete" or s == "finished")
    end

    -- percentage (stored as 0.0-1.0 float by KOReader)
    -- Only set if percent_finished key actually exists — means book was genuinely opened
    local percent = nil
    local pf = docinfo.data.percent_finished
    if type(pf) == "number" then
        -- pf exists: book has been opened; clamp to 0-100
        percent = math.max(0, math.min(100, math.floor(pf * 100 + 0.5)))
    end

    if docinfo.close then pcall(function() docinfo:close() end) end

    _progress_cache[filepath] = { percent = percent, is_finished = is_finished }
    return percent, is_finished
end

-- ── progress badge painter ────────────────────────────────────────────────────
-- White filled rectangle with rounded top-left corner, anchored at the
-- bottom-right corner of the cover flush against the inside of the outline.
-- The outline's right/bottom bars and corner arc form the right/bottom border.
-- Black border on top and left edges only.
--
-- outline_r – same corner radius used by the outline arc.  We redraw the arc
--             on top of the fill so the corner is never overwritten.
local function paintProgressBadge(bb, cover_x, cover_y, cover_w, cover_h,
                                   percent, is_finished, ot, outline_r)
    -- nil percent means book was never opened / has no saved reading state.
    -- In that case the Real Books badge should say NEW instead of 0%.
    local is_new_or_unread = (percent == nil and not is_finished)

    ot        = ot        or 2
    outline_r = outline_r or ot

    -- Badge dimensions: Ry controls height, Rx controls width
    local Ry = math.max(16, math.floor(math.min(cover_w, cover_h) * 0.143))
    local Rx = math.floor(Ry * 1.375)

    -- Inner corner flush against the inside face of the outline
    local ax = cover_x + cover_w - 1 - ot
    local ay = cover_y + cover_h - 1 - ot

    -- Badge extents
    local bx = ax - Rx + 1
    local bt = ay - Ry + 1

    -- Badge rounded top-left corner radius
    local rc       = math.max(4, math.floor(math.min(Rx, Ry) * 0.30))
    local rc_inner = math.max(0, rc - ot)

    -- Outline corner arc geometry (same as outline code):
    --   cx_arc = cover_x + cover_w - outline_r
    --   cy_arc = cover_y + cover_h - 1 - outline_r  (cy_br in outline)
    local cx_arc  = cover_x + cover_w - outline_r
    local cy_arc  = cover_y + cover_h - 1 - outline_r
    local r_inner = math.max(0, outline_r - ot)
    local right_edge = cover_x + cover_w - 1

    -- ── 1. White fill ────────────────────────────────────────────────────────
    -- Clip LEFT only at the badge's rounded top-left corner.
    -- Go all the way to ax on the right; step 2 redraws the arc ring on top.
    for py = bt, ay do
        local xl = bx

        local dy_corner = (bt + rc) - py
        if dy_corner > 0 then
            local chord = math.floor(
                math.sqrt(math.max(0, rc * rc - dy_corner * dy_corner)) + 0.5)
            xl = bx + rc - chord
        end

        if ax >= xl then
            bb:paintRect(xl, py, ax - xl + 1, 1, Blitbuffer.COLOR_WHITE)
        end
    end

    -- ── 2. Redraw the outline corner arc on top of the fill ──────────────────
    -- Step 1 painted white over the arc ring pixels in the badge area; restore
    -- them so the corner arc looks exactly as the outline code drew it.
    for dy = 1, outline_r do
        local row_br = cy_arc + dy
        if row_br > ay then break end
        local outer_dx = math.floor(
            math.sqrt(math.max(0, outline_r * outline_r - dy * dy)) + 0.5)
        outer_dx = math.min(outer_dx, right_edge - cx_arc)
        local inner_dx = r_inner > 0
            and math.floor(math.sqrt(math.max(0, r_inner * r_inner - dy * dy)) + 0.5)
            or 0
        local ring_len = (cx_arc + outer_dx) - (cx_arc + inner_dx) + 1
        if ring_len > 0 then
            bb:paintRect(cx_arc + inner_dx, row_br, ring_len, 1, Blitbuffer.COLOR_BLACK)
        end
    end

    -- ── 3. Black border on the two free edges ────────────────────────────────
    local arc_cx = bx + rc
    local arc_cy = bt + rc

    -- top bar (straight part after the rounded corner)
    local top_len = ax - arc_cx + 1
    if top_len > 0 then
        bb:paintRect(arc_cx, bt, top_len, ot, Blitbuffer.COLOR_BLACK)
    end
    -- left bar
    local left_len = ay - arc_cy + 1
    if left_len > 0 then
        bb:paintRect(bx, arc_cy, ot, left_len, Blitbuffer.COLOR_BLACK)
    end
    -- rounded top-left arc ring (upper-left quadrant, no erase needed)
    for dy = 0, rc do
        local outer_dx = math.floor(math.sqrt(math.max(0, rc * rc - dy * dy)) + 0.5)
        local inner_dx = rc_inner > 0
            and math.floor(math.sqrt(math.max(0, rc_inner * rc_inner - dy * dy)) + 0.5)
            or 0
        local ring_len = outer_dx - inner_dx
        local row = arc_cy - dy
        if ring_len > 0 and row >= bt then
            bb:paintRect(arc_cx - outer_dx, row, ring_len, 1, Blitbuffer.COLOR_BLACK)
        end
    end

    -- ── 4. Black text / checkmark / NEW label ────────────────────────────────
    local text_str
    if is_finished then
        text_str = "\xe2\x9c\x93"
    elseif is_new_or_unread then
        text_str = "NEW"
    else
        text_str = tostring(percent) .. "%"
    end

    -- usable interior: left border (bx+ot) to right outline inside edge (ax-ot), top/bottom same
    local text_left  = bx + ot + 1
    local text_right = ax - ot
    local inner_w = text_right - text_left
    local inner_h = ay - (bt + ot) - ot

    -- start from a DPI-normalised size, then shrink until text fits the interior
    local badge_fs = math.max(6, math.floor(math.min(Rx, Ry) * 0.52 / getDPIScale()))
    local tw, ts
    for _ = 1, 10 do
        tw = TextWidget:new{
            text    = text_str,
            face    = Font:getFace("cfont", badge_fs),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        ts = tw:getSize()
        if ts.w <= inner_w and ts.h <= inner_h then break end
        tw:free()
        badge_fs = math.max(6, badge_fs - 1)
    end

    -- center text within the explicit left/right bounds
    local usable_cx = math.floor((text_left + text_right) / 2)
    -- center text vertically, shifted ~15% down from true center
    local badge_h = ay - bt
    local badge_mid_y = math.floor(bt + badge_h * 0.58)
    local tx = math.max(text_left, usable_cx - math.floor(ts.w / 2))
    local ty = badge_mid_y - math.floor(ts.h / 2)
    tw:paintTo(bb, tx, ty)
    tw:free()
end

-- ── rounded-end line painter ──────────────────────────────────────────────────
local function paintRoundedLine(bb, x, y, len, thick, color)
    if len <= 0 or thick <= 0 then return end
    local r = math.floor(thick / 2)
    -- rectangular body between the two cap centres
    local body_x = x + r
    local body_len = len - 2 * r
    if body_len > 0 then
        bb:paintRect(body_x, y, body_len, thick, color)
    end
    -- filled-circle caps via scanline (avoids any external dependency)
    for dr = -r, r do
        local half_chord = math.floor(math.sqrt(math.max(0, r * r - dr * dr)) + 0.5)
        if half_chord > 0 then
            local cy = y + r + dr
            -- left cap
            bb:paintRect(x + r - half_chord, cy, half_chord, 1, color)
            -- right cap
            bb:paintRect(x + len - r, cy, half_chord, 1, color)
        end
    end
end

-- ── blitbuffer edge scan ──────────────────────────────────────────────────────
-- Only left_off and top_off are used by the caller; right/bottom are not needed.
local function findCoverEdges(bb, cell_x, cell_w, cell_y, cell_h)
    local left_offset = 0
    local top_offset  = 0

    local scan_rows = math.floor(cell_h * 0.25)
    for row = 0, scan_rows do
        local sy = cell_y + row
        for col = 0, cell_w - 1 do
            local c = bb:getPixel(cell_x + col, sy)
            if c and c:getR() < 250 then
                if col > left_offset then left_offset = col end
                break
            end
        end
    end

    local mid_x = cell_x + math.floor(cell_w / 2)
    for row = 0, cell_h - 1 do
        local c = bb:getPixel(mid_x, cell_y + row)
        if c and c:getR() < 250 then top_offset = row; break end
    end

    return left_offset, 0, top_offset, 0
end

-- ── cover shape transform ─────────────────────────────────────────────────────
-- Applies aspect-ratio enforcement and scale-% in a SINGLE scale operation.
-- When both are active the final pixel dimensions are computed first, then
-- one Blitbuffer scale() call produces the result directly — half the work
-- compared to doing the two steps sequentially.
local function applyCoverTransform(bb, x, y, item_w, item_h, cover_x, cover_y, cover_w, cover_h, left_reserve)
    left_reserve = left_reserve or 0
    local scale_pct   = get("cover_scale_pct")
    local asp_enabled = get("aspect_enabled")

    -- fast-path: nothing to do
    if scale_pct == 100 and not asp_enabled then
        return cover_x, cover_y, cover_w, cover_h
    end

    local cx, cy, cw, ch = cover_x, cover_y, cover_w, cover_h

    -- ── compute AR target box (geometry only, no pixels yet) ─────────────────
    local tgt_x, tgt_y, tgt_w, tgt_h
    if asp_enabled and cw > 0 and ch > 0 then
        local ratio_w = get("aspect_ratio_w")
        local ratio_h = get("aspect_ratio_h")

        local tgt_h_from_w = math.floor(item_w * ratio_h / ratio_w)
        if tgt_h_from_w <= item_h then
            tgt_w = item_w
            tgt_h = math.max(1, tgt_h_from_w)
        else
            tgt_h = item_h
            tgt_w = math.max(1, math.floor(item_h * ratio_w / ratio_h))
        end

        tgt_x = x + math.floor((item_w - tgt_w) / 2)
        tgt_y = y + math.floor((item_h - tgt_h) / 2)
    else
        -- no AR: treat the current cover box as the target
        tgt_x = cx
        tgt_y = cy
        tgt_w = cw
        tgt_h = ch
    end

    -- ── compute AR image dimensions (always stretch) ──────────────────────────
    local img_w = math.max(1, tgt_w)
    local img_h = math.max(1, tgt_h)

    -- ── apply scale% to the AR image dimensions ───────────────────────────────
    -- Compute the usable horizontal space accounting for spine reserve.
    -- The reserve is relative to the tgt box, not the full cell.
    local res_in_tgt = 0
    if scale_pct ~= 100 then
        res_in_tgt = math.max(0, (x + left_reserve) - tgt_x)
    end
    local usable_w = math.max(1, tgt_w - res_in_tgt)

    local final_w, final_h
    if scale_pct ~= 100 then
        final_w = math.max(1, math.floor(math.min(img_w, usable_w) * scale_pct / 100))
        final_h = math.max(1, math.floor(img_h * scale_pct / 100))
    else
        final_w = img_w
        final_h = img_h
    end

    -- ── compute final destination position ────────────────────────────────────
    local usable_x = tgt_x + res_in_tgt
    local dst_x, dst_y
    if scale_pct ~= 100 then
        dst_x = usable_x + math.floor((usable_w - final_w) / 2)
        dst_y = tgt_y    + math.floor((tgt_h    - final_h) / 2)
    else
        dst_x = tgt_x + math.floor((tgt_w - final_w) / 2)
        dst_y = tgt_y + math.floor((tgt_h - final_h) / 2)
    end

    -- ── early-out: no actual change ───────────────────────────────────────────
    if final_w == cw and final_h == ch and dst_x == cx and dst_y == cy then
        return cx, cy, cw, ch
    end

    -- ── single scale from original source to final dimensions ─────────────────
    local src = Blitbuffer.new(cw, ch, bb:getType())
    src:blitFrom(bb, 0, 0, cx, cy, cw, ch)
    local scaled = src:scale(final_w, final_h)
    src:free()

    bb:paintRect(x, y, item_w, item_h, Blitbuffer.COLOR_WHITE)

    local src_x, src_y = 0, 0
    local bw, bh = final_w, final_h

    if dst_x < x then
        src_x = x - dst_x; bw = bw - (x - dst_x); dst_x = x
    end
    if dst_y < y then
        src_y = y - dst_y; bh = bh - (y - dst_y); dst_y = y
    end
    bw = math.min(bw, x + item_w - dst_x)
    bh = math.min(bh, y + item_h - dst_y)
    bw = math.max(0, bw)
    bh = math.max(0, bh)

    if bw > 0 and bh > 0 then
        bb:blitFrom(scaled, dst_x, dst_y, src_x, src_y, bw, bh)
    end
    scaled:free()

    return dst_x, dst_y, bw, bh
end

-- ── core patch ────────────────────────────────────────────────────────────────
local function patchMosaicMenuItem(MosaicMenuItem)
    if MosaicMenuItem._vlabel_patched then return end
    MosaicMenuItem._vlabel_patched = true

    local orig_paintTo = MosaicMenuItem.paintTo

    MosaicMenuItem.paintTo = function(self, bb, x, y)
        orig_paintTo(self, bb, x, y)

        if self.is_directory then return end

        local item_w = self.dimen and self.dimen.w or self.width  or 0
        local item_h = self.dimen and self.dimen.h or self.height or 0
        if item_w == 0 or item_h == 0 then return end

        local filepath = self.filepath or self.text
        local ckey = itemCacheKey(filepath, item_w, item_h)
        local cached = _item_cache[ckey]

        local cover_x, cover_y, cover_w, cover_h, name, num_lines

        if cached then
            -- fast path: all geometry and text already known, skip all lookups
            cover_x   = x + cached.left_off
            cover_y   = y + cached.top_off
            cover_w   = cached.cover_w
            cover_h   = cached.cover_h
            name      = cached.name
            num_lines = cached.num_lines
        else
            -- slow path: compute everything and populate the cache

            -- detect cover position within cell
            local left_off, right_off, top_off, bottom_off = findCoverEdges(bb, x, item_w, y, item_h)
            cover_y = y + top_off
            cover_h = item_h - top_off - bottom_off
            cover_x = x + left_off
            cover_w = item_w - left_off - right_off

            -- BIM override using cached dims where possible
            do
                local bim_cw_raw, bim_ch_raw
                if _bim_dims_cache[filepath] then
                    bim_cw_raw = _bim_dims_cache[filepath].cw
                    bim_ch_raw = _bim_dims_cache[filepath].ch
                else
                    local bim = getBIM()
                    if bim and filepath then
                        local ok, bookinfo = pcall(function() return bim:getBookInfo(filepath, false) end)
                        if ok and bookinfo and bookinfo.cover_w and bookinfo.cover_h
                                and bookinfo.cover_w > 0 and bookinfo.cover_h > 0 then
                            bim_cw_raw = bookinfo.cover_w
                            bim_ch_raw = bookinfo.cover_h
                            _bim_dims_cache[filepath] = { cw = bim_cw_raw, ch = bim_ch_raw }
                        end
                    end
                end
                if bim_cw_raw and bim_ch_raw then
                    local scale = math.min(item_w / bim_cw_raw, item_h / bim_ch_raw)
                    local bim_cw = math.floor(bim_cw_raw * scale)
                    local bim_ch = math.floor(bim_ch_raw * scale)
                    if bim_cw > 4 and bim_ch > 4 then
                        cover_x = x + math.floor((item_w - bim_cw) / 2)
                        cover_y = y + math.floor((item_h - bim_ch) / 2)
                        cover_w = bim_cw
                        cover_h = bim_ch
                    end
                end
            end

            name      = getLabelText(self)
            num_lines = getNumLines(filepath)

            -- store offsets (not absolute coords) so cache is position-independent
            _item_cache[ckey] = {
                left_off  = cover_x - x,
                top_off   = cover_y - y,
                cover_w   = cover_w,
                cover_h   = cover_h,
                name      = name,
                num_lines = num_lines,
            }
        end

        -- ── cover shape: runs regardless of spine-label enabled state ─────────
        -- strip_w is computed early so applyCoverTransform can reserve that space
        -- on the left before sizing the cover — prevents right-edge clipping.
        local strip_w    = get("enabled") and getStripW(item_w) or 0
        local left_reserve = strip_w > 0 and (strip_w + 1) or 0
        if cover_w > 0 and cover_h > 0 then
            cover_x, cover_y, cover_w, cover_h = applyCoverTransform(
                bb, x, y, item_w, item_h, cover_x, cover_y, cover_w, cover_h, left_reserve)
        end

        -- ── replace KOReader's 1px outline with our own (page_thickness wide) ──
        -- Always runs: covers 100% scale, aspect ratio changes, and reduced scale.
        -- Left side intentionally omitted — the spine label sits there.
        -- cover_x/y/w/h boundary includes KOReader's 1px outline pixel, so we
        -- draw our outline overlapping inward from that boundary — no gap.
        if cover_w > 0 and cover_h > 0 then
            local ot = get("page_thickness")
            local r = math.min(ot * 4, math.floor(math.min(cover_w, cover_h) / 4))
            r = math.max(r, ot)
            local r_inner = r - ot  -- inner radius

            -- Pixel geometry (all inclusive):
            --   right_edge  = cover_x + cover_w - 1
            --   bottom_edge = cover_y + cover_h - 1
            --
            -- Arc centre x: cx = cover_x + cover_w - r
            --   → at dy=0: outer_dx = r, so rightmost pixel = cx + r - 1 = right_edge  ✓
            --
            -- Arc centre y for top-right:    cy_tr = cover_y + r
            --   → at dy=r: row = cy_tr - r = cover_y  ✓  (joins top bar)
            --   → right bar top  = cy_tr (first row below the arc's topmost point)
            --
            -- Arc centre y for bottom-right: cy_br = cover_y + cover_h - 1 - r
            --   → at dy=r: row = cy_br + r = cover_y + cover_h - 1 = bottom_edge  ✓
            --   → right bar bottom ends at cy_br (last row above arc's bottommost point)

            local cx    = cover_x + cover_w - r
            local cy_tr = cover_y + r
            local cy_br = cover_y + cover_h - 1 - r
            local right_edge  = cover_x + cover_w - 1
            local bottom_edge = cover_y + cover_h - 1

            -- Straight bars:
            -- top bar: cover_y .. cover_y+ot-1, from cover_x to cx-1
            bb:paintRect(cover_x, cover_y, cx - cover_x, ot, Blitbuffer.COLOR_BLACK)
            -- bottom bar: bottom_edge-ot+1 .. bottom_edge, from cover_x to cx-1
            bb:paintRect(cover_x, bottom_edge - ot + 1, cx - cover_x, ot, Blitbuffer.COLOR_BLACK)
            -- right bar: x = right_edge-ot+1 .. right_edge, from cy_tr to cy_br (inclusive)
            if cy_br >= cy_tr then
                bb:paintRect(right_edge - ot + 1, cy_tr, ot, cy_br - cy_tr + 1, Blitbuffer.COLOR_BLACK)
            end

            -- Rounded corners: for each dy 0..r, paint the arc ring row.
            -- dy=0 is the centre row (horizontal tangent), dy=r is the top/bottom tangent row.
            for dy = 0, r do
                local outer_dx = math.floor(math.sqrt(math.max(0, r * r - dy * dy)) + 0.5)
                local inner_dx = r_inner > 0
                    and math.floor(math.sqrt(math.max(0, r_inner * r_inner - dy * dy)) + 0.5)
                    or 0

                -- clamp outer so we never draw past right_edge
                outer_dx = math.min(outer_dx, right_edge - cx)

                local ring_start = cx + inner_dx
                local ring_end   = cx + outer_dx
                local ring_len   = ring_end - ring_start + 1

                -- erase the square corner region to the right of the arc
                local erase_start = ring_end + 1
                local erase_len   = right_edge - erase_start + 1

                -- top-right corner (rows from cy_tr upward to cover_y)
                local row_tr = cy_tr - dy
                if ring_len > 0 then
                    bb:paintRect(ring_start, row_tr, ring_len, 1, Blitbuffer.COLOR_BLACK)
                end
                if erase_len > 0 then
                    bb:paintRect(erase_start, row_tr, erase_len, 1, Blitbuffer.COLOR_WHITE)
                end

                -- bottom-right corner (rows from cy_br downward to bottom_edge)
                -- skip dy=0 to avoid repainting the shared centre row
                if dy > 0 then
                    local row_br = cy_br + dy
                    if ring_len > 0 then
                        bb:paintRect(ring_start, row_br, ring_len, 1, Blitbuffer.COLOR_BLACK)
                    end
                    if erase_len > 0 then
                        bb:paintRect(erase_start, row_br, erase_len, 1, Blitbuffer.COLOR_WHITE)
                    end
                end
            end
        end

        -- ── progress badge: rounded-rect corner label ────────────────────────
        -- Always paints when enabled, covering KOReader's dog ear.
        -- Unread/new books show NEW; finished books show ✓; opened books show percent.
        -- Native progress bar renders freely beneath — no suppression needed.
        if get("progress_badge_enabled") and cover_w > 0 and cover_h > 0 then
            local prog_pct, prog_done = getReadingProgress(filepath)
            local badge_ot = get("page_thickness")
            -- recompute outline corner radius (same formula as the outline block above)
            local badge_r = math.max(badge_ot,
                math.min(badge_ot * 4, math.floor(math.min(cover_w, cover_h) / 4)))
            paintProgressBadge(bb, cover_x, cover_y, cover_w, cover_h,
                               prog_pct, prog_done, badge_ot, badge_r)
        end

        -- ── spine label: gated by main enabled flag ───────────────────────────
        if not get("enabled") then return end
        if cover_w <= 0 or cover_h <= 0 then return end

        if not name or name == "" then return end

        -- strip_w already computed above; fetch remaining per-frame locals
        local pad   = get("padding")
        local fs    = get("font_size")
        local alpha = get("alpha")

        -- label sits flush against cover left edge; no overlap guaranteed by applyCoverTransform
        local label_x = math.max(x, cover_x - strip_w)

        -- angle cut depths (defined early so l_total can reference cut_h_top)
        local cut_h_bot = math.floor(strip_w * 0.5774)  -- tan(30°)

        -- dynamic line count based on page count
        local page_thick = get("page_thickness")
        local page_gap   = get("page_spacing")
        local line_step  = page_thick + page_gap
        local l_total    = num_lines * line_step
        local label_y    = cover_y - l_total
        local scale_pct  = get("cover_scale_pct")
        local label_h    = cover_h + l_total + (scale_pct < 100 and 1 or 0) - 1

        -- top angle always spans exactly l_total so right corner anchors to cover_y
        local cut_h_top  = l_total

        -- text max_width excludes the angled cut areas so text stays within visible box
        local text_max_w = label_h - cut_h_top - cut_h_bot - 2 * pad

        -- resolve font file from module-level map
        local face_entry = FONT_MAP[get("font_face")] or FONT_MAP["NotoSerif"]
        local font_file  = get("font_bold") and face_entry.bold or face_entry.regular

        -- build label widget sized to extended height
        local text_widget = TextWidget:new{
            text                  = name,
            face                  = Font:getFace(font_file, fs),
            fgcolor               = Blitbuffer.COLOR_WHITE,
            max_width             = math.max(1, text_max_w),
            truncate_with_ellipsis = false,
        }
        -- rotate and blit back with angled top/bottom ends
        local angle   = (get("direction") == "down") and 270 or 90

        -- sample the full cover strip (cover_h tall) then scale-stretch to label_h
        local tmp = Blitbuffer.new(label_h, strip_w, bb:getType())
        local src = Blitbuffer.new(strip_w, cover_h, bb:getType())
        src:blitFrom(bb, 0, 0, cover_x, cover_y, strip_w, cover_h)
        -- stretch src (strip_w × cover_h) → stretched (strip_w × label_h)
        local stretched = src:scale(strip_w, label_h)
        src:free()
        -- rotate cover 180° extra by using opposite angle then flip
        local img_angle = (angle == 90) and 270 or 90
        local src_rot = stretched:rotatedCopy(img_angle)
        stretched:free()
        tmp:blitFrom(src_rot, 0, 0, 0, 0, label_h, strip_w)
        src_rot:free()

        -- blend bg color at alpha opacity onto cover pixels
        local dark_mode = get("dark_mode")
        local bg_r, bg_g, bg_b = dark_mode and 0 or 255, dark_mode and 0 or 255, dark_mode and 0 or 255
        local blend_alpha = math.floor(alpha * 255)
        tmp:blendRectRGB32(0, 0, label_h, strip_w, Blitbuffer.ColorRGB32(bg_r, bg_g, bg_b, blend_alpha))

        -- paint text at 100% opacity on top
        local text_color = dark_mode and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        text_widget.fgcolor = text_color
        local text_only = CenterContainer:new{
            dimen = Geom:new{ w = label_h, h = strip_w },
            text_widget,
        }
        text_only:paintTo(tmp, 0, 0)
        text_only:free()
        local shear = -(get("text_shear") / 100)
        local sheared = Blitbuffer.new(label_h, strip_w, bb:getType())
        for row = 0, strip_w - 1 do
            local offset = math.floor((row - strip_w / 2) * shear)
            local src_x = math.max(0, -offset)
            local dst_x = math.max(0, offset)
            local w = label_h - math.abs(offset)
            if w > 0 then
                sheared:blitFrom(tmp, dst_x, row, src_x, row, w, 1)
            end
        end
        tmp:free()
        tmp = sheared

        local rotated = tmp:rotatedCopy(angle)
        tmp:free()

        -- save background strip before we draw (so we can restore corners)
        local bg = Blitbuffer.new(strip_w, label_h, bb:getType())
        bg:blitFrom(bb, 0, 0, label_x, label_y, strip_w, label_h)

        -- blit the full rotated rectangle
        bb:blitFrom(rotated, label_x, label_y, 0, 0, strip_w, label_h)
        rotated:free()

        for row = 0, math.max(cut_h_top, cut_h_bot) - 1 do
            local brow = label_h - (scale_pct < 100 and 0 or 1) - row
            if row < cut_h_top then
                local t = (cut_h_top - row) / cut_h_top
                local trim = math.floor(t ^ 0.6 * strip_w)
                if trim > 0 then
                    bb:blitFrom(bg, label_x + strip_w - trim, label_y + row, strip_w - trim, row, trim, 1)
                end
            end
            if row < cut_h_bot then
                local t = (cut_h_bot - row) / cut_h_bot
                local trim = math.floor((1 - (1 - t) ^ 0.6) * strip_w)
                if trim > 0 then
                    bb:paintRect(label_x, label_y + brow, trim, 1, Blitbuffer.COLOR_WHITE)
                end
            end
        end
        bg:free()

        -- draw lines above cover: all lines same length, anchored at spine angle edge
        do
            local color    = getLineColor()
            local len_pct  = get("page_line_length_pct")
            -- fixed line length based on cover width percentage
            local fixed_len = math.max(1, math.floor(cover_w * len_pct / 100))

            for i = 1, num_lines do
                local by = cover_y - page_thick - page_gap - (i - 1) * line_step
                -- compute where the spine angle ends for this row
                local row_in_cut = by - label_y
                local line_start
                if row_in_cut >= 0 and row_in_cut < cut_h_top then
                    local t = (cut_h_top - row_in_cut) / cut_h_top
                    local trim = math.floor(t ^ 0.6 * strip_w)
                    line_start = label_x + strip_w - trim
                else
                    line_start = label_x + strip_w
                end
                -- all lines same fixed length; topmost gets +1px so it visually caps the stack
                local this_len = (i == num_lines) and (fixed_len + 1) or fixed_len
                local draw_len = math.min(this_len, cover_x + cover_w - line_start)
                local line_color = (i == num_lines) and Blitbuffer.COLOR_GRAY_2 or color
                if draw_len > 0 then
                    paintRoundedLine(bb, line_start, by, draw_len, page_thick, line_color)
                end
            end
        -- [merged] Visual Overhaul series badge, painted after Real Books so it stays visible.
        if self.has_series_badge and self.series_badge then
            local inset = 2
            self.series_badge:paintTo(bb, cover_x + inset, cover_y + inset)
        end
        end
    end
end

-- ── menu ──────────────────────────────────────────────────────────────────────
local orig_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
function FileManagerMenu:setUpdateItemTable()
    if type(FileManagerMenuOrder.filemanager_settings) == "table" then
        local found = false
        for _, k in ipairs(FileManagerMenuOrder.filemanager_settings) do
            if k == "ai_slop_settings" then found = true; break end
        end
        if not found then
            table.insert(FileManagerMenuOrder.filemanager_settings, 1, "ai_slop_settings")
        end
    end

    if not self.menu_items.ai_slop_settings then
        self.menu_items.ai_slop_settings = {
            text = "AI Slop Settings",
            sub_item_table = {},
        }
    end

    local already = false
    for _, item in ipairs(self.menu_items.ai_slop_settings.sub_item_table) do
        if item._mosaic_vlabel_entry then already = true; break end
    end
    if not already then
        table.insert(self.menu_items.ai_slop_settings.sub_item_table, {
            _mosaic_vlabel_entry = true,
            text = "Real Books",
            sub_item_table_func = function()
                return {
                -- ── master toggle ──────────────────────────────────────────
                {
                    text_func = function()
                        return get("enabled") and "Spine label: enabled" or "Spine label: disabled"
                    end,
                    checked_func = function() return get("enabled") end,
                    callback = function(touchmenu_instance)
                        set("enabled", not get("enabled"))
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                        local fc = require("ui/widget/filechooser")
                        if fc.instance then fc.instance:updateItems() end
                    end,
                },
                -- ── progress badge toggle ───────────────────────────────────
                {
                    text_func = function()
                        return "Progress badge"
                    end,
                    checked_func = function() return get("progress_badge_enabled") end,
                    callback = function(touchmenu_instance)
                        set("progress_badge_enabled", not get("progress_badge_enabled"))
                        _progress_cache = {}
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                        local fc = require("ui/widget/filechooser")
                        if fc.instance then fc.instance:updateItems() end
                    end,
                },
                -- ── label text ─────────────────────────────────────────────
                {
                    text_func = function()
                        local v = get("spine_width_pct")
                        if v == 100 then return "Spine width: 100% (default)"
                        else return ("Spine width: %d%%"):format(v) end
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local SpinWidget = require("ui/widget/spinwidget")
                        local UIManager  = require("ui/uimanager")
                        UIManager:show(SpinWidget:new{
                            title_text          = "Spine width",
                            value               = get("spine_width_pct"),
                            value_min           = 100,
                            value_max           = 200,
                            value_step          = 5,
                            keep_shown_on_apply = true,
                            value_text_func     = function(v) return v .. "%" end,
                            callback = function(spin)
                                set("spine_width_pct", spin.value)
                                _strip_w_cache = nil
                                invalidateItemCache()
                                local fc = require("ui/widget/filechooser")
                                if fc.instance then fc.instance:updateItems() end
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        })
                    end,
                },
                {
                    text = "Label text",
                    sub_item_table = {
                        {
                            text = "Filename",
                            checked_func = function() return get("text_mode") == "filename" end,
                            callback = function()
                                set("text_mode", "filename")
                                local fc = require("ui/widget/filechooser")
                                if fc.instance then fc.instance:updateItems() end
                            end,
                        },
                        {
                            text = "Title",
                            checked_func = function() return get("text_mode") == "title" end,
                            callback = function()
                                set("text_mode", "title")
                                local fc = require("ui/widget/filechooser")
                                if fc.instance then fc.instance:updateItems() end
                            end,
                        },
                        {
                            text = "Author – Title",
                            checked_func = function() return get("text_mode") == "author_title" end,
                            callback = function()
                                set("text_mode", "author_title")
                                local fc = require("ui/widget/filechooser")
                                if fc.instance then fc.instance:updateItems() end
                            end,
                        },
                        {
                            text = "Title – Author",
                            checked_func = function() return get("text_mode") == "title_author" end,
                            callback = function()
                                set("text_mode", "title_author")
                                local fc = require("ui/widget/filechooser")
                                if fc.instance then fc.instance:updateItems() end
                            end,
                        },
                        {
                            text_func = function()
                                return get("direction") == "up" and "Text direction: Bottom to top" or "Text direction: Top to bottom"
                            end,
                            callback = function(touchmenu_instance)
                                set("direction", get("direction") == "up" and "down" or "up")
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                                local fc = require("ui/widget/filechooser")
                                if fc.instance then fc.instance:updateItems() end
                            end,
                        },
                        {
                            text_func = function()
                                return get("dark_mode") and "Text style: White on black" or "Text style: Black on white"
                            end,
                            callback = function(touchmenu_instance)
                                set("dark_mode", not get("dark_mode"))
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                                local fc = require("ui/widget/filechooser")
                                if fc.instance then fc.instance:updateItems() end
                            end,
                        },
                        {
                            text_func = function()
                                local v = get("alpha")
                                return ("Label opacity: %d%%"):format(math.floor(v * 100))
                            end,
                            keep_menu_open = true,
                            callback = function(touchmenu_instance)
                                local SpinWidget = require("ui/widget/spinwidget")
                                local UIManager  = require("ui/uimanager")
                                UIManager:show(SpinWidget:new{
                                    title_text          = "Label opacity",
                                    value               = math.floor(get("alpha") * 100),
                                    value_min           = 0,
                                    value_max           = 100,
                                    value_step          = 5,
                                    default_value       = math.floor(DEFAULTS.alpha * 100),
                                    keep_shown_on_apply = true,
                                    callback = function(spin)
                                        set("alpha", spin.value / 100)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                        if touchmenu_instance then touchmenu_instance:updateItems() end
                                    end,
                                })
                            end,
                        },
                        {
                            text = "Font face",
                            sub_item_table = {
                                {
                                    text = "Noto Serif Italic",
                                    checked_func = function() return get("font_face") == "NotoSerif" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSerif") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Serif Bold Italic",
                                    checked_func = function() return get("font_face") == "NotoSerif" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSerif") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Serif Regular",
                                    checked_func = function() return get("font_face") == "NotoSerifRegular" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSerifRegular") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Serif Bold",
                                    checked_func = function() return get("font_face") == "NotoSerifRegular" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSerifRegular") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Italic",
                                    checked_func = function() return get("font_face") == "NotoSans" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSans") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Bold Italic",
                                    checked_func = function() return get("font_face") == "NotoSans" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSans") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Regular",
                                    checked_func = function() return get("font_face") == "NotoSansRegular" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansRegular") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Bold",
                                    checked_func = function() return get("font_face") == "NotoSansRegular" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansRegular") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Free Serif",
                                    checked_func = function() return get("font_face") == "FreeSerif" end,
                                    callback = function()
                                        set("font_face", "FreeSerif")
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Free Sans",
                                    checked_func = function() return get("font_face") == "FreeSans" end,
                                    callback = function()
                                        set("font_face", "FreeSans")
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Droid Sans Mono",
                                    checked_func = function() return get("font_face") == "DroidSansMono" end,
                                    callback = function()
                                        set("font_face", "DroidSansMono")
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Naskh Arabic Regular",
                                    checked_func = function() return get("font_face") == "NotoNaskhArabic" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoNaskhArabic") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Naskh Arabic Bold",
                                    checked_func = function() return get("font_face") == "NotoNaskhArabic" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoNaskhArabic") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Arabic UI Regular",
                                    checked_func = function() return get("font_face") == "NotoSansArabicUI" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansArabicUI") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Arabic UI Bold",
                                    checked_func = function() return get("font_face") == "NotoSansArabicUI" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansArabicUI") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Bengali UI Regular",
                                    checked_func = function() return get("font_face") == "NotoSansBengaliUI" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansBengaliUI") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Bengali UI Bold",
                                    checked_func = function() return get("font_face") == "NotoSansBengaliUI" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansBengaliUI") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans CJK SC",
                                    checked_func = function() return get("font_face") == "NotoSansCJKsc" end,
                                    callback = function()
                                        set("font_face", "NotoSansCJKsc")
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Devanagari UI Regular",
                                    checked_func = function() return get("font_face") == "NotoSansDevanagariUI" and not get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansDevanagariUI") set("font_bold", false)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Noto Sans Devanagari UI Bold",
                                    checked_func = function() return get("font_face") == "NotoSansDevanagariUI" and get("font_bold") end,
                                    callback = function()
                                        set("font_face", "NotoSansDevanagariUI") set("font_bold", true)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                                {
                                    text = "Symbols",
                                    checked_func = function() return get("font_face") == "Symbols" end,
                                    callback = function()
                                        set("font_face", "Symbols")
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                    end,
                                },
                            },
                        },
                        {
                            text_func = function()
                                return ("Font size: %d"):format(get("font_size"))
                            end,
                            keep_menu_open = true,
                            callback = function(touchmenu_instance)
                                local SpinWidget = require("ui/widget/spinwidget")
                                local UIManager  = require("ui/uimanager")
                                UIManager:show(SpinWidget:new{
                                    title_text          = "Font size",
                                    value               = get("font_size"),
                                    value_min           = 10,
                                    value_max           = 24,
                                    value_step          = 1,
                                    default_value       = DEFAULTS.font_size,
                                    keep_shown_on_apply = true,
                                    callback = function(spin)
                                        set("font_size", spin.value)
                                        _strip_w_cache = nil
                                        invalidateItemCache()
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                        if touchmenu_instance then touchmenu_instance:updateItems() end
                                    end,
                                })
                            end,
                        },
                        {
                            text_func = function()
                                local v = get("text_shear")
                                if v == 0 then return "Text lean: none"
                                else return ("Text lean: %d%%"):format(v) end
                            end,
                            keep_menu_open = true,
                            callback = function(touchmenu_instance)
                                local SpinWidget = require("ui/widget/spinwidget")
                                local UIManager  = require("ui/uimanager")
                                UIManager:show(SpinWidget:new{
                                    title_text          = "Text lean",
                                    value               = get("text_shear"),
                                    value_min           = 0,
                                    value_max           = 100,
                                    value_step          = 5,
                                    default_value       = DEFAULTS.text_shear,
                                    keep_shown_on_apply = true,
                                    callback = function(spin)
                                        set("text_shear", spin.value)
                                        local fc = require("ui/widget/filechooser")
                                        if fc.instance then fc.instance:updateItems() end
                                        if touchmenu_instance then touchmenu_instance:updateItems() end
                                    end,
                                })
                            end,
                        },
                    },
                },
                -- ── cover shape ────────────────────────────────────────────
                {
                    text = "Cover shape",
                    sub_item_table_func = function()
                        local SpinWidget = require("ui/widget/spinwidget")
                        local UIManager  = require("ui/uimanager")
                        local function refresh(tmi)
                            invalidateItemCache()
                            local fc = require("ui/widget/filechooser")
                            if fc.instance then fc.instance:updateItems() end
                            if tmi then tmi:updateItems() end
                        end
                        return {
                            -- cover size %
                            {
                                text_func = function()
                                    local v = get("cover_scale_pct")
                                    if v == 100 then return "Cover size: 100% (natural)"
                                    else return ("Cover size: %d%%"):format(v) end
                                end,
                                keep_menu_open = true,
                                callback = function(tmi)
                                    UIManager:show(SpinWidget:new{
                                        title_text          = "Cover size",
                                        value               = get("cover_scale_pct"),
                                        value_min           = 50,
                                        value_max           = 100,
                                        value_step          = 1,
                                        default_value       = DEFAULTS.cover_scale_pct,
                                        keep_shown_on_apply = true,
                                        value_text_func     = function(v) return v .. "%" end,
                                        callback = function(spin)
                                            set("cover_scale_pct", spin.value)
                                            refresh(tmi)
                                        end,
                                    })
                                end,
                            },
                            -- aspect ratio toggle
                            {
                                text_func = function()
                                    if get("aspect_enabled") then
                                        return ("Aspect ratio: %d:%d (enabled)"):format(
                                            get("aspect_ratio_w"), get("aspect_ratio_h"))
                                    else
                                        return "Aspect ratio: disabled"
                                    end
                                end,
                                checked_func = function() return get("aspect_enabled") end,
                                callback = function(tmi)
                                    set("aspect_enabled", not get("aspect_enabled"))
                                    refresh(tmi)
                                end,
                            },
                            -- ratio presets
                            {
                                text = "Ratio preset",
                                enabled_func = function() return get("aspect_enabled") end,
                                sub_item_table = {
                                    {
                                        text = "2:3  (standard book portrait)",
                                        checked_func = function()
                                            return get("aspect_ratio_w") == 2 and get("aspect_ratio_h") == 3
                                        end,
                                        callback = function()
                                            set("aspect_ratio_w", 2) set("aspect_ratio_h", 3)
                                            local fc = require("ui/widget/filechooser")
                                            if fc.instance then fc.instance:updateItems() end
                                        end,
                                    },
                                    {
                                        text = "3:4  (A4 / US Letter)",
                                        checked_func = function()
                                            return get("aspect_ratio_w") == 3 and get("aspect_ratio_h") == 4
                                        end,
                                        callback = function()
                                            set("aspect_ratio_w", 3) set("aspect_ratio_h", 4)
                                            local fc = require("ui/widget/filechooser")
                                            if fc.instance then fc.instance:updateItems() end
                                        end,
                                    },
                                    {
                                        text = "9:16  (tall)",
                                        checked_func = function()
                                            return get("aspect_ratio_w") == 9 and get("aspect_ratio_h") == 16
                                        end,
                                        callback = function()
                                            set("aspect_ratio_w", 9) set("aspect_ratio_h", 16)
                                            local fc = require("ui/widget/filechooser")
                                            if fc.instance then fc.instance:updateItems() end
                                        end,
                                    },
                                    {
                                        text = "1:1  (square)",
                                        checked_func = function()
                                            return get("aspect_ratio_w") == 1 and get("aspect_ratio_h") == 1
                                        end,
                                        callback = function()
                                            set("aspect_ratio_w", 1) set("aspect_ratio_h", 1)
                                            local fc = require("ui/widget/filechooser")
                                            if fc.instance then fc.instance:updateItems() end
                                        end,
                                    },
                                    {
                                        text = "3:2  (landscape)",
                                        checked_func = function()
                                            return get("aspect_ratio_w") == 3 and get("aspect_ratio_h") == 2
                                        end,
                                        callback = function()
                                            set("aspect_ratio_w", 3) set("aspect_ratio_h", 2)
                                            local fc = require("ui/widget/filechooser")
                                            if fc.instance then fc.instance:updateItems() end
                                        end,
                                    },
                                    -- custom W
                                    {
                                        text_func = function()
                                            return ("Custom ratio W: %d"):format(get("aspect_ratio_w"))
                                        end,
                                        keep_menu_open = true,
                                        callback = function(tmi)
                                            UIManager:show(SpinWidget:new{
                                                title_text          = "Ratio width",
                                                value               = get("aspect_ratio_w"),
                                                value_min           = 1,
                                                value_max           = 20,
                                                value_step          = 1,
                                                default_value       = DEFAULTS.aspect_ratio_w,
                                                keep_shown_on_apply = true,
                                                callback = function(spin)
                                                    set("aspect_ratio_w", spin.value)
                                                    local fc = require("ui/widget/filechooser")
                                                    if fc.instance then fc.instance:updateItems() end
                                                    if tmi then tmi:updateItems() end
                                                end,
                                            })
                                        end,
                                    },
                                    -- custom H
                                    {
                                        text_func = function()
                                            return ("Custom ratio H: %d"):format(get("aspect_ratio_h"))
                                        end,
                                        keep_menu_open = true,
                                        callback = function(tmi)
                                            UIManager:show(SpinWidget:new{
                                                title_text          = "Ratio height",
                                                value               = get("aspect_ratio_h"),
                                                value_min           = 1,
                                                value_max           = 20,
                                                value_step          = 1,
                                                default_value       = DEFAULTS.aspect_ratio_h,
                                                keep_shown_on_apply = true,
                                                callback = function(spin)
                                                    set("aspect_ratio_h", spin.value)
                                                    local fc = require("ui/widget/filechooser")
                                                    if fc.instance then fc.instance:updateItems() end
                                                    if tmi then tmi:updateItems() end
                                                end,
                                            })
                                        end,
                                    },
                                },
                            },
                        }
                    end,
                },
                -- ── page lines ─────────────────────────────────────────────
                {
                    text = "Page lines",
                    sub_item_table_func = function()
                        local SpinWidget = require("ui/widget/spinwidget")
                        local UIManager  = require("ui/uimanager")
                        local function refresh(tmi)
                            _lines_cache = {}
                            invalidateItemCache()
                            local fc = require("ui/widget/filechooser")
                            if fc.instance then fc.instance:updateItems() end
                            if tmi then tmi:updateItems() end
                        end
                        local items = {
                            {
                                text_func = function()
                                    return ("Line thickness: %d px"):format(get("page_thickness"))
                                end,
                                keep_menu_open = true,
                                callback = function(tmi)
                                    UIManager:show(SpinWidget:new{
                                        title_text          = "Line thickness",
                                        value               = get("page_thickness"),
                                        value_min           = 1,
                                        value_max           = 5,
                                        value_step          = 1,
                                        default_value       = DEFAULTS.page_thickness,
                                        keep_shown_on_apply = true,
                                        callback = function(spin)
                                            set("page_thickness", spin.value)
                                            refresh(tmi)
                                        end,
                                    })
                                end,
                            },
                            {
                                text_func = function()
                                    return ("Line spacing: %d px"):format(get("page_spacing"))
                                end,
                                keep_menu_open = true,
                                callback = function(tmi)
                                    UIManager:show(SpinWidget:new{
                                        title_text          = "Line spacing",
                                        value               = get("page_spacing"),
                                        value_min           = 0,
                                        value_max           = 5,
                                        value_step          = 1,
                                        default_value       = DEFAULTS.page_spacing,
                                        keep_shown_on_apply = true,
                                        callback = function(spin)
                                            set("page_spacing", spin.value)
                                            refresh(tmi)
                                        end,
                                    })
                                end,
                            },
                            {
                                text_func = function()
                                    local v = get("page_line_length_pct")
                                    return ("Line length: %d%% of cover width"):format(v)
                                end,
                                keep_menu_open = true,
                                callback = function(tmi)
                                    UIManager:show(SpinWidget:new{
                                        title_text          = "Line length (% of cover width)",
                                        value               = get("page_line_length_pct"),
                                        value_min           = 10,
                                        value_max           = 150,
                                        value_step          = 5,
                                        default_value       = DEFAULTS.page_line_length_pct,
                                        keep_shown_on_apply = true,
                                        value_text_func     = function(v) return v .. "%" end,
                                        callback = function(spin)
                                            set("page_line_length_pct", spin.value)
                                            refresh(tmi)
                                        end,
                                    })
                                end,
                            },
                            {
                                text_func = function()
                                    local key = get("line_color")
                                    for _, entry in ipairs(LINE_COLOR_MAP) do
                                        if entry.key == key then
                                            return "Line color: " .. entry.label:gsub("%s+%b()",""):gsub("%s+$","")
                                        end
                                    end
                                    return "Line color: Gray 4"
                                end,
                                sub_item_table_func = function()
                                    local color_items = {}
                                    for _, entry in ipairs(LINE_COLOR_MAP) do
                                        local ekey = entry.key
                                        table.insert(color_items, {
                                            text = entry.label,
                                            checked_func = function() return get("line_color") == ekey end,
                                            callback = function()
                                                set("line_color", ekey)
                                                invalidateItemCache()
                                                local fc = require("ui/widget/filechooser")
                                                if fc.instance then fc.instance:updateItems() end
                                            end,
                                        })
                                    end
                                    return color_items
                                end,
                            },
                            {
                                text = "Show line tiers",
                                sub_item_table_func = function()
                                    local tier_items = {}
                                    for n = 2, 10 do
                                        local key = "lines_enabled_" .. n
                                        local nn = n
                                        table.insert(tier_items, {
                                            text = nn .. " lines",
                                            checked_func = function()
                                                return get(key) ~= false
                                            end,
                                            enabled_func = function()
                                                return nn ~= 2  -- 2 is always-on fallback
                                            end,
                                            callback = function()
                                                set(key, get(key) == false and true or false)
                                                _lines_cache = {}
                                                local fc = require("ui/widget/filechooser")
                                                if fc.instance then fc.instance:updateItems() end
                                            end,
                                        })
                                    end
                                    return tier_items
                                end,
                            },
                        }
                        local range_labels = { "2 lines", "3 lines", "4 lines", "5 lines", "6 lines", "7 lines", "8 lines", "9 lines" }
                        local range_keys   = { "page_range_2", "page_range_3", "page_range_4", "page_range_5", "page_range_6", "page_range_7", "page_range_8", "page_range_9" }
                        for tier = 1, 8 do
                            local key   = range_keys[tier]
                            local label = range_labels[tier]
                            local tier_enabled = get("lines_enabled_" .. (tier + 1)) ~= false
                            local is_highest = tier_enabled
                            for t = tier + 2, 10 do
                                if get("lines_enabled_" .. t) ~= false then
                                    is_highest = false
                                    break
                                end
                            end
                            if tier_enabled and not is_highest then
                                table.insert(items, {
                                    text_func = function()
                                        return ("%s: up to %d pages"):format(label, get(key))
                                    end,
                                    keep_menu_open = true,
                                    callback = function(tmi)
                                        UIManager:show(SpinWidget:new{
                                            title_text          = label .. ": upper page limit (pages)",
                                            value               = get(key),
                                            value_min           = 1,
                                            value_max           = 9999,
                                            value_step          = 10,
                                            default_value       = DEFAULTS[key],
                                            keep_shown_on_apply = true,
                                            callback = function(spin)
                                                set(key, spin.value)
                                                refresh(tmi)
                                            end,
                                        })
                                    end,
                                })
                            end
                        end
                        -- read-only display of the highest enabled tier
                        table.insert(items, {
                            text_func = function()
                                local highest = 2
                                for tier = 10, 2, -1 do
                                    if get("lines_enabled_" .. tier) ~= false then
                                        highest = tier
                                        break
                                    end
                                end
                                local last_threshold = 0
                                for tier = highest - 1, 2, -1 do
                                    if get("lines_enabled_" .. tier) ~= false then
                                        last_threshold = get(range_keys[tier - 1]) or 0
                                        break
                                    end
                                end
                                return ("%d lines: %d+ pages"):format(highest, last_threshold)
                            end,
                            enabled_func = function() return false end,
                            callback = function() end,
                        })
                        -- file size estimation settings
                        table.insert(items, {
                            text = "--- Pages estimation by filesize (fallback option) ---",
                            enabled_func = function() return false end,
                            callback = function() end,
                        })
                        local fmt_labels = { "EPUB bytes/page", "PDF KB/page", "CBZ KB/page" }
                        local fmt_keys   = { "epub_bytes_per_page", "pdf_kb_per_page", "cbz_kb_per_page" }
                        local fmt_is_kb  = { false, true, true }
                        for i = 1, 3 do
                            local key    = fmt_keys[i]
                            local label  = fmt_labels[i]
                            local is_kb  = fmt_is_kb[i]
                            table.insert(items, {
                                text_func = function()
                                    if is_kb then
                                        return ("%s: %d KB"):format(label, get(key))
                                    else
                                        return ("%s: %.1f KB"):format(label, get(key) / 1024)
                                    end
                                end,
                                keep_menu_open = true,
                                callback = function(tmi)
                                    UIManager:show(SpinWidget:new{
                                        title_text          = label,
                                        value               = is_kb and get(key) or math.floor(get(key) / 512),
                                        value_min           = 1,
                                        value_max           = 10000,
                                        value_step          = 1,
                                        default_value       = is_kb and DEFAULTS[key] or math.floor(DEFAULTS[key] / 512),
                                        keep_shown_on_apply = true,
                                        value_text_func     = is_kb and nil or function(v)
                                            return string.format("%.1f KB", v * 512 / 1024)
                                        end,
                                        callback = function(spin)
                                            set(key, is_kb and spin.value or spin.value * 512)
                                            _lines_cache = {}
                                            refresh(tmi)
                                        end,
                                    })
                                end,
                            })
                        end
                        return items
                    end,
                },
                }
            end,
        })
    end

    orig_setUpdateItemTable(self)
end

-- ── hook into genItemTableFromPath to grab MosaicMenuItem ────────────────────
local orig_genItemTableFromPath = FileChooser.genItemTableFromPath
function FileChooser:genItemTableFromPath(path, ...)
    _lines_cache = {}
    _item_cache  = {}
    _bim_dims_cache = {}
    _progress_cache = {}
    if not FileChooser._vlabel_done then
        local ok, MosaicMenu = pcall(require, "mosaicmenu")
        if ok and MosaicMenu then
            local MM = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
            if MM then
                patchMosaicMenuItem(MM)
                FileChooser._vlabel_done = true
            end
        end
    end
    return orig_genItemTableFromPath(self, path, ...)
end

logger.info("mlabel: patch applied")
