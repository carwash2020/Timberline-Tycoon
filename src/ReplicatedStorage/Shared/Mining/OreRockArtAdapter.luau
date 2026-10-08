--!strict
-- OreRockArtAdapter: ore nodes call NatureArt.OreRock when Lane G has
-- shipped it, and a small part-built rock until then. Same arguments
-- either way: shape, size, vein colour, vein material, glow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.Art.Kit)

local OreRockArtAdapter = {}

OreRockArtAdapter.MaxParts = 8
OreRockArtAdapter._live = nil :: any

local SCALE = { small = 0.72, mid = 1, large = 1.32 }
local ROCK = Color3.fromRGB(126, 118, 108)
local MOSS = Color3.fromRGB(78, 110, 62)

local function scaleOf(size: any): number
	if type(size) == "number" then
		return math.clamp(size, 0.4, 2)
	end
	if type(size) == "string" and SCALE[size] ~= nil then
		return SCALE[size]
	end
	return 1
end

local function vein(model: Model, cf: CFrame, color: Color3, material: Enum.Material, s: number): WedgePart
	local part = Kit.wedge(model, "Vein", Vector3.new(0.35 * s, 0.9 * s, 1.3 * s), cf, color, material)
	Kit.decor(part, false)
	return part
end

local function body(model: Model, name: string, size: Vector3, cf: CFrame, material: Enum.Material?): Part
	return Kit.part(model, name, size, cf, ROCK, material or Enum.Material.Slate)
end

local function fallback(shape: string, size: any, oreColor: Color3, oreMaterial: Enum.Material, glow: boolean?): Model
	local model = Instance.new("Model")
	model.Name = "OreRock"
	local s = scaleOf(size)
	local host: BasePart
	local veins = 3
	if shape == "split" then
		host = body(model, "Rock", Vector3.new(2.2 * s, 1.5 * s, 1.6 * s), CFrame.new(-0.55 * s, 0.75 * s, 0))
		body(model, "Rock", Vector3.new(1.6 * s, 1.3 * s, 1.5 * s), CFrame.new(0.85 * s, 0.65 * s, 0.15 * s))
		veins = 2
	elseif shape == "standing" then
		host = body(model, "Rock", Vector3.new(1.3 * s, 3.1 * s, 1.2 * s), CFrame.new(0, 1.55 * s, 0))
		veins = 2
	elseif shape == "slab" then
		host = body(model, "Rock", Vector3.new(3.2 * s, 0.7 * s, 2.1 * s), CFrame.new(0, 0.35 * s, 0))
		veins = 2
	elseif shape == "pebbles" then
		host = body(model, "Rock", Vector3.new(0.9 * s, 0.7 * s, 0.8 * s), CFrame.new(0, 0.35 * s, 0))
		body(model, "Rock", Vector3.new(0.7 * s, 0.55 * s, 0.7 * s), CFrame.new(0.8 * s, 0.28 * s, 0.3 * s))
		body(model, "Rock", Vector3.new(0.6 * s, 0.45 * s, 0.6 * s), CFrame.new(-0.7 * s, 0.22 * s, 0.35 * s))
		body(model, "Rock", Vector3.new(0.5 * s, 0.4 * s, 0.5 * s), CFrame.new(0.2 * s, 0.2 * s, -0.7 * s))
		veins = 2
	elseif shape == "mossy" then
		host = body(model, "Rock", Vector3.new(2.4 * s, 1.4 * s, 1.8 * s), CFrame.new(0, 0.7 * s, 0))
		local moss = Kit.part(
			model,
			"Moss",
			Vector3.new(1.6 * s, 0.18 * s, 1.2 * s),
			CFrame.new(-0.2 * s, 1.42 * s, 0.1 * s),
			MOSS,
			Enum.Material.Grass
		)
		Kit.decor(moss, false)
		veins = 3
	else
		host = body(model, "Rock", Vector3.new(2.4 * s, 1.8 * s, 2.1 * s), CFrame.new(0, 0.9 * s, 0))
		veins = 3
	end
	model.PrimaryPart = host
	local face = host.CFrame * CFrame.new(0, host.Size.Y / 2 - 0.02 * s, host.Size.Z / 2 - 0.05 * s)
	for i = 1, veins do
		local slide = (i - (veins + 1) / 2) * 0.45 * s
		local cf = face * CFrame.new(slide, 0, 0) * CFrame.Angles(0, math.rad(8 * i), math.rad(-8))
		local part = vein(model, cf, oreColor, oreMaterial, s)
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
	if mod == nil or not mod:IsA("ModuleScript") then
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
