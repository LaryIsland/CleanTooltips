local _, ns = ...
local L = ns.L

-- Options > AddOns > Clean Tooltips. Clean-up, Look and Sources are canvas pages, CT's own frames,
-- so each can show live preview tooltips beside its options; Profiles (Profiles.lua) is a canvas page too. The pages'
-- widgets are in OptionsWidgets.lua, and each page is built the first time it's shown. Every option applies at once,
-- to the previews and to tooltips already shown. The Defaults button resets the page shown. Removal rules are the
-- player's own list, not settings, so Defaults leaves them alone (Reset Profile clears them).
--   ns.Options.Open(page)   page: nil (Clean-up), "look", "sources", "last" (Sources on the last tooltip), "profiles"

ns.Options = {}
local Options = ns.Options

local Kit = ns.OptionsKit -- OptionsWidgets.lua
local TITLE, LEFT, TOP, ROW, INDENT, LABEL_WIDTH = Kit.TITLE, Kit.LEFT, Kit.TOP, Kit.ROW, Kit.INDENT, Kit.LABEL_WIDTH
local RefuseInCombat, AddTip, Text, Check, ClickSound = Kit.RefuseInCombat, Kit.AddTip, Kit.Text, Kit.Check,
	Kit.ClickSound
local NewPage, FieldCheck, Dropdown, DefaultsOf = Kit.NewPage, Kit.FieldCheck, Kit.Dropdown, Kit.DefaultsOf
local Readable = ns.Readable

local PREVIEW_X = 330    -- the Look page's previews, right of its options
local CLEANUP_COLUMN = 300 -- the Clean-up page's second column of options, from its first
local COLUMN_GAP = 24    -- between the Sources page's two columns of options
local MIN_COLUMN = 220   -- narrowest a column of options gets before the list stays in one
local MIN_LIST = 300     -- the Sources page's list is never narrower (the page's width unknown yet)

local categories = {}    -- [page key] = the Settings category
local sourcesMode = "last" -- the Sources page opens on the current tooltip

-- Clean-up -------------------------------------------------------------------------------------------------------------

local CLEANUP_FIELDS = ns.CLEANUP_FIELDS -- Core.lua

local function BuildCleanup(canvas)
	local page = NewPage(TITLE, canvas)
	-- Two columns, in the order the first samples show them (Preview.SAMPLES). Left, the lines hidden from items: sell
	-- price, requirements met, "Soulbound", "Unique", durability, then dps. Right, the shortened Equip and Use lines with
	-- the options that shape them, then the unit tooltip lines.
	local left, right = TOP, TOP
	local function Left(field, text, tip)
		local check = FieldCheck(page, field, text, tip, LEFT, left)
		left = left - ROW
		return check
	end
	local function Right(field, text, tip, indent)
		local check = FieldCheck(page, field, text, tip, LEFT + CLEANUP_COLUMN + (indent and INDENT or 0), right)
		right = right - ROW
		return check
	end
	Left("hideSellPrice", L.OPT_SELL_PRICE, L.OPT_SELL_PRICE_TIP)
	Left("hideMetLevel", L.OPT_LEVEL, nil)
	Left("hideMetRequirements", L.OPT_MET_REQUIREMENTS, nil)
	Left("hideSoulbound", L.OPT_SOULBOUND, nil)
	Left("hideUnique", L.OPT_UNIQUE, nil)
	Left("hideDurability", L.OPT_DURABILITY, nil)
	Left("shortenDps", L.OPT_SHORTEN_DPS, nil)
	Right("shortenEquip", L.OPT_SHORTEN_EQUIP, nil)
	local noPrefix = Right("dropEquipPrefix", L.OPT_DROP_EQUIP_PREFIX, nil, true)
	table.insert(page.refreshers, function() noPrefix:SetActive(ns.profile.shortenEquip == true) end)
	Right("shortenUse", L.OPT_SHORTEN_USE, nil)
	local oneSecond = Right("hideSecondCooldown", L.OPT_HIDE_SECOND_COOLDOWN, nil, true)
	table.insert(page.refreshers, function() oneSecond:SetActive(ns.profile.shortenUse == true) end)
	Right("hideFaction", L.OPT_FACTION, nil)
	Right("hidePvP", L.OPT_PVP, nil)
	local y = math.min(left, right) - 12

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

-- Look ---------------------------------------------------------------------------------------------------------------

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
		-- Cancel puts back what was there: the game's own background stays the game's, not a colour that matches it.
		local before = ns.profile.background
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, opacity = a, hasOpacity = true,
			swatchFunc = Picked, opacityFunc = Picked,
			cancelFunc = function(previous)
				if type(before) ~= "table" then return SetBackground(false) end
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

-- Sample name lines for what can't be previewed with a real unit: a hostile player and an NPC.
local function DrawSample(tooltip, page, anchor, text, color, borderColor)
	ns.Preview.Place(tooltip, page, "TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	tooltip:SetText(text, color.r, color.g, color.b)
	tooltip:Show()
	ns.Style.SetBorder(tooltip, borderColor)
end

local function BuildLook(canvas)
	local page = NewPage(L.PAGE_LOOK, canvas)
	local y = TOP
	FieldCheck(page, "classNames", L.OPT_CLASS_NAMES, nil, LEFT, y)
	y = y - ROW
	local hostile = FieldCheck(page, "hostileRed", L.OPT_HOSTILE_RED, nil, LEFT + INDENT, y)
	table.insert(page.refreshers, function() hostile:SetActive(ns.profile.classNames == true) end)
	y = y - ROW - 10

	local borders = Text(page, "GameFontNormal", L.OPT_BORDERS)
	borders:SetPoint("TOPLEFT", LEFT, y)
	y = y - 20
	FieldCheck(page, "borderClass", L.OPT_BORDER_CLASS, nil, LEFT, y)
	y = y - ROW
	FieldCheck(page, "borderReaction", L.OPT_BORDER_REACTION, nil, LEFT, y)
	y = y - ROW
	FieldCheck(page, "borderQuality", L.OPT_BORDER_QUALITY, nil, LEFT, y)
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

		-- The sample hostile player is a shaman, whatever the player's class.
		local classColor = C_ClassColor.GetClassColor("SHAMAN") or HIGHLIGHT_FONT_COLOR
		local red = FACTION_BAR_COLORS[2]
		local nameColor = (profile.classNames and not profile.hostileRed) and classColor or red
		DrawSample(hostilePlayer, self, item, L.SAMPLE_HOSTILE_PLAYER, nameColor,
			profile.borderClass and classColor or nil)
		DrawSample(npc, self, hostilePlayer, L.SAMPLE_HOSTILE_NPC, red, profile.borderReaction and red or nil)
	end

	function page:OnDefault() DefaultsOf(LOOK_FIELDS) end
	return page
end

-- Sources --------------------------------------------------------------------------------------------------------------
-- A list of every addon seen adding tooltip lines this session (and any with a rule), each with "hide every line" and
-- its recent lines; or the last tooltip, line by line. Beside it, the last tooltip with the sources column.

local function Label(folder) return ns.Sources.Label(folder, 16) end

-- The tooltip types a line has been seen on, for its rule (Remove.SetLine): the types listed for it, and the type of
-- the tooltip it's on now.
local function LineTypes(folder, text, typeName)
	local types = {}
	for name in pairs(ns.Sources.LineTypes(folder, text) or {}) do types[name] = true end
	if typeName then types[typeName] = true end
	return types
end

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
	for folder in pairs(ns.profile.hideWritten) do Add(folder) end
	table.sort(folders, function(a, b) return ns.Sources.Title(a):lower() < ns.Sources.Title(b):lower() end)
	return folders
end

-- Row specs: { kind = "header" | "check" | "line" | "note", text, checked, active, indent, click, toggle, tip }.
-- A heading's `toggle` ({ checked, click }) is its addon's "Hide everything", inline after its name; hovering it shows
-- the page's advice (it's better to turn a line off in its own addon). `tip` ({ title, text }) is shown when the row's
-- tick box or text is hovered.

-- An addon's heading, with "Hide everything" on the same line.
local function AddonHeader(folder)
	return { kind = "header", text = Label(folder), toggle = { checked = ns.Remove.IsAddonHidden(folder),
		click = function(on) ns.Remove.SetAddon(folder, on) end } }
end

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
		rows[#rows + 1] = AddonHeader(folder)
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
			-- With its icons, as the tooltip showed it; only its colours go.
			rows[#rows + 1] = { kind = "check", text = ns.WithIcons(text) or "", indent = true,
				checked = hideAll or ns.Remove.IsLineHidden(folder, text), active = not hideAll,
				click = function(on) ns.Remove.SetLine(folder, text, on, LineTypes(folder, text)) end }
		end
		-- Lines it adds blank and then writes into, hidden from the current tooltip (Remove.SetWritten), so they can be
		-- shown again here. Unticking drops the rule, so the row goes when the page is drawn again.
		local written = ns.Remove.WrittenRules(folder)
		if written then
			local sites = {}
			for site in pairs(written) do sites[#sites + 1] = site end
			table.sort(sites)
			for _, site in ipairs(sites) do
				local rule = written[site]
				rows[#rows + 1] = { kind = "check", text = rule.label, indent = true, checked = true,
					active = not hideAll,
					click = function(on) ns.Remove.SetWritten(folder, site, rule.label, on, rule.types) end }
			end
		end
	end
	return rows
end

-- The current tooltip's addon lines, in the order the tooltip shows them, each with a tick box whose tooltip names the
-- addon that added it, with its icon; no headings and no "Hide everything" here (that's on All addons). The game's lines aren't listed (there's nothing to do with them). Blank lines have no rule of their own, as
-- they go with the addon's lines beside them, so they aren't listed. A line its addon added blank and then wrote
-- into (Leatrix Plus's "Target: <name>") is listed as written, and its tick box goes by where the addon adds it
-- (Remove.SetWritten), as its text changes with every target; without a readable call site it has no tick box.
local function LastRows()
	local record = ns.Sources.Current()
	if not record then return { { kind = "note", text = L.SOURCES_LAST_EMPTY } } end
	local typeName = record.typeName -- now: records are reused, so the click mustn't read it later
	local rows = {}
	for index = 1, record.n do
		local source = record.source[index]
		if source and source ~= ns.Sources.GAME then
			local hideAll = ns.Remove.IsAddonHidden(source)
			local tip = { title = Label(source) }
			local raw = record.left[index] or record.right[index]
			if raw ~= nil and ns.Sources.IsBlank(raw) then
				-- As written (kept even once it's hidden), else as shown.
				local shown = record.written[index] or record.finalLeft[index] or record.finalRight[index]
				local site = record.site[index]
				if shown and not ns.Sources.IsBlank(shown) then
					local row = { kind = site and "check" or "line", text = ns.WithIcons(shown) or L.SOURCES_UNREADABLE,
						tip = tip }
					if site then
						local types = typeName and { [typeName] = true } or nil
						row.active = not hideAll
						row.checked = hideAll or ns.Remove.IsWrittenHidden(source, site)
						row.click = function(on) ns.Remove.SetWritten(source, site, shown, on, types) end
					end
					rows[#rows + 1] = row
				end
			else
				-- With its icons, as the tooltip showed it; only its colours go.
				local row = { kind = "check", text = raw and ns.WithIcons(raw) or L.SOURCES_UNREADABLE, tip = tip,
					active = raw ~= nil and not hideAll }
				row.checked = hideAll or (raw ~= nil and ns.Remove.IsLineHidden(source, raw))
				row.click = function(on) ns.Remove.SetLine(source, raw, on, LineTypes(source, raw, typeName)) end
				rows[#rows + 1] = row
			end
		end
	end
	if #rows == 0 then rows[1] = { kind = "note", text = L.SOURCES_LAST_NONE } end
	return rows
end
Options.LastRows = LastRows
Options.AddonRows = AddonRows

local function ListRow(list, index)
	local row = list.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, list.frame)
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
	list.rows[index] = row
	return row
end

-- "Hide everything" explains the page when hovered: it's better to turn a line off in its own addon.
local function ShowAdvice(owner)
	Kit.ShowTip(owner, L.SOURCES_HIDE_ADDON, L.SOURCES_ADVICE)
end

-- A row's own tooltip (its spec's `tip`): the addon that added the line, with its icon, and a note if there is one.
local function ShowRowTip(check)
	local tip = check.tip
	if tip then Kit.ShowTip(check, tip.title, tip.text) end
end

-- Fills row `index` for `spec` at `width` (its text wraps to it) and gives its height.
local function FillRow(list, index, spec, width)
	local row = ListRow(list, index)
	local x = spec.indent and INDENT or 0
	local toggle = spec.kind == "header" and spec.toggle or nil
	row:SetWidth(width)
	row.click = toggle and toggle.click or spec.click
	row.check:SetShown(spec.kind == "check" or toggle ~= nil)
	row.check:SetLabel("") -- "Hide everything" is the box alone (its tooltip says what it is)
	row.check.tip = spec.tip
	row.check:SetScript("OnEnter", toggle and ShowAdvice or (spec.tip and ShowRowTip) or nil)
	row.check:SetScript("OnLeave", (toggle or spec.tip) and Kit.HideTip or nil)
	-- A "line" row (an addon line with no tick box) lines up with the ticked ones' text. A heading's "Hide everything"
	-- box comes before the addon's name, spaced as any tick box.
	local textX = (spec.kind == "check" or spec.kind == "line" or toggle) and x + 28 or x
	row.text:ClearAllPoints()
	row.text:SetPoint("TOPLEFT", textX, -7)
	row.text:SetFontObject(spec.kind == "header" and GameFontNormal
		or (spec.kind == "note" and GameFontDisable) or GameFontHighlight)
	row.text:SetText(spec.text or "")
	row.check:ClearAllPoints()
	row.check:SetPoint("TOPLEFT", x, -2)
	if toggle then
		row.check:SetChecked(toggle.checked == true)
		row.check:SetActive(true)
	end
	row.text:SetWidth(width - textX)
	if spec.kind == "check" and spec.tip then
		-- Hovering (and clicking) the line's text works as its tick box, so its tooltip is easy to reach.
		row.check:SetHitRectInsets(0, -math.min(row.text:GetUnboundedStringWidth() + 4, width - 28), 0, 0)
	end
	if spec.kind == "check" then
		row.check:SetChecked(spec.checked == true)
		row.check:SetActive(spec.active ~= false)
		if spec.active == false then row.text:SetFontObject(GameFontDisable) end
	end
	local height = row.text:GetStringHeight() + 12
	if spec.kind == "header" and index > 1 then height = height + 4 end
	height = math.max(height, (spec.kind == "check" or toggle) and 30 or 20)
	row:SetHeight(height)
	return height
end

-- Lays the rows out `width` wide: one column, or two when one would be taller than `available` (nil: not known yet)
-- and there's room for two. The second column starts at the addon heading nearest half way, so an addon's lines stay
-- together (any row when there's no heading). Returns the list's height.
local function DrawList(list, specs, width, available)
	local function Measure(columnWidth)
		local heights, total = {}, 0
		for index, spec in ipairs(specs) do
			heights[index] = FillRow(list, index, spec, columnWidth)
			total = total + heights[index]
		end
		return heights, total
	end
	local columnWidth = width
	local heights, total = Measure(width)
	local second = #specs + 1 -- the first row of the second column
	local half = math.floor((width - COLUMN_GAP) / 2)
	if available and total > available and half >= MIN_COLUMN and #specs > 1 then
		columnWidth = half
		heights, total = Measure(half)
		local best, bestGap, y = nil, math.huge, 0
		for index = 2, #specs do
			y = y + heights[index - 1]
			if specs[index].kind == "header" and math.abs(y - total / 2) < bestGap then
				best, bestGap = index, math.abs(y - total / 2)
			end
		end
		if not best then
			y = 0
			for index = 1, #specs - 1 do
				y = y + heights[index]
				if y >= total / 2 then
					best = index + 1
					break
				end
			end
		end
		second = best or second
	end
	local x, y, tallest = 0, 0, 0
	for index = 1, #specs do
		if index == second then x, y = columnWidth + COLUMN_GAP, 0 end
		local row = list.rows[index]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", list.frame, "TOPLEFT", x, -y)
		row:Show()
		y = y + heights[index]
		tallest = math.max(tallest, y)
	end
	for index = #specs + 1, #list.rows do list.rows[index]:Hide() end
	list.columns = second <= #specs and 2 or 1
	list.frame:SetSize(width, math.max(1, tallest))
	return tallest
end

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
			or (source and source ~= ns.Sources.GAME and (ns.Remove.ShouldHide(source, original)
				or (record.written[index] ~= nil and ns.Remove.IsWrittenHidden(source, record.site[index]))))
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
				-- Wrapped where the real one wrapped, so the copy is as wide as it was.
				tooltip:AddLine(left, lr, lg, lb, record.finalWrap[index] == true)
			end
			shown = shown + 1
			view.lineIndex[index] = shown
		end
	end
	tooltip:SetMinimumWidth(record.minWidth or 0)
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

local function BuildSources(canvas)
	local page = NewPage(L.PAGE_SOURCES, canvas)
	local y = TOP
	FieldCheck(page, "showSources", L.OPT_SHOW_SOURCES, L.OPT_SHOW_SOURCES_TIP, LEFT, y)
	y = y - ROW - 8
	Dropdown(page, L.OPT_SOURCES_LIST, 160, function()
		return { { value = "last", text = L.SOURCES_MODE_LAST }, { value = "addons", text = L.SOURCES_MODE_ADDONS } }
	end, function() return sourcesMode end, function(value)
		sourcesMode = value
		page:Draw()
	end, LEFT, y)
	y = y - ROW - 10
	local top = y -- where the current tooltip (Current tooltip) or the list (All addons) starts
	local BOTTOM = 16 -- below everything, inside the visible page

	-- The list of options: under the current tooltip, or straight under the controls for All addons. The page scrolls.
	local list = { rows = {}, frame = CreateFrame("Frame", nil, page) }
	list.frame:SetSize(1, 1)

	-- Current tooltip: the tooltip and its sources column on top, in a region at least half the page's height below the
	-- controls that scrolls sideways when they're wider than it (a long line, a wide column): a slider under it, and the
	-- mouse wheel over it, while there's anything to scroll.
	local viewport = CreateFrame("ScrollFrame", nil, page)
	viewport:SetPoint("TOPLEFT", LEFT, top)
	viewport:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, top)
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
		local scrolled = Readable(viewport:GetHorizontalScroll()) or 0
		slider:SetValue(math.max(0, math.min(range, scrolled - delta * SCROLL_STEP)))
	end)

	-- The page's visible height below the controls; nil until the panel has laid the page out.
	local function Remaining()
		local visible = Readable(page.scroll:GetHeight())
		if not visible or visible <= 1 then return nil end
		return math.max(0, visible + top - BOTTOM)
	end

	-- Puts the list under the tooltip region (or the controls) and lays it out in one or two columns for the room left.
	local function Layout()
		local listTop = top
		if sourcesMode == "last" and viewport:IsShown() then
			listTop = top - (Readable(viewport:GetHeight()) or 1) - (slider:IsShown() and 32 or 12)
		end
		list.frame:ClearAllPoints()
		list.frame:SetPoint("TOPLEFT", LEFT, listTop)
		local width = math.max(MIN_LIST, (Readable(page:GetWidth()) or 0) - LEFT - 8)
		local remaining = Remaining()
		DrawList(list, list.specs or {}, width, remaining and remaining - (top - listTop))
		page:FitHeight()
	end

	-- Sizes the region to the tooltip and its column once they're laid out (at least half the room below the controls),
	-- and shows the slider if they're wider.
	local function FitView()
		-- Any position the game keeps secret counts as not laid out (the preview's text is never secret, but be safe).
		local left, regionTop = Readable(stage:GetLeft()), Readable(stage:GetTop())
		local right, bottom = Readable(preview:GetRight()), Readable(preview:GetBottom())
		if sourcesMode ~= "last" or not (left and regionTop and right and bottom) or not preview:IsShown() then
			viewport:SetHeight(1)
			slider:Hide()
			viewport:EnableMouseWheel(false)
			Layout()
			return
		end
		local column = ns.SourcesView.ColumnOf(preview)
		if column and column:IsShown() then
			right = math.max(right, Readable(column:GetRight()) or right)
			bottom = math.min(bottom, Readable(column:GetBottom()) or bottom)
		end
		local width, height = right - left + 4, regionTop - bottom + 4
		stage:SetSize(width, height)
		viewport:SetHeight(math.max(height, math.floor((Remaining() or 0) / 2)))
		range = math.max(0, width - (Readable(viewport:GetWidth()) or width))
		if range > 0 then
			local scrolled = Readable(viewport:GetHorizontalScroll()) or 0
			slider:Init(math.min(scrolled, range), 0, range, math.max(1, math.floor(range / 20)))
			slider:Show()
		else
			viewport:SetHorizontalScroll(0)
			slider:Hide()
		end
		viewport:EnableMouseWheel(range > 0)
		Layout()
	end
	local FitViewSoon = ns.Throttled(FitView)
	preview:HookScript("OnSizeChanged", FitViewSoon)

	function page:Draw()
		if not self:IsVisible() then return end
		local last = sourcesMode == "last"
		list.specs = last and LastRows() or AddonRows()
		-- All addons has no current tooltip.
		viewport:SetShown(last)
		if last then
			DrawCurrentTooltip(preview, self, anchor)
		else
			preview:Hide()
			ns.SourcesView.Hide(preview)
			slider:Hide()
		end
		Layout()
		FitViewSoon()
	end
	-- The current tooltip changes as the player hovers things: drawn again while the page is open.
	ns.Listen("TOOLTIP_SEEN", function()
		if page:IsVisible() then page:Refresh() end
	end)
	page.list = list

	function page:OnDefault() DefaultsOf({ "showSources" }) end
	return page
end

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
	for _, page in ipairs(Kit.pages) do
		if page:IsVisible() then page:Refresh() end
	end
end
local RefreshShownSoon = ns.Throttled(RefreshShown)

ns.Listen("DB_READY", function()
	if categories.cleanup then return end
	-- Registered now, built when first shown (Kit.Canvas): the previews and their hooks aren't made during the login
	-- loading screen, or at all for players who never open the options.
	local root = Settings.RegisterCanvasLayoutCategory(Kit.Canvas(BuildCleanup), TITLE)
	categories.cleanup = root
	categories.look = Settings.RegisterCanvasLayoutSubcategory(root, Kit.Canvas(BuildLook), L.PAGE_LOOK)
	categories.sources = Settings.RegisterCanvasLayoutSubcategory(root, Kit.Canvas(BuildSources), L.PAGE_SOURCES)
	categories.profiles = Settings.RegisterCanvasLayoutSubcategory(root, Kit.Canvas(Options.BuildProfiles),
		L.PAGE_PROFILES)
	Settings.RegisterAddOnCategory(root)
end)

ns.Listen("SETTINGS_CHANGED", RefreshShownSoon)
ns.Listen("RULES_CHANGED", RefreshShownSoon)
ns.Listen("SOURCE_SEEN", RefreshShownSoon)
