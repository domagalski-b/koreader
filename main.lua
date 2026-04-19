local WidgetContainer = require("ui/widget/container/widgetcontainer")

local function safe_require(name)
    local ok, err = pcall(require, name)
    if not ok then
        print("[simpleui_custom_look_v2] failed to load " .. tostring(name) .. ": " .. tostring(err))
    end
end

-- Load quote first because it depends on plugin-style environment.
safe_require("quote_patch")
safe_require("wallpaper_patch")
safe_require("navbar_indicator_patch")
safe_require("navbar_separator_patch")
safe_require("reading_stats_patch")

local SimpleUICustomLook = WidgetContainer:extend({
    name = "SimpleUI Custom Look v2",
    is_doc_only = false,
})

return SimpleUICustomLook
