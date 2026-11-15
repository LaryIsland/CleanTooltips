local addonName, ns = ...

-- Which addon added each tooltip line (design document 4.1). Nothing in the API says, so the hooks on the tooltip's
-- AddLine, AddDoubleLine and SetText ask the call stack, and the hook on each line's font string notices lines
-- another addon rewrote. Every line's record is kept until the tooltip is cleared.
--
-- A record (ns.Sources.Record(tooltip), or the current tooltip's with ns.Sources.Current()):
--   n            lines recorded
--   source[i]    the addon folder that added line i, ns.Sources.GAME for the game, nil when unknown (secret stack)
--   edited[i]    the addon folder that rewrote line i
--   hidden[i]    true when CT removed line i (Remove.lua)
--   left[i], right[i]           the line's text when it was added (nil when secret)
--   lr/lg/lb[i], rr/rg/rb[i]    its colours when it was added
--   finalLeft/finalRight[i], flr/flg/flb[i], frr/frg/frb[i], finalShown[i], border, center
--                as the player saw it when the tooltip was last shown (CT's changes and other addons' included):
--                kept for the current tooltip, for the Sources page's preview
--   addons       true when any line came from an addon
--
--   ns.Sources.Watch(tooltip)            hooks a tooltip (the named ones are hooked at load)
--   ns.Sources.Seen()                    [folder] = { lines = { text, ... }, listed, candidates, candidateCount }
--   ns.Sources.Current()                 the current tooltip's record
--   ns.Sources.Title(folder), Icon(folder), Label(folder, iconSize)
--   ns.Sources.Shape(text), IsBlank(text)

ns.Sources = {}
local Sources = ns.Sources

local GAME = "*game" -- folder names can't contain *
Sources.GAME = GAME

local records = setmetatable({}, { __mode = "k" })  -- [tooltip] = its record
local fontLines = setmetatable({}, { __mode = "k" }) -- [font string] = { tooltip, index }
local watched = setmetatable({}, { __mode = "k" })
local current -- the record of the latest item or unit tooltip shown (not CT's previews or option hints)

-- Development counters for /ctt perf (Dev.lua): calls, stacks read, cache hits, and time when Sources.timing is set.
Sources.stats = { calls = 0, stacks = 0, hits = 0, secret = 0, pipeline = 0, byText = 0, ms = 0 }
Sources.timing = false
Sources.shortcut = true -- the pipeline and text shortcuts below; off only to compare costs (harness, /ctt perf)
Sources.probe = nil -- Dev.lua's stack probe: called with every raw stack read

-- Reading the call stack ---------------------------------------------------------------------------------------------

-- Library paths: embedded (Foo/libs/LibBar/...) or stand-alone library addons (LibBar, Ace3). Libraries load from
-- whichever addon loaded them first, so the folder a library lives in isn't the addon using it.
local function IsLibrary(folder, path)
	local lower = path:lower():gsub("\\", "/")
	if lower:find("^libs?/") or lower:find("/libs?/") or lower:find("^libraries/") or lower:find("/libraries/") then
		return true
	end
	return folder:find("^Lib") ~= nil or folder:find("^!?LibStub") ~= nil or folder == "Ace3"
end

-- Long paths may come back shortened from the front ("...ns/Blizzard_SharedXMLGame/Tooltip/..."), as Lua does with
-- its chunk names. When the cut falls in "Interface/AddOns" the folder is whole; when it falls in the folder's name,
-- the loaded addon whose name ends with what's left is the folder, if only one does.
local INTERFACE_ADDONS = "interface/addons"
local PIPELINE = "Blizzard_SharedXMLGame"
local endingWith = {}

local function FolderEndingWith(partial)
	local found = endingWith[partial]
	if found ~= nil then return found or nil end
	found = false
	local lower = partial:lower()
	if PIPELINE:lower():sub(-#lower) == lower then
		found = PIPELINE
	else
		for i = 1, C_AddOns.GetNumAddOns() do
			local name = C_AddOns.GetAddOnInfo(i)
			if type(name) == "string" and name:lower():sub(-#lower) == lower then
				if found then
					found = false
					break
				end
				found = name
			end
		end
	end
	endingWith[partial] = found
	return found or nil
end

-- The addon folder and the path inside it in one frame of a stack, or nil.
local function FolderOf(frame)
	local folder, path = frame:match("[Aa][Dd][Dd][Oo][Nn][Ss][/\\]([^/\\]+)[/\\]([^:\"%]>]+)")
	if folder then return folder, path end
	local tail = frame:match("%.%.%.([^:\"%]>]+)")
	if not tail then return nil end
	local first, rest = tail:match("^([^/\\]*)[/\\](.+)$")
	if not first then return nil end
	if INTERFACE_ADDONS:sub(-#first) == first:lower() then
		return rest:match("^([^/\\]+)[/\\](.+)$")
	end
	if first == "" then return nil end
	return FolderEndingWith(first), rest
end

-- The source in a debugstack text. Frames are read from the line's caller outwards:
--   1. CT's own frames and frames with no addon path ([C], tail calls) are skipped.
--   2. Blizzard's tooltip data pipeline (Blizzard_SharedXMLGame/Tooltip) means the game added the line. Other Blizzard
--      frames are helpers (GameTooltip_AddColoredLine) that an addon may have called, so the walk goes on.
--   3. A library frame is remembered and the walk goes on, to the addon using it.
--   4. The first other addon is the source; if only a library was seen, it's the source; otherwise the game.
function Sources.Parse(stack)
	local library
	for frame in stack:gmatch("[^\n]+") do
		local folder, path = FolderOf(frame)
		if folder and folder ~= addonName then
			if folder:find("^Blizzard_") then
				if folder == PIPELINE and path:find("^Tooltip[/\\]") then
					return library or GAME
				end
			elseif IsLibrary(folder, path) then
				library = library or folder
			else
				return folder
			end
		end
	end
	return library or GAME
end

local STACK_CACHE_SIZE = 1000
local stackCache, stackCached = {}, 0

-- The source of the line being added now. nil when the stack is secret (design document 4.1, Beta Checks 6).
local function Caller()
	local stats = Sources.stats
	stats.stacks = stats.stacks + 1
	-- From Caller's caller; CT's own frames are skipped in Parse, so the exact depth doesn't matter.
	local stack = debugstack(2, 16, 0)
	if Sources.probe then Sources.probe(stack) end
	if ns.IsSecret(stack) or stack == nil then
		stats.secret = stats.secret + 1
		return nil
	end
	local source = stackCache[stack]
	if source then
		stats.hits = stats.hits + 1
		return source
	end
	source = Sources.Parse(stack)
	if stackCached >= STACK_CACHE_SIZE then
		stackCache, stackCached = {}, 0
	end
	stackCache[stack] = source
	stackCached = stackCached + 1
	return source
end

-- The text shortcut: a line (or a rewrite) whose text has been attributed before takes the same source without
-- reading the stack. At launch (15 Nov, /ctt perf on a weapon) nearly every stack still read was the same texts again
-- and again: the comparison tooltips' "If you replace this item..." lines (the game's, added outside its data), and
-- addons' fixed lines and rewrites (AllTheThings' icon, Auctionator's "Vendor"). Blank lines are left out: the game and
-- addons both add " ", and a removal rule may name one addon's. The one case it gets wrong: two sources adding the
-- very same text, where the second takes the first's name. Separate tables for added and rewritten lines. The same
-- table answers for a line whose stack is secret (in combat): most addon lines are the same text every time.
local TEXT_SHORTCUT_SIZE = 1000
local byText = { added = {}, rewrite = {} }
local byTextCount = { added = 0, rewrite = 0 }

local function Known(which, text)
	if text == nil or not text:find("%S") then return nil end
	return byText[which][text]
end

-- Not while /ctt probe wants to see stacks (Dev.lua), or the probe's own line is read only once.
local function ByText(which, text)
	if not Sources.shortcut or Sources.probe then return nil end
	return Known(which, text)
end

-- Only while the pipeline shortcut is on, so the game's own data lines (which it takes) are never remembered and can't
-- lend their source to an addon's copy of the same text.
local function RememberText(which, text, source)
	if not Sources.shortcut or source == nil or text == nil or not text:find("%S") or byText[which][text] == source then
		return
	end
	if byTextCount[which] >= TEXT_SHORTCUT_SIZE then
		byText[which], byTextCount[which] = {}, 0
	end
	byText[which][text] = source
	byTextCount[which] = byTextCount[which] + 1
end

-- For tests and /ctt perf: start the text shortcut empty.
function Sources.ForgetTexts()
	byText.added, byText.rewrite = {}, {}
	byTextCount.added, byTextCount.rewrite = 0, 0
end

-- Addons seen this session ----------------------------------------------------------------------------------------------

-- A line's shape: its text without colour codes and icons, with every number as "#", so a line whose numbers change
-- ("Vendor 1g 2s", "Bags: 3") is one line for listing and removal rules. "" for a blank line.
local SHAPE_CACHE_SIZE = 500
local shapes, shapeCount = {}, 0

function Sources.Shape(text)
	if type(text) ~= "string" then return nil end
	local shape = shapes[text]
	if shape == nil then
		shape = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		shape = shape:gsub("%d[%d,%.]*", "#"):gsub("%s+", " ")
		shape = shape:gsub("^ ", ""):gsub(" $", "")
		if shapeCount >= SHAPE_CACHE_SIZE then shapes, shapeCount = {}, 0 end
		shapes[text] = shape
		shapeCount = shapeCount + 1
	end
	return shape
end

local function IsBlank(text)
	return text ~= nil and not text:find("%S")
end
Sources.IsBlank = IsBlank

-- What a tooltip is about, so a line's subjects can be counted: an item, an NPC type (every Kobold Vermin is one), a
-- player, or another kind of data. nil when it can't be read (secret in combat).
local function SubjectOf(data)
	if not data then return nil end
	local dataType, id, guid = data.type, data.id, data.guid
	if ns.IsSecret(dataType) or ns.IsSecret(id) or ns.IsSecret(guid) then return nil end
	if type(guid) == "string" then
		local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
		if npc then return kind .. ":" .. npc end
		return guid
	end
	if id == nil then return nil end
	return tostring(dataType) .. ":" .. tostring(id)
end

-- Addons seen this session, and the lines the Sources page lists for each. Only lines an addon shows all the time are
-- listed: a line is listed once it has been added to PERMANENT different subjects (items, NPC types, players), so a
-- line for one quest's mobs or items (Questie's objectives) stays off the list. Blank lines are never listed: they
-- follow the addon's lines next to them (Added, below).
local seen = {}
local PERMANENT = 3        -- different subjects before a line is listed
local MAX_LISTED = 12      -- lines listed per addon
local MAX_CANDIDATES = 60  -- lines counted per addon while they wait

local function Seen(folder, text, subject)
	local entry = seen[folder]
	if not entry then
		entry = { lines = {}, listed = {}, candidates = {}, candidateCount = 0 }
		seen[folder] = entry
		ns.Fire("SOURCE_SEEN", folder)
	end
	if text == nil or subject == nil or IsBlank(text) or #entry.lines >= MAX_LISTED then return end
	local shape = Sources.Shape(text)
	if shape == "" or entry.listed[shape] then return end
	local subjects = entry.candidates[shape]
	if not subjects then
		-- Full of lines that never came round again (quest objectives): start counting afresh.
		if entry.candidateCount >= MAX_CANDIDATES then entry.candidates, entry.candidateCount = {}, 0 end
		subjects = { n = 0 }
		entry.candidates[shape] = subjects
		entry.candidateCount = entry.candidateCount + 1
	end
	if subjects[subject] then return end
	subjects[subject] = true
	subjects.n = subjects.n + 1
	if subjects.n >= PERMANENT then
		entry.listed[shape] = true
		entry.lines[#entry.lines + 1] = text
		entry.candidates[shape] = nil
		entry.candidateCount = entry.candidateCount - 1
		ns.Fire("SOURCE_SEEN", folder)
	end
end

function Sources.Seen()
	return seen
end

local titles = {}
function Sources.Title(folder)
	if folder == GAME then return nil end
	local title = titles[folder]
	if not title then
		title = ns.PlainText(C_AddOns.GetAddOnTitle(folder)) or folder
		if title == "" then title = folder end
		titles[folder] = title
	end
	return title
end

local icons = {} -- [folder] = its icon, or false
function Sources.Icon(folder)
	if folder == GAME then return nil end
	local icon = icons[folder]
	if icon == nil then
		icon = C_AddOns.GetAddOnMetadata(folder, "IconTexture")
		if icon == "" or type(icon) ~= "string" then icon = false end
		icons[folder] = icon
	end
	return icon or nil
end

-- An addon's title with its icon in front, for the Sources page (iconSize 16) and the sources column (0: line height).
function Sources.Label(folder, iconSize)
	local title = Sources.Title(folder) or folder
	local icon = Sources.Icon(folder)
	if icon then return "|T" .. icon .. ":" .. (iconSize or 0) .. "|t " .. title end
	return title
end

-- Records ------------------------------------------------------------------------------------------------------------

local RECORD_TABLES = { "source", "edited", "hidden", "left", "right", "lr", "lg", "lb", "rr", "rg", "rb",
	"finalLeft", "finalRight", "flr", "flg", "flb", "frr", "frg", "frb", "finalShown",
	"lastHidden",     -- [folder] = whether that addon's last non-blank line here was hidden
	"pendingBlanks" } -- [folder] = its blank lines waiting on its next line

local function ResetRecord(record)
	record.n, record.addons = 0, false
	record.fromData = false -- built by the game's data pipeline (an item, unit, spell...), not with SetText
	record.subject = nil    -- what it's about (SubjectOf), false when unreadable
	record.border, record.center, record.borderGrey = nil, nil, nil
	for _, key in ipairs(RECORD_TABLES) do
		local t = record[key]
		if t then wipe(t) else record[key] = {} end
	end
	return record
end

local function NewRecord()
	return ResetRecord({})
end

function Sources.Record(tooltip)
	return records[tooltip]
end

-- The current tooltip: the latest item or unit tooltip shown, kept after it's hidden until the next one. The Sources
-- page shows it and lists its lines (/ctt last); TOOLTIP_SEEN tells it, at most once a frame, that it changed.
function Sources.Current()
	return current
end

local NotifySeen = ns.Throttled(function() ns.Fire("TOOLTIP_SEEN") end)

local pending -- below: the text the pipeline adds next, per tooltip

-- A cleared tooltip starts afresh. Its record is wiped and reused (bag and comparison tooltips clear many times a
-- second), unless it's the current tooltip, which stays whole for the Sources page until the next one.
local function Clear(tooltip)
	pending[tooltip] = nil
	local record = records[tooltip]
	if not record or record.n == 0 then return end
	if ns.Remove then ns.Remove.Restore(tooltip, record) end
	if record == current then
		records[tooltip] = NewRecord()
	else
		ResetRecord(record)
	end
end

local function ReadText(fontString)
	if not fontString then return nil end
	local text = fontString:GetText()
	if ns.IsSecret(text) or text == nil then return nil end
	return text
end

local function ReadColor(fontString)
	if not fontString then return 1, 1, 1 end
	local r, g, b = fontString:GetTextColor()
	if ns.IsSecret(r) or ns.IsSecret(g) or ns.IsSecret(b) then return 1, 1, 1 end
	return r, g, b
end

local OnLineSetText -- below

local function WatchLine(tooltip, index, fontString)
	if not fontString then return end
	local entry = fontLines[fontString]
	if not entry then
		fontLines[fontString] = { tooltip, index }
		hooksecurefunc(fontString, "SetText", OnLineSetText)
	end
end

-- The game's own lines without reading the stack. Most lines are the data pipeline's, and debugstack costs about
-- 30 us a line in game (Beta Checks 7), so a line pre-call notes the text the pipeline is about to add, and the AddLine
-- that follows with exactly that text is the game's. Anything else (another addon's line added from its own pre-call or
-- post-call, a secret or empty text) still reads the stack. The note is dropped once used, by the line's post-call, and
-- when the tooltip is cleared or finished: a later addon pre-call that consumes the line skips its post-calls, and
-- the note mustn't outlive it to claim an addon's line with the same text for the game.
pending = setmetatable({}, { __mode = "k" }) -- [tooltip] = the text the pipeline adds next

-- A tooltip the game's data pipeline builds (an item, a unit, a spell...): marked as it starts, with what it's about,
-- just after the pipeline cleared it (so on its new record). Only these become the current tooltip and count towards
-- an addon's lasting lines; a tooltip made with SetText (an option's hint) never does, even if it still holds the
-- data of what it showed before.
TooltipDataProcessor.AddTooltipPreCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
	if ns.raw[tooltip] or not watched[tooltip] then return end
	local record = records[tooltip]
	if not record then
		record = NewRecord()
		records[tooltip] = record
	end
	record.fromData = true
	record.subject = SubjectOf(data) or false
end)

TooltipDataProcessor.AddLinePreCall(TooltipDataProcessor.AllTypes, function(tooltip, lineData)
	if ns.raw[tooltip] or not watched[tooltip] then return end
	local text = lineData.leftText
	if text == nil or ns.IsSecret(text) or type(text) ~= "string" or text == "" then
		text = lineData.rightText
		if text == nil or ns.IsSecret(text) or type(text) ~= "string" or text == "" then text = nil end
	end
	pending[tooltip] = text
end)

TooltipDataProcessor.AddLinePostCall(TooltipDataProcessor.AllTypes, function(tooltip)
	pending[tooltip] = nil
end)

TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip)
	pending[tooltip] = nil
end)

-- While /ctt perf runs (Dev.lua sets Sources.misses to a table): every stack read, by what it found, with a few sample
-- texts, so the report says which lines miss the shortcut and why. [label] = { n, samples = { text, ... } }
Sources.misses = nil
local MISS_SAMPLES = 3

local function Missed(label, text, tooltip)
	local misses = Sources.misses
	if not misses then return end
	local entry = misses[label]
	if not entry then
		entry = { n = 0, samples = {}, tooltips = {} }
		misses[label] = entry
	end
	entry.n = entry.n + 1
	local name = tooltip and tooltip:GetName()
	if name then entry.tooltips[name] = true end
	if text and #entry.samples < MISS_SAMPLES and not tContains(entry.samples, text) then
		entry.samples[#entry.samples + 1] = text
	end
end

local function MissLabel(source, expected)
	if source == nil then return "unknown (secret stack)" end
	if source ~= GAME then return source end
	if expected == nil then return "the game, a line not from its data (added by a Blizzard post-call or helper)" end
	return "the game, text not as in its data"
end

-- Line `index` was just added by whoever is calling.
local function Added(tooltip, index)
	local stats = Sources.stats
	stats.calls = stats.calls + 1
	local started = Sources.timing and debugprofilestop()

	local record = records[tooltip]
	if not record then
		record = NewRecord()
		records[tooltip] = record
	end
	local left, right = ns.Line(tooltip, index)
	WatchLine(tooltip, index, left)
	WatchLine(tooltip, index, right)
	-- A tooltip the data pipeline builds (not an option's hint) is the current tooltip.
	if record.fromData then
		current = record
		NotifySeen()
	end

	local leftText, rightText = ReadText(left), ReadText(right)
	local key = leftText or rightText
	local expected = pending[tooltip]
	local source
	if expected ~= nil and Sources.shortcut and (expected == leftText or (leftText == nil and expected == rightText)) then
		pending[tooltip] = nil
		stats.pipeline = stats.pipeline + 1
		source = GAME
	else
		source = ByText("added", key)
		if source then
			stats.byText = stats.byText + 1
		else
			source = Caller()
			RememberText("added", key, source)
			if Sources.misses then
				local shown = key
				if source == GAME and expected ~= nil then
					shown = tostring(shown) .. " (data: " .. tostring(expected) .. ")"
				end
				Missed(MissLabel(source, expected), shown, tooltip)
			end
		end
	end
	-- A secret stack: the line goes by its text if a readable stack named it before (never a blank line).
	if source == nil then source = Known("added", key) end

	record.n = index
	record.source[index] = source
	record.left[index], record.right[index] = leftText, rightText
	record.lr[index], record.lg[index], record.lb[index] = ReadColor(left)
	if right and right:IsShown() then
		record.rr[index], record.rg[index], record.rb[index] = ReadColor(right)
	end
	if source and source ~= GAME then
		record.addons = true
		Seen(source, key, record.subject or nil)
		if ns.Remove then
			-- A blank line goes with the addon's lines beside it: hidden if its line before was, or (when it comes
			-- first) once its next line turns out hidden. So a spacer never stays behind a removed line.
			local blank = IsBlank(key)
			local hide = ns.Remove.ShouldHide(source, key)
			if blank and not hide then
				if record.lastHidden[source] then
					hide = true
				else
					local pendingBlanks = record.pendingBlanks[source] or {}
					pendingBlanks[#pendingBlanks + 1] = index
					record.pendingBlanks[source] = pendingBlanks
				end
			end
			if hide then ns.Remove.Hide(tooltip, record, index) end
			if not blank then
				local pendingBlanks = record.pendingBlanks[source]
				if pendingBlanks and hide then
					for _, blankIndex in ipairs(pendingBlanks) do ns.Remove.Hide(tooltip, record, blankIndex) end
				end
				record.pendingBlanks[source] = nil
				record.lastHidden[source] = hide
			end
		end
	end

	if started then stats.ms = stats.ms + debugprofilestop() - started end
end

local function OnAddLine(tooltip)
	if ns.editing then return end
	local index = tooltip:NumLines()
	if type(index) == "number" and index > 0 then Added(tooltip, index) end
end

-- SetText starts the tooltip again with one line.
local function OnSetText(tooltip)
	if ns.editing then return end
	Clear(tooltip)
	OnAddLine(tooltip)
end

-- Another addon rewrote a line's text: shown in the sources column, never removed (design document 4.1).
function OnLineSetText(fontString)
	if ns.editing then return end
	local entry = fontLines[fontString]
	local tooltip, index = entry[1], entry[2]
	local record = records[tooltip]
	if not record or index > record.n then return end
	local started = Sources.timing and debugprofilestop()
	local text = ReadText(fontString)
	local source = ByText("rewrite", text)
	if source then
		Sources.stats.byText = Sources.stats.byText + 1
	else
		source = Caller()
		RememberText("rewrite", text, source)
		if Sources.misses then
			Missed("rewrites by " .. (source == GAME and "the game" or tostring(source or "unknown (secret stack)")),
				text, tooltip)
		end
	end
	if source and source ~= GAME and source ~= record.source[index] then
		record.edited[index] = source
		record.addons = true
	end
	if started then Sources.stats.ms = Sources.stats.ms + debugprofilestop() - started end
end

-- The current tooltip as the player saw it, each time it's shown: every line's final text, colours and whether it's
-- shown (after CT's shortening, colouring and removal, and other addons' changes), and the frame's colours.
local function Snapshot(tooltip)
	local record = records[tooltip]
	if not record or record ~= current then return end
	for index = 1, record.n do
		local left, right = ns.Line(tooltip, index)
		local leftShown = left and left:IsShown() or false
		local rightShown = right and right:IsShown() or false
		record.finalShown[index] = leftShown or rightShown
		record.finalLeft[index] = leftShown and ReadText(left) or nil
		record.finalRight[index] = rightShown and ReadText(right) or nil
		record.flr[index], record.flg[index], record.flb[index] = ReadColor(left)
		if rightShown then record.frr[index], record.frg[index], record.frb[index] = ReadColor(right) end
	end
	local nineSlice = tooltip.NineSlice
	if nineSlice and nineSlice.GetBorderColor then
		local r, g, b, a = nineSlice:GetBorderColor()
		if not ns.IsSecret(r) then record.border = { r, g, b, a } end
		record.borderGrey = ns.Style.IsBorderGrey(nineSlice) -- CT's colours go on grey art (Style.lua)
		r, g, b, a = nineSlice:GetCenterColor()
		if not ns.IsSecret(r) then record.center = { r, g, b, a } end
	end
	NotifySeen()
end

function Sources.Watch(tooltip)
	if watched[tooltip] then return end
	watched[tooltip] = true
	hooksecurefunc(tooltip, "Show", Snapshot)
	records[tooltip] = NewRecord()
	hooksecurefunc(tooltip, "AddLine", OnAddLine)
	hooksecurefunc(tooltip, "AddDoubleLine", OnAddLine)
	hooksecurefunc(tooltip, "SetText", OnSetText)
	hooksecurefunc(tooltip, "ClearLines", Clear)
	tooltip:HookScript("OnTooltipCleared", Clear)
	tooltip:HookScript("OnHide", Clear)
end

local function WatchNamed()
	for _, name in ipairs(ns.TOOLTIPS) do
		local tooltip = _G[name]
		if tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden()) then Sources.Watch(tooltip) end
	end
end

WatchNamed()
ns.Listen("LOGIN", WatchNamed) -- any named tooltip that didn't exist yet
