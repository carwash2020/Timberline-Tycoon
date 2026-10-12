--!nocheck
-- The store item models PLACED on a plot (BlueprintModels, MachineArt.BuildSkyBin):
-- for each of Barrel, Crate, Glow Wire and Sky Bin the part-built item (left, what
-- the game shows until the mesh id is set) next to the same item wearing its model
-- slot (right), on a 1 stud grid with the footprint outlined, so size, pivot and
-- facing can be compared. Also the ghost (placement preview) of each.
-- Views: 1 all, then a front close-up and a three-quarter per item.
--   bash tools/preview/shoot.sh store-item-models-placed
local ITEMS = { "Barrel", "Crate", "GlowWire", "SkyBin" }

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local Slots = ctx.shared("StoreModelSlots")
		local PlotData = ctx.shared("PlotData")
		local BlueprintModels = ctx.shared("BlueprintModels")
		local MachineArt = ctx.art("MachineArt")
		local TownMeshes = ctx.art("TownMeshes")
		local Common = require("./_common")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 300, C3.fromRGB(110, 160, 80))
		TownMeshes.Enabled = false -- as in the game today (GameConfig.TownMeshes = false)

		local function build(id, ghost)
			if id == "SkyBin" then
				return MachineArt.BuildSkyBin(ghost)
			end
			return BlueprintModels.Build(PlotData.Blueprint(id), ghost)
		end

		local function footprint(id)
			if id == "SkyBin" then
				return V3.new(8, 0, 8)
			end
			local bp = PlotData.Blueprint(id)
			return V3.new(bp.footprint.X, 0, bp.footprint.Y)
		end

		local preview = Slots.PreviewIds
		local cameras = {}
		local x = 0
		local spans = {}
		local total = 0
		for _, id in ipairs(ITEMS) do
			spans[id] = footprint(id).X + 3
			total += spans[id] * 3
		end
		x = -total / 2
		local centres = {}
		for _, id in ipairs(ITEMS) do
			local fp = footprint(id)
			local row = {}
			-- left: the part build (no preview ids); middle: the model; right: its ghost
			for i, mode in ipairs({ "parts", "model", "ghost" }) do
				local cx = x + spans[id] * (i - 0.5)
				Slots.PreviewIds = if mode == "parts" then nil else preview
				local model = build(id, mode == "ghost")
				model:PivotTo(CF.new(cx, 0, 0))
				model.Parent = root
				-- the footprint, outlined on the ground
				for _, edge in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
					local along = edge[1] == 0
					Kit.part(
						root,
						"Footprint",
						V3.new(if along then fp.X else 0.12, 0.06, if along then 0.12 else fp.Z),
						CF.new(cx + edge[1] * fp.X / 2, 0.03, edge[2] * fp.Z / 2),
						C3.fromRGB(255, 240, 120),
						Enum.Material.Neon
					)
				end
				row[i] = cx
			end
			Slots.PreviewIds = preview
			x += spans[id] * 3
			centres[id] = row
		end
		for _, id in ipairs(ITEMS) do
			local mid = centres[id][2]
			local h = if id == "SkyBin" then 9 else 3.4
			local d = footprint(id).X * 1.6 + 5
			table.insert(cameras, {
				pos = { (centres[id][1] + centres[id][3]) / 2, h * 0.7, -d * 1.6 },
				target = { (centres[id][1] + centres[id][3]) / 2, h * 0.3, 0 },
				fov = 40,
				label = id .. " placed: parts, model, ghost (front)",
			})
			table.insert(cameras, {
				pos = { mid + d * 0.7, h * 0.9, -d },
				target = { mid, h * 0.35, 0 },
				fov = 42,
				label = id .. " placed model three-quarter",
			})
		end
		table.insert(cameras, 1, { pos = { 0, 20, -62 }, target = { 0, 3, 0 }, fov = 55, label = "all placed items" })
		return { root = root, cameras = cameras }
	end,
}
