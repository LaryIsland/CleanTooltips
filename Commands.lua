local _, ns = ...
local L = ns.L

-- /ctt on its own opens the options; the rest toggle the sources column or open a page.
-- /ct is left alone: it's short enough to clash with other addons.

local HELP = { L.HELP_OPTIONS, L.HELP_SOURCES, L.HELP_LAST, L.HELP_HELP }

local commands = {}

function commands.help()
	for _, line in ipairs(HELP) do ns.Print(line) end
	-- The development commands aren't packaged, so they're only listed when they're there (and in English).
	if ns.Dev then
		ns.Print("/ctt lines | capture | perf | watch | probe - development and beta check tools")
	end
end

function commands.sources()
	ns.ToggleSources()
end

function commands.last()
	ns.Options.Open("last")
end

SLASH_CLEANTOOLTIPS1 = "/ctt"
SLASH_CLEANTOOLTIPS2 = "/cleantooltips"
SlashCmdList.CLEANTOOLTIPS = function(text)
	local args = {}
	for word in tostring(text or ""):gmatch("%S+") do args[#args + 1] = word end
	local name = args[1] and args[1]:lower()
	local command = name and (commands[name] or (ns.Dev and ns.Dev[name]))
	if command then
		command(args)
	elseif name then
		commands.help()
	else
		ns.Options.Open()
	end
end
