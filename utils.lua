local _, private = ...;
local type = type;
local tonumber = tonumber;
local unpack = unpack;
local gsub = string.gsub;
local match = string.match;

-- The TOC loads the SavedVariable before this file (## LoadSavedVariablesFirst),
-- so the settings table is the saved one; options.lua fills in the defaults.
if type(PrettyLootAlertDB) ~= "table" then PrettyLootAlertDB = {}; end
private.config = PrettyLootAlertDB;

private.Print = function(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ffffPretty Loot Alert:|r " .. tostring(msg));
end

-- GlobalString format -> anchored Lua pattern (positional %1$s aware)
local pattern_cache = {};

local function BuildPattern(fmt)
	local entry = pattern_cache[fmt];
	if entry then return entry; end

	local order, n = {}, 0;
	local pat = gsub(fmt, "%%(%d?)%$?([sd])", function(index, kind)
		n = n + 1;
		order[n] = tonumber(index) or n;
		return kind == "d" and "\002" or "\001";
	end);
	pat = gsub(pat, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1");
	pat = gsub(pat, "\001", "(.-)");
	pat = gsub(pat, "\002", "(%%d+)");

	entry = { pattern = "^" .. pat .. "$", order = order, n = n };
	pattern_cache[fmt] = entry;
	return entry;
end

-- Captures of `message` against a GlobalString, in the format's argument order, or nil.
-- Most calls miss, so the miss path builds no table.
private.MatchFormat = function(message, fmt)
	if type(message) ~= "string" or type(fmt) ~= "string" then return; end
	local entry = BuildPattern(fmt);
	local c1, c2, c3, c4, c5 = match(message, entry.pattern);
	if c1 == nil then return; end
	local captures = (entry.n > 5) and { match(message, entry.pattern) } or { c1, c2, c3, c4, c5 };
	local order = entry.order;
	local result = {};
	for i = 1, entry.n do
		result[order[i]] = captures[i];
	end
	return unpack(result, 1, entry.n);
end

-- Items
-- itemID from an ID, "item:..." payload or chat link; no item cache needed
private.GetItemID = function(item)
	if item == nil then return; end
	return C_Item.GetItemIDForItemInfo(item);
end

-- The full chat link inside `text`: "|cff1eff00|Hitem:...|h[Name]|h|r"
private.GetChatLink = function(text)
	if type(text) ~= "string" then return; end
	return match(text, "(|c%x+|Hitem:[^|]+|h%[.-%]|h|r)") or match(text, "(|Hitem:[^|]+|h%[.-%]|h)");
end

-- The display name inside a chat link
private.GetLinkName = function(link)
	if type(link) ~= "string" then return; end
	local name = match(link, "|h%[(.-)%]|h");
	if name and name ~= "" then return name; end
end

-- "item:..." payload of a chat link, or `text` itself when it already is one
-- (loot history links are bare "item:<id>:0:<suffix>:<unique>" payloads)
local function GetItemPayload(text)
	if type(text) ~= "string" then return; end
	return match(text, "|H(item:[%-%d:]+)|h") or match(text, "^(item:[%-%d:]+)$");
end

-- true when the payload carries a random suffix ("of the Monkey")
local function HasRandomSuffix(payload)
	local suffix = payload and tonumber(match(payload, "^item:%d+:%-?%d+:(%-?%d+)"));
	return suffix ~= nil and suffix ~= 0;
end

-- C_Item only knows the base item: read the suffixed name off a hidden tooltip
local scanTip;
local function GetDecoratedName(payload)
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "PrettyLootAlertScanTooltip", nil, "GameTooltipTemplate");
		scanTip.firstLine = _G["PrettyLootAlertScanTooltipTextLeft1"];
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE");
	scanTip:ClearLines();
	scanTip:SetHyperlink(payload);
	local name = scanTip.firstLine and scanTip.firstLine:GetText();
	scanTip:Hide();
	if name and name ~= "" then return name; end
end

-- Display link and name for a toast. `text` is a chat link or a bare payload;
-- `baseName`/`baseLink` are the base item's (no random suffix).
private.ResolveItemLink = function(text, baseName, baseLink)
	local chat = private.GetChatLink(text);
	if chat then
		return chat, private.GetLinkName(chat) or baseName;
	end
	local payload = GetItemPayload(text);
	if payload and HasRandomSuffix(payload) then
		-- rebuild a chat link around the payload so tooltip and shift-click keep the suffix
		local name = GetDecoratedName(payload) or baseName;
		local color = (type(baseLink) == "string" and match(baseLink, "^(|c%x+)")) or "|cffffffff";
		return color .. "|H" .. payload .. "|h[" .. name .. "]|h|r", name;
	end
	return baseLink, baseName;
end

-- name, link, quality, itemLevel, itemType, itemSubType, texture, classID, subclassID
-- of the base item, or nothing while it is not cached.
private.GetItemData = function(item)
	local id = private.GetItemID(item);
	if not id then return; end
	local name, link, quality, iLevel, _, itemType, subType, _, _, texture, _, classID, subclassID = C_Item.GetItemInfo(id);
	if name then
		return name, link, tonumber(quality) or 0, tonumber(iLevel) or 0, itemType, subType, texture, classID, subclassID;
	end
end

-- Ctrl-click: dressing room, shift-click: link into chat
private.HandleModifiedItemClick = function(link)
	if not link then return; end
	if IsControlKeyDown() then
		if DressUpItemLink then DressUpItemLink(link); end
		return true;
	elseif IsShiftKeyDown() then
		if ChatEdit_InsertLink then
			ChatEdit_InsertLink(link);
		elseif ChatFrameEditBox then
			-- open the chat input first, like shift-clicking a bag item
			local box = ChatFrameEditBox;
			if box:IsVisible() then
				box:Insert(link);
			else
				-- opening the input clears its text, so the link goes in as the opening text;
				-- next frame, put it in if the input came up empty anyway
				if ChatFrame_OpenChat then ChatFrame_OpenChat(link); else box:Show(); end
				C_Timer.After(0, function()
					if not box:IsVisible() then return; end
					local text = box:GetText() or "";
					if not string.find(text, link, 1, true) then box:Insert(link); end
				end);
			end
		end
		return true;
	end
end
