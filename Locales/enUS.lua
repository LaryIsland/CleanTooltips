local _, ns = ...

-- Every line of text players see, in one place for reviewing and translating. Code uses the names on the left
-- (L.OPT_SELL_PRICE); a name with no text here shows as itself, with an error, so a typo is easy to spot.
--
-- This is British English. It's registered as enUS because the game has no English locale but enUS (British clients
-- report enUS too) and AceLocale treats enGB as enUS. A translation goes in a file of its own, loaded after this one
-- in the TOC, that starts:
--   local L = LibStub("AceLocale-3.0"):NewLocale("CleanTooltips", "deDE")
--   if not L then return end
-- and sets the lines it translates; anything it leaves out stays in English.
--
-- Placeholders: %s is text (a name, a number copied from the game's line). Keep them, in the same order. %% is a
-- percent sign.
--
-- Names of things in the addon players see or click (options, pages, commands) go in braces, {like this}: they're
-- shown in a colour of their own.

local L = LibStub("AceLocale-3.0"):NewLocale("CleanTooltips", "enUS", true)

-- Shortened Use and Equip lines (Condense.lua). Each %s is a number copied from the game's line,
-- in the order the game's line has them. The game's own "Use:" or "Equip:" goes in front. Durations copied from the
-- game's line read "30s" for seconds (the addon turns "30 sec" into "30s"); minutes and hours stay as written.
L["SHORT_FOOD"] = "Heal +%s over %ss"
L["SHORT_DRINK"] = "Mana +%s over %ss"
L["SHORT_FOOD_DRINK"] = "Heal +%s, Mana +%s over %ss"
L["SHORT_POTION"] = "Heal +%s to %s"
L["SHORT_MANA_POTION"] = "Mana +%s to %s"
L["SHORT_BANDAGE"] = "Heal +%s over %ss"
-- Food with Well Fed: heal, seconds, then the buff's amount and stat ("3", "Stamina"), then the XP bonus.
L["SHORT_FOOD_WELL_FED_XP"] = "Heal +%s over %ss, Well Fed: +%s %s, +%s%% Kill XP" -- XP from kills only
L["SHORT_FOOD_WELL_FED"] = "Heal +%s over %ss, Well Fed: +%s %s"
L["SHORT_HEAL_TARGET"] = "Heal target +%s to %s"
-- Elixirs and buff potions: amount, stat, and the duration as the game wrote it ("1 hour").
L["SHORT_BUFF"] = "+%s %s for %s"
L["SHORT_RUN_SPEED"] = "+%s%% Run Speed for %ss"
-- A potion: the percentage, then the duration as the game wrote it ("30 sec").
L["SHORT_ATTACK_SPEED_FOR"] = "+%s%% Attack Speed for %s"
-- A fishing lure: the skill, then the duration as the game wrote it ("10 min").
L["SHORT_LURE"] = "Lure: +%s Fishing for %s"
-- A recipe or pattern: what it teaches, as the game wrote it ("Crocolisk Gumbo").
L["SHORT_RECIPE"] = "Learn %s"
-- An enchanting formula: the item with its article ("a two-handed weapon"), then what it gains ("+5 Spirit").
L["SHORT_FORMULA"] = "Learn to enchant %s with %s"
-- Cure kits: what's cured, as the game wrote it ("poisons"), and up to which level.
L["SHORT_CURE"] = "Cure %s up to level %s"
-- Armour kits: the slots as the game wrote them, the stat's value and name, the armour, then the item level.
L["SHORT_ENCHANT"] = "Enchant %s: +%s %s, +%s Armor"
L["SHORT_ENCHANT_LEVEL"] = "Enchant %s: +%s %s, +%s Armor (ilvl %s+)"
-- A trinket raising spell damage and healing by the same amount: spell damage, healing, then the duration ("30 sec").
L["SHORT_DAMAGE_HEALING_FOR"] = "+%s Spell Damage, +%s Healing for %s"
-- Poisons: minutes, charges, chance, then the effect.
L["SHORT_POISON_DAMAGE"] = "Poison %s min, %s charges: %s%% chance of %s to %s %s damage"
L["SHORT_POISON_SLOW"] = "Poison %s min: %s%% chance to slow %s%% for %ss"
L["SHORT_POISON_CAST"] = "Poison %s min, %s charges: %s%% chance of +%s%% cast time for %ss"
-- %s the place, as the game wrote it. The cooldown is left off.
L["SHORT_HEARTHSTONE"] = "Returns you to %s"
L["SHORT_ATTACK_POWER"] = "+%s Attack Power"
L["SHORT_RANGED_ATTACK_POWER"] = "+%s Ranged Attack Power"
-- The second %s is the creature type, as the game wrote it (Beasts, Undead).
L["SHORT_ATTACK_POWER_AGAINST"] = "+%s Attack Power vs %s"
-- Druid forms only.
L["SHORT_FERAL_ATTACK_POWER"] = "+%s Feral Attack Power"
L["SHORT_HEALING"] = "+%s Healing"
L["SHORT_HEALING_DAMAGE"] = "+%s Healing, +%s Spell Damage"
-- Spell damage and healing by one amount, damage first as the game writes it ("damage and healing ... by up to 5").
L["SHORT_DAMAGE_HEALING"] = "+%s Spell Damage, +%s Healing"
L["SHORT_SPELL_DAMAGE"] = "+%s Spell Damage"
-- The second %s is the school, as the game wrote it (Fire, Shadow).
L["SHORT_SCHOOL_DAMAGE"] = "+%s %s Damage"
-- The second %s is the creature type, as the game wrote it.
L["SHORT_SPELL_DAMAGE_AGAINST"] = "+%s Spell Damage vs %s"
L["SHORT_HIT"] = "+%s%% Hit"
L["SHORT_SPELL_HIT"] = "+%s%% Spell Hit"
-- The second %s is the school, as the game wrote it.
L["SHORT_SCHOOL_HIT"] = "+%s%% %s Hit"
L["SHORT_RANGED_HIT"] = "+%s%% Ranged Hit"
L["SHORT_CRIT"] = "+%s%% Crit"
L["SHORT_MELEE_CRIT"] = "+%s%% Melee Crit"
L["SHORT_RANGED_CRIT"] = "+%s%% Ranged Crit"
L["SHORT_SPELL_CRIT"] = "+%s%% Spell Crit"
L["SHORT_CRIT_DAMAGE"] = "+%s%% Crit Damage"
L["SHORT_SPELL_CRIT_DAMAGE"] = "+%s%% Spell Crit Damage"
L["SHORT_MP5"] = "+%s Mana per 5s"
L["SHORT_HP5"] = "+%s Health per 5s"
L["SHORT_DEFENSE"] = "+%s Defense" -- the game's own name for the stat
L["SHORT_DODGE"] = "+%s%% Dodge"
L["SHORT_PARRY"] = "+%s%% Parry"
L["SHORT_PARRY_DOWN"] = "-%s%% Parry"
L["SHORT_BLOCK"] = "+%s%% Block"
-- Chance to block, then the percentage more each block stops.
L["SHORT_BLOCK_AND_AMOUNT"] = "+%s%% Block, +%s%% Block Amount"
L["SHORT_BLOCK_VALUE"] = "+%s Block Value"
L["SHORT_THREAT"] = "+%s%% Threat"
L["SHORT_THREAT_DOWN"] = "-%s%% Threat"
L["SHORT_RANGED_ATTACK_SPEED"] = "+%s%% Ranged Attack Speed"
L["SHORT_MOUNT_SPEED"] = "+%s%% Mount Speed"
-- The second %s is the effect, as the game wrote it (Fear, Sleep, Disorient).
L["SHORT_EFFECT_RESIST"] = "+%s%% %s Resist"
-- Damage dealt to whoever hits you. The second %s is the school, as the game wrote it (Arcane, Physical).
L["SHORT_THORNS"] = "%s %s damage to attackers when struck"
-- Less mana for some spells: the amount, then the spells as the game wrote them ("Flame Shock and Lightning Bolt").
L["SHORT_MANA_COST"] = "-%s Mana Cost for %s"
L["SHORT_REVIVE_CAST_TIME"] = "-%s%% Resurrection Cast Time"
-- A stat only some of the time: amount, stat, then when, as the game wrote it ("affected by a Bleed").
L["SHORT_STAT_WHILE"] = "+%s %s while %s"
-- Extra damage dealt on hits against one kind of creature (an effect, not a stat): amount, school, then the creature
-- type as the game wrote it (Swine).
L["SHORT_DAMAGE_AGAINST"] = "%s %s damage on hits vs %s"
-- Damage dealt to the attacker each time you block (an effect, not a stat): the range, then the school.
L["SHORT_BLOCK_DAMAGE"] = "%s to %s %s damage to attackers on block"
-- Use lines with a duration, written as the game wrote it ("15 sec").
L["SHORT_ALL_STATS_FOR"] = "+%s All Stats for %s"
L["SHORT_SPELL_HIT_FOR"] = "+%s%% Spell Hit for %s"
-- "Chance on hit:" lines. The second %s is the school, as the game wrote it (Fire, Nature).
L["SHORT_PROC_DAMAGE"] = "%s %s damage"
L["SHORT_PROC_DOT"] = "%s %s damage, +%s over %ss"
L["SHORT_PROC_BLEED"] = "%s bleed damage over %ss"
L["SHORT_PROC_PLAIN"] = "%s damage"
L["SHORT_PROC_DRAIN"] = "Steal %s life"
-- A weapon's damage per second, lowercase as the game writes "damage per second".
L["SHORT_DPS"] = "(%s dps)"
L["SHORT_ATTACK_SPEED"] = "+%s%% Attack Speed"
L["SHORT_ARMOR"] = "+%s Armor" -- the game's own spelling for the stat
L["SHORT_SHIELD_ARMOR"] = "+%s Armor with a Shield"
-- The second %s is the school, as the game wrote it (Fire, Shadow).
L["SHORT_RESIST"] = "+%s %s Resist"
L["SHORT_ALL_RESIST"] = "+%s All Resist"
L["SHORT_SPELL_PENETRATION"] = "+%s Spell Penetration"
L["SHORT_STEALTH"] = "+%s Stealth"
L["SHORT_STEALTH_DETECTION"] = "+%s Stealth Detection"
-- The second %s is the skill, as the game wrote it (Swords, Two-handed Axes, Fishing).
L["SHORT_SKILL"] = "+%s %s"
-- A stat line the game already writes short ("+5 Agility."), without its full stop. The second %s is the stat.
L["SHORT_STAT"] = "+%s %s"

-- Options page: Clean-up (Options.lua)
L["OPT_SELL_PRICE"] = "Hide sell price"
L["OPT_SELL_PRICE_AT_VENDOR"] = "Show it at vendors"
L["OPT_DURABILITY"] = "Hide durability on undamaged items"
L["OPT_LEVEL"] = "Hide level requirements you meet"
L["OPT_MET_REQUIREMENTS"] = "Hide other requirements you meet"
L["OPT_SOULBOUND"] = "Hide Soulbound"
L["OPT_UNIQUE"] = "Hide Unique on items you own"
L["OPT_FACTION"] = "Hide faction on unit tooltips"
L["OPT_PVP"] = "Hide PvP on unit tooltips"
L["OPT_SHORTEN_USE"] = "Shorten Use lines"
L["OPT_SHORTEN_EQUIP"] = "Shorten Equip lines"
L["OPT_HIDE_SECOND_COOLDOWN"] = "Hide 1 second cooldowns"
L["OPT_DROP_EQUIP_PREFIX"] = "Leave out \"Equip:\""
L["OPT_SHORTEN_DPS"] = "Shorten damage per second"
L["OPT_SAMPLE"] = "Sample item"
-- %d the item's ID, while the game hasn't loaded its name.
L["SAMPLE_ITEM"] = "Item %d"
-- Above the preview tooltip as the game draws it, beside Clean Tooltips' own.
L["PREVIEW_GAME"] = "Game"

-- Options page: Look
L["PAGE_LOOK"] = "Look"
L["OPT_CLASS_NAMES"] = "Class colours for player names"
L["OPT_HOSTILE_RED"] = "Keep red names for hostile players"
L["OPT_BORDERS"] = "Border colour"
L["OPT_BORDER_CLASS"] = "Players by class"
L["OPT_BORDER_REACTION"] = "NPCs by reaction"
L["OPT_BORDER_QUALITY"] = "Items by quality"
L["OPT_HEALTH_BAR"] = "Health bar texture"
L["OPT_FONT"] = "Font"
-- The first choice in the texture and font lists.
L["OPT_GAME_DEFAULT"] = "Default"
L["OPT_BACKGROUND"] = "Background"
L["OPT_BACKGROUND_TIP"] = "Colour and transparency."
L["OPT_BACKGROUND_RESET"] = "Reset"
-- The Look page's sample name lines, for what can't be previewed with a real unit.
L["SAMPLE_HOSTILE_PLAYER"] = "Hostile player"
L["SAMPLE_HOSTILE_NPC"] = "Hostile NPC"

-- Options page: Sources
L["PAGE_SOURCES"] = "Sources"
L["OPT_SHOW_SOURCES"] = "Show line sources beside tooltips"
L["OPT_SHOW_SOURCES_TIP"] = "Names the addon beside each line it added."
L["OPT_SOURCES_LIST"] = "Show"
L["SOURCES_MODE_ADDONS"] = "All addons"
L["SOURCES_MODE_LAST"] = "Current tooltip"
L["SOURCES_HIDE_ADDON"] = "Hide everything"
-- At the top of the Sources page.
L["SOURCES_ADVICE"] = "It's better to turn a tooltip line off in the addon that adds it. Use this for lines that addon has no setting for."
L["SOURCES_EMPTY"] = "No addon has added a tooltip line yet this session."
L["SOURCES_LAST_EMPTY"] = "No tooltip has been shown yet this session."
L["SOURCES_LAST_NONE"] = "No addon added a line to this tooltip."
-- A line whose text the game hid (unit tooltips in combat).
L["SOURCES_UNREADABLE"] = "(text hidden by the game)"
-- The sources column. %s the addon that changed the line's text.
L["SOURCES_EDITED"] = "%s edited"
-- A removed line, listed under the tooltip: %s the addon, %s the line.
L["SOURCES_REMOVED"] = "%s: %s"
L["BINDING_SOURCES"] = "Show tooltip line sources"


-- Options page: Profiles
L["PAGE_PROFILES"] = "Profiles"
L["PROFILE_ACTIVE"] = "Active profile"
L["PROFILE_DEFAULT"] = "Default for new characters"
L["PROFILE_NEW"] = "New Profile"
L["PROFILE_NEW_TEXT"] = "Name the new profile."
L["PROFILE_COPY"] = "Copy from"
-- %s the profile copied from, %s the current one.
L["PROFILE_COPY_CONFIRM"] = "Copy everything from %s into %s?"
L["PROFILE_CHOOSE"] = "Choose a profile"
L["PROFILE_DELETE"] = "Delete"
L["PROFILE_DELETE_CONFIRM"] = "Delete the profile %s?"
L["PROFILE_RESET"] = "Reset Profile"
L["PROFILE_RESET_CONFIRM"] = "Reset the profile %s to the default settings?"
L["PROFILE_EXISTS"] = "There's already a profile called %s."
-- Refusals, only if Blizzard's own ERR_NOT_IN_COMBAT is missing.
L["OPT_IN_COMBAT"] = "You can't do that in combat."

-- /ctt help (Commands.lua)
L["HELP_OPTIONS"] = "{/ctt} - options"
L["HELP_SOURCES"] = "{/ctt sources} - toggle line sources beside tooltips"
L["HELP_LAST"] = "{/ctt last} - the current tooltip's lines"
L["HELP_HELP"] = "{/ctt help} - this list"

ns.L = LibStub("AceLocale-3.0"):GetLocale("CleanTooltips")
