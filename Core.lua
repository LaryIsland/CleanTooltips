local addonName, ns = ...

-- Names of things in the addon players see or click (options, pages, commands) are marked {like this} in Locales,
-- and shown in a colour of their own. Done once every locale file has loaded, so a translation's lines are marked too.
ns.NAME_COLOR = "ff71d5ff"
for key, text in pairs(ns.L) do
	if type(text) == "string" and text:find("{", 1, true) then
		rawset(ns.L, key, (text:gsub("{(.-)}", "|c" .. ns.NAME_COLOR .. "%1|r")))
	end
end

-- The tooltips whose lines are attributed and can be removed. Clean-up and styling reach every
-- data-driven tooltip through TooltipDataProcessor, which is global.
ns.TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }

-- Secret values ------------------------------------------------------------------------------------------------------
-- Unit tooltips can hold secret text in combat. It can be shown, but never compared,
-- pattern-matched or measured, so everything that reads tooltip, unit or stack values reads them through
-- ns.Readable first and then works only on what it returned: a secret becomes nil before anything compares it, tests
-- it or asks its type.

function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

-- The value when it can be read, otherwise nil.
function ns.Readable(value)
	if issecretvalue ~= nil and issecretvalue(value) == true then return nil end
	return value
end

-- True only for a readable true (a secret boolean counts as unknown).
function ns.True(value)
	return not ns.IsSecret(value) and value == true
end

-- Tooltip text --------------------------------------------------------------------------------------------------------

-- A Lua pattern matching the whole of a line built from one of the game's format strings ("Durability %d / %d"), so
-- the match follows the client's language. Numbers are captured as text; %s captures anything.
function ns.PatternFromFormat(format)
	if type(format) ~= "string" or format == "" then return nil end
	-- Placeholders (also the numbered %1$d form translations use) and "%%" are set aside before the rest is escaped.
	local pattern = format:gsub("%%%%", "\3"):gsub("%%%d?%$?d", "\1"):gsub("%%%d?%$?s", "\2")
	pattern = pattern:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
	pattern = pattern:gsub("\1", "(%%d+)"):gsub("\2", "(.+)"):gsub("\3", "%%%%")
	return "^" .. pattern .. "$"
end

-- Text without colour codes, its icons kept (|T...|t textures, |A...|a atlases), for showing a line as it looked.
function ns.WithIcons(text)
	text = ns.Readable(text)
	if type(text) ~= "string" then return nil end
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Text without colour codes and textures, for showing and matching.
function ns.PlainText(text)
	text = ns.Readable(text)
	if type(text) ~= "string" then return nil end
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

-- A capped cache for the hot paths (stacks, texts, shapes, short forms): reads are plain table lookups on
-- `cache.items`; Set starts afresh once `size` entries have been stored, so it never grows past that.
--   local cache = ns.Cache(500); local value = cache.items[key]; cache:Set(key, value); cache:Clear()
local CacheMethods = {}
CacheMethods.__index = CacheMethods

function CacheMethods:Set(key, value)
	if self.count >= self.size then self:Clear() end
	self.items[key] = value
	self.count = self.count + 1
end

function CacheMethods:Clear()
	self.items, self.count = {}, 0
end

function ns.Cache(size)
	return setmetatable({ items = {}, count = 0, size = size }, CacheMethods)
end

-- A tooltip's left and right font strings for line `index`.
function ns.Line(tooltip, index)
	if tooltip.GetLeftLine then
		return tooltip:GetLeftLine(index), tooltip:GetRightLine(index)
	end
	local name = tooltip:GetName()
	if not name then return nil end
	return _G[name .. "TextLeft" .. index], _G[name .. "TextRight" .. index]
end

-- CT's own changes to tooltip text happen inside ns.Editing, so the attribution hooks know they're CT's
-- without reading the call stack.
ns.editing = false
function ns.Editing(fn, ...)
	local was = ns.editing -- so a call inside another doesn't end the outer one early
	ns.editing = true
	local ok, err = xpcall(fn, ns.WithStack, ...)
	ns.editing = was
	if not ok then ns.ReportError("editing", err) end
end

-- CT's own preview tooltips that show the game's tooltip untouched. Every CT callback skips them.
ns.raw = setmetatable({}, { __mode = "k" })
function ns.Active(tooltip)
	return ns.profile ~= nil and not ns.raw[tooltip]
end

-- Errors and events --------------------------------------------------------------------------------------------------

local function WithStack(err)
	return tostring(err) .. (debugstack and ("\n" .. debugstack(2)) or "")
end
ns.WithStack = WithStack

function ns.ReportError(where, err)
	geterrorhandler()(addonName .. " (" .. tostring(where) .. "): " .. tostring(err))
end

function ns.SafeCall(where, fn, ...)
	local ok, err = xpcall(fn, WithStack, ...)
	if not ok then ns.ReportError(where, err) end
	return ok
end

-- `fn` made safe to hook onto a tooltip or font string: those hooks run inside whoever called the method (the game's
-- tooltip build, another addon's handler), so an error is reported here instead of stopping that caller part way.
function ns.Guarded(where, fn)
	return function(...) ns.SafeCall(where, fn, ...) end
end

local events = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handlers = events[event]
	if not handlers then return end
	for i = 1, #handlers do
		local ok, err = xpcall(handlers[i], WithStack, ...)
		if not ok then ns.ReportError(event, err) end
	end
end)

-- Calls handler(...) on every `event`.
function ns.On(event, handler)
	if not events[event] then
		events[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(events[event], handler)
end

-- The addon's own notifications: DB_READY, LOGIN, SETTINGS_CHANGED (what changed, nil for everything after a profile
-- change), RULES_CHANGED (removal rules), SOURCE_SEEN (an addon's line, or a line newly listed on the Sources page),
-- TOOLTIP_SEEN (the current tooltip changed, at most once a frame).
local listeners = {}
function ns.Listen(name, handler)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], handler)
end

function ns.Fire(name, ...)
	local handlers = listeners[name]
	if not handlers then return end
	for i = 1, #handlers do
		local ok, err = xpcall(handlers[i], WithStack, ...)
		if not ok then ns.ReportError(name, err) end
	end
end

-- Chat lines for the player have no addon prefix, so they're easy to skim.
function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage(text)
end

function ns.InCombat()
	return InCombatLockdown() == true
end

-- Runs fn at most once a frame, however often it's asked for.
function ns.Throttled(fn)
	local queued = false
	local function Run()
		queued = false
		ns.SafeCall("throttled", fn)
	end
	return function()
		if queued then return end
		queued = true
		C_Timer.After(0, Run)
	end
end

-- Shown tooltips are rebuilt after a setting changes, so it applies at once. Only data-driven
-- tooltips can be; others show the change next time. At most once a frame. Not in combat: the rebuild runs from
-- addon code, and tooltip processing tainted with secret data shows no lines; the next tooltip picks the
-- change up.
ns.RefreshShownTooltips = ns.Throttled(function()
	if ns.InCombat() then return end
	for _, name in ipairs(ns.TOOLTIPS) do
		local tooltip = _G[name]
		if tooltip and tooltip:IsShown() and tooltip.RefreshData and tooltip.GetPrimaryTooltipInfo
			and tooltip:GetPrimaryTooltipInfo() then
			ns.SafeCall("refresh", tooltip.RefreshData, tooltip)
		end
	end
end)

-- Saved settings ------------------------------------------------------------------------------------------------------
-- Everything players set is in AceDB profiles.
--   ns.db       the AceDB object
--   ns.profile  the current profile
--   ns.global   account-wide: the default profile for new characters, development captures

-- Everything is off by default: with a new profile, tooltips are exactly the game's until the player changes something.
-- The clean-up options, in the order the Clean-up page shows them: one list for the page's Defaults button and for
-- rebuilding shown tooltips when one changes (Blizzard.lua).
ns.CLEANUP_FIELDS = { "hideSellPrice", "sellPriceAtVendor", "hideMetLevel", "hideMetRequirements", "hideSoulbound",
	"hideUnique", "hideDurability", "shortenDps", "shortenEquip", "dropEquipPrefix", "shortenUse", "hideSecondCooldown",
	"hideFaction", "hidePvP" }

ns.PROFILE_DEFAULTS = {
	-- Clean-up
	hideSellPrice = false,
	sellPriceAtVendor = false,
	hideDurability = false,
	hideMetLevel = false,
	shortenUse = false,
	hideSecondCooldown = false,
	shortenEquip = false,
	dropEquipPrefix = false,
	shortenDps = false,
	hideMetRequirements = false,
	hideSoulbound = false,
	hideUnique = false,
	hideFaction = false,
	hidePvP = false,
	-- Look
	classNames = false,
	hostileRed = false,
	borderClass = false,
	borderReaction = false,
	borderQuality = false,
	healthBar = false,  -- a LibSharedMedia status bar's name; false keeps the game's
	font = false,       -- a LibSharedMedia font's name; false keeps the game's
	background = false, -- { r, g, b, a }; false keeps the game's
	-- Other addons' lines
	showSources = false,
	hideAddon = {},     -- [addon folder] = true: every line it adds
	hideLine = {},      -- [addon folder] = { [line shape] = { types, sites } } (Sources.Shape: numbers as "#"; Remove.lua)
	hideWritten = {},   -- [addon folder] = { [call site] = { prefix, label, types } }: lines added blank, then written
}

function ns.ProfileChanged()
	ns.profile = ns.db.profile
	ns.Fire("SETTINGS_CHANGED")
	ns.Fire("RULES_CHANGED")
end

-- Records a change to the current profile (what: the field's name) and applies it.
function ns.Changed(what)
	ns.Fire("SETTINGS_CHANGED", what)
end

ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	local saved = _G.CleanTooltipsDB
	local defaultProfile = type(saved) == "table" and type(saved.global) == "table" and saved.global.defaultProfile
	local db = LibStub("AceDB-3.0"):New("CleanTooltipsDB", {
		profile = ns.PROFILE_DEFAULTS,
		global = { defaultProfile = "Default" },
	}, type(defaultProfile) == "string" and defaultProfile or true)
	ns.db = db
	ns.global = db.global
	for _, callback in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
		db.RegisterCallback(ns, callback, ns.ProfileChanged)
	end
	ns.profile = db.profile
	ns.Fire("DB_READY")
end)

ns.On("PLAYER_LOGIN", function()
	ns.Fire("LOGIN")
end)

