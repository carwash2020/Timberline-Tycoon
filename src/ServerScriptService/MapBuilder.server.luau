--!strict
-- MapBuilder: constructs the Phase 1 world from code at server start.
-- Everything the vertical slice needs: ground, spawn, starter forest
-- (40 oak + 15 birch), a parking lot, sawmill + sell zone, and plot markers
-- for later phases. GameServer waits for the TimberlineMap folder before
-- accepting players.

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
-- forest (-Z).
local SLOT_ROWS, SLOTS_PER_ROW = 3, 8
local slotIndex = 0
for row = 0, SLOT_ROWS - 1 do
	for col = 0, SLOTS_PER_ROW - 1 do
		slotIndex += 1
		local slot = box(
			"ParkingSlot_" .. slotIndex,
			Vector3.new(5, 0.2, 13),
			Vector3.new(16 + col * 7, 0.1, 50 - row * 20),
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

-- Sign (SurfaceGui on both faces so it reads from either side).
local signBoard =
	box("MillSign", Vector3.new(14, 3, 0.5), Vector3.new(MILL_X, 10, MILL_Z - 13.2), WOOD, Enum.Material.Wood)
for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.Parent = signBoard
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Fantasy
	label.TextSize = 42
	label.TextColor3 = Color3.fromRGB(245, 235, 215)
	label.Text = "TIMBERLINE SAWMILL"
	label.Parent = sg
end

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

print("[MapBuilder] Phase 1 world built: spawn, starter forest, parking, sawmill, sell zone, plot markers.")
