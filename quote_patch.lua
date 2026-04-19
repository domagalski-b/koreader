local AlphaTextBoxWidget = require("widgets/alphatextboxwidget")
local Blitbuffer         = require("ffi/blitbuffer")
local VerticalGroup      = require("ui/widget/verticalgroup")
local userpatch          = require("userpatch")
local _                  = require("gettext")
local UI                 = require("sui_core")

userpatch.registerPatchPluginFunc("simpleui", function()
    local quotes = require("desktop_modules/module_quote")
    if not quotes or type(quotes.build) ~= "function" then return end

    local buildFromQuote, buildFromQuote_idx = userpatch.getUpValue(quotes.build, "buildFromQuote")
    if not buildFromQuote then return end

    local _, buildWidget_idx = userpatch.getUpValue(buildFromQuote, "buildWidget")
    local pickQuote          = userpatch.getUpValue(buildFromQuote, "pickQuote")
    if not buildWidget_idx or not pickQuote then return end

    local function new_buildWidget(inner_w, text_str, attr_str, face_quote, face_attr, vspan_gap)
        local vg = VerticalGroup:new { align = "center" }
        local quote_fg = Blitbuffer.COLOR_BLACK

        vg[#vg + 1] = AlphaTextBoxWidget:new {
            text      = text_str,
            face      = face_quote,
            fgcolor   = quote_fg,
            width     = inner_w,
            alignment = "center",
        }

        vg[#vg + 1] = AlphaTextBoxWidget:new {
            text      = attr_str,
            face      = face_attr,
            fgcolor   = UI.CLR_TEXT_SUB,
            bold      = true,
            width     = inner_w,
            alignment = "center",
        }
        return vg
    end

    local function new_buildFromQuote(inner_w, face_quote, face_attr, vspan_gap)
        local q = pickQuote()

        if not q then
            return AlphaTextBoxWidget:new {
                text    = _("No quotes found."),
                face    = face_quote,
                fgcolor = UI.CLR_TEXT_SUB,
                width   = inner_w,
            }
        end

        local attr = "— " .. (q.a or "?")
        if q.b and q.b ~= "" then
            attr = attr .. ",  " .. q.b
        end
        return new_buildWidget(inner_w, "“" .. q.q .. "”", attr, face_quote, face_attr, vspan_gap)
    end

    userpatch.replaceUpValue(buildFromQuote, buildWidget_idx, new_buildWidget)
    userpatch.replaceUpValue(quotes.build, buildFromQuote_idx, new_buildFromQuote)
end)
