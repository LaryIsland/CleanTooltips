local _, ns = ...
local L = ns.L

-- Removing other addons' lines (design document 4.3). Always the player's choice: every rule is off until they pick
-- it on the Sources page. Three kinds, kept in the profile:
--   hideAddon[folder]          every line that addon adds
--   hideLine[folder][shape]    one line, by its shape (its text with numbers as "#", Sources.Shape)
--   known[id]                  a ready-made rule for a line that has no setting in its own addon (KNOWN below, 4.5)
--
-- A line is taken out by blanking and hiding its font strings (the gap probe found no gap left behind, launch, 8 Nov),
-- and the tooltip is shown again next frame so it shrinks. Restore puts the font strings back when the tooltip is
-- cleared, as the tooltip reuses them for its next lines.
--   ns.Remove.ShouldHide(folder, text)
--   ns.Remove.Hide(tooltip, record, index), ns.Remove.Restore(tooltip, record)
--   ns.Remove.SetAddon(folder, on), SetLine(folder, text, on), SetKnown(id, on), and their getters
--   ns.Remove.Known(folder)   the known lines of an addon; ns.Remove.KnownAddons()

ns.Remove = {}
local Remove = ns.Remove

-- Known lines: other addons' lines with no setting of their own. Patterns are per locale; a missing locale just
-- means no ready-made rule. label: what the Sources page calls the line; hint: where it's turned off properly, or
-- that it can't be.
local KNOWN = {
	{
		id = "NpcAbilities_hint",
		addon = "NpcAbilities",
		label = L.KNOWN_NPCABILITIES_HINT,
		hint = L.KNOWN_NPCABILITIES_HINT_TIP,
		patterns = {
			enUS = { "^%(Press .+ for details%)$", "^%(Hotkey not bound%)$" },
		},
	},
}

local locale = GetLocale()
local knownByAddon = {}
for _, entry in ipairs(KNOWN) do
	entry.match = entry.patterns[locale] or (locale == "enGB" and entry.patterns.enUS) or nil
	knownByAddon[entry.addon] = knownByAddon[entry.addon] or {}
	table.insert(knownByAddon[entry.addon], entry)
end

function Remove.Known(folder)
	return knownByAddon[folder]
end

function Remove.KnownAddons()
	return knownByAddon
end

-- Deciding ----------------------------------------------------------------------------------------------------------

-- A known line whose rule is on (Remove.IsKnownLine, below, finds which known line it is).
local function MatchesKnown(folder, text, profile)
	local entry = Remove.IsKnownLine(folder, text)
	return entry ~= nil and profile.known[entry.id] == true
end

-- text: the line's text, or nil when it's secret (then only "every line from this addon" can apply). Line rules go by
-- the line's shape (Sources.Shape: numbers as "#"), so one rule covers a line whose numbers change. A blank line has
-- no rule of its own: it goes with the addon's lines beside it (Sources.lua).
function Remove.ShouldHide(folder, text)
	local profile = ns.profile
	if not profile then return false end
	if profile.hideAddon[folder] then return true end
	if text == nil or ns.Sources.IsBlank(text) then return false end
	local lines = profile.hideLine[folder]
	if lines and lines[ns.Sources.Shape(text)] then return true end
	return MatchesKnown(folder, text, profile)
end

-- Taking lines out -------------------------------------------------------------------------------------------------

local wasShown = setmetatable({}, { __mode = "k" }) -- [font string] = shown before CT hid it

local function Blank(fontString)
	if not fontString then return end
	if wasShown[fontString] == nil then wasShown[fontString] = fontString:IsShown() end
	fontString:SetText("")
	fontString:Hide()
end

-- The tooltip is shown again once at the end of the frame, so it fits its remaining lines. The data pipeline and most
-- addons call Show themselves after adding lines; this covers those that don't.
local resize = {}
local resizeQueued = false
local function ResizeNow()
	resizeQueued = false
	for tooltip in pairs(resize) do
		resize[tooltip] = nil
		if tooltip:IsShown() then tooltip:Show() end
	end
end

function Remove.Hide(tooltip, record, index)
	local left, right = ns.Line(tooltip, index)
	ns.Editing(function()
		Blank(left)
		Blank(right)
	end)
	record.hidden[index] = true
	resize[tooltip] = true
	if not resizeQueued then
		resizeQueued = true
		C_Timer.After(0, ResizeNow)
	end
end

function Remove.Restore(tooltip, record)
	if not next(record.hidden) then return end
	for index in pairs(record.hidden) do
		local left, right = ns.Line(tooltip, index)
		for _, fontString in ipairs({ left, right }) do
			if wasShown[fontString] then fontString:Show() end
			wasShown[fontString] = nil
		end
	end
end

-- Rules ------------------------------------------------------------------------------------------------------------

local function Changed()
	ns.Fire("RULES_CHANGED")
	ns.RefreshShownTooltips()
end

function Remove.IsAddonHidden(folder)
	return ns.profile and ns.profile.hideAddon[folder] == true
end

function Remove.SetAddon(folder, on)
	ns.profile.hideAddon[folder] = on or nil
	Changed()
end

-- hideLine[folder] holds shapes; `text` may be a line's text or a shape (shaping a shape changes nothing).
function Remove.IsLineHidden(folder, text)
	local lines = ns.profile and ns.profile.hideLine[folder]
	return lines ~= nil and lines[ns.Sources.Shape(text)] == true
end

function Remove.SetLine(folder, text, on)
	local lines = ns.profile.hideLine
	local shape = ns.Sources.Shape(text)
	if on then
		lines[folder] = lines[folder] or {}
		lines[folder][shape] = true
	elseif lines[folder] then
		lines[folder][shape] = nil
		if not next(lines[folder]) then lines[folder] = nil end
	end
	Changed()
end

function Remove.IsKnownOn(id)
	return ns.profile and ns.profile.known[id] == true
end

function Remove.SetKnown(id, on)
	ns.profile.known[id] = on or nil
	Changed()
end

-- Whether a line would be removed by the known rule (on or off), for the Sources page to show it under that rule
-- rather than as a line of its own.
function Remove.IsKnownLine(folder, text)
	local entries = knownByAddon[folder]
	if not entries or not text then return nil end
	local plain = ns.PlainText(text)
	for _, entry in ipairs(entries) do
		for _, pattern in ipairs(entry.match or {}) do
			if plain and plain:find(pattern) then return entry end
		end
	end
	return nil
end
