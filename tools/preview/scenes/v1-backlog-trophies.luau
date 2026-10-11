--!nocheck
-- Job 17: the relic trophies by a plot's sign, framed so the plot name
-- reads (the old v1-a2-endgame shot had the sign's post across "Connor").
-- Real PlotSign mesh (assets/meshes/items) over the post and board parts,
-- the way PlotService builds it, and RelicData.Trophies beside it.
-- Needs preview/a2-centres.json: `python3 tools/preview/v1_a2_meshes.py`
-- writes it with the GondolaCabin set; the trophies need only the repo's
-- PlotSign GLB, so this one is enough:
--   python3 -c "import importlib.util as u,json,pathlib; s=u.spec_from_file_location('a','tools/preview/v1_a2_meshes.py'); m=u.module_from_spec(s); s.loader.exec_module(m); pathlib.Path('preview').mkdir(exist_ok=True); pathlib.Path('preview/a2-centres.json').write_text(json.dumps(m.town_centres()))"
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local RelicData = ctx.shared("RelicData")
		local ItemMeshData = ctx.shared("ItemMeshData")
		local root = roblox.Instance.new("Model")
		assert(fs.isFile("preview/a2-centres.json"), "run tools/preview/v1_a2_meshes.py (it writes a2-centres.json)")
		local centres = serde.decode("json", fs.readFile("preview/a2-centres.json"))

		Kit.part(
			root,
			"PlotGround",
			V3.new(40, 1, 30),
			CF.new(0, -0.5, 0),
			C3.fromRGB(116, 164, 78),
			Enum.Material.Grass
		)
		local post =
			Kit.part(root, "SignPost", V3.new(0.6, 6, 0.6), CF.new(0, 3, 0), C3.fromRGB(70, 45, 22), Enum.Material.Wood)
		local board =
			Kit.part(root, "Sign", V3.new(8, 3.5, 0.4), CF.new(0, 6.5, 0), C3.fromRGB(101, 67, 33), Enum.Material.Wood)
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
		for _, def in ipairs(ItemMeshData.List("PlotSign")) do
			local id = string.match(def.meshId, "%d+")
			local at = assert(centres[id], "PlotSign piece " .. def.name)
			local piece = roblox.Instance.new("MeshPart")
			piece.Name = def.name
			piece.Size = def.size
			piece.CFrame = CF.new(at[1], at[2], at[3])
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
			shadowRadius = 40,
			fov = 45,
			cameras = {
				{ pos = { 6, 10.5, -17 }, target = { 4.5, 4, 0 }, fov = 45, label = "trophies" },
				{ pos = { 5, 5, -13 }, target = { 4.5, 2.6, 0 }, fov = 40, label = "close" },
			},
		}
	end,
}
