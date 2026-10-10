--!strict
-- Places the mine's rubble, ore anchors, furnace pad, cave lights and
-- secret markers. Rubble is never scripted away: Lane M removes it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local NatureArt = require(ReplicatedStorage.Shared.Art.NatureArt)
local UndergroundData = require(ReplicatedStorage.Shared.World.UndergroundData)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)

local UndergroundBuilder = {}

local ROCK = Color3.fromRGB(90, 84, 76)
local INK = Color3.fromRGB(42, 36, 32)

local function rubbleModel(parent: Instance, rubble: UndergroundData.Rubble): Model
	local model = Instance.new("Model")
	model.Name = "Rubble"
	model:SetAttribute("RubbleId", rubble.id)
	model:SetAttribute("Tier", rubble.tier)
	local cf = CFrame.new(rubble.x, rubble.y + rubble.sy / 2, rubble.z) * CFrame.Angles(0, math.rad(rubble.yaw), 0)
	-- Eight blocks, under the 12-part cap. Anchored, so it stays until Lane M clears it.
	local seeds = { 0, 1.2, -1.1, 0.6, -0.5, 1.4, -1.3, 0.3 }
	for i, ox in ipairs(seeds) do
		local part = Kit.part(
			model,
			"Stone",
			Vector3.new(4, 4, 4),
			cf * CFrame.new((i - 4.5) * 1.6, (i % 3) * 1.2 - 1, ox),
			ROCK,
			Enum.Material.Slate
		)
		part.Anchored = true
	end
	model.Parent = parent
	CollectionService:AddTag(model, "Rubble")
	return model
end

local function anchorPart(parent: Instance, anchor: UndergroundData.Anchor)
	local part = Kit.part(
		parent,
		"MineAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(anchor.x, anchor.y, anchor.z),
		INK,
		Enum.Material.SmoothPlastic
	)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part:SetAttribute("MineAnchor", true)
	part:SetAttribute("Tier", anchor.tier)
end

local function systemOf(id: string): string
	if string.sub(id, 1, 4) == "mine" or id == "hills-cave" or id == "peak-cave" or id == "lava-cave" then
		return "mine"
	end
	return id
end

local function lightsFor(parent: Instance, cave: UndergroundData.Cave, n: number)
	for i = 1, n do
		local angle = (i - 1) / n * math.pi * 2
		local part = Kit.part(
			parent,
			"Lantern",
			Vector3.new(1, 1, 1),
			CFrame.new(cave.x + math.cos(angle) * 8, cave.floorY + cave.height - 4, cave.z + math.sin(angle) * 8),
			Color3.fromRGB(255, 214, 140),
			Enum.Material.Neon
		)
		part.Anchored = true
		part.CanCollide = false
		local light = Instance.new("PointLight")
		light.Brightness = 0.6
		light.Range = 18
		light.Shadows = false
		light.Parent = part
	end
end

function UndergroundBuilder.Build(parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Underground"
	folder.Parent = parent
	for _, rubble in ipairs(UndergroundData.Rubble) do
		rubbleModel(folder, rubble)
	end
	local anchors = Instance.new("Folder")
	anchors.Name = "MineAnchors"
	anchors.Parent = folder
	for _, anchor in ipairs(UndergroundData.MineAnchors) do
		anchorPart(anchors, anchor)
	end
	local site = UndergroundData.FurnaceSite
	local pad = Kit.part(
		folder,
		"FurnaceSite",
		Vector3.new(site.sx, 4, site.sz),
		CFrame.new(site.x, 2, site.z),
		Color3.fromRGB(120, 116, 110),
		Enum.Material.Concrete
	)
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanQuery = true
	pad:SetAttribute("FurnaceSite", true)
	local lit: { [string]: number } = {}
	for _, cave in ipairs(UndergroundData.Caves) do
		local system = systemOf(cave.id)
		local used = lit[system] or 0
		local n = math.min(cave.lights, UndergroundData.PhoneLights - used)
		if n > 0 then
			lightsFor(folder, cave, n)
			lit[system] = used + n
		end
	end
	-- Tunnel lamps: eight, shadows off, along the bore.
	local pts = WorldLayout.TunnelPoints
	local lamps = Instance.new("Folder")
	lamps.Name = "TunnelLights"
	lamps.Parent = folder
	for i = 1, UndergroundData.TunnelLights do
		local u = i / (UndergroundData.TunnelLights + 1)
		local index = math.clamp(math.floor(u * (#pts - 1)) + 1, 1, #pts - 1)
		local a, b = pts[index], pts[index + 1]
		local cf = CFrame.new(a:Lerp(b, 0.5).X, WorldLayout.TunnelFloorY + 16, a:Lerp(b, 0.5).Y)
		local part =
			Kit.part(lamps, "TunnelLamp", Vector3.new(1, 1, 1), cf, Color3.fromRGB(255, 220, 160), Enum.Material.Neon)
		part.Anchored = true
		part.CanCollide = false
		local light = Instance.new("PointLight")
		light.Brightness = 0.5
		light.Range = 28
		light.Shadows = false
		light.Parent = part
	end
	-- The decline's lamps: a few, shadows off, hung from the roof along the
	-- grade so the way down is lit from the door to the chamber.
	local rampLamps = Instance.new("Folder")
	rampLamps.Name = "RampLights"
	rampLamps.Parent = folder
	local samples = UndergroundData.RampSamples
	for i = 1, UndergroundData.Ramp.lights do
		local at = samples[math.clamp(math.floor(i / (UndergroundData.Ramp.lights + 0.5) * #samples) + 1, 1, #samples)]
		local cf = CFrame.new(at.x, at.y + UndergroundData.Ramp.height - 2, at.z)
		local part =
			Kit.part(rampLamps, "RampLamp", Vector3.new(1, 1, 1), cf, Color3.fromRGB(255, 220, 160), Enum.Material.Neon)
		part.Anchored = true
		part.CanCollide = false
		local light = Instance.new("PointLight")
		light.Brightness = 0.6
		light.Range = 26
		light.Shadows = false
		light.Color = Color3.fromRGB(255, 214, 140)
		light.Parent = part
	end
	for _, secret in ipairs(UndergroundData.Secrets) do
		local mark = Kit.part(
			folder,
			"Secret",
			Vector3.new(2, 2, 2),
			CFrame.new(secret.x, 2, secret.z),
			INK,
			Enum.Material.Slate
		)
		mark.Anchored = true
		mark.CanCollide = false
		mark:SetAttribute("SecretId", secret.id)
	end
	UndergroundBuilder.PlaceMouth(parent)
	return folder
end

-- The mine mouth (NatureArt.CaveMouth, Lane G's model) at UndergroundData.MineMouth.
-- The model's door faces -Z and its throat runs to +Z, so it is turned half a
-- circle: the door faces +Z, toward town, and the throat runs to -Z, into the
-- hill and down the ramp (UndergroundData.Ramp). Its Body does not collide;
-- its invisible Collision piece is two pillars and a lintel round the doorway.
-- The pivot sits 0.4 under the ground at the door, so the stone is never
-- left standing on a ledge.
function UndergroundBuilder.MouthCFrame(): CFrame
	local mouth = UndergroundData.MineMouth
	return CFrame.new(mouth.x, UndergroundData.Ramp.top - 0.4, mouth.z) * CFrame.Angles(0, math.pi, 0)
end

function UndergroundBuilder.PlaceMouth(parent: Instance): Model
	local model = NatureArt.CaveMouth()
	model.Name = "MineMouth"
	Kit.placeAt(model, UndergroundBuilder.MouthCFrame())
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent
	CollectionService:AddTag(model, "MineMouth")
	return model
end

return UndergroundBuilder
