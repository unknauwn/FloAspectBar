-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this file,
-- You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local VERSION = "6.0.17"

-------------------------------------------------------------------------------
-- Variables
-------------------------------------------------------------------------------

local _
local SHOW_WELCOME = true;
local FLOASPECTBAR_BARSETTINGS_DEFAULT = { position = "auto", buttonsOrder = {}, color = { 0, 0.49, 0, 0.7 }, hiddenSpells = {} };
local FLOASPECTBAR_OPTIONS_DEFAULT = { [1] = { scale = 1, borders = true, barSettings = FLOASPECTBAR_BARSETTINGS_DEFAULT }, active = 1 };
FLOASPECTBAR_OPTIONS = FLOASPECTBAR_OPTIONS_DEFAULT;
local ACTIVE_OPTIONS = FLOASPECTBAR_OPTIONS[1];

-- Ugly
local changingSpec = false;

-------------------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------------------

-- Executed on load, calls general set-up functions
function FloAspectBar_OnLoad(self)

	-- Class-based setup, abort if not supported
	local temp, classFileName = UnitClass("player");
	classFileName = strupper(classFileName);

	local classSpells = FLO_ASPECT_SPELLS[classFileName];
	if classSpells == nil then
		return;
	end

	-- Store the spell list for later
	self.availableSpells = classSpells;
	if self.availableSpells == nil then
		return;
	end

	self.spells = {};
	self.SetupSpell = FloAspectBar_SetupSpell;
	self.UpdateState = FloAspectBar_UpdateState;
	self.menuHooks = { SetPosition = FloAspectBar_SetPosition, SetBorders = FloAspectBar_SetBorders };
	self:EnableMouse(1);

	if SHOW_WELCOME then
		DEFAULT_CHAT_FRAME:AddMessage( "FloAspectBar "..VERSION.." loaded." );
		SHOW_WELCOME = nil;

		SLASH_FLOASPECTBAR1 = "/floaspectbar";
		SLASH_FLOASPECTBAR2 = "/fab";
		SlashCmdList["FLOASPECTBAR"] = FloAspectBar_ReadCmd;

		self:RegisterEvent("ADDON_LOADED");
		self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
		self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED");
	end

	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("LEARNED_SPELL_IN_TAB");
	self:RegisterEvent("CHARACTER_POINTS_CHANGED");
	self:RegisterEvent("PLAYER_ALIVE");
	self:RegisterEvent("PLAYER_LEVEL_UP");
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN");
	self:RegisterEvent("ACTIONBAR_UPDATE_USABLE");
	self:RegisterEvent("UNIT_AURA");
	self:RegisterEvent("UPDATE_BINDINGS");
end

function FloAspectBar_OnEvent(self, event, arg1, ...)

	if event == "PLAYER_ENTERING_WORLD" or event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_ALIVE" or event == "PLAYER_LEVEL_UP" or event == "CHARACTER_POINTS_CHANGED" then
		if not changingSpec then
		        FloLib_Setup(self);
                end

	elseif event == "ADDON_LOADED" and arg1 == "FloAspectBar" then
		FloAspectBar_CheckTalentGroup(FLOASPECTBAR_OPTIONS.active);

		-- Hook the UIParent_ManageFramePositions function
		hooksecurefunc("UIParent_ManageFramePositions", FloAspectBar_UpdatePosition);
		hooksecurefunc("SetActiveSpecGroup", function() changingSpec = true; end);

	elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
		local spellName = ...;
		if arg1 == "player" and (spellName == FLOLIB_ACTIVATE_SPEC_1 or spellName == FLOLIB_ACTIVATE_SPEC_2) then
			changingSpec = false;
		end

	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
		if FLOASPECTBAR_OPTIONS.active ~= arg1 then
			FloAspectBar_TalentGroupChanged(arg1);
		end

	elseif event == "UPDATE_BINDINGS" then
		FloLib_UpdateBindings(self, "SHAPESHIFT");

	elseif event == "UNIT_AURA" then
		local unit = ...;
		if unit == PlayerFrame.unit then
			FloLib_UpdateState(self);
		end

	else
		FloLib_UpdateState(self);
	end
end

function FloAspectBar_TalentGroupChanged(grp)

	-- Save old spec position
	if ACTIVE_OPTIONS.barSettings.position ~= "auto" then
		ACTIVE_OPTIONS.barSettings.refPoint = { FloAspectBar:GetPoint() };
	end
	FloAspectBar_CheckTalentGroup(grp);
	FloLib_Setup(FloAspectBar);
	-- Restore position
	if ACTIVE_OPTIONS.barSettings.position ~= "auto" and ACTIVE_OPTIONS.barSettings.refPoint then
		FloAspectBar:ClearAllPoints();
		FloAspectBar:SetPoint(unpack(ACTIVE_OPTIONS.barSettings.refPoint));
	end
end

function FloAspectBar_CheckTalentGroup(grp)

	changingSpec = false;

	FLOASPECTBAR_OPTIONS.active = grp;
	ACTIVE_OPTIONS = FLOASPECTBAR_OPTIONS[grp];
	-- first time talent activation ?
	if not ACTIVE_OPTIONS then
		-- Copy primary spec options into other spec
		FLOASPECTBAR_OPTIONS[grp] = {};
		FloLib_CopyPreserve(FLOASPECTBAR_OPTIONS[1], FLOASPECTBAR_OPTIONS[grp]);
		ACTIVE_OPTIONS = FLOASPECTBAR_OPTIONS[grp];
	end

	FloAspectBar.globalSettings = ACTIVE_OPTIONS;
	FloAspectBar.settings = ACTIVE_OPTIONS.barSettings;
	FloAspectBar_SetPosition(nil, FloAspectBar, ACTIVE_OPTIONS.barSettings.position);
	FloAspectBar_SetScale(ACTIVE_OPTIONS.scale);
	FloAspectBar_SetBorders(nil, ACTIVE_OPTIONS.borders);

end

function FloAspectBar_ReadCmd(line)

	local cmd, var = strsplit(' ', line or "");

	if cmd == "scale" and tonumber(var) then
		FloAspectBar_SetScale(var);
	elseif cmd == "lock" or cmd == "unlock" or cmd == "auto" then
		FloAspectBar_SetPosition(nil, FloAspectBar, cmd);
	elseif cmd == "borders" then
		FloAspectBar_SetBorders(true);
	elseif cmd == "noborders" then
		FloAspectBar_SetBorders(false);
	elseif cmd == "panic" or cmd == "reset" then
		FloLib_ResetAddon("FloAspectBar");
	else
		DEFAULT_CHAT_FRAME:AddMessage( "FloAspectBar usage :" );
		DEFAULT_CHAT_FRAME:AddMessage( "/fab lock|unlock : lock/unlock position" );
		DEFAULT_CHAT_FRAME:AddMessage( "/fab borders|noborders : show/hide borders" );
		DEFAULT_CHAT_FRAME:AddMessage( "/fab auto : Automatic positioning" );
		DEFAULT_CHAT_FRAME:AddMessage( "/fab scale <num> : Set scale" );
		DEFAULT_CHAT_FRAME:AddMessage( "/fab panic||reset : Reset FloAspectBar" );
		return;
	end
end

function FloAspectBar_SetupSpell(self, spell, pos)

	-- Avoid tainting
	if not InCombatLockdown() then
		local name, button, icon;
		name = self:GetName();
		button = _G[name.."Button"..pos];
		icon = _G[name.."Button"..pos.."Icon"];

		button:SetAttribute("type1", "spell");
		button:SetAttribute("spell", spell.name);

		icon:SetTexture(spell.texture);
	end

	self.spells[pos] = { name = spell.name };
	self.spells[pos] = { id = spell.id, name = spell.name, addName = spell.addName, talented = spell.talented };

end

function FloAspectBar_UpdateState(self, pos)

	local button = _G[self:GetName().."Button"..pos];
	local spell = self.spells[pos];

	if UnitAura(PlayerFrame.unit, spell.name, nil, "PLAYER") then
		button:SetChecked(1);
	else
		button:SetChecked(0);
	end
end

function FloAspectBar_UpdatePosition()

	-- Avoid tainting when in combat
	if ACTIVE_OPTIONS.barSettings.position ~= "auto" or InCombatLockdown() then
		return;
	end

	local yOffset = -3;
	local anchorFrame;

	if not MainMenuBar:IsShown() and not (VehicleMenuBar and VehicleMenuBar:IsShown()) then
		anchorFrame = UIParent;
		yOffset = 110-UIParent:GetHeight();
	else
		anchorFrame = MainMenuBar;
		if ReputationWatchBar:IsShown() and MainMenuExpBar:IsShown() then
			yOffset = yOffset + 9;
		end

		if MainMenuBarMaxLevelBar:IsShown() then
			yOffset = yOffset - 5;
		end

		if SHOW_MULTI_ACTIONBAR_2 then
			yOffset = yOffset + 45;
		end
	end

	FloAspectBar:ClearAllPoints();
	FloAspectBar:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 512/ACTIVE_OPTIONS.scale, yOffset/ACTIVE_OPTIONS.scale);
end

function FloAspectBar_SetBorders(self, visible)

	ACTIVE_OPTIONS.borders = visible;
	if visible or ACTIVE_OPTIONS.barSettings.position == "unlock" then
		FloLib_ShowBorders(FloAspectBar);
	else
		FloLib_HideBorders(FloAspectBar);
	end

end

function FloAspectBar_SetPosition(self, bar, mode)

	local unlocked = (mode == "unlock");

	-- Close all dropdowns
	CloseDropDownMenus();

	if bar.settings then
		local savePoints = bar.settings.position ~= mode;
	        bar.settings.position = mode;
	        DEFAULT_CHAT_FRAME:AddMessage(bar:GetName().." position "..mode);

	        if unlocked then
		        FloLib_ShowBorders(bar);
		        bar:RegisterForDrag("LeftButton");
	        else
		        if ACTIVE_OPTIONS.borders then
			        FloLib_ShowBorders(bar);
		        else
			        FloLib_HideBorders(bar);
		        end
	        end

	        if mode == "auto" then
		        -- Force the auto positionning
		        FloAspectBar_UpdatePosition(bar);
	        else
		        -- Force the game to remember position
		        bar:StartMoving();
		        bar:StopMovingOrSizing();
			if savePoints then
				bar.settings.refPoint = { bar:GetPoint() };
			end
	        end
        end
end

function FloAspectBar_SetScale(scale)

	scale = tonumber(scale);
	if ( not scale or scale <= 0 ) then
		DEFAULT_CHAT_FRAME:AddMessage( "FloAspectBar : scale must be >0 ("..scale..")" );
		return;
	end

	ACTIVE_OPTIONS.scale = scale;

	local v = FloAspectBar;
	local p, a, rp, ox, oy = v:GetPoint();
	local os = v:GetScale();
	v:SetScale(scale);
	if a == nil or a == UIParent or a == MainMenuBar then
		v:SetPoint(p, a, rp, ox*os/scale, oy*os/scale);
	end

end

