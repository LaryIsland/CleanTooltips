local _, ns = ...

-- Development commands and the beta check probes (design document 6, Notes/Beta Checks.md). Not packaged, and not
-- translated. Findings are printed and kept in the saved variables (CleanTooltipsDB.global.dev) to read after a reload.
--   /ctt lines     toggle: print and keep every new tooltip's line types and texts (Beta Checks 2)
--   /ctt capture   toggle: keep every distinct Use/Equip/proc line text (Beta Checks 4)
--   /ctt perf      ten seconds of attribution and build times, with and without the pipeline shortcut (Beta Checks 7)
--   /ctt watch     ten seconds of who rebuilds, shows and resizes the tooltips (Beta Checks 13, the NPC jitter)
--   /ctt probe     the gap probe now (Beta Checks 1), and arm the stack probe (Beta Checks 5, 6); /ctt probe off

ns.Dev = {}
local Dev = ns.Dev

local LineType = Enum.TooltipDataLineType
local lineTypeNames, tooltipTypeNames = {}, {}
for name, value in pairs(LineType) do lineTypeNames[value] = name end
for name, value in pairs(Enum.TooltipDataType) do tooltipTypeNames[value] = name end

local MAX_KEPT = 200

local function Store()
	ns.global.dev = ns.global.dev or {}
	local dev = ns.global.dev
	dev.lines = dev.lines or {}
	dev.capture = dev.capture or {}
	dev.probe = dev.probe or {}
	return dev
end

local function Shown(value)
	if value == nil then return "" end
	if ns.IsSecret(value) then return "<secret>" end
	return tostring(value)
end

local function Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

-- /ctt lines and /ctt capture both read every tooltip as it's built.
local recordingLines, capturing = false, false

TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
	if not (recordingLines or capturing) or ns.raw[tooltip] then return end
	local dev = Store()
	local dataType, id = ns.Readable(data.type), ns.Readable(data.id)
	if recordingLines then
		local key = tostring(tooltipTypeNames[dataType] or dataType) .. ":" .. tostring(id)
		if not dev.lines[key] and Count(dev.lines) < MAX_KEPT then
			local kept = {}
			ns.Print("|cff71d5ff" .. key .. "|r")
			for i, line in ipairs(data.lines or {}) do
				local text = ("%d [%s] %s | %s"):format(i, tostring(lineTypeNames[line.type] or line.type),
					Shown(line.leftText), Shown(line.rightText))
				kept[i] = text
				ns.Print(text)
			end
			dev.lines[key] = kept
		end
	end
	if capturing then
		for _, line in ipairs(data.lines or {}) do
			local text = ns.Readable(line.leftText)
			local kind = text and ns.Condense.KindOf(line.type, text)
			if kind and not dev.capture[text] then -- Condense knows every kind, by line type or prefix
				local short = ns.Condense.Shorten(text, kind) or false
				dev.capture[text] = { type = lineTypeNames[line.type], item = id, short = short }
				-- What no rule shortens is printed as it comes, odd bytes (colour codes, non-breaking spaces) shown
				-- as codes, so the rule can be written from it.
				if not short then
					ns.Print(("Not shortened [%s]: %s"):format(tostring(lineTypeNames[line.type] or line.type),
						(text:gsub("|", "||"):gsub("[^\32-\126]", function(c) return ("<%d>"):format(c:byte()) end))))
				end
			end
		end
	end
end)

function Dev.lines()
	recordingLines = not recordingLines
	ns.Print("Line types: " .. (recordingLines and "recording (hover items and units)" or "stopped") .. ". "
		.. Count(Store().lines) .. " tooltips kept.")
end

function Dev.capture()
	capturing = not capturing
	local kept = Store().capture
	local matched = 0
	-- Each kept line is checked again against the current rules, so results from older rules don't linger.
	for text, entry in pairs(kept) do
		local kind = ns.Condense.KindOf(LineType[entry.type], text)
		entry.short = kind and ns.Condense.Shorten(text, kind) or false
		if entry.short then matched = matched + 1 end
	end
	ns.Print("Use/Equip capture: " .. (capturing and "on (browse bags, vendors, the bank)" or "off") .. ". "
		.. Count(kept) .. " distinct lines, " .. matched .. " shortened by the current rules.")
end

-- /ctt perf ------------------------------------------------------------------------------------------------------------

-- Two halves of PERF_SECONDS / 2 on whatever's hovered: with the pipeline and text shortcuts (Sources.lua), then
-- reading every line's stack as before them. Each half reports attribution (lines, stacks read, time) and whole builds: from CT's
-- tooltip pre-call to its post-call, so the lines and every line callback (anyone's), by tooltip type and by tooltip,
-- with what started them. The first half also lists every stack read by what it found (Sources.misses), with samples.

local PERF_SECONDS = 10
local building = setmetatable({}, { __mode = "k" }) -- [tooltip] = when its build started, while perf runs
local builds                                         -- [type name] = { n, ms, worst }, while perf runs
local buildsBy                                       -- [tooltip name] = { n, by = { [caller] = n } }, while perf runs

-- What started a build: the first frame outside CT, the tooltip pipeline and the client, as "folder: function"
-- (GameTooltip_OnUpdate is the game's 0.2 s refresh; an addon's folder means that addon asked).
local function Starter()
	local stack = debugstack(3, 24, 0)
	if stack == nil or ns.IsSecret(stack) then return "secret stack" end
	for frame in stack:gmatch("[^\n]+") do
		local folder = frame:match("[Aa][Dd][Dd][Oo][Nn][Ss][/\\]([^/\\]+)[/\\]")
		if folder and folder ~= "CleanTooltips" and not frame:find("Blizzard_SharedXMLGame[/\\]Tooltip") then
			-- A named function, else the file and line ("GameTooltip.lua:451").
			local fn = frame:match("in function [`']([^'`]+)'")
			if not fn or fn == "?" then
				local file, line = frame:match("([^/\\%[%]]+%.lua)%]?:(%d+)")
				fn = file and (file .. ":" .. line) or "?"
			end
			return folder .. ": " .. fn
		end
	end
	return "the client"
end

TooltipDataProcessor.AddTooltipPreCall(TooltipDataProcessor.AllTypes, function(tooltip)
	if not builds then return end
	local name = tooltip:GetName() or "unnamed"
	local entry = buildsBy[name]
	if not entry then
		entry = { n = 0, by = {} }
		buildsBy[name] = entry
	end
	entry.n = entry.n + 1
	local starter = Starter()
	entry.by[starter] = (entry.by[starter] or 0) + 1
	building[tooltip] = debugprofilestop()
end)

TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
	local started = builds and building[tooltip]
	if not started then return end
	building[tooltip] = nil
	local ms = debugprofilestop() - started
	local dataType = ns.Readable(data and data.type)
	local name = tostring(tooltipTypeNames[dataType] or dataType)
	local entry = builds[name]
	if not entry then
		entry = { n = 0, ms = 0, worst = 0 }
		builds[name] = entry
	end
	entry.n, entry.ms, entry.worst = entry.n + 1, entry.ms + ms, math.max(entry.worst, ms)
end)

-- The keys of a count table, largest first, as "key n, key n".
local function Largest(map, field)
	local keys = {}
	for key in pairs(map) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		local x, y = field and map[a][field] or map[a], field and map[b][field] or map[b]
		if x ~= y then return x > y end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function PerfHalf(label, seconds, breakdown, done)
	local stats = ns.Sources.stats
	for key in pairs(stats) do stats[key] = 0 end
	builds, buildsBy = {}, {}
	ns.Sources.misses = breakdown and {} or nil
	ns.Sources.timing = true
	C_Timer.After(seconds, function()
		ns.Sources.timing = false
		local out = {}
		local perLine = stats.calls > 0 and (stats.ms * 1000 / stats.calls) or 0
		out[1] = ("%s: attribution %d lines, %d stacks read (%d lines by the pipeline shortcut, %d lines and rewrites"
			.. " by their text, %d stacks from cache, %d secret), %.2f ms, %.1f us a line, %.3f ms a second."):format(label,
			stats.calls, stats.stacks, stats.pipeline, stats.byText, stats.hits, stats.secret, stats.ms, perLine,
			stats.ms / seconds)
		for _, name in ipairs(Largest(builds, "n")) do
			local entry = builds[name]
			out[#out + 1] = ("  %s builds: %d (%.1f a second), %.2f ms each, worst %.2f ms"):format(name, entry.n,
				entry.n / seconds, entry.ms / entry.n, entry.worst)
		end
		if breakdown then
			for _, name in ipairs(Largest(buildsBy, "n")) do
				local entry = buildsBy[name]
				local by = {}
				for _, starter in ipairs(Largest(entry.by)) do by[#by + 1] = starter .. " " .. entry.by[starter] end
				out[#out + 1] = ("  %s: %d builds (%.1f a second), started by %s"):format(name, entry.n,
					entry.n / seconds, table.concat(by, ", "))
			end
			local misses = ns.Sources.misses
			for _, missLabel in ipairs(Largest(misses, "n")) do
				local entry = misses[missLabel]
				local tooltips = {}
				for name in pairs(entry.tooltips) do tooltips[#tooltips + 1] = name end
				table.sort(tooltips)
				out[#out + 1] = ("  stacks read for %s: %d (%.1f a second) on %s; e.g. %s"):format(missLabel, entry.n,
					entry.n / seconds, table.concat(tooltips, ", "), #entry.samples > 0
					and ('"' .. table.concat(entry.samples, '", "'):gsub("|", "||") .. '"') or "no readable text")
			end
		end
		builds, buildsBy = nil, nil
		ns.Sources.misses = nil
		for _, line in ipairs(out) do ns.Print(line) end
		done(out)
	end)
end

local perfRunning = false

function Dev.perf()
	-- One at a time: two runs would share the counters, and the first to end would clear the second's.
	if perfRunning then
		ns.Print("Already timing.")
		return
	end
	perfRunning = true
	local half = PERF_SECONDS / 2
	ns.Sources.ForgetTexts() -- so the breakdown names every source at least once
	ns.Print("Timing tooltips for " .. PERF_SECONDS .. " s: hover a weapon in your bags, or an NPC, and keep still.")
	PerfHalf("With the shortcut", half, true, function(first)
		ns.Sources.shortcut = false
		PerfHalf("Reading every stack", half, false, function(second)
			ns.Sources.shortcut = true
			local kept = {}
			for _, line in ipairs(first) do kept[#kept + 1] = line end
			for _, line in ipairs(second) do kept[#kept + 1] = line end
			Store().probe.perf = kept
			perfRunning = false
		end)
	end)
end

-- /ctt watch ------------------------------------------------------------------------------------------------------------
-- For the NPC tooltip jitter (15 Nov): for WATCH_SECONDS, every rebuild (OnTooltipCleared) and Show of the named
-- tooltips, with who called it (CleanTooltips, the game, or another addon, from the call stack), the height after each
-- Show, and whether the shown lines changed. A jitter shows as heights or lines changing between Shows; the "by"
-- counts say whose calls they were. Reads the stack on every call, so only while watching.

local WATCH_SECONDS = 10
local watching -- [tooltip] = its counts, while watching
local watchHooked = false

local function Who()
	local stack = debugstack(3, 20, 0)
	if stack == nil or ns.IsSecret(stack) then return "secret stack" end
	local kept = {}
	for frame in stack:gmatch("[^\n]+") do
		if not frame:find("CleanTooltips[/\\]Dev%.lua") then kept[#kept + 1] = frame end
	end
	local rest = table.concat(kept, "\n")
	if rest:find("CleanTooltips[/\\]") then return "CleanTooltips" end
	local source = ns.Sources.Parse(rest)
	return source == ns.Sources.GAME and "the game" or source
end

local function Signature(tooltip)
	local parts = {}
	for i = 1, tooltip:NumLines() do
		local left = ns.Line(tooltip, i)
		if left and left:IsShown() then
			local text = left:GetText()
			parts[#parts + 1] = ns.IsSecret(text) and "<secret>" or tostring(text)
		end
	end
	return table.concat(parts, "|")
end

local function Tally(map, key) map[key] = (map[key] or 0) + 1 end

local function WatchCounts(tooltip)
	if not watching then return nil end
	local counts = watching[tooltip]
	if not counts then
		counts = { clears = 0, shows = 0, clearsBy = {}, showsBy = {}, heightChanges = 0, lineChanges = 0,
			heightBy = {}, linesBy = {} }
		watching[tooltip] = counts
	end
	return counts
end

local function OnWatchCleared(tooltip)
	local counts = WatchCounts(tooltip)
	if not counts then return end
	counts.clears = counts.clears + 1
	Tally(counts.clearsBy, Who())
end

local function OnWatchShow(tooltip)
	local counts = WatchCounts(tooltip)
	if not counts then return end
	local who = Who()
	counts.shows = counts.shows + 1
	Tally(counts.showsBy, who)
	local height = tooltip:GetHeight()
	if ns.IsSecret(height) then height = nil end
	local signature = Signature(tooltip)
	if counts.height and height and math.abs(height - counts.height) > 0.5 then
		counts.heightChanges = counts.heightChanges + 1
		Tally(counts.heightBy, who)
	end
	if counts.signature and signature ~= counts.signature then
		counts.lineChanges = counts.lineChanges + 1
		Tally(counts.linesBy, who)
	end
	counts.height, counts.signature = height, signature
end

local function ByText(map)
	local parts = {}
	for who, n in pairs(map) do parts[#parts + 1] = who .. " " .. n end
	table.sort(parts)
	return #parts > 0 and table.concat(parts, ", ") or "none"
end

function Dev.watch()
	if watching then
		ns.Print("Already watching.")
		return
	end
	if not watchHooked then
		watchHooked = true
		for _, name in ipairs(ns.TOOLTIPS) do
			local tooltip = _G[name]
			if tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden()) then
				tooltip:HookScript("OnTooltipCleared", OnWatchCleared)
				hooksecurefunc(tooltip, "Show", OnWatchShow)
			end
		end
	end
	watching = {}
	ns.Print("Watching tooltips for " .. WATCH_SECONDS .. " s: hover the NPC that jitters and keep still.")
	C_Timer.After(WATCH_SECONDS, function()
		local out = {}
		for tooltip, counts in pairs(watching) do
			out[#out + 1] = ("%s: %d rebuilds (%.1f a second) by %s; %d Shows by %s"):format(tooltip:GetName() or "?",
				counts.clears, counts.clears / WATCH_SECONDS, ByText(counts.clearsBy), counts.shows,
				ByText(counts.showsBy))
			out[#out + 1] = ("  height changed %d times (by %s); shown lines changed %d times (by %s)"):format(
				counts.heightChanges, ByText(counts.heightBy), counts.lineChanges, ByText(counts.linesBy))
		end
		watching = nil
		if #out == 0 then out[1] = "No tooltip activity." end
		for _, line in ipairs(out) do ns.Print(line) end
		Store().probe.watch = out
	end)
end

-- /ctt probe: the gap probe -----------------------------------------------------------------------------------------
-- How tall a tooltip is with some lines blanked, three ways (design document 4.3). Gap = the height with the blanked
-- lines minus the height without them. Run on a tooltip of CT's own made from GameTooltipTemplate, at screen centre.

local probeTooltip

local BLANKS = {
	hide = function(fontString) fontString:SetText("") fontString:Hide() end,
	textNil = function(fontString) fontString:SetText(nil) end,
	hideOnly = function(fontString) fontString:Hide() end,
}

local function Height(lines, blanked, blank)
	local tooltip = probeTooltip
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	tooltip:SetPoint("CENTER")
	for i = 1, lines do tooltip:AddLine("Clean Tooltips probe line " .. i) end
	for _, index in ipairs(blanked or {}) do
		local left, right = ns.Line(tooltip, index)
		ns.Editing(function()
			blank(left)
			if right then blank(right) end
		end)
	end
	tooltip:Show()
	return tooltip:GetHeight()
end

local function GapProbe(when)
	probeTooltip = probeTooltip or CreateFrame("GameTooltip", "CleanTooltipsProbeTooltip", UIParent,
		"GameTooltipTemplate")
	local results = {}
	local two, three = Height(2), Height(3)
	results[#results + 1] = ("%s: 2 lines %.1f, 3 lines %.1f (a line is %.1f)"):format(when, two, three, three - two)
	for name, blank in pairs(BLANKS) do
		local one = Height(3, { 2 }, blank) - two
		local both = Height(4, { 2, 3 }, blank) - two
		results[#results + 1] = ("  %s: gap with line 2 blanked %.1f, with lines 2 and 3 blanked %.1f"):format(name,
			one, both)
	end
	-- After a blank, does the client show the font string again for the next tooltip's line 2?
	Height(3, { 2 }, BLANKS.hide)
	Height(3)
	local line2 = ns.Line(probeTooltip, 2)
	results[#results + 1] = "  line 2 shown again after ClearLines and AddLine: " .. tostring(line2:IsShown())
	probeTooltip:Hide()
	for _, line in ipairs(results) do ns.Print(line) end
	Store().probe["gap " .. when] = results
end

-- /ctt probe: the stack probe ---------------------------------------------------------------------------------------
-- While armed, CT adds a line to GameTooltip from a TooltipDataProcessor post-call, as other addons do, and prints the
-- raw debugstack the attribution hook sees: whether it's secret (try in combat on a unit), whether this file's frame is
-- in it, and whether Blizzard's pipeline frames show past the forbidden delegate.

local PROBE_TEXT = "Clean Tooltips probe line"
local PRINT_EVERY = 2 -- seconds, as hovered tooltips rebuild five times a second
local armed, lastPrint, wantStack = false, -math.huge, false

local function OnStack(stack)
	if not wantStack then return end
	wantStack = false
	local secret = ns.IsSecret(stack)
	local lines = { ("Stack probe (%s): secret %s"):format(InCombatLockdown() and "in combat" or "out of combat",
		tostring(secret)) }
	if not secret and stack then
		lines[#lines + 1] = "  has Dev.lua: " .. tostring(stack:find("CleanTooltips[/\\]Dev%.lua") ~= nil)
			.. ", has the data pipeline: " .. tostring(stack:find("Blizzard_SharedXMLGame[/\\]Tooltip") ~= nil)
			.. ", attributed to: " .. tostring(ns.Sources.Parse(stack))
		local count = 0
		for frame in stack:gmatch("[^\n]+") do
			count = count + 1
			if count > 10 then break end
			lines[#lines + 1] = "  " .. frame
		end
	end
	for _, line in ipairs(lines) do ns.Print(line) end
	local probe = Store().probe
	probe.stacks = probe.stacks or {}
	if #probe.stacks < 20 then probe.stacks[#probe.stacks + 1] = lines end
end

local function AddProbeLine(tooltip)
	if not armed or tooltip ~= GameTooltip then return end
	local now = GetTime()
	wantStack = now - lastPrint >= PRINT_EVERY
	if wantStack then lastPrint = now end
	tooltip:AddLine(PROBE_TEXT)
	wantStack = false
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddProbeLine)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddProbeLine)

function Dev.probe(args)
	if args[2] and args[2]:lower() == "off" then
		armed = false
		ns.Sources.probe = nil
		ns.Print("Stack probe off.")
		return
	end
	GapProbe("now")
	C_Timer.After(0.2, function() GapProbe("a moment later") end)
	armed = true
	ns.Sources.probe = OnStack
	ns.Print("Stack probe armed: hover items and units, also in combat. /ctt probe off to stop.")
end
