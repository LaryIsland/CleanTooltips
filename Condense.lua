local _, ns = ...
local L = ns.L

-- Shortened item lines: "Use:", "Equip:", "Chance on hit:" and set bonus ("Set:", "(3) Set:")
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
-- Wording is Forever's: two spaces between sentences, percentages on gear with one decimal ("by 2.0%"), and Equip
-- lines typed None. Only the English client has rules.
--   ns.Condense.KindOf(lineType, text)   "use", "equip", "proc", "set", "dps" or nil
--   ns.Condense.Shorten(text, kind)      the short form, or nil; and whether a rule matched
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
	lineType = ns.Readable(lineType)
	local kind = lineType ~= nil and KIND[lineType]
	if kind then return kind end
	text = ns.Readable(text)
	if type(text) ~= "string" or not FIRST[text:byte(1) or 0] then return nil end
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
	-- Spell damage and healing: both shown, in the game's order. "Damage and healing" by one amount reads damage
	-- first; "healing ... and damage ..." reads healing first.
	{ "^Increases damage and healing done by magical spells and effects by up to " .. N .. END, "SHORT_DAMAGE_HEALING",
		order = { 1, 1 } },
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
	-- Forever capitalises it on spell Equip lines ("a Critical Strike with Spells")
	{ "^Improves your chance to get a [Cc]ritical [Ss]trike with [Ss]pells by " .. N .. "%%" .. END, "SHORT_SPELL_CRIT" },
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
	{ "^Increases your chance to [Dd]odge an attack by " .. N .. "%%" .. END, "SHORT_DODGE" }, -- Forever: "Dodge"
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
	{ "^Increases mount speed by " .. N .. "%%" .. END, "SHORT_MOUNT_SPEED" },
	-- Resisting crowd control ("Reduces the hit chance of Fear effects against you by 2%.")
	{ "^Reduces the hit chance of (.-) effects against you by " .. N .. "%%" .. END, "SHORT_EFFECT_RESIST",
		order = { 2, 1 } },
	-- Damage back to whoever hits you (with and without the comma)
	{ "^When struck in combat,? inflicts " .. N .. " (%a+) damage to the attacker" .. END, "SHORT_THORNS" },
	-- Other gear effects. The +/- form only where the line really changes a stat (mana cost, cast
	-- time, a stat some of the time); effects that deal damage (to attackers, on block, on hits) say what they do.
	{ "^Reduces the mana cost of (.-) by " .. N .. " Mana" .. END, "SHORT_MANA_COST", order = { 2, 1 } },
	{ "^Reduces the mana cost of (.-) by " .. N .. END, "SHORT_MANA_COST", order = { 2, 1 } },
	{ "^Reduces the cast time of spells and effects that revive targets by " .. N .. "%%" .. END,
		"SHORT_REVIVE_CAST_TIME" },
	{ "^Increases (%a+) by " .. N .. " while (.-)" .. END, "SHORT_STAT_WHILE", order = { 2, 1, 3 } },
	{ "^Spells and attacks against (.-) deal " .. N .. " (%a+) damage" .. END, "SHORT_DAMAGE_AGAINST",
		order = { 2, 3, 1 } },
	{ "^Deals " .. N .. " to " .. N .. " (%a+) damage every time you block" .. END, "SHORT_BLOCK_DAMAGE" },
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
			-- Well Fed food (the stat can be several words: "Attack Power", "Stamina and Spirit").
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
			-- Potions: Forever writes "health"/"mana" and "Health"/"Mana"
			{ "^Restores " .. N .. " to " .. N .. " [Hh]ealth" .. END, "SHORT_POTION" },
			{ "^Restores " .. N .. " to " .. N .. " [Mm]ana" .. END, "SHORT_MANA_POTION" },
			-- Healing over time without eating (a trinket; later sentences follow as written)
			{ "^Restores " .. N .. " [Hh]ealth over " .. N .. " sec" .. END, "SHORT_BANDAGE" },
			{ "^Heals " .. N .. " damage over " .. N .. " sec" .. END, "SHORT_BANDAGE" },
			{ "^Heals the target for " .. N .. " damage over " .. N .. " sec" .. END, "SHORT_BANDAGE" },
			{ "^Heal your target for " .. N .. " to " .. N .. END, "SHORT_HEAL_TARGET" },
			{ "^Returns you to (.-)%. Speak to an Innkeeper in a different place to change your home location" .. END,
				"SHORT_HEARTHSTONE", dropCooldown = true },
			-- Elixirs, buff potions and trinkets; run speed first
			{ "^Increases run speed by " .. N .. "%% for " .. N .. " sec" .. END, "SHORT_RUN_SPEED" },
			{ "^Increases damage and healing done by magical spells and effects by up to " .. N .. " for (.-)" .. END,
				"SHORT_DAMAGE_HEALING_FOR", order = { 1, 1, 2 } }, -- both, damage first
			{ "^Increases your (%a+) by " .. N .. "%. Effect lasts for (.-)" .. END, "SHORT_BUFF", order = { 2, 1, 3 } },
			{ "^Increases (%a+) by " .. N .. " for (.-)" .. END, "SHORT_BUFF", order = { 2, 1, 3 } },
			{ "^Increases your (%a+) by " .. N .. END, "SHORT_STAT", order = { 2, 1 } },
			{ "^Increase (%a+) by " .. N .. END, "SHORT_STAT", order = { 2, 1 } }, -- "Increase Rage by 30."
			{ "^Increases (%a+) by " .. N .. END, "SHORT_STAT", order = { 2, 1 } }, -- "Increases Stamina by 3."
			{ "^Increases your attack speed by " .. N .. "%% for (.-)" .. END, "SHORT_ATTACK_SPEED_FOR" },
			{ "^Increases all attributes by " .. N .. " for (.-)" .. END, "SHORT_ALL_STATS_FOR" },
			{ "^Increases your Spell Hit chance by " .. N .. "%% for (.-)" .. END, "SHORT_SPELL_HIT_FOR" },
			-- Fishing lures ("for 10 min." and "for 10 minutes.")
			{ "^When applied to your fishing pole, increases Fishing by " .. N .. " for (.-)" .. END, "SHORT_LURE" },
			-- Recipes and patterns: what they teach (a second sentence follows as written)
			{ "^Teaches you how to cook an? (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to cook (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to make an? (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to make (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to sew an? (.-)" .. END, "SHORT_RECIPE" },
			{ "^Teaches you how to sew (.-)" .. END, "SHORT_RECIPE" },
			-- Enchanting formulae (line type ItemSpellTriggerLearn): the item with its article, then the stat
			{ "^Teaches you how to permanently enchant (an? .-) so it grants (.-)" .. END, "SHORT_FORMULA" },
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
			{ "^Wounds the target for " .. N .. " damage" .. END, "SHORT_PROC_PLAIN" },
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

-- Durations in seconds read "30s" everywhere in a short form ("for 30 sec", "for 30 seconds"),
-- the sentences that follow it as written included. The cooldown is put back after this, so it keeps the game's
-- wording (its |4 plural code). Minutes and hours stay as written.
local SECONDS = {
	enUS = { "(%d) seconds?%f[^%a]", "(%d) sec%f[^%a]" },
}
SECONDS.enGB = SECONDS.enUS
local secondsPatterns = SECONDS[GetLocale()] or {}

local function Seconds(text)
	for i = 1, #secondsPatterns do text = text:gsub(secondsPatterns[i], "%1s") end
	return text
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
			local key = rule[2]
			-- Protected: a translation with a different number of %s (or a rule's `order` naming a missing capture)
			-- mustn't raise inside the game's tooltip build; the line then stays as the game wrote it, and the result
			-- is cached, so it's reported once.
			local ok, short = pcall(string.format, L[key], unpack(found))
			if ok then return short, rule end
			ns.ReportError("condense " .. tostring(key), short)
			return nil
		end
	end
	return nil
end

local function Match(text, kind)
	local plain = Plain(text)
	if kind == "dps" then
		local value = DPS and plain:match(DPS)
		if value then return L.SHORT_DPS:format(value), true end
		return false, false
	end
	local list = rules[kind]
	local body, prefix
	if list then body, prefix = Body(plain, kind) end
	if not body then return false, false end
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
	-- With Leave out "Equip:", every Equip line loses its prefix, shortened or not. Stat short forms start
	-- with + or -, so those read like the game's white stat lines ("+3 Stamina").
	local dropPrefix = kind == "equip" and profile.dropEquipPrefix
	if not short then
		-- No rule: the rest stays as the game wrote it; only "Equip:" or a 1 second cooldown can go.
		if dropPrefix then return cooldown and (body .. " " .. cooldown) or body, false end
		if dropOneSecond then return prefix .. " " .. body, false end
		return false, false
	end
	short = Seconds(short)
	if not dropPrefix then short = prefix .. " " .. short end
	if cooldown and not rule.dropCooldown and not dropOneSecond then short = short .. " " .. cooldown end
	return short, true
end

-- Bag and character tooltips rebuild five times a second, so each text is matched once, per
-- kind: [text] = { short form or false, whether a rule matched }.
local CACHE_SIZE = 500
local cache = {}
for kind in pairs(Condense.OPTION) do cache[kind] = ns.Cache(CACHE_SIZE) end

-- The short forms depend on these options too, so they're worked out again when one changes.
local SHAPING = { dropEquipPrefix = true, hideSecondCooldown = true }
ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil or SHAPING[what] then
		for _, kindCache in pairs(cache) do kindCache:Clear() end
	end
end)

-- The line as Clean Tooltips shows it (nil: as the game wrote it), and whether a rule matched it (false when only
-- "Equip:" or a 1 second cooldown went; /ctt capture counts those as not shortened).
function Condense.Shorten(text, kind)
	text = ns.Readable(text)
	local kindCache = cache[kind]
	if type(text) ~= "string" or not kindCache then return nil, false end
	local entry = kindCache.items[text]
	if entry == nil then
		local short, matched = Match(text, kind)
		entry = { short, matched == true }
		kindCache:Set(text, entry)
	end
	return entry[1] or nil, entry[2]
end
