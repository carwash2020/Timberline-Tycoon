--!strict
-- WindSway: the wind in the trees, and the wind itself (REDESIGN.md "one
-- animator per tree": sway leaves busy trees alone).
--   * Canopies near the camera (the nearest 32 "Tree"-tagged trees within
--     120 studs, or 16 within 80 on low quality) lean and rock gently
--     about the top of their trunk: the "Leaves" and "Frond" parts, every
--     part of a pine's "Tier" models and a frostwood's snow caps.
--     Positions are absolute CFrames worked out from rest offsets
--     relative to the tree's HomePivot and the time (never accumulated,
--     so a tree that sits out a few frames picks up exactly where it would
--     have been), written with one workspace:BulkMoveTo a frame.
--   * A frame moves at most 900 canopy parts, 400 on low quality
--     (PLAY-04; the tiers are Quality.Budget(), PLAY-05): it walks the
--     trees round-robin from where the last frame stopped
--     (WindSway.PlanFrame), so in a dense frostwood stand (96 parts a
--     tree) each tree updates every few frames, and in the Starter Forest
--     (11-21 parts) every tree updates every frame.
--   * A tree is left alone while TreeFX animates it (a fall, a regrow),
--     while it's felled, dormant or at 0 HP, and while its pivot is off
--     HomePivot (a hit wobble is playing). Trees leaving range are put
--     back exactly at rest; one that is busy as it leaves is put back as
--     soon as it's idle again.
--   * NAT-09: each canopy part's rest offset from HomePivot is recorded
--     once, the first time WindSway sees the part (before it ever moves
--     it), and kept until the tree streams out. A canopy WindSway left
--     leaning (felled or wobbling as you walked away) is never re-read as
--     the rest pose, so it can't be baked in.
--   * v2 section trees (M1.3) rock about the top of their trunk (their
--     SwayTop attribute; their PrimaryPart's length is up its Y axis), and
--     a tree that loses parts (a limb cut free, leaves dropped before it
--     dies) is captured afresh, so a falling piece's leaves are never
--     pulled back to where they hung.
--   * The wind (workspace.GlobalWind, set locally) gusts around the base
--     breeze (6, 0, 3) and blows harder in storms, blizzards and up on
--     the isles; grass, clouds and the weather's particles all follow it,
--     and the canopies lean the same way.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local LightingController = require(script.Parent.LightingController)
local Quality = require(script.Parent.Quality)
local TreeFX = require(script.Parent.TreeFX)

local WindSway = {}

-- How far, how many trees and how many parts a frame: Quality.Budget()'s
-- SwayRange, SwayTrees and SwayParts (Shared/QualityBudgets).
local SCAN_EVERY = 0.4
local WIND_EVERY = 0.1
local BASE_WIND = Vector3.new(6, 0, 3)

type Sway = {
	tree: Model,
	home: CFrame,
	parts: { BasePart },
	rest: { CFrame }, -- each part's rest CFrame (HomePivot * its offset)
	top: Vector3, -- the trunk's top: what the canopy rocks about
	v2: boolean, -- a section tree: its parts can leave it (a cut limb, dropped leaves)
	phase: number,
	freq: number, -- radians per second; tall trees rock slower
}

local known: { [Model]: Vector3 } = {} -- every tree streamed in -> its home position
-- Each canopy part's offset from HomePivot (its server pose), for as long
-- as the tree instance lives: written the first time WindSway sees the
-- part and cleared only in removeTree (NAT-09).
local restOf: { [Model]: { [BasePart]: CFrame } } = {}
local sways: { [Model]: Sway } = {}
local order: { Sway } = {} -- the active ones, nearest first
local unrestored: { [Model]: Sway } = {} -- left range while busy: put back once idle
local cursor = 1 -- where in `order` the next frame's walk starts

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
	local offsets = restOf[tree]
	if not offsets then
		offsets = {}
		restOf[tree] = offsets
	end
	local rest: { CFrame } = {}
	for i, p in ipairs(parts) do
		local offset = offsets[p]
		if not offset then
			-- First sight of this part, before WindSway ever moved it: its
			-- offset from HomePivot is the server's.
			offset = home:ToObjectSpace(p.CFrame)
			offsets[p] = offset
		end
		rest[i] = home * offset -- the canopy's exact rest pose, in world space
	end
	local trunk = tree.PrimaryPart
	local length = if trunk then trunk.Size.X else 8
	local top = home.Position + home.RightVector * (length / 2)
	local swayTop = tree:GetAttribute("SwayTop")
	if typeof(swayTop) == "Vector3" then
		-- A v2 section tree: its trunk's top, and how tall that is.
		top = swayTop
		length = math.max(4, swayTop.Y - (home.Position.Y - (if trunk then trunk.Size.Y / 2 else 0)))
	end
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
		v2 = typeof(swayTop) == "Vector3",
	}
end

-- Puts a tree's canopy back at rest. False while it's busy (TreeFX owns
-- it now): try again later.
local function restore(s: Sway): boolean
	if s.tree.Parent == nil then
		return true -- streamed out: its parts are gone with it
	end
	local home = homeOf(s.tree)
	if not home then
		return true -- no HomePivot to judge it by: nothing we can do
	end
	if not idle(s.tree, home) then
		return false
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
	return true
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
		unrestored[inst] = nil
		restOf[inst] = nil
	end
end

-- Picks the trees to sway: the nearest SwayTrees within SwayRange.
local function scan()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local budget = Quality.Budget()
	local eye = camera.CFrame.Position
	local near: { { tree: Model, d: number } } = {}
	for tree, p in pairs(known) do
		local d = (p - eye).Magnitude
		if d <= budget.SwayRange then
			table.insert(near, { tree = tree, d = d })
		end
	end
	table.sort(near, function(a, b)
		return a.d < b.d
	end)
	local keep: { [Model]: boolean } = {}
	table.clear(order)
	for i = 1, math.min(#near, budget.SwayTrees) do
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
			sways[tree] = nil
			if not restore(s) then
				unrestored[tree] = s -- falling, regrowing or wobbling
			end
		end
	end
	for tree, s in pairs(unrestored) do
		if sways[tree] or restore(s) then
			unrestored[tree] = nil -- swaying again, or back at rest
		end
	end
end

-- Picks this frame's trees (PLAY-04). Walks the `count` trees round-robin
-- from `start`, taking each one whose cost (its canopy part count, from
-- `costOf`) still fits in `budget`, and stops at the first that doesn't:
-- the next frame starts there, so every tree gets its turn. A tree that
-- costs 0 (busy, felled, behind the camera) is passed over for free, and
-- one that costs more than the whole budget is passed over too, so no
-- frame ever moves more than `budget` parts and nothing stalls the walk.
-- Calls `take(i)` for each tree it picks and returns the next frame's
-- cursor. Pure (tests/WindSway.spec.luau).
function WindSway.PlanFrame(
	count: number,
	start: number,
	budget: number,
	costOf: (number) -> number,
	take: (number) -> ()
): number
	if count <= 0 then
		return 1
	end
	local i = if start >= 1 and start <= count then start else 1
	local spent = 0
	for _ = 1, count do
		local cost = costOf(i)
		if cost > 0 and cost <= budget then
			if spent + cost > budget then
				return i -- full: this one goes first next frame
			end
			spent += cost
			take(i)
		end
		i = i % count + 1
	end
	return i -- every tree had its turn this frame
end

-- This frame's camera and wind, set once a frame for costOf and swayOne
-- (so the planner's callbacks are made once, not every frame).
local frameNow = 0
local frameEye = Vector3.zero
local frameLook = Vector3.new(0, 0, -1)
local frameDir = BASE_WIND.Unit
local frameAxis = Vector3.new(0, 1, 0):Cross(frameDir)
local frameStrength = 0
local frameAmplitude = 0

-- How many parts swaying order[i] this frame would move: 0 to pass it over.
local function costOf(i: number): number
	local s = order[i]
	local tree = s.tree
	if tree.Parent == nil or not idle(tree, s.home) then
		return 0
	end
	if s.v2 then
		-- A v2 tree whose parts left it (a limb cut free, its leaves dropped)
		-- starts over with what it has now: the parts that left are never
		-- moved again (they fall with their piece).
		for _, part in ipairs(s.parts) do
			if not part:IsDescendantOf(tree) then
				sways[tree] = nil
				local offsets = restOf[tree]
				if offsets then
					for _, p in ipairs(s.parts) do
						if not p:IsDescendantOf(tree) then
							offsets[p] = nil
						end
					end
				end
				return 0
			end
		end
	end
	if (s.top - frameEye):Dot(frameLook) < -25 then
		return 0 -- behind the camera: nobody sees it rock
	end
	return #s.parts
end

-- Queues order[i]'s canopy at its pose for this moment: a function of the
-- time and the wind alone.
local function swayOne(i: number)
	local s = order[i]
	local now, strength, amplitude = frameNow, frameStrength, frameAmplitude
	local gust = math.noise(now * 0.3 + s.phase, s.phase * 0.7)
	local lean = strength * 0.015 + gust * strength * 0.03
	local angle = lean + math.sin(now * s.freq + s.phase) * amplitude
	local side = math.sin(now * s.freq * 0.71 + s.phase * 1.7) * amplitude * 0.35
	local turn = CFrame.fromAxisAngle(frameAxis, angle) * CFrame.fromAxisAngle(frameDir, side)
	local sway = CFrame.new(s.top) * turn * CFrame.new(-s.top)
	for k, part in ipairs(s.parts) do
		table.insert(moveParts, part)
		table.insert(moveFrames, sway * s.rest[k])
	end
end

local function swayAll(now: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	frameNow = now
	frameEye = camera.CFrame.Position
	frameLook = camera.CFrame.LookVector
	frameStrength = windStrength
	frameDir = windDir
	frameAxis = Vector3.new(0, 1, 0):Cross(windDir) -- turning about this tips the crown downwind
	frameAmplitude = 0.008 + windStrength * 0.04
	table.clear(moveParts)
	table.clear(moveFrames)
	cursor = WindSway.PlanFrame(#order, cursor, Quality.Budget().SwayParts, costOf, swayOne)
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
