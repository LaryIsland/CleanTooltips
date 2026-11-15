local _, ns = ...
local L = ns.L

-- Options > AddOns > Clean Tooltips (design document 5). Clean-up, Look and Sources are canvas pages, CT's own frames,
-- so each can show live preview tooltips beside its options; Profiles is a list page built with the game's own
-- Settings controls. Every option applies at once, to the previews and to tooltips already shown. The Defaults button
-- resets the page shown. Removal rules are the player's own list, not settings, so Defaults leaves them alone (Reset
-- Profile clears them).
--   ns.Options.Open(page)   page: nil (Clean-up), "look", "sources", "last" (Sources on the last tooltip), "profiles"

ns.Options = {}
local Options = ns.Options

local TITLE = "Clean Tooltips"
local POPUP_PREFIX = "CLEANTOOLTIPS_"
local NAME_LETTERS = 32

local LEFT = 16          -- the pages' left margin
local TOP = -56          -- the first row, under the page's title
local ROW = 28           -- one checkbox row
local INDENT = 24        -- a checkbox that depends on the one above
local LABEL_WIDTH = 150  -- a dropdown's or swatch's label, before its control
local PREVIEW_X = 330    -- the Look page's previews, right of its options
local LIST_WIDTH = 240   -- the Sources page's list; the current tooltip is to the right
local ADVICE_WIDTH = 600 -- the Sources page's advice note, across the page
local MENU_HEIGHT = 320  -- long dropdown menus scroll past this

local categories = {}    -- [page key] = the Settings category
local pages = {}         -- every canvas page
local sourcesMode = "addons"

-- Refusing in combat --------------------------------------------------------------------------------------------------
-- The game's options panel isn't safe to open from addon code in combat.

local function RefuseInCombat()
	if not ns.InCombat() then return false end
	local text = ERR_NOT_IN_COMBAT or L.OPT_IN_COMBAT
	if UIErrorsFrame and UIErrorsFrame.AddExternalErrorMessage then
		UIErrorsFrame:AddExternalErrorMessage(text)
	else
		ns.Print(text)
	end
	return true
end

-- Widgets --------------------------------------------------------------------------------------------------------------

local function ShowTip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, title)
	GameTooltip_AddNormalLine(GameTooltip, text, true)
	GameTooltip:Show()
end

local function HideTip()
	GameTooltip:Hide()
end

-- Only options with something to add get a tooltip: a bare repeat of the label tells nothing.
local function AddTip(frame, title, text)
	if not text then return end
	frame:SetScript("OnEnter", function(self) ShowTip(self, title, text) end)
	frame:SetScript("OnLeave", HideTip)
end

local function Text(parent, font, text)
	local fontString = parent:CreateFontString(nil, "ARTWORK", font)
	fontString:SetJustifyH("LEFT")
	if text then fontString:SetText(text) end
	return fontString
end

local function Check(parent, text, tip)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	local label = rawget(check, "Text")
	if not label then
		label = check:CreateFontString(nil, "ARTWORK")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
	end
	label:SetFontObject(GameFontHighlight)
	label:SetJustifyH("LEFT")
	check.label = label
	function check:SetLabel(newText)
		label:SetText(newText)
		self:SetHitRectInsets(0, -math.min(label:GetUnboundedStringWidth(), 400), 0, 0)
	end
	function check:SetActive(on)
		self:SetEnabled(on)
		label:SetFontObject(on and GameFontHighlight or GameFontDisable)
	end
	check:SetLabel(text or "")
	AddTip(check, text, tip)
	return check
end

local function ClickSound(checked)
	PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

-- A page scrolls: everything on it (options and preview tooltips) is built on `page`, the scroll child, which grows to
-- fit whatever reaches lowest, so a tall preview never runs off the panel. `page.canvas` is the frame registered with
-- the Settings panel.
local SCROLLBAR_GAP = 26 -- room for the scroll bar, right of the page
local FIT_MARGIN = 16    -- below the lowest thing on the page

local function NewPage(title)
	local canvas = CreateFrame("Frame")
	canvas:Hide()
	local scroll = CreateFrame("ScrollFrame", nil, canvas, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_GAP, 0)
	if scroll.ScrollBar and scroll.ScrollBar.SetHideIfUnscrollable then scroll.ScrollBar:SetHideIfUnscrollable(true) end
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(1, 1)
	scroll:SetScrollChild(page)
	page.canvas, page.scroll, canvas.page = canvas, scroll, page
	page.refreshers = {}
	local heading = Text(page, "GameFontHighlightHuge", title)
	heading:SetPoint("TOPLEFT", 7, -16)

	-- As tall as the lowest thing on it, and never shorter than the visible area. Once a frame, however often asked.
	local fitQueued = false
	local function Fit()
		fitQueued = false
		local top = page:GetTop()
		if not top then return end
		local lowest = top
		local function Consider(thing)
			if thing:IsShown() then
				local bottom = thing:GetBottom()
				if bottom and bottom < lowest then lowest = bottom end
			end
		end
		for _, child in ipairs({ page:GetChildren() }) do Consider(child) end
		for _, region in ipairs({ page:GetRegions() }) do Consider(region) end
		page:SetHeight(math.max(top - lowest + FIT_MARGIN, scroll:GetHeight() or 1))
	end
	function page:FitHeight()
		if fitQueued then return end
		fitQueued = true
		C_Timer.After(0, Fit)
	end
	scroll:SetScript("OnSizeChanged", function(_, width)
		page:SetWidth(width)
		page:FitHeight()
	end)

	function page:Refresh()
		if not ns.profile then return end
		for _, refresh in ipairs(self.refreshers) do refresh() end
		local draw = rawget(self, "Draw") -- the pages with previews have one; Profiles doesn't
		if draw then ns.SafeCall("preview", draw, self) end
		self:FitHeight()
	end
	-- The Settings panel calls these on the registered frame.
	canvas.OnRefresh = function() page:Refresh() end
	canvas.OnDefault = function()
		local default = rawget(page, "OnDefault")
		if default then default(page) end
	end
	canvas:SetScript("OnShow", function() page:Refresh() end)
	pages[#pages + 1] = page
	return page
end

-- A checkbox for one of the profile's true/false options.
local function FieldCheck(page, field, text, tip, x, y)
	local check = Check(page, text, tip)
	check:SetPoint("TOPLEFT", x, y)
	check:SetScript("OnClick", function(self)
		local on = self:GetChecked() == true
		ClickSound(on)
		ns.profile[field] = on
		ns.Changed(field)
	end)
	table.insert(page.refreshers, function() check:SetChecked(ns.profile[field] == true) end)
	return check
end

-- A labelled dropdown. choices() gives { { value, text }, ... }.
local function Dropdown(page, labelText, width, choices, get, set, x, y)
	local label = Text(page, "GameFontHighlight", labelText)
	label:SetPoint("TOPLEFT", x, y - 7)
	local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("TOPLEFT", x + LABEL_WIDTH, y)
	dropdown:SetWidth(width)
	dropdown:SetupMenu(function(_, root)
		root:SetScrollMode(MENU_HEIGHT)
		for _, choice in ipairs(choices()) do
			root:CreateRadio(choice.text, function() return get() == choice.value end, function()
				set(choice.value)
			end)
		end
	end)
	table.insert(page.refreshers, function() dropdown:GenerateMenu() end)
	return dropdown
end

local function DefaultsOf(fields)
	for _, field in ipairs(fields) do
		local default = ns.PROFILE_DEFAULTS[field]
		ns.profile[field] = type(default) == "table" and CopyTable(default) or default
	end
	ns.Changed(nil)
end

-- Clean-up (design document 3.1 to 3.4) --------------------------------------------------------------------------------

local CLEANUP_FIELDS = ns.CLEANUP_FIELDS -- Core.lua

local function BuildCleanup()
	local page = NewPage(TITLE)
	local y = TOP
	-- In the order the samples show them: the food (sell price, a level requirement met, its Use line and 1 second
	-- cooldown), the potion (Use), the helm (Equip lines, durability), then the weapons (dps).
	FieldCheck(page, "hideSellPrice", L.OPT_SELL_PRICE, L.OPT_SELL_PRICE_TIP, LEFT, y)
	y = y - ROW
	FieldCheck(page, "hideMetLevel", L.OPT_LEVEL, L.OPT_LEVEL_TIP, LEFT, y)
	y = y - ROW
	FieldCheck(page, "shortenUse", L.OPT_SHORTEN_USE, L.OPT_SHORTEN_USE_TIP, LEFT, y)
	y = y - ROW
	local oneSecond = FieldCheck(page, "hideSecondCooldown", L.OPT_HIDE_SECOND_COOLDOWN,
		L.OPT_HIDE_SECOND_COOLDOWN_TIP, LEFT + INDENT, y)
	table.insert(page.refreshers, function() oneSecond:SetActive(ns.profile.shortenUse == true) end)
	y = y - ROW
	FieldCheck(page, "shortenEquip", L.OPT_SHORTEN_EQUIP, L.OPT_SHORTEN_EQUIP_TIP, LEFT, y)
	y = y - ROW
	local noPrefix = FieldCheck(page, "dropEquipPrefix", L.OPT_DROP_EQUIP_PREFIX, L.OPT_DROP_EQUIP_PREFIX_TIP,
		LEFT + INDENT, y)
	table.insert(page.refreshers, function() noPrefix:SetActive(ns.profile.shortenEquip == true) end)
	y = y - ROW
	FieldCheck(page, "hideDurability", L.OPT_DURABILITY, L.OPT_DURABILITY_TIP, LEFT, y)
	y = y - ROW
	FieldCheck(page, "shortenDps", L.OPT_SHORTEN_DPS, L.OPT_SHORTEN_DPS_TIP, LEFT, y)
	y = y - ROW - 12

	local sample = 1
	Dropdown(page, L.OPT_SAMPLE, 200, function()
		local list = {}
		for i, item in ipairs(ns.Preview.SAMPLES) do
			list[i] = { value = i, text = ns.Preview.SampleName(item) }
		end
		return list
	end, function() return sample end, function(value)
		sample = value
		page:Draw()
	end, LEFT, y)
	y = y - ROW - 16

	-- The game's tooltip and CT's, side by side.
	local gameLabel = Text(page, "GameFontNormal", L.PREVIEW_GAME)
	gameLabel:SetPoint("TOPLEFT", LEFT, y)
	local cleanLabel = Text(page, "GameFontNormal", TITLE)
	local raw = ns.Preview.Create(page, true)
	local clean = ns.Preview.Create(page)

	-- The first time the page is drawn, every sample's item data is asked for, and the page is drawn again as each
	-- arrives: the dropdown gets the item's name, and the previews the whole item.
	local requested = false
	local RefreshSoon = ns.Throttled(function()
		if page:IsVisible() then page:Refresh() end
	end)
	local function RequestSamples()
		requested = true
		for _, item in ipairs(ns.Preview.SAMPLES) do
			if not (C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(item.id)) then
				ns.Preview.WhenLoaded(item.id, RefreshSoon)
			end
		end
	end

	function page:Draw()
		if not self:IsVisible() then return end
		if not requested then RequestSamples() end
		local item = ns.Preview.SAMPLES[sample]
		ns.Preview.Place(raw, self, "TOPLEFT", gameLabel, "BOTTOMLEFT", 0, -6)
		ns.Preview.ShowSample(raw, item)
		ns.Preview.Place(clean, self, "TOPLEFT", raw, "TOPRIGHT", 16, 0)
		ns.Preview.ShowSample(clean, item)
		cleanLabel:ClearAllPoints()
		cleanLabel:SetPoint("BOTTOMLEFT", clean, "TOPLEFT", 0, 6)
	end

	function page:OnDefault() DefaultsOf(CLEANUP_FIELDS) end
	return page
end

-- Look (3.5 to 3.9) --------------------------------------------------------------------------------------------------

local LOOK_FIELDS = { "classNames", "hostileRed", "borderClass", "borderReaction", "borderQuality", "healthBar", "font",
	"background" }

local function MediaChoices(mediaType)
	return function()
		local list = { { value = "", text = L.OPT_GAME_DEFAULT } }
		for _, name in ipairs(ns.Style.MediaNames(mediaType)) do
			list[#list + 1] = { value = name, text = name }
		end
		return list
	end
end

local function MediaDropdown(page, field, mediaType, labelText, y)
	return Dropdown(page, labelText, 150, MediaChoices(mediaType),
		function() return ns.profile[field] or "" end,
		function(value)
			ns.profile[field] = value ~= "" and value or false
			ns.Changed(field)
		end, LEFT, y)
end

local function BackgroundColor()
	local color = ns.profile.background
	if type(color) == "table" then return color.r or 0, color.g or 0, color.b or 0, color.a or 1 end
	local r, g, b = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
	return r, g, b, 1
end

local function SetBackground(color)
	ns.profile.background = color or false
	ns.Changed("background")
end

local function BackgroundSwatch(page, y)
	local label = Text(page, "GameFontHighlight", L.OPT_BACKGROUND)
	label:SetPoint("TOPLEFT", LEFT, y - 7)
	local swatch = CreateFrame("Button", nil, page)
	swatch:SetSize(22, 22)
	swatch:SetPoint("TOPLEFT", LEFT + LABEL_WIDTH, y - 2)
	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.7, 0.7, 0.7, 1)
	local fill = swatch:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)

	local function Picked()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		SetBackground({ r = r, g = g, b = b, a = ColorPickerFrame:GetColorAlpha() })
	end
	swatch:SetScript("OnClick", function()
		local r, g, b, a = BackgroundColor()
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, opacity = a, hasOpacity = true,
			swatchFunc = Picked, opacityFunc = Picked,
			cancelFunc = function(previous)
				SetBackground({ r = previous.r, g = previous.g, b = previous.b, a = previous.a })
			end,
		})
	end)
	AddTip(swatch, L.OPT_BACKGROUND, L.OPT_BACKGROUND_TIP)

	-- Back to the game's own, shown only while a colour is chosen.
	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetText(L.OPT_BACKGROUND_RESET)
	reset:SetSize(math.max(80, reset:GetFontString():GetUnboundedStringWidth() + 30), 22)
	reset:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
	reset:SetScript("OnClick", function() SetBackground(false) end)

	table.insert(page.refreshers, function()
		local r, g, b, a = BackgroundColor()
		fill:SetColorTexture(r, g, b, a)
		reset:SetShown(type(ns.profile.background) == "table")
	end)
end

-- Sample name lines for what can't be previewed with a real unit (design document 5): a hostile player and an NPC.
local function DrawSample(tooltip, page, anchor, text, color, borderColor)
	ns.Preview.Place(tooltip, page, "TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	tooltip:SetText(text, color.r, color.g, color.b)
	tooltip:Show()
	ns.Style.SetBorder(tooltip, borderColor)
end

local function BuildLook()
	local page = NewPage(L.PAGE_LOOK)
	local y = TOP
	FieldCheck(page, "classNames", L.OPT_CLASS_NAMES, L.OPT_CLASS_NAMES_TIP, LEFT, y)
	y = y - ROW
	local hostile = FieldCheck(page, "hostileRed", L.OPT_HOSTILE_RED, L.OPT_HOSTILE_RED_TIP, LEFT + INDENT, y)
	table.insert(page.refreshers, function() hostile:SetActive(ns.profile.classNames == true) end)
	y = y - ROW - 10

	local borders = Text(page, "GameFontNormal", L.OPT_BORDERS)
	borders:SetPoint("TOPLEFT", LEFT, y)
	y = y - 20
	FieldCheck(page, "borderClass", L.OPT_BORDER_CLASS, nil, LEFT, y)
	y = y - ROW
	FieldCheck(page, "borderReaction", L.OPT_BORDER_REACTION, nil, LEFT, y)
	y = y - ROW
	FieldCheck(page, "borderQuality", L.OPT_BORDER_QUALITY, L.OPT_BORDER_QUALITY_TIP, LEFT, y)
	y = y - ROW - 14

	MediaDropdown(page, "healthBar", "statusbar", L.OPT_HEALTH_BAR, y)
	y = y - ROW - 6
	MediaDropdown(page, "font", "font", L.OPT_FONT, y)
	y = y - ROW - 6
	BackgroundSwatch(page, y)

	-- The player, a sample item (quality border) and the two sample names.
	local anchor = CreateFrame("Frame", nil, page)
	anchor:SetSize(1, 1)
	anchor:SetPoint("TOPLEFT", PREVIEW_X, TOP + 12)
	local player = ns.Preview.Create(page)
	local item = ns.Preview.Create(page)
	local hostilePlayer = ns.Preview.Create(page)
	local npc = ns.Preview.Create(page)

	function page:Draw()
		if not self:IsVisible() then return end
		local profile = ns.profile
		ns.Preview.Place(player, self, "TOPLEFT", anchor, "TOPLEFT", 0, 0)
		player:SetUnit("player")
		ns.Preview.Place(item, self, "TOPLEFT", player, "BOTTOMLEFT", 0, -12)
		item:SetItemByID(ns.Preview.LOOK_ITEM)

		local _, class = UnitClass("player")
		local classColor = class and C_ClassColor.GetClassColor(class) or HIGHLIGHT_FONT_COLOR
		local red = FACTION_BAR_COLORS[2]
		local nameColor = (profile.classNames and not profile.hostileRed) and classColor or red
		DrawSample(hostilePlayer, self, item, L.SAMPLE_HOSTILE_PLAYER, nameColor,
			profile.borderClass and classColor or nil)
		DrawSample(npc, self, hostilePlayer, L.SAMPLE_HOSTILE_NPC, red, profile.borderReaction and red or nil)
	end

	function page:OnDefault() DefaultsOf(LOOK_FIELDS) end
	return page
end

-- Sources (4.2, 4.3) ---------------------------------------------------------------------------------------------------
-- A list of every addon seen adding tooltip lines this session (and any with a rule), each with "hide every line" and
-- its recent lines; or the last tooltip, line by line. Beside it, the last tooltip with the sources column.

local function Label(folder) return ns.Sources.Label(folder, 16) end

local function SortedFolders()
	local folders, added = {}, {}
	local function Add(folder)
		if not added[folder] then
			added[folder] = true
			folders[#folders + 1] = folder
		end
	end
	for folder in pairs(ns.Sources.Seen()) do Add(folder) end
	for folder in pairs(ns.profile.hideAddon) do Add(folder) end
	for folder in pairs(ns.profile.hideLine) do Add(folder) end
	for folder in pairs(ns.Remove.KnownAddons()) do
		if C_AddOns.IsAddOnLoaded(folder) then Add(folder) end
	end
	table.sort(folders, function(a, b) return ns.Sources.Title(a):lower() < ns.Sources.Title(b):lower() end)
	return folders
end

-- Row specs: { kind = "header" | "check" | "note", text, note, checked, active, indent, click }.
local function AddonRows()
	local rows = {}
	local seen = ns.Sources.Seen()
	local folders = SortedFolders()
	if #folders == 0 then
		rows[1] = { kind = "note", text = L.SOURCES_EMPTY }
		return rows
	end
	for _, folder in ipairs(folders) do
		local hideAll = ns.Remove.IsAddonHidden(folder)
		rows[#rows + 1] = { kind = "header", text = Label(folder) }
		rows[#rows + 1] = { kind = "check", text = L.SOURCES_HIDE_ADDON, checked = hideAll, active = true,
			click = function(on) ns.Remove.SetAddon(folder, on) end }
		for _, entry in ipairs(ns.Remove.Known(folder) or {}) do
			if entry.match then
				rows[#rows + 1] = { kind = "check", text = entry.label, note = entry.hint, indent = true,
					checked = hideAll or ns.Remove.IsKnownOn(entry.id), active = not hideAll,
					click = function(on) ns.Remove.SetKnown(entry.id, on) end }
			end
		end
		-- Its lines: those it shows all the time (Sources.lua lists a line once it's on three different items or units),
		-- then any hidden earlier that haven't shown up yet (rules are kept by shape, numbers as "#"). Never blank ones.
		local lines, listed = {}, {}
		for _, text in ipairs(seen[folder] and seen[folder].lines or {}) do
			lines[#lines + 1] = text
			listed[ns.Sources.Shape(text)] = true
		end
		for shape in pairs(ns.profile.hideLine[folder] or {}) do
			if not listed[shape] and not ns.Sources.IsBlank(shape) then lines[#lines + 1] = shape end
		end
		for _, text in ipairs(lines) do
			if not ns.Remove.IsKnownLine(folder, text) then
				rows[#rows + 1] = { kind = "check", text = ns.PlainText(text) or "", indent = true,
					checked = hideAll or ns.Remove.IsLineHidden(folder, text), active = not hideAll,
					click = function(on) ns.Remove.SetLine(folder, text, on) end }
			end
		end
	end
	return rows
end

local function LastRows()
	local record = ns.Sources.Current()
	if not record then return { { kind = "note", text = L.SOURCES_LAST_EMPTY } } end
	local rows = {}
	for index = 1, record.n do
		local source = record.source[index]
		local raw = record.left[index] or record.right[index]
		local text = raw and ns.PlainText(raw) or L.SOURCES_UNREADABLE
		if source and source ~= ns.Sources.GAME then
			local hideAll = ns.Remove.IsAddonHidden(source)
			local known = raw and ns.Remove.IsKnownLine(source, raw)
			local row = { kind = "check", text = text, note = Label(source), active = raw ~= nil and not hideAll }
			if known then
				row.checked = hideAll or ns.Remove.IsKnownOn(known.id)
				row.click = function(on) ns.Remove.SetKnown(known.id, on) end
			else
				row.checked = hideAll or (raw ~= nil and ns.Remove.IsLineHidden(source, raw))
				row.click = function(on) ns.Remove.SetLine(source, raw, on) end
			end
			rows[#rows + 1] = row
		else
			rows[#rows + 1] = { kind = "note", text = text, indent = true }
		end
	end
	return rows
end

local function ListRow(list, index)
	local row = list.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, list.child)
	row.check = Check(row, "")
	row.check.label:SetText("")
	row.check:SetPoint("TOPLEFT", 0, -2)
	row.check:SetScript("OnClick", function(self)
		local on = self:GetChecked() == true
		ClickSound(on)
		if row.click then row.click(on) end
	end)
	row.text = Text(row, "GameFontHighlight")
	row.text:SetWordWrap(true)
	row.note = Text(row, "GameFontDisableSmall")
	row.note:SetWordWrap(true)
	list.rows[index] = row
	return row
end

local function DrawList(list, specs)
	local width = LIST_WIDTH - 24
	local y = 0
	for index, spec in ipairs(specs) do
		local row = ListRow(list, index)
		local x = spec.indent and INDENT or 0
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -y)
		row:SetWidth(width)
		row.click = spec.click
		row.check:SetShown(spec.kind == "check")
		row.check:ClearAllPoints()
		row.check:SetPoint("TOPLEFT", x, -2)
		local textX = spec.kind == "check" and x + 28 or x
		row.text:ClearAllPoints()
		row.text:SetPoint("TOPLEFT", textX, -7)
		row.text:SetWidth(width - textX)
		row.text:SetFontObject(spec.kind == "header" and GameFontNormal
			or (spec.kind == "note" and GameFontDisable) or GameFontHighlight)
		row.text:SetText(spec.text or "")
		if spec.kind == "check" then
			row.check:SetChecked(spec.checked == true)
			row.check:SetActive(spec.active ~= false)
			if spec.active == false then row.text:SetFontObject(GameFontDisable) end
		end
		local height = row.text:GetStringHeight() + 12
		row.note:ClearAllPoints()
		if spec.note then
			row.note:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
			row.note:SetWidth(width - textX)
			row.note:SetText(spec.note)
			row.note:Show()
			height = height + row.note:GetStringHeight() + 2
		else
			row.note:Hide()
		end
		if spec.kind == "header" and index > 1 then height = height + 4 end
		row:SetHeight(math.max(height, spec.kind == "check" and 30 or 20))
		row:Show()
		y = y + row:GetHeight()
	end
	for index = #specs + 1, #list.rows do list.rows[index]:Hide() end
	list.child:SetSize(width, math.max(y, 1))
end

-- The last tooltip redrawn in a preview, with the sources column beside it. Lines the current rules would remove are
-- kept in the preview and struck through in the column.
-- The current tooltip as the player saw it (Sources.lua's snapshot): Clean Tooltips' changes and other addons' lines
-- included, removed lines left out and listed under it in the sources column, its border and background colours.
-- Removal rules ticked since are applied at once. Lines are matched to rules by their text as added.
local function DrawCurrentTooltip(tooltip, page, anchor)
	local record = ns.Sources.Current()
	if not record then
		tooltip:Hide()
		ns.SourcesView.Hide(tooltip)
		return
	end
	ns.Preview.Place(tooltip, page, "TOPLEFT", anchor, "TOPLEFT", 0, 0)
	local view = setmetatable({ hidden = {}, lineIndex = {} }, { __index = record })
	local gray = GRAY_FONT_COLOR
	local shown = 0
	for index = 1, record.n do
		local source, original = record.source[index], record.left[index] or record.right[index]
		local removed = record.hidden[index]
			or (source and source ~= ns.Sources.GAME and ns.Remove.ShouldHide(source, original))
		local snapped = record.finalShown[index] ~= nil
		if removed then
			view.hidden[index] = true
		elseif not snapped or record.finalShown[index] then
			local left = snapped and record.finalLeft[index] or (not snapped and record.left[index]) or nil
			local right = snapped and record.finalRight[index] or (not snapped and record.right[index]) or nil
			local lr, lg, lb = record.lr[index], record.lg[index], record.lb[index]
			if snapped then lr, lg, lb = record.flr[index], record.flg[index], record.flb[index] end
			if left == nil and right == nil then
				tooltip:AddLine(L.SOURCES_UNREADABLE, gray.r, gray.g, gray.b)
			elseif right then
				local rr, rg, rb = record.rr[index], record.rg[index], record.rb[index]
				if snapped then rr, rg, rb = record.frr[index], record.frg[index], record.frb[index] end
				tooltip:AddDoubleLine(left or "", right, lr, lg, lb, rr or 1, rg or 1, rb or 1)
			else
				tooltip:AddLine(left, lr, lg, lb)
			end
			shown = shown + 1
			view.lineIndex[index] = shown
		end
	end
	tooltip:Show()
	local nineSlice = tooltip.NineSlice
	if nineSlice then
		local border, center = record.border, record.center
		ns.Style.SetBorderGrey(nineSlice, record.borderGrey)
		nineSlice:SetBorderColor(border and border[1] or 1, border and border[2] or 1, border and border[3] or 1,
			border and border[4] or 1)
		local default = TOOLTIP_DEFAULT_BACKGROUND_COLOR
		nineSlice:SetCenterColor(center and center[1] or default.r, center and center[2] or default.g,
			center and center[3] or default.b, center and center[4] or 1)
	end
	ns.SourcesView.Draw(tooltip, view, false)
end

local function BuildSources()
	local page = NewPage(L.PAGE_SOURCES)
	local y = TOP
	-- Removing lines here is the fallback: the addon's own setting is the better way.
	local advice = Text(page, "GameFontHighlight", L.SOURCES_ADVICE)
	advice:SetPoint("TOPLEFT", LEFT, y)
	advice:SetWidth(ADVICE_WIDTH)
	advice:SetJustifyH("LEFT")
	advice:SetWordWrap(true)
	y = y - 44
	FieldCheck(page, "showSources", L.OPT_SHOW_SOURCES, L.OPT_SHOW_SOURCES_TIP, LEFT, y)
	y = y - ROW - 8
	Dropdown(page, L.OPT_SOURCES_LIST, 160, function()
		return { { value = "addons", text = L.SOURCES_MODE_ADDONS }, { value = "last", text = L.SOURCES_MODE_LAST } }
	end, function() return sourcesMode end, function(value)
		sourcesMode = value
		page:Draw()
	end, LEFT, y)
	y = y - ROW - 10

	local scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", LEFT, y)
	scroll:SetPoint("BOTTOMLEFT", LEFT, 16)
	scroll:SetWidth(LIST_WIDTH)
	local list = { rows = {}, child = CreateFrame("Frame", nil, scroll) }
	list.child:SetSize(LIST_WIDTH - 24, 1)
	scroll:SetScrollChild(list.child)

	-- The current tooltip and its sources column, in a region right of the list that scrolls sideways when they're
	-- wider than it (a long line, a wide column): a slider under it, and the mouse wheel over it, while there's
	-- anything to scroll.
	local viewport = CreateFrame("ScrollFrame", nil, page)
	viewport:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 30, 0)
	viewport:SetPoint("RIGHT", page, "RIGHT", -8, 0)
	viewport:SetHeight(1)
	local stage = CreateFrame("Frame", nil, viewport)
	stage:SetSize(1, 1)
	viewport:SetScrollChild(stage)
	local anchor = CreateFrame("Frame", nil, stage)
	anchor:SetSize(1, 1)
	anchor:SetPoint("TOPLEFT", 0, 0)
	local preview = ns.Preview.Create(stage, true)

	local slider = CreateFrame("Frame", nil, page, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 0, -6)
	slider:SetPoint("TOPRIGHT", viewport, "BOTTOMRIGHT", 0, -6)
	slider:SetHeight(20)
	slider:Init(0, 0, 1, 1)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		viewport:SetHorizontalScroll(value)
	end, viewport)
	slider:Hide()
	local SCROLL_STEP = 40 -- pixels a wheel notch moves
	local range = 0
	viewport:SetScript("OnMouseWheel", function(_, delta)
		slider:SetValue(math.max(0, math.min(range, viewport:GetHorizontalScroll() - delta * SCROLL_STEP)))
	end)

	-- Sizes the region to the tooltip and its column once they're laid out, and shows the slider if they're wider.
	local function FitView()
		local left, top = stage:GetLeft(), stage:GetTop()
		local right, bottom = preview:GetRight(), preview:GetBottom()
		if not (left and top and right and bottom) or not preview:IsShown() then
			viewport:SetHeight(1)
			slider:Hide()
			viewport:EnableMouseWheel(false)
			return
		end
		local column = ns.SourcesView.ColumnOf(preview)
		if column and column:IsShown() then
			right = math.max(right, column:GetRight() or right)
			bottom = math.min(bottom, column:GetBottom() or bottom)
		end
		local width, height = right - left + 4, top - bottom + 4
		stage:SetSize(width, height)
		viewport:SetHeight(height)
		range = math.max(0, width - (viewport:GetWidth() or width))
		if range > 0 then
			slider:Init(math.min(viewport:GetHorizontalScroll(), range), 0, range, math.max(1, math.floor(range / 20)))
			slider:Show()
		else
			viewport:SetHorizontalScroll(0)
			slider:Hide()
		end
		viewport:EnableMouseWheel(range > 0)
		page:FitHeight()
	end
	local FitViewSoon = ns.Throttled(FitView)
	preview:HookScript("OnSizeChanged", FitViewSoon)

	function page:Draw()
		if not self:IsVisible() then return end
		DrawList(list, sourcesMode == "last" and LastRows() or AddonRows())
		DrawCurrentTooltip(preview, self, anchor)
		FitViewSoon()
	end
	-- The current tooltip changes as the player hovers things: drawn again while the page is open.
	ns.Listen("TOOLTIP_SEEN", function()
		if page:IsVisible() then page:Refresh() end
	end)

	function page:OnDefault() DefaultsOf({ "showSources" }) end
	return page
end

-- Profiles -------------------------------------------------------------------------------------------------------------
-- A canvas page like the others, with CT's own dropdowns and buttons. Not a list page of the game's Settings controls:
-- the panel's search reads every list page's settings, and reading CT's taints the rest of the search, so the game
-- refused the Social page's protected Discord call while it drew the results (ADDON_ACTION_FORBIDDEN IsUserOAuthed,
-- 8 Nov). Canvas pages aren't searched.

local profilesPage

local function RefreshProfiles()
	if profilesPage then profilesPage:Refresh() end
end

local function Trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ProfileNames(skipCurrent)
	local names = {}
	if not ns.db then return names end
	local current = ns.db:GetCurrentProfile()
	for _, name in ipairs((ns.db:GetProfiles({}))) do
		if not (skipCurrent and name == current) then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

local function ProfileExists(name)
	for _, existing in ipairs(ProfileNames()) do
		if existing == name then return true end
	end
	return false
end

-- The profile names for a dropdown, as { value, text }; `extra` first when it isn't a profile yet.
local function ProfileChoices(skipCurrent, extra)
	return function()
		local list, seen = {}, {}
		if extra then
			list[1] = { value = extra, text = extra }
			seen[extra] = true
		end
		for _, name in ipairs(ProfileNames(skipCurrent)) do
			if not seen[name] then list[#list + 1] = { value = name, text = name } end
		end
		return list
	end
end

local PROFILE_DROPDOWN_WIDTH = 200
local BUTTON_WIDTH = 160

local function ProfileButton(page, text, x, y, click)
	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(BUTTON_WIDTH, 22)
	button:SetPoint("TOPLEFT", x, y)
	button:SetScript("OnClick", click)
	return button
end

-- A dropdown that picks a profile to act on (copy from, delete): it always reads as a prompt, asks to confirm, and is
-- greyed while there's no other profile.
local function PickerDropdown(page, labelText, popup, y)
	local dropdown = Dropdown(page, labelText, PROFILE_DROPDOWN_WIDTH, ProfileChoices(true),
		function() return nil end,
		function(value)
			if RefuseInCombat() then return end
			StaticPopup_Show(POPUP_PREFIX .. popup, value, ns.db and ns.db:GetCurrentProfile() or "", value)
		end, LEFT, y)
	dropdown:SetDefaultText(L.PROFILE_CHOOSE)
	table.insert(page.refreshers, function() dropdown:SetEnabled(#ProfileNames(true) > 0) end)
	return dropdown
end

local function BuildProfiles()
	local page = NewPage(L.PAGE_PROFILES)
	local y = TOP
	page.Active = Dropdown(page, L.PROFILE_ACTIVE, PROFILE_DROPDOWN_WIDTH, ProfileChoices(false),
		function() return ns.db and ns.db:GetCurrentProfile() end,
		function(value)
			if ns.db and not RefuseInCombat() then ns.db:SetProfile(value) end
			RefreshProfiles()
		end, LEFT, y)
	y = y - ROW - 8
	-- The default for new characters may name a profile that doesn't exist yet (AceDB makes it on first use).
	page.Default = Dropdown(page, L.PROFILE_DEFAULT, PROFILE_DROPDOWN_WIDTH,
		function() return ProfileChoices(false, ns.global and ns.global.defaultProfile or "Default")() end,
		function() return ns.global and ns.global.defaultProfile or "Default" end,
		function(value)
			if ns.global then ns.global.defaultProfile = value end
			RefreshProfiles()
		end, LEFT, y)
	y = y - ROW - 16
	page.New = ProfileButton(page, L.PROFILE_NEW, LEFT + LABEL_WIDTH, y, function()
		if not RefuseInCombat() then StaticPopup_Show(POPUP_PREFIX .. "PROFILE_NEW") end
	end)
	y = y - ROW - 8
	page.Copy = PickerDropdown(page, L.PROFILE_COPY, "PROFILE_COPY", y)
	y = y - ROW - 8
	page.Delete = PickerDropdown(page, L.PROFILE_DELETE, "PROFILE_DELETE", y)
	y = y - ROW - 16
	page.Reset = ProfileButton(page, L.PROFILE_RESET, LEFT + LABEL_WIDTH, y, function()
		if not RefuseInCombat() and ns.db then
			StaticPopup_Show(POPUP_PREFIX .. "PROFILE_RESET", ns.db:GetCurrentProfile())
		end
	end)
	-- Defaults on this page would be Reset Profile, which asks first: the button is there for that.
	function page:OnDefault() end
	profilesPage = page
	return page
end

local function Popup(key, info)
	info.timeout = 0
	info.whileDead = true
	info.hideOnEscape = true
	StaticPopupDialogs[POPUP_PREFIX .. key] = info
end

Popup("PROFILE_NEW", {
	text = L.PROFILE_NEW_TEXT,
	button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = true, maxLetters = NAME_LETTERS,
	OnShow = function(dialog) dialog:GetButton1():Disable() end,
	EditBoxOnTextChanged = function(editBox) StaticPopup_StandardNonEmptyTextHandler(editBox) end,
	EditBoxOnEnterPressed = function(editBox)
		local button = editBox:GetParent():GetButton1()
		if button:IsEnabled() then button:Click() end
	end,
	OnAccept = function(dialog)
		if RefuseInCombat() or not ns.db then return end
		local name = Trim(dialog:GetEditBox():GetText())
		if name == "" then return true end
		if ProfileExists(name) then
			ns.Print(L.PROFILE_EXISTS:format(name))
			return true
		end
		ns.db:SetProfile(name)
		RefreshProfiles()
	end,
})

Popup("PROFILE_COPY", {
	text = L.PROFILE_COPY_CONFIRM, -- %s the profile copied from, %s the current one
	button1 = YES, button2 = NO, showAlert = true,
	OnAccept = function(_, source)
		if RefuseInCombat() or not ns.db or not ProfileExists(source) then return end
		if source ~= ns.db:GetCurrentProfile() then ns.db:CopyProfile(source) end
	end,
})

Popup("PROFILE_DELETE", {
	text = L.PROFILE_DELETE_CONFIRM, -- %s the profile
	button1 = YES, button2 = NO, showAlert = true,
	OnAccept = function(_, name)
		if RefuseInCombat() or not ns.db or not ProfileExists(name) then return end
		if name == ns.db:GetCurrentProfile() then return end
		ns.db:DeleteProfile(name)
		if ns.global and ns.global.defaultProfile == name then ns.global.defaultProfile = "Default" end
		RefreshProfiles()
	end,
})

Popup("PROFILE_RESET", {
	text = L.PROFILE_RESET_CONFIRM, -- %s the profile
	button1 = YES, button2 = NO, showAlert = true,
	OnAccept = function()
		if not RefuseInCombat() and ns.db then ns.db:ResetProfile() end
	end,
})

-- Opening and keeping current -------------------------------------------------------------------------------------------

function Options.Open(which)
	if RefuseInCombat() then return false end
	if which == "last" then
		sourcesMode = "last"
		which = "sources"
	end
	local category = categories[which or "cleanup"] or categories.cleanup
	if not category then return false end
	Settings.OpenToCategory(category:GetID())
	return true
end

local function RefreshShown()
	for _, page in ipairs(pages) do
		if page:IsVisible() then page:Refresh() end
	end
end
local RefreshShownSoon = ns.Throttled(RefreshShown)

ns.Listen("DB_READY", function()
	if categories.cleanup then return end
	local cleanup = BuildCleanup()
	local root = Settings.RegisterCanvasLayoutCategory(cleanup.canvas, TITLE)
	categories.cleanup = root
	categories.look = Settings.RegisterCanvasLayoutSubcategory(root, BuildLook().canvas, L.PAGE_LOOK)
	categories.sources = Settings.RegisterCanvasLayoutSubcategory(root, BuildSources().canvas, L.PAGE_SOURCES)
	categories.profiles = Settings.RegisterCanvasLayoutSubcategory(root, BuildProfiles().canvas, L.PAGE_PROFILES)
	Settings.RegisterAddOnCategory(root)
end)

ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil then RefreshProfiles() end
	RefreshShownSoon()
end)
ns.Listen("RULES_CHANGED", RefreshShownSoon)
ns.Listen("SOURCE_SEEN", RefreshShownSoon)
