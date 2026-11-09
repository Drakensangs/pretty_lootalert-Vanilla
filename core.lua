local _, private = ...;
local L = private.L;
local config = private.config;
local MatchFormat = private.MatchFormat;
local GetItemData = private.GetItemData;
local GetItemID = private.GetItemID;
local GetChatLink = private.GetChatLink;
local GetLinkName = private.GetLinkName;
local ResolveItemLink = private.ResolveItemLink;

local pairs = pairs;
local ipairs = ipairs;
local next = next;
local type = type;
local tonumber = tonumber;
local tostring = tostring;
local find = string.find;
local lower = string.lower;
local match = string.match;
local tInsert = table.insert;
local tRemove = table.remove;
local wipe = table.wipe;
local GetTime = GetTime;
local GameTooltip = GameTooltip;

local MAX_BUTTONS = 8;

-- Assets
local assets = [[Interface\AddOns\pretty_lootalert\assets\]];
local RECIPE_FALLBACK_ICON = [[Interface\Icons\INV_Scroll_04]];
local ICON_CROP = 0.07;       -- trims the bevel baked into square icons
local TEX_COMMON_BORDER = assets .. "CommonIconBorder";
local TEX_LOOT_ATLAS = assets .. "LootToastAtlas";
local SOUNDKIT = {
	UI_EPICLOOT_TOAST = assets .. "ui_epicloot_toast_01.ogg",
	UI_GARRISON_FOLLOWER_LEARN_TRAIT = assets .. "ui_garrison_follower_trait_learned_02.ogg",
	UI_LEGENDARY_LOOT_TOAST = assets .. "ui_legendary_item_toast.ogg",
	UI_RAID_LOOT_TOAST_LESSER_ITEM_WON = assets .. "ui_loot_toast_lesser_item_won_01.ogg",
};

-- Constants (ClassicAPI enums)
local LE_ITEM_QUALITY_COMMON = LE_ITEM_QUALITY_COMMON;
local LE_ITEM_QUALITY_UNCOMMON = LE_ITEM_QUALITY_UNCOMMON;
local LE_ITEM_QUALITY_RARE = LE_ITEM_QUALITY_RARE;
local LE_ITEM_QUALITY_EPIC = LE_ITEM_QUALITY_EPIC;
local LE_ITEM_QUALITY_LEGENDARY = LE_ITEM_QUALITY_LEGENDARY;
local LE_ITEM_QUALITY_ARTIFACT = LE_ITEM_QUALITY_ARTIFACT;
local ITEM_CLASS_RECIPE = Enum.ItemClass.Recipe;

local LOOT_ROLL_TYPE_NEED = 1;
local LOOT_ROLL_TYPE_GREED = 2;
local RIDING_SKILL = 762;

local LOOT_BORDER_BY_QUALITY = {
	[LE_ITEM_QUALITY_UNCOMMON] = {0.34082, 0.397461, 0.53125, 0.644531},
	[LE_ITEM_QUALITY_RARE] = {0.272461, 0.329102, 0.785156, 0.898438},
	[LE_ITEM_QUALITY_EPIC] = {0.34082, 0.397461, 0.882812, 0.996094},
	[LE_ITEM_QUALITY_LEGENDARY] = {0.34082, 0.397461, 0.765625, 0.878906},
	[LE_ITEM_QUALITY_ARTIFACT] = {0.272461, 0.329102, 0.667969, 0.78125},
};
-- item name colours; ITEM_QUALITY_COLORS has no Artifact entry on this client
local QUALITY_RGB = {
	[0] = {0.62, 0.62, 0.62}, [1] = {1, 1, 1}, [2] = {0.12, 1, 0},
	[3] = {0, 0.44, 0.87}, [4] = {0.64, 0.21, 0.93}, [5] = {1, 0.5, 0}, [6] = {0.9, 0.8, 0.5},
};
local function GetQualityRGB(quality)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality];
	if c and c.r then return c.r, c.g, c.b; end
	c = QUALITY_RGB[quality] or QUALITY_RGB[1];
	return c[1], c[2], c[3];
end

local HONOR_BACKGROUND_TCOORDS = {
	["Alliance"] = {277, 113, 0.001953, 0.542969, 0.460938, 0.902344},
	["Horde"] = {281, 115, 0.001953, 0.550781, 0.003906, 0.453125},
};
local function GetPlayerFaction() return UnitFactionGroup("player") or "Alliance"; end

-- Professions: keyed by SkillLine ID, named by the client's own SkillLine data
-- Each profession's base spell; its icon comes from the client (SpellIcon.dbc).
-- Any rank shares the same icon, so the Apprentice spell is enough.
local PROFESSION_SPELL = {
	ALCHEMY = 2259, BLACKSMITHING = 2018, ENCHANTING = 7411, ENGINEERING = 4036, LEATHERWORKING = 2108,
	TAILORING = 3908, COOKING = 2550, FIRST_AID = 3273, FISHING = 7620, MINING = 2575, POISONS = 2842,
};
-- used only if the client can't resolve a spell icon
local PROFESSION_ICON_FALLBACK = {
	ALCHEMY = [[Interface\Icons\Trade_Alchemy]], BLACKSMITHING = [[Interface\Icons\Trade_BlackSmithing]],
	ENCHANTING = [[Interface\Icons\Trade_Engraving]], ENGINEERING = [[Interface\Icons\Trade_Engineering]],
	LEATHERWORKING = [[Interface\Icons\INV_Misc_ArmorKit_17]], TAILORING = [[Interface\Icons\Trade_Tailoring]],
	COOKING = [[Interface\Icons\INV_Misc_Food_15]], FIRST_AID = [[Interface\Icons\Spell_Holy_SealOfSacrifice]],
	FISHING = [[Interface\Icons\Trade_Fishing]], MINING = [[Interface\Icons\Trade_Mining]],
	POISONS = [[Interface\Icons\Trade_BrewPoison]],
};
local professionIconCache = {};
local function ProfessionIcon(key)
	if not key then return; end
	local icon = professionIconCache[key];
	if icon == nil then
		local spell = PROFESSION_SPELL[key];
		icon = (spell and C_Spell.GetSpellTexture(spell)) or PROFESSION_ICON_FALLBACK[key] or false;
		professionIconCache[key] = icon;
	end
	return icon or nil;
end
local PROFESSION_SKILL = {
	ALCHEMY = 171, BLACKSMITHING = 164, ENCHANTING = 333, ENGINEERING = 202, LEATHERWORKING = 165,
	TAILORING = 197, COOKING = 185, FIRST_AID = 129, FISHING = 356, MINING = 186, POISONS = 40,
};
-- Recipe item subclass -> profession (Enum.ItemClass.Recipe subclasses)
local RECIPE_SUBCLASS = {
	[1] = "LEATHERWORKING", [2] = "TAILORING", [3] = "ENGINEERING", [4] = "BLACKSMITHING", [5] = "COOKING",
	[6] = "ALCHEMY", [7] = "FIRST_AID", [8] = "ENCHANTING", [9] = "FISHING",
};
-- professions that teach recipes, for the "only one profession" guess
-- (Mining teaches smelting, Poisons is the rogue skill)
local RECIPE_PROFESSIONS = {
	"ALCHEMY", "BLACKSMITHING", "ENCHANTING", "ENGINEERING", "LEATHERWORKING", "TAILORING", "COOKING", "FIRST_AID",
	"MINING", "POISONS",
};
local PROFESSION_BY_SKILL = {};
for key, skill in pairs(PROFESSION_SKILL) do PROFESSION_BY_SKILL[skill] = key; end

-- localized skill line name (trade skill, craft and trainer windows) -> profession key;
-- the names come from the client's SkillLine data, so they match in every language
local professionByName;
local function ProfessionKey(name)
	if not name then return; end
	if not professionByName then
		professionByName = {};
		for key, skill in pairs(PROFESSION_SKILL) do
			local localized = C_SpellBook.GetSkillLineName(skill);
			if localized then professionByName[localized] = key; end
		end
	end
	return professionByName[name];
end

-- Chat formats (1.12.1 GlobalStrings)
local LOOT_FORMATS = {
	-- {format, kind, hasCount, isPushed}; the multiple-count form of each must come first
	{LOOT_ITEM_CREATED_SELF_MULTIPLE, "created", true},
	{LOOT_ITEM_CREATED_SELF, "created"},
	{LOOT_ITEM_SELF_MULTIPLE, "received", true},
	{LOOT_ITEM_SELF, "received"},
	{LOOT_ITEM_PUSHED_SELF_MULTIPLE, "received", true, true},
	{LOOT_ITEM_PUSHED_SELF, "received", nil, true},
};
local MONEY_FORMATS = { YOU_LOOT_MONEY or false, LOOT_MONEY_SPLIT or false };  -- false: missing in this locale
local GOLD = string.gsub(GOLD_AMOUNT, "%%d", "(%%d+)");
local SILVER = string.gsub(SILVER_AMOUNT, "%%d", "(%%d+)");
local COPPER = string.gsub(COPPER_AMOUNT, "%%d", "(%%d+)");

-- State
-- Stamps count copies, so two copies of one item can be rolled on at once; toasts are
-- matched to them by item ID, oldest first. Each list: itemID -> {expiry, ...}
local pendingRolls = {};      -- open group-loot rolls
local expectedReceive = {};   -- "won" toasts that will absorb the next "You receive loot" line
local recentReceive = {};     -- "You receive" toasts shown for a rolled item before its result came
local lateReceive = {};       -- "You receive loot" lines whose roll result was late (toast or not)
local handledRolls = {};      -- loot history rollID -> time, so a result is handled once
local ROLL_GRACE = 15;        -- seconds a roll may outlast its timer before it counts as stale
local ROLL_DEFAULT_TIME = 60; -- roll timer when START_LOOT_ROLL gives none
local RECEIVE_EXPIRE = 15;
local RECENT_RECEIVE_EXPIRE = 30;
local ROLL_RESULT_WAIT = 4;   -- how long a "You receive" line for a rolled item waits for the result
local HANDLED_EXPIRE = 300;

-- Solo coin loot prints no chat line, so money gained while looting is used instead.
-- In a group only corpse and chest coins are shared (and announced); coins from an
-- opened bag item (sack, clam) are not, so they count as solo loot.
local lootOpen = false;
local lootClosedAt;
local lootHadCoin = false;    -- the open (or just closed) loot window held coins
local lootWalkActive = false; -- a C_Loot.LootAllCorpses walk is running
local LOOT_GRACE = 1.5;
local itemOpenedAt;           -- an openable bag item was used
local lootFromItem = false;   -- the current (or just closed) loot window is that item's
local ITEM_OPEN_WAIT = 2;
-- vendor purchases print "You receive item: ..." like pushed loot
local merchantOpen = false;
local merchantClosedAt;
-- items a quest hands out on accept print the same line; they get no toast
local questAcceptClickedAt;   -- AcceptQuest() sent, server reply pending
local questAcceptedAt;        -- QUEST_ACCEPTED
local QUEST_ACCEPT_WAIT = 5;
local lastMoney;

-- recipe item the player used last: {link, name, quality, profession, taught, expires}
local lastRecipe;
local RECIPE_EXPIRE = 30;
local LEARN_SETTLE = 0.5;     -- lets the spellbook and profession windows catch up with a learn message

local alertQueue = {};
local alertButtons = {};      -- created on first use
local shownButtons = {};      -- oldest first: the oldest sits on the anchor, newer ones stack above
local waitingForItem = {};    -- itemID -> toasts waiting for the item's data

local function FormatMoney(money)
	return GetMoneyString(money, true);
end

-- Settings
-- The Advanced value for a toast type ("looting", "creating", "rolling", "money",
-- "recipes", "honor"), or nil while the Advanced options are off.
local function AdvValue(cat, key)
	if config.adv_enabled and cat then return config["adv_" .. cat .. "_" .. key]; end
end

local function GetToastEffect(cat, key)
	local v = AdvValue(cat, key);
	if v ~= nil then return v; end
	return config[key];
end

-- Advanced "Play sound from": true when this quality may play its sound
local function SoundQualityAllowed(cat, quality)
	if AdvValue(cat, "soundq") then
		return (tonumber(quality) or 0) >= (tonumber(AdvValue(cat, "soundmin")) or 0);
	end
	return true;
end

-- ignoreFilter, minimum quality below max level, minimum quality at max level
local function GetQualityFilter(cat)
	if AdvValue(cat, "qoverride") then
		return AdvValue(cat, "ignore"), AdvValue(cat, "low"), AdvValue(cat, "max");
	end
	return config.ignore_level, config.low_level, config.max_level;
end

-- minimum money (copper) or honor for a toast; 0 shows every gain
local function GetMinimum(cat)
	local min = AdvValue(cat, "min");  -- may be no value at all, and tonumber() with no argument raises an error
	return tonumber(min) or 0;
end

local function GetScale()
	local scale = tonumber(config.scale) or 1;
	if scale <= 0 then scale = 1; end
	return scale;
end

local function NumButtons()
	local n = tonumber(config.numbuttons) or 4;
	if n < 1 then n = 1; elseif n > MAX_BUTTONS then n = MAX_BUTTONS; end
	return n;
end

-- Queue
-- true when the quality filter of category `cat` lets this quality through
local function PassesQualityFilter(quality, cat)
	local ignoreFilter, lowLevel, maxLevel = GetQualityFilter(cat);
	if ignoreFilter then return true; end
	local minQuality = (UnitLevel("player") < GetMaxPlayerLevel()) and lowLevel or maxLevel;
	return quality >= (tonumber(minQuality) or 0);
end

-- Queues a toast. `data.force` skips the quality filter. Returns true when queued.
local function AddAlert(data)
	data.quality = tonumber(data.quality) or 0;
	if not data.force and not PassesQualityFilter(data.quality, data.cat) then return; end
	tInsert(alertQueue, data);
	-- wake the update frame (it sleeps while the queue is empty or every button is busy)
	private.updateFrame:Show();
	return true;
end

local CreateAlertButton;  -- defined with the toast layout below

local STRATAS = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
	FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true };
local function GetStrata()
	return STRATAS[config.frame_strata] and config.frame_strata or "HIGH";
end

local function GetFreeButton()
	if #alertQueue == 0 then return; end
	for i = 1, NumButtons() do
		local button = alertButtons[i] or CreateAlertButton(i);
		if not button:IsShown() then
			button.data = tRemove(alertQueue, 1);
			return button;
		end
	end
end

-- saved position, kept inside the options sliders' range
local POSITION_LIMIT = 1000;
local function ClampPosition(v)
	v = tonumber(v) or 0;
	if v < -POSITION_LIMIT then return -POSITION_LIMIT; elseif v > POSITION_LIMIT then return POSITION_LIMIT; end
	return v;
end
private.ClampPosition = ClampPosition;

local function AdjustAnchors()
	-- SetPoint offsets are in the toast's own (scaled) units, so the unscaled anchor
	-- position is divided by the scale; the gap between toasts scales with them
	local scale = GetScale();
	local previousButton;
	for i = 1, #shownButtons do
		local button = shownButtons[i];
		button:SetScale(scale);
		button:ClearAllPoints();
		if not previousButton then
			button:SetPoint("CENTER", UIParent, "CENTER", ClampPosition(config.point_x) / scale, ClampPosition(config.point_y) / scale);
		else
			-- offset_x is the vertical gap between toasts (name kept for saved settings)
			button:SetPoint("BOTTOM", previousButton, "TOP", 0, config.offset_x or 4);
		end
		previousButton = button;
	end
end
private.AdjustAnchors = AdjustAnchors;

-- Per-copy stamp lists: itemID -> {expiry, ...}, oldest first
local function PushStamp(t, id, lifetime)
	local list = t[id];
	if not list then list = {}; t[id] = list; end
	tInsert(list, GetTime() + lifetime);
end
-- removes the oldest live stamp; true if there was one
local function PopStamp(t, id)
	local list = t[id];
	if not list then return false; end
	local now = GetTime();
	while #list > 0 do
		if tRemove(list, 1) >= now then
			if #list == 0 then t[id] = nil; end
			return true;
		end
	end
	t[id] = nil;
	return false;
end
local function HasStamp(t, id)
	local list = t[id];
	if not list then return false; end
	local now = GetTime();
	for i = 1, #list do
		if list[i] >= now then return true; end
	end
	return false;
end

local lastPrune = 0;
local STAMP_LISTS = { pendingRolls, expectedReceive, recentReceive, lateReceive };
local function PruneRollState()
	local now = GetTime();
	if (now - lastPrune) < 60 then return; end
	lastPrune = now;
	for _, t in ipairs(STAMP_LISTS) do
		for id, list in pairs(t) do
			for i = #list, 1, -1 do
				if list[i] < now then tRemove(list, i); end
			end
			if #list == 0 then t[id] = nil; end
		end
	end
	for rollID, stamp in pairs(handledRolls) do
		if (now - stamp) > HANDLED_EXPIRE then handledRolls[rollID] = nil; end
	end
end

-- Item toasts
local petItems = {};
for _, id in ipairs(private.PetDB) do petItems[id] = true; end

-- mount items: itemID -> true/false, filled on first sight
local mountLookup = {};
local function IsMountItem(id)
	local known = mountLookup[id];
	if known ~= nil then return known; end
	local itemData = C_Item.GetItemDataByID(id);
	if not itemData then return false; end  -- not cached yet: don't remember a guess
	known = itemData.requiredSkill == RIDING_SKILL;
	mountLookup[id] = known;
	return known;
end

-- A toast is one table, from the request through the queue to its button.
-- kind: "received", "won", "created", "money", "honor" or "recipe"
-- cat: the Advanced options type it uses ("looting", "creating", "rolling", ...)
local function NewItemToast(link, count, kind, cat)
	return { link = link, itemID = GetItemID(link), count = count, kind = kind, cat = cat };
end

local QueueLoot;  -- defined with the roll handling below

-- A "won" toast that will never show must not keep absorbing its item's "You receive loot"
-- line: give back its stamp, or show the line it already absorbed.
local function ToastRejected(data)
	if not data.stamped then return; end
	data.stamped = nil;
	if data.merged then
		QueueLoot(data.merged.link, data.merged.count);
	else
		PopStamp(expectedReceive, data.itemID);
	end
end

local OnItemLoaded;

-- Fills in an item toast and queues it; an uncached item waits for its data first.
-- `loaded` is set once the data has arrived.
local function QueueItemToast(data, loaded)
	local id = data.itemID;
	if not id then return; end
	local baseName, baseLink, quality, _, _, _, texture = GetItemData(id);
	if not baseName then
		if loaded then return ToastRejected(data); end
		local list = waitingForItem[id];
		if list then
			tInsert(list, data);
		else
			waitingForItem[id] = { data };
			Item:CreateFromItemID(id):ContinueOnItemLoad(function(_, success) OnItemLoaded(id, success); end);
		end
		return;
	end

	local link, name = ResolveItemLink(data.link, baseName, baseLink);
	local toast = "defaulttoast";
	if quality >= LE_ITEM_QUALITY_LEGENDARY then
		toast = "legendarytoast";
	elseif quality < LE_ITEM_QUALITY_COMMON then
		toast = "commontoast";  -- the small grey toast, for Poor items
	end
	if IsMountItem(id) then toast = "mounttoast"; end
	if petItems[id] then toast = "pettoast"; end
	data.name, data.link, data.quality, data.texture, data.toast = name, link, quality, texture, toast;

	if not AddAlert(data) then return ToastRejected(data); end
	-- a late "You receive" toast is remembered, so the roll result doesn't show the copy twice
	if data.late then
		PushStamp(recentReceive, id, RECENT_RECEIVE_EXPIRE);
		data.recentStamped = true;
	end
end

-- the item's data arrived, or (`success` nil) it can't be loaded
OnItemLoaded = function(itemID, success)
	local list = waitingForItem[itemID];
	waitingForItem[itemID] = nil;
	if not list then return; end
	for i = 1, #list do
		if success then QueueItemToast(list[i], true); else ToastRejected(list[i]); end
	end
end

-- Forced test toast (options panel)
private.AddItemToast = function(link)
	local data = NewItemToast(link, nil, "received", "looting");
	data.force = true;
	QueueItemToast(data);
end

-- The first toast for this item and kind that passes `accept`, waiting, queued or shown.
-- Returns the toast and, when it is on screen, its button.
local function FindToast(id, kind, accept)
	local waiting = waitingForItem[id];
	if waiting then
		for _, data in ipairs(waiting) do
			if data.kind == kind and (not accept or accept(data)) then return data; end
		end
	end
	for _, data in ipairs(alertQueue) do
		if data.itemID == id and data.kind == kind and (not accept or accept(data)) then return data; end
	end
	for _, button in ipairs(alertButtons) do
		local data = button:IsShown() and button.data;
		if data and data.itemID == id and data.kind == kind and (not accept or accept(data)) then
			return data, button;
		end
	end
end

local UpdateButtonRoll, UpdateButtonItem;  -- refresh a toast on screen; defined with the layout

local function IsLate(data) return data.late; end

-- Settles a late "received" toast for this item (its line came before the result) as the
-- copy we won: it becomes the "won" toast if the rolling quality filter allows it.
local function PatchWonToast(id, rollType, roll)
	local data, button = FindToast(id, "received", IsLate);
	if not data then return; end
	if data.recentStamped then PopStamp(recentReceive, id); end
	PopStamp(lateReceive, id);
	data.late, data.recentStamped = nil, nil;
	-- already queued under the looting filter (a waiting one is filtered once it loads)
	if data.quality and not PassesQualityFilter(data.quality, "rolling") then return true; end
	data.kind, data.cat, data.rollType, data.roll = "won", "rolling", rollType, roll;
	if button then UpdateButtonRoll(button); end
	return true;
end

local function NotMerged(data) return not data.merged; end

-- A "won" toast came before its "You receive loot" line: take the line's chat link
-- (it always carries the random suffix) and count, and remember the line.
local function UpdateWonToastLink(id, chatLink, count)
	local data, button = FindToast(id, "won", NotMerged);
	if not data then return; end
	data.merged = { link = chatLink, count = count };
	local full = GetChatLink(chatLink);
	if full then
		data.link = full;
		-- a waiting toast takes its name from the link once it loads
		if data.name then data.name = GetLinkName(full) or data.name; end
	end
	if count then data.count = count; end
	if button then UpdateButtonItem(button); end
end

-- Rolls (results come from ClassicAPI's loot history)
-- we won one copy of this item
local function MarkWon(id, rollType, roll, link)
	PopStamp(pendingRolls, id);
	if not config.rolling then return; end
	-- the "You receive loot" line came first: upgrade that toast
	if PatchWonToast(id, rollType, roll) then return; end
	-- its "You receive" toast was shown and is gone already: don't show the copy twice
	if PopStamp(recentReceive, id) then
		PopStamp(lateReceive, id);
		return;
	end
	-- no toast for this copy yet; unless its line already came, the toast absorbs it
	local data = NewItemToast(link, nil, "won", "rolling");
	data.rollType, data.roll = rollType, roll;
	if not PopStamp(lateReceive, id) then
		PushStamp(expectedReceive, id, RECEIVE_EXPIRE);
		data.stamped = true;
	end
	QueueItemToast(data);
end

-- `late`: the line for a rolled item whose result has not come
QueueLoot = function(link, count, late)
	if not config.looting then return; end
	local data = NewItemToast(link, count, "received", "looting");
	data.late = late;
	QueueItemToast(data);
end

-- a "You receive loot" line for one copy of an item
local function HandleReceived(id, link, count)
	PruneRollState();
	if PopStamp(expectedReceive, id) then
		UpdateWonToastLink(id, link, count);
		return;
	end
	if HasStamp(pendingRolls, id) then
		-- we rolled on this item and the result has not come yet: wait for it briefly
		C_Timer.After(ROLL_RESULT_WAIT, function()
			if PopStamp(expectedReceive, id) then
				UpdateWonToastLink(id, link, count);
			elseif not HasStamp(pendingRolls, id) then
				QueueLoot(link, count);  -- settled without a "won" toast (rolling toasts off)
			else
				PushStamp(lateReceive, id, RECENT_RECEIVE_EXPIRE);
				QueueLoot(link, count, true);
			end
		end);
		return;
	end
	QueueLoot(link, count);
end

local function HandleRollComplete(itemIndex)
	PruneRollState();
	local rollID, link, numPlayers, _, winnerIdx = C_LootHistory.GetItem(itemIndex);
	local id = GetItemID(link);
	if not id then return; end
	if rollID then
		if handledRolls[rollID] then return; end
		handledRolls[rollID] = GetTime();
	end
	for i = 1, numPlayers or 0 do
		local _, _, rollType, roll, _, isMe = C_LootHistory.GetPlayerInfo(itemIndex, i);
		if isMe then
			if i == winnerIdx then
				MarkWon(id, rollType ~= 0 and rollType or nil, roll, link);
			else
				PopStamp(pendingRolls, id);
			end
			return;
		end
	end
	-- not our roll: leave our own open rolls of this item alone
end

local function HandleStartRoll(rollID, rollTime)
	local id = GetLootRollItemID(rollID);
	if not id then return; end
	local seconds = tonumber(rollTime) and (rollTime / 1000) or ROLL_DEFAULT_TIME;
	PushStamp(pendingRolls, id, seconds + ROLL_GRACE);
end

-- Loot and money
local function IsShopping()
	return merchantOpen or (merchantClosedAt ~= nil and (GetTime() - merchantClosedAt) < LOOT_GRACE);
end

-- The item can arrive before QUEST_ACCEPTED (which waits on uncached quest data) or just
-- after it, so both the accept click and the event open a window.
local function IsQuestHandout()
	local now = GetTime();
	if questAcceptClickedAt and (now - questAcceptClickedAt) < QUEST_ACCEPT_WAIT then return true; end
	return questAcceptedAt ~= nil and (now - questAcceptedAt) < LOOT_GRACE;
end
local function QuestAcceptClicked() questAcceptClickedAt = GetTime(); end
hooksecurefunc("AcceptQuest", QuestAcceptClicked);
if ConfirmAcceptQuest then hooksecurefunc("ConfirmAcceptQuest", QuestAcceptClicked); end -- escort shares

local function HandleLootMessage(message)
	for _, entry in ipairs(LOOT_FORMATS) do
		local link, count = MatchFormat(message, entry[1]);
		if link then
			if not entry[3] then count = nil; end
			local id = GetItemID(link);
			if not id then return; end
			-- pushed items that arrive while a vendor window is open are purchases
			if entry[4] and (IsShopping() or IsQuestHandout()) then return; end
			if entry[2] == "created" then
				if config.creating then QueueItemToast(NewItemToast(link, count, "created", "creating")); end
			else
				HandleReceived(id, link, count);
			end
			return;
		end
	end
end

-- `force` skips the Advanced minimum (test toasts)
private.AddMoneyAlert = function(money, force)
	if not force and money < GetMinimum("money") then return; end
	AddAlert({ kind = "money", toast = "moneytoast", name = FormatMoney(money), money = money,
		quality = LE_ITEM_QUALITY_ARTIFACT, cat = "money", force = true });
end

local function HandleMoneyMessage(message)
	for _, fmt in ipairs(MONEY_FORMATS) do
		if MatchFormat(message, fmt) then
			local gold = tonumber(match(message, GOLD)) or 0;
			local silver = tonumber(match(message, SILVER)) or 0;
			local copper = tonumber(match(message, COPPER)) or 0;
			local money = copper + (silver * 100) + (gold * 10000);
			if money > 0 then private.AddMoneyAlert(money); end
			return;
		end
	end
end

-- C_Loot.IsScanInProgress() is true for ScanNearbyLoot (a peek that takes nothing) and
-- for LootAllCorpses (which loots), so the wrapper marks the real loot walks.
do
	local LootAllCorpses = C_Loot.LootAllCorpses;
	local function Track(ok, ...)
		if ok then lootWalkActive = true; lootFromItem = false; end
		return ok, ...;
	end
	C_Loot.LootAllCorpses = function(...) return Track(LootAllCorpses(...)); end
end

local function IsLooting()
	if lootOpen then return true; end
	-- the coin's PLAYER_MONEY can land just after the window closes; only a window
	-- that actually held coins gets that grace, and only for one gain
	if lootHadCoin and lootClosedAt and (GetTime() - lootClosedAt) < LOOT_GRACE then return true; end
	if lootWalkActive then
		if C_Loot.IsScanInProgress() then return true; end
		lootWalkActive = false;
	end
	return false;
end

-- unshared coin loot prints no chat line: show the money gained while looting
local function HandlePlayerMoney()
	local now = GetMoney();
	if lastMoney then
		local delta = now - lastMoney;
		if delta > 0 and IsLooting() then
			if not lootOpen and not lootWalkActive then lootHadCoin = false; end  -- grace used up
			if config.money and (lootFromItem or not IsInGroup()) then private.AddMoneyAlert(delta); end
		end
	end
	lastMoney = now;
end

-- Recipes
-- the item a use call refers to: bag + slot, a location table, an ID, a link or a name
local function UsedItemLink(item, slot)
	if slot then return GetContainerItemLink(item, slot); end
	if type(item) == "table" then
		if item.bagID and item.slotIndex then return GetContainerItemLink(item.bagID, item.slotIndex); end
		return;
	end
	local id = GetItemID(item);
	if id then return "item:" .. id; end
	if type(item) ~= "string" then return; end
	local wanted = lower(item);
	for bag = 0, NUM_BAG_SLOTS do
		for s = 1, GetContainerNumSlots(bag) do
			local slotID = C_Container.GetContainerItemID(bag, s);
			if slotID and lower(C_Item.GetItemNameByID(slotID) or "") == wanted then
				return "item:" .. slotID;
			end
		end
	end
end

-- remembers a used recipe item and the spells it teaches, so the "learned" toast gets
-- its profession, link and quality
local function RememberRecipe(link)
	if not link then return; end
	local name, baseLink, quality, _, _, _, _, classID, subclassID = GetItemData(link);
	if classID ~= ITEM_CLASS_RECIPE then return; end
	local profession = RECIPE_SUBCLASS[subclassID];
	local taught = {};
	local itemData = C_Item.GetItemDataByID(link);
	if itemData and itemData.spells then
		for _, spell in pairs(itemData.spells) do
			local spellName = GetSpellInfo(spell.id);
			if spellName then taught[spellName] = true; end
			if not profession then
				local _, skill = C_SpellBook.GetSpellSkillLine(spell.id);
				profession = skill and PROFESSION_BY_SKILL[skill];
			end
		end
	end
	if not profession then return; end  -- class books and the like
	lastRecipe = { link = GetChatLink(link) or baseLink, name = name, quality = quality, profession = profession,
		taught = next(taught) and taught, expires = GetTime() + RECIPE_EXPIRE };
end
-- a used item may be a recipe, or a sack or clam whose loot window is about to open
local function ItemUsed(link)
	if not link then return; end
	if config.recipes then RememberRecipe(link); end
	local itemData = C_Item.GetItemDataByID(link);
	if itemData and itemData.isOpenable then itemOpenedAt = GetTime(); end
end
hooksecurefunc("UseContainerItem", function(bag, slot) ItemUsed(UsedItemLink(bag, slot)); end);
-- ClassicAPI's item use path and action bar items don't go through UseContainerItem
hooksecurefunc(C_Item, "UseItemByName", function(item) ItemUsed(UsedItemLink(item)); end);
hooksecurefunc("UseAction", function(slot)
	local actionType, id = GetActionInfo(slot);
	if actionType == "item" and id then ItemUsed("item:" .. id); end
end);

-- the remembered recipe item, if it is the one that taught `skill` (a failed use, or a
-- recipe sold to a vendor, must not label an unrelated toast)
local function TakeRecipe(skill)
	local recipe = lastRecipe;
	if not recipe or GetTime() > recipe.expires then return; end
	local matches;
	if recipe.taught then
		matches = recipe.taught[skill];
	else
		matches = recipe.name and find(recipe.name, skill, 1, true);
	end
	if matches then
		lastRecipe = nil;
		return recipe;
	end
end

-- the skill line of the open trainer's service with this name
-- (the trainer, trade skill and craft windows are load-on-demand, so they may not exist yet)
local function TrainerSkillLineFor(spellName)
	if not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) then return; end
	for i = 1, GetNumTrainerServices() do
		local name, _, category = GetTrainerServiceInfo(i);
		if category ~= "header" and name == spellName then
			return GetTrainerServiceSkillLine(i);
		end
	end
end
-- the profession the open trainer teaches
local function TrainerProfession()
	if not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) then return; end
	for i = 1, GetNumTrainerServices() do
		local _, _, category = GetTrainerServiceInfo(i);
		if category ~= "header" then
			local key = ProfessionKey(GetTrainerServiceSkillLine(i));
			if key then return key; end
		end
	end
end

-- the player's own Enchanting craft window is open
local function EnchantingWindowOpen()
	return CraftFrame and CraftFrame:IsShown() and not IsCraftLinked()
		and ProfessionKey(GetCraftDisplaySkillLine()) == "ENCHANTING";
end
local function CraftListHas(skill)
	for i = 1, GetNumCrafts() do
		if GetCraftInfo(i) == skill then return true; end
	end
end
-- the profession of the player's own open trade skill or craft window, if it lists `skill`
local function OpenWindowProfession(skill)
	if TradeSkillFrame and TradeSkillFrame:IsShown() and not IsTradeSkillLinked() then
		for i = 1, GetNumTradeSkills() do
			if GetTradeSkillInfo(i) == skill then return ProfessionKey(GetTradeSkillLine()); end
		end
	end
	if CraftFrame and CraftFrame:IsShown() and not IsCraftLinked() and CraftListHas(skill) then
		return ProfessionKey(GetCraftDisplaySkillLine());
	end
end
-- the player's only recipe profession, or nil
local function OnlyProfession()
	local known;
	for _, key in ipairs(RECIPE_PROFESSIONS) do
		if C_SpellBook.GetSkillLineRank(PROFESSION_SKILL[key]) then
			if known then return; end  -- more than one: don't guess
			known = key;
		end
	end
	return known;
end

-- An unknown profession gets a plain scroll icon.
-- `link`: the recipe item
local function ShowRecipeToast(skill, message, profession, link, quality)
	AddAlert({ kind = "recipe", toast = "recipetoast", name = skill, link = link,
		quality = quality or LE_ITEM_QUALITY_COMMON, tip = message,
		profession = profession, cat = "recipes", force = true });
end
local function ShowRememberedRecipe(skill, message, recipe)
	return ShowRecipeToast(skill, message, recipe.profession, recipe.link, recipe.quality);
end

local function HandleSystemMessage(message)
	-- trade skill recipes: the recipe item, then the trainer, then the profession windows
	local skill = MatchFormat(message, ERR_LEARN_RECIPE_S);
	if skill then
		local recipe = TakeRecipe(skill);
		if recipe then return ShowRememberedRecipe(skill, message, recipe); end
		local line = TrainerSkillLineFor(skill);
		local trainer = ProfessionKey(line) or (not line and TrainerProfession());
		if trainer then return ShowRecipeToast(skill, message, trainer); end
		-- taught by the open trainer, under a skill we have no icon for: don't guess
		if line then return ShowRecipeToast(skill, message); end
		C_Timer.After(LEARN_SETTLE, function()
			ShowRecipeToast(skill, message, OpenWindowProfession(skill) or OnlyProfession());
		end);
		return;
	end

	-- Enchanting formulas make no item, so they are announced like spells. Class spells,
	-- Disenchant and the Enchanting ranks use the same line; formulas are the ones that
	-- don't enter the spellbook.
	skill = MatchFormat(message, ERR_LEARN_SPELL_S);
	if not skill then return; end
	local recipe = TakeRecipe(skill);
	if recipe then return ShowRememberedRecipe(skill, message, recipe); end
	local fromCraftWindow = false;
	local line = TrainerSkillLineFor(skill);
	if line then
		if ProfessionKey(line) ~= "ENCHANTING" then return; end
	elseif TrainerProfession() ~= "ENCHANTING" then
		if not EnchantingWindowOpen() then return; end
		fromCraftWindow = true;
	end
	C_Timer.After(LEARN_SETTLE, function()
		if GetSpellInfo(skill) then return; end
		if fromCraftWindow and not CraftListHas(skill) then return; end
		ShowRecipeToast(skill, message, "ENCHANTING");
	end);
end

-- Honor (individual gains are reported in chat, in every zone; kill honor is an estimate)
local HONOR_ICONS = { Alliance = assets .. "PVPCurrency-Honor-Alliance", Horde = assets .. "PVPCurrency-Honor-Horde" };
local function HandleHonorMessage(message)
	local victim, _, honor = MatchFormat(message, COMBATLOG_HONORGAIN);
	if not victim then honor = MatchFormat(message, COMBATLOG_HONORAWARD); end
	honor = tonumber(honor);
	if not honor or honor <= 0 or honor < GetMinimum("honor") then return; end
	AddAlert({ kind = "honor", toast = "honortoast", name = HONOR or "Honor", count = honor, tip = message,
		quality = LE_ITEM_QUALITY_ARTIFACT, texture = HONOR_ICONS[GetPlayerFaction()] or HONOR_ICONS.Alliance,
		cat = "honor", force = true });
end

-- Events
local events = {
	CHAT_MSG_LOOT = HandleLootMessage,
	CHAT_MSG_MONEY = function(message) if config.money then HandleMoneyMessage(message); end end,
	CHAT_MSG_SYSTEM = function(message) if config.recipes then HandleSystemMessage(message); end end,
	CHAT_MSG_COMBAT_HONOR_GAIN = function(message) if config.honor then HandleHonorMessage(message); end end,
	PLAYER_MONEY = HandlePlayerMoney,
	PLAYER_ENTERING_WORLD = function() lastMoney = GetMoney(); end,
	LOOT_OPENED = function()
		lootOpen = true;
		lootHadCoin = false;
		for slot = 1, GetNumLootItems() do
			if LootSlotIsCoin(slot) then lootHadCoin = true; break; end
		end
		lootFromItem = itemOpenedAt ~= nil and (GetTime() - itemOpenedAt) < ITEM_OPEN_WAIT;
		itemOpenedAt = nil;
	end,
	LOOT_CLOSED = function() lootOpen = false; lootClosedAt = GetTime(); end,
	-- a loot walk's last coin arrives just before this; keep the usual grace window
	LOOT_SCAN_COMPLETED = function()
		if lootWalkActive then lootClosedAt = GetTime(); lootHadCoin = true; end
		lootWalkActive = false;
	end,
	MERCHANT_SHOW = function() merchantOpen = true; end,
	MERCHANT_CLOSED = function() merchantOpen = false; merchantClosedAt = GetTime(); end,
	QUEST_ACCEPTED = function() questAcceptClickedAt = nil; questAcceptedAt = GetTime(); end,
	START_LOOT_ROLL = HandleStartRoll,
	LOOT_HISTORY_ROLL_COMPLETE = HandleRollComplete,
};
-- a group roll can't finish once you are out of the group
local function HandleGroupChange()
	if not IsInGroup() then wipe(pendingRolls); end
end
events.PARTY_MEMBERS_CHANGED = HandleGroupChange;
events.RAID_ROSTER_UPDATE = HandleGroupChange;

-- Toast button: layout
-- point = {point, relativeKey (nil = the button), relativePoint, x, y}
-- 1.12.1 has no draw order inside a layer, so overlapping art is split across layers.
local REGIONS = {
	-- BACKGROUND
	{ key = "Background", layer = "BACKGROUND", file = "loottoast", size = {276, 96}, point = {"CENTER"},
		coords = {0.28222656, 0.55175781, 0.57812500, 0.95312500} },
	{ key = "EpicBackground", layer = "BACKGROUND", file = "LootToastAtlas", size = {272, 94}, point = {"CENTER"},
		coords = {0.001953125, 0.267578125, 0.416015625, 0.599609375} },
	{ key = "PvPBackground", layer = "BACKGROUND", file = "PvPRatedLootToast", size = {277, 113}, point = {"CENTER", nil, "CENTER", -1, 2} },
	{ key = "MoneyBackground", layer = "BACKGROUND", file = "loottoast", size = {249, 71}, point = {"CENTER"},
		coords = {0.56347656, 0.80664063, 0.28906250, 0.56640625} },
	{ key = "MountToastBackground", layer = "BACKGROUND", file = "mounttoast", size = {276, 109}, point = {"CENTER"},
		coords = {0.001953, 0.541016, 0.007813, 0.859375} },
	{ key = "PetToastBackground", layer = "BACKGROUND", file = "pettoast", size = {276, 98}, point = {"CENTER"},
		coords = {0.001953, 0.541016, 0.007813, 0.773438} },
	-- centred on the frame's round window (57px across), its edge just under the rim
	{ key = "RecipeIcon", layer = "BACKGROUND", size = {60, 60}, point = {"CENTER", nil, "LEFT", 31.5, 0}, mask = "RecipeIconMask" },
	-- legendary burst behind the frame, centred on the icon (retail LegendaryItemAlertFrameTemplate
	-- offsets, shifted by LegendaryBackground's -12, -4)
	{ key = "legendaryRing", layer = "BACKGROUND", file = "LegendaryToast", size = {131, 176}, point = {"CENTER", nil, "CENTER", -92, -8},
		coords = {0.001953125, 0.2578125, 0.400390625, 0.744140625} },
	{ key = "legendaryParticles3", layer = "BACKGROUND", file = "LegendaryToast", size = {84, 163}, point = {"CENTER", nil, "CENTER", -92, -4},
		coords = {0.396484375, 0.560546875, 0.57421875, 0.892578125} },
	{ key = "legendaryParticles2", layer = "BACKGROUND", file = "LegendaryToast", size = {78, 147}, point = {"CENTER", nil, "CENTER", -92, -4},
		coords = {0.642578125, 0.794921875, 0.23828125, 0.525390625} },
	{ key = "legendaryParticles1", layer = "BACKGROUND", file = "LegendaryToast", size = {124, 170}, point = {"CENTER", nil, "CENTER", -92, -4},
		coords = {0.396484375, 0.638671875, 0.23828125, 0.5703125} },
	{ key = "legendaryStarglow", layer = "BACKGROUND", file = "LegendaryToast", blend = "ADD", size = {230, 230}, point = {"CENTER", nil, "CENTER", -92, -4},
		coords = {0.001953125, 0.392578125, 0.001953125, 0.396484375} },
	-- BORDER
	{ key = "RecipeBackground", layer = "BORDER", file = "recipetoast", size = {312, 89}, point = {"CENTER"},
		coords = {0.001953125, 0.611328125, 0.0078125, 0.703125} },
	{ key = "Icon", layer = "BORDER", file = "unknow_treasure", size = {52, 52}, point = {"LEFT", nil, "LEFT", 23, -2} },
	{ key = "LessIcon", layer = "BORDER", file = "unknow_treasure", size = {44, 44}, point = {"LEFT", nil, "LEFT", 23, 0} },
	{ key = "RollWonTitle", layer = "BORDER", size = {21, 21}, point = {"TOPLEFT", "Icon", "TOPRIGHT", 158, 5} },
	{ key = "MoneyIcon", layer = "BORDER", path = [[Interface\Icons\INV_Misc_Coin_02]], size = {38, 38}, point = {"LEFT", nil, "LEFT", 30, 0} },
	-- ARTWORK
	{ key = "LegendaryBackground", layer = "ARTWORK", file = "LegendaryToast", size = {302, 119}, point = {"CENTER", nil, "CENTER", -12, -4},
		coords = {0.396484, 0.986328, 0.00195312, 0.234375} },
	{ key = "LessBackground", layer = "ARTWORK", file = "LootToastAtlas", size = {276, 80}, point = {"CENTER"},
		coords = {0.000976562, 0.270508, 0.796875, 0.953125} },
	{ key = "MoneyIconBorder", layer = "ARTWORK", file = "loottoast", size = {45, 45}, point = {"CENTER", "MoneyIcon", "CENTER", 0, 0},
		coords = {0.73242188, 0.78906250, 0.57421875, 0.80078125} },
	{ key = "IconBorder", layer = "ARTWORK", file = "LootToastAtlas", size = {58, 58}, point = {"CENTER", "Icon", "CENTER", 0, 0},
		coords = {0.34082, 0.397461, 0.53125, 0.644531}, shown = true },
	{ key = "Count", font = "NumberFontNormal", layer = "ARTWORK", justifyH = "RIGHT", point = {"BOTTOMRIGHT", "Icon", "BOTTOMRIGHT", -2, 3}, shown = true },
	{ key = "Label", font = "GameFontNormal", layer = "ARTWORK", justifyH = "LEFT", size = {167, 16}, point = {"TOPLEFT", "Icon", "TOPRIGHT", 7, 5} },
	{ key = "ItemName", font = "GameFontNormal", fontSize = 14, layer = "ARTWORK", justifyH = "LEFT", justifyV = "MIDDLE", size = {167, 33},
		point = {"TOPLEFT", "Icon", "TOPRIGHT", 10, -16} },
	{ key = "RollWon", font = "GameFontGreen", layer = "ARTWORK", justifyH = "LEFT", point = {"TOPRIGHT", "RollWonTitle", "TOPLEFT", -4, -2} },
	{ key = "MoneyLabel", font = "GameFontNormal", layer = "ARTWORK", justifyH = "LEFT", point = {"TOPLEFT", "MoneyIconBorder", "TOPRIGHT", 7, -1} },
	{ key = "Amount", font = "GameFontHighlightLarge", layer = "ARTWORK", justifyH = "LEFT", point = {"BOTTOMLEFT", "MoneyIconBorder", "BOTTOMRIGHT", 10, 7} },
	{ key = "LessItemName", font = "GameFontNormal", fontSize = 14, layer = "ARTWORK", justifyH = "LEFT", justifyV = "MIDDLE", size = {167, 33},
		point = {"TOPLEFT", "LessIcon", "TOPRIGHT", 14, -4}, color = {1, 1, 1} },
	{ key = "RecipeTitle", font = "GameFontHighlight", layer = "ARTWORK", point = {"TOP", nil, "TOP", 31, -19} },
	{ key = "RecipeName", font = "GameFontNormal", layer = "ARTWORK", justifyH = "CENTER", justifyV = "MIDDLE",
		point = {"TOPLEFT", nil, "TOPLEFT", 98, -34}, point2 = {"BOTTOMRIGHT", nil, "BOTTOMRIGHT", -32, 17} },
	-- OVERLAY
	-- legendary frame flash: in ARTWORK it could end up under LegendaryBackground
	{ key = "legendaryGlow", layer = "OVERLAY", file = "LegendaryToast", blend = "ADD", size = {302, 119}, point = {"CENTER", nil, "CENTER", -12, -4},
		coords = {0.396484, 0.986328, 0.00195312, 0.234375} },
	{ key = "legendaryShine", layer = "OVERLAY", file = "LegendaryToast", blend = "ADD", size = {302, 119}, point = {"CENTER", nil, "CENTER", -12, -4},
		coords = {0.396484, 0.986328, 0.00195312, 0.234375} },
	-- artifact icon frame: covers the orange frame baked into LegendaryBackground
	{ key = "ArtifactIconBorder", layer = "OVERLAY", file = "LootToastAtlas", size = {58, 58}, point = {"CENTER", "Icon", "CENTER", 0, 0},
		coords = {0.272461, 0.329102, 0.667969, 0.78125} },
	{ key = "glow", layer = "OVERLAY", file = "LootToastAtlas", blend = "ADD", size = {286, 109}, point = {"CENTER"},
		coords = {0.000976562, 0.280273, 0.00195312, 0.214844} },
	{ key = "shine", layer = "OVERLAY", file = "LootToastAtlas", blend = "ADD", size = {171, 75}, point = {"BOTTOMLEFT", nil, "BOTTOMLEFT", -10, 12},
		coords = {0.817383, 0.984375, 0.21875, 0.365234} },
	{ key = "recipeGlow", layer = "OVERLAY", file = "LootToastAtlas", blend = "ADD", size = {330, 120}, point = {"CENTER"},
		coords = {0.000976562, 0.280273, 0.00195312, 0.214844} },
	{ key = "recipeShine", layer = "OVERLAY", file = "LootToastAtlas", blend = "ADD", size = {171, 75}, point = {"BOTTOMLEFT", nil, "BOTTOMLEFT", 0, 7},
		coords = {0.817383, 0.984375, 0.21875, 0.365234} },
	-- sheen across the legendary frame (retail BOTTOMLEFT 10, 24 of the 302x119 frame)
	{ key = "legendarySheen", layer = "OVERLAY", file = "LootToastAtlas", blend = "ADD", size = {171, 75}, point = {"BOTTOMLEFT", nil, "BOTTOMLEFT", -15, 8},
		coords = {0.817383, 0.984375, 0.21875, 0.365234} },
};

-- animation steps: {type, change or offsetX, duration, order, startDelay}
-- Alpha changes add to the stored alpha (1), so a 0s -1 step starts a fade-in from 0.
-- The legendary burst follows the toast's 0.2s fade-in; the frame flash follows retail (0.6s).
local GLOW_ANIMS = {
	legendaryGlow = { {"Alpha", 1, 0.5, 1, 0.6}, {"Alpha", -1, 0.5, 2} },
	legendaryShine = { {"Alpha", 1, 0.5, 1, 0.6}, {"Alpha", -1, 0.5, 2} },
	legendaryRing = { {"Alpha", 1, 0.5, 1, 0.2}, {"Alpha", -1, 0.5, 2} },
	legendaryStarglow = { {"Alpha", 1, 0.5, 1, 0.2}, {"Alpha", -1, 0.5, 2} },
	legendaryParticles1 = { {"Alpha", 1, 0.3, 1, 0.2}, {"Alpha", -1, 0.3, 2} },
	legendaryParticles2 = { {"Alpha", 1, 0.3, 1, 0.2}, {"Alpha", -1, 1, 2} },
	legendaryParticles3 = { {"Alpha", 1, 0.3, 1, 0.2}, {"Alpha", -1, 0.3, 2} },
	legendarySheen = { {"Alpha", -1, 0, 1}, {"Alpha", 1, 0.1, 2}, {"Translation", 220, 0.71, 3}, {"Alpha", -1, 0.25, 3, 0.175} },
	glow = { {"Alpha", -1, 0, 1}, {"Alpha", 1, 0.2, 2}, {"Alpha", -1, 0.5, 3} },
	shine = { {"Alpha", -1, 0, 1}, {"Alpha", 1, 0.1, 2}, {"Translation", 200, 0.71, 3}, {"Alpha", -1, 0.25, 3, 0.175} },
	recipeGlow = { {"Alpha", -1, 0, 1}, {"Alpha", 1, 0.2, 2}, {"Alpha", -1, 0.5, 3} },
	recipeShine = { {"Alpha", -1, 0.2, 1}, {"Translation", 240, 0.65, 2}, {"Alpha", -1, 0.45, 2, 0.25} },
};
-- these fade in from a stored alpha of 0
local START_TRANSPARENT = {
	legendaryGlow = true, legendaryShine = true, legendaryRing = true, legendaryStarglow = true,
	legendaryParticles1 = true, legendaryParticles2 = true, legendaryParticles3 = true,
};
local LEGENDARY_ANIMS = { "legendaryStarglow", "legendaryRing", "legendaryParticles1", "legendaryParticles2", "legendaryParticles3",
	"legendaryGlow", "legendaryShine", "legendarySheen" };

local function AddAnimation(group, step)
	local anim = group:CreateAnimation(step[1]);
	if step[1] == "Alpha" then
		anim:SetChange(step[2]);
	else
		anim:SetOffset(step[2], 0);
	end
	anim:SetDuration(step[3]);
	anim:SetOrder(step[4]);
	if step[5] then anim:SetStartDelay(step[5]); end
	return anim;
end

local function CreateRegions(button)
	local font = GameFontNormal:GetFont();
	for _, spec in ipairs(REGIONS) do
		local region;
		if spec.font then
			region = button:CreateFontString(nil, spec.layer, spec.font);
			if spec.fontSize then region:SetFont(font, spec.fontSize); end
			if spec.justifyH then region:SetJustifyH(spec.justifyH); end
			if spec.justifyV then region:SetJustifyV(spec.justifyV); end
			if spec.color then region:SetTextColor(spec.color[1], spec.color[2], spec.color[3]); end
		else
			region = button:CreateTexture(nil, spec.layer);
			if spec.file then
				region:SetTexture(assets .. spec.file);
			elseif spec.path then
				region:SetTexture(spec.path);
			end
			if spec.coords then region:SetTexCoord(spec.coords[1], spec.coords[2], spec.coords[3], spec.coords[4]); end
			if spec.blend then region:SetBlendMode(spec.blend); end
			if spec.mask then region:SetMask(assets .. spec.mask); end
		end
		if spec.size then region:SetSize(spec.size[1], spec.size[2]); end
		for _, p in ipairs({spec.point, spec.point2}) do
			local relative = p[2] and button[p[2]] or button;
			region:SetPoint(p[1], relative, p[3] or p[1], p[4] or 0, p[5] or 0);
		end
		if not spec.shown then region:Hide(); end
		button[spec.key] = region;
	end
end

-- shared by every group: a group's parent is the region it animates
local function ShowRegion(group) group:GetParent():Show(); end
local function HideRegion(group) group:GetParent():Hide(); end

local function CreateGlowAnimations(button)
	for key, steps in pairs(GLOW_ANIMS) do
		local texture = button[key];
		local group = texture:CreateAnimationGroup();
		for _, step in ipairs(steps) do AddAnimation(group, step); end
		group:SetScript("OnPlay", ShowRegion);
		group:SetScript("OnFinished", HideRegion);
		group:SetScript("OnStop", HideRegion);
		if START_TRANSPARENT[key] then texture:SetAlpha(0); end
		texture.animIn = group;
	end
end

-- Toast button: behaviour
-- glow {w, h} and sheen {w, h, x, y} per toast size: the default 276x96 toast, the
-- 80px-tall grey toast (which sits 8px up) and the 249x71 money toast
local FX_DEFAULT = { glow = {286, 109}, shine = {171, 75, -10, 12} };
local FX_GREY = { glow = {286, 91}, shine = {143, 62, -10, 18} };
local FX_MONEY = { glow = {258, 81}, shine = {126, 55, 4, 21} };

-- a toast waits this long before it fades out; once held under the mouse, only RESUME_DELAY
-- after the mouse leaves (retail AlertFrame_StopOutAnimation/AlertFrame_ResumeOutAnimation)
local FADE_OUT_DELAY = 4.05;
local RESUME_DELAY = 1;

local KIND_LABELS = {
	received = L.YOU_RECEIVED_LABEL, won = L.YOU_WON_LABEL, created = L.YOU_CREATED_LABEL,
	honor = L.YOU_EARNED_LABEL, recipe = L.NEW_RECIPE_LEARNED_TITLE,
};
local function ToastLabel(data)
	if data.toast == "legendarytoast" then
		if data.quality >= LE_ITEM_QUALITY_ARTIFACT then return ITEM_QUALITY6_DESC or "Artifact"; end
		return ITEM_QUALITY5_DESC;
	end
	return KIND_LABELS[data.kind] or "";
end

-- dice for Need, coin for Greed, nothing otherwise
local ROLL_ICONS = {
	[LOOT_ROLL_TYPE_NEED] = [[Interface\Buttons\UI-GroupLoot-Dice-Up]],
	[LOOT_ROLL_TYPE_GREED] = [[Interface\Buttons\UI-GroupLoot-Coin-Up]],
};
-- label and roll result of a toast on screen
UpdateButtonRoll = function(button)
	local data = button.data;
	button.Label:SetText(ToastLabel(data));
	local hasRoll = data.roll ~= nil;
	button.RollWon:SetShown(hasRoll);
	button.RollWonTitle:SetShown(hasRoll);
	if hasRoll then
		button.RollWon:SetText(data.roll);
		local icon = data.rollType and ROLL_ICONS[data.rollType];
		if icon then button.RollWonTitle:SetTexture(icon); else button.RollWonTitle:Hide(); end
	end
end

local function ShowTooltip(button)
	local data = button.data;
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	if data.tip then
		GameTooltip:SetText(tostring(data.name or ""), 1, 1, 1);
		GameTooltip:AddLine(data.tip, nil, nil, nil, 1);
	elseif data.money then
		GameTooltip:AddLine(L.YOU_RECEIVED_LABEL);
		GameTooltip:AddLine(FormatMoney(data.money), 1, 1, 1);
	elseif data.link then
		GameTooltip:SetHyperlink(data.link);
	else
		GameTooltip:SetText(tostring(data.name or ""), 1, 1, 1);
	end
	GameTooltip:Show();
end

-- name, count and tooltip of a toast on screen
UpdateButtonItem = function(button)
	local data = button.data;
	button.ItemName:SetText(data.name);
	button.LessItemName:SetText(data.name);
	local count = tonumber(data.count) or 0;
	button.Count:SetText(count > 1 and data.count or "");
	if GameTooltip:IsOwned(button) then ShowTooltip(button); end
end

local function Button_OnShow(button)
	-- shown again with its parent (UIParent after Alt-Z): it is still set up
	if button.active then return; end
	local data = button.data;
	if not data or not data.name then button:Hide(); return; end
	button.active = true;

	local toast = data.toast;
	local isDefault, isRecipe, isHonor = toast == "defaulttoast", toast == "recipetoast", toast == "honortoast";
	local isMoney, isLegendary, isCommon = toast == "moneytoast", toast == "legendarytoast", toast == "commontoast";
	local quality = data.quality;
	local isAverage = not isRecipe and not isMoney and not isCommon;
	-- artifacts reuse the legendary toast with the artifact icon frame
	local isArtifact = isLegendary and quality >= LE_ITEM_QUALITY_ARTIFACT;
	local honorCoords = HONOR_BACKGROUND_TCOORDS[GetPlayerFaction()] or HONOR_BACKGROUND_TCOORDS.Alliance;

	local count = tonumber(data.count) or 0;
	button.Count:SetText(count > (isHonor and 0 or 1) and data.count or "");
	button.Icon:SetTexture(data.texture); button.Icon:SetShown(isAverage);
	button.IconBorder:SetShown(isAverage and not isArtifact); button.ArtifactIconBorder:SetShown(isArtifact);
	button.LessIcon:SetTexture(data.texture);
	button.ItemName:SetText(data.name); button.ItemName:SetShown(isAverage);
	button.LessItemName:SetText(data.name);
	button.Label:SetShown(isAverage);
	button.MoneyLabel:SetText(L.YOU_RECEIVED_LABEL); button.MoneyLabel:SetShown(isMoney);
	button.Amount:SetText(data.name); button.Amount:SetShown(isMoney);
	local isEpic = isDefault and quality == LE_ITEM_QUALITY_EPIC;
	button.Background:SetShown(isDefault and not isEpic);
	button.EpicBackground:SetShown(isEpic);
	button.PvPBackground:SetShown(isHonor);
	button.PvPBackground:SetSize(honorCoords[1], honorCoords[2]);
	button.PvPBackground:SetTexCoord(honorCoords[3], honorCoords[4], honorCoords[5], honorCoords[6]);
	button.RecipeBackground:SetShown(isRecipe); button.RecipeTitle:SetShown(isRecipe);
	button.RecipeName:SetShown(isRecipe); button.RecipeIcon:SetShown(isRecipe);
	button.LessBackground:SetShown(isCommon); button.LessItemName:SetShown(isCommon);
	button.LessIcon:SetShown(isCommon); button.LegendaryBackground:SetShown(isLegendary);
	button.MoneyBackground:SetShown(isMoney); button.MoneyIconBorder:SetShown(isMoney);
	button.MoneyIcon:SetShown(isMoney);
	button.MountToastBackground:SetShown(toast == "mounttoast");
	button.PetToastBackground:SetShown(toast == "pettoast");
	UpdateButtonRoll(button);

	if isRecipe then
		button.RecipeIcon:SetTexture(ProfessionIcon(data.profession) or RECIPE_FALLBACK_ICON);
		button.RecipeIcon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP);
		button.RecipeName:SetText(data.name);
		button.RecipeTitle:SetText(ToastLabel(data));
	end

	local r, g, b = GetQualityRGB(quality);
	button.ItemName:SetTextColor(r, g, b);
	button.LessItemName:SetTextColor(r, g, b);
	if quality == LE_ITEM_QUALITY_COMMON and not isCommon then
		-- the atlas has no white frame
		button.IconBorder:SetTexture(TEX_COMMON_BORDER);
		button.IconBorder:SetTexCoord(0, 0.8125, 0, 0.8125);
	else
		local border = LOOT_BORDER_BY_QUALITY[quality];
		button.IconBorder:SetTexture(TEX_LOOT_ATLAS);
		if border then button.IconBorder:SetTexCoord(border[1], border[2], border[3], border[4]); end
	end

	local cat = data.cat;
	if GetToastEffect(cat, "sound") and SoundQualityAllowed(cat, quality) then
		if isLegendary then PlaySoundFile(SOUNDKIT.UI_LEGENDARY_LOOT_TOAST);
		elseif isCommon or (isDefault and quality and quality <= LE_ITEM_QUALITY_COMMON) then PlaySoundFile(SOUNDKIT.UI_RAID_LOOT_TOAST_LESSER_ITEM_WON);
		elseif isRecipe or toast == "mounttoast" or toast == "pettoast" then PlaySoundFile(SOUNDKIT.UI_GARRISON_FOLLOWER_LEARN_TRAIT);
		else PlaySoundFile(SOUNDKIT.UI_EPICLOOT_TOAST); end
	end
	if GetToastEffect(cat, "anims") then
		if isLegendary then
			for i = 1, #LEGENDARY_ANIMS do button[LEGENDARY_ANIMS[i]].animIn:Play(); end
		elseif isRecipe then
			button.recipeGlow.animIn:Play(); button.recipeShine.animIn:Play();
		else
			local fx = (isCommon and FX_GREY) or (isMoney and FX_MONEY) or FX_DEFAULT;
			button.glow:SetSize(fx.glow[1], fx.glow[2]);
			button.shine:SetSize(fx.shine[1], fx.shine[2]);
			button.shine:ClearAllPoints();
			button.shine:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", fx.shine[3], fx.shine[4]);
			button.glow.animIn:Play(); button.shine.animIn:Play();
		end
	end
end

local function Button_OnHide(button)
	-- hidden with its parent: keep the toast; its animations pause until it shows again
	if button:IsShown() then return; end
	button.active = nil;
	button.hovered = nil;
	button.fadeOut:SetStartDelay(FADE_OUT_DELAY);
	button.animIn:Stop(); button.waitAndAnimOut:Stop();
	for key in pairs(GLOW_ANIMS) do button[key].animIn:Stop(); end
	button.data = nil;
	if GameTooltip:IsOwned(button) then GameTooltip:Hide(); end
	for i = #shownButtons, 1, -1 do
		if shownButtons[i] == button then tRemove(shownButtons, i); end
	end
	AdjustAnchors();
	-- a button is free again: resume the queue
	if #alertQueue > 0 then private.updateFrame:Show(); end
end

local function Button_OnClick(button, mouseButton)
	if mouseButton == "RightButton" then
		button:Hide();
	elseif button.data and button.data.link then
		private.HandleModifiedItemClick(button.data.link);
	end
end

local function Button_OnEnter(button)
	-- hold the toast while it is hovered; stopping the fade-out restores its alpha
	button.hovered = true;
	if button.waitAndAnimOut:IsPlaying() then
		button.waitAndAnimOut:Stop();
		button.fadeOut:SetStartDelay(RESUME_DELAY);
	end
	if button.data then ShowTooltip(button); end
end

local function Button_OnLeave(button)
	button.hovered = nil;
	GameTooltip:Hide();
	-- resume the fade-out, unless the toast is gone or still fading in (that starts it)
	if button:IsShown() and not button.animIn:IsPlaying() and not button.waitAndAnimOut:IsPlaying() then
		button.waitAndAnimOut:Play();
	end
end

-- fade-in done: start the fade-out timer, or keep the toast while it is held
local function AnimIn_OnFinished(group)
	local button = group:GetParent();
	if button.hovered then
		button.fadeOut:SetStartDelay(RESUME_DELAY);
	else
		button.waitAndAnimOut:Play();
	end
end

CreateAlertButton = function(index)
	local button = CreateFrame("Button", "PrettyLootAlertButton" .. index, UIParent);
	button:SetSize(276, 96);
	-- default HIGH: above the action bars, below the Escape menu and popups (DIALOG)
	button:SetFrameStrata(GetStrata());
	button:SetToplevel(true);
	button:EnableMouse(true);
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	button:Hide();

	CreateRegions(button);
	CreateGlowAnimations(button);

	-- fade in (the 0s step drops the stored alpha of 1 to 0), then wait and fade out
	local animIn = button:CreateAnimationGroup();
	AddAnimation(animIn, {"Alpha", -1, 0, 1});
	AddAnimation(animIn, {"Alpha", 1, 0.2, 2});
	animIn:SetScript("OnFinished", AnimIn_OnFinished);
	local waitAndAnimOut = button:CreateAnimationGroup();
	button.fadeOut = AddAnimation(waitAndAnimOut, {"Alpha", -1, 1.5, 1, FADE_OUT_DELAY});
	waitAndAnimOut:SetScript("OnFinished", HideRegion);
	button.animIn = animIn;
	button.waitAndAnimOut = waitAndAnimOut;

	button:SetScript("OnShow", Button_OnShow);
	button:SetScript("OnHide", Button_OnHide);
	button:SetScript("OnClick", Button_OnClick);
	button:SetScript("OnEnter", Button_OnEnter);
	button:SetScript("OnLeave", Button_OnLeave);

	alertButtons[index] = button;
	return button;
end

-- Event/update frame
-- not parented to UIParent, so the queue keeps ticking while the interface is hidden (Alt-Z)
local eventFrame = CreateFrame("Frame", "PrettyLootAlertFrame");
for event in pairs(events) do eventFrame:RegisterEvent(event); end
eventFrame:SetScript("OnEvent", function(_, event, ...) events[event](...); end);

-- shows queued toasts at least config.time seconds apart; with every button busy it
-- sleeps until one hides (Button_OnHide)
local nextShow = 0;
eventFrame:SetScript("OnUpdate", function(self)
	if #alertQueue == 0 then self:Hide(); return; end
	if not UIParent:IsShown() then
		-- interface hidden: keep only the newest screenful, so it doesn't burst on return
		local keep = NumButtons();
		while #alertQueue > keep do
			local dropped = tRemove(alertQueue, 1);
			if dropped.kind == "won" then ToastRejected(dropped); end
		end
		return;
	end
	local now = GetTime();
	if now < nextShow then return; end
	local alert = GetFreeButton();
	if not alert then self:Hide(); return; end
	nextShow = now + (tonumber(config.time) or 0.30);
	tInsert(shownButtons, alert);
	AdjustAnchors();
	alert:Show();
	alert.animIn:Play();
end);
-- hidden frames still get events; AddAlert and Button_OnHide wake it
eventFrame:Hide();
private.updateFrame = eventFrame;

-- Movable anchor for positioning
local anchor = CreateFrame("Button", "PrettyLootAlertAnchor", UIParent);
anchor:SetSize(276, 96);
anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
anchor:SetFrameStrata(GetStrata());
anchor:SetMovable(true);
anchor:SetClampedToScreen(true);
anchor:EnableMouse(true);
anchor:RegisterForDrag("LeftButton");
anchor:Hide();

local anchorBg = anchor:CreateTexture(nil, "BACKGROUND");
anchorBg:SetAllPoints(anchor);
anchorBg:SetColorTexture(0.1, 0.8, 0.1, 0.5);

local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal");
anchorText:SetPoint("CENTER", anchor, "CENTER", 0, 0);
anchorText:SetText(L.ANCHOR_TEXT);

anchor:SetScript("OnDragStart", anchor.StartMoving);
anchor:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing();
	local x = self:GetLeft() + (self:GetWidth() / 2) - (UIParent:GetWidth() / 2);
	local y = self:GetTop() - (self:GetHeight() / 2) - (UIParent:GetHeight() / 2);
	config.point_x = ClampPosition(math.floor(x + 0.5));
	config.point_y = ClampPosition(math.floor(y + 0.5));
	private.PlaceAnchor();  -- snaps back if the drag went past the limit
	AdjustAnchors();
	if private.RefreshOptions then private.RefreshOptions(); end
end);

private.ApplyStrata = function()
	local strata = GetStrata();
	anchor:SetFrameStrata(strata);
	for _, button in pairs(alertButtons) do button:SetFrameStrata(strata); end
end

private.PlaceAnchor = function()
	private.ApplyStrata();
	-- same on-screen size as a toast at the current scale
	local scale = GetScale();
	anchor:SetSize(276 * scale, 96 * scale);
	anchor:ClearAllPoints();
	anchor:SetPoint("CENTER", UIParent, "CENTER", ClampPosition(config.point_x), ClampPosition(config.point_y));
end
private.IsAnchorShown = function() return anchor:IsShown() and true or false; end
private.ToggleAnchor = function(show)
	if show == nil then show = not anchor:IsShown(); end
	if show then
		private.PlaceAnchor();
		anchor:Show();
	else
		anchor:Hide();
	end
end
