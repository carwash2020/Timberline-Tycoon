--!strict
-- NPCService: the townsfolk (Murph, Millie at the sawmill, the shopkeepers,
-- the gondola operator): their models, where they stand and walk, and what
-- they say.
-- (First pass: just Murph, the blocky figure QuestUI needs. The characters
-- workstream replaces this with real rigs and more townsfolk.)
--
-- Contract: a Persistent Model "Murph" under TimberlineMap with parts Head,
-- Beard, Beanie, Torso (PrimaryPart; QuestUI's Talk prompt goes on it),
-- LeftArm, RightArm (QuestUI's portrait clones them).

local NPCService = {}

-- Where Murph stands: by his camp at the spawn, facing it.
NPCService.MurphSpot = CFrame.lookAt(Vector3.new(-8, 0, 30), Vector3.new(0, 0, 40))

local function buildMurph(map: Instance)
	local murph = Instance.new("Model")
	murph.Name = "Murph"
	murph.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local base = NPCService.MurphSpot
	local function limb(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = base * CFrame.new(offset)
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = name == "Torso"
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = murph
		return p
	end
	local skin, flannel, jeans = Color3.fromRGB(234, 184, 146), Color3.fromRGB(170, 40, 35), Color3.fromRGB(55, 70, 110)
	limb("LeftLeg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), jeans)
	limb("RightLeg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), jeans)
	local torso = limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), flannel, Enum.Material.Fabric)
	limb("LeftArm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), flannel, Enum.Material.Fabric)
	limb("RightArm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), flannel, Enum.Material.Fabric)
	limb("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), skin)
	limb(
		"Beard",
		Vector3.new(1.3, 0.9, 0.4),
		Vector3.new(0, 4.25, -0.55),
		Color3.fromRGB(110, 72, 40),
		Enum.Material.Fabric
	)
	limb(
		"Beanie",
		Vector3.new(1.35, 0.55, 1.35),
		Vector3.new(0, 5.4, 0),
		Color3.fromRGB(120, 30, 30),
		Enum.Material.Fabric
	)
	murph.PrimaryPart = torso
	murph.Parent = map
end

function NPCService.Init(mapFolder: Instance)
	buildMurph(mapFolder)
end

return NPCService
