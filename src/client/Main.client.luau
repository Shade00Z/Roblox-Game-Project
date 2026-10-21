--!nonstrict
-- Client entry point. The only LocalScript; everything else is a ModuleScript.

local ProximityPromptService = game:GetService("ProximityPromptService")

local Client = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local HUD = require(Client:WaitForChild("UI"):WaitForChild("HUD"))
local Shops = require(Client.UI:WaitForChild("Shops"))
local AwayScreen = require(Client.UI:WaitForChild("AwayScreen"))
local EggShop = require(Client.UI:WaitForChild("EggShop"))
local ShaftRenderer = require(Client:WaitForChild("Controllers"):WaitForChild("ShaftRenderer"))
local Walkways = require(Client.Controllers:WaitForChild("Walkways"))

HUD.Init()
Shops.Init()
AwayScreen.Init()
EggShop.Init()
ShaftRenderer.Init(HUD.Toast)
Walkways.Init()

Remotes.State.OnClientEvent:Connect(function(state)
	HUD.Update(state)
	Shops.Update(state)
	EggShop.Update(state)
	ShaftRenderer.Update(state)
end)

Remotes.AwaySummary.OnClientEvent:Connect(AwayScreen.Show)
Remotes.Notify.OnClientEvent:Connect(HUD.Toast)
Remotes.CrackResult.OnClientEvent:Connect(HUD.ShowCrack)
Remotes.DigFind.OnClientEvent:Connect(HUD.ShowFind)
Remotes.HatchResult.OnClientEvent:Connect(EggShop.ShowHatch)

-- prompts created by the server that open client-side panels
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local action = prompt:GetAttribute("Action")
	if action == "OpenUpgrades" then
		Shops.Open()
	elseif action == "OpenHatchery" then
		EggShop.Open()
	elseif action == "OpenRack" then
		HUD.FlashRack()
	end
end)
