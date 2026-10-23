--!strict
-- WireArt: the spool of wire a player carries (T420). A wooden spool with a coil
-- of copper wire on it, a band and a loose end. Built from parts only (no mesh,
-- no asset id), small and chunky like the hammer so it reads at hotbar size.
-- Pure (see Kit).
--
-- Contract (the same as HammerArt, so a Tool is built the same way):
--   * Build() returns a Model with PrimaryPart "Handle" (a Tool needs it); every
--     other part is welded to it. The spool's axis runs along X.
--   * Held(): Build, then unanchored, massless and non-colliding.
--   * Grip(): the Tool.Grip that holds the spool at its middle, axis across the hand.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local WireArt = {}

-- TODO(Builder): the spool mesh. Set WireSpoolMeshId to its uploaded MeshPart id
-- (a number; never guess one). While it is nil the part-built spool below is
-- used, and only then. With an id, Build() returns one MeshPart Handle instead.
WireArt.Config = {
	WireSpoolMeshId = nil :: number?,
	MeshSize = Vector3.new(1.5, 1.5, 1.4), -- TODO(Builder): the mesh's real size
}

-- True when the mesh slot is filled (the part-built spool is the fallback).
function WireArt.UsesMesh(): boolean
	return WireArt.Config.WireSpoolMeshId ~= nil
end

local WOOD = Palette.TimberBrown
-- New, for the part-built stand-in only (the mesh will carry its own look):
local COPPER = Color3.fromRGB(196, 122, 66)
local COPPER_DARK = Color3.fromRGB(150, 90, 48)
local BAND = Palette.Brass

local FLANGE = 1.5 -- diameter of each end disc
local COIL = 1.15 -- diameter of the wire on the spool
local LENGTH = 1.0 -- between the flanges

WireArt.Length = LENGTH

local function add(
	model: Model,
	name: string,
	length: number,
	diameter: number,
	x: number,
	color: Color3,
	material: Enum.Material
): Part
	local p = Kit.cylinder(model, name, length, diameter, CFrame.new(x, 0, 0), color, material)
	Kit.decor(p, false)
	return p
end

-- The mesh spool: one MeshPart Handle. Only used once WireSpoolMeshId is set.
local function buildMesh(id: number): Model
	local model = Kit.model("WireSpool")
	local handle = Instance.new("MeshPart")
	handle.Name = "Handle"
	handle.MeshId = "rbxassetid://" .. tostring(id)
	handle.Size = WireArt.Config.MeshSize
	handle.Anchored = true
	handle.CanTouch = false
	handle.Parent = model
	model.PrimaryPart = handle
	return model
end

function WireArt.Build(): Model
	local meshId = WireArt.Config.WireSpoolMeshId
	if meshId ~= nil then
		return buildMesh(meshId)
	end
	-- TODO(Builder): part-built stand-in until the mesh id above is set.
	local model = Kit.model("WireSpool")
	-- The axle is the Handle: a bar through the spool, a little longer than it.
	local handle = Kit.part(
		model,
		"Handle",
		Vector3.new(LENGTH + 0.4, 0.3, 0.3),
		CFrame.new(0, 0, 0),
		Kit.shade(WOOD, -0.12),
		Enum.Material.Wood
	)
	handle.CanTouch = false
	model.PrimaryPart = handle
	add(model, "FlangeLeft", 0.12, FLANGE, -LENGTH / 2, WOOD, Enum.Material.Wood)
	add(model, "FlangeRight", 0.12, FLANGE, LENGTH / 2, WOOD, Enum.Material.Wood)
	add(model, "Coil", LENGTH - 0.1, COIL, 0, COPPER, Enum.Material.Metal)
	add(model, "CoilBand", 0.18, COIL + 0.06, 0, BAND, Enum.Material.Fabric)
	add(model, "CoilLow", 0.3, COIL + 0.02, -0.3, COPPER_DARK, Enum.Material.Metal)
	-- The loose end: a short bright tail off the coil.
	local tail = Kit.part(
		model,
		"WireEnd",
		Vector3.new(0.08, 0.08, 0.7),
		CFrame.new(0.2, 0.55, 0.3) * CFrame.Angles(math.rad(-30), 0, 0),
		COPPER,
		Enum.Material.Metal
	)
	Kit.decor(tail, false)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle then
			local w = Instance.new("Weld")
			w.Name = "Weld"
			w.Part0 = handle
			w.Part1 = d
			w.C0 = handle.CFrame:Inverse() * d.CFrame
			w.Parent = d
		end
	end
	return model
end

-- For a Tool: nothing anchored, nothing collides, nothing weighs anything.
function WireArt.Held(): Model
	local model = WireArt.Build()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	return model
end

-- Tool.Grip: the spool held at its middle, its axis across the hand, tipped a
-- little forward so the coil shows.
function WireArt.Grip(): CFrame
	return (CFrame.Angles(0.35, 0, 0) * CFrame.new(0, 0, 0)):Inverse()
end

return WireArt
