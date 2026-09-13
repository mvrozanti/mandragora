local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")

local ROOT = "/mnt/us/mandragora"
local SCRIPTLETS = ROOT .. "/scriptlets"

local HOME_CORNER = "DTAP_ZONE_BOTTOM_RIGHT"
local HOME_HOLD_OVERRIDES = { "readerhighlight_hold", "readerfooter_hold" }

local ACTIONS = {
    {
        id = "mandragora_portrait",
        label = "Portrait",
        widget = "portrait",
        icon = "portrait.svg",
        note = "full-screen art, tap to shuffle",
    },
    {
        id = "mandragora_status",
        label = "Status",
        script = "mandragora-status.sh",
        icon = "status.svg",
        note = "device overlay",
    },
    {
        id = "mandragora_mpd",
        label = "Music",
        widget = "mpd",
        icon = "mpd.svg",
        note = "now playing, transport",
    },
    {
        id = "mandragora_dash",
        label = "Dash",
        script = "mandragora-dash.sh",
        icon = "dash.svg",
        note = "host status panel",
    },
    {
        id = "mandragora_sync",
        label = "Sync",
        script = "mandragora-sync.sh",
        icon = "sync.svg",
        note = "pull new art",
    },
}

local Mandragora = WidgetContainer:new{
    name = "mandragora",
    is_doc_only = false,
}

local function findQuickActions()
    local ok, mod = pcall(require, "features/sui_quickactions")
    if ok and type(mod) == "table" and mod.register then return mod end
    for key, m in pairs(package.loaded) do
        if type(key) == "string" and key:find("sui_quickactions", 1, true)
            and type(m) == "table" and m.register then
            return m
        end
    end
    return nil
end

local function scriptPath(name)
    return SCRIPTLETS .. "/" .. name
end

local function exists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

local icon_cache = {}

local function iconPath(name)
    if icon_cache[name] then return icon_cache[name] end
    local candidate = ROOT .. "/icons/" .. name
    if not exists(candidate) then return nil end
    icon_cache[name] = candidate
    return candidate
end

local function openWidget(name)
    local ok, mod = pcall(require, name)
    if not ok or type(mod) ~= "table" or not mod.open then
        local here = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
        ok, mod = pcall(dofile, here .. name .. ".lua")
        if not ok or type(mod) ~= "table" or not mod.open then
            UIManager:show(InfoMessage:new{ text = "cannot load " .. name, timeout = 3 })
            return
        end
    end
    mod.open()
end

local function runScriptlet(entry)
    local path = scriptPath(entry.script)
    if not exists(path) then
        UIManager:show(InfoMessage:new{
            text = "missing: " .. path,
            timeout = 3,
        })
        return
    end
    logger.info("mandragora: running", path)
    os.execute("/bin/sh " .. path .. " >/dev/null 2>&1 &")
end

function Mandragora:registerActions()
    local QA = findQuickActions()
    if not QA then return false end
    for _, entry in ipairs(ACTIONS) do
        QA.register{
            id = entry.id,
            label = entry.label,
            icon = iconPath(entry.icon),
            get_icon = function() return iconPath(entry.icon) end,
            is_in_place = true,
            execute = function()
                if entry.widget then
                    openWidget(entry.widget)
                else
                    runScriptlet(entry)
                end
            end,
        }
    end
    logger.info("mandragora: registered", #ACTIONS, "quick actions")
    self.registered = true
    return true
end

function Mandragora:registerHomeGesture()
    if not self.ui or not self.ui.registerTouchZones then return end
    if not self.ui.document then return end
    local corner = G_defaults and G_defaults:readSetting(HOME_CORNER)
    if not corner then return end
    self.ui:registerTouchZones{
        {
            id = "mandragora_home_corner",
            ges = "hold",
            screen_zone = {
                ratio_x = corner.x,
                ratio_y = corner.y,
                ratio_w = corner.w,
                ratio_h = corner.h,
            },
            overrides = HOME_HOLD_OVERRIDES,
            handler = function()
                return self.ui:handleEvent(Event:new("SimpleUIGoHomescreen")) and true or false
            end,
        },
    }
    logger.info("mandragora: home gesture on hold", HOME_CORNER)
end

function Mandragora:init()
    self:registerHomeGesture()
    if self:registerActions() then return end
    local attempts = 0
    local function retry()
        attempts = attempts + 1
        if self:registerActions() then return end
        if attempts < 10 then UIManager:scheduleIn(1, retry) end
    end
    UIManager:scheduleIn(1, retry)
end

function Mandragora:onCloseWidget()
    if not self.registered then return end
    local QA = findQuickActions()
    if not QA or not QA.unregister then return end
    for _, entry in ipairs(ACTIONS) do
        QA.unregister(entry.id)
    end
end

return Mandragora
