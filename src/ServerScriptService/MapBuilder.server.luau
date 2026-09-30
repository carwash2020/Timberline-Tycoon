-- MapBuilder: constructs the Phase 1 world from code at server start.
-- Everything the vertical slice needs: ground, spawn, starter forest
-- (40 oak + 15 birch), sawmill + sell zone, and plot markers for later phases.
-- GameServer waits for the TimberlineMap folder before accepting players.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local TreeService = require(script.Parent.TreeService)

local map = Instance.new("Folder")
map.Name = "TimberlineMap"
map.Parent = workspace

local function box(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, props: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = map
	return p
end

-- Ground (Phase 1: starter area only; the full 3000x3000 world comes later).
box("Ground", Vector3.new(1200, 2, 1200), Vector3.new(0, -1, 0),
	Color3.fromRGB(91, 155, 72), Enum.Material.Grass)

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
local function scatterPositions(count: number, xMin: number, xMax: number, zMin: number, zMax: number, minGap: number)
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
box("MillRoof", Vector3.new(38, 1, 30), Vector3.new(MILL_X, 8.75, MILL_Z), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)

-- Saw prop: stand + big circular blade.
box("SawStand", Vector3.new(3, 3, 2), Vector3.new(MILL_X - 8, 2.5, MILL_Z), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
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
local signBoard = box("MillSign", Vector3.new(14, 3, 0.5), Vector3.new(MILL_X, 10, MILL_Z - 13.2), WOOD, Enum.Material.Wood)
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

-- SellZone: stand inside to sell. Invisible, non-colliding.
box("SellZone", Vector3.new(24, 12, 18), Vector3.new(MILL_X, 6, MILL_Z - 24),
	Color3.fromRGB(255, 255, 255), nil, { Transparency = 1, CanCollide = false })

-- Plot markers for later phases (visual only in Phase 1).
local plotPositions = {
	Vector3.new(150, 0.5, 110),
	Vector3.new(-150, 0.5, 110),
	Vector3.new(150, 0.5, -60),
	Vector3.new(-150, 0.5, -60),
}
for i, pos in ipairs(plotPositions) do
	local pad = box("PlotSpot_" .. i, Vector3.new(120, 1, 120), pos,
		Color3.fromRGB(210, 190, 150), Enum.Material.Sand,
		{ Transparency = 0.85, CanCollide = false })
	CollectionService:AddTag(pad, "PlotSpot")
end

-- Warm afternoon light.
Lighting.ClockTime = 15.5
Lighting.Brightness = 2

print("[MapBuilder] Phase 1 world built: spawn, starter forest, sawmill, sell zone, plot markers.")
