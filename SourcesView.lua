local _, ns = ...
local L = ns.L

-- The sources column: a thin column on the tooltip's right edge, outside it, naming the addon
-- beside each line an addon added. The tooltip itself isn't touched, so its layout is what the player sees without
-- the column. Lines the game added show nothing. Lines CT removed are listed under the tooltip's lines, struck
-- through, so the player sees what's being taken out.
--   ns.SourcesView.Draw(tooltip, record, inline)   draws the column for a record; inline: the removed lines are still
--                                                  in the tooltip, so they're struck through on their own rows.
--                                                  record.lineIndex[i], if given, is line i's place in the tooltip.
--   ns.SourcesView.Hide(tooltip), ColumnOf(tooltip)

ns.SourcesView = {}
local View = ns.SourcesView

local PAD = 6
local ROW_GAP = 2
local MAX_WIDTH = 220 -- longer removed lines wrap rather than run on

local columns = setmetatable({}, { __mode = "k" })

local function Column(tooltip)
	local column = columns[tooltip]
	if column then return column end
	column = CreateFrame("Frame", nil, tooltip, "TooltipBackdropTemplate")
	column:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", -1, 0)
	column.rows = {}
	columns[tooltip] = column
	return column
end

local function Row(column, index)
	local row = column.rows[index]
	if not row then
		row = column:CreateFontString(nil, "ARTWORK", "GameTooltipTextSmall")
		row:SetJustifyH("LEFT")
		row.strike = column:CreateTexture(nil, "OVERLAY")
		row.strike:SetColorTexture(1, 1, 1, 0.8)
		row.strike:SetHeight(1)
		row.strike:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.strike:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		column.rows[index] = row
	end
	row:ClearAllPoints()
	row:SetWidth(0)
	row:Show()
	return row
end

-- An addon as the column names it: its icon at line height, if it has one, then its title.
local function Label(folder) return ns.Sources.Label(folder, 0) end

local function LineText(record, index)
	local text = record.written[index] or record.left[index] or record.right[index] -- as written into, if it was
	return ns.PlainText(text) or ""
end

-- What the column shows beside line `index`, or nil.
local function Describe(record, index)
	local source, edited = record.source[index], record.edited[index]
	local own = source and source ~= ns.Sources.GAME and Label(source) or nil
	if edited then
		local editedText = L.SOURCES_EDITED:format(Label(edited))
		return own and (own .. ", " .. editedText) or editedText
	end
	return own
end

local function Readable(value)
	value = ns.Readable(value)
	return type(value) == "number" and value or nil
end

-- The column drawn for a tooltip, if any (the Sources page sizes its scrolling region to include it).
function View.ColumnOf(tooltip)
	return columns[tooltip]
end

function View.Hide(tooltip)
	local column = columns[tooltip]
	if column then column:Hide() end
end

function View.Draw(tooltip, record, inline)
	if not record or not record.addons then return View.Hide(tooltip) end
	local column = Column(tooltip)
	for _, row in ipairs(column.rows) do
		row:Hide()
		row.strike:Hide()
	end

	local top = Readable(tooltip:GetTop())
	local height = Readable(tooltip:GetHeight()) or 0
	local count, width, bottom = 0, 0, 0
	local gray = GRAY_FONT_COLOR

	local function Place(text, y, struck)
		count = count + 1
		local row = Row(column, count)
		row:SetText(text)
		local rowWidth = math.min(row:GetUnboundedStringWidth(), MAX_WIDTH)
		row:SetWidth(rowWidth)
		row:SetPoint("TOPLEFT", column, "TOPLEFT", PAD, y)
		row:SetTextColor(gray.r, gray.g, gray.b)
		row.strike:SetShown(struck)
		width = math.max(width, rowWidth)
		bottom = math.min(bottom, y - row:GetStringHeight())
	end

	-- Beside their lines.
	for index = 1, record.n do
		local hidden = record.hidden[index]
		if not hidden or inline then
			local text = Describe(record, index)
			if hidden then text = Label(record.source[index]) end
			-- A redrawn record may have left lines out: lineIndex maps its line to the tooltip's (the Sources page).
			local lineIndex = record.lineIndex and record.lineIndex[index] or index
			local line = text and top and ns.Line(tooltip, lineIndex)
			local lineTop = line and Readable(line:GetTop())
			if lineTop then Place(text, lineTop - top, hidden) end
		end
	end

	-- Removed lines, under the tooltip's own.
	if not inline then
		local y = -height
		for index = 1, record.n do
			if record.hidden[index] then
				local text = L.SOURCES_REMOVED:format(Label(record.source[index]), LineText(record, index))
				Place(text, y, true)
				y = bottom - ROW_GAP
			end
		end
	end

	if count == 0 then return column:Hide() end
	column:SetSize(width + 2 * PAD, math.max(height, PAD - bottom))
	column:Show()
end

-- The live tooltips -----------------------------------------------------------------------------------------------------

local hooked = setmetatable({}, { __mode = "k" })

local function Update(tooltip)
	if not (ns.profile and ns.profile.showSources) then return View.Hide(tooltip) end
	View.Draw(tooltip, ns.Sources.Record(tooltip), false)
end

local UpdateHook = ns.Guarded("sources column", Update)
local HideHook = ns.Guarded("sources column", function(tooltip) View.Hide(tooltip) end)

local function Hook(tooltip)
	if hooked[tooltip] then return end
	hooked[tooltip] = true
	hooksecurefunc(tooltip, "Show", UpdateHook)
	tooltip:HookScript("OnHide", HideHook)
end

local function HookNamed()
	for _, name in ipairs(ns.TOOLTIPS) do
		local tooltip = _G[name]
		if tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden()) then Hook(tooltip) end
	end
end

HookNamed()
ns.Listen("LOGIN", HookNamed)

local function Redraw()
	for tooltip in pairs(hooked) do
		if tooltip:IsShown() then Update(tooltip) else View.Hide(tooltip) end
	end
end

ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil or what == "showSources" then Redraw() end
end)

-- The key binding and /ctt sources.
function ns.ToggleSources()
	if not ns.profile then return end
	ns.profile.showSources = not ns.profile.showSources
	ns.Changed("showSources")
end

CleanTooltips_ToggleSources = ns.ToggleSources
BINDING_HEADER_CLEANTOOLTIPS = "Clean Tooltips"
BINDING_NAME_CLEANTOOLTIPS_SOURCES = L.BINDING_SOURCES
