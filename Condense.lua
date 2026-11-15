local _, ns = ...
local L = ns.L

-- Shortened item lines (design document 3.4): "Use:", "Equip:", "Chance on hit:" and set bonus ("Set:", "(3) Set:")
-- lines, and the weapon's "(6.7 damage per second)". Each rule is a Lua pattern on what follows the game's prefix and
-- a locale line for the short form, which goes after that prefix as the game wrote it. The captures are put into it
-- in order (or in the rule's `order`), copied as the game wrote them except that a trailing ".0" goes (2.0% reads
-- 2%). First match wins, and a line no rule matches stays as the game wrote it.
--
-- Before matching, colour codes go, any run of spaces (non-breaking ones and line breaks too) counts as one, and the
-- final full stop is optional. A cooldown at the end is set aside and put back. A line no rule matches whole is tried
-- again by its first sentence, and the rest follows as the game wrote it ("Chance on hit: 42 damage. Naga are Stunned
-- for 2 sec").
--
-- Wording is Forever's, from launch (8 and 15 Nov, /ctt lines and /ctt capture, and the 1.60.1 Spell table on
-- wago.tools): two spaces between sentences, percentages on gear with one decimal ("by 2.0%"), and Equip lines typed
-- None. Rules not yet seen in game are marked in the design document. Only the English client has rules.
--   ns.Condense.KindOf(lineType, text)   "use", "equip", "proc", "set", "dps" or nil
--   ns.Condense.Shorten(text, kind)      the short form, or nil
--   ns.Condense.OPTION[kind]             the profile option that switches it

ns.Condense = {}
local Condense = ns.Condense

local LineType = Enum.TooltipDataLineType
local KIND = {
	[LineType.ItemSpellTriggerOnUse] = "use",
	[LineType.ItemSpellTriggerOnEquip] = "equip",
	[LineType.ItemSpellTriggerOnProc] = "proc",
}
-- Procs and set bonuses are on gear, so they follow the Equip option. Two more options shape the short forms:
-- dropEquipPrefix (an Equip line reads "+3 Stamina", like the game's white stat lines) and hideSecondCooldown.
Condense.OPTION = { use = "shortenUse", equip = "shortenEquip", proc = "shortenEquip", set = "shortenEquip",
	dps = "shortenDps" }

-- A Lua pattern matching `text` exactly.
local function Literal(text)
	return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- The game's own prefixes, so a shortened line still says what it is. Set bonuses may have a count in front.
local PREFIX = { use = ITEM_SPELL_TRIGGER_ONUSE, equip = ITEM_SPELL_TRIGGER_ONEQUIP, proc = ITEM_SPELL_TRIGGER_ONPROC }
local SET = ITEM_SET_BONUS and (ITEM_SET_BONUS:gsub("%s*%%s$", ""))  -- "Set:"
local SET_PATTERNS = SET and { "^(%(%d+%) " .. Literal(SET) .. ")", "^(" .. Literal(SET) .. ")" } or {}

local N = "([%d,%.]+)" -- a number as the game wrote it (1,234 or 1.5)
local END = "%.?$"     -- the final full stop, if there is one

-- "(6.7 damage per second)", from the game's own string.
local DPS = DPS_TEMPLATE and ("^" .. Literal(DPS_TEMPLATE):gsub("%%%%s", function() return N end) .. "$")

local function SetPrefix(text)
	for _, pattern in ipairs(SET_PATTERNS) do
		local prefix = text:match(pattern)
		if prefix then return prefix end
	end
end

-- The first characters a line of any kind can start with ("U", "E", "C", "S", and "(" for "(3) Set:" and dps), so
-- most lines are turned away by one byte (KindOf runs on every line of every tooltip).
local FIRST = { [("("):byte()] = true }
for _, prefix in pairs(PREFIX) do
	if prefix and prefix ~= "" then FIRST[prefix:byte(1)] = true end
end
if SET and SET ~= "" then FIRST[SET:byte(1)] = true end

function Condense.KindOf(lineType, text)
	local kind = not ns.IsSecret(lineType) and KIND[lineType]
	if kind then return kind end
	if type(text) ~= "string" or ns.IsSecret(text) or not FIRST[text:byte(1) or 0] then return nil end
	for name, prefix in pairs(PREFIX) do
		if prefix and text:sub(1, #prefix) == prefix then return name end
	end
	if SetPrefix(text) then return "set" end
	if DPS and text:find(DPS) then return "dps" end
	return nil
end

local EQUIP = {
	-- Attack power: Forever already writes it short ("+12 Attack Power."); only the full stop goes.
	{ "^%+?Increases attack power by " .. N .. END, "SHORT_ATTACK_POWER" },
	{ "^%+" .. N .. " Attack Power" .. END, "SHORT_ATTACK_POWER" },
	{ "^%+" .. N .. " [Rr]anged Attack Power" .. END, "SHORT_RANGED_ATTACK_POWER" },
	{ "^%+" .. N .. " Attack Power against (.-)" .. END, "SHORT_ATTACK_POWER_AGAINST" },
	{ "^%+" .. N .. " Attack Power in Cat, Bear, and Dire Bear forms only" .. END, "SHORT_FERAL_ATTACK_POWER" },
	-- Spell power and healing
	{ "^Increases damage and healing done by magical spells and effects by up to " .. N .. END, "SHORT_SPELL_POWER" },
	{ "^Increases healing done by up to " .. N .. " and damage done by up to " .. N
		.. " for all magical spells and effects" .. END, "SHORT_HEALING_DAMAGE" }, -- Forever
	{ "^Increases healing done by spells and effects by up to " .. N .. " and damage done by up to " .. N .. END,
		"SHORT_HEALING_DAMAGE" },
	{ "^Increases healing done by spells and effects by up to " .. N .. END, "SHORT_HEALING" },
	{ "^Increases healing done by magical spells and effects by up to " .. N .. END, "SHORT_HEALING" }, -- Forever
	{ "^Increases damage done by spells and effects by up to " .. N .. END, "SHORT_SPELL_DAMAGE" },
	{ "^Increases damage done by magical spells and effects by up to " .. N .. END, "SHORT_SPELL_DAMAGE" }, -- Forever
	{ "^Increases damage done by (%a+) spells and effects by up to " .. N .. END, "SHORT_SCHOOL_DAMAGE",
		order = { 2, 1 } },
	{ "^Increases damage done to (%a+) by magical spells and effects by up to " .. N .. END,
		"SHORT_SPELL_DAMAGE_AGAINST", order = { 2, 1 } },
	-- Hit and crit
	{ "^Improves your chance to hit by " .. N .. "%%" .. END, "SHORT_HIT" },
	{ "^Improves your chance to hit with spells by " .. N .. "%%" .. END, "SHORT_SPELL_HIT" },
	{ "^Improves your chance to hit with all spells by " .. N .. "%%" .. END, "SHORT_SPELL_HIT" },
	{ "^Improves your chance to hit with (%a+) spells by " .. N .. "%%" .. END, "SHORT_SCHOOL_HIT", order = { 2, 1 } },
	{ "^Improves your chance to hit with ranged weapons by " .. N .. "%%" .. END, "SHORT_RANGED_HIT" },
	{ "^Improves your chance to get a critical strike by " .. N .. "%%" .. END, "SHORT_CRIT" },
	{ "^Improves your chance to get a critical strike with melee attacks by " .. N .. "%%" .. END, "SHORT_MELEE_CRIT" },
	{ "^Improves your chance to get a critical strike with ranged weapons by " .. N .. "%%" .. END,
		"SHORT_RANGED_CRIT" },
	{ "^Improves your chance to get a critical strike with spells by " .. N .. "%%" .. END, "SHORT_SPELL_CRIT" },
	{ "^Improves your chance to get a critical strike with all spells and attacks by " .. N .. "%%" .. END,
		"SHORT_CRIT" },
	{ "^Increases your critical strike chance with spells and attacks by " .. N .. "%%" .. END, "SHORT_CRIT" },
	{ "^Increases your critical strike chance with all attacks by " .. N .. "%%" .. END, "SHORT_CRIT" },
	{ "^Increases your critical strike chance with ranged weapons by " .. N .. "%%" .. END, "SHORT_RANGED_CRIT" },
	{ "^Increases the critical strike damage bonus of your abilities by " .. N .. "%%" .. END, "SHORT_CRIT_DAMAGE" },
	{ "^Increases critical strike damage bonus of all spells by " .. N .. "%%" .. END, "SHORT_SPELL_CRIT_DAMAGE" },
	-- Regeneration
	{ "^Restores " .. N .. " [Mm]ana per 5 sec" .. END, "SHORT_MP5" }, -- Forever writes both
	{ "^Restores " .. N .. " [Hh]ealth per 5 sec" .. END, "SHORT_HP5" },
	-- Defence
	{ "^Increased Defense %+" .. N .. END, "SHORT_DEFENSE" },
	{ "^Increases your chance to dodge an attack by " .. N .. "%%" .. END, "SHORT_DODGE" },
	{ "^Increases your chance to [Pp]arry an attack by " .. N .. "%%" .. END, "SHORT_PARRY" },
	{ "^Increases your [Pp]arry chance by " .. N .. "%%" .. END, "SHORT_PARRY" },
	{ "^Decreases your chance to [Pp]arry an attack by " .. N .. "%%" .. END, "SHORT_PARRY_DOWN" },
	{ "^Increases your chance to [Bb]lock attacks with a shield by " .. N .. "%%" .. END, "SHORT_BLOCK" }, -- Forever: both
	{ "^Increases your chance to [Bb]lock attacks with a shield by " .. N .. "%% and increases the amount blocked by "
		.. N .. "%%" .. END, "SHORT_BLOCK_AND_AMOUNT" },
	{ "^Increases the [Bb]lock [Vv]alue of your shield by " .. N .. END, "SHORT_BLOCK_VALUE" }, -- Forever writes both
	-- Threat
	{ "^Increases all threat generated by " .. N .. "%%" .. END, "SHORT_THREAT" },
	{ "^Decreases all threat generated by " .. N .. "%%" .. END, "SHORT_THREAT_DOWN" },
	-- Speed: quivers and ammo pouches, and melee
	{ "^Increases ranged attack speed by " .. N .. "%%" .. END, "SHORT_RANGED_ATTACK_SPEED" },
	{ "^Increases attack speed by " .. N .. "%%" .. END, "SHORT_ATTACK_SPEED" },
	{ "^Increases your attack speed by " .. N .. "%%" .. END, "SHORT_ATTACK_SPEED" },
	-- Armour
	{ "^Increases your armor by " .. N .. " while using a Shield or Buckler" .. END, "SHORT_SHIELD_ARMOR" },
	{ "^Increases your armor by " .. N .. END, "SHORT_ARMOR" },
	{ "^Increases armor by " .. N .. END, "SHORT_ARMOR" },
	-- Resistances (one school, or all), and getting past the target's
	{ "^%+" .. N .. " All Resistances" .. END, "SHORT_ALL_RESIST" },
	{ "^%+" .. N .. " (%a+) Resistance" .. END, "SHORT_RESIST" },
	{ "^Increases (%a+) resistance by " .. N .. END, "SHORT_RESIST", order = { 2, 1 } },
	{ "^Decreases the magical resistances of your spell targets by " .. N .. END, "SHORT_SPELL_PENETRATION" },
	{ "^Your spells pierce " .. N .. " Magical Resistances?" .. END, "SHORT_SPELL_PENETRATION" }, -- Forever
	-- Stealth
	{ "^Increases your stealth detection by " .. N .. END, "SHORT_STEALTH_DETECTION" },
	{ "^Increases your stealth by " .. N .. END, "SHORT_STEALTH" },
	{ "^Increases your effective stealth level by " .. N .. END, "SHORT_STEALTH" },
	-- Skills: weapons ("Increased Swords +3."), Fishing, and anything else written that way
	{ "^Increased (.-) %+" .. N .. END, "SHORT_SKILL", order = { 2, 1 } },
	-- A stat written name first ("Stamina +3."), turned round to read like the game's white stat lines ("+3 Stamina")
	{ "^(%a[%a ]-) %+" .. N .. END, "SHORT_STAT", order = { 2, 1 } },
	-- Last: any line Forever already writes short ("+5 Agility.") loses its full stop
	{ "^%+" .. N .. " (.-)" .. END, "SHORT_STAT" },
}

local RULES = {
	enUS = {
		use = {
			-- Well Fed food (captured 15 Nov; the stat can be several words: "Attack Power", "Stamina and Spirit").
			{ "^Restores " .. N .. " health over " .. N .. " sec%. Must remain seated while eating%. If you spend at least "
				.. "%d+ sec%a* eating,? you will become well fed and gain " .. N .. " (.-) for %d+ %a+%. Additionally, "
				.. "experience gained from kills is increased by " .. N .. "%%" .. END, "SHORT_FOOD_WELL_FED_XP" },
			{ "^Restores " .. N .. " health over " .. N .. " sec%. Must remain seated while eating%. If you spend at least "
				.. "%d+ sec%a* eating,? you will become well fed and gain " .. N .. " (.-) for %d+ %a+" .. END,
				"SHORT_FOOD_WELL_FED" },
			{ "^Restores " .. N .. " health over " .. N .. " sec%. Must remain seated while eating%. Also increases your "
				.. "(.-) by " .. N .. " for %d+ %a+" .. END, "SHORT_FOOD_WELL_FED", order = { 1, 2, 4, 3 } },
			{ "^Restores " .. N .. " health and " .. N .. " mana over " .. N
				.. " sec%. Must remain seated while eating" .. END, "SHORT_FOOD_DRINK" },
			{ "^Restores " .. N .. " health over " .. N .. " sec%. Must remain seated while eating" .. END, "SHORT_FOOD" },
			{ "^Restores " .. N .. " mana over " .. N .. " sec%. Must remain seated while drinking" .. END, "SHORT_DRINK" },
			{ "^Restores " .. N .. " to " .. N .. " health" .. END, "SHORT_POTION" },
			{ "^Restores " .. N .. " to " .. N .. " mana" .. END, "SHORT_MANA_POTION" },
			{ "^Heals " .. N .. " damage over " .. N .. " sec" .. END, "SHORT_BANDAGE" },
			{ "^Heals the target for " .. N .. " damage over " .. N .. " sec" .. END, "SHORT_BANDAGE" }, -- captured
			{ "^Heal your target for " .. N .. " to " .. N .. END, "SHORT_HEAL_TARGET" }, -- captured 15 Nov
			{ "^Returns you to (.-)%. Speak to an Innkeeper in a different place to change your home location" .. END,
				"SHORT_HEARTHSTONE", dropCooldown = true },
			-- Elixirs, buff potions and trinkets; run speed first
			{ "^Increases run speed by " .. N .. "%% for " .. N .. " sec" .. END, "SHORT_RUN_SPEED" },
			{ "^Increases damage and healing done by magical spells and effects by up to " .. N .. " for (.-)" .. END,
				"SHORT_SPELL_POWER_FOR" }, -- captured 15 Nov
			{ "^Increases your (%a+) by " .. N .. "%. Effect lasts for (.-)" .. END, "SHORT_BUFF", order = { 2, 1, 3 } },
			{ "^Increases (%a+) by " .. N .. " for (.-)" .. END, "SHORT_BUFF", order = { 2, 1, 3 } },
			{ "^Increases your (%a+) by " .. N .. END, "SHORT_STAT", order = { 2, 1 } },
			{ "^Increase (%a+) by " .. N .. END, "SHORT_STAT", order = { 2, 1 } }, -- "Increase Rage by 30." (captured)
			{ "^Increases (%a+) by " .. N .. END, "SHORT_STAT", order = { 2, 1 } }, -- "Increases Stamina by 3." (captured)
			{ "^Increases your attack speed by " .. N .. "%% for (.-)" .. END, "SHORT_ATTACK_SPEED_FOR" }, -- captured
			-- Fishing lures (captured: "for 10 min." and "for 10 minutes.")
			{ "^When applied to your fishing pole, increases Fishing by " .. N .. " for (.-)" .. END, "SHORT_LURE" },
			-- Recipes and patterns: what they teach (a second sentence follows as written)
			{ "^Teaches you how to cook an? (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to cook (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to make an? (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to make (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to sew an? (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to sew (.-)" .. END, "SHORT_RECIPE" },
			-- Cure kits (a second sentence, "Not usable in combat.", follows as written)
			{ "^Target is cured of (%a+) up to level " .. N .. END, "SHORT_CURE" },
			-- Enchant items (armour kits): the stat, its value, the armour, the slots, and the item level if there is one
			{ "^Permanently increase the (.-) value by " .. N .. " and [%a ]-[Aa]rmor value by " .. N
				.. " of an item worn on the (.-)%. Only usable on items level " .. N .. " and above" .. END,
				"SHORT_ENCHANT_LEVEL", order = { 4, 2, 1, 3, 5 } },
			{ "^Permanently increase the (.-) value by " .. N .. " and [%a ]-[Aa]rmor value by " .. N
				.. " of an item worn on the (.-)" .. END, "SHORT_ENCHANT", order = { 4, 2, 1, 3 } },
			-- Rogue poisons (the game writes a line break before "Each strike"; it counts as a space here)
			{ "^Coats a weapon with poison that lasts for " .. N .. " %a+%. Each strike has a " .. N .. "%% chance of "
				.. "poisoning the enemy which instantly inflicts " .. N .. " to " .. N .. " (%a+) damage%. " .. N
				.. " charges" .. END, "SHORT_POISON_DAMAGE", order = { 1, 6, 2, 3, 4, 5 } },
			{ "^Coats a weapon with poison that lasts for " .. N .. " %a+%. Each strike has a " .. N .. "%% chance of "
				.. "poisoning the enemy, slowing their movement speed by " .. N .. "%% for " .. N .. " sec" .. END,
				"SHORT_POISON_SLOW" },
			{ "^Coats a weapon with poison that lasts for " .. N .. " %a+%. Each strike has a " .. N .. "%% chance of "
				.. "poisoning the enemy, increasing their casting time by " .. N .. "%% for " .. N .. " sec%. " .. N
				.. " charges" .. END, "SHORT_POISON_CAST", order = { 1, 5, 2, 3, 4 } },
		},
		equip = EQUIP,
		set = EQUIP,
		-- "Chance on hit:" (the common item procs in Forever's spell data; a second sentence follows as written)
		proc = {
			{ "^Blasts .- for " .. N .. " (%a+) damage" .. END, "SHORT_PROC_DAMAGE" },
			{ "^Casts a bolt of lightning at the target for " .. N .. " (%a+) damage" .. END, "SHORT_PROC_DAMAGE" },
			{ "^Sends a shadowy bolt at the enemy,? causing " .. N .. " (%a+) damage" .. END, "SHORT_PROC_DAMAGE" },
			{ "^Hurls a fiery ball that causes " .. N .. " (%a+) damage and an additional " .. N .. " [%a ]-damage over "
				.. N .. " sec" .. END, "SHORT_PROC_DOT" },
			{ "^Wounds the target causing them to bleed for " .. N .. " damage over " .. N .. " sec" .. END,
				"SHORT_PROC_BLEED" },
			{ "^Wounds the target for " .. N .. " damage" .. END, "SHORT_PROC_PLAIN" }, -- captured 15 Nov
			{ "^Steals " .. N .. " life from target enemy" .. END, "SHORT_PROC_DRAIN" },
		},
	},
}
RULES.enGB = RULES.enUS

local rules = RULES[GetLocale()] or {}

-- "2.0" reads "2"; "1.5" and "1,338" stay as they are. A full stop the number took from the end of the sentence
-- ("by up to 5.", as the final full stop is optional) goes too.
local function Tidy(value)
	return value and (value:gsub("%.$", ""):gsub("%.0+$", ""))
end

-- The text as the rules see it: no colour codes, one plain space wherever the game put any run of spaces.
local function Plain(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("\194\160", " "):gsub("%s+", " ")
	return (text:gsub("^ ", ""):gsub(" $", ""))
end

-- What follows the line's prefix, and the prefix as the game wrote it.
local function Body(text, kind)
	local prefix = kind == "set" and SetPrefix(text) or PREFIX[kind]
	if prefix and text:sub(1, #prefix) == prefix then
		return (text:sub(#prefix + 1):gsub("^ ", "")), prefix
	end
	return nil
end

-- A cooldown the game puts at the end ("(1 |4Hr:Hr; Cooldown)") is kept as written, after the short form, and the
-- rules match what's before it. |4 is the game's plural code, so it's never rewritten. A rule with dropCooldown leaves
-- it off (the Hearthstone's, which everyone knows). With the hideSecondCooldown option, a 1 second cooldown goes from
-- any Use line, matched by a rule or not: it only stops the item being used again at once (armour kits, food).
local COOLDOWN = {
	enUS = "^(.-) (%([^()]* Cooldown%))$",
}
COOLDOWN.enGB = COOLDOWN.enUS
local cooldownPattern = COOLDOWN[GetLocale()]
local ONE_SECOND = {
	enUS = "^%(1 [^()]-Sec[^()]-Cooldown%)$", -- "(1 |4Sec:Sec; Cooldown)" or "(1 Sec Cooldown)"; not "(10 Sec", "(1 Min"
}
ONE_SECOND.enGB = ONE_SECOND.enUS
local oneSecondPattern = ONE_SECOND[GetLocale()]

-- The short form of `body` by the first rule that matches it whole, or nil.
local function ByRules(list, body)
	for i = 1, #list do
		local rule = list[i]
		local found = { body:match(rule[1]) }
		if found[1] then
			for k = 1, #found do found[k] = Tidy(found[k]) end
			local order = rule.order
			if order then
				local ordered = {}
				for to, from in ipairs(order) do ordered[to] = found[from] end
				found = ordered
			end
			-- Protected: a translation with a different number of %s (or a rule's `order` naming a missing capture)
			-- mustn't raise inside the game's tooltip build; the line then stays as the game wrote it, and the result
			-- is cached, so it's reported once.
			local ok, short = pcall(string.format, L[rule[2]], unpack(found))
			if ok then return short, rule end
			ns.ReportError("condense " .. tostring(rule[2]), short)
			return nil
		end
	end
	return nil
end

local function Match(text, kind)
	local plain = Plain(text)
	if kind == "dps" then
		local value = DPS and plain:match(DPS)
		return value and L.SHORT_DPS:format(value) or false
	end
	local list = rules[kind]
	local body, prefix
	if list then body, prefix = Body(plain, kind) end
	if not body then return false end
	local profile = ns.profile or {}
	local cooldown
	if cooldownPattern then
		local front, tail = body:match(cooldownPattern)
		if front then body, cooldown = front, tail end
	end
	local dropOneSecond = cooldown and profile.hideSecondCooldown and oneSecondPattern and cooldown:find(oneSecondPattern)
	local short, rule = ByRules(list, body)
	if not short then
		-- The first sentence alone, the rest as written (without its final full stop).
		local first, rest = body:match("^(.-%.) (%u.*)$")
		if first then
			short, rule = ByRules(list, first)
			if short then short = short .. ". " .. rest:gsub("%.$", "") end
		end
	end
	if not short then
		-- No rule: only a 1 second cooldown can go, the rest stays as the game wrote it.
		if dropOneSecond then return prefix .. " " .. body end
		return false
	end
	-- Equip lines can lose their prefix and read like the game's white stat lines ("+3 Stamina"), when the short form
	-- starts that way (every Equip rule's does).
	if not (kind == "equip" and profile.dropEquipPrefix and short:find("^[%+%-]%d")) then
		short = prefix .. " " .. short
	end
	if cooldown and not rule.dropCooldown and not dropOneSecond then short = short .. " " .. cooldown end
	return short
end

-- Bag and character tooltips rebuild five times a second (design document 2.9), so each text is matched once.
local CACHE_SIZE = 500
local KINDS = { "use", "equip", "proc", "set", "dps" }
local cache, cached

local function NewCache()
	cache, cached = {}, 0
	for _, kind in ipairs(KINDS) do cache[kind] = {} end
end
NewCache()

-- The short forms depend on these options too, so they're worked out again when one changes.
local SHAPING = { dropEquipPrefix = true, hideSecondCooldown = true }
ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil or SHAPING[what] then NewCache() end
end)

function Condense.Shorten(text, kind)
	if type(text) ~= "string" or ns.IsSecret(text) or not cache[kind] then return nil end
	local short = cache[kind][text]
	if short == nil then
		short = Match(text, kind)
		if cached >= CACHE_SIZE then NewCache() end
		cache[kind][text] = short
		cached = cached + 1
	end
	return short or nil
end
