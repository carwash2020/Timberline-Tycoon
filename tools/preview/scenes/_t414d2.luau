--!nocheck
-- T414d-2 roadside greenery: a stretch of road from a player's eye and from above, with (after) or
-- without (before) what Scatter plans: cover, stumps, rocks, saplings, snags. After also draws the
-- keep-out lines (red, 0.4 wide) beside every road in the shot so the clear band can be seen.
-- A helper (files starting with _ are not scenes): T414.scene(ctx, site, withScatter).
local Site = require("./_site")

local T414 = {}

-- id -> { rect, eye (x, z), look (x, z), top (x, z, height), label }
T414.Sites = {
	main = {
		rect = { -420, -60, 60, 220 },
		eye = { -60, 73 },
		near = { -150, 76 },
		nearLook = { -250, 80 },
		look = { -300, 80 },
		top = { -250, 90, 150 },
		label = "Main road at (-60, 73), looking west along the Hills Road",
	},
	mill = {
		rect = { -110, 40, 130, 300 },
		eye = { 0, 215 },
		look = { 0, 330 },
		top = { 0, 200, 190 },
		label = "the Snow Road leaving the town mill",
	},
	hills = {
		rect = { -660, 0, -380, 320 },
		eye = { -440, 84 },
		look = { -600, 110 },
		top = { -540, 120, 150 },
		label = "the Hills Road into the hills",
	},
	snow = {
		rect = { -140, 520, 140, 800 },
		eye = { 0, 560 },
		look = { 0, 700 },
		top = { 0, 660, 150 },
		label = "the Snow Road toward Frostpeak",
	},
	bayou = {
		rect = { -820, -760, -540, -480 },
		eye = { -560, -520 },
		look = { -690, -610 },
		top = { -690, -620, 150 },
		label = "the Bayou Road into the bayou",
	},
	mesa = {
		rect = { 380, -780, 700, -320 },
		eye = { 440, -360 },
		look = { 560, -560 },
		top = { 520, -540, 230 },
		label = "the Mesa Road toward Red Mesa",
	},
}

function T414.scene(ctx, id, withScatter)
	local roblox = ctx.roblox
	local V3, CF = roblox.Vector3, roblox.CFrame
	local site = T414.Sites[id]
	local r = site.rect
	local built = Site.build(ctx, r[1], r[2], r[3], r[4], 3)
	local Kit = ctx.art("Kit")
	local Greenery = ctx.art("Greenery")
	local Scatter = ctx.load("ReplicatedStorage/Shared/World/Scatter")
	local WorldLayout = ctx.load("ReplicatedStorage/Shared/World/WorldLayout")
	local root = built.root
	local function inside(x, z)
		return x > r[1] and x < r[3] and z > r[2] and z < r[4]
	end
	if withScatter then
		local made = {}
		local function put(item, model)
			if model then
				Kit.placeAt(model, CF.new(item.x, item.y, item.z) * CF.Angles(0, item.yaw, 0))
				model.Parent = root
			end
		end
		for _, item in ipairs(Scatter.Cover()) do
			if inside(item.x, item.z) then
				local key = item.kind .. item.region .. item.variant
				made[key] = made[key] or Greenery.Cover(item.kind, item.region, item.variant)
				put(item, made[key]:Clone())
			end
		end
		for _, item in ipairs(Scatter.Built()) do
			if inside(item.x, item.z) then
				put(item, Greenery.Item(item.kind, item.region, item.variant, item.size))
			end
		end
		-- The keep-out lines: red strips along each road's keep-out distance, both sides.
		local lines = roblox.Instance.new("Model")
		lines.Name = "KeepOuts"
		lines.Parent = root
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		for _, road in ipairs(WorldLayout.Roads) do
			local keep = if road.width >= 32 then Scatter.MainKeep else Scatter.BranchKeep
			for i = 1, #road.points - 1 do
				local a, b = road.points[i], road.points[i + 1]
				local len = (b - a).Magnitude
				local dir = (b - a) / len
				for s = 0, len, 6 do
					for _, side in ipairs({ -1, 1 }) do
						local x = a.X + dir.X * s - dir.Y * side * keep
						local z = a.Y + dir.Y * s + dir.X * side * keep
						if inside(x, z) then
							local p = Kit.part(
								lines,
								"Line",
								V3.new(0.5, 0.15, 6),
								CF.lookAt(
									V3.new(x, TerrainGen.HeightAt(x, z) + 0.2, z),
									V3.new(x + dir.X, TerrainGen.HeightAt(x, z) + 0.2, z + dir.Y)
								),
								roblox.Color3.fromRGB(220, 40, 40)
							)
							p.CanCollide = false
						end
					end
				end
			end
		end
	end
	local function eye(x, z, up)
		local e = Site.eye(ctx, x, z)
		e[2] += up or 0
		return e
	end
	built.cameras = {
		{
			pos = eye(site.eye[1], site.eye[2]),
			target = eye(site.look[1], site.look[2], -1),
			label = "eye: " .. site.label,
			fov = 70,
		},
		{
			pos = { site.top[1], site.top[3], site.top[2] + 1 },
			target = { site.top[1], 0, site.top[2] },
			label = "from above: the road and its verge" .. (withScatter and ", keep-outs in red" or ""),
			fov = 60,
		},
	}
	if site.near then
		table.insert(built.cameras, {
			pos = eye(site.near[1], site.near[2]),
			target = eye(site.nearLook[1], site.nearLook[2], -1),
			label = "eye: a walker on the verge, close",
			fov = 70,
		})
	end
	return built
end

return T414
