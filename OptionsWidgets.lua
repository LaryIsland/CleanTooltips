local _, ns = ...
local L = ns.L

-- The options pages' building blocks, shared by Options.lua (Clean-up, Look, Sources) and
-- Profiles.lua: checkboxes, dropdowns, scrolling canvas pages and refusing in combat. Every page is a canvas page, CT's
-- own frames, built the first time the Settings panel shows it, not at login.
--   ns.OptionsKit   the constants and functions below

ns.OptionsKit = {}
local Kit = ns.OptionsKit

Kit.TITLE = "Clean Tooltips"
Kit.LEFT = 16          -- the pages' left margin
Kit.TOP = -56          -- the first row, under the page's title
Kit.ROW = 28           -- one checkbox row
Kit.INDENT = 24        -- a checkbox that depends on the one above
Kit.LABEL_WIDTH = 150  -- a dropdown's or swatch's label, before its control
local MENU_HEIGHT = 320 -- long dropdown menus scroll past this
local LABEL_WIDTH = Kit.LABEL_WIDTH

Kit.pages = {}         -- every page built so far
local pages = Kit.pages

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
	if text then GameTooltip_AddNormalLine(GameTooltip, text, true) end
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
local PAN_EXTENT = 30    -- pixels a mouse wheel notch scrolls (Blizzard's default for scroll frames)

local Readable = ns.Readable

-- A ScrollFrameTemplate frame whose scroll bar works from the content height CT sets (`scroll:SetContentHeight`), never
-- from the frame's own scroll range. Blizzard's wiring (ScrollUtil.InitScrollFrameWithScrollBar) does arithmetic on
-- `GetVerticalScrollRange()`, which the game makes secret once something secret is laid out in the scroll child (a
-- unit preview, Look page), and the error is blamed on CT. So the three handlers it set on this frame are replaced with
-- ones that use only CT's own numbers.
local function SafeScroll(scroll, child)
	local bar = scroll.ScrollBar
	local contentHeight, offset = 1, 0
	local function ViewHeight()
		return Readable(scroll:GetHeight()) or 0
	end
	local function Range()
		return math.max(0, contentHeight - ViewHeight())
	end
	local function Update()
		local range, view = Range(), ViewHeight()
		offset = math.min(offset, range)
		scroll:SetVerticalScroll(offset)
		if not bar then return end
		bar:SetVisibleExtentPercentage(view > 0 and view / (range + view) or 0)
		bar:SetPanExtentPercentage(range > 0 and math.min(1, PAN_EXTENT / range) or 0)
		bar:SetScrollPercentage(range > 0 and offset / range or 0, ScrollBoxConstants and ScrollBoxConstants.NoScrollInterpolation)
	end
	scroll:SetScript("OnScrollRangeChanged", Update)
	scroll:SetScript("OnVerticalScroll", function(_, value)
		value = Readable(value)
		if value then offset = value end
		local range = Range()
		if bar then
			bar:SetScrollPercentage(range > 0 and offset / range or 0,
				ScrollBoxConstants and ScrollBoxConstants.NoScrollInterpolation)
		end
	end)
	if bar and BaseScrollBoxEvents then
		bar:UnregisterCallback(BaseScrollBoxEvents.OnScroll, scroll)
		bar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(_, percentage)
			percentage = Readable(percentage)
			if not percentage then return end
			offset = percentage * Range()
			scroll:SetVerticalScroll(offset)
		end, scroll)
	end
	-- Sizes the scroll child and updates the bar. Only this sets the child's height.
	function scroll:SetContentHeight(height)
		contentHeight = math.max(1, height)
		child:SetHeight(contentHeight)
		Update()
	end
end

local function NewPage(title, canvas)
	local scroll = CreateFrame("ScrollFrame", nil, canvas, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_GAP, 0)
	if scroll.ScrollBar and scroll.ScrollBar.SetHideIfUnscrollable then scroll.ScrollBar:SetHideIfUnscrollable(true) end
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(1, 1)
	scroll:SetScrollChild(page)
	SafeScroll(scroll, page)
	page.canvas, page.scroll = canvas, scroll
	page.refreshers = {}
	local heading = Text(page, "GameFontHighlightHuge", title)
	heading:SetPoint("TOPLEFT", 7, -16)

	-- As tall as the lowest thing on it, and never shorter than the visible area. Once a frame, however often asked.
	-- Positions the game keeps secret (a unit preview's, while its text is secret) are left out.
	local fitQueued = false
	local function Fit()
		fitQueued = false
		local top = Readable(page:GetTop())
		if not top then return end
		local lowest = top
		local function Consider(thing)
			if Readable(thing:IsShown()) then
				local bottom = Readable(thing:GetBottom())
				if bottom and bottom < lowest then lowest = bottom end
			end
		end
		for _, child in ipairs({ page:GetChildren() }) do Consider(child) end
		for _, region in ipairs({ page:GetRegions() }) do Consider(region) end
		scroll:SetContentHeight(math.max(top - lowest + FIT_MARGIN, Readable(scroll:GetHeight()) or 1))
	end
	function page:FitHeight()
		if fitQueued then return end
		fitQueued = true
		C_Timer.After(0, Fit)
	end
	-- The page is as wide as the visible area: the Sources page's preview region is anchored to its right edge. Set
	-- when the scroll frame's size changes, and whenever the page is drawn, as a page built while the panel is already
	-- shown (Kit.Canvas) may never see a size change, and would stay 1 wide and clip the Sources preview to nothing.
	local function FitWidth(width)
		width = Readable(width)
		if width and width > 1 and width ~= Readable(page:GetWidth()) then page:SetWidth(width) end
	end
	scroll:SetScript("OnSizeChanged", function(_, width)
		FitWidth(width)
		page:FitHeight()
	end)

	function page:Refresh()
		if not ns.profile then return end
		FitWidth(scroll:GetWidth())
		for _, refresh in ipairs(self.refreshers) do refresh() end
		local draw = rawget(self, "Draw") -- the pages with previews have one; Profiles doesn't
		if draw then ns.SafeCall("preview", draw, self) end
		self:FitHeight()
	end
	pages[#pages + 1] = page
	return page
end

-- The frame registered with the Settings panel for a page. `build(canvas)` makes the page (with NewPage) the first
-- time the panel shows it, or asks for its Defaults; until then the page costs one empty frame.
function Kit.Canvas(build)
	local canvas = CreateFrame("Frame")
	canvas:Hide()
	local page
	local function Page()
		if not page then
			page = build(canvas)
			canvas.page = page
		end
		return page
	end
	-- The Settings panel calls these on the registered frame.
	canvas.OnRefresh = function()
		if page then page:Refresh() end
	end
	canvas.OnDefault = function()
		local built = Page()
		local default = rawget(built, "OnDefault")
		if default then default(built) end
	end
	-- While a page is shown, attribution runs on every tooltip, so its lists fill (Sources.lua's gate).
	canvas:SetScript("OnShow", function()
		ns.Sources.SetOptionsShown(canvas, true)
		Page():Refresh()
	end)
	canvas:SetScript("OnHide", function() ns.Sources.SetOptionsShown(canvas, false) end)
	return canvas
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

-- A labelled dropdown. choices() gives { { value, text }, ... }; labelWidth, if given, replaces LABEL_WIDTH.
local function Dropdown(page, labelText, width, choices, get, set, x, y, labelWidth)
	local label = Text(page, "GameFontHighlight", labelText)
	label:SetPoint("TOPLEFT", x, y - 7)
	local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("TOPLEFT", x + (labelWidth or LABEL_WIDTH), y)
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

Kit.RefuseInCombat = RefuseInCombat
Kit.AddTip = AddTip
Kit.Text = Text
Kit.Check = Check
Kit.ClickSound = ClickSound
Kit.ShowTip = ShowTip
Kit.HideTip = HideTip
Kit.NewPage = NewPage
Kit.FieldCheck = FieldCheck
Kit.Dropdown = Dropdown
Kit.DefaultsOf = DefaultsOf
