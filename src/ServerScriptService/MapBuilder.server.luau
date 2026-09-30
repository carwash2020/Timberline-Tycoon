--!strict
-- MapBuilder: constructs the Phase 1 world from code at server start.
-- Ground, spawn, starter forest (40 oak + 15 birch), a parking lot,
-- sawmill + sell zone, the Tool Shed (axes), the Dealership (trucks),
-- Murph (the tutorial NPC), and plot markers for later phases. GameServer waits for the
-- TimberlineMap folder before accepting players.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local TreeService = require(script.Parent.TreeService)

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

-- Ground (Phase 1: starter area only; the full 3000x3000 world comes later).
box("Ground", Vector3.new(1200, 2, 1200), Vector3.new(0, -1, 0), Color3.fromRGB(91, 155, 72), Enum.Material.Grass)

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

-- Starter forest: oak + birch south of spawn, scattered with spacing.
local function scatterPositions(
	count: number,
	xMin: number,
	xMax: number,
	zMin: number,
	zMax: number,
	minGap: number
): { Vector3 }
	local pts: { Vector3 } = {}
	local tries = 0
	while #pts < count and tries < count * 60 do
		tries += 1
		local x = xMin + math.random() * (xMax - xMin)
		local z = zMin + math.random() * (zMax - zMin)
		local clear = true
		for _, q in ipairs(pts) do
			local dx, dz = x - q.X, z - q.Z
			if dx * dx + dz * dz < minGap * minGap then
				clear = false
				break
			end
		end
		if clear then
			table.insert(pts, Vector3.new(x, 0, z))
		end
	end
	return pts
end

for _, pos in ipairs(scatterPositions(40, -90, 90, -170, -30, 9)) do
	TreeService.SpawnTree("oak", CFrame.new(pos))
end
for _, pos in ipairs(scatterPositions(15, -90, 90, -170, -30, 9)) do
	TreeService.SpawnTree("birch", CFrame.new(pos))
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
	Vector3.new(150, 0.15, 110),
	Vector3.new(-150, 0.15, 110),
	Vector3.new(150, 0.15, -60),
	Vector3.new(-150, 0.15, -60),
}
for i, pos in ipairs(plotPositions) do
	local pad =
		box("PlotSpot_" .. i, Vector3.new(120, 0.2, 120), pos, Color3.fromRGB(210, 190, 150), Enum.Material.Sand)
	ghost(pad, 0.85)
	CollectionService:AddTag(pad, "PlotSpot")
end

-- Warm afternoon light.
Lighting.ClockTime = 15.5
Lighting.Brightness = 2

print("[MapBuilder] World built: spawn, forest, parking, sawmill, sell zone, Tool Shed, Dealership, Murph, plots.")
