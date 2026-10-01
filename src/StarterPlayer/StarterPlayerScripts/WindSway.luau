--!strict
-- WindSway: the wind in the trees, and the wind itself (REDESIGN.md "one
-- animator per tree": sway leaves busy trees alone).
--   * Canopies near the camera (the nearest 48 "Tree"-tagged trees within
--     120 studs) lean and rock gently about the top of their trunk: the
--     "Leaves" and "Frond" parts, every part of a pine's "Tier" models and
--     a frostwood's snow caps. Positions are absolute CFrames worked out
--     from rest offsets relative to the tree's HomePivot, written with one
--     workspace:BulkMoveTo a frame (half the trees each frame).
--   * A tree is left alone while TreeFX animates it (a fall, a regrow),
--     while it's felled, dormant or at 0 HP, and while its pivot is off
--     HomePivot (a hit wobble is playing). Trees leaving range are put
--     back exactly at rest.
--   * The wind (workspace.GlobalWind, set locally) gusts around the base
--     breeze (6, 0, 3) and blows harder in storms, blizzards and up on
--     the isles; grass, clouds and the weather's particles all follow it,
--     and the canopies lean the same way.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local LightingController = require(script.Parent.LightingController)
local TreeFX = require(script.Parent.TreeFX)

local WindSway = {}

local RANGE = 120
local MAX_TREES = 48
local SCAN_EVERY = 0.4
local WIND_EVERY = 0.1
local BASE_WIND = Vector3.new(6, 0, 3)

type Sway = {
	tree: Model,
	home: CFrame,
	parts: { BasePart },
	rest: { CFrame }, -- each part's rest CFrame (HomePivot * its offset)
	top: Vector3, -- the trunk's top: what the canopy rocks about
	phase: number,
	freq: number, -- radians per second; tall trees rock slower
}

local known: { [Model]: Vector3 } = {} -- every tree streamed in -> its home position
local sways: { [Model]: Sway } = {}
local order: { Sway } = {} -- the active ones, nearest first

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local windDir = BASE_WIND.Unit
local windStrength = 0.25

local function homeOf(tree: Model): CFrame?
	local home = tree:GetAttribute("HomePivot")
	return if typeof(home) == "CFrame" then home else nil
end

-- Whether WindSway may move this tree's leaves right now.
local function idle(tree: Model, home: CFrame): boolean
	if TreeFX.IsBusy(tree) then
		return false
	end
	if tree:GetAttribute("Felled") == true or tree:GetAttribute("Dormant") == true then
		return false
	end
	local hp = tree:GetAttribute("HP")
	if type(hp) == "number" and hp <= 0 then
		return false
	end
	local pivot = tree:GetPivot()
	if (pivot.Position - home.Position).Magnitude > 0.01 then
		return false
	end
	return pivot.RightVector:Dot(home.RightVector) > 0.99999 and pivot.UpVector:Dot(home.UpVector) > 0.99999
end

local CANOPY: { [string]: boolean } = { Leaves = true, Frond = true }

local function canopyParts(tree: Model): { BasePart }
	local out: { BasePart } = {}
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") then
			local parent = d.Parent
			local inTier = parent ~= nil and parent ~= tree and parent:IsA("Model") and parent.Name == "Tier"
			local snowCap = d.Name == "Facet" and parent == tree
			if CANOPY[d.Name] or inTier or snowCap then
				table.insert(out, d)
			end
		end
	end
	return out
end

local function capture(tree: Model): Sway?
	local home = homeOf(tree)
	if not home or not idle(tree, home) then
		return nil -- try again on a later scan
	end
	local parts = canopyParts(tree)
	if #parts == 0 then
		return nil
	end
	local rest: { CFrame } = {}
	for i, p in ipairs(parts) do
		-- The offset from HomePivot, then back to world space: the canopy's
		-- exact rest pose for as long as the tree stands here.
		rest[i] = home * home:ToObjectSpace(p.CFrame)
	end
	local trunk = tree.PrimaryPart
	local length = if trunk then trunk.Size.X else 8
	local top = home.Position + home.RightVector * (length / 2)
	local p = home.Position
	local phase = (math.sin(p.X * 0.137 + p.Z * 0.071) * 0.5 + 0.5) * math.pi * 2
	return {
		tree = tree,
		home = home,
		parts = parts,
		rest = rest,
		top = top,
		phase = phase,
		freq = 1.15 / math.sqrt(math.max(0.6, length / 12)),
	}
end

local function restore(s: Sway)
	local home = homeOf(s.tree)
	if s.tree.Parent == nil or not home or not idle(s.tree, home) then
		return -- busy or gone: TreeFX (or streaming) owns it now
	end
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for i, part in ipairs(s.parts) do
		if part.Parent then
			table.insert(parts, part)
			table.insert(frames, s.rest[i])
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function addTree(inst: Instance)
	if inst:IsA("Model") and not known[inst] then
		local home = homeOf(inst)
		known[inst] = if home then home.Position else inst:GetPivot().Position
	end
end

local function removeTree(inst: Instance)
	if inst:IsA("Model") then
		known[inst] = nil
		sways[inst] = nil -- streamed out: its parts are gone with it
	end
end

-- Picks the trees to sway: the nearest MAX_TREES within RANGE.
local function scan()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local near: { { tree: Model, d: number } } = {}
	for tree, p in pairs(known) do
		local d = (p - eye).Magnitude
		if d <= RANGE then
			table.insert(near, { tree = tree, d = d })
		end
	end
	table.sort(near, function(a, b)
		return a.d < b.d
	end)
	local keep: { [Model]: boolean } = {}
	table.clear(order)
	for i = 1, math.min(#near, MAX_TREES) do
		local tree = near[i].tree
		keep[tree] = true
		local s: Sway? = sways[tree]
		if s then
			-- A tree whose HomePivot moved (replanted elsewhere): start over.
			local home = homeOf(tree)
			if home and (home.Position - s.home.Position).Magnitude > 0.01 then
				sways[tree] = nil
				s = nil
			end
		end
		if not s then
			s = capture(tree)
			if s then
				sways[tree] = s
			end
		end
		if s then
			table.insert(order, s)
		end
	end
	for tree, s in pairs(sways) do
		if not keep[tree] then
			restore(s)
			sways[tree] = nil
		end
	end
end

local frame = 0

local function swayAll(now: number)
	frame += 1
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	table.clear(moveParts)
	table.clear(moveFrames)
	local strength = windStrength
	local dir = windDir
	local axis = Vector3.new(0, 1, 0):Cross(dir) -- turning about this tips the crown downwind
	local amplitude = 0.008 + strength * 0.04
	for i, s in ipairs(order) do
		if (i + frame) % 2 ~= 0 then
			continue -- half the trees each frame
		end
		local tree = s.tree
		if tree.Parent == nil or not idle(tree, s.home) then
			continue
		end
		if (s.top - eye):Dot(look) < -25 then
			continue -- behind the camera: nobody sees it rock
		end
		local gust = math.noise(now * 0.3 + s.phase, s.phase * 0.7)
		local lean = strength * 0.015 + gust * strength * 0.03
		local angle = lean + math.sin(now * s.freq + s.phase) * amplitude
		local side = math.sin(now * s.freq * 0.71 + s.phase * 1.7) * amplitude * 0.35
		local turn = CFrame.fromAxisAngle(axis, angle) * CFrame.fromAxisAngle(dir, side)
		local sway = CFrame.new(s.top) * turn * CFrame.new(-s.top)
		for k, part in ipairs(s.parts) do
			table.insert(moveParts, part)
			table.insert(moveFrames, sway * s.rest[k])
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- The wind: a steady breeze that wanders a little and gusts, stronger in
-- rough weather.
local function updateWind(now: number)
	local env = LightingController.Environment()
	windStrength = env.wind
	local baseAngle = math.atan2(BASE_WIND.Z, BASE_WIND.X)
	local angle = baseAngle + math.noise(now * 0.02, 3.3) * 0.7
	local gust = 0.75 + 0.5 * math.clamp(math.noise(now * 0.12, 9.1) + 0.5, 0, 1)
	windDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local speed = BASE_WIND.Magnitude * gust * (0.55 + env.wind * 1.4)
	workspace.GlobalWind = windDir * speed
	-- Gusts lean the trees a little further.
	windStrength = env.wind * (0.8 + 0.4 * (gust - 0.75) / 0.5)
end

function WindSway.Start()
	for _, inst in ipairs(CollectionService:GetTagged("Tree")) do
		addTree(inst)
	end
	CollectionService:GetInstanceAddedSignal("Tree"):Connect(addTree)
	CollectionService:GetInstanceRemovedSignal("Tree"):Connect(removeTree)

	local sinceScan = math.huge
	local sinceWind = math.huge
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		sinceWind += dt
		if sinceWind >= WIND_EVERY then
			sinceWind = 0
			updateWind(now)
		end
		sinceScan += dt
		if sinceScan >= SCAN_EVERY then
			sinceScan = 0
			scan()
		end
		swayAll(now)
	end)
end

return WindSway
