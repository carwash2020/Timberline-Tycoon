--!nocheck
-- Lane A2 (end game) for Connor: the real models only.
--   1 forge     The Sky Forge Court (uploaded meshes, preview manifest) with
--               Old Bram at the anvil, from a player's eye: the backdrop for
--               the ForgeUI shots (tools/preview/v1_a2_ui.py).
--   2 gate      The town gondola station (GondolaStation mesh), Gus beside
--               its platform where NPCData puts him, and the gate sign
--               GondolaService.GateSign stands (Signpost mesh) with
--               SkyQuestLogic.GateWords.
--   3 isle      The Starfall Forge on the isle (uploaded meshes).
--   4 trophies  Relic trophies by a plot's sign (RelicData.Trophies).
--   5, 6        The court again, framed for the phone and PC ForgeUI shots
--               (v1_a2_ui.py).
-- The court, forge and cabin GLBs are not in assets/meshes yet (job 17 wires
-- them): run `python3 tools/preview/v1_a2_meshes.py` and export with
-- PREVIEW_MESHES=preview/a2-meshes.json (it also writes a2-centres.json). Without it the scene refuses to
-- build rather than draw stand-ins.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local CharacterArt = ctx.art("CharacterArt")
		local NPCData = ctx.shared("NPCData")
		local SkyQuestLogic = ctx.shared("SkyQuestLogic")
		local RelicData = ctx.shared("RelicData")
		local root = roblox.Instance.new("Model")

		assert(fs.isFile("preview/a2-meshes.json"), "run tools/preview/v1_a2_meshes.py first (no stand-ins)")
		local manifest = serde.decode("json", fs.readFile("preview/a2-meshes.json"))
		-- Model-space centre of each uploaded piece (the pack's stats.json).
		local CENTRES = {
			SkyForgeCourt = {
				Body = { 0, 9.225, -0.075 },
				Glow = { -3.35, 3.545, 4.075 },
				Sign = { -8, 11.2, 3.6 },
				Smokestack = { -8, 18.6, 8.2 },
				StarfallForge = { 1.65, 3.1, 1.5 },
			},
			StarfallForge = {
				Body = { -0.125, 6.1, 2.15 },
				Glow = { -0.337, 2.875, 1.739 },
				StarfallForge = { -0.55, 3.212, 0 },
			},
		}
		local function uploaded(modelName, at)
			local model = roblox.Instance.new("Model")
			model.Name = modelName
			local n = 0
			for id, info in pairs(manifest) do
				local centre = CENTRES[modelName] and CENTRES[modelName][info.node]
				if info.model == modelName and centre then
					local part = roblox.Instance.new("MeshPart")
					part.Name = info.node
					part.Size = V3.new(info.initialSize[1], info.initialSize[2], info.initialSize[3])
					part.CFrame = at * CF.new(centre[1], centre[2], centre[3])
					part:SetAttribute("MeshId", id)
					part.Parent = model
					n += 1
				end
			end
			assert(n > 0, "no pieces for " .. modelName)
			model.Parent = root
			return model
		end
		-- Studio keeps each town piece where it sits in its uploaded model
		-- (MeshKit: pivot "authored"); Lune has no pivots and TownMeshes
		-- stands every piece on the ground (a roof by the steps, a sign board
		-- in the grass). Put each piece at its GLB place (v1_a2_meshes.py),
		-- while the model is still at the origin.
		local centres = serde.decode("json", fs.readFile("preview/a2-centres.json"))
		local function authored(model)
			for _, d in ipairs(model:GetDescendants()) do
				local at = d:IsA("MeshPart") and centres[tostring(d:GetAttribute("MeshId"))]
				if at then
					d.CFrame = CF.new(at[1], at[2], at[3]) * d.CFrame.Rotation
				end
			end
		end
		local function npc(id, cf)
			local m = CharacterArt.Build(NPCData.Get(id).look)
			Kit.placeAt(m, cf)
			m.Parent = root
			return m
		end
		local GRASS, COBBLE = C3.fromRGB(116, 164, 78), C3.fromRGB(150, 140, 122)

		-- 1. The Sky Forge Court, at the origin, opening toward -Z.
		Kit.part(root, "CourtGround", V3.new(90, 1, 70), CF.new(0, -0.5, -10), COBBLE, Enum.Material.Cobblestone)
		uploaded("SkyForgeCourt", CF.new(0, 0, 0))
		npc("Bram", CF.new(-1.5, 0, -6) * CF.Angles(0, math.rad(180), 0))

		-- 2. The town gondola station, 200 studs east, its steps toward -Z.
		local GX = 200
		Kit.part(root, "GateGround", V3.new(80, 1, 70), CF.new(GX, -0.5, -10), GRASS, Enum.Material.Grass)
		local station = BuildingArt.GondolaStation()
		authored(station)
		Kit.placeAt(station, CF.new(GX, 0, 0))
		station.Parent = root
		local platform = station:FindFirstChild("Platform")
		-- Gus: NPCData's "beside" spot (offset 1.8, 0, -3, turned 20 degrees).
		local gus = NPCData.Get("Gus").spot
		npc(
			"Gus",
			platform.CFrame
				* CF.new(0, platform.Size.Y / 2, 0)
				* CF.new(gus.offset.X, gus.offset.Y, gus.offset.Z)
				* CF.Angles(0, math.rad(gus.turn), 0)
		)
		-- The sign, where GondolaService.GateSign stands it.
		local sign = BuildingArt.Signpost("SKYROOT GONDOLA\n" .. SkyQuestLogic.GateWords)
		authored(sign)
		Kit.placeAt(sign, platform.CFrame * CF.new(-10.5, -0.5, -8.5))
		sign.Parent = root

		-- 3. The isle forge, 400 east, on isle stone.
		local IX = 400
		Kit.part(
			root,
			"IsleGround",
			V3.new(60, 1, 50),
			CF.new(IX, -0.5, 0),
			C3.fromRGB(176, 170, 160),
			Enum.Material.Slate
		)
		uploaded("StarfallForge", CF.new(IX, 0, 0) * CF.Angles(0, math.rad(180), 0))

		-- 4. Relic trophies by a plot's sign, built the way PlotService builds
		-- it: the post and board parts, the PlotSign mesh over them, the
		-- board's text on both faces (Fantasy, scaled).
		local PX = 600
		Kit.part(root, "PlotGround", V3.new(40, 1, 30), CF.new(PX, -0.5, 0), GRASS, Enum.Material.Grass)
		local ItemMeshData = ctx.shared("ItemMeshData")
		local signAt = CF.new(PX, 0, 0)
		local post = Kit.part(
			root,
			"SignPost",
			V3.new(0.6, 6, 0.6),
			signAt * CF.new(0, 3, 0),
			C3.fromRGB(70, 45, 22),
			Enum.Material.Wood
		)
		local board = Kit.part(
			root,
			"Sign",
			V3.new(8, 3.5, 0.4),
			signAt * CF.new(0, 6.5, 0),
			C3.fromRGB(101, 67, 33),
			Enum.Material.Wood
		)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local sg = roblox.Instance.new("SurfaceGui")
			sg.Face = face
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 40
			sg.Parent = board
			local l = roblox.Instance.new("TextLabel")
			l.Size = roblox.UDim2.fromScale(1, 1)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.Fantasy
			l.TextScaled = true
			l.TextColor3 = C3.fromRGB(245, 235, 215)
			l.Text = "PLOT 3\nHOMESTEAD\nConnor"
			l.Parent = sg
		end
		-- ItemMeshes.AttachTo clones Studio templates; here each PlotSign
		-- piece is a MeshPart at its GLB place over the sign's foot.
		for _, def in ipairs(ItemMeshData.List("PlotSign")) do
			local id = string.match(def.meshId, "%d+")
			local at = assert(centres[id], "PlotSign piece " .. def.name)
			local piece = roblox.Instance.new("MeshPart")
			piece.Name = def.name
			piece.Size = def.size
			piece.CFrame = signAt * CF.new(at[1], at[2], at[3])
			piece:SetAttribute("MeshId", id)
			piece.Parent = root
		end
		board.Transparency = 1
		post.Transparency = 1
		local trophies =
			RelicData.Trophies({ "FrostRelic", "EmberRelic", "GloamRelic", "LumenRelic" }, post.CFrame, post.Size.Y)
		trophies.Parent = root

		return {
			root = root,
			shadowRadius = 70,
			-- PREVIEW_HUD=0: no caption (the backdrop under the ForgeUI shots).
			hud = process.env.PREVIEW_HUD ~= "0",
			fov = 50,
			cameras = {
				{ pos = { 0, 9, -34 }, target = { 0, 5, 0 }, fov = 55, label = "forge" },
				{ pos = { GX - 9, 7.5, -32 }, target = { GX - 4, 4.5, -2 }, fov = 50, label = "gate" },
				{ pos = { IX + 6, 9, 21 }, target = { IX, 5.5, 0 }, fov = 50, label = "isle" },
				{ pos = { PX + 2, 6.5, 19 }, target = { PX + 4.5, 3.5, 0 }, fov = 50, label = "trophies" },
				-- Behind the window shots: Bram and the anvil left of the window
				-- (phone: the window's left edge is 41% across; PC: 27%).
				{ pos = { -3, 7.5, -27 }, target = { -11, 4, 2 }, fov = 50, label = "ui-phone" },
				{ pos = { -3, 7.5, -27 }, target = { -16, 4, 2 }, fov = 50, label = "ui-pc" },
			},
		}
	end,
}
