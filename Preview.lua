local _, ns = ...

-- Preview tooltips for the options pages: CT's own tooltips made from GameTooltipTemplate, so
-- the whole data pipeline (Blizzard's rules, CT's callbacks, other addons' callbacks) runs on them exactly as on
-- GameTooltip. A "raw" preview is skipped by every CT callback, to show the game's own tooltip beside CT's.
--   ns.Preview.Create(parent, raw)                     a new preview tooltip, drawn at the parent's level
--   ns.Preview.Place(tooltip, owner, point, relativeTo, relativePoint, x, y)
--   ns.Preview.SAMPLES                                 sample items: { id, durability = { current, max }, setPieces,
--                                                      own, requirementsMet } (SampleData)
--   ns.Preview.ShowSample(tooltip, sample)              builds the tooltip for a sample
--   ns.Preview.LOOK_ITEM, SampleName(sample), WhenLoaded(id, fn), Backing(tooltip)

ns.Preview = {}
local Preview = ns.Preview

-- Sample items. The first five go through the Clean-up page's options in order, each showing the next ones: the ribs
-- the sell price and level requirement, the bandage the other requirements, the Hearthstone "Soulbound" and "Unique",
-- the staff durability, dps and the Equip lines, the armour kit the Use lines. The rest show more of the shortening
-- rules. Gear gets a full durability line, as the game shows none for an item you don't own; it has no API for an
-- unowned item's maximum durability and Forever's item data doesn't list it, so 100 is illustrative.
Preview.SAMPLES = {
	{ id = 2687 },  -- Dry Pork Ribs: sell price, a level requirement; Well Fed food with the XP bonus, a 1 second cooldown
	-- Heavy Silk Bandage: Requires First Aid (125), drawn as met; a bandage's Use line
	{ id = 6451, requirementsMet = true },
	-- The player's own Hearthstone, from their bags: "Soulbound" and "Unique"; its Use line
	{ id = 6948, own = true },
	{ id = 271767, durability = { 100, 100 } }, -- Healer's Staff: durability, dps, healing and spell damage, mana per 5
	{ id = 4265 },  -- Heavy Armor Kit: an armour kit's Use line with an item level ("ilvl")
	{ id = 12640, durability = { 100, 100 } }, -- Lionheart Helm: crit, hit, Requires Level 57
	{ id = 2816, durability = { 100, 100 } },  -- Death Speaker Scepter: Shadow damage, healing, health per 5
	-- Scarlet Leggings: drawn as if 4 pieces of the set were worn, so the first bonuses show active ("Set:", resist,
	-- attack power vs Undead) and the later ones inactive ("(N) Set:", hit)
	{ id = 10330, durability = { 100, 100 }, setPieces = 4 },
	{ id = 3078, durability = { 100, 100 } },  -- a weapon with "Chance on hit:" and a second sentence; dps
	{ id = 282283, durability = { 100, 100 } }, -- Malignant Root: attack power, spell power
}

local LineType = Enum.TooltipDataLineType

-- A sample's tooltip data: the item's own, with the sample's extras. A copy of the line list (changed lines are new
-- tables), so the game's own data isn't written to; Blizzard's pipeline builds the preview from it as from any other
-- data, so every rule and callback runs on it.
--   durability = { current, max }   a durability line where the game puts it (before the requirements and sell price)
--   setPieces = n                    the item's set drawn as if n pieces were worn: the header's count, n pieces listed
--                                    as worn (this item first), and the bonuses for n or fewer pieces active
--   own = true                       the player's own copy, from their bags ("Soulbound", its own GUID); without one,
--                                    drawn as owned ("Soulbound", and counted as owned for "Unique": data.ctOwned)
--   requirementsMet = true           requirements other than class, race and level drawn as met (white, not red)
local AFTER_DURABILITY = { [LineType.UsageRequirement] = true, [LineType.SellPrice] = true }

-- Patterns from the game's own strings: "Chain of the Scarlet Crusade (0/6)" and "(3) Set: ...".
local SET_NAME = ns.PatternFromFormat(ITEM_SET_NAME)            -- name, worn, total
local SET_BONUS_GRAY = ns.PatternFromFormat(ITEM_SET_BONUS_GRAY) -- pieces, text
-- A worn piece in the set's list: Classic's colour for it (light yellow), which reads like a real worn set in game.
local SET_WORN_COLOR = CreateColor(1, 1, 0.6)

local function CopyLine(line, changes)
	local copy = {}
	for key, value in pairs(line) do copy[key] = value end
	for key, value in pairs(changes) do copy[key] = value end
	return copy
end

local function WithSetPieces(lines, worn)
	local name = lines[1] and lines[1].leftText
	local inList, listed = false, 0
	for i, line in ipairs(lines) do
		local text = ns.Readable(line.leftText)
		if type(text) == "string" then
			-- (Two statements each: "x and f()" would keep only f's first result.)
			local setName, wornNow, total, pieces, bonus
			if SET_NAME then setName, wornNow, total = text:match(SET_NAME) end
			if SET_BONUS_GRAY then pieces, bonus = text:match(SET_BONUS_GRAY) end
			if setName and total then
				lines[i] = CopyLine(line, { leftText = ITEM_SET_NAME:format(setName, math.min(worn, tonumber(total)),
					tonumber(total)) })
				inList, listed = true, 0
			elseif pieces then
				inList = false
				if tonumber(pieces) <= worn and ITEM_SET_BONUS then
					lines[i] = CopyLine(line, { leftText = ITEM_SET_BONUS:format(bonus), leftColor = GREEN_FONT_COLOR })
				end
			elseif inList and text:find("%S") then
				-- This item first, then the others in order, up to the pieces worn.
				local isThis = name and strtrim(text) == name
				if isThis or listed < worn - 1 then
					if not isThis then listed = listed + 1 end
					lines[i] = CopyLine(line, { leftColor = SET_WORN_COLOR })
				end
			elseif inList then
				inList = false
			end
		end
	end
end

-- The tooltip data of the player's own copy of an item, from their bags, or nil.
local function OwnCopy(id)
	if not (C_Container and C_Container.GetContainerNumSlots and C_TooltipInfo.GetBagItem) then return nil end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			if C_Container.GetContainerItemID(bag, slot) == id then return C_TooltipInfo.GetBagItem(bag, slot) end
		end
	end
	return nil
end

-- A requirement Hide other requirements you meet acts on: not the level one (its own option), and not one that always
-- shows (class, race, a level range; Blizzard.lua's list).
local function IsOtherRequirement(line)
	local text = ns.Readable(line.leftText)
	if line.type ~= LineType.UsageRequirement or type(text) ~= "string" then return false end
	local minLevel = ns.Blizzard.patterns.minLevel
	if minLevel and text:find(minLevel) then return false end
	return not ns.Blizzard.IsKeptRequirement(text)
end

local function SampleData(sample)
	local own = sample.own and OwnCopy(sample.id)
	local data = own or C_TooltipInfo.GetItemByID(sample.id)
	if not (data and data.lines) then return nil end
	local lines = {}
	for i, line in ipairs(data.lines) do lines[i] = line end
	if sample.setPieces then WithSetPieces(lines, sample.setPieces) end
	-- Not in the bags: drawn as the player's own, as a set is drawn as worn.
	local drawnOwned = sample.own and not own
	for i, line in ipairs(lines) do
		if drawnOwned and line.type == LineType.ItemBinding and ITEM_SOULBOUND then
			lines[i] = CopyLine(line, { leftText = ITEM_SOULBOUND })
		elseif sample.requirementsMet and IsOtherRequirement(line) then
			lines[i] = CopyLine(line, { leftColor = HIGHLIGHT_FONT_COLOR })
		end
	end
	if sample.durability and DURABILITY_TEMPLATE then
		local durability = { type = LineType.None, leftColor = HIGHLIGHT_FONT_COLOR,
			leftText = DURABILITY_TEMPLATE:format(sample.durability[1], sample.durability[2]) }
		local at = #lines + 1
		for i, line in ipairs(lines) do
			if AFTER_DURABILITY[line.type] then
				at = i
				break
			end
		end
		table.insert(lines, at, durability)
	end
	local copy = {}
	for key, value in pairs(data) do copy[key] = value end
	copy.lines = lines
	copy.ctOwned = drawnOwned or nil -- CT's own copy of the data, so its own marker; Blizzard.lua's IsOwned reads it
	return copy
end

-- The Look page's item: Lionheart Helm, an epic, for the quality border.
Preview.LOOK_ITEM = 12640

-- With a getter, not the data itself: when the item's data arrives later (TOOLTIP_DATA_UPDATE), the tooltip's refresh
-- calls the getter again and gets the whole item, durability line and all. Handed only data, the refresh reuses what
-- it has, so a sample first shown before its item loaded stays half built.
function Preview.ShowSample(tooltip, sample)
	if sample.durability or sample.setPieces or sample.own or sample.requirementsMet then
		tooltip:ProcessInfo({ getterFunction = function() return SampleData(sample) end })
	else
		tooltip:SetItemByID(sample.id)
	end
end

-- Calls fn once the item's data is cached (at once if it is), for names and tooltips that need it.
function Preview.WhenLoaded(id, fn)
	if C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(id) then return fn() end
	if Item and Item.CreateFromItemID then
		Item:CreateFromItemID(id):ContinueOnItemLoad(fn)
	elseif C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(id)
	end
end

function Preview.SampleName(sample)
	local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(sample.id)
	if type(name) == "string" and name ~= "" then return name end
	return ns.L.SAMPLE_ITEM:format(sample.id)
end

local count = 0
local previewTooltips = setmetatable({}, { __mode = "k" }) -- every preview, for the backing (below)

function Preview.Create(parent, raw)
	count = count + 1
	local tooltip = CreateFrame("GameTooltip", "CleanTooltipsPreview" .. count, parent, "GameTooltipTemplate")
	if raw then
		ns.raw[tooltip] = true
	else
		ns.Style.Watch(tooltip)
		ns.Style.WatchHealthBar(tooltip.StatusBar)
	end
	-- GameTooltipTemplate answers TOOLTIP_DATA_UPDATE by asking for a refresh on its next update, but only the game's
	-- own tooltips have the OnUpdate that does it; without this a preview never catches up with item data that arrives
	-- after it was first drawn.
	tooltip:SetScript("OnUpdate", function(self)
		if self.shouldRefreshData then self:RefreshData() end
	end)
	-- An opaque backing under its background (Preview.Backing, below), kept in step with the background piece.
	previewTooltips[tooltip] = true
	Preview.Backing(tooltip)
	tooltip:HookScript("OnShow", function(self) Preview.Backing(self) end)
	-- The page grows to fit it (Options.lua).
	tooltip:HookScript("OnSizeChanged", function()
		local fit = parent and rawget(parent, "FitHeight")
		if fit then fit(parent) end
	end)
	return tooltip
end

-- An opaque backing inside each preview, exactly under its background. Forever's tooltip background art is only 76%
-- opaque (alpha 195 of 255 in Tooltip-NineSlice-Center), so a tooltip always shows a quarter of what's behind it; over
-- the options panel that's the panel, which makes the previews' background look wrong. The backing is a flat,
-- mid-toned Forever brown: the hue of the game's own inset frame art (common-insideframe), as bright as an average
-- outdoor scene (mean brightness 0.31). It sits on the tooltip's NineSlice, the
-- same size as its Center piece and drawn just beneath it, so it covers exactly the area the game's own background
-- does and the border's corners draw over it as they do over the background. A chosen background transparency still
-- shows.
local BACKING_COLOR = { 0.40, 0.30, 0.19 } -- Forever's inset-frame brown, luminance 0.31

local function Backing(tooltip)
	local nineSlice = tooltip.NineSlice
	local center = nineSlice and rawget(nineSlice, "Center")
	if not center then return end -- laid out on the tooltip's first style; tried again when it's shown
	local backing = rawget(tooltip, "ctBacking")
	if not backing then
		backing = nineSlice:CreateTexture(nil, "BACKGROUND", nil, -8)
		backing:SetColorTexture(BACKING_COLOR[1], BACKING_COLOR[2], BACKING_COLOR[3], 1)
		tooltip.ctBacking = backing
	end
	backing:ClearAllPoints()
	backing:SetAllPoints(center)
	backing:SetShown(center:IsShown())
end
Preview.Backing = Backing

-- The Center piece may first appear when the tooltip's style is applied (after its first OnShow), so the backing is
-- attached then too.
hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
	if previewTooltips[tooltip] then Backing(tooltip) end
end)

-- Owns the tooltip by `owner` (its page) and puts it in place, below the page's own popups and menus.
function Preview.Place(tooltip, owner, ...)
	tooltip:SetOwner(owner, "ANCHOR_NONE")
	tooltip:ClearAllPoints()
	tooltip:SetPoint(...)
	tooltip:SetFrameStrata(owner:GetFrameStrata())
	tooltip:SetFrameLevel(owner:GetFrameLevel() + 10)
end
