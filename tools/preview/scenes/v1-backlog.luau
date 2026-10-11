--!nocheck
-- Job 17: every asset wired to a backlog mesh, drawn with the REAL meshes
-- from several angles. Needs the preview manifest and piece centres:
--   python3 tools/preview/backlog_manifest.py
--   PREVIEW_MESHES=preview/backlog-meshes.json bash tools/preview/shoot.sh v1-backlog
-- (Lune has no mesh pivots, so each piece is moved to its GLB place, the way
-- Studio's authored pivots leave it.) Views are named in each camera's label.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local BoxArt = ctx.art("BoxArt")
		local BoxSize = ctx.shared("BoxSize")
		local RobuxShelf = ctx.shared("RobuxShelf")
		local TreeArt = ctx.art("TreeArt")
		local TreeGen = ctx.shared("TreeGen")
		local WoodData = ctx.shared("WoodData")
		assert(fs.isFile("preview/backlog-centres.json"), "run tools/preview/backlog_manifest.py")
		local centres = serde.decode("json", fs.readFile("preview/backlog-centres.json"))
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 900, C3.fromRGB(100, 150, 70), V3.new(200, -0.5, 40))

		-- TownMeshes snaps these onto their part-built host (a sign onto its
		-- board, the counter...) keep the host's place. With no host (the gate
		-- kiosk's sign) the piece is at its GLB place like the rest.
		local SNAPPED = { Counter = true, Sign = true, OfficeSign = true, CampSign = true, SkyBin = true, Board = true }
		local function authored(model)
			local hosts = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("VisualMesh") ~= true then
					hosts[d.Name] = true
				end
			end
			for _, d in ipairs(model:GetDescendants()) do
				local at = d:IsA("MeshPart")
					and not (SNAPPED[d.Name] and hosts[d.Name])
					and centres[tostring(d:GetAttribute("MeshId"))]
				if at then
					d.CFrame = CF.new(at[1], at[2], at[3]) * d.CFrame.Rotation
				end
			end
		end

		local cameras = {}
		-- Five angles round a model of the given half size: front (-Z, the
		-- street side), both three-quarters, the back, and a close one.
		local function shoot(label, x, z, r, h, aim)
			local tx, ty = aim or 0, h * 0.5
			local views = {
				{ "front", { 0, h * 0.7, -r } },
				{ "left", { -r * 0.8, h * 0.7, -r * 0.6 } },
				{ "right", { r * 0.8, h * 0.7, -r * 0.6 } },
				{ "back", { r * 0.3, h * 0.8, r } },
				{ "close", { r * 0.25, h * 0.45, -r * 0.55 } },
			}
			for _, v in ipairs(views) do
				table.insert(cameras, {
					pos = { x + v[2][1], v[2][2], z + v[2][3] },
					target = { x + tx, ty, z },
					label = label .. "-" .. v[1],
					fov = 50,
				})
			end
		end
		local function put(model, x, z)
			authored(model)
			Kit.placeAt(model, CF.new(x, 0, z))
			model.Parent = root
		end

		put(BuildingArt.OddsAndEnds(), 0, 0)
		shoot("odds-and-ends", 0, 0, 30, 10)
		put(BuildingArt.Sparkworks(), 60, 0)
		shoot("sparkworks", 60, 0, 32, 12)
		put(BuildingArt.LandOffice(), 120, 0)
		shoot("land-office", 120, 0, 32, 10)
		local gk = BuildingArt.GateKiosk(C3.fromRGB(58, 111, 216))
		put(gk, 180, 0)
		shoot("gate-kiosk", 180, 0, 16, 8)
		put(BuildingArt.ArrivalArch(), 220, 0)
		shoot("arrival-arch", 220, 0, 22, 12)

		-- The Robux crate on a plain ledge, the size the shelf uses.
		local size = BoxSize.Class(RobuxShelf.Class).size
		local crate = roblox.Instance.new("Model")
		local body =
			Kit.part(crate, "Box", size, CF.new(0, size.Y / 2, 0), C3.fromRGB(196, 154, 99), Enum.Material.Wood)
		body.Anchored = true
		BoxArt.Dress(crate, body, { name = "Large Cash Pack", kind = "Robux", gold = true, robuxKey = "Cash10k" })
		authored(crate)
		Kit.placeAt(crate, CF.new(260, 0, 0))
		crate.Parent = root
		shoot("robux-crate", 260, 0, 7, 3, 0)

		-- Lanternwood: sections, crown and pods, at night for the glow.
		local def = WoodData.Get("lanternwood")
		local tree = TreeArt.FromSkeleton(def, TreeGen.Skeleton(def.id, 21, 1))
		Kit.placeAt(tree, CF.new(320, 0, 0))
		tree.Parent = root
		for _, v in ipairs({ { "front", 0, -40 }, { "side", 40, 0 }, { "back", 0, 40 }, { "foot", 12, -14 } }) do
			table.insert(cameras, {
				pos = { 320 + v[2], if v[1] == "foot" then 5 else 14, v[3] },
				target = { 320, if v[1] == "foot" then 3 else 14, 0 },
				label = "lanternwood-" .. v[1],
				fov = 50,
			})
		end

		return { root = root, fov = 50, shadowRadius = 120, cameras = cameras }
	end,
}
