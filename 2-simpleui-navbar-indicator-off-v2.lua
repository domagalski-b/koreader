-- Hide SimpleUI navbar top indicator strip by forcing its height to 0.
-- Narrow patch: only overrides sui_bottombar.INDIC_H().

local UIManager = require("ui/uimanager")

local installed = false
local tries = 0
local max_tries = 20

local function log(msg)
    print("[SUI navbar indicator off v2] " .. tostring(msg))
end

local function install_patch()
    if installed then return true end

    local ok, Bar = pcall(require, "sui_bottombar")
    if not ok or type(Bar) ~= "table" then
        return false
    end
    if Bar._navbar_indicator_off_v2_applied then
        installed = true
        return true
    end

    local old = Bar.INDIC_H
    if type(old) ~= "function" then
        log("INDIC_H missing")
        return false
    end

    Bar.INDIC_H = function()
        return 0
    end

    Bar._navbar_indicator_off_v2_applied = true
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
