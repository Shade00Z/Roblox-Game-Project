--!nonstrict
-- Server entry point. The only server Script; everything else is a ModuleScript.
-- Each service may define Init() (set up, no yielding) and Start() (runs after every Init).

local Services = script.Parent:WaitForChild("Services")

local ORDER = {
	"PlayerData",
	"PlotService",
	"ShaftService",
	"CrewService",
	"DigService",
	"EggService",
	"GeodeService",
	"ShopService",
	"MovementService",
	-- Phase 2+: "EventService", "SocialService", "QuestService", "Analytics"
}

local loaded = {}
for _, name in ipairs(ORDER) do
	loaded[name] = require(Services:WaitForChild(name))
end

for _, name in ipairs(ORDER) do
	local service = loaded[name]
	if service.Init then
		service.Init()
	end
end

-- PlayerData.Start is last so every service has registered its OnLoaded callback
-- before the first profile loads.
for _, name in ipairs(ORDER) do
	local service = loaded[name]
	if service.Start and name ~= "PlayerData" then
		task.spawn(service.Start)
	end
end
loaded.PlayerData.Start()

print("[Deep Core Colony] Server started")
