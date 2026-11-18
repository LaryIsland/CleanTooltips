local addonName, ns = ...

-- Which addon added each tooltip line. Nothing in the API says, so the hooks on the tooltip's
-- AddLine, AddDoubleLine and SetText ask the call stack, and the hook on each line's font string notices lines
-- another addon rewrote. Every line's record is kept until the tooltip is cleared.
--
-- A record (ns.Sources.Record(tooltip), or the current tooltip's with ns.Sources.Current()):
--   n            lines recorded
--   source[i]    the addon folder that added line i, ns.Sources.GAME for the game, nil when unknown (a secret stack,
--                or one that can't say: Parse)
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
--   ns.Sources.Seen()                    [folder] = { lines = { text, ... }, types, candidates, candidateCount }
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
Sources.stats = { calls = 0, rewrites = 0, stacks = 0, hits = 0, secret = 0, deep = 0, pipeline = 0, byText = 0,
	ms = 0 }
Sources.timing = false
Sources.shortcut = true -- the pipeline and text shortcuts below; off only to compare costs (/ctt perf)
Sources.probe = nil -- Dev.lua's stack probe: called with every raw stack read (maybe secret) and the frames asked for

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
-- the loaded addon whose name ends with what's left is the folder, if only one does. Answers are kept, and forgotten
-- when another addon loads (it may be the one that matches).
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
			if type(name) == "string" and name:lower():sub(-#lower) == lower and C_AddOns.IsAddOnLoaded(name) then
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

ns.On("ADDON_LOADED", function() wipe(endingWith) end)

-- The addon folder and the path inside it in one frame of a stack. nil when the frame has no addon path; nil, nil, true
-- when it has one but the folder can't be told (a shortened name no single loaded addon ends with).
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
	folder = FolderEndingWith(first)
	if not folder then return nil, nil, true end
	return folder, rest
end

-- The source in a debugstack text. Frames are read from the line's caller outwards:
--   1. CT's own frames and frames with no addon path ([C], tail calls) are skipped. `counted` (optional) is asked
--      about each of CT's own paths, and true counts it as another addon's (the stack probe's, in Dev.lua).
--   2. Blizzard's tooltip data pipeline (Blizzard_SharedXMLGame/Tooltip) means the game added the line. Other Blizzard
--      frames are helpers (GameTooltip_AddColoredLine) that an addon may have called, so the walk goes on.
--   3. A library frame is remembered and the walk goes on, to the addon using it.
--   4. The first other addon is the source; if only a library was seen, it's the source; otherwise the game, unless
--      the stack can't say: a frame whose folder couldn't be told, or a stack cut short, may hide the addon that
--      called. Then nil (unknown), and "cut" for a cut stack, which Caller reads again deeper. The game ends a stack it
--      cut with a line "...".
-- With an addon's name it also gives the call site, the file and line in that addon that called ("Leatrix_Plus.lua:
-- 16692"), which names a line its text can't (Remove.SetWritten).
function Sources.Parse(stack, counted)
	local library, unresolved, cut = nil, false, false
	for frame in stack:gmatch("[^\n]+") do
		if frame == "..." then cut = true end
		local folder, path, unknown = FolderOf(frame)
		if unknown then unresolved = true end
		if folder and (folder ~= addonName or (counted and counted(path))) then
			if folder:find("^Blizzard_") then
				if folder == PIPELINE and path:find("^Tooltip[/\\]") then
					return library or GAME
				end
			elseif IsLibrary(folder, path) then
				library = library or folder
			else
				return folder, nil, path:gsub("\\", "/") .. ":" .. (frame:match("%]?:(%d+):") or "?")
			end
		end
	end
	if library then return library end
	if cut then return nil, "cut" end
	if unresolved then return nil end
	return GAME
end

local STACK_DEPTH = 16 -- frames read for every line that needs its stack (game stacks run 18 to 20 deep)
local DEEP_DEPTH = 64  -- frames read again when those 16 didn't reach whoever called
local stackCache = ns.Cache(1000) -- [stack] = { its source or false when unknown, the call site }

-- The source of the line being added now, and the call site in that addon (Parse). nil when the stack is secret
-- (not seen in game), or can't say who called.
local function Caller()
	local stats = Sources.stats
	stats.stacks = stats.stacks + 1
	-- From Caller's caller; CT's own frames are skipped in Parse, so the exact depth doesn't matter.
	local raw = debugstack(2, STACK_DEPTH, 0)
	if Sources.probe then Sources.probe(raw, STACK_DEPTH) end
	local stack = ns.Readable(raw)
	if stack == nil then
		stats.secret = stats.secret + 1
		return nil
	end
	local cached = stackCache.items[stack]
	if cached then
		stats.hits = stats.hits + 1
		return cached[1] or nil, cached[2]
	end
	local source, why, site = Sources.Parse(stack)
	if why == "cut" then
		-- Rare (the first addon frame is normally near the top). Not kept under the short stack: two addons calling
		-- the same deep Blizzard code would share its first 16 frames and take each other's name. The text shortcut
		-- still saves a repeat of the same line.
		stats.deep = stats.deep + 1
		local deep = ns.Readable(debugstack(2, DEEP_DEPTH, 0))
		if deep then source, why, site = Sources.Parse(deep) end
		return source, site
	end
	stackCache:Set(stack, { source or false, site })
	return source, site
end

-- The text shortcut: a line (or a rewrite) whose text has been attributed before takes the same source without
-- reading the stack, as nearly every stack read otherwise is the same texts again and again: the comparison
-- tooltips' "If you replace this item..." lines (the game's, added outside its data), and addons' fixed lines and
-- rewrites (AllTheThings' icon, Auctionator's "Vendor"). Blank lines are left out: the game and addons both add " ",
-- and a removal rule may name one addon's. Separate tables for added and rewritten lines.
--
-- A text is remembered per tooltip owner (the frame the tooltip is for), as two sources can add the very same text:
-- Shadowed Unit Frames copies Blizzard's unit frame tooltip, "<Right click for Frame Settings>" included, so by text
-- alone, once a Blizzard unit frame has been hovered, SUF's line would go by the game's name. Owners tell them apart
-- (SUF's frames, Blizzard's frames); a bag slot or a comparison tooltip reads the stack once per owner.
--   byText[which].items[text] = { [owner] = source, any = the source when every owner agrees, else false }
-- `any` answers for a line whose stack is secret (in combat): most addon lines are the same text every time.
local TEXT_SHORTCUT_SIZE = 1000
local byText = { added = ns.Cache(TEXT_SHORTCUT_SIZE), rewrite = ns.Cache(TEXT_SHORTCUT_SIZE) }
local NO_OWNER = {} -- the key for a tooltip with no owner

-- owner: the tooltip's owner, or nil for the source every owner agrees on.
local function Known(which, text, owner)
	if text == nil or not text:find("%S") then return nil end
	local byOwner = byText[which].items[text]
	if not byOwner then return nil end
	if owner == nil then return byOwner.any or nil end
	return byOwner[owner]
end

local function OwnerOf(tooltip)
	return tooltip:GetOwner() or NO_OWNER
end

-- Not while /ctt probe wants to see stacks (Dev.lua), or the probe's own line is read only once.
local function ByText(which, text, tooltip)
	if not Sources.shortcut or Sources.probe or text == nil then return nil end
	return Known(which, text, OwnerOf(tooltip))
end

-- Only while the pipeline shortcut is on, so the game's own data lines (which it takes) are never remembered and can't
-- lend their source to an addon's copy of the same text.
local function RememberText(which, text, source, tooltip)
	if not Sources.shortcut or source == nil or text == nil or not text:find("%S") then return end
	local cache = byText[which]
	local byOwner = cache.items[text]
	local owner = OwnerOf(tooltip)
	if not byOwner then
		byOwner = { any = source }
		cache:Set(text, byOwner)
	elseif byOwner[owner] == source then
		return
	elseif byOwner.any ~= source then
		byOwner.any = false
	end
	byOwner[owner] = source
end

-- What each addon's call site has added this session: [folder][site] = the line's shape, or false once it has added
-- lines of two shapes (a shared helper). Line rules apply by call site only to a site that adds just their line
-- (Remove.HiddenBySite), as in combat the text can't say which line it is.
local siteShapes = {}

local function NoteSite(source, site, text)
	if not (source and site and text) or source == GAME or Sources.IsBlank(text) then return end
	local shape = Sources.Shape(text)
	local sites = siteShapes[source]
	if not sites then
		sites = {}
		siteShapes[source] = sites
	end
	local known = sites[site]
	if known == nil then
		sites[site] = shape
	elseif known ~= shape then
		sites[site] = false
	end
end

-- The one line shape `site` of `folder` has added this session; false when it has added several; nil when not seen.
function Sources.SiteOnlyAdds(folder, site)
	local sites = siteShapes[folder]
	if sites == nil then return nil end
	return sites[site]
end

-- For tests and /ctt perf: start the text shortcut empty.
function Sources.ForgetTexts()
	byText.added:Clear()
	byText.rewrite:Clear()
end

-- Where attribution runs ---------------------------------------------------------------------------------------------
-- Only where something uses it: on every tooltip while the sources column is on or one of CT's
-- options pages is shown (the Sources page's lists fill then); otherwise only on tooltips of the types a removal rule
-- applies to (Remove.RuleTypes: a line rule on the types its line was seen on, "every line it adds" on every type).
-- A tooltip not built from data has no type, so only "every type" covers it. /ctt perf and the stack probe force it on
-- while they run. Everywhere else the hooks return at once.
--   Sources.Wanted(typeName), Sources.Gate(), Sources.UpdateGate(), Sources.Force(reason, on),
--   Sources.SetOptionsShown(frame, shown), Sources.TypeName(dataType)

local TYPE_NAMES = {} -- [Enum.TooltipDataType value] = its name ("Item", "Unit"), as rules keep them
for name, value in pairs(Enum.TooltipDataType) do TYPE_NAMES[value] = name end

function Sources.TypeName(dataType)
	dataType = ns.Readable(dataType)
	return dataType ~= nil and TYPE_NAMES[dataType] or nil
end

local gate = { all = false, types = {} }
local forcedBy = {}     -- [reason] = true
local optionsShown = {} -- [options page frame] = true while shown

local function Wanted(typeName)
	return gate.all or (typeName ~= nil and gate.types[typeName] == true)
end
Sources.Wanted = Wanted

function Sources.Gate()
	return gate
end

function Sources.UpdateGate()
	local profile = ns.profile
	local all = next(forcedBy) ~= nil or next(optionsShown) ~= nil or (profile ~= nil and profile.showSources == true)
	local types = {}
	if not all and profile and ns.Remove then all, types = ns.Remove.RuleTypes() end
	-- Tooltips already shown of a type just switched on are rebuilt, so they're attributed (and lines removed) now.
	local widened = all and not gate.all
	if not all and not gate.all then
		for name in pairs(types) do
			if not gate.types[name] then widened = true end
		end
	end
	gate.all, gate.types = all, types
	if widened then ns.RefreshShownTooltips() end
end

function Sources.Force(reason, on)
	forcedBy[reason] = on and true or nil
	Sources.UpdateGate()
end

function Sources.SetOptionsShown(frame, shown)
	optionsShown[frame] = shown and true or nil
	Sources.UpdateGate()
end

ns.Listen("DB_READY", Sources.UpdateGate)
ns.Listen("RULES_CHANGED", Sources.UpdateGate)
ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil or what == "showSources" then Sources.UpdateGate() end
end)

-- Addons seen this session ----------------------------------------------------------------------------------------------

-- A line's shape: its text without colour codes and icons, with every number as "#", so a line whose numbers change
-- ("Vendor 1g 2s", "Bags: 3") is one line for listing and removal rules. "" for a blank line.
local shapes = ns.Cache(500)

function Sources.Shape(text)
	text = ns.Readable(text)
	if type(text) ~= "string" then return nil end
	local shape = shapes.items[text]
	if shape == nil then
		shape = ns.PlainText(text):gsub("%d[%d,%.]*", "#"):gsub("%s+", " ")
		shape = shape:gsub("^ ", ""):gsub(" $", "")
		shapes:Set(text, shape)
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
	-- Any of them secret: unknown (a missing guid or id is fine, a secret one isn't).
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

-- Each listed line also keeps the tooltip types it has been seen on (types[shape] = { Item = true, ... }), so a rule
-- hiding it runs attribution only on those (Remove.SetLine).
local function Seen(folder, text, subject, typeName)
	local entry = seen[folder]
	if not entry then
		entry = { lines = {}, candidates = {}, candidateCount = 0, types = {} }
		seen[folder] = entry
		ns.Fire("SOURCE_SEEN", folder)
	end
	if text == nil or subject == nil or IsBlank(text) then return end
	local shape = Sources.Shape(text)
	if shape == "" then return end
	local types = entry.types[shape]
	if types then -- listed already
		if typeName then types[typeName] = true end
		return
	end
	if #entry.lines >= MAX_LISTED then return end
	local subjects = entry.candidates[shape]
	if not subjects then
		-- Full of lines that never came round again (quest objectives): start counting afresh.
		if entry.candidateCount >= MAX_CANDIDATES then entry.candidates, entry.candidateCount = {}, 0 end
		subjects = { n = 0, types = {} }
		entry.candidates[shape] = subjects
		entry.candidateCount = entry.candidateCount + 1
	end
	if typeName then subjects.types[typeName] = true end
	if subjects[subject] then return end
	subjects[subject] = true
	subjects.n = subjects.n + 1
	if subjects.n >= PERMANENT then
		entry.types[shape] = subjects.types
		entry.lines[#entry.lines + 1] = text
		entry.candidates[shape] = nil
		entry.candidateCount = entry.candidateCount - 1
		ns.Fire("SOURCE_SEEN", folder)
	end
end

function Sources.Seen()
	return seen
end

-- The tooltip types a listed line of an addon has been seen on, or nil.
function Sources.LineTypes(folder, text)
	local entry = seen[folder]
	local shape = Sources.Shape(text)
	return entry and shape and entry.types[shape] or nil
end

-- A rule can name an addon the player has since uninstalled, and the game errors on an unknown name ("Invalid AddOn
-- name"), so those keep their folder name and no icon, and stay listed for the player to untick.
local function Installed(folder)
	return C_AddOns.DoesAddOnExist == nil or C_AddOns.DoesAddOnExist(folder)
end

local titles = {}
function Sources.Title(folder)
	if folder == GAME then return nil end
	local title = titles[folder]
	if not title then
		title = Installed(folder) and ns.PlainText(C_AddOns.GetAddOnTitle(folder)) or folder
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
		icon = Installed(folder) and C_AddOns.GetAddOnMetadata(folder, "IconTexture")
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
	"finalWrap",      -- [i] = whether line i wrapped (its left font string's word wrap), for the Sources page's copy
	"lastHidden",     -- [folder] = whether that addon's last non-blank line here was hidden
	"pendingBlanks", -- [folder] = its blank lines waiting on its next line
	"site",          -- [i] = the call site that added line i, when its stack was read (Parse)
	"written" }      -- [i] = the text its own addon wrote into line i after adding it blank (when readable)

local function ResetRecord(record)
	record.n, record.addons = 0, false
	record.fromData = false -- built by the game's data pipeline (an item, unit, spell...), not with SetText
	record.subject = nil    -- what it's about (SubjectOf), false when unreadable
	record.typeName = nil   -- its data's type ("Item", "Unit"), when built from data
	record.attribute = gate.all -- whether its lines are attributed (Wanted; set again by type when built from data)
	record.border, record.center, record.borderGrey = nil, nil, nil
	record.minWidth = nil -- the tooltip's minimum width when last shown
	for _, key in ipairs(RECORD_TABLES) do
		local t = record[key]
		if t then wipe(t) else record[key] = {} end
	end
	return record
end

-- Records are reused, never thrown away: a tooltip rebuilds up to 20 times a second, and a fresh record is 22 tables
-- (about 120 KB of garbage a second on a weapon with comparisons).
-- A record replaced while it's the current tooltip's (Clear) is kept until another becomes current, then it's spare.
local spare = {}    -- records no tooltip or Sources page uses, ready to reuse
local MAX_SPARE = 4

local function NewRecord()
	local record = table.remove(spare)
	return ResetRecord(record or {})
end

-- A record becomes the current tooltip's; the one before goes spare if its tooltip has moved on to a new record.
local function SetCurrent(record)
	if current == record then return end
	if current and current.replaced and #spare < MAX_SPARE then
		current.replaced = nil
		spare[#spare + 1] = current
	end
	current = record
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
		record.replaced = true
		records[tooltip] = NewRecord()
	else
		ResetRecord(record)
	end
end

local function ReadText(fontString)
	if not fontString then return nil end
	return ns.Readable(fontString:GetText())
end

local function ReadColor(fontString)
	if not fontString then return 1, 1, 1 end
	local r, g, b = fontString:GetTextColor()
	r, g, b = ns.Readable(r), ns.Readable(g), ns.Readable(b)
	if not (r and g and b) then return 1, 1, 1 end
	return r, g, b
end

local OnLineSetText -- below
local LineSetTextHook = ns.Guarded("line text", function(...) return OnLineSetText(...) end)

local function WatchLine(tooltip, index, fontString)
	if not fontString then return end
	local entry = fontLines[fontString]
	if not entry then
		fontLines[fontString] = { tooltip, index }
		hooksecurefunc(fontString, "SetText", LineSetTextHook)
	end
end

-- The game's own lines without reading the stack. Most lines are the data pipeline's, and debugstack costs about
-- 30 us a line in game, so a line pre-call notes the text the pipeline is about to add, and the AddLine that follows
-- with exactly that text is the game's. Anything else (another addon's line added from its own pre-call or post-call,
-- a secret or empty text) still reads the stack. The note is dropped once used, by the line's post-call, and
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
	record.typeName = Sources.TypeName(data.type)
	record.attribute = Wanted(record.typeName)
	record.subject = record.attribute and SubjectOf(data) or false
end)

TooltipDataProcessor.AddLinePreCall(TooltipDataProcessor.AllTypes, function(tooltip, lineData)
	if ns.raw[tooltip] or not watched[tooltip] then return end
	local record = records[tooltip]
	if not (record and record.attribute) then return end
	local text = ns.Readable(lineData.leftText)
	if type(text) ~= "string" or text == "" then
		text = ns.Readable(lineData.rightText)
		if type(text) ~= "string" or text == "" then text = nil end
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
	if source == nil then return "unknown (secret stack, or one that can't say)" end
	if source ~= GAME then return source end
	if expected == nil then return "the game, a line not from its data (added by a Blizzard post-call or helper)" end
	return "the game, text not as in its data"
end

-- While /ctt perf times attribution (Sources.timing): the time spent, in all and by tooltip ([name] = ms).
Sources.msBy = {}
local function Timed(tooltip, ms)
	Sources.stats.ms = Sources.stats.ms + ms
	local name = tooltip:GetName() or "unnamed"
	Sources.msBy[name] = (Sources.msBy[name] or 0) + ms
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
		SetCurrent(record)
		NotifySeen()
	end

	local leftText, rightText = ReadText(left), ReadText(right)
	local key = leftText or rightText
	local expected = pending[tooltip]
	local source, site
	if expected ~= nil and Sources.shortcut and (expected == leftText or (leftText == nil and expected == rightText)) then
		pending[tooltip] = nil
		stats.pipeline = stats.pipeline + 1
		source = GAME
	else
		source = ByText("added", key, tooltip)
		if source then
			stats.byText = stats.byText + 1
		else
			source, site = Caller()
			RememberText("added", key, source, tooltip)
			NoteSite(source, site, key)
			if Sources.misses then
				local shown = key
				if source == GAME and expected ~= nil then
					shown = tostring(shown) .. " (data: " .. tostring(expected) .. ")"
				end
				Missed(MissLabel(source, expected), shown, tooltip)
			end
		end
	end
	-- Unknown (a secret stack, or one that can't say): the line goes by its text if a readable stack named it before
	-- (never a blank line).
	if source == nil then source = Known("added", key) end

	record.n = index
	record.source[index] = source
	record.site[index] = site
	record.left[index], record.right[index] = leftText, rightText
	record.lr[index], record.lg[index], record.lb[index] = ReadColor(left)
	if right and right:IsShown() then
		record.rr[index], record.rg[index], record.rb[index] = ReadColor(right)
	end
	if source and source ~= GAME then
		record.addons = true
		Seen(source, key, record.subject or nil, record.typeName)
		if ns.Remove then
			-- A blank line goes with the addon's lines beside it: hidden if its line before was, or (when it comes
			-- first) once its next line turns out hidden. So a spacer never stays behind a removed line.
			local blank = IsBlank(key)
			local hide, rule = ns.Remove.ShouldHide(source, key, record.typeName, site)
			-- A line rule that hasn't learned where its line is added (the line went by the text shortcut, without
			-- its stack) reads the stack once now, so the rule holds in combat when the text is secret.
			if type(rule) == "table" and not site and not (rule.sites and next(rule.sites)) then
				local _, learned = Caller()
				if learned then
					rule.sites = rule.sites or {}
					rule.sites[learned] = true
					NoteSite(source, learned, key)
				end
			end
			-- A blank line its addon writes into afterwards (Leatrix Plus's target) goes by where it's added.
			if blank and not hide and site and ns.Remove.IsWrittenHidden(source, site) then hide = true end
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

	if started then Timed(tooltip, debugprofilestop() - started) end
end

local function OnAddLine(tooltip)
	if ns.editing then return end
	local record = records[tooltip]
	if record and not record.attribute then return end
	local index = ns.Readable(tooltip:NumLines())
	if type(index) == "number" and index > 0 then Added(tooltip, index) end
end

-- SetText starts the tooltip again with one line.
local function OnSetText(tooltip)
	if ns.editing then return end
	Clear(tooltip)
	OnAddLine(tooltip)
end

-- Another addon rewrote a line's text: shown in the sources column, never removed.
function OnLineSetText(fontString)
	if ns.editing then return end
	local entry = fontLines[fontString]
	local tooltip, index = entry[1], entry[2]
	local record = records[tooltip]
	if not record or index > record.n then return end
	local started = Sources.timing and debugprofilestop()
	Sources.stats.rewrites = Sources.stats.rewrites + 1
	local text = ReadText(fontString)
	local source = ByText("rewrite", text, tooltip)
	if source then
		Sources.stats.byText = Sources.stats.byText + 1
	else
		source = Caller()
		RememberText("rewrite", text, source, tooltip)
		if Sources.misses then
			Missed("rewrites by " .. (source == GAME and "the game" or tostring(source or "unknown")),
				text, tooltip)
		end
	end
	if source and source ~= GAME and source ~= record.source[index] then
		record.edited[index] = source
		record.addons = true
	elseif source and source ~= GAME and IsBlank(record.left[index]) then
		-- Its own addon writing into a blank line it added (Leatrix Plus's "Target: <name>", secret in combat): the line
		-- is what it writes. A rule for it hides it when added (by call site); its text up to ": " catches it too, out
		-- of combat, and moves the rule to a new call site after the addon changes.
		record.written[index] = text
		if text and not record.hidden[index] and ns.Remove.MatchWritten(source, text, record.site[index]) then
			ns.Remove.Hide(tooltip, record, index)
		end
	end
	if started then Timed(tooltip, debugprofilestop() - started) end
end

local function Fill(t, r, g, b, a)
	t = t or {}
	t[1], t[2], t[3], t[4] = r, g, b, a
	return t
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
		record.finalWrap[index] = leftShown and left.CanWordWrap ~= nil and ns.Readable(left:CanWordWrap()) == true
		record.finalRight[index] = rightShown and ReadText(right) or nil
		record.flr[index], record.flg[index], record.flb[index] = ReadColor(left)
		if rightShown then record.frr[index], record.frg[index], record.frb[index] = ReadColor(right) end
	end
	record.minWidth = tooltip.GetMinimumWidth and ns.Readable(tooltip:GetMinimumWidth()) or nil
	local nineSlice = tooltip.NineSlice
	if nineSlice and nineSlice.GetBorderColor then
		-- Into the record's own colour tables, made once, as the current tooltip is shown many times a second.
		local r, g, b, a = nineSlice:GetBorderColor()
		if ns.Readable(r) then
			record.borderKept = Fill(record.borderKept, r, g, b, a)
			record.border = record.borderKept
		end
		record.borderGrey = ns.Style.IsBorderGrey(nineSlice) -- CT's colours go on grey art (Style.lua)
		r, g, b, a = nineSlice:GetCenterColor()
		if ns.Readable(r) then
			record.centerKept = Fill(record.centerKept, r, g, b, a)
			record.center = record.centerKept
		end
	end
	NotifySeen()
end

local SnapshotHook = ns.Guarded("snapshot", Snapshot)
local AddLineHook = ns.Guarded("line added", OnAddLine)
local SetTextHook = ns.Guarded("tooltip text", OnSetText)
local ClearHook = ns.Guarded("tooltip cleared", Clear)

function Sources.Watch(tooltip)
	if watched[tooltip] then return end
	watched[tooltip] = true
	hooksecurefunc(tooltip, "Show", SnapshotHook)
	records[tooltip] = NewRecord()
	hooksecurefunc(tooltip, "AddLine", AddLineHook)
	hooksecurefunc(tooltip, "AddDoubleLine", AddLineHook)
	hooksecurefunc(tooltip, "SetText", SetTextHook)
	hooksecurefunc(tooltip, "ClearLines", ClearHook)
	tooltip:HookScript("OnTooltipCleared", ClearHook)
	tooltip:HookScript("OnHide", ClearHook)
end

local function WatchNamed()
	for _, name in ipairs(ns.TOOLTIPS) do
		local tooltip = _G[name]
		if tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden()) then Sources.Watch(tooltip) end
	end
end

WatchNamed()
ns.Listen("LOGIN", WatchNamed) -- any named tooltip that didn't exist yet
