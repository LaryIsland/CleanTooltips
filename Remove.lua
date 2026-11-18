local _, ns = ...
local L = ns.L

-- Removing other addons' lines. Always the player's choice: every rule is off until they pick
-- it on the Sources page. Three kinds, kept in the profile:
--   hideAddon[folder]          every line that addon adds, on every tooltip type
--   hideLine[folder][shape]    one line, by its shape (its text with numbers as "#", Sources.Shape):
--                              { types = the tooltip types it was seen on ({ Item = true }; none: every type),
--                                sites = the call sites it's added from ({ ["Addon.lua:120"] = true }) }. Its text
--                              can be secret in combat, and then the line goes by its call site (learned when the
--                              rule hides it out of combat), unless that site has added other lines too this session
--                              (Sources.SiteOnlyAdds).
--   known[id]                  a ready-made rule for a line that has no setting in its own addon (KNOWN below),
--                              on the types its entry names
--   hideWritten[folder][site]  a line the addon adds blank and then writes into (Leatrix Plus's "Target: <name>"):
--                              its text changes (and is secret in combat), so the rule goes by where the addon adds
--                              it (the call site, "Leatrix_Plus.lua:16692", Sources.Parse) and hides it as it's
--                              added. { prefix = its text up to ": " ("Target: "), label = the text when ticked,
--                              types }. The prefix catches it out of combat after the addon changes and its call
--                              site moves, and moves the rule there.
-- Attribution runs only on the tooltip types some rule covers (Remove.RuleTypes, Sources.lua's gate). A line rule
-- learns another type whenever its line is attributed there (the column on, or the options open).
--
-- A line is taken out by blanking and hiding its font strings, which leaves no gap behind, and the tooltip is shown
-- again next frame so it shrinks. Restore puts the font strings back when the tooltip is cleared, as the tooltip reuses
-- them for its next lines.
--   ns.Remove.ShouldHide(folder, text, typeName, site)   whether to hide, and the line rule that matched
--   ns.Remove.RuleTypes()
--   ns.Remove.SetWritten(folder, site, text, on, types), IsWrittenHidden(folder, site),
--   MatchWritten(folder, text, site), WrittenRules(folder), HiddenBySite(folder, site, lines)
--   ns.Remove.Hide(tooltip, record, index), ns.Remove.Restore(tooltip, record)
--   ns.Remove.SetAddon(folder, on), SetLine(folder, text, on, types), SetKnown(id, on), and their getters
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
		types = { Unit = true }, -- its hint is on NPC tooltips only
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
-- the line's shape (Sources.Shape: numbers as "#"), so one rule covers a line whose numbers change, on any tooltip
-- type; typeName (the tooltip's, when known) is added to the rule's types if it's new. A blank line has no rule of its
-- own: it goes with the addon's lines beside it (Sources.lua).
-- site: where the addon added the line (Sources.Parse), when its stack was read. A matched line rule learns the type
-- (typeName) and the site; with no text (secret, in combat) a rule that learned this site applies. The second result
-- is the line rule that matched, if one did.
function Remove.ShouldHide(folder, text, typeName, site)
	local profile = ns.profile
	if not profile then return false end
	if profile.hideAddon[folder] then return true end
	local lines = profile.hideLine[folder]
	if text == nil then
		return site ~= nil and lines ~= nil and Remove.HiddenBySite(folder, site, lines) or false
	end
	if ns.Sources.IsBlank(text) then return false end
	local rule = lines and lines[ns.Sources.Shape(text)]
	if rule then
		if type(rule) == "table" then
			if typeName and rule.types and not rule.types[typeName] then
				rule.types[typeName] = true
				ns.Sources.UpdateGate()
			end
			if site then
				rule.sites = rule.sites or {}
				rule.sites[site] = true
			end
		end
		return true, rule
	end
	return MatchesKnown(folder, text, profile)
end

-- Whether a line rule of `folder` has learned `site`, and the site is trusted: it added only that rule's line this
-- session (a site shared by several lines, an addon's helper, would take the others with it).
function Remove.HiddenBySite(folder, site, lines)
	local shape = ns.Sources.SiteOnlyAdds(folder, site)
	if shape == false then return false end
	for ruleShape, rule in pairs(lines) do
		if type(rule) == "table" and rule.sites and rule.sites[site] and (shape == nil or shape == ruleShape) then
			return true
		end
	end
	return false
end

-- Where attribution has to run for the rules on: true when on every tooltip ("every line it adds", or a line rule not
-- tied to types); otherwise false and the set of tooltip type names.
function Remove.RuleTypes()
	local profile = ns.profile
	local types = {}
	if not profile then return false, types end
	if next(profile.hideAddon) then return true, types end
	for _, lines in pairs(profile.hideLine) do
		for _, rule in pairs(lines) do
			local ruleTypes = type(rule) == "table" and rule.types
			if not (ruleTypes and next(ruleTypes)) then return true, types end
			for name in pairs(ruleTypes) do types[name] = true end
		end
	end
	for _, entry in ipairs(KNOWN) do
		if profile.known[entry.id] then
			if not entry.types then return true, types end
			for name in pairs(entry.types) do types[name] = true end
		end
	end
	for _, rules in pairs(profile.hideWritten) do
		for _, rule in pairs(rules) do
			if not (rule.types and next(rule.types)) then return true, types end
			for name in pairs(rule.types) do types[name] = true end
		end
	end
	return false, types
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
	return lines ~= nil and lines[ns.Sources.Shape(text)] ~= nil
end

-- types: the tooltip type names the line was seen on ({ Item = true }), or nil when not known (every type).
function Remove.SetLine(folder, text, on, types)
	local lines = ns.profile.hideLine
	local shape = ns.Sources.Shape(text)
	if on then
		lines[folder] = lines[folder] or {}
		local rule = lines[folder][shape]
		if type(rule) ~= "table" then rule = { sites = {} } end
		if types and next(types) then
			rule.types = rule.types or {}
			for name in pairs(types) do rule.types[name] = true end
		else
			rule.types = nil -- every type
		end
		lines[folder][shape] = rule
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

-- Lines an addon adds blank and then writes into (hideWritten, above) -------------------------------------------------

function Remove.WrittenRules(folder)
	return ns.profile and ns.profile.hideWritten[folder]
end

function Remove.IsWrittenHidden(folder, site)
	local rules = ns.profile and ns.profile.hideWritten[folder]
	return rules ~= nil and site ~= nil and rules[site] ~= nil
end

-- The rule for a line `folder` just wrote into a blank line of its own, by its call site, or by its text's prefix (then
-- the rule moves to this call site: the addon changed and the line is added elsewhere now). nil when none.
function Remove.MatchWritten(folder, text, site)
	local rules = ns.profile and ns.profile.hideWritten[folder]
	if not rules then return nil end
	if site and rules[site] then return rules[site] end
	local plain = ns.PlainText(text)
	if not plain then return nil end
	for key, rule in pairs(rules) do
		if rule.prefix and plain:sub(1, #rule.prefix) == rule.prefix then
			if site and key ~= site then
				rules[key] = nil
				rules[site] = rule
			end
			return rule
		end
	end
	return nil
end

-- text: the line as it was shown (its label on the Sources page, and where its prefix comes from); types: the tooltip
-- types it was seen on (nil: every type).
function Remove.SetWritten(folder, site, text, on, types)
	local all = ns.profile.hideWritten
	if on then
		local plain = ns.PlainText(text) or ""
		local rule = { label = plain, prefix = plain:match("^(.-:%s)") }
		if types and next(types) then
			rule.types = {}
			for name in pairs(types) do rule.types[name] = true end
		end
		all[folder] = all[folder] or {}
		all[folder][site] = rule
	elseif all[folder] then
		all[folder][site] = nil
		if not next(all[folder]) then all[folder] = nil end
	end
	Changed()
end
