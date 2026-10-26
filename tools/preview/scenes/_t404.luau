--!nocheck
-- T404 roof clearance: one shop from outside, roof on, on a flat lawn, with the uploaded town meshes on
-- (opts.meshes) or off (parts only). Views: 1 front, 2 forty-five degrees from the door side.
local Common = require("./_common")

local T404 = {}

function T404.scene(opts)
	return {
		build = function(ctx)
			local roblox = ctx.roblox
			local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
			local Kit = ctx.art("Kit")
			local BuildingArt = ctx.art("BuildingArt")
			local root = roblox.Instance.new("Model")
			Common.ground(ctx, root, 700, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))
			ctx.art("TownMeshes").Enabled = opts.meshes == true
			local shop, cx, fz
			if opts.kind == "Sawmill" then
				shop = BuildingArt.Sawmill()
				cx, fz = 0, -11.5 * BuildingArt.Scale.Sawmill
			else
				shop = BuildingArt.Shop(opts.kind, opts.title, C3.fromRGB(table.unpack(opts.accent)))
				local spec = BuildingArt.FacadeSpec(opts.kind, BuildingArt.Scale[opts.kind] or 1, C3.fromRGB(1, 1, 1))
				-- the camera looks at the door; the front view stands straight out from it, the 45 view diagonally
				cx, fz = spec.doorCx, spec.frontZ
			end
			Kit.placeAt(shop, CF.new(0, 0, 0))
			shop.Parent = root
			local d = opts.distance
			local label = opts.title .. if opts.meshes then " (meshes)" else " (parts only)"
			return {
				root = root,
				shadowRadius = 120,
				cameras = {
					{
						pos = { cx, opts.height, fz - d },
						target = { cx, 9, fz },
						fov = 55,
						label = "1 front, " .. label,
					},
					{
						pos = { cx - d * 0.707, opts.height, fz - d * 0.707 },
						target = { cx, 9, fz },
						fov = 55,
						label = "2 forty-five degrees, " .. label,
					},
				},
			}
		end,
	}
end

return T404
