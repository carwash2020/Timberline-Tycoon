--!strict
-- GrassTufts (FOR-04): clumps of grass tufts round the camera, built on this
-- client only. Where each goes is WorldPlan's (TuftCell, TuftPlanAround):
-- deterministic, so every player sees the same grass. They sit at the forest's
-- fringe, on the road verges, round the rocks and at the fence posts.
--   * Cells of 32 studs. Within Quality.Budget().TuftNear of the camera a cell
--     holds its tufts (PropArt.GrassTuft); a loaded cell keeps its tufts
--     WorldPlan.TuftHysteresis past its radius.
--   * The work is spread out: it starts only after the player can play, the
--     deferred controllers (ClientBoot) have all started and the HUD has
--     settled, so it never lands on top of them. The rocks and scenery the
--     tufts gather round are worked out a slice a frame; then each frame
--     builds cells, nearest first, for at most TuftBuildMs (less when the
--     last frame was already slow: FrameBudget.Adapt), and unloads a few.
--   * Everything is decoration (Kit.decor: no collisions, clicks or touches)
--     and casts no shadow. Parts are cloned from one template per look.
-- Trees are not here: every tree in the world is a TreeService tree.
-- Everything lives in the workspace folder "GrassTufts".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientBoot = require(ReplicatedStorage.Shared.ClientBoot)
local FrameBudget = require(ReplicatedStorage.Shared.FrameBudget)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local TimeSlice = require(ReplicatedStorage.Shared.TimeSlice)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local Quality = require(script.Parent.Quality)

local GrassTufts = {}

local CELL = WorldPlan.TuftCellSize
local SCAN_EVERY = 0.5 -- seconds between looks round the camera
local MOVED_FAR = 24 -- studs the camera may move before an early look
local UNLOADS_PER_FRAME = 24
local TUFT_LOOKS = 8 -- looks per grass tint

type PartSpec = { template: BasePart, offset: Vector3, turn: CFrame, size: Vector3 }
type Job = { key: number, d: number }

local tuftCells: { [number]: { folder: Folder? } } = {}
local tuftLoaded: { [number]: boolean } = {} -- for TuftPlanAround
local tuftLooks: { [string]: { { PartSpec } } } = {}
local queue: { Job } = {} -- nearest last
local unloads: { number } = {}

local folder: Folder? = nil
local function root(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "GrassTufts"
	made.Parent = workspace
	folder = made
	return made
end

-- A grass tint's tuft looks (PropArt.GrassTuft), built once each.
local function tuftLook(biome: string, variant: number): { PartSpec }
	local list = tuftLooks[biome]
	if not list then
		list = {}
		tuftLooks[biome] = list
	end
	local look = list[variant]
	if not look then
		local parts: { PartSpec } = {}
		local model = PropArt.GrassTuft(variant * 37 + 5, PropArt.Tints(biome).grass)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local cf = d.CFrame
				d.Parent = nil
				table.insert(parts, { template = d, offset = cf.Position, turn = cf - cf.Position, size = d.Size })
			end
		end
		model:Destroy()
		list[variant] = parts
		look = parts
	end
	return look
end

-- Builds cell `key`'s grass tufts (no folder if it has none).
local function buildTufts(key: number)
	local cx, cz = WorldPlan.TuftCellOf(key)
	local made: Folder? = nil
	for _, tuft in ipairs(WorldPlan.TuftCell(cx, cz)) do
		local f: Folder
		local existing = made
		if existing then
			f = existing
		else
			f = Instance.new("Folder")
			f.Name = string.format("tuft %d %d", cx, cz)
			made = f
		end
		local base = CFrame.new(tuft.x, tuft.y, tuft.z) * CFrame.Angles(0, tuft.yaw, 0)
		for _, spec in ipairs(tuftLook(tuft.biome, tuft.seed % TUFT_LOOKS + 1)) do
			local p = spec.template:Clone()
			p.CFrame = base * CFrame.new(spec.offset) * spec.turn
			p.Parent = f
		end
	end
	if made then
		made.Parent = root()
	end
	tuftCells[key] = { folder = made }
	tuftLoaded[key] = true
end

local function unloadTufts(key: number)
	local cell = tuftCells[key]
	tuftCells[key] = nil
	tuftLoaded[key] = nil
	if cell and cell.folder then
		cell.folder:Destroy()
	end
end

-- Looks round the camera: what to build (nearest first) and what to unload.
local lastScanAt: Vector3? = nil
local function scan()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local p = camera.CFrame.Position
	lastScanAt = p
	local budget = Quality.Budget()
	table.clear(queue)
	table.clear(unloads)
	local tufts = WorldPlan.TuftPlanAround(p.X, p.Y, p.Z, budget.TuftNear, tuftLoaded)
	for key in pairs(tuftCells) do
		if not tufts[key] then
			table.insert(unloads, key)
		end
	end
	for key in pairs(tufts) do
		if not tuftCells[key] then
			local cx, cz = WorldPlan.TuftCellOf(key)
			local dx, dz = (cx + 0.5) * CELL - p.X, (cz + 0.5) * CELL - p.Z
			table.insert(queue, { key = key, d = dx * dx + dz * dz })
		end
	end
	table.sort(queue, function(a: Job, b: Job): boolean
		return a.d > b.d
	end)
end

local function work(frameDt: number)
	local n = 0
	while #unloads > 0 and n < UNLOADS_PER_FRAME do
		unloadTufts(table.remove(unloads) :: number)
		n += 1
	end
	local started = os.clock()
	-- A frame that was already slow builds less this time (one cell at least,
	-- so a run of slow frames cannot stop the grass for good).
	local shape = Quality.Budget()
	local budget = FrameBudget.Adapt(shape.TuftBuildMs, frameDt, 1 / math.max(shape.CosmeticHz, 1)) / 1000
	local built = 0
	while #queue > 0 and (built == 0 or os.clock() - started < budget) do
		built += 1
		local job = table.remove(queue) :: Job
		if not tuftCells[job.key] then
			buildTufts(job.key)
		end
	end
end

-- The tufts wait until the player is in the game (the loading card is gone)
-- and never delay the load (LOAD-01). At most WAIT_READY seconds.
local WAIT_READY = 40
local PLAN_SLICE = 0.008 -- seconds of planning per frame
local SETTLE_SECONDS = 1.5 -- after the player can play and the deferred controllers have started
local BOOT_WAIT = 10 -- the most it waits for the deferred controllers
local function waitUntilPlaying()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	local startedWaiting = os.clock()
	while os.clock() - startedWaiting < WAIT_READY do
		if player:GetAttribute("ProfileLoaded") == true and player.Character ~= nil then
			break
		end
		task.wait(0.25)
	end
	local boot = ClientBoot.Default
	local bootWaited = os.clock()
	while boot.Released() and not boot.Drained() and os.clock() - bootWaited < BOOT_WAIT do
		task.wait()
	end
	task.wait(SETTLE_SECONDS)
end

function GrassTufts.Start()
	task.spawn(function()
		waitUntilPlaying()
		-- What the tufts gather round (rocks, scenery) and the forest's trees
		-- (the cave points of interest are placed against them), a step a
		-- frame (each is cached for the next); every step pauses on a time slice.
		local planSlice = TimeSlice.new({ budget = PLAN_SLICE })
		for i, step in ipairs(WorldPlan.TuftSteps) do
			local ok, err = pcall(function(): any
				if step == WorldPlan.Trees then
					WorldPlan.Trees(planSlice.step)
				else
					WorldPlan.WithPause(planSlice.step, step)
				end
				return nil
			end)
			if not ok then
				warn(string.format("[GrassTufts] plan step %d failed, no grass tufts: %s", i, tostring(err)))
				return
			end
			task.wait()
		end
		planSlice.finish()
		local sinceScan = math.huge
		local sinceCosmetic = 0
		RunService.Heartbeat:Connect(function(dt: number)
			sinceCosmetic += dt
			if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
				return
			end
			local step = sinceCosmetic
			sinceCosmetic = 0
			sinceScan += step
			local camera = workspace.CurrentCamera
			local moved = if camera and lastScanAt
				then (camera.CFrame.Position - lastScanAt).Magnitude > MOVED_FAR
				else true
			if sinceScan >= SCAN_EVERY or moved then
				sinceScan = 0
				scan()
			end
			work(dt)
		end)
	end)
end

return GrassTufts
