--!nocheck
-- Shared build for the Lane R region scenes (v1-r-bayou, v1-r-mesa): the
-- region's terrain, every piece of RegionArt exactly as RegionService builds
-- it, the region's trees (Bog Cypress or Ironwood, from WorldPlan.RegionTrees
-- the way SectionTrees plants them), the scatter, and the junction signpost.
-- Bog Cypress and Ironwood have no TreeModels rows on main yet (job 17 wires
-- the uploaded meshes), so their trees are the part-built fallback: that is
-- what the game draws today.
local Common = require("./_common")

local Region = {}

function Region.build(ctx, which)
	local roblox = ctx.roblox
	local V3, CF = roblox.Vector3, roblox.CFrame
	local Kit = ctx.art("Kit")
	local RegionArt = ctx.art("RegionArt")
	local TreeArt = ctx.art("TreeArt")
	local BuildingArt = ctx.art("BuildingArt")
	local WoodData = ctx.shared("WoodData")
	local GrowLogic = ctx.shared("GrowLogic")
	local TreeGen = ctx.shared("TreeGen")
	local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	local RegionScatter = ctx.load("ReplicatedStorage/Shared/Regions/RegionScatter")
	local root = roblox.Instance.new("Model")
	local function ground(x, z)
		return TerrainGen.HeightAt(x, z)
	end
	local function place(model, cf)
		Kit.placeAt(model, cf)
		model.Parent = root
	end

	local biome = if which == "bayou" then "bayou" else "mesa"
	local trees = {}
	local treeSpots = {}
	for _, spot in ipairs(WorldPlan.RegionTrees()) do
		if spot.biome == biome then
			table.insert(treeSpots, spot)
			table.insert(trees, spot.position)
			local def = WoodData.Get(spot.woodId)
			local boot = GrowLogic.BootTree(def, spot.position)
			local skel = if boot.stage < 1 then TreeGen.AtStage(boot.skel, boot.stage) else boot.skel
			place(TreeArt.FromSkeleton(def, skel), CF.new(spot.position) * CF.Angles(0, boot.yaw, 0))
		end
	end

	for _, site in ipairs(RegionScatter.Sites(biome, trees, TerrainGen.RoadClearance)) do
		local piece = RegionArt.Scatter(site.kind, site.seed)
		if piece then
			place(piece, CF.new(site.x, ground(site.x, site.z), site.z) * CF.Angles(0, site.yaw, 0))
		end
	end

	local deckTop
	if which == "bayou" then
		RegionArt.MudAndPools(root, ground)
		local walk = RegionArt.Boardwalk(root, ground)
		deckTop = walk:GetAttribute("DeckTop")
		RegionArt.BaitShack(root, ground, deckTop)
		RegionArt.Lanterns(root, ground, deckTop)
		RegionArt.Landing(root, ground)
		RegionArt.RarePlinth(root, ground)
	else
		RegionArt.QuarryFace(root, ground)
		RegionArt.MesaLanterns(root, ground)
		RegionArt.Overlook(root, ground)
		RegionArt.Arch(root, ground)
		RegionArt.Butte(root, ground)
	end

	-- The junction signpost, as MapBuilder's road signs build it.
	local sign
	for _, s in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
		local first = string.match(s.text, "^[^\n]+")
		if (which == "bayou" and first == "BAYOU") or (which == "mesa" and first == "RED MESA") then
			sign = s
			place(BuildingArt.Signpost(s.text), s.cframe)
		end
	end
	return root,
		{
			V3 = V3,
			ground = ground,
			deckTop = deckTop,
			sign = sign,
			treeSpots = treeSpots,
			terrain = function(x0, z0, x1, z1, step)
				return Common.terrain(ctx, x0, z0, x1, z1, step)
			end,
		}
end

-- A camera aimed at `target` from an offset, as the scenes' lists want it.
function Region.cam(label, pos, target, fov, night)
	return {
		label = label,
		pos = { pos.X, pos.Y, pos.Z },
		target = { target.X, target.Y, target.Z },
		fov = fov,
		night = night,
	}
end

-- A bright fill light for dark views (preview only: the game has no such light).
function Region.fill(ctx, root, at, range, brightness)
	local roblox = ctx.roblox
	local Kit = ctx.art("Kit")
	local part = Kit.part(
		root,
		"PreviewFill",
		roblox.Vector3.new(1, 1, 1),
		roblox.CFrame.new(at),
		roblox.Color3.fromRGB(255, 235, 200),
		roblox.Enum.Material.SmoothPlastic
	)
	Kit.decor(part, false)
	part.Transparency = 1
	local light = roblox.Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = roblox.Color3.fromRGB(255, 226, 190)
	light.Shadows = false
	light.Parent = part
end

return Region
