local _, private = ...;
local L = private.L;
local config = private.config;
local format = string.format;
local floor = math.floor;

local PANEL_NAME = "Pretty Loot Alert";

local defaults = {
	-- Display
	scale = 1, sound = true, time = 0.30, numbuttons = 4, anims = true,
	offset_x = 4, point_x = 0, point_y = -255, frame_strata = "HIGH",  -- offset_x: vertical gap between toasts
	-- Toast types
	looting = true, creating = true, rolling = true, money = true, recipes = true, honor = true,
	-- Quality filter
	ignore_level = true, low_level = 2, max_level = 4,
};
-- Advanced page: per toast type overrides, used while adv_enabled is on
local ADV_TYPES = { "looting", "creating", "rolling", "money", "recipes", "honor" };
local ADV_QUALITY_TYPES = { looting = true, creating = true, rolling = true };
defaults.adv_enabled = false;
defaults.adv_initialized = false;  -- the overrides are seeded from the main options on first enable
for _, cat in ipairs(ADV_TYPES) do
	defaults["adv_" .. cat .. "_sound"] = true;
	defaults["adv_" .. cat .. "_anims"] = true;
	if ADV_QUALITY_TYPES[cat] then
		defaults["adv_" .. cat .. "_qoverride"] = false;
		defaults["adv_" .. cat .. "_ignore"] = true;
		defaults["adv_" .. cat .. "_low"] = 2;
		defaults["adv_" .. cat .. "_max"] = 4;
		defaults["adv_" .. cat .. "_soundq"] = false;   -- "Play sound from" override on
		defaults["adv_" .. cat .. "_soundmin"] = 0;     -- lowest quality that plays the sound
	end
end
defaults.adv_money_min = 0;  -- copper
defaults.adv_honor_min = 0;  -- honor points
private.defaults = defaults;

local function ApplyDefaults(target, overwrite)
	for key, value in pairs(defaults) do
		if overwrite or target[key] == nil then target[key] = value; end
	end
end
-- config is the saved table (loaded before the addon's files): drop settings that no longer exist
for key in pairs(config) do
	if defaults[key] == nil then config[key] = nil; end
end
ApplyDefaults(config);
-- older versions saved dragged positions past the sliders' range
config.point_x = private.ClampPosition and private.ClampPosition(config.point_x) or config.point_x;
config.point_y = private.ClampPosition and private.ClampPosition(config.point_y) or config.point_y;

-- Blizzard's 1.12.1 had no Artifact (6) items, but custom servers hand them out,
-- so the quality filters and "Play sound from" go up to it
local MAX_QUALITY = 6;
local QUALITY_NAMES = {
	[0] = ITEM_QUALITY0_DESC or "Poor", [1] = ITEM_QUALITY1_DESC or "Common", [2] = ITEM_QUALITY2_DESC or "Uncommon",
	[3] = ITEM_QUALITY3_DESC or "Rare", [4] = ITEM_QUALITY4_DESC or "Epic", [5] = ITEM_QUALITY5_DESC or "Legendary",
	[6] = ITEM_QUALITY6_DESC or "Artifact",
};
local QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
	[6] = "e6cc80" };

local function OnSettingChanged(key)
	if key == "point_x" or key == "point_y" or key == "scale" then
		private.PlaceAnchor();
		private.AdjustAnchors();
	elseif key == "frame_strata" then
		private.ApplyStrata();
	elseif key == "offset_x" then
		private.AdjustAnchors();
	end
end

-- Panel and widgets
local panel = CreateFrame("Frame", "PrettyLootAlertOptionsPanel", UIParent);
panel.name = PANEL_NAME;
panel:Hide();

local widgets = {};   -- every widget: {frame, refresh, setEnabled}
local updating = false;  -- true while widgets are set from config, so they don't write it back

-- where = "left" (x from the left edge), "indent", "center" or "right" (right half)
local function Place(region, parent, where, x, y)
	if where == "indent" then
		region:SetPoint("TOPLEFT", parent, "TOPLEFT", 16 + (x or 0), y);
	elseif where == "center" then
		region:SetPoint("TOP", parent, "TOP", x or 0, y);
	elseif where == "right" then
		region:SetPoint("TOPLEFT", parent, "TOP", 10 + (x or 0), y);
	else
		region:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y);
	end
end

local function Header(parent, text, where, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	Place(fs, parent, where, nil, y);
	fs:SetText(text);
	return fs;
end

local function Slider(parent, key, label, minValue, maxValue, step, where, y, formatter)
	local name = "PrettyLootAlertOption_" .. key;
	local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate");
	slider:SetSize(200, 17);
	Place(slider, parent, where, nil, y);
	slider:SetMinMaxValues(minValue, maxValue);
	slider:SetValueStep(step);

	local text, low, high = _G[name .. "Text"], _G[name .. "Low"], _G[name .. "High"];
	formatter = formatter or function(v)
		if step < 1 then return format("%.1f", v); end
		return tostring(v);
	end
	if low then low:SetText(formatter(minValue)); end
	if high then high:SetText(formatter(maxValue)); end

	local function SetLabel(v)
		if text then text:SetText(label .. ": " .. formatter(v)); end
	end

	slider:SetScript("OnValueChanged", function(_, value)
		local v = floor(value / step + 0.5) * step;
		if step < 1 then v = tonumber(format("%.2f", v)); end
		SetLabel(v);
		if updating then return; end
		config[key] = v;
		OnSettingChanged(key);
	end);

	local widget = { frame = slider };
	widget.refresh = function()
		local v = tonumber(config[key]) or minValue;
		SetLabel(v);
		slider:SetValue(v);
	end
	widget.setEnabled = function(enabled)
		if enabled then
			if slider.Enable then slider:Enable(); end
			slider:SetAlpha(1);
		else
			if slider.Disable then slider:Disable(); end
			slider:SetAlpha(0.4);
		end
	end
	table.insert(widgets, widget);
	return widget;
end

-- Dropdown in the game's own 1.12 style, right next to its label.
-- options = { {value, text}, ... }
local function Dropdown(parent, key, label, options, y, width)
	local name = "PrettyLootAlertOption_" .. key;
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y - 9);
	fs:SetText(label);
	-- the template has ~16px of empty space on its left, so pull it back toward the label
	local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate");
	dropdown:SetPoint("LEFT", fs, "RIGHT", -10, -2);
	-- the argument order changed after 1.12 (width, frame -> frame, width)
	if not pcall(UIDropDownMenu_SetWidth, dropdown, width) then
		UIDropDownMenu_SetWidth(width, dropdown);
	end
	local text = _G[name .. "Text"];

	local function Refresh()
		local current = options[1][2];
		for _, option in ipairs(options) do
			if option[1] == config[key] then current = option[2]; end
		end
		if text then text:SetText(current); end
	end

	UIDropDownMenu_Initialize(dropdown, function()
		for _, option in ipairs(options) do
			local value = option[1];
			local info = {};
			info.text = option[2];
			info.value = value;
			info.checked = config[key] == value;
			info.func = function()
				config[key] = value;
				Refresh();
				OnSettingChanged(key);
			end
			UIDropDownMenu_AddButton(info);
		end
	end);

	local widget = { frame = dropdown, refresh = Refresh };
	table.insert(widgets, widget);
	return widget;
end

-- Position slider: slider plus an editbox for typing the value
local function PositionSlider(parent, key, label, minValue, maxValue, where, y)
	local name = "PrettyLootAlertOption_" .. key;
	local step = 1;

	local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate");
	slider:SetSize(200, 17);
	Place(slider, parent, where, nil, y);
	slider:SetMinMaxValues(minValue, maxValue);
	slider:SetValueStep(step);

	local sliderText, low, high = _G[name .. "Text"], _G[name .. "Low"], _G[name .. "High"];
	if sliderText then sliderText:SetText(label); end
	if low then low:SetText(tostring(minValue)); end
	if high then high:SetText(tostring(maxValue)); end

	local eb = CreateFrame("EditBox", name .. "EditBox", parent, "InputBoxTemplate");
	eb:SetSize(44, 16);
	eb:SetPoint("TOP", slider, "BOTTOM", 0, -4);
	eb:SetAutoFocus(false);
	eb:SetMaxLetters(5);  -- "-1000"
	eb:SetNumeric(false); -- allows the minus sign
	eb:SetJustifyH("CENTER");

	local function CommitEditBox()
		local v = tonumber(eb:GetText()) or (tonumber(config[key]) or 0);
		if v < minValue then v = minValue; end
		if v > maxValue then v = maxValue; end
		config[key] = v;
		local wasUpdating = updating;
		updating = true;
		slider:SetValue(v);
		updating = wasUpdating;
		OnSettingChanged(key);
		eb:SetText(tostring(v));
	end

	eb:SetScript("OnEnterPressed", function() CommitEditBox(); eb:ClearFocus(); end);
	-- Escape throws the typing away: restore the saved value before focus loss would commit it
	eb:SetScript("OnEscapePressed", function() eb:SetText(tostring(tonumber(config[key]) or 0)); eb:ClearFocus(); end);
	eb:SetScript("OnEditFocusLost", function() CommitEditBox(); end);


	slider:SetScript("OnValueChanged", function(_, value)
		local v = floor(value / step + 0.5) * step;
		if not eb:HasFocus() then
			eb:SetText(tostring(v));
		end
		if updating then return; end
		config[key] = v;
		OnSettingChanged(key);
	end);

	local widget = { frame = slider };
	widget.refresh = function()
		local v = tonumber(config[key]) or 0;
		-- restore the flag: RefreshAll is still refreshing the widgets after this one
		local wasUpdating = updating;
		updating = true;
		slider:SetValue(v);
		updating = wasUpdating;
		eb:SetText(tostring(v));
	end
	table.insert(widgets, widget);
	return widget;
end

local function CheckBox(parent, key, label, where, y, onChange)
	local check = CreateFrame("CheckButton", "PrettyLootAlertOption_" .. key, parent, "UICheckButtonTemplate");
	check:SetSize(26, 26);
	Place(check, parent, where, nil, y);
	local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	text:SetPoint("LEFT", check, "RIGHT", 2, 1);
	text:SetText(label);

	check:SetScript("OnClick", function()
		config[key] = check:GetChecked() and true or false;
		if onChange then onChange(); end
	end);

	local widget = { frame = check };
	widget.refresh = function() check:SetChecked(config[key] and true or false); end
	widget.setEnabled = function(enabled)
		if enabled then
			check:Enable(); text:SetTextColor(1, 1, 1);
		else
			check:Disable(); text:SetTextColor(0.5, 0.5, 0.5);
		end
	end
	table.insert(widgets, widget);
	return widget;
end

local function PushButton(parent, name, text, width, x, y, onClick)
	local button = CreateFrame("Button", "PrettyLootAlertOption_" .. name, parent, "UIPanelButtonTemplate");
	button:SetSize(width, 22);
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
	button:SetText(text);
	button:SetScript("OnClick", function() onClick(button); end);
	return button;
end

-- title
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16);
title:SetText(PANEL_NAME);
local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6);
subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0);
subtitle:SetHeight(24);
subtitle:SetJustifyH("LEFT");
subtitle:SetJustifyV("TOP");
subtitle:SetText(L.OPT_SUBTITLE);
local commandsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal");
commandsHeader:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12);
commandsHeader:SetText(L.OPT_COMMANDS);
local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
hint:SetPoint("TOPLEFT", commandsHeader, "BOTTOMLEFT", 0, -6);
hint:SetPoint("RIGHT", panel, "RIGHT", -16, 0);
hint:SetJustifyH("LEFT");
hint:SetText(L.OPT_COMMANDS_HINT);

-- Pages: each one is listed under "Pretty Loot Alert" (page.parent)
local pages = {};

local function AddPage(text)
	local index = #pages + 1;
	local page = CreateFrame("Frame", "PrettyLootAlertOptionsPage" .. index, UIParent);
	page.name = text;
	page.parent = PANEL_NAME;
	page:Hide();
	pages[index] = page;

	local pageTitle = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	pageTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16);
	pageTitle:SetText(text);
	return page;
end

local displayPage = AddPage(L.OPT_PAGE_DISPLAY);
local toastsPage = AddPage(L.OPT_PAGE_TOASTS);
local advancedPage = AddPage(L.OPT_PAGE_ADVANCED);

-- Display & Position
Header(displayPage, L.OPT_DISPLAY, "left", -64);
Slider(displayPage, "scale", L.OPT_SCALE, 0.5, 2.0, 0.1, "left", -94);
Slider(displayPage, "numbuttons", L.OPT_MAX_ALERTS, 1, 8, 1, "left", -136);
Slider(displayPage, "time", L.OPT_UPDATE_TIME, 0.1, 2.0, 0.1, "left", -178);
Slider(displayPage, "offset_x", L.OPT_SPACING, 0, 20, 1, "left", -220);
Dropdown(displayPage, "frame_strata", L.OPT_STRATA, {
	{ "BACKGROUND", L.STRATA_BACKGROUND }, { "LOW", L.STRATA_LOW }, { "MEDIUM", L.STRATA_MEDIUM },
	{ "HIGH", L.STRATA_HIGH }, { "DIALOG", L.STRATA_DIALOG }, { "FULLSCREEN", L.STRATA_FULLSCREEN },
	{ "FULLSCREEN_DIALOG", L.STRATA_FULLSCREEN_DIALOG }, { "TOOLTIP", L.STRATA_TOOLTIP },
}, -248, 130);

Header(displayPage, L.OPT_POSITION, "left", -296);
local unlockButton;
local function UpdateUnlockText()
	if unlockButton then
		unlockButton:SetText(private.IsAnchorShown() and L.OPT_LOCK or L.OPT_UNLOCK);
	end
end
unlockButton = PushButton(displayPage, "Unlock", L.OPT_UNLOCK, 120, 16, -314, function()
	private.ToggleAnchor();
	UpdateUnlockText();
end);
PushButton(displayPage, "Test", L.OPT_TEST, 130, 146, -314, function()
	private.ShowTestToasts();
end);
PositionSlider(displayPage, "point_x", L.OPT_X, -1000, 1000, "left", -362);
PositionSlider(displayPage, "point_y", L.OPT_Y, -1000, 1000, "left", -426);

-- Toasts, Effects & Quality
Header(toastsPage, L.OPT_SHOW_FOR, "left", -64);
CheckBox(toastsPage, "looting", L.OPT_LOOTING, "left", -82);
CheckBox(toastsPage, "creating", L.OPT_CRAFTING, "left", -108);
CheckBox(toastsPage, "rolling", L.OPT_ROLLS, "left", -134);
CheckBox(toastsPage, "money", L.OPT_MONEY, "left", -160);
CheckBox(toastsPage, "recipes", L.OPT_RECIPES, "left", -186);
CheckBox(toastsPage, "honor", HONOR or "Honor", "left", -212);

Header(toastsPage, L.OPT_EFFECTS, "right", -64);
CheckBox(toastsPage, "sound", L.OPT_SOUNDS, "right", -82);
CheckBox(toastsPage, "anims", L.OPT_ANIMS, "right", -108);

local function QualityText(v)
	v = tonumber(v) or 0;
	return "|cff" .. (QUALITY_HEX[v] or "ffffff") .. (QUALITY_NAMES[v] or tostring(v)) .. "|r";
end
local qualityLow, qualityMax;
local function UpdateQualityEnabled()
	local enabled = not config.ignore_level;
	if qualityLow then qualityLow.setEnabled(enabled); end
	if qualityMax then qualityMax.setEnabled(enabled); end
end
Header(toastsPage, L.OPT_QFILTER, "left", -252);
CheckBox(toastsPage, "ignore_level", L.OPT_EVERY_QUALITY, "left", -270, UpdateQualityEnabled);
qualityLow = Slider(toastsPage, "low_level", L.OPT_MIN_LOW, 0, MAX_QUALITY, 1, "left", -322, QualityText);
qualityMax = Slider(toastsPage, "max_level", L.OPT_MIN_MAX, 0, MAX_QUALITY, 1, "left", -364, QualityText);

-- Advanced (per toast type overrides)
-- Numeric editbox bound to config[key] (whole numbers >= 0)
local function NumberBox(parent, key, label, where, y, width, maxLetters)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	Place(fs, parent, where, nil, y);
	fs:SetText(label);
	local eb = CreateFrame("EditBox", "PrettyLootAlertOption_" .. key, parent, "InputBoxTemplate");
	eb:SetSize(width or 60, 18);
	eb:SetPoint("LEFT", fs, "RIGHT", 10, 0);
	eb:SetAutoFocus(false);
	eb:SetMaxLetters(maxLetters or 7);
	eb:SetNumeric(true);
	eb:SetJustifyH("CENTER");
	local function Commit()
		local v = floor(tonumber(eb:GetText()) or 0);
		if v < 0 then v = 0; end
		config[key] = v;
		eb:SetText(tostring(v));
	end
	eb:SetScript("OnEnterPressed", function() Commit(); eb:ClearFocus(); end);
	-- Escape throws the typing away: restore the saved value before focus loss would commit it
	eb:SetScript("OnEscapePressed", function() eb:SetText(tostring(tonumber(config[key]) or 0)); eb:ClearFocus(); end);
	eb:SetScript("OnEditFocusLost", function() Commit(); end);
	local widget = { frame = eb };
	widget.refresh = function() eb:SetText(tostring(tonumber(config[key]) or 0)); end
	widget.setEnabled = function(enabled)
		if enabled then eb:EnableMouse(true); eb:SetAlpha(1); fs:SetTextColor(1, 1, 1);
		else eb:ClearFocus(); eb:EnableMouse(false); eb:SetAlpha(0.4); fs:SetTextColor(0.5, 0.5, 0.5); end
	end
	table.insert(widgets, widget);
	return widget;
end

-- Gold/silver/copper editboxes bound to one copper value in config[key]
local function MoneyBox(parent, key, label, where, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	Place(fs, parent, where, nil, y);
	fs:SetText(label);
	local parts = {
		{ suffix = "g", mult = 10000, width = 44, letters = 5 },
		{ suffix = "s", mult = 100, width = 26, letters = 2 },
		{ suffix = "c", mult = 1, width = 26, letters = 2 },
	};
	local boxes, labels = {}, {};
	local function Commit()
		local total = 0;
		for i, part in ipairs(parts) do
			total = total + floor(tonumber(boxes[i]:GetText()) or 0) * part.mult;
		end
		if total < 0 then total = 0; end
		config[key] = total;
	end
	local function Show()
		local v = tonumber(config[key]) or 0;
		boxes[1]:SetText(tostring(floor(v / 10000)));
		boxes[2]:SetText(tostring(floor((v - floor(v / 10000) * 10000) / 100)));
		boxes[3]:SetText(tostring(v - floor(v / 100) * 100));
	end
	local prev;
	for i, part in ipairs(parts) do
		local eb = CreateFrame("EditBox", "PrettyLootAlertOption_" .. key .. part.suffix, parent, "InputBoxTemplate");
		eb:SetSize(part.width, 18);
		if prev then eb:SetPoint("LEFT", prev, "RIGHT", 14, 0);
		else eb:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 6, -4); end
		eb:SetAutoFocus(false);
		eb:SetMaxLetters(part.letters);
		eb:SetNumeric(true);
		eb:SetJustifyH("CENTER");
		eb:SetScript("OnEnterPressed", function() Commit(); Show(); eb:ClearFocus(); end);
		-- Escape throws the typing away: Show() restores all three boxes before focus loss commits
		eb:SetScript("OnEscapePressed", function() Show(); eb:ClearFocus(); end);
		eb:SetScript("OnEditFocusLost", function() Commit(); Show(); end);
		local suffix = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
		suffix:SetPoint("LEFT", eb, "RIGHT", 2, 0);
		suffix:SetText(part.suffix);
		boxes[i], labels[i] = eb, suffix;
		prev = suffix;
	end
	local widget = { frame = boxes[1] };
	widget.refresh = Show;
	widget.setEnabled = function(enabled)
		local c = enabled and 1 or 0.5;
		fs:SetTextColor(c, c, c);
		for i, eb in ipairs(boxes) do
			if not enabled then eb:ClearFocus(); end
			eb:EnableMouse(enabled); eb:SetAlpha(enabled and 1 or 0.4);
			labels[i]:SetTextColor(c, c, c);
		end
	end
	table.insert(widgets, widget);
	return widget;
end

local advWidgets = {};       -- every widget that depends on the global Advanced switch
local advQuality = {};       -- cat -> {override, ignore, low, max}
local advSound = {};         -- cat -> {override, min}
local function UpdateAdvancedEnabled()
	local on = config.adv_enabled and true or false;
	for _, w in ipairs(advWidgets) do w.setEnabled(on); end
	for cat, q in pairs(advQuality) do
		local override = on and config["adv_" .. cat .. "_qoverride"];
		q.ignore.setEnabled(override and true or false);
		local sliders = override and not config["adv_" .. cat .. "_ignore"];
		q.low.setEnabled(sliders and true or false);
		q.max.setEnabled(sliders and true or false);
	end
	for cat, sq in pairs(advSound) do
		local sound = on and config["adv_" .. cat .. "_sound"];
		sq.override.setEnabled(sound and true or false);
		sq.min.setEnabled((sound and config["adv_" .. cat .. "_soundq"]) and true or false);
	end
end

-- first time Advanced is switched on, start every override from the current main options
local function SeedAdvanced()
	if config.adv_initialized then return; end
	config.adv_initialized = true;
	for _, cat in ipairs(ADV_TYPES) do
		config["adv_" .. cat .. "_sound"] = config.sound and true or false;
		config["adv_" .. cat .. "_anims"] = config.anims and true or false;
		if ADV_QUALITY_TYPES[cat] then
			config["adv_" .. cat .. "_ignore"] = config.ignore_level and true or false;
			config["adv_" .. cat .. "_low"] = config.low_level;
			config["adv_" .. cat .. "_max"] = config.max_level;
		end
	end
end

local RefreshAll;  -- defined once every widget exists
CheckBox(advancedPage, "adv_enabled", L.OPT_ADV_ENABLE, "left", -40, function()
	if config.adv_enabled then SeedAdvanced(); end
	RefreshAll();
end);

local advNote = advancedPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
advNote:SetPoint("TOPLEFT", advancedPage, "TOPLEFT", 20, -70);
advNote:SetPoint("RIGHT", advancedPage, "RIGHT", -16, 0);
advNote:SetHeight(28);
advNote:SetJustifyH("LEFT");
advNote:SetJustifyV("TOP");
advNote:SetText(L.OPT_ADV_NOTE);

-- the page is taller than the options window, so it scrolls
local advScroll = CreateFrame("ScrollFrame", "PrettyLootAlertAdvancedScroll", advancedPage, "UIPanelScrollFrameTemplate");
advScroll:SetPoint("TOPLEFT", advancedPage, "TOPLEFT", 4, -106);
advScroll:SetPoint("BOTTOMRIGHT", advancedPage, "BOTTOMRIGHT", -28, 10);
local adv = CreateFrame("Frame", "PrettyLootAlertAdvancedContent", advScroll);
adv:SetWidth(360);  -- the height is set once the sections are laid out
advScroll:SetScrollChild(adv);
advScroll:EnableMouseWheel(true);
advScroll:SetScript("OnMouseWheel", function(_, delta)
	local maxScroll = advScroll:GetVerticalScrollRange() or 0;
	local v = (advScroll:GetVerticalScroll() or 0) - delta * 40;
	if v < 0 then v = 0; elseif v > maxScroll then v = maxScroll; end
	advScroll:SetVerticalScroll(v);
	local bar = _G["PrettyLootAlertAdvancedScrollScrollBar"];
	if bar then bar:SetValue(v); end
end);
local function FitContent()
	local w = advScroll:GetWidth();
	if w and w > 100 then adv:SetWidth(w); end
end
advScroll:SetScript("OnSizeChanged", FitContent);
advScroll:SetScript("OnShow", FitContent);

-- one section per toast type, in a single column
local function Divider(y)
	local line = adv:CreateTexture(nil, "ARTWORK");
	line:SetColorTexture(1, 1, 1, 0.12);
	line:SetHeight(1);
	line:SetPoint("TOPLEFT", adv, "TOPLEFT", 12, y);
	line:SetPoint("TOPRIGHT", adv, "TOPRIGHT", -8, y);
end

-- header, sound and animations; returns the y below the last row
local function AdvEffects(cat, heading, y)
	Header(adv, heading, "left", y);
	table.insert(advWidgets, CheckBox(adv, "adv_" .. cat .. "_sound", L.OPT_SOUNDS, "indent", y - 18, UpdateAdvancedEnabled));
	table.insert(advWidgets, CheckBox(adv, "adv_" .. cat .. "_anims", L.OPT_ANIMS, "indent", y - 44));
	return y - 74;
end

-- "Play sound from": only toasts of the chosen quality or better play a sound
local function AdvSound(cat, y)
	local sq = {};
	sq.override = CheckBox(adv, "adv_" .. cat .. "_soundq", L.OPT_SOUND_OVERRIDE, "indent", y, UpdateAdvancedEnabled);
	sq.min = Slider(adv, "adv_" .. cat .. "_soundmin", L.OPT_SOUND_FROM, 0, MAX_QUALITY, 1, "indent", y - 58, QualityText);
	advSound[cat] = sq;
	return y - 92;
end

local function AdvQuality(cat, y)
	local q = {};
	q.override = CheckBox(adv, "adv_" .. cat .. "_qoverride", L.OPT_QOVERRIDE, "indent", y, UpdateAdvancedEnabled);
	table.insert(advWidgets, q.override);
	q.ignore = CheckBox(adv, "adv_" .. cat .. "_ignore", L.OPT_EVERY_QUALITY, "indent", y - 26, UpdateAdvancedEnabled);
	-- slider titles sit ~15px above the bar and the Poor/Artifact labels ~15px below it
	q.low = Slider(adv, "adv_" .. cat .. "_low", L.OPT_MIN_LOW, 0, MAX_QUALITY, 1, "indent", y - 84, QualityText);
	q.max = Slider(adv, "adv_" .. cat .. "_max", L.OPT_MIN_MAX, 0, MAX_QUALITY, 1, "indent", y - 136, QualityText);
	advQuality[cat] = q;
	return y - 170;
end

local y = -8;
local first = true;
local function Section()
	if not first then Divider(y + 12); end
	first = false;
end
for _, item in ipairs({ { "looting", L.OPT_LOOTING }, { "creating", L.OPT_CRAFTING }, { "rolling", L.OPT_ROLLS } }) do
	Section();
	y = AdvEffects(item[1], item[2], y);
	y = AdvSound(item[1], y);
	y = AdvQuality(item[1], y) - 24;
end

Section();
y = AdvEffects("money", L.OPT_MONEY, y);
table.insert(advWidgets, MoneyBox(adv, "adv_money_min", L.OPT_MONEY_MIN, "indent", y - 4));
y = y - 66;

Section();
y = AdvEffects("recipes", L.OPT_RECIPES, y) - 16;

Section();
y = AdvEffects("honor", HONOR or "Honor", y);
table.insert(advWidgets, NumberBox(adv, "adv_honor_min", L.OPT_HONOR_MIN, "indent", y - 6, 50, 6));
y = y - 40;
adv:SetHeight(-y);

RefreshAll = function()
	updating = true;
	for _, widget in ipairs(widgets) do widget.refresh(); end
	updating = false;
	UpdateQualityEnabled();
	UpdateAdvancedEnabled();
	UpdateUnlockText();
end
private.RefreshOptions = function()
	local visible = panel:IsVisible();
	for _, page in ipairs(pages) do if page:IsVisible() then visible = true; end end
	if visible then RefreshAll(); end
end

-- Every change is saved the moment it's made; Okay, Cancel and Escape just close the window
panel.refresh = RefreshAll;
panel.okay = function() end
panel.cancel = function() end
panel.default = function()
	ApplyDefaults(config, true);
	OnSettingChanged("point_x");
	RefreshAll();
end
panel:SetScript("OnShow", RefreshAll);

-- every page shares the same settings and callbacks
for _, page in ipairs(pages) do
	page.refresh, page.okay, page.cancel, page.default = panel.refresh, panel.okay, panel.cancel, panel.default;
	page:SetScript("OnShow", RefreshAll);
end

InterfaceOptions_AddCategory(panel);
for _, page in ipairs(pages) do InterfaceOptions_AddCategory(page); end

local function OpenOptions()
	InterfaceOptionsFrame_OpenToCategory(panel);
end

-- Test toasts
-- One toast per list, shown in this order with a random item ID from each; edit freely.
local TEST_TOASTS = {
	{ 19019, 17182, 22589, 18563, 18564 },   -- legendary
	{ 18832, 17076, 19364, 16922 },          -- epic
	{ 11815, 13965, 12930, 20130 },          -- rare
};
local TEST_MONEY = 12345;

private.ShowTestToasts = function()
	for _, ids in ipairs(TEST_TOASTS) do
		-- forced past the quality filter; an uncached item shows once it loads
		private.AddItemToast("item:" .. ids[math.random(1, #ids)]);
	end
	private.AddMoneyAlert(TEST_MONEY, true);
end

-- Slash commands
SLASH_PRETTYLOOTALERT1 = "/pla";
SLASH_PRETTYLOOTALERT2 = "/prettyloot";
SlashCmdList["PRETTYLOOTALERT"] = function(msg)
	msg = strtrim(msg or ""):lower();
	if msg == "" or msg == "config" or msg == "options" then
		OpenOptions();
	elseif msg == "test" then
		private.ShowTestToasts();
	elseif msg == "unlock" or msg == "lock" then
		private.ToggleAnchor(msg == "unlock");
		UpdateUnlockText();
	elseif msg == "reset" then
		panel.default();
		private.Print(L.MSG_RESET);
	else
		private.Print(L.MSG_USAGE);
	end
end