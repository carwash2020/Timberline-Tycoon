--!strict
-- OreRockArtAdapter: ore nodes call NatureArt.OreRock when Lane G has
-- shipped it, and a small part-built rock until then. Same arguments
-- either way: shape, size, vein colour, vein material, glow.
--
-- The fallback is a tilted pile of 3 to 5 wedges and blocks, partly sunk,
-- with 2 or 3 vein wedges lying flat on the faces (0.1 stud proud, about
-- a fifth of the face). Glow only when the ore says so.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.Art.Kit)

local OreRockArtAdapter = {}

OreRockArtAdapter.MaxParts = 8
OreRockArtAdapter._live = nil :: any

local SCALE = { small = 0.72, mid = 1, large = 1.32 }
local ROCK = Color3.fromRGB(126, 118, 108)
local MOSS = Color3.fromRGB(78, 110, 62)

local LAYOUT = {
	boulder = { parts = 4, veins = 3, seed = 11 },
	split = { parts = 5, veins = 2, seed = 23 },
	standing = { parts = 4, veins = 2, seed = 37 },
	slab = { parts = 3, veins = 2, seed = 41 },
	pebbles = { parts = 5, veins = 2, seed = 53 },
	mossy = { parts = 4, veins = 3, seed = 67 },
}

local function scaleOf(size: any): number
	if type(size) == "number" then
		return math.clamp(size, 0.4, 2)
	end
	if type(size) == "string" and SCALE[size] ~= nil then
		return SCALE[size]
	end
	return 1
end

local function fallback(shape: string, size: any, oreColor: Color3, oreMaterial: Enum.Material, glow: boolean?): Model
	local model = Instance.new("Model")
	model.Name = "OreRock"
	local s = scaleOf(size)
	local layout = LAYOUT[shape] or LAYOUT.boulder
	local rng = Kit.rng(layout.seed)
	local host: BasePart? = nil
	local biggest = 0
	for i = 1, layout.parts do
		local sx = rng:range(1.15, 2.15) * s
		local sy = rng:range(0.7, 1.45) * s
		local sz = rng:range(1.05, 1.9) * s
		local cf = CFrame.new(
			rng:range(-0.4, 0.4) * s,
			rng:range(-0.45, 0.15) * s + sy * 0.15,
			rng:range(-0.35, 0.35) * s
		) * CFrame.Angles(math.rad(rng:range(-26, 22)), math.rad(rng:range(-50, 50)), math.rad(rng:range(-20, 20)))
		local moss = shape == "mossy" and i == layout.parts
		local color = if moss then MOSS else ROCK
		local material = if moss then Enum.Material.Grass else Enum.Material.Slate
		local part: BasePart
		if rng:next() < 0.6 then
			part = Kit.wedge(model, "Rock", Vector3.new(sx, sy, sz), cf, color, material)
		else
			part = Kit.part(model, "Rock", Vector3.new(sx, sy, sz), cf, color, material)
		end
		local volume = sx * sy * sz
		if volume > biggest then
			biggest = volume
			host = part
		end
	end
	local body = host :: BasePart
	model.PrimaryPart = body
	-- Flat insets on the front, the side, and (when there is a third) the top.
	local faces = {
		{
			normal = Vector3.new(0, 0, -1),
			width = body.Size.X,
			height = body.Size.Y,
			along = "z",
		},
		{
			normal = Vector3.new(1, 0, 0),
			width = body.Size.Z,
			height = body.Size.Y,
			along = "x",
		},
		{
			normal = Vector3.new(0, 1, 0),
			width = body.Size.X,
			height = body.Size.Z,
			along = "y",
		},
	}
	for i = 1, layout.veins do
		local face = faces[i]
		local cover = 0.18 + (i - 1) * 0.03
		local span = math.sqrt(math.max(face.width * face.height * cover, 0.05))
		local wide = math.clamp(span, face.width * 0.35, face.width * 0.7)
		local tall = math.clamp((face.width * face.height * cover) / wide, face.height * 0.28, face.height * 0.7)
		local proud = 0.1
		local plate: Vector3
		local localCf: CFrame
		if face.along == "z" then
			plate = Vector3.new(wide, tall, proud)
			localCf = CFrame.new(0, 0, -body.Size.Z / 2 - proud / 2)
		elseif face.along == "x" then
			plate = Vector3.new(proud, tall, wide)
			localCf = CFrame.new(body.Size.X / 2 + proud / 2, 0, 0)
		else
			plate = Vector3.new(wide, proud, tall)
			localCf = CFrame.new(0, body.Size.Y / 2 + proud / 2, 0)
		end
		local part = Kit.wedge(model, "Vein", plate, body.CFrame * localCf, oreColor, oreMaterial)
		Kit.decor(part, false)
		if glow == true and i == 1 then
			local light = Instance.new("PointLight")
			light.Name = "VeinLight"
			light.Color = oreColor
			light.Range = 8
			light.Brightness = 0.6
			light.Shadows = false
			light.Parent = part
		end
	end
	model:SetAttribute("OreShape", shape)
	return model
end

local function findLive(): any
	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	local art = sharedFolder and sharedFolder:FindFirstChild("Art")
	local mod = art and art:FindFirstChild("NatureArt")
	-- Under Lune the loader hands back plain tables, not Instances: no live art.
	if mod == nil or typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" then
		local fn = (result :: any).OreRock
		if type(fn) == "function" then
			return fn
		end
	end
	return nil
end

function OreRockArtAdapter.OreRock(
	shape: string,
	size: any,
	oreColor: Color3,
	oreMaterial: Enum.Material,
	glow: boolean?
): Model
	if OreRockArtAdapter._live == nil then
		OreRockArtAdapter._live = findLive() or false
	end
	local live = OreRockArtAdapter._live
	if type(live) == "function" then
		return live(shape, size, oreColor, oreMaterial, glow)
	end
	return fallback(shape, size, oreColor, oreMaterial, glow)
end

return OreRockArtAdapter
