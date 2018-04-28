----------------------------------------------------------------------------------------------------
-- settings / constants / references
----------------------------------------------------------------------------------------------------
DruidBuffsSave = nil -- saved settings - defaults are set up in ADDON_LOADED

local CHECK_SECONDS = 10 -- how often to check for needed buffs

_G["BINDING_HEADER_DRUIDBUFFS"]                      = "Druid Buffs"
_G["BINDING_NAME_CLICK DruidBuffsButton:LeftButton"] = "Cast Next Buff"

-- get locale names for spells
local MARK_OF_THE_WILD = (GetSpellInfo(26990))
local GIFT_OF_THE_WILD = (GetSpellInfo(26991))
local OMEN_OF_CLARITY  = (GetSpellInfo(16864))
local THORNS           = (GetSpellInfo(26992))
local PHASE_SHIFT      = (GetSpellInfo(4511))

-- local references to commonly used functions
local GetPlayerBuffName     = GetPlayerBuffName
local GetPlayerBuffTimeLeft = GetPlayerBuffTimeLeft
local GetNumPartyMembers    = GetNumPartyMembers
local GetNumRaidMembers     = GetNumRaidMembers
local GetRaidRosterInfo     = GetRaidRosterInfo
local IsSpellInRange        = IsSpellInRange
local IsUsableSpell         = IsUsableSpell
local UnitBuff              = UnitBuff
local UnitIsConnected       = UnitIsConnected
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local UnitName              = UnitName

----------------------------------------------------------------------------------------------------
-- buff text
----------------------------------------------------------------------------------------------------
-- frame to show warning text and to handle events
local druidBuffsFrame = CreateFrame("frame", "DruidBuffsFrame", UIParent)
druidBuffsFrame:SetWidth(250)
druidBuffsFrame:SetHeight(30)
druidBuffsFrame:SetPoint("TOP")

-- the text
local druidBuffsText = druidBuffsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
druidBuffsText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
druidBuffsText:SetPoint("CENTER")

-- load the previously saved position
function druidBuffsFrame:RestorePosition()
	druidBuffsFrame:ClearAllPoints()
	druidBuffsFrame:SetPoint(
		DruidBuffsSave.textPosition.anchor1, UIParent, DruidBuffsSave.textPosition.anchor2,
		DruidBuffsSave.textPosition.offsetX, DruidBuffsSave.textPosition.offsetY)
end

-- save the current position
function druidBuffsFrame:SavePosition()
	local _
	DruidBuffsSave.textPosition.anchor1, _, DruidBuffsSave.textPosition.anchor2,
		DruidBuffsSave.textPosition.offsetX, DruidBuffsSave.textPosition.offsetY = self:GetPoint(1)
end

-- set it to be movable when holding shift
druidBuffsFrame:SetMovable(true)
druidBuffsFrame:EnableMouse(true)
druidBuffsFrame:RegisterForDrag("LeftButton")
druidBuffsFrame:SetScript("OnDragStart", function(self)
	if IsShiftKeyDown() then
		self:StartMoving()
	end
end)
druidBuffsFrame:SetScript("OnDragStop", druidBuffsFrame.StopMovingOrSizing)
druidBuffsFrame:SetScript("OnMouseDown", function(self, button)
	if button == "LeftButton" and IsShiftKeyDown() and not self.isMoving then
		self:StartMoving()
		self.isMoving = true
	end
end)
druidBuffsFrame:SetScript("OnMouseUp", function(self, button)
	if button == "LeftButton" and self.isMoving then
		self:StopMovingOrSizing()
		self.isMoving = false
		self:SavePosition()
	end
end)
druidBuffsFrame:SetScript("OnHide", function(self)
	if self.isMoving then
		self:StopMovingOrSizing()
		self.isMoving = false
		self:SavePosition()
	end
end)

--------------------------------------------------
-- color picker for the text color
--------------------------------------------------
function druidBuffsText:RestoreColor()
	local tc = DruidBuffsSave.textColor
	druidBuffsText:SetTextColor(tc[1], tc[2], tc[3], 1)
end

-- called when the color changes or the picker is canceled
function druidBuffsText.ColorPickerCallback(restore)
	local tc = DruidBuffsSave.textColor
	if restore then
		tc[1], tc[2], tc[3] = unpack(restore)
	else
		tc[1], tc[2], tc[3] = ColorPickerFrame:GetColorRGB()
	end
	druidBuffsText:RestoreColor()
end

-- open and show the color picker
function druidBuffsText:ShowColorPicker()
	local tc = DruidBuffsSave.textColor
	ColorPickerFrame:SetColorRGB(tc[1], tc[2], tc[3])
	ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = nil, nil
	ColorPickerFrame.previousValues = {tc[1], tc[2], tc[3]}
	ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc =
		druidBuffsText.ColorPickerCallback, druidBuffsText.ColorPickerCallback, druidBuffsText.ColorPickerCallback
	ColorPickerFrame:Hide() -- if already opened, need to reopen to update color
	ColorPickerFrame:Show()
end

----------------------------------------------------------------------------------------------------
-- setting the next buff
----------------------------------------------------------------------------------------------------
-- hidden secure button used with the key binding - its target/spell is set up in SetNextBuff()
local buffButton = CreateFrame("Button", "DruidBuffsButton", nil, "SecureActionButtonTemplate")
buffButton:SetAttribute("type", "spell")

-- counter for periodic buff checking
local elapsedCheckTime = CHECK_SECONDS - 3 -- make the first check in 3 seconds

--------------------------------------------------
-- return 1 if the player has learned a spell, else nil
--------------------------------------------------
local function HasLearnedSpell(spell)
	local usable, nomana = IsUsableSpell(spell)
	return usable or nomana
end

--------------------------------------------------
-- return which buff someone needs
--------------------------------------------------
local function FindBuffNeeded(name, check_distance)
	if (check_distance and IsSpellInRange(MARK_OF_THE_WILD, name) ~= 1) or not UnitIsConnected(name) or UnitIsDeadOrGhost(name) then
		return nil
	end

	local has_omen, has_mark, has_thorns
	local buff, left, _
	local check_thorns = DruidBuffsSave.checkThorns and DruidBuffsSave.thornsList[name]
	local is_player = name == UnitName("player")

	for i=1,32 do
		-- GetPlayerBuffTimeLeft() can see some times that UnitBuff() can't, so use it if possible
		if is_player then
			buff = (GetPlayerBuffName(i))
			left = (GetPlayerBuffTimeLeft(i))
		else
			buff, _, _, _, _, left = UnitBuff(name, i)
		end
		if not buff then
			break
		end

		if (buff == MARK_OF_THE_WILD or buff == GIFT_OF_THE_WILD) and (not left or left >= DruidBuffsSave.rebuffMark) then
			has_mark = true
		elseif buff == THORNS and (not left or left >= DruidBuffsSave.rebuffThorns) then
			has_thorns = true
		elseif buff == OMEN_OF_CLARITY and (not left or left >= DruidBuffsSave.rebuffOmen) then
			has_omen = true
		elseif buff == PHASE_SHIFT then
			return nil -- imp can't receive buffs now
		end
	end

	if not has_omen and name == UnitName("player") and HasLearnedSpell(OMEN_OF_CLARITY) then
		return OMEN_OF_CLARITY
	elseif not has_mark and HasLearnedSpell(MARK_OF_THE_WILD) then
		return MARK_OF_THE_WILD
	elseif check_thorns and not has_thorns and HasLearnedSpell(THORNS) then
		return THORNS
	end
end

--------------------------------------------------
-- return true if target's subgroup needs Gift of the Wild
--------------------------------------------------
local function GroupNeedsGift(target, group)
	if DruidBuffsSave.giftAmount == 0 or not HasLearnedSpell(GIFT_OF_THE_WILD) then
		return
	elseif DruidBuffsSave.giftAmount == 1 then
		return true
	elseif not group then
		return
	end

	local count = 1 -- how many need Mark of the Wild in the group
	if GetNumRaidMembers() > 0 then
		local name, _, subgroup
		for i=1,MAX_RAID_MEMBERS do
			name, _, subgroup = GetRaidRosterInfo(i)
			if name then
				if target ~= name and FindBuffNeeded(name, false) == MARK_OF_THE_WILD then
					count = count + 1
					if count >= DruidBuffsSave.giftAmount then
						return true
					end
				end
				local pet_name = name.."-Pet"
				if target ~= pet_name and FindBuffNeeded(pet_name, false) == MARK_OF_THE_WILD then
					count = count + 1
					if count >= DruidBuffsSave.giftAmount then
						return true
					end
				end
			end
		end
	else
		-- the player won't be in the party member loop, so check now
		if target ~= UnitName("player") and FindBuffNeeded(UnitName("player"), false) == MARK_OF_THE_WILD then
			count = count + 1
			if count >= DruidBuffsSave.giftAmount then
				return true
			end
		end
		local name
		for i=1,GetNumPartyMembers() do
			name = UnitName("party"..i)
			if target ~= name and FindBuffNeeded(name, false) == MARK_OF_THE_WILD then
				count = count + 1
				if count >= DruidBuffsSave.giftAmount then
					return true
				end
			end
			local pet_name = name.."-Pet"
			if target ~= pet_name and FindBuffNeeded(pet_name, false) == MARK_OF_THE_WILD then
				count = count + 1
				if count >= DruidBuffsSave.giftAmount then
					return true
				end
			end
		end
	end
end

--------------------------------------------------
-- set up the next buff
--------------------------------------------------
local function SetNextBuff()
	elapsedCheckTime = 0
	if InCombatLockdown() then
		return
	end

	local player_name = UnitName("player")
	local target, spell
	local group

	-- check self first
	spell = FindBuffNeeded(player_name, true)
	if spell then
		target = player_name
		-- find the player's group number
		if GetNumRaidMembers() > 0 then
			local name, _
			for i=1,MAX_RAID_MEMBERS do
				name, _, group = GetRaidRosterInfo(i)
				if name == player_name then
					break
				end
			end
		elseif GetNumPartyMembers() > 0 then
			group = 1
		end
	else
		-- check raid or party members - Mark of the Wild is wanted first, so only stop if that is
		-- found to be needed. If someone needs Thorns, then save their name in case no one else
		-- needed Mark of the Wild. Pets are lowest priority, so save their name too
		local needs_thorns_name
		local pet_needs_mark
		local pet_needs_thorns
		-- raid
		if GetNumRaidMembers() > 0 then
			local name, _
			for i=1,MAX_RAID_MEMBERS do
				name, _, group = GetRaidRosterInfo(i)
				if name and name ~= player_name then
					-- first the raid member
					spell = FindBuffNeeded(name, true)
					if spell then
						if spell == MARK_OF_THE_WILD then
							target = name
							break
						elseif not needs_thorns_name then
							needs_thorns_name = name
							spell = nil
						end
					else
						-- then their pet
						name = name .. "-Pet"
						spell = FindBuffNeeded(name, true)
						if spell then
							if spell == MARK_OF_THE_WILD then
								if not pet_needs_mark then
									pet_needs_mark = name
								end
							elseif not pet_needs_thorns then
								pet_needs_thorns = name
							end
							spell = nil
						end
					end
				end
			end
		-- party
		elseif GetNumPartyMembers() > 0 then
			local name
			for i=1,GetNumPartyMembers() do
				name = UnitName("party"..i)
				if name ~= player_name then
					-- first the party member
					spell = FindBuffNeeded(name, true)
					if spell then
						if spell == MARK_OF_THE_WILD then
							target = name
							group = 1
							break
						elseif not needs_thorns_name then
							needs_thorns_name = name
							spell = nil
						end
					else
						-- then their pet
						name = name .. "-Pet"
						spell = FindBuffNeeded(name, true)
						if spell then
							if spell == MARK_OF_THE_WILD then
								if not pet_needs_mark then
									pet_needs_mark = name
								end
							elseif not pet_needs_thorns then
								pet_needs_thorns = name
							end
							spell = nil
						end
					end
				end
			end
		end
		-- last resort spells if nothing more important was found
		if not spell then
			if needs_thorns_name then
				spell = THORNS
				target = needs_thorns_name
			elseif pet_needs_mark then
				spell = MARK_OF_THE_WILD
				target = pet_needs_mark
			elseif pet_needs_thorns then
				spell = THORNS
				target = pet_needs_thorns
			end
		end
	end

	-- upgrade to Gift of the Wild if needed
	if spell == MARK_OF_THE_WILD and GroupNeedsGift(target, group) then
		spell = GIFT_OF_THE_WILD
	end

	-- set the buff button and text - don't show the text while in sanctuary areas like Shattrath
	buffButton:SetAttribute("unit", target)
	buffButton:SetAttribute("spell", spell)
	if spell and target and GetZonePVPInfo() ~= "sanctuary" then
		druidBuffsText:SetText(target .. ": " .. spell)
	else
		druidBuffsText:SetText("")
	end
end

--------------------------------------------------
-- check buffs periodically
--------------------------------------------------
druidBuffsFrame:SetScript("OnUpdate", function(self, elapsed)
	elapsedCheckTime = elapsedCheckTime + elapsed
	if elapsedCheckTime >= CHECK_SECONDS then
		SetNextBuff()
	end
end)

--------------------------------------------------
-- handle events that affect buff checks
--------------------------------------------------
druidBuffsFrame:SetScript("OnEvent", function(self, event, arg1)
	-- someone's buffs/debuffs have changed, so recheck buffs now
	if event == "UNIT_AURA" then
		if UnitInParty(arg1) or UnitInRaid(arg1) or arg1:find("^partypet") or arg1:find("^raidpet") then -- "player" is always in party
			elapsedCheckTime = CHECK_SECONDS - .03 -- this lets a group of changes happen at once
		end
		return
	end

	-- combat started, so disable buff checking and hide the text
	if event == "PLAYER_REGEN_DISABLED" then
		druidBuffsFrame:UnregisterEvent("UNIT_AURA")
		druidBuffsFrame:Hide()
		return
	end

	-- combat ended, so restart buff checking and reshow the text
	if event == "PLAYER_REGEN_ENABLED" then
		druidBuffsFrame:RegisterEvent("UNIT_AURA")
		SetNextBuff()
		druidBuffsFrame:Show()
		return
	end

	-- the addon has loaded, so set default settings if needed
	if event == "ADDON_LOADED" and arg1 == "DruidBuffs" then
		druidBuffsFrame:UnregisterEvent(event)
		if DruidBuffsSave              == nil then DruidBuffsSave              = {}    end
		if DruidBuffsSave.checkThorns  == nil then DruidBuffsSave.checkThorns  = true  end
		if DruidBuffsSave.thornsList   == nil then DruidBuffsSave.thornsList   = {[UnitName("player")]=true} end
		if DruidBuffsSave.giftAmount   == nil then DruidBuffsSave.giftAmount   = 3     end
		if DruidBuffsSave.rebuffMark   == nil then DruidBuffsSave.rebuffMark   = 5*60  end
		if DruidBuffsSave.rebuffOmen   == nil then DruidBuffsSave.rebuffOmen   = 5*60  end
		if DruidBuffsSave.rebuffThorns == nil then DruidBuffsSave.rebuffThorns = 2*60  end
		if DruidBuffsSave.textColor    == nil then DruidBuffsSave.textColor    = {1, 1, 1} end
		druidBuffsText:RestoreColor()

		if DruidBuffsSave.textPosition == nil then
			DruidBuffsSave.textPosition = {}
			druidBuffsFrame:SavePosition()
		else
			druidBuffsFrame:RestorePosition()
		end
		return
	end
end)
druidBuffsFrame:RegisterEvent("ADDON_LOADED")          -- temporary - to set up default settings
druidBuffsFrame:RegisterEvent("UNIT_AURA")             -- to know when a buff/debuff has changed
druidBuffsFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- to know when combat starts
druidBuffsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- to know when combat ends

----------------------------------------------------------------------------------------------------
-- /buff command
----------------------------------------------------------------------------------------------------
-- show the list of people that will get Thorns
local function ShowThornsList()
	local name_table = {}
	for name in pairs(DruidBuffsSave.thornsList) do
		table.insert(name_table, name)
	end
	local names = table.concat(name_table, ", ")
	DEFAULT_CHAT_FRAME:AddMessage("Thorns list: " .. (names ~= "" and names or "none"))
end

_G.SLASH_BUFF1 = "/buff"
_G.SLASH_BUFF2 = "/druidbuffs"
function SlashCmdList.BUFF(input)
	input = input or ""

	local command, value, value2 = input:match("^(%w+)%s*([%w%-]*)%s*(%w*)%s*")
	command = command and command:lower()
	value = value and value:lower()

	-- /buff thorns
	if command and command:find("^thorn[s]?$") then
		if value == "on" then
			DruidBuffsSave.checkThorns = true
			DEFAULT_CHAT_FRAME:AddMessage("Thorns will be checked.")
		elseif value == "off" then
			DruidBuffsSave.checkThorns = false
			DEFAULT_CHAT_FRAME:AddMessage("Thorns will not be checked.")
		elseif not value or value == "" then
			ShowThornsList()
		else
			value = value and (value:gsub("(%a)(%w*)", function(first,rest) return first:upper() .. rest:lower() end)) -- capitalize
			if DruidBuffsSave.thornsList[value] then
				DruidBuffsSave.thornsList[value] = nil
				DEFAULT_CHAT_FRAME:AddMessage(value .. " will no longer be given Thorns.")
			else
				DruidBuffsSave.thornsList[value] = true
				DEFAULT_CHAT_FRAME:AddMessage(value .. " will be given Thorns.")
			end
		end
		SetNextBuff()
		return
	end

	-- /buff rebuff
	if command == "rebuff" then
		local minutes = tonumber(value2)
		if minutes then
			if value == "mark" then
				DruidBuffsSave.rebuffMark = minutes * 60
				DEFAULT_CHAT_FRAME:AddMessage("Rebuff time for Mark of the wild is set to " .. value2 .. " minute(s) left.")
				SetNextBuff()
				return
			end
			if value == "omen" then
				DruidBuffsSave.rebuffOmen = minutes * 60
				DEFAULT_CHAT_FRAME:AddMessage("Rebuff time for Omen of Clarity is set to " .. value2 .. " minute(s) left.")
				SetNextBuff()
				return
			end
			if value == "thorns" then
				DruidBuffsSave.rebuffThorns = minutes * 60
				DEFAULT_CHAT_FRAME:AddMessage("Rebuff time for Thorns is set to " .. value2 .. " minute(s) left.")
				SetNextBuff()
				return
			end
		end
		DEFAULT_CHAT_FRAME:AddMessage('The rebuff command is:')
		DEFAULT_CHAT_FRAME:AddMessage('/buff rebuff <"mark"|"omen"|"thorns"> <minutes left>')
		DEFAULT_CHAT_FRAME:AddMessage('For example: /buff rebuff omen 6')
		return
	end

	-- /buff gift
	if command == "gift" then
		local amount = tonumber(value)
		if value == "off" then
			DruidBuffsSave.giftAmount = 0
			DEFAULT_CHAT_FRAME:AddMessage("Gift of the Wild will never be used.")
		elseif not amount or amount < 1 or amount > 5 then
			DEFAULT_CHAT_FRAME:AddMessage('The amount must be from 1 to 5 or "off"')
		else
			DruidBuffsSave.giftAmount = amount
			DEFAULT_CHAT_FRAME:AddMessage("Gift of the Wild will be used when " .. value .. " or more need Mark of the Wild.")
		end
		SetNextBuff()
		return
	end

	-- /buff color
	if command == "color" then
		druidBuffsText:ShowColorPicker()
		return
	end

	-- bad or no command - show syntax
	DEFAULT_CHAT_FRAME:AddMessage('DruidBuffs commands:', 1, 1, 0)
	DEFAULT_CHAT_FRAME:AddMessage('/buff thorns <"on"|"off">')
	DEFAULT_CHAT_FRAME:AddMessage('/buff thorns <name>')
	DEFAULT_CHAT_FRAME:AddMessage('/buff rebuff <"mark"|"omen"|"thorns"> <minutes left>')
	DEFAULT_CHAT_FRAME:AddMessage('/buff gift <group amount|"off">')
	DEFAULT_CHAT_FRAME:AddMessage('/buff color')
	DEFAULT_CHAT_FRAME:AddMessage(' ')
	DEFAULT_CHAT_FRAME:AddMessage(string.format("Thorns:[%s], Gift:[%d], Rebuffs:[Mark=%d, Omen=%d, Thorns=%d]",
		(DruidBuffsSave.checkThorns and "ON" or "OFF"), DruidBuffsSave.giftAmount,
		DruidBuffsSave.rebuffMark/60, DruidBuffsSave.rebuffOmen/60, DruidBuffsSave.rebuffThorns/60))
	ShowThornsList()
end
