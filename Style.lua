local _, ns = ...

-- The tooltip's look: class-coloured player names, border colours, the health bar's
-- texture, the font and the background. Only post-hooks, TooltipDataProcessor callbacks and colour/texture calls on
-- the tooltip's own pieces; nothing Blizzard's is replaced.
--   ns.Style.Watch(tooltip)   styles a tooltip the hooks below wouldn't otherwise reach (CT's previews)
--   ns.Style.SetBorder(tooltip, color), SetBorderGrey(nineSlice, grey), IsBorderGrey(nineSlice)
--   ns.Style.WatchHealthBar(bar), MediaNames(mediaType)

ns.Style = {}
local Style = ns.Style

local LSM = LibStub("LibSharedMedia-3.0", true)
local LineType = Enum.TooltipDataLineType
local TooltipType = Enum.TooltipDataType
local UNCOMMON = Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2

local unitOf = setmetatable({}, { __mode = "k" })  -- [tooltip] = the unit on its name line
local border = setmetatable({}, { __mode = "k" })  -- [tooltip] = the border colour CT wants, while it wants one
local tinted = setmetatable({}, { __mode = "k" })  -- [tooltip] = true while CT has changed its border
local shaded = setmetatable({}, { __mode = "k" })  -- [tooltip] = true while CT has changed its background
local seen = setmetatable({}, { __mode = "k" })    -- every tooltip styled so far, for applying a changed option
local defaultBorder = setmetatable({}, { __mode = "k" }) -- [NineSlice] = { r, g, b, a } before CT changed it
local applying = false                               -- CT's own colour calls, which the colour hooks let through

-- Colours --------------------------------------------------------------------------------------------------------------

local function ClassColor(unit)
	if not ns.True(UnitIsPlayer(unit)) then return nil end
	local _, class = UnitClass(unit)
	class = ns.Readable(class)
	if class == nil then return nil end
	return (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
end

-- Blizzard draws a player's name red when each of you can attack the other (GameTooltip_UnitColor). nil: unknown.
local function IsHostilePlayer(unit)
	local theyCan, youCan = UnitCanAttack(unit, "player"), UnitCanAttack("player", unit)
	if ns.IsSecret(theyCan) or ns.IsSecret(youCan) then return nil end -- before either is compared
	return theyCan == true and youCan == true
end

local function ReactionColor(unit)
	local reaction = ns.Readable(UnitReaction(unit, "player"))
	if reaction == nil then return nil end
	return FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
end

local function QualityColor(data)
	local item = ns.Readable(data.hyperlink) or ns.Readable(data.id)
	if item == nil then return nil end
	local quality = C_Item.GetItemQualityByID(item)
	-- Poor and common items keep the plain border: colouring them adds nothing.
	if type(quality) ~= "number" or quality < UNCOMMON then return nil end
	return ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
end

-- Player names ---------------------------------------------------------------------------------------------------------
-- Blizzard's own pre-call has coloured the name by reaction (players white); a player's becomes their class colour.

TooltipDataProcessor.AddLinePostCall(LineType.UnitName, function(tooltip, lineData)
	local unit = ns.Readable(lineData.unitToken)
	if unit == nil then return end
	unitOf[tooltip] = unit
	if not (ns.Active(tooltip) and ns.profile.classNames) then return end
	local color = ClassColor(unit)
	if not color then return end
	if ns.profile.hostileRed and IsHostilePlayer(unit) ~= false then return end
	local index = ns.Readable(lineData.lineIndex)
	local line = index and ns.Line(tooltip, index)
	if line then line:SetTextColor(color.r, color.g, color.b) end
end)

-- Borders and background ----------------------------------------------------------------------------------------------
-- SharedTooltip_SetBackdropStyle puts the game's colours back whenever a tooltip is shown or hidden, and other
-- addons may set them too, so CT's colours are put back after each (as TipTac does).

-- Forever's tooltip border art is gold (its bright edges about 0.97, 0.86, 0.69), and a border colour multiplies it,
-- so a quality colour comes out darker and duller than the item's name. While CT colours a border, its pieces are desaturated to grey and the colour is lifted by the art's brightness (0.87, capped at 1),
-- so the border matches the name; the game's own border gets its gold art back.
local BORDER_PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
	"BottomEdge", "LeftEdge", "RightEdge" }
local BORDER_ART_BRIGHTNESS = 0.87

-- Grey (desaturated) border art, or the game's gold; and whether a border has it grey now.
function Style.SetBorderGrey(nineSlice, grey)
	for _, name in ipairs(BORDER_PIECES) do
		local piece = rawget(nineSlice, name)
		if piece and piece.SetDesaturated then piece:SetDesaturated(grey == true) end
	end
end

function Style.IsBorderGrey(nineSlice)
	local piece = rawget(nineSlice, "TopEdge")
	return piece ~= nil and piece.IsDesaturated ~= nil and piece:IsDesaturated() == true
end

local function SetBorder(nineSlice, r, g, b, a, ours)
	Style.SetBorderGrey(nineSlice, ours)
	if ours then
		r = math.min(1, r / BORDER_ART_BRIGHTNESS)
		g = math.min(1, g / BORDER_ART_BRIGHTNESS)
		b = math.min(1, b / BORDER_ART_BRIGHTNESS)
	end
	applying = true
	nineSlice:SetBorderColor(r, g, b, a)
	applying = false
end

local function ApplyBorder(tooltip)
	local nineSlice = tooltip.NineSlice
	if not nineSlice or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
	local color = border[tooltip]
	if color then
		if not defaultBorder[nineSlice] then defaultBorder[nineSlice] = { nineSlice:GetBorderColor() } end
		SetBorder(nineSlice, color.r, color.g, color.b, 1, true)
		tinted[tooltip] = true
	elseif tinted[tooltip] then
		local original = defaultBorder[nineSlice] or {}
		SetBorder(nineSlice, original[1] or 1, original[2] or 1, original[3] or 1, original[4] or 1)
		tinted[tooltip] = nil
	end
end

local function ApplyBackground(tooltip)
	local nineSlice = tooltip.NineSlice
	if not nineSlice or (tooltip.IsForbidden and tooltip:IsForbidden()) or ns.raw[tooltip] then return end
	local color = ns.profile and ns.profile.background
	applying = true
	if type(color) == "table" then
		nineSlice:SetCenterColor(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
		shaded[tooltip] = true
	elseif shaded[tooltip] then
		local r, g, b = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
		nineSlice:SetCenterColor(r, g, b, 1)
		shaded[tooltip] = nil
	end
	applying = false
end

local function Forget(tooltip)
	unitOf[tooltip] = nil
	if border[tooltip] then
		border[tooltip] = nil
		ApplyBorder(tooltip)
	end
end

function Style.Watch(tooltip)
	if seen[tooltip] or not tooltip.NineSlice then return end
	seen[tooltip] = true
	local nineSlice = tooltip.NineSlice
	hooksecurefunc(nineSlice, "SetBorderColor", function()
		if not applying and border[tooltip] then ApplyBorder(tooltip) end
	end)
	hooksecurefunc(nineSlice, "SetCenterColor", function()
		if not applying and ns.profile and ns.profile.background then ApplyBackground(tooltip) end
	end)
	tooltip:HookScript("OnHide", Forget)
	tooltip:HookScript("OnTooltipCleared", Forget)
	ApplyBackground(tooltip)
end

-- A border colour for a tooltip the data pipeline doesn't build (the Look page's sample names); nil for the game's.
function Style.SetBorder(tooltip, color)
	Style.Watch(tooltip)
	border[tooltip] = color
	ApplyBorder(tooltip)
end

local function BorderColor(tooltip, profile)
	local data = tooltip.GetPrimaryTooltipData and tooltip:GetPrimaryTooltipData()
	local dataType = data and ns.Readable(data.type)
	if dataType == nil then return nil end
	if dataType == TooltipType.Unit then
		local unit = unitOf[tooltip]
		if not unit then return nil end
		if ns.True(UnitIsPlayer(unit)) then
			return profile.borderClass and ClassColor(unit) or nil
		end
		return profile.borderReaction and ReactionColor(unit) or nil
	elseif dataType == TooltipType.Item then
		return profile.borderQuality and QualityColor(data) or nil
	end
end

TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip)
	if not ns.Active(tooltip) then return end
	Style.Watch(tooltip)
	local profile = ns.profile
	local color
	if profile.borderClass or profile.borderReaction or profile.borderQuality then
		color = BorderColor(tooltip, profile)
	end
	border[tooltip] = color
	ApplyBorder(tooltip)
end)

hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
	if not ns.Active(tooltip) then return end
	Style.Watch(tooltip)
	ApplyBorder(tooltip)
	ApplyBackground(tooltip)
end)

-- Health bar -----------------------------------------------------------------------------------------------------------
-- SetStatusBarTexture once, then the texture itself for later changes: setting the bar's texture again makes it
-- flicker. The bar's colour stays Blizzard's.

local bars = {}            -- every health bar styled: GameTooltip's and the previews'
local barOriginal = {}     -- [bar] = its texture before CT changed it
local barSet = {}          -- [bar] = true once CT has set its texture

local function Fetch(mediaType, name)
	return name and LSM and LSM:Fetch(mediaType, name, true) or nil
end

local function ApplyHealthBar(bar)
	local path = Fetch("statusbar", ns.profile and ns.profile.healthBar)
	if not path and not barSet[bar] then return end
	local texture = bar:GetStatusBarTexture()
	if barOriginal[bar] == nil then
		barOriginal[bar] = texture and texture:GetTexture() or "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
	end
	path = path or barOriginal[bar]
	if barSet[bar] and texture then
		texture:SetTexture(path)
	else
		bar:SetStatusBarTexture(path)
		barSet[bar] = true
	end
end

function Style.WatchHealthBar(bar)
	if not bar then return end
	for _, known in ipairs(bars) do
		if known == bar then return end
	end
	bars[#bars + 1] = bar
	if ns.profile then ApplyHealthBar(bar) end
end

-- Font -----------------------------------------------------------------------------------------------------------------
-- The three font objects every tooltip line inherits. Each keeps its own size and outline.

local FONT_OBJECTS = { "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }
local originalFonts = {}
local fontChanged = false

local function ApplyFont()
	local path = Fetch("font", ns.profile and ns.profile.font)
	if not path and not fontChanged then return end
	for _, name in ipairs(FONT_OBJECTS) do
		local fontObject = _G[name]
		if fontObject then
			if not originalFonts[name] then originalFonts[name] = { fontObject:GetFont() } end
			local original = originalFonts[name]
			fontObject:SetFont(path or original[1], original[2], original[3])
		end
	end
	fontChanged = path ~= nil
end

-- Applying -------------------------------------------------------------------------------------------------------------

local function ApplyBackgrounds()
	for tooltip in pairs(seen) do ApplyBackground(tooltip) end
end

local function ApplyHealthBars()
	for _, bar in ipairs(bars) do ApplyHealthBar(bar) end
end

local REBUILD = { classNames = true, hostileRed = true, borderClass = true, borderReaction = true, borderQuality = true }

ns.Listen("DB_READY", function()
	for _, name in ipairs(ns.TOOLTIPS) do
		if _G[name] then Style.Watch(_G[name]) end
	end
	Style.WatchHealthBar(GameTooltipStatusBar or (GameTooltip and GameTooltip.StatusBar))
	ApplyFont()
	ApplyHealthBars()
	ApplyBackgrounds()
	-- Fonts and textures other addons register later are picked up when they arrive.
	if LSM then
		LSM.RegisterCallback(Style, "LibSharedMedia_Registered", function(_, mediaType, key)
			local profile = ns.profile
			if mediaType == "font" and key == profile.font then ApplyFont() end
			if mediaType == "statusbar" and key == profile.healthBar then ApplyHealthBars() end
		end)
	end
end)

ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil or what == "font" then ApplyFont() end
	if what == nil or what == "healthBar" then ApplyHealthBars() end
	if what == nil or what == "background" then ApplyBackgrounds() end
	if what == nil or REBUILD[what] then ns.RefreshShownTooltips() end
end)

-- For the options' dropdowns: the names LibSharedMedia knows of a type, sorted.
function Style.MediaNames(mediaType)
	return LSM and LSM:List(mediaType) or {}
end
