--!nocheck
-- Lane P: the store's world pieces, as the game builds them.
--   1 bulletin board, day   2 bulletin board, night   3 board from the side
--   4 board from behind     5 Tool Shed: the gold table from the aisle
--   6 gold crate close-up (the shed's uploaded mesh has a ceiling, so
--   there is no view from above; the counter lamp sits low in view 5)
-- The board's poster canvas (a SurfaceGui of cards) is taken off here and
-- pasted back onto the cork face by tools/preview/v1p_composite.py from
-- v1p_gui's render of the real canvas (the 3D viewer draws a SurfaceGui
-- only as one block of text). Its world corners are printed for that.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local BoxArt = ctx.art("BoxArt")
		local BoxSize = ctx.shared("BoxSize")
		local RobuxShelf = ctx.shared("RobuxShelf")
		local StoreBoard = ctx.shared("StoreBoard")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 1200, C3.fromRGB(104, 152, 74), V3.new(0, -0.5, 200))
		local cameras = {}

		-- The board, its cork centre FieldBottom + half its height up, facing -Z.
		local board = StoreBoard.Build()
		local size = StoreBoard.BoardSize
		local centre = CF.new(0, StoreBoard.FieldBottom + size.Y / 2, 0)
		board:PivotTo(centre)
		board:FindFirstChild("Posters", true):Destroy()
		board.Parent = root
		-- Preview only: two fill lights in front of the board so the night shot
		-- isn't black (framing rule: dark scenes get a fill light). Named
		-- LampGlow and switched off so the viewer only lights it at night;
		-- fully transparent, so the bulb itself never shows.
		for i, at in ipairs({ V3.new(0, 7, -6), V3.new(4, 11, -11), V3.new(-6, 6, -16), V3.new(8, 6, -4) }) do
			local fill = Kit.part(root, "LampGlow", V3.new(0.2, 0.2, 0.2), CF.new(at), C3.new(1, 1, 1))
			fill.Transparency = 1
			local fillLight = roblox.Instance.new("PointLight")
			fillLight.Name = "PreviewFill" .. i
			fillLight.Range = 60
			fillLight.Brightness = 14
			fillLight.Color = C3.fromRGB(255, 236, 205)
			fillLight.Enabled = false
			fillLight.Parent = fill
		end
		local bc = centre.Position
		table.insert(
			cameras,
			{ pos = { bc.X + 4.5, 11.0, -13 }, target = { bc.X + 0.3, 4.3, 0 }, label = "board-day", fov = 45 }
		)
		table.insert(cameras, {
			pos = { bc.X + 4.5, 11.0, -13 },
			target = { bc.X + 0.3, 4.3, 0 },
			label = "board-night",
			fov = 45,
			night = true,
		})
		table.insert(
			cameras,
			{ pos = { bc.X - 11.5, 10.5, -9 }, target = { bc.X, 4.0, 0 }, label = "board-side", fov = 50 }
		)
		table.insert(
			cameras,
			{ pos = { bc.X - 3, 9.2, 10.5 }, target = { bc.X, 4.2, 0 }, label = "board-back", fov = 50 }
		)

		-- The Tool Shed, roof off, its gold crates on the table and riser.
		local ROOF = { Roof = true, Shingle = true, RidgeCap = true, Gable = true, Rafter = true, TieBeam = true }
		local shed = BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(58, 111, 216))
		for _, d in ipairs(shed:GetDescendants()) do
			if d:IsA("BasePart") and ROOF[d.Name] then
				d:Destroy()
			end
		end
		local SX, SZ = 0, 400
		Kit.placeAt(shed, CF.new(SX, 0, SZ))
		shed.Parent = root
		local counter = shed:FindFirstChild("Counter")
		local crates = {}
		for _, att in ipairs(counter:GetChildren()) do
			if att:IsA("Attachment") and att.Name == "RobuxSlot" then
				local at = counter.CFrame:PointToWorldSpace(att.Position)
				local entry = RobuxShelf.Get(att:GetAttribute("SlotId"))
				local m = roblox.Instance.new("Model")
				m.Name = entry.key
				local bsize = BoxSize.Class(RobuxShelf.Class).size
				local body =
					Kit.part(m, "Box", bsize, CF.new(at), C3.fromHex(RobuxShelf.Gold), roblox.Enum.Material.Metal)
				body.CanCollide = false
				BoxArt.Dress(m, body, {
					name = entry.displayName,
					kind = "Robux",
					color = C3.fromHex(RobuxShelf.Gold),
					gold = true,
					robuxKey = entry.key,
				})
				m.Parent = root
				crates[entry.key] = at
			end
		end
		local tz = SZ + RobuxShelf.TableZ
		table.insert(
			cameras,
			{ pos = { SX - 1.5, 14, tz - 12 }, target = { SX, 4.2, tz - 0.5 }, label = "gold-table", fov = 55 }
		)
		local c = crates.Cash10k or crates.DoubleCash
		table.insert(cameras, {
			pos = { c.X - 2.2, c.Y + 2.4, c.Z - 5.2 },
			target = { c.X, c.Y, c.Z },
			label = "gold-box-closeup",
			fov = 45,
		})
		-- For the composite: the cork face's corners (canvas TL, TR, BR, BL).
		local half = size / 2
		local face = centre * CF.new(0, 0, -half.Z - 0.01)
		local corners = {
			face * V3.new(half.X, half.Y, 0),
			face * V3.new(-half.X, half.Y, 0),
			face * V3.new(-half.X, -half.Y, 0),
			face * V3.new(half.X, -half.Y, 0),
		}
		local list = {}
		for _, p in ipairs(corners) do
			table.insert(list, string.format("[%.3f,%.3f,%.3f]", p.X, p.Y, p.Z))
		end
		print("BOARD_FACE " .. table.concat(list, ","))
		return { root = root, shadowRadius = 60, fov = 50, cameras = cameras }
	end,
}
