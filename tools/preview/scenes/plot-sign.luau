--!nocheck
-- The plot sign as PlotService builds it (SignPost + Sign board with a
-- SurfaceGui on both faces, the PlotSign mesh over them), up close from the
-- front, the back and the side, to check the owner name is readable.
--   1 front   2 back   3 side   4 front, a long name   5 street view
-- Needs preview/a2-centres.json (python3 tools/preview/v1_a2_meshes.py writes it):
-- where each PlotSign piece sits in its GLB. Without it the scene refuses to
-- build rather than draw stand-ins.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local ItemMeshData = ctx.shared("ItemMeshData")
		local PlotData = ctx.shared("PlotData")
		local root = roblox.Instance.new("Model")
		assert(fs.isFile("preview/a2-centres.json"), "run tools/preview/v1_a2_meshes.py first (no stand-ins)")
		local centres = serde.decode("json", fs.readFile("preview/a2-centres.json"))
		local GRASS = C3.fromRGB(116, 164, 78)

		local function sign(x, name, info)
			local signAt = CF.new(x, 0, 0)
			Kit.part(root, "Ground", V3.new(24, 1, 20), CF.new(x, -0.5, 0), GRASS, Enum.Material.Grass)
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
				for _, line in ipairs({ "name", "info" }) do
					local box = PlotData.SignText[line]
					local l = roblox.Instance.new("TextLabel")
					l.Position = roblox.UDim2.fromScale(0.04, box.top)
					l.Size = roblox.UDim2.fromScale(0.92, box.height)
					l.BackgroundTransparency = 1
					l.Font = Enum.Font.Fantasy
					l.TextScaled = true
					l.TextColor3 = C3.fromRGB(245, 235, 215)
					l.Text = if line == "name" then name else info
					l.Parent = sg
				end
			end
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
		end
		sign(0, "Connor", "PLOT 3 · HOMESTEAD")
		sign(100, "Maximilian the Great", "PLOT 12 · ESTATE")

		return {
			root = root,
			shadowRadius = 40,
			fov = 45,
			cameras = {
				{ pos = { 0, 6.5, -12 }, target = { 0, 6.5, 0 }, fov = 40, label = "front" },
				{ pos = { 0, 6.5, 12 }, target = { 0, 6.5, 0 }, fov = 40, label = "back" },
				{ pos = { 12, 6.5, -3 }, target = { 0, 6, 0 }, fov = 40, label = "side" },
				{ pos = { 100, 6.5, -12 }, target = { 100, 6.5, 0 }, fov = 40, label = "long" },
				{ pos = { 3, 3, -20 }, target = { 0, 6, 0 }, fov = 55, label = "street" },
			},
		}
	end,
}
