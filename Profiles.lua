local _, ns = ...
local L = ns.L

-- Options > AddOns > Clean Tooltips > Profiles: the active profile, the default for new
-- characters, new, copy, delete and reset, each asking first through the game's popups.
--   ns.Options.BuildProfiles(canvas)   the page, built on first show (OptionsWidgets.lua)

local Kit = ns.OptionsKit
local LEFT, TOP, ROW, LABEL_WIDTH = Kit.LEFT, Kit.TOP, Kit.ROW, Kit.LABEL_WIDTH
local RefuseInCombat, NewPage, Dropdown = Kit.RefuseInCombat, Kit.NewPage, Kit.Dropdown

local POPUP_PREFIX = "CLEANTOOLTIPS_"
local NAME_LETTERS = 32

-- Profiles -------------------------------------------------------------------------------------------------------------
-- A canvas page like the others, with CT's own dropdowns and buttons. Not a list page of the game's Settings controls:
-- the panel's search reads every list page's settings, and reading CT's taints the rest of the search, so the game
-- then refuses the Social page's protected Discord call while it draws the results (ADDON_ACTION_FORBIDDEN).
-- Canvas pages aren't searched.

local profilesPage

local function RefreshProfiles()
	if profilesPage then profilesPage:Refresh() end
end

local function Trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ProfileNames(skipCurrent)
	local names = {}
	if not ns.db then return names end
	local current = ns.db:GetCurrentProfile()
	for _, name in ipairs((ns.db:GetProfiles({}))) do
		if not (skipCurrent and name == current) then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

local function ProfileExists(name)
	for _, existing in ipairs(ProfileNames()) do
		if existing == name then return true end
	end
	return false
end

-- The profile names for a dropdown, as { value, text }; `extra` first when it isn't a profile yet.
local function ProfileChoices(skipCurrent, extra)
	return function()
		local list, seen = {}, {}
		if extra then
			list[1] = { value = extra, text = extra }
			seen[extra] = true
		end
		for _, name in ipairs(ProfileNames(skipCurrent)) do
			if not seen[name] then list[#list + 1] = { value = name, text = name } end
		end
		return list
	end
end

local PROFILE_DROPDOWN_WIDTH = 200
local BUTTON_WIDTH = 160

local function ProfileButton(page, text, x, y, click)
	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(BUTTON_WIDTH, 22)
	button:SetPoint("TOPLEFT", x, y)
	button:SetScript("OnClick", click)
	return button
end

-- A dropdown that picks a profile to act on (copy from, delete): it always reads as a prompt, asks to confirm, and is
-- greyed while there's no other profile.
local function PickerDropdown(page, labelText, popup, y)
	local dropdown = Dropdown(page, labelText, PROFILE_DROPDOWN_WIDTH, ProfileChoices(true),
		function() return nil end,
		function(value)
			if RefuseInCombat() then return end
			StaticPopup_Show(POPUP_PREFIX .. popup, value, ns.db and ns.db:GetCurrentProfile() or "", value)
		end, LEFT, y)
	dropdown:SetDefaultText(L.PROFILE_CHOOSE)
	table.insert(page.refreshers, function() dropdown:SetEnabled(#ProfileNames(true) > 0) end)
	return dropdown
end

function ns.Options.BuildProfiles(canvas)
	local page = NewPage(L.PAGE_PROFILES, canvas)
	local y = TOP
	page.Active = Dropdown(page, L.PROFILE_ACTIVE, PROFILE_DROPDOWN_WIDTH, ProfileChoices(false),
		function() return ns.db and ns.db:GetCurrentProfile() end,
		function(value)
			if ns.db and not RefuseInCombat() then ns.db:SetProfile(value) end
			RefreshProfiles()
		end, LEFT, y)
	y = y - ROW - 8
	-- The default for new characters may name a profile that doesn't exist yet (AceDB makes it on first use).
	page.Default = Dropdown(page, L.PROFILE_DEFAULT, PROFILE_DROPDOWN_WIDTH,
		function() return ProfileChoices(false, ns.global and ns.global.defaultProfile or "Default")() end,
		function() return ns.global and ns.global.defaultProfile or "Default" end,
		function(value)
			if ns.global then ns.global.defaultProfile = value end
			RefreshProfiles()
		end, LEFT, y)
	y = y - ROW - 16
	page.New = ProfileButton(page, L.PROFILE_NEW, LEFT + LABEL_WIDTH, y, function()
		if not RefuseInCombat() then StaticPopup_Show(POPUP_PREFIX .. "PROFILE_NEW") end
	end)
	y = y - ROW - 8
	page.Copy = PickerDropdown(page, L.PROFILE_COPY, "PROFILE_COPY", y)
	y = y - ROW - 8
	page.Delete = PickerDropdown(page, L.PROFILE_DELETE, "PROFILE_DELETE", y)
	y = y - ROW - 16
	page.Reset = ProfileButton(page, L.PROFILE_RESET, LEFT + LABEL_WIDTH, y, function()
		if not RefuseInCombat() and ns.db then
			StaticPopup_Show(POPUP_PREFIX .. "PROFILE_RESET", ns.db:GetCurrentProfile())
		end
	end)
	-- Defaults on this page would be Reset Profile, which asks first: the button is there for that.
	function page:OnDefault() end
	profilesPage = page
	return page
end

local function Popup(key, info)
	info.timeout = 0
	info.whileDead = true
	info.hideOnEscape = true
	StaticPopupDialogs[POPUP_PREFIX .. key] = info
end

Popup("PROFILE_NEW", {
	text = L.PROFILE_NEW_TEXT,
	button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = true, maxLetters = NAME_LETTERS,
	OnShow = function(dialog) dialog:GetButton1():Disable() end,
	EditBoxOnTextChanged = function(editBox) StaticPopup_StandardNonEmptyTextHandler(editBox) end,
	EditBoxOnEnterPressed = function(editBox)
		local button = editBox:GetParent():GetButton1()
		if button:IsEnabled() then button:Click() end
	end,
	OnAccept = function(dialog)
		if RefuseInCombat() or not ns.db then return end
		local name = Trim(dialog:GetEditBox():GetText())
		if name == "" then return true end
		if ProfileExists(name) then
			ns.Print(L.PROFILE_EXISTS:format(name))
			return true
		end
		ns.db:SetProfile(name)
		RefreshProfiles()
	end,
})

Popup("PROFILE_COPY", {
	text = L.PROFILE_COPY_CONFIRM, -- %s the profile copied from, %s the current one
	button1 = YES, button2 = NO, showAlert = true,
	OnAccept = function(_, source)
		if RefuseInCombat() or not ns.db or not ProfileExists(source) then return end
		if source ~= ns.db:GetCurrentProfile() then ns.db:CopyProfile(source) end
	end,
})

Popup("PROFILE_DELETE", {
	text = L.PROFILE_DELETE_CONFIRM, -- %s the profile
	button1 = YES, button2 = NO, showAlert = true,
	OnAccept = function(_, name)
		if RefuseInCombat() or not ns.db or not ProfileExists(name) then return end
		if name == ns.db:GetCurrentProfile() then return end
		ns.db:DeleteProfile(name)
		if ns.global and ns.global.defaultProfile == name then ns.global.defaultProfile = "Default" end
		RefreshProfiles()
	end,
})

Popup("PROFILE_RESET", {
	text = L.PROFILE_RESET_CONFIRM, -- %s the profile
	button1 = YES, button2 = NO, showAlert = true,
	OnAccept = function()
		if not RefuseInCombat() and ns.db then ns.db:ResetProfile() end
	end,
})

ns.Listen("SETTINGS_CHANGED", function(what)
	if what == nil then RefreshProfiles() end
end)
