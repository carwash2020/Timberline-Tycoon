--!strict
-- MapBuilder: constructs the world from code at server start (placeholder
-- art until the Studio-built world, GAME_DESIGN §14.7).
--   * A 3,000-stud world with every biome that has an area in BiomeData:
--     ground patch, trees (BiomeData.trees), a few landmarks, a road and
--     signpost from town. The Phantom Grove is hidden: no road, no sign.
--   * Town: spawn, parking lot, sawmill + sell zone, the Tool Shed (axes),
--     the Dealership (trucks), Hearth & Home (gear), Murph (the tutorial
--     NPC), and plot markers for later phases.
--   * Starts the day/night clock once the trees are in (WorldClock).
-- GameServer waits for the TimberlineMap folder before accepting players.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TreeService = require(script.Parent.TreeService)
local WorldClock = require(script.Parent.WorldClock)

-- A place made from Studio's "Baseplate" template ships its own Baseplate and
-- SpawnLocation. They would z-fight with our ground and steal spawns, so
-- remove them for this session (changes made while playing never touch the
-- saved place file).
for _, child in ipairs(workspace:GetChildren()) do
	if (child.Name == "Baseplate" and child:IsA("BasePart")) or child:IsA("SpawnLocation") then
		warn(string.format("[MapBuilder] Removing template %s '%s' for this session", child.ClassName, child.Name))
		child:Destroy()
	end
end

local map = Instance.new("Folder")
map.Name = "TimberlineMap"
map.Parent = workspace

local function box(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = map
	return p
end

-- Invisible helper volume: no collisions, no clicks, no touches.
local function ghost(p: BasePart, transparency: number)
	p.Transparency = transparency
	p.CanCollide = false -- must be false before CanQuery can be
	p.CanQuery = false
	p.CanTouch = false
end

local function topLabel(part: BasePart, text: string)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.PixelsPerStud = 20
	sg.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Fantasy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(70, 45, 22)
	label.Text = text
	label.Parent = sg
end

-- A sign's text on both faces, so it reads from either side.
local function signText(part: BasePart, text: string, textSize: number)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Fantasy
		label.TextSize = textSize
		label.TextColor3 = Color3.fromRGB(245, 235, 215)
		label.Text = text
		label.Parent = sg
	end
end

-- Ground: the whole world, WORLD_HALF studs each way from the origin, in
-- four tiles (a part can be at most 2,048 studs long).
local WORLD_HALF = 1500
local GRASS = Color3.fromRGB(91, 155, 72)
for _, sx in ipairs({ -1, 1 }) do
	for _, sz in ipairs({ -1, 1 }) do
		box(
			"Ground",
			Vector3.new(WORLD_HALF, 2, WORLD_HALF),
			Vector3.new(sx * WORLD_HALF / 2, -1, sz * WORLD_HALF / 2),
			GRASS,
			Enum.Material.Grass
		)
	end
end
-- Invisible walls at the edge, so nobody drives off the world.
for _, edge in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
	local ex, ez = edge[1], edge[2]
	local wall = box(
		"WorldEdge",
		Vector3.new(if ex ~= 0 then 2 else WORLD_HALF * 2, 60, if ez ~= 0 then 2 else WORLD_HALF * 2),
		Vector3.new(ex * WORLD_HALF, 30, ez * WORLD_HALF),
		GRASS
	)
	wall.Transparency = 1
	wall.CanQuery = false
end

-- Spawn at the starter-forest edge.
local spawn = Instance.new("SpawnLocation")
spawn.Name = "SpawnLocation"
spawn.Size = Vector3.new(6, 1, 6)
spawn.Position = Vector3.new(0, 0.5, 40)
spawn.Anchored = true
spawn.Neutral = true
spawn.Color = Color3.fromRGB(160, 160, 160)
spawn.Material = Enum.Material.Concrete
spawn.Parent = map

-- Points at least `minGap` apart inside a ring (inner..outer radius)
-- around (cx, cz), also clear of every point already in `taken` (which
-- gains the new ones). Fewer than `count` if the ring is too crowded.
local function scatterInRing(
	count: number,
	cx: number,
	cz: number,
	inner: number,
	outer: number,
	minGap: number,
	taken: { Vector3 }
): { Vector3 }
	local pts: { Vector3 } = {}
	local tries = 0
	while #pts < count and tries < count * 80 do
		tries += 1
		local angle = math.random() * math.pi * 2
		local r = math.sqrt(inner * inner + math.random() * (outer * outer - inner * inner)) -- even spread
		local x, z = cx + math.cos(angle) * r, cz + math.sin(angle) * r
		local clear = true
		for _, q in ipairs(taken) do
			local dx, dz = x - q.X, z - q.Z
			if dx * dx + dz * dz < minGap * minGap then
				clear = false
				break
			end
		end
		if clear then
			local p = Vector3.new(x, 0, z)
			table.insert(pts, p)
			table.insert(taken, p)
		end
	end
	return pts
end

local function disc(
	name: string,
	x: number,
	z: number,
	radius: number,
	y: number,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder -- axis X, turned upright below
	p.Size = Vector3.new(0.2, radius * 2, radius * 2)
	p.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.Parent = map
	return p
end

local SAWMILL = Vector3.new(0, 0, 110)

-- Landmarks on the far side of a biome (away from town, so they never
-- block the road in). Returns the radius to keep clear of trees.
local function decorate(biome: BiomeData.BiomeDef): number
	local area = biome.area :: { x: number, z: number, radius: number }
	local towardTown = math.atan2(SAWMILL.Z - area.z, SAWMILL.X - area.x)
	local function farSide(i: number, n: number): (number, number)
		local angle = towardTown + math.pi / 2 + math.pi * (i - 0.5) / n
		return area.x + math.cos(angle) * (area.radius + 18), area.z + math.sin(angle) * (area.radius + 18)
	end
	if biome.id == "hills" or biome.id == "snow" then
		-- Rolling mounds (or snowdrifts) around the far rim.
		local color = if biome.id == "hills" then Color3.fromRGB(70, 125, 55) else Color3.fromRGB(235, 242, 248)
		local material = if biome.id == "hills" then Enum.Material.Grass else Enum.Material.Snow
		for i = 1, 7 do
			local x, z = farSide(i, 7)
			local size = 40 + (i % 3) * 14
			local mound = Instance.new("Part")
			mound.Name = "Mound"
			mound.Shape = Enum.PartType.Ball
			mound.Size = Vector3.new(size, size, size)
			mound.Position = Vector3.new(x, -size * 0.3, z) -- mostly buried
			mound.Color = color
			mound.Material = material
			mound.Anchored = true
			mound.Parent = map
		end
		return 0
	elseif biome.id == "volcano" then
		-- The cone: stacked rock rings with a lava crater on top.
		local rock = Color3.fromRGB(45, 38, 35)
		for i, radius in ipairs({ 55, 44, 33, 22 }) do
			local ring = disc("VolcanoCone", area.x, area.z, radius, 7.5 + (i - 1) * 15, rock, Enum.Material.Basalt)
			ring.Size = Vector3.new(15, radius * 2, radius * 2)
		end
		local crater = disc("Crater", area.x, area.z, 16, 60.2, Color3.fromRGB(255, 106, 26), Enum.Material.Neon)
		crater.CanCollide = false
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 120, 40)
		glow.Range = 60
		glow.Brightness = 3
		glow.Parent = crater
		return 65
	elseif biome.id == "grove" then
		-- Glowing mushrooms: the grove's tell at night.
		for i = 1, 12 do
			local angle = i / 12 * math.pi * 2
			local r = area.radius * (0.3 + (i % 4) * 0.18)
			local cap = Instance.new("Part")
			cap.Name = "GlowCap"
			cap.Shape = Enum.PartType.Ball
			cap.Size = Vector3.new(1.6, 1.6, 1.6)
			cap.Position = Vector3.new(area.x + math.cos(angle) * r, 0.5, area.z + math.sin(angle) * r)
			cap.Color = Color3.fromRGB(80, 230, 210)
			cap.Material = Enum.Material.Neon
			cap.Anchored = true
			cap.CanCollide = false
			cap.Parent = map
		end
		return 0
	end
	return 0
end

-- Lava pools on the Volcano (looks only; the ground itself burns).
local function lavaPools(biome: BiomeData.BiomeDef, taken: { Vector3 })
	local area = biome.area :: { x: number, z: number, radius: number }
	for _, pos in ipairs(scatterInRing(6, area.x, area.z, 75, area.radius - 20, 30, taken)) do
		local pool = disc("LavaPool", pos.X, pos.Z, 6, 0.12, Color3.fromRGB(255, 90, 26), Enum.Material.Neon)
		ghost(pool, 0)
	end
end

-- Every biome with an area: ground patch, landmarks, trees.
for _, biome in ipairs(BiomeData.All()) do
	local area = biome.area
	if area then
		local ground = biome.ground
		if ground then
			local patch = disc(
				biome.id .. "Ground",
				area.x,
				area.z,
				area.radius,
				0.05,
				Color3.fromHex(ground.color),
				Enum.Material:FromName(ground.material) or Enum.Material.Grass
			)
			ghost(patch, 0) -- players and trucks stay on the real ground under it
		end
		local clear = decorate(biome)
		local taken: { Vector3 } = {}
		if biome.id == "volcano" then
			lavaPools(biome, taken)
		end
		-- Plant woods in a fixed order so every server builds the same mix.
		local woodIds: { string } = {}
		for woodId in pairs(biome.trees or {}) do
			table.insert(woodIds, woodId)
		end
		table.sort(woodIds)
		for _, woodId in ipairs(woodIds) do
			local count = (biome.trees :: { [string]: number })[woodId]
			for _, pos in ipairs(scatterInRing(count, area.x, area.z, clear, area.radius - 6, 9, taken)) do
				TreeService.SpawnTree(woodId, CFrame.new(pos))
			end
		end
	end
end

-- Parking lot east of spawn: one slot per player, so trucks never spawn
-- inside each other. VehicleService claims slots by Index. Trucks face the
-- forest (-Z). Slots are sized for the biggest truck (the Logging Rig,
-- about 6 x 24 studs), so no two parked trucks can overlap.
local SLOT_ROWS, SLOTS_PER_ROW = 3, 8
local slotIndex = 0
for row = 0, SLOT_ROWS - 1 do
	for col = 0, SLOTS_PER_ROW - 1 do
		slotIndex += 1
		local slot = box(
			"ParkingSlot_" .. slotIndex,
			Vector3.new(6.5, 0.2, 25),
			Vector3.new(18 + col * 8, 0.1, 56 - row * 28),
			Color3.fromRGB(150, 140, 125),
			Enum.Material.Slate
		)
		slot:SetAttribute("Index", slotIndex)
		CollectionService:AddTag(slot, "ParkingSlot")
	end
end

-- Sawmill (north of spawn). Open front faces -Z toward the spawn.
local WOOD = Color3.fromRGB(101, 67, 33)
local WOOD_DARK = Color3.fromRGB(70, 45, 22)
local MILL_X, MILL_Z = 0, 110

box("MillFloor", Vector3.new(34, 1, 26), Vector3.new(MILL_X, 0.5, MILL_Z), WOOD, Enum.Material.WoodPlanks)
box("MillBackWall", Vector3.new(34, 7, 1), Vector3.new(MILL_X, 4.5, MILL_Z + 12.5), WOOD_DARK, Enum.Material.Wood)
box("MillWallL", Vector3.new(1, 7, 26), Vector3.new(MILL_X - 16.5, 4.5, MILL_Z), WOOD_DARK, Enum.Material.Wood)
box("MillWallR", Vector3.new(1, 7, 26), Vector3.new(MILL_X + 16.5, 4.5, MILL_Z), WOOD_DARK, Enum.Material.Wood)
box("MillPillarL", Vector3.new(2, 7, 1), Vector3.new(MILL_X - 8, 4.5, MILL_Z - 12.5), WOOD_DARK, Enum.Material.Wood)
box("MillPillarR", Vector3.new(2, 7, 1), Vector3.new(MILL_X + 8, 4.5, MILL_Z - 12.5), WOOD_DARK, Enum.Material.Wood)
box("MillHeader", Vector3.new(34, 1.5, 1), Vector3.new(MILL_X, 7.75, MILL_Z - 12.5), WOOD_DARK, Enum.Material.Wood)
box(
	"MillRoof",
	Vector3.new(38, 1, 30),
	Vector3.new(MILL_X, 8.75, MILL_Z),
	Color3.fromRGB(120, 80, 50),
	Enum.Material.Wood
)

-- Saw prop: stand + big circular blade.
box(
	"SawStand",
	Vector3.new(3, 3, 2),
	Vector3.new(MILL_X - 8, 2.5, MILL_Z),
	Color3.fromRGB(90, 60, 40),
	Enum.Material.Wood
)
local blade = Instance.new("Part")
blade.Name = "SawBlade"
blade.Shape = Enum.PartType.Cylinder
blade.Size = Vector3.new(0.4, 6, 6)
blade.Position = Vector3.new(MILL_X - 8, 5.5, MILL_Z)
blade.Color = Color3.fromRGB(170, 170, 175)
blade.Material = Enum.Material.Metal
blade.Anchored = true
blade.Parent = map

-- Decorative log piles.
for _, offset in ipairs({ Vector3.new(8, 4), Vector3.new(8, -2) }) do
	for j = 1, 3 do
		local log = Instance.new("Part")
		log.Name = "DecorLog"
		log.Shape = Enum.PartType.Cylinder
		log.Size = Vector3.new(4, 1.2, 1.2)
		log.Color = Color3.fromRGB(122, 82, 48)
		log.Material = Enum.Material.Wood
		log.Anchored = true
		log.CFrame = CFrame.new(MILL_X + offset.X, 1.6, MILL_Z + offset.Y + (j - 2) * 1.3)
		log.Parent = map
	end
end

local signBoard =
	box("MillSign", Vector3.new(14, 3, 0.5), Vector3.new(MILL_X, 10, MILL_Z - 13.2), WOOD, Enum.Material.Wood)
signText(signBoard, "TIMBERLINE SAWMILL", 42)

-- SellZone: stand (or park) inside to sell. The volume itself is invisible;
-- a painted pad on the ground shows players where it is. Both live in a
-- Persistent model so they're always streamed in on every client (the
-- client-side "Sell logs" prompt hangs off SellZone).
local sellArea = Instance.new("Model")
sellArea.Name = "SellArea"
sellArea.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
sellArea.Parent = map

local sellZone = box("SellZone", Vector3.new(24, 12, 18), Vector3.new(MILL_X, 6, MILL_Z - 24), Color3.new(1, 1, 1))
ghost(sellZone, 1)
sellZone.Parent = sellArea
local sellPoint = Instance.new("Attachment") -- where the client's "Sell logs" prompt appears
sellPoint.Name = "SellPoint"
sellPoint.Position = Vector3.new(0, -2.5, 0)
sellPoint.Parent = sellZone

local sellPad = box(
	"SellPad",
	Vector3.new(24, 0.2, 18),
	Vector3.new(MILL_X, 0.1, MILL_Z - 24),
	Color3.fromRGB(214, 170, 92),
	Enum.Material.WoodPlanks
)
sellPad.Parent = sellArea
topLabel(sellPad, "SELL LOGS HERE")

-- Shops: small open-front buildings facing -Z (toward spawn). Each is a
-- Persistent model, so every client always has it, with a Counter whose
-- "ShopPoint" attachment is where the client's "Browse" prompt appears and
-- what the server measures purchase range from (ShopService).
local function shopBuilding(name: string, center: Vector3, sign: string, roofColor: Color3): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = map
	local function part(partName: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): Part
		local p = box(partName, size, center + offset, color, material)
		p.Parent = model
		return p
	end
	part("Floor", Vector3.new(16, 1, 12), Vector3.new(0, 0.5, 0), WOOD, Enum.Material.WoodPlanks)
	part("BackWall", Vector3.new(16, 8, 1), Vector3.new(0, 5, 5.5), WOOD_DARK, Enum.Material.Wood)
	part("WallL", Vector3.new(1, 8, 12), Vector3.new(-7.5, 5, 0), WOOD_DARK, Enum.Material.Wood)
	part("WallR", Vector3.new(1, 8, 12), Vector3.new(7.5, 5, 0), WOOD_DARK, Enum.Material.Wood)
	part("Roof", Vector3.new(18, 1, 14), Vector3.new(0, 9.5, 0), roofColor, Enum.Material.Wood)
	local counter = part("Counter", Vector3.new(10, 3, 2), Vector3.new(0, 2.5, 1), WOOD, Enum.Material.Wood)
	local point = Instance.new("Attachment")
	point.Name = "ShopPoint"
	point.Position = Vector3.new(0, 0, -1.5) -- the customer's side
	point.Parent = counter
	local board = part("Sign", Vector3.new(12, 2.5, 0.5), Vector3.new(0, 11.25, -6.5), WOOD, Enum.Material.Wood)
	signText(board, sign, 36)
	model.PrimaryPart = counter
	return model
end

-- Tool Shed (axe shop), west of the sawmill, with three axes on the back wall.
local toolShed = shopBuilding("ToolShed", Vector3.new(-45, 0, 100), "TOOL SHED", Color3.fromRGB(150, 62, 44))
for i, color in ipairs({ Color3.fromRGB(167, 173, 180), Color3.fromRGB(94, 102, 112), Color3.fromRGB(225, 181, 48) }) do
	local x = -45 + (i - 2) * 4
	local handle = box("RackHandle", Vector3.new(0.5, 3, 0.5), Vector3.new(x, 5, 104.6), Color3.fromRGB(122, 82, 48))
	handle.Material = Enum.Material.Wood
	handle.Parent = toolShed
	local head = box("RackHead", Vector3.new(2, 1.2, 0.4), Vector3.new(x + 0.6, 6, 104.6), color, Enum.Material.Metal)
	head.Parent = toolShed
end

-- Dealership (trucks), east of the sawmill, across from the Tool Shed.
local dealership = shopBuilding("Dealership", Vector3.new(45, 0, 100), "DEALERSHIP", Color3.fromRGB(47, 109, 181))
for i, color in ipairs({ Color3.fromRGB(47, 109, 181), Color3.fromRGB(217, 162, 27), Color3.fromRGB(178, 58, 38) }) do
	-- Paint swatches on the back wall: the colours on sale.
	local swatch = box("PaintSwatch", Vector3.new(2, 2, 0.3), Vector3.new(45 + (i - 2) * 3.5, 5.5, 104.7), color)
	swatch.Material = Enum.Material.Metal
	swatch.Parent = dealership
end

-- Hearth & Home (biome gear), west of the Tool Shed. A lantern and a coat
-- hang on the back wall.
local hearth = shopBuilding("HearthAndHome", Vector3.new(-80, 0, 100), "HEARTH & HOME", Color3.fromRGB(122, 90, 60))
local lantern = box("LanternProp", Vector3.new(1, 1.4, 1), Vector3.new(-82, 5.5, 104.6), Color3.fromRGB(242, 193, 78))
lantern.Material = Enum.Material.Neon
lantern.Parent = hearth
local lanternLight = Instance.new("PointLight")
lanternLight.Color = Color3.fromRGB(255, 214, 140)
lanternLight.Range = 12
lanternLight.Parent = lantern
local coat = box("CoatProp", Vector3.new(2.2, 3, 0.4), Vector3.new(-77.5, 5, 104.6), Color3.fromRGB(92, 135, 184))
coat.Material = Enum.Material.Fabric
coat.Parent = hearth

---------------------------------------------------------------------------
-- Roads and signposts out to the biomes
---------------------------------------------------------------------------

local ROAD_COLOR = Color3.fromRGB(150, 118, 82)

-- A dirt road for looks: trucks drive on the flat ground under it, so
-- there's no lip to snag on.
local function road(name: string, x1: number, z1: number, x2: number, z2: number)
	local from, to = Vector3.new(x1, 0.1, z1), Vector3.new(x2, 0.1, z2)
	local p = box(name, Vector3.new(10, 0.1, (to - from).Magnitude), (from + to) / 2, ROAD_COLOR, Enum.Material.Ground)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	ghost(p, 0)
end

-- A post with a board facing (towardX, towardZ); text scales to fit.
local function signpost(name: string, x: number, z: number, towardX: number, towardZ: number, text: string)
	local post = box(name .. "Post", Vector3.new(0.6, 7, 0.6), Vector3.new(x, 3.5, z), WOOD_DARK, Enum.Material.Wood)
	post.CanCollide = false
	local board = box(name, Vector3.new(9, 4, 0.4), Vector3.new(x, 7, z), WOOD, Enum.Material.Wood)
	board.CFrame = CFrame.lookAt(Vector3.new(x, 7, z), Vector3.new(towardX, 7, towardZ))
	board.CanCollide = false
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.PixelsPerStud = 40
		sg.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Fantasy
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(245, 235, 215)
		label.Text = text
		label.Parent = sg
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.05, 0)
		pad.PaddingRight = UDim.new(0.05, 0)
		pad.PaddingTop = UDim.new(0.05, 0)
		pad.PaddingBottom = UDim.new(0.05, 0)
		pad.Parent = label
	end
end

-- "THE HILLS\npine · maple" (+ the gear it needs)
local function biomeSign(biome: BiomeData.BiomeDef): string
	local woods: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		if (biome.trees or {})[wood.id] then
			table.insert(woods, string.lower(wood.displayName))
		end
	end
	local text = string.upper(biome.displayName) .. "\n" .. table.concat(woods, " · ")
	local gearId = biome.requiresGear or (if biome.slowdown then biome.slowdown.removedBy else nil)
	local gear = if gearId then ItemCatalog.GetGear(gearId) else nil
	if gear then
		text ..= "\nBring: " .. gear.displayName
	end
	return text
end

-- Each road runs from town to where it meets the biome's edge, and ends in
-- a signpost facing back toward town. (The Phantom Grove has none.)
type Route = { biome: string, from: Vector2 }
local ROUTES: { Route } = {
	{ biome = "hills", from = Vector2.new(-20, 20) }, -- west, between the plot markers
	{ biome = "snow", from = Vector2.new(0, 128) }, -- north, from behind the sawmill
	{ biome = "volcano", from = Vector2.new(25, 130) }, -- north-east
}
local distances: { string } = {}
for _, route in ipairs(ROUTES) do
	local biome = BiomeData.Get(route.biome)
	local area = if biome then biome.area else nil
	if biome and area then
		local center = Vector2.new(area.x, area.z)
		local dir = (center - route.from).Unit
		local edge = center - dir * (area.radius - 10) -- a little way in
		road(biome.id .. "Road", route.from.X, route.from.Y, edge.X, edge.Y)
		signpost(
			biome.id .. "Sign",
			edge.X - dir.X * 14 + dir.Y * 9,
			edge.Y - dir.Y * 14 - dir.X * 9,
			route.from.X,
			route.from.Y,
			biomeSign(biome)
		)
		table.insert(distances, string.format("%s  %d", biome.displayName, biome.haulStuds or 0))
	end
end
-- Where the roads start: a signpost by the spawn with every destination.
signpost("TownSign", -16, 44, 0, 40, "TO THE WOODS\n" .. table.concat(distances, "\n"))

-- Murph, the retired lumberjack who runs the tutorial (GAME_DESIGN §11),
-- stands just ahead of the spawn, facing it. A blocky figure (no Humanoid:
-- he doesn't walk yet). Persistent, so QuestUI can always find him and put
-- its "Talk" prompt on his Torso.
do
	local murph = Instance.new("Model")
	murph.Name = "Murph"
	murph.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	murph.Parent = map
	local base = CFrame.lookAt(Vector3.new(-8, 0, 30), Vector3.new(0, 0, 40)) -- facing the spawn
	local SKIN = Color3.fromRGB(234, 184, 146)
	local FLANNEL = Color3.fromRGB(170, 40, 35)
	local JEANS = Color3.fromRGB(55, 70, 110)
	local BEARD = Color3.fromRGB(110, 72, 40)
	local function limb(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
		local p = box(name, size, Vector3.zero, color, material or Enum.Material.SmoothPlastic)
		p.CFrame = base * CFrame.new(offset)
		p.CanCollide = name == "Torso" -- one solid part so players don't walk through him
		p.Parent = murph
		return p
	end
	limb("LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), JEANS)
	limb("RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), JEANS)
	local torso = limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), FLANNEL, Enum.Material.Fabric)
	limb("LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), FLANNEL, Enum.Material.Fabric)
	limb("RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), FLANNEL, Enum.Material.Fabric)
	local head = limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), SKIN)
	limb("Beard", Vector3.new(1.3, 0.9, 0.4), Vector3.new(0, 4.25, -0.55), BEARD, Enum.Material.Fabric)
	limb(
		"Beanie",
		Vector3.new(1.35, 0.55, 1.35),
		Vector3.new(0, 5.4, 0),
		Color3.fromRGB(120, 30, 30),
		Enum.Material.Fabric
	)
	murph.PrimaryPart = torso

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(160, 40)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 60
	tag.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Fantasy
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(245, 235, 215)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = "Murph"
	nameLabel.Parent = tag
	local role = Instance.new("TextLabel")
	role.Position = UDim2.fromScale(0, 0.6)
	role.Size = UDim2.fromScale(1, 0.4)
	role.BackgroundTransparency = 1
	role.Font = Enum.Font.Gotham
	role.TextScaled = true
	role.TextColor3 = Color3.fromRGB(245, 235, 215)
	role.TextStrokeTransparency = 0.6
	role.Text = "Retired lumberjack"
	role.Parent = tag
end

-- Plot markers for later phases (visual only in Phase 1).
local plotPositions = {
	Vector3.new(170, 0.15, 110),
	Vector3.new(-170, 0.15, 110),
	Vector3.new(170, 0.15, -60),
	Vector3.new(-170, 0.15, -60),
}
for i, pos in ipairs(plotPositions) do
	local pad =
		box("PlotSpot_" .. i, Vector3.new(120, 0.2, 120), pos, Color3.fromRGB(210, 190, 150), Enum.Material.Sand)
	ghost(pad, 0.85)
	CollectionService:AddTag(pad, "PlotSpot")
end

-- Warm light; the time of day comes from WorldClock.
Lighting.Brightness = 2
WorldClock.Start()

print("[MapBuilder] World built: biomes, roads, town (sawmill, Tool Shed, Dealership, Hearth & Home), Murph, plots.")
