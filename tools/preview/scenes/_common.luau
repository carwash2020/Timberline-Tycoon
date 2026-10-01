--!nocheck
-- Shared helpers for preview scenes (tools/preview/scenes/*.luau).

local Common = {}

function Common.ground(ctx, root, size, color, center)
	local roblox = ctx.roblox
	local Kit = ctx.art("Kit")
	Kit.part(
		root,
		"Ground",
		roblox.Vector3.new(size, 1, size),
		roblox.CFrame.new(center or roblox.Vector3.new(0, -0.5, 0)),
		color or roblox.Color3.fromRGB(110, 160, 80),
		roblox.Enum.Material.Grass
	)
end

-- The world's terrain over a rectangle, sampled every `step` studs.
function Common.terrain(ctx, x0, z0, x1, z1, step)
	local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
	local colors = {}
	for name, c in pairs(TerrainGen.MaterialColors) do
		colors[name] = c:ToHex()
	end
	return {
		x0 = x0,
		z0 = z0,
		x1 = x1,
		z1 = z1,
		step = step,
		colors = colors,
		waterColor = "#3f9ac2",
		sample = function(x, z)
			return TerrainGen.Sample(x, z)
		end,
	}
end

return Common
