--!strict
-- RegionFX: the Bayou's fireflies (Lane R), client only. A few small
-- glowing specks drift round the local player while they are in the Bayou
-- after dark or at dusk. Nothing collides, nothing is queried or touched, no
-- light is added, and the count is a tenth of the device's critter part cap
-- (QualityBudgets.MaxCritterParts: 24 on high and medium, 12 on low), so the
-- phone tier stays inside its budget. The mud's slowdown is the server's
-- (BiomeService); this module only dresses the place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BayouData = require(ReplicatedStorage.Shared.Regions.BayouData)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local Quality = require(script.Parent.Quality)
local LightingController = require(script.Parent.LightingController)

local RegionFX = {}

-- How many fireflies a device gets: a tenth of its critter part cap, never more
-- than the Bayou's own budget.
function RegionFX.Count(partCap: number): number
	if type(partCap) ~= "number" or partCap ~= partCap or partCap < 0 then
		return 0
	end
	return math.clamp(math.floor(partCap / 10), 0, BayouData.Budgets.fireflies)
end

-- Whether it is dim enough for fireflies (dusk, night or the small hours).
function RegionFX.Wanted(biomeId: string, daylight: number): boolean
	return biomeId == "bayou" and daylight < 0.55
end

function RegionFX.Start()
	local folder = Instance.new("Folder")
	folder.Name = "RegionFX"
	folder.Parent = workspace
	local flies: { Part } = {}
	local seeds: { number } = {}
	local function count(n: number)
		while #flies < n do
			local p = Instance.new("Part")
			p.Name = "Firefly"
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(0.3, 0.3, 0.3)
			p.Color = Color3.fromRGB(255, 226, 120)
			p.Material = Enum.Material.Neon
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Transparency = 1
			p.Parent = folder
			table.insert(flies, p)
			table.insert(seeds, #flies * 12.9898)
		end
	end
	local sinceCosmetic = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCosmetic += dt
		if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
			return
		end
		sinceCosmetic = 0
		local camera = workspace.CurrentCamera
		local env = LightingController.Environment()
		local want = RegionFX.Wanted(env.biomeId, env.daylight)
		local n = if want then RegionFX.Count(QualityBudgets.CritterPartCap(Quality.Budget().Tier)) else 0
		count(n)
		local now = os.clock()
		for i, p in ipairs(flies) do
			if i > n or camera == nil then
				p.Transparency = 1
			else
				local s = seeds[i]
				local at = camera.CFrame.Position
				-- A slow lazy figure round a point 8 to 26 studs off, 1 to 5 up.
				local a = s + now * (0.12 + (i % 5) * 0.03)
				local r = 8 + (i % 7) * 2.6
				p.CFrame = CFrame.new(
					at.X + math.cos(a) * r + math.sin(now * 0.7 + s) * 2,
					at.Y - 2.5 + 1 + (i % 5) + math.sin(now * 0.9 + s * 2),
					at.Z + math.sin(a) * r + math.cos(now * 0.6 + s) * 2
				)
				-- A slow blink.
				p.Transparency = 0.15 + 0.8 * (0.5 + 0.5 * math.sin(now * 1.7 + s * 3))
			end
		end
	end)
end

return RegionFX
