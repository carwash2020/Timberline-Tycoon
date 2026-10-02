--!strict
-- ForestFiller (phase 10, FOR-02): the forest ring's trees (WorldLayout's
-- band layout), built on this client only, round the camera. Where every
-- tree goes is WorldPlan's (FillerCellTrees, FillerFarCell,
-- FillerPlanAround): deterministic, so every player sees the same forest.
--   * Cells of 32 studs. Within Quality.Budget().FillerNear of the camera
--     a cell holds its filler trees (PropArt.FillerTree: 3-5 parts each);
--     out to FillerFar, one or two dark canopy blocks, so the forest reads
--     from far off. A cell keeps its look WorldPlan.FillerHysteresis past
--     its radius, so walking along an edge doesn't flip it to and fro.
--   * The work is spread out: WorldPlan's plan (the trees, rocks and
--     scenery the filler keeps clear of) is worked out one step a frame at
--     start; then each frame builds cells, nearest first, for at most
--     FillerBuildMs, and unloads a few. A cell's new look is in before its
--     old one goes, so nothing pops out.
--   * Everything is decoration (Kit.decor: no collisions, clicks or
--     touches; a collider only this client had would fight the trucks,
--     which their drivers' clients simulate) and casts no shadow. Parts are
--     cloned from one template per look, then sized and placed.
--   * A crown between the camera and what it looks at (or round the camera
--     itself) fades (LocalTransparencyModifier), so the forest never hides
--     your character.
-- Everything lives in the workspace folder "ForestFiller".

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local Quality = require(script.Parent.Quality)

local ForestFiller = {}

local CELL = WorldPlan.FillerCellSize
local SCAN_EVERY = 0.5 -- seconds between looks round the camera
local MOVED_FAR = 24 -- studs the camera may move before an early look
local UNLOADS_PER_FRAME = 24
local FADE_EVERY = 0.1
local FADE_TO = 0.75 -- a faded crown's LocalTransparencyModifier

-- One look of one kind: its parts (templates to clone), where they sit
-- round the tree's foot, and its crown's middle and reach (for the fade).
type PartSpec = { template: BasePart, offset: Vector3, turn: CFrame, size: Vector3, crown: boolean }
type Look = { parts: { PartSpec }, crownY: number, crownR: number }
local looks: { [string]: { Look } } = {}
local farTemplate: Part? = nil

type Tree = { crown: { BasePart }, at: Vector3, r: number }
type Cell = { mode: string, folder: Folder?, trees: { Tree } }
local cells: { [number]: Cell } = {}
local modes: { [number]: string } = {} -- each loaded cell's look, for FillerPlanAround
type Job = { key: number, mode: string, d: number }
local queue: { Job } = {} -- nearest last
local unloads: { number } = {}

local folder: Folder? = nil
local function root(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "ForestFiller"
	made.Parent = workspace
	folder = made
	return made
end

-- Each kind's looks, built once from PropArt's builders.
local function makeLooks()
	for _, kind in ipairs(PropArt.FillerKinds) do
		local list: { Look } = {}
		for variant = 1, PropArt.FillerVariants do
			local model = PropArt.FillerTree(kind, variant)
			local parts: { PartSpec } = {}
			local lo, hi, reach = math.huge, -math.huge, 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local cf = d.CFrame
					local crown = d.Name ~= "FillerTrunk"
					d.Parent = nil
					table.insert(parts, {
						template = d,
						offset = cf.Position,
						turn = cf - cf.Position,
						size = d.Size,
						crown = crown,
					})
					if crown then
						local half = d.Size.Magnitude / 2
						lo, hi = math.min(lo, cf.Position.Y - half), math.max(hi, cf.Position.Y + half)
						reach = math.max(reach, Vector3.new(cf.Position.X, 0, cf.Position.Z).Magnitude + half * 0.8)
					end
				end
			end
			model:Destroy()
			local crownY = if lo < hi then (lo + hi) / 2 else 0
			table.insert(list, { parts = parts, crownY = crownY, crownR = math.max(reach, (hi - lo) / 2) })
		end
		looks[kind] = list
	end
	local holder = Instance.new("Folder")
	local block = Kit.part(
		holder,
		"FillerFar",
		Vector3.one,
		CFrame.identity,
		PropArt.FillerFarColor("broad"),
		Enum.Material.SmoothPlastic
	)
	Kit.decor(block, false)
	block.Parent = nil
	holder:Destroy()
	farTemplate = block
end

local function buildTree(parent: Folder, tree: WorldPlan.FillerTree): Tree?
	local list = looks[tree.kind] or looks.broad
	local look = if list then list[tree.variant] or list[1] else nil
	if not look then
		return nil
	end
	local s = tree.scale
	local base = CFrame.new(tree.x, tree.y, tree.z) * CFrame.Angles(0, tree.yaw, 0)
	local crown: { BasePart } = {}
	for _, spec in ipairs(look.parts) do
		local p = spec.template:Clone()
		p.Size = spec.size * s
		p.CFrame = base * CFrame.new(spec.offset * s) * spec.turn
		p.Parent = parent
		if spec.crown then
			table.insert(crown, p)
		end
	end
	return { crown = crown, at = Vector3.new(tree.x, tree.y + look.crownY * s, tree.z), r = look.crownR * s }
end

-- Builds cell `key` in `mode` ("near" trees or "far" blocks). A cell with
-- nothing in it gets no folder.
local function build(key: number, mode: string): Cell
	local cx, cz = WorldPlan.FillerCellOf(key)
	local trees: { Tree } = {}
	local made: Folder? = nil
	local function holder(): Folder
		local existing = made
		if existing then
			return existing
		end
		local f = Instance.new("Folder")
		f.Name = string.format("%s %d %d", mode, cx, cz)
		made = f
		return f
	end
	if mode == "near" then
		for _, spot in ipairs(WorldPlan.FillerCellTrees(cx, cz)) do
			local tree = buildTree(holder(), spot)
			if tree then
				table.insert(trees, tree)
			end
		end
	else
		local template = farTemplate
		if template then
			for _, b in ipairs(WorldPlan.FillerFarCell(cx, cz)) do
				local p = template:Clone()
				p.Size = b.size
				p.CFrame = b.cframe
				p.Color = PropArt.FillerFarColor(b.kind)
				p.Parent = holder()
			end
		end
	end
	if made then
		made.Parent = root()
	end
	return { mode = mode, folder = made, trees = trees }
end

local function unload(key: number)
	local cell = cells[key]
	if cell then
		cells[key] = nil
		modes[key] = nil
		if cell.folder then
			cell.folder:Destroy()
		end
	end
end

-- Looks round the camera: what to build (nearest first, real trees before
-- stand-ins) and what to unload.
local lastScanAt: Vector3? = nil
local function scan()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local p = camera.CFrame.Position
	lastScanAt = p
	local budget = Quality.Budget()
	local plan = WorldPlan.FillerPlanAround(p.X, p.Y, p.Z, budget.FillerNear, budget.FillerFar, modes)
	table.clear(queue)
	table.clear(unloads)
	for key in pairs(cells) do
		if not plan[key] then
			table.insert(unloads, key)
		end
	end
	for key, mode in pairs(plan) do
		if modes[key] ~= mode then
			local cx, cz = WorldPlan.FillerCellOf(key)
			local dx, dz = (cx + 0.5) * CELL - p.X, (cz + 0.5) * CELL - p.Z
			-- Real trees first, then the stand-ins, each nearest first.
			table.insert(queue, { key = key, mode = mode, d = dx * dx + dz * dz + (if mode == "near" then 0 else 1e8) })
		end
	end
	table.sort(queue, function(a: Job, b: Job): boolean
		return a.d > b.d
	end)
end

local function work()
	local n = 0
	while #unloads > 0 and n < UNLOADS_PER_FRAME do
		unload(table.remove(unloads) :: number)
		n += 1
	end
	local started = os.clock()
	local budget = Quality.Budget().FillerBuildMs / 1000
	while #queue > 0 and os.clock() - started < budget do
		local job = table.remove(queue) :: Job
		local old = cells[job.key]
		cells[job.key] = build(job.key, job.mode)
		modes[job.key] = job.mode
		if old and old.folder then
			old.folder:Destroy() -- after the new look is in
		end
	end
end

-- The crowns in the way: between the camera and its focus, or round the
-- camera itself.
local faded: { [Tree]: boolean } = {}
local function fade()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local c, f = camera.CFrame.Position, camera.Focus.Position
	local seg = f - c
	local len2 = seg:Dot(seg)
	local now: { [Tree]: boolean } = {}
	local pad = 12
	for cx = (math.min(c.X, f.X) - pad) // CELL, (math.max(c.X, f.X) + pad) // CELL do
		for cz = (math.min(c.Z, f.Z) - pad) // CELL, (math.max(c.Z, f.Z) + pad) // CELL do
			local cell = cells[WorldPlan.FillerCellKey(cx, cz)]
			if cell and cell.mode == "near" then
				for _, tree in ipairs(cell.trees) do
					local t = if len2 > 1e-6 then math.clamp((tree.at - c):Dot(seg) / len2, 0, 1) else 0
					local d = (c + seg * t - tree.at).Magnitude
					if d < tree.r or (tree.at - c).Magnitude < tree.r + 2 then
						now[tree] = true
					end
				end
			end
		end
	end
	for tree in pairs(now) do
		if not faded[tree] then
			for _, p in ipairs(tree.crown) do
				p.LocalTransparencyModifier = FADE_TO
			end
		end
	end
	for tree in pairs(faded) do
		if not now[tree] then
			for _, p in ipairs(tree.crown) do
				p.LocalTransparencyModifier = 0
			end
		end
	end
	faded = now
end

function ForestFiller.Start()
	task.spawn(function()
		-- WorldPlan's plan, a step a frame (each is cached for the next).
		local started = os.clock()
		for i, step in ipairs(WorldPlan.FillerSteps) do
			local ok, err = pcall(step)
			if not ok then
				warn(string.format("[ForestFiller] plan step %d failed, no filler forest: %s", i, tostring(err)))
				return
			end
			task.wait()
		end
		makeLooks()
		print(string.format("[ForestFiller] plan ready in %.1f s", os.clock() - started))
		local sinceScan, sinceFade = math.huge, 0
		RunService.Heartbeat:Connect(function(dt: number)
			sinceScan += dt
			sinceFade += dt
			local camera = workspace.CurrentCamera
			local moved = if camera and lastScanAt
				then (camera.CFrame.Position - lastScanAt).Magnitude > MOVED_FAR
				else true
			if sinceScan >= SCAN_EVERY or moved then
				sinceScan = 0
				scan()
			end
			work()
			if sinceFade >= FADE_EVERY then
				sinceFade = 0
				fade()
			end
		end)
	end)
end

return ForestFiller
