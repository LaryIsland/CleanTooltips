local _, ns = ...

-- Compacting Blizzard's own tooltips, all through TooltipDataProcessor, so it reaches
-- every data-driven tooltip. A line pre-call returning true drops the line with no gap; a post-call changes
-- only the font string the line was drawn in. Nothing here writes into lineData or tooltipData.
--
-- Registered when the file loads: the callbacks do nothing until the profile is ready (ns.Active).

local LineType = Enum.TooltipDataLineType
local TooltipType = Enum.TooltipDataType

-- The tooltip's data, when it's being built.
local function DataOf(tooltip)
	local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
	return info and info.tooltipData
end

-- The tooltip is about an item (not a unit or spell that happens to show an item line): its data's type is Item, or
-- its first line is an item's name. An item on an action button (Bartender4's, through SetAction) has its item's
-- lines but not, it seems, the Item type.
local function IsItemTooltip(tooltip)
	local data = DataOf(tooltip)
	if data == nil then return false end
	if ns.Readable(data.type) == TooltipType.Item then return true end
	local first = type(data.lines) == "table" and data.lines[1]
	return type(first) == "table" and ns.Readable(first.type) == LineType.ItemName
end

-- Sell price: the line has no text; Blizzard's own post-call writes the price, and is skipped with the line.
local atVendor = false
ns.On("MERCHANT_SHOW", function() atVendor = true end)
ns.On("MERCHANT_CLOSED", function() atVendor = false end)

TooltipDataProcessor.AddLinePreCall(LineType.SellPrice, function(tooltip)
	if not (ns.Active(tooltip) and ns.profile.hideSellPrice) then return end
	if atVendor and ns.profile.sellPriceAtVendor then return end
	return true
end)

-- Full durability and a level requirement already met, matched on the game's own strings so they follow
-- the client's language. Durability lines are typed None and level requirements UsageRequirement, so each pre-call
-- runs only on its type, and only acts on item tooltips. A missing or reworded format string leaves its pattern nil or
-- never matching; /ctt lines reports either (Dev.lua).
ns.Blizzard = {
	FORMATS = { durability = "DURABILITY_TEMPLATE", minLevel = "ITEM_MIN_LEVEL" }, -- the global strings they're built from
	patterns = {},
}
local patterns = ns.Blizzard.patterns
for key, global in pairs(ns.Blizzard.FORMATS) do patterns[key] = ns.PatternFromFormat(_G[global]) end

local function LineText(lineData)
	local text = ns.Readable(lineData.leftText)
	return type(text) == "string" and text or nil
end

-- "Unique" in its three forms: "Unique", "Unique (20)", "Unique-Equipped".
local UNIQUE_MULTIPLE = ns.PatternFromFormat(ITEM_UNIQUE_MULTIPLE)
local function IsUnique(text)
	return text == ITEM_UNIQUE or text == ITEM_UNIQUE_EQUIPPABLE
		or (UNIQUE_MULTIPLE ~= nil and text:find(UNIQUE_MULTIPLE) ~= nil)
end

-- An item tooltip about an item the player has: one in the bags, bank or worn has its own GUID in the tooltip's data,
-- and any other copy (a vendor's, a link) counts when the player holds one.
local function IsOwned(tooltip)
	local data = DataOf(tooltip)
	if not data then return false end
	if ns.Readable(data.guid) ~= nil or data.ctOwned then return true end -- ctOwned: a sample drawn as owned (Preview)
	local id = ns.Readable(data.id)
	local count = id and C_Item.GetItemCount and ns.Readable(C_Item.GetItemCount(id, true))
	return type(count) == "number" and count > 0
end

-- Unit tooltip lines under the name: the faction ("Alliance", "Horde") and the PvP flag ("PvP"), by the game's
-- own strings. In combat their text can be secret, and they stay.
local FACTIONS = {}
for _, text in ipairs({ FACTION_ALLIANCE, FACTION_HORDE }) do
	if type(text) == "string" then FACTIONS[text] = true end
end

local function IsUnitTooltip(tooltip)
	local data = DataOf(tooltip)
	return data ~= nil and ns.Readable(data.type) == TooltipType.Unit
end

-- Plain lines: full durability and "Unique" on items you own, the faction and PvP lines on units.
TooltipDataProcessor.AddLinePreCall(LineType.None, function(tooltip, lineData)
	if not ns.Active(tooltip) then return end
	local profile = ns.profile
	if not (profile.hideDurability or profile.hideUnique or profile.hideFaction or profile.hidePvP) then return end
	local text = LineText(lineData)
	if not text then return end
	if profile.hideFaction and FACTIONS[text] and IsUnitTooltip(tooltip) then return true end
	if profile.hidePvP and text == PVP_ENABLED and IsUnitTooltip(tooltip) then return true end
	if not IsItemTooltip(tooltip) then return end
	if profile.hideDurability and patterns.durability then
		local current, maximum = text:match(patterns.durability)
		if current and tonumber(current) == tonumber(maximum) then return true end
	end
	if profile.hideUnique and IsUnique(text) and IsOwned(tooltip) then return true end
end)

-- "Soulbound": only items the player has say it, so it tells them nothing new. "Binds when picked up" stays.
-- Binding lines are only ever an item's, whatever the tooltip's type (an item on an action button).
TooltipDataProcessor.AddLinePreCall(LineType.ItemBinding, function(tooltip, lineData)
	if not (ns.Active(tooltip) and ns.profile.hideSoulbound) then return end
	local text = LineText(lineData)
	if text and ITEM_SOULBOUND and text == ITEM_SOULBOUND then return true end
end)

-- Requirements: the level one by the player's level; any other the player meets (a profession, a
-- reputation, a faction) by its colour, as the game draws one the player doesn't meet in red. Class and race
-- restrictions always stay: they say who the item is for. A level range stays too. The Clean-up page's samples use
-- the same list (Preview.lua).
local KEPT_REQUIREMENTS = {}
local KEPT_FORMATS = { "ITEM_CLASSES_ALLOWED", "ITEM_RACES_ALLOWED", "ITEM_LEVEL_RANGE", "ITEM_LEVEL_RANGE_CURRENT" }
for _, global in ipairs(KEPT_FORMATS) do
	KEPT_REQUIREMENTS[#KEPT_REQUIREMENTS + 1] = ns.PatternFromFormat(_G[global])
end

local function IsKeptRequirement(text)
	for i = 1, #KEPT_REQUIREMENTS do
		if text:find(KEPT_REQUIREMENTS[i]) then return true end
	end
	return false
end
ns.Blizzard.IsKeptRequirement = IsKeptRequirement

local function IsRed(color)
	if type(color) ~= "table" then return false end
	local r, g, b = ns.Readable(color.r), ns.Readable(color.g), ns.Readable(color.b)
	return r ~= nil and g ~= nil and b ~= nil and r > 0.9 and g < 0.3 and b < 0.3
end

TooltipDataProcessor.AddLinePreCall(LineType.UsageRequirement, function(tooltip, lineData)
	if not ns.Active(tooltip) then return end
	local profile = ns.profile
	if not (profile.hideMetLevel or profile.hideMetRequirements) then return end
	-- Requirement lines are only ever an item's, whatever the tooltip's type (an item on an action button).
	local text = LineText(lineData)
	if not text then return end
	local level = patterns.minLevel and tonumber(text:match(patterns.minLevel))
	if level then
		local playerLevel = profile.hideMetLevel and ns.Readable(UnitLevel("player"))
		if playerLevel and playerLevel >= level then return true end
		return
	end
	if profile.hideMetRequirements and not IsKeptRequirement(text) and not IsRed(lineData.leftColor) then
		return true
	end
end)

-- Shortened Use/Equip lines: the line Blizzard just added gets the short text; its colour stays.
-- Every line type: Forever types Equip lines None, so lines are known by their prefix too (Condense.KindOf).
local function ShortenLine(tooltip, lineData)
	if not ns.Active(tooltip) then return end
	-- Every line of every tooltip comes here, so nothing more unless something is to be shortened at all.
	local profile = ns.profile
	if not (profile.shortenUse or profile.shortenEquip or profile.shortenDps) then return end
	local text = lineData.leftText
	local kind = ns.Condense.KindOf(lineData.type, text)
	if not (kind and ns.profile[ns.Condense.OPTION[kind]]) then return end
	local short = ns.Condense.Shorten(text, kind)
	local index = short and ns.Readable(lineData.lineIndex)
	if not index then return end
	local line = ns.Line(tooltip, index)
	if line then ns.Editing(line.SetText, line, short) end
end

TooltipDataProcessor.AddLinePostCall(TooltipDataProcessor.AllTypes, ShortenLine)

-- A clean-up option changed: shown tooltips are rebuilt so it applies at once.
local CLEANUP = {}
for _, field in ipairs(ns.CLEANUP_FIELDS) do CLEANUP[field] = true end
ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil or CLEANUP[what] then ns.RefreshShownTooltips() end
end)
