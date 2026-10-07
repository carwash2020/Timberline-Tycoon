--!nocheck
-- Model preview, no Studio needed. From the repo root:
--   lune run tools/preview/export            list the scenes
--   lune run tools/preview/export trees      write preview/trees.html
--   lune run tools/preview/export all        every scene
--
-- Builds a scene (tools/preview/scenes/<scene>.luau) with the game's own art modules
-- (src/ReplicatedStorage/Shared/Art) through tools/loader.luau, then writes a
-- self-contained HTML viewer (tools/preview/viewer.html + the scene's parts,
-- lights, sign text and terrain) to preview/<scene>.html. Open it in any
-- browser. `node tools/preview/render.mjs` turns those into PNG screenshots.
--
-- It also lints the art: parts placed with .Position instead of .CFrame
-- (the preview can't tell which was set last, so art code uses CFrame only),
-- and part counts per scene, so the phone budget stays visible.
--
-- A scene's build(ctx) returns { root, cameras?, lighting?, fov?,
-- shadowRadius?, terrain? }. Each camera is
--   { pos = { x, y, z }, target = { x, y, z }, label = "...", fov = 50?, night = true? }
-- and number key 1-9 in the viewer jumps to it. `night = true` renders that
-- view with the viewer's night preset (viewer.html NIGHT): dark blue light,
-- and the parts the game lights after dark (WindowGlass, LampGlow,
-- LanternGlow; see night.luau) glow with their lights on. The viewer draws
-- at most 24 point lights: in export order on a day camera, the 24 nearest
-- the camera at night. Cameras without the flag render as they always have.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/preview/export <scene>")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local Night = require("./night")
-- One scene per file in tools/preview/scenes (files starting with _ are helpers).
local scenes = {}
for _, file in ipairs(fs.readDir("tools/preview/scenes")) do
	local name = string.match(file, "^([^_][%w_%-]*)%.luau$")
	if name then
		scenes[name] = require("./scenes/" .. name)
	end
end

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local SHAPES = { "Block", "Wedge", "CornerWedge", "Cylinder", "Ball", "Sphere" }
local SHAPE_INDEX = {}
for i, s in ipairs(SHAPES) do
	SHAPE_INDEX[s] = i - 1
end

local function round(n: number, places: number): number
	local m = 10 ^ places
	return math.floor(n * m + 0.5) / m
end

local function hex(c): string
	return c:ToHex()
end

local function shapeOf(part): (string?, Vector3)
	local size = part.Size
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		local scaled = size * mesh.Scale
		local t = mesh.MeshType.Name
		if t == "Sphere" then
			return "Sphere", scaled
		elseif t == "Brick" then
			return "Block", scaled
		elseif t == "Wedge" then
			return "Wedge", scaled
		elseif t == "Cylinder" then
			return "Cylinder", scaled
		end
		return nil, size -- FileMesh and friends: can't draw them here
	end
	local class = part.ClassName
	if class == "WedgePart" then
		return "Wedge", size
	elseif class == "CornerWedgePart" then
		return "CornerWedge", size
	elseif class == "MeshPart" then
		return nil, size
	end
	local ok, shape = pcall(function()
		return part.Shape.Name
	end)
	if ok then
		if shape == "Cylinder" or shape == "Ball" or shape == "Wedge" or shape == "CornerWedge" then
			return shape, size
		end
	end
	return "Block", size
end

local FACE_ROT = {
	Front = CFrame.Angles(0, math.pi, 0),
	Back = CFrame.identity,
	Right = CFrame.Angles(0, math.pi / 2, 0),
	Left = CFrame.Angles(0, -math.pi / 2, 0),
	Top = CFrame.Angles(-math.pi / 2, 0, 0),
	Bottom = CFrame.Angles(math.pi / 2, 0, 0),
}
local FACE_NORMAL = {
	Front = Vector3.new(0, 0, -1),
	Back = Vector3.new(0, 0, 1),
	Right = Vector3.new(1, 0, 0),
	Left = Vector3.new(-1, 0, 0),
	Top = Vector3.new(0, 1, 0),
	Bottom = Vector3.new(0, -1, 0),
}

local function cframeList(cf): { number }
	local c = { cf:GetComponents() }
	local out = {}
	for i = 1, 12 do
		out[i] = round(c[i], if i <= 3 then 3 else 5)
	end
	return out
end

local function export(name: string, def)
	local loader = Loader.new()
	local built = def.build({
		loader = loader,
		shared = function(n)
			return loader:shared(n)
		end,
		art = function(n)
			return loader:load("ReplicatedStorage/Shared/Art/" .. n)
		end,
		load = function(path)
			return loader:load(path)
		end,
		roblox = roblox,
	})
	local root = built.root

	local parts, lights, texts = {}, {}, {}
	local materials, materialIndex = {}, {}
	local counts, warnings = {}, {}
	local positionWarned = 0
	local total = 0

	local function matIdx(m: string): number
		local i = materialIndex[m]
		if i == nil then
			table.insert(materials, m)
			i = #materials - 1
			materialIndex[m] = i
		end
		return i
	end

	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("BasePart") then
			total += 1
			counts[inst.ClassName] = (counts[inst.ClassName] or 0) + 1
			if pcall(function()
				return inst.Position
			end) then
				positionWarned += 1
				if positionWarned <= 5 then
					table.insert(warnings, "set .Position (use .CFrame): " .. inst:GetFullName())
				end
			end
			local shape, size = shapeOf(inst)
			if shape then
				local c = cframeList(inst.CFrame)
				local entry = {
					SHAPE_INDEX[shape],
					round(size.X, 3),
					round(size.Y, 3),
					round(size.Z, 3),
					c[1],
					c[2],
					c[3],
					c[4],
					c[5],
					c[6],
					c[7],
					c[8],
					c[9],
					c[10],
					c[11],
					c[12],
					hex(inst.Color),
					matIdx(inst.Material.Name),
					round(inst.Transparency, 2),
				}
				-- [20]: the colour it glows on a night camera (night.luau).
				entry[20] = Night.GlowColor(inst)
				table.insert(parts, entry)
			end
		elseif inst:IsA("Light") then
			local parent = inst.Parent
			-- A night light built switched off still comes on at night.
			local nightOnly = not inst.Enabled and Night.IsNightLight(inst)
			if parent and parent:IsA("BasePart") and (inst.Enabled or nightOnly) then
				local p = parent.CFrame.Position
				table.insert(lights, {
					round(p.X, 2),
					round(p.Y, 2),
					round(p.Z, 2),
					hex(inst.Color),
					inst.Range,
					inst.Brightness,
					if nightOnly then 1 else nil, -- [7]: drawn only on a night camera
				})
			end
		elseif inst:IsA("SurfaceGui") or inst:IsA("BillboardGui") then
			local part = inst.Parent
			local label = inst:FindFirstChildWhichIsA("TextLabel", true)
			-- A gui with several text lines
			-- previews as one block, top line first.
			local text = if label then label.Text else ""
			if label then
				local lines = {}
				for _, d in ipairs(inst:GetDescendants()) do
					if d:IsA("TextLabel") and d.Text ~= "" then
						table.insert(lines, d)
					end
				end
				if #lines > 1 then
					table.sort(lines, function(a, b)
						return a.Position.Y.Scale < b.Position.Y.Scale
					end)
					local parts = {}
					for _, d in ipairs(lines) do
						table.insert(parts, d.Text)
					end
					text = table.concat(parts, "\n")
				end
			end
			if part and part:IsA("BasePart") and label and text ~= "" then
				local cf, w, h
				if inst:IsA("SurfaceGui") then
					local face = inst.Face.Name
					local n = FACE_NORMAL[face]
					local s = part.Size
					local depth = math.abs(n.X) * s.X + math.abs(n.Y) * s.Y + math.abs(n.Z) * s.Z
					cf = part.CFrame * CFrame.new(n * (depth / 2 + 0.03)) * FACE_ROT[face]
					if face == "Front" or face == "Back" then
						w, h = s.X, s.Y
					elseif face == "Left" or face == "Right" then
						w, h = s.Z, s.Y
					else
						w, h = s.X, s.Z
					end
				else
					cf = part.CFrame + inst.StudsOffset + Vector3.new(0, part.Size.Y / 2, 0)
					w, h = 4, 1.2
				end
				local c = cframeList(cf)
				table.insert(texts, {
					if inst:IsA("SurfaceGui") then "surface" else "billboard",
					round(w, 2),
					round(h, 2),
					c[1],
					c[2],
					c[3],
					c[4],
					c[5],
					c[6],
					c[7],
					c[8],
					c[9],
					c[10],
					c[11],
					c[12],
					text,
					hex(label.TextColor3),
				})
			end
		end
	end
	if positionWarned > 5 then
		table.insert(warnings, string.format("... and %d more parts placed with .Position", positionWarned - 5))
	end

	local scene = {
		name = name,
		shapes = SHAPES,
		materials = materials,
		parts = parts,
		lights = lights,
		texts = texts,
		cameras = built.cameras,
		lighting = built.lighting,
		fov = built.fov,
		shadowRadius = built.shadowRadius,
	}

	local t = built.terrain
	if t then
		local nx = math.floor((t.x1 - t.x0) / t.step) + 1
		local nz = math.floor((t.z1 - t.z0) / t.step) + 1
		local h, m, wet = table.create(nx * nz), table.create(nx * nz), table.create(nx * nz)
		local palette, paletteIndex = {}, {}
		for iz = 0, nz - 1 do
			for ix = 0, nx - 1 do
				local height, material, water = t.sample(t.x0 + ix * t.step, t.z0 + iz * t.step)
				wet[iz * nx + ix + 1] = if water then round(water, 2) else -9999
				local color = t.colors[material] or "FF00FF"
				local pi = paletteIndex[color]
				if pi == nil then
					table.insert(palette, color)
					pi = #palette - 1
					paletteIndex[color] = pi
				end
				h[iz * nx + ix + 1] = round(height, 2)
				m[iz * nx + ix + 1] = pi
			end
		end
		scene.terrain = {
			x0 = t.x0,
			z0 = t.z0,
			step = t.step,
			nx = nx,
			nz = nz,
			h = h,
			m = m,
			palette = palette,
			wet = wet,
			waterColor = t.waterColor,
		}
	end

	local json = serde.encode("json", scene)
	json = string.gsub(json, "</", "<\\/")
	local template = fs.readFile("tools/preview/viewer.html")
	local start, finish = string.find(template, "/*SCENE_JSON*/", 1, true)
	assert(start, "viewer.html is missing its /*SCENE_JSON*/ placeholder")
	local html = string.sub(template, 1, start - 1) .. json .. string.sub(template, finish + 1)
	if not fs.isDir("preview") then
		fs.writeDir("preview")
	end
	fs.writeFile("preview/" .. name .. ".html", html)

	local classes = {}
	for class, n in pairs(counts) do
		table.insert(classes, string.format("%s %d", class, n))
	end
	table.sort(classes)
	print(
		string.format(
			"preview/%s.html  %d parts (%s), %d lights%s",
			name,
			total,
			table.concat(classes, ", "),
			#lights,
			if built.terrain then ", terrain" else ""
		)
	)
	for _, w in ipairs(warnings) do
		print("  warning: " .. w)
	end
	return total
end

local which = process.args[1]
local names = {}
for name in pairs(scenes) do
	table.insert(names, name)
end
table.sort(names)
if not which then
	print("Scenes: " .. table.concat(names, ", ") .. "  (or: all)")
	process.exit(0)
end
local selected = if which == "all" then names else { which }
for _, name in ipairs(selected) do
	local def = scenes[name]
	if not def then
		print("No scene called " .. name .. ". Scenes: " .. table.concat(names, ", "))
		process.exit(1)
	end
	export(name, def)
end
