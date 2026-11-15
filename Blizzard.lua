local _, ns = ...

-- Compacting Blizzard's own tooltips (design document 3.1 to 3.4), all through TooltipDataProcessor, so it reaches
-- every data-driven tooltip. A line pre-call returning true drops the line with no gap (2.1); a post-call changes
-- only the font string the line was drawn in. Nothing here writes into lineData or tooltipData (2.8).
--
-- Registered when the file loads: the callbacks do nothing until the profile is ready (ns.Active).

local LineType = Enum.TooltipDataLineType
local TooltipType = Enum.TooltipDataType

-- The tooltip's own data is an item (not a unit or spell that happens to show an item line).
local function IsItemTooltip(tooltip)
	local info = tooltip.GetProcessingTooltipInfo and tooltip:GetProcessingTooltipInfo()
	local data = info and info.tooltipData
	local dataType = data and data.type
	return not ns.IsSecret(dataType) and dataType ~= nil and dataType == TooltipType.Item
end

-- Sell price (3.1): the line has no text; Blizzard's own post-call writes the price, and is skipped with the line.
TooltipDataProcessor.AddLinePreCall(LineType.SellPrice, function(tooltip)
	if ns.Active(tooltip) and ns.profile.hideSellPrice then return true end
end)

-- Full durability (3.2) and a level requirement already met (3.3), matched on the game's own strings so they follow
-- the client's language. Their line type isn't known yet (Beta Checks 2), so this runs for every line and only acts
-- on item tooltips.
local DURABILITY = ns.PatternFromFormat(DURABILITY_TEMPLATE)
local MIN_LEVEL = ns.PatternFromFormat(ITEM_MIN_LEVEL)

TooltipDataProcessor.AddLinePreCall(TooltipDataProcessor.AllTypes, function(tooltip, lineData)
	if not ns.Active(tooltip) then return end
	local profile = ns.profile
	if not (profile.hideDurability or profile.hideMetLevel) then return end
	local text = lineData.leftText
	if ns.IsSecret(text) or text == nil or type(text) ~= "string" or not IsItemTooltip(tooltip) then return end

	if profile.hideDurability and DURABILITY then
		local current, maximum = text:match(DURABILITY)
		if current and tonumber(current) == tonumber(maximum) then return true end
	end
	if profile.hideMetLevel and MIN_LEVEL then
		local level = tonumber(text:match(MIN_LEVEL))
		local playerLevel = level and ns.Readable(UnitLevel("player"))
		if playerLevel and playerLevel >= level then return true end
	end
end)

-- Shortened Use/Equip lines (3.4): the line Blizzard just added gets the short text; its colour stays.
-- Every line type: Forever types Equip lines None (captured 15 Nov), so lines are known by their prefix too
-- (Condense.KindOf).
local function ShortenLine(tooltip, lineData)
	if not ns.Active(tooltip) then return end
	-- Every line of every tooltip comes here, so nothing more unless something is to be shortened at all.
	local profile = ns.profile
	if not (profile.shortenUse or profile.shortenEquip or profile.shortenDps) then return end
	local text = lineData.leftText
	local kind = ns.Condense.KindOf(lineData.type, text)
	if not (kind and ns.profile[ns.Condense.OPTION[kind]]) then return end
	local short = ns.Condense.Shorten(text, kind)
	local index = short and lineData.lineIndex
	if not index or ns.IsSecret(index) then return end
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
