--!strict
-- MeshKit: one way to get a MeshPart. A script cannot set MeshPart.MeshId,
-- so this clones a Rojo template under ReplicatedStorage.MeshTemplates or
-- asks AssetService. Both sit in a pcall. meshId 0, a failed load, or a
-- test run with no override returns nil and the caller keeps its old parts.
-- Tests set Override to hand back a MeshPart without the engine.
--
-- Failures are never silent: the first few are warned with the engine's own
-- error text, and MeshKit.Stats / MeshKit.Report give the totals (MapBuilder
-- prints them in the build check). The usual cause is asset permission: a
-- mesh only loads for an experience its owner allows (see PHASE2_NOTES.md,
-- "Creator Hub: mesh permissions"). A load is retried once; after
-- BlockAfter failures in a row with not one success, the kit stops asking
-- (each miss is slow) and says so once.
--
-- NEVER BLOCKS (12 October 2026, Connor's Studio log: "4. The shops done in
-- 300.2s", "meshes: 476 of 685 loaded ... (timed out)"). The world build called
-- Create for every piece and Create yielded in CreateMeshPartAsync, one mesh
-- after another, behind 24 preload workers that already held the asset
-- quota. Now Create on an uncached mesh returns nil at once (the caller keeps
-- its part-built art, exactly as for a failed load), asks for the mesh in the
-- background (Request) and, when the caller ran inside MeshKit.Attempt,
-- remembers to run the same dress step again when the mesh has arrived (the
-- swap: batched, a few milliseconds a frame, Pump). CreateAwait is the old
-- yielding call, for background threads only (tests/BuildBudget.spec fences
-- who may call it).
-- Each meshId is loaded once per server. Later uses clone that MeshPart.
-- Loads run side by side: MeshKit.Preload takes a list of ids and loads them
-- a couple of dozen at a time (Shared/WorkPool), and a Create for an id that
-- is being loaded waits for that load instead of starting another. One
-- CreateMeshPartAsync costs about a third of a second of network time, so
-- loading the NPCs' 150 pieces and the plot kit's pieces one after another
-- held server start for 70 s in Studio (7 October 2026); never load serially
-- on the start path.
-- A failed id is remembered and not tried again; the caller keeps the
-- part-built model. Collision is Box unless the caller passes Hull
-- (a wheel, or any shape a box would misrepresent).

local FrameBudget = require(script.Parent.Parent.FrameBudget)
local NearFirst = require(script.Parent.Parent.NearFirst)
local WorkPool = require(script.Parent.Parent.WorkPool)

local MeshKit = {}

export type OverrideFn = (meshId: number, name: string, size: Vector3) -> MeshPart?

MeshKit.Override = nil :: OverrideFn?

-- One loaded MeshPart per meshId, and ids that already failed.
local masters: { [number]: MeshPart } = {}
local failed: { [number]: boolean } = {}
local inflight: { [number]: boolean } = {} -- ids being loaded right now (a second asker waits)

-- The swap queue's state (see "The swap queue" below).
type Waiter = {
	remaining: number,
	dead: boolean,
	tries: number,
	alive: Instance?,
	attempt: () -> any,
	at: NearFirst.Point?, -- where it is (found once, for nearest-first)
}

local waiting: { [number]: { Waiter } } = {}
local ready: { Waiter } = {}
local readyHead = 1
local draining = false
local collecting: { [number]: boolean }? = nil
local swapped, swapSkipped, swapRetried = 0, 0, 0
local requested: { [number]: boolean } = {} -- ids asked for in the background
local requestQueue: { { id: number, fidelity: Enum.CollisionFidelity } } = {}
local requestHead = 1
local requestActive = 0

-- Injectable for specs (Lune has no `task`, and a spec wants to hold a load).
MeshKit.Scheduler = {
	spawn = function(fn: () -> ())
		-- (a spec's stub `task` may lack spawn)
		if type(task) == "table" and type(task.spawn) == "function" then
			task.spawn(fn)
		else
			fn()
		end
	end,
	wait = function()
		if type(task) == "table" and type(task.wait) == "function" then
			task.wait()
		end
	end,
	clock = os.clock,
}
-- Replaces the AssetService call (specs only): (meshId, collision) -> (part, why).
MeshKit.EngineLoad = nil :: ((number, Enum.CollisionFidelity) -> (MeshPart?, string?))?
MeshKit.RequestConcurrency = 24 -- background loads started by Create misses at once
MeshKit.SwapBudget = 0.004 -- seconds of dressing per Pump (one frame's slice)
-- Swap-ins land in bursts (696 in one Studio start: the shops, the boxes, the
-- vehicles, the machines), so a frame's drain is capped three ways: this many
-- swaps, SwapBudget seconds, and the shared frame budget when there is one.
-- A swap is always at least one a frame, so the queue never stalls.
MeshKit.SwapMaxPerFrame = 6
-- The budget the server's other background work shares (Shared/FrameBudget),
-- set by LoadState; nil on a client (it has its own frame to protect).
MeshKit.SwapFrame = nil :: FrameBudget.Budget?
-- Where the players are (their characters, or the camera): the swaps nearest
-- them run first. nil, or no points: the order they became ready in.
MeshKit.Focus = nil :: (() -> { NearFirst.Point })?

-- Lune has no AssetService. Remember that so every tree doesn't pay for the miss.
local noAssetService = false

-- Load accounting (engine path only; an Override never counts).
local loadedCount = 0
local failedCount = 0
local failStreak = 0
local blocked = false
local firstError: string? = nil
local failedIds: { number } = {}
local WARN_LIMIT = 5
MeshKit.BlockAfter = 8 -- failures in a row, none ever loaded, before giving up
MeshKit.Retries = 1 -- extra tries after a failed load, only until one has loaded

export type Stats = {
	loaded: number,
	failed: number,
	blocked: boolean,
	firstError: string?,
	failedIds: { number },
}

-- True once an engine-less run (Lune) has found there is no AssetService:
-- a miss then is not worth a warning.
function MeshKit.NoEngine(): boolean
	return noAssetService
end

function MeshKit.Stats(): Stats
	return {
		loaded = loadedCount,
		failed = failedCount,
		blocked = blocked,
		firstError = firstError,
		failedIds = failedIds,
	}
end

-- One line for the build check.
function MeshKit.Report(): string
	if noAssetService and loadedCount == 0 and failedCount == 0 then
		return "no AssetService here, part-built art"
	end
	local line = string.format("%d mesh assets loaded, %d failed", loadedCount, failedCount)
	if failedCount > 0 then
		line ..= " (first error: " .. tostring(firstError) .. ")"
		if blocked then
			line ..= "; gave up after " .. tostring(MeshKit.BlockAfter) .. " misses in a row: check asset permissions"
		end
	end
	return line
end

local PERMISSION_HELP = "Creator Hub > Creations > Assets: open each asset, Permissions, and allow this experience"
	.. " (and open Studio as the account that owns the assets). See PHASE2_NOTES.md."

local function noteFailure(meshId: number, err: string)
	failedCount += 1
	failStreak += 1
	table.insert(failedIds, meshId)
	if firstError == nil then
		firstError = err
	end
	if failedCount <= WARN_LIMIT then
		warn(string.format("[MeshKit] mesh %d did not load (%s). %s", meshId, err, PERMISSION_HELP))
	end
	if loadedCount == 0 and failStreak >= MeshKit.BlockAfter and not blocked then
		blocked = true
		warn(
			string.format(
				"[MeshKit] %d meshes in a row failed and none has loaded: no more tries this server."
					.. " Everything stays part-built. %s",
				failStreak,
				PERMISSION_HELP
			)
		)
	end
end

local function noteSuccess()
	loadedCount += 1
	failStreak = 0
end

-- Looks-only. Ticket I uses this same helper. CanCollide, CanTouch and
-- CanQuery are off, and the part is Massless, so it stays out of raycasts
-- (TruckLoad, the sell zone, the sawmill). WoodService.partsIn skips these.
-- meshId is stored as text: a number attribute truncates ids this large.
function MeshKit.Visual(part: BasePart, meshId: number)
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part:SetAttribute("VisualMesh", true)
	if type(meshId) == "number" and meshId == meshId and meshId ~= 0 then
		part:SetAttribute("MeshId", tostring(meshId))
	end
end

-- True when a part counts toward a gameplay budget (a section, a chassis).
function MeshKit.Counts(part: BasePart): boolean
	return part:GetAttribute("VisualMesh") ~= true
end

function MeshKit.Fidelity(part: MeshPart, name: Enum.RenderFidelity)
	pcall(function()
		part.RenderFidelity = name
	end)
end

-- Drops the load cache. Tests call this so one spec does not count as the server.
function MeshKit.Reset()
	for _, part in pairs(masters) do
		part:Destroy()
	end
	table.clear(masters)
	table.clear(failed)
	table.clear(inflight)
	loadedCount = 0
	failedCount = 0
	failStreak = 0
	blocked = false
	firstError = nil
	table.clear(failedIds)
	table.clear(waiting)
	table.clear(ready)
	readyHead = 1
	draining = false
	collecting = nil
	swapped, swapSkipped, swapRetried = 0, 0, 0
	table.clear(requested)
	table.clear(requestQueue)
	requestHead = 1
	requestActive = 0
end

local function finish(part: MeshPart, name: string, size: Vector3, collision: Enum.CollisionFidelity): MeshPart
	part.Name = name
	local native = part.Size
	local pivot = part.PivotOffset
	part.Size = size
	if native.X > 0.05 and native.Y > 0.05 and native.Z > 0.05 then
		local p = pivot.Position
		local scaled = Vector3.new(p.X * size.X / native.X, p.Y * size.Y / native.Y, p.Z * size.Z / native.Z)
		if scaled.Magnitude > 0.05 then
			part.PivotOffset = CFrame.new(scaled) * (pivot - p)
			part:SetAttribute("MeshPivot", "authored")
		end
	end
	pcall(function()
		part.CollisionFidelity = collision
	end)
	return part
end

local function fromTemplate(meshId: number): MeshPart?
	local ok, part = pcall(function(): MeshPart?
		local storage = game:GetService("ReplicatedStorage")
		local folder = storage:FindFirstChild("MeshTemplates")
		local template = if folder then folder:FindFirstChild(tostring(meshId)) else nil
		if not template or not template:IsA("MeshPart") then
			return nil
		end
		local clone = template:Clone()
		if not clone:IsA("MeshPart") then
			clone:Destroy()
			return nil
		end
		return clone
	end)
	if ok then
		return part
	end
	return nil
end

-- (part, nil) or (nil, why). `why` is the engine's own error text.
local function fromAssetService(meshId: number, collision: Enum.CollisionFidelity): (MeshPart?, string?)
	local custom = MeshKit.EngineLoad
	if custom then
		return custom(meshId, collision)
	end
	if noAssetService then
		return nil, "no AssetService"
	end
	local okService, assetService = pcall(function()
		return game:GetService("AssetService")
	end)
	if not okService or assetService == nil then
		noAssetService = true
		return nil, "no AssetService"
	end
	local uri = "rbxassetid://" .. tostring(meshId)
	local options = {
		CollisionFidelity = collision,
		RenderFidelity = Enum.RenderFidelity.Automatic,
	}
	local function take(value: any): MeshPart?
		if typeof(value) == "Instance" and value:IsA("MeshPart") then
			return value
		end
		return nil
	end
	local why: string? = nil
	local firstOk, first = pcall(function()
		return (assetService :: any):CreateMeshPartAsync((Content :: any).fromUri(uri), options)
	end)
	local created = if firstOk then take(first) else nil
	if not firstOk then
		why = tostring(first)
	end
	if not created then
		local secondOk, second = pcall(function()
			return (assetService :: any):CreateMeshPartAsync(uri, collision, Enum.RenderFidelity.Automatic)
		end)
		created = if secondOk then take(second) else nil
		if not secondOk and why == nil then
			why = tostring(second)
		end
	end
	if created then
		return created, nil
	end
	return nil, why or "no mesh came back"
end

-- Loads with a retry (a busy moment is not a permission problem). The
-- retries stop once any mesh has loaded: a miss after that is this id.
local function load(meshId: number, collision: Enum.CollisionFidelity): MeshPart?
	if blocked then
		return nil
	end
	local made, why = fromAssetService(meshId, collision)
	local tries = 0
	while not made and why ~= "no AssetService" and loadedCount == 0 and tries < MeshKit.Retries do
		tries += 1
		pcall(function()
			task.wait(0.5)
		end)
		made, why = fromAssetService(meshId, collision)
	end
	if made then
		noteSuccess()
		return made
	end
	local template = fromTemplate(meshId)
	if template then
		noteSuccess()
		return template
	end
	if why ~= "no AssetService" then
		noteFailure(meshId, tostring(why))
	end
	return nil
end

local function remember(meshId: number, part: MeshPart)
	part.Name = "MeshCache"
	masters[meshId] = part
end

-- The swap queue ------------------------------------------------------------
-- A dress step that missed only because a mesh was still loading is a Waiter:
-- it waits for every mesh it missed, then runs again from `ready`, a few
-- milliseconds per Pump. A mesh that FAILED cancels its waiters (the part-built
-- art is the answer for good).

local function falsy(result: any): boolean
	return result == nil or result == false or result == 0
end

local function missesOf(set: { [number]: boolean }): { number }
	local ids: { number } = {}
	for id in pairs(set) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function startDrain()
	if draining then
		return
	end
	draining = true
	MeshKit.Scheduler.spawn(function()
		while readyHead <= #ready do
			MeshKit.Pump()
			if readyHead <= #ready then
				MeshKit.Scheduler.wait()
			end
		end
		draining = false
	end)
end

-- Registers `attempt` to run again once every id in `ids` has loaded. Nothing
-- is registered when an id already failed (the fallback is final).
local function schedule(alive: Instance?, attempt: () -> any, ids: { number }, tries: number)
	local waiter: Waiter = { remaining = 0, dead = false, tries = tries, alive = alive, attempt = attempt }
	for _, id in ipairs(ids) do
		if failed[id] then
			return
		end
		if not masters[id] then
			waiter.remaining += 1
			local list = waiting[id]
			if not list then
				list = {}
				waiting[id] = list
			end
			table.insert(list, waiter)
		end
	end
	if waiter.remaining == 0 then
		table.insert(ready, waiter)
		startDrain()
	end
end

-- Called when an id has loaded or failed.
local function resolved(meshId: number)
	local list = waiting[meshId]
	if not list then
		return
	end
	waiting[meshId] = nil
	local any = false
	for _, waiter in ipairs(list) do
		if failed[meshId] then
			waiter.dead = true
		else
			waiter.remaining -= 1
			if waiter.remaining == 0 and not waiter.dead then
				table.insert(ready, waiter)
				any = true
			end
		end
	end
	if any then
		startDrain()
	end
end

-- Where a waiting dressing is, on the ground: its model's pivot or its part's
-- position; the origin when that cannot be read.
local function positionOf(waiter: Waiter): NearFirst.Point
	local known = waiter.at
	if known then
		return known
	end
	local x, z = 0, 0
	local inst = waiter.alive
	if inst then
		local ok, at = pcall(function(): Vector3?
			if inst:IsA("Model") then
				return inst:GetPivot().Position
			elseif inst:IsA("BasePart") then
				return inst.Position
			end
			return nil
		end)
		if ok and at then
			x, z = at.X, at.Z
		end
	end
	local made = { x = x, z = z }
	waiter.at = made
	return made
end

-- Puts the ready swaps in the order of the players' distance, nearest first.
local function orderReady()
	local focusFn = MeshKit.Focus
	if focusFn == nil or #ready - readyHead < 1 then
		return
	end
	local focus = focusFn()
	if #focus == 0 then
		return
	end
	local pending = table.move(ready, readyHead, #ready, 1, {})
	local sorted = NearFirst.Order(pending, positionOf, focus, { x = 0, z = 0 })
	table.move(sorted, 1, #sorted, readyHead, ready)
end

-- Runs ready swaps until `budget` seconds are spent (at least one runs).
-- Returns how many ran. The drain loop calls this once a frame; specs call it.
-- With no `budget` (the drain's frame) the swaps are also capped at
-- MeshKit.SwapMaxPerFrame, held to the shared frame budget, and the ones
-- nearest the players go first. An explicit budget is the caller's own: only
-- the time limit applies.
function MeshKit.Pump(budget: number?): number
	local limit = budget or MeshKit.SwapBudget
	local frameCall = budget == nil
	local maxRun = if frameCall then MeshKit.SwapMaxPerFrame else math.huge
	local frame = if frameCall then MeshKit.SwapFrame else nil
	local clock = MeshKit.Scheduler.clock
	local startedAt = clock()
	local ran = 0
	if frameCall then
		orderReady()
	end
	while readyHead <= #ready do
		local waiter = ready[readyHead]
		ready[readyHead] = nil :: any
		readyHead += 1
		local keep = waiter.alive == nil or waiter.alive.Parent ~= nil
		if keep and not waiter.dead then
			ran += 1
			local mine: { [number]: boolean } = {}
			local outer = collecting
			collecting = mine
			local ok, result = pcall(waiter.attempt)
			collecting = outer
			if not ok then
				warn("[MeshKit] a swapped-in mesh step failed: " .. tostring(result))
			elseif falsy(result) then
				swapRetried += 1
				if next(mine) ~= nil and waiter.tries < 3 then
					schedule(waiter.alive, waiter.attempt, missesOf(mine), waiter.tries + 1)
				end
			else
				swapped += 1
			end
		else
			swapSkipped += 1
		end
		if clock() - startedAt >= limit or ran >= maxRun or (frame ~= nil and frame.Over()) then
			break
		end
	end
	if readyHead > #ready then
		table.clear(ready)
		readyHead = 1
	end
	return ran
end

export type SwapStats = { waiting: number, ready: number, swapped: number, skipped: number, retried: number }

function MeshKit.SwapStats(): SwapStats
	local count = 0
	for _, list in pairs(waiting) do
		count += #list
	end
	return {
		waiting = count,
		ready = #ready - readyHead + 1,
		swapped = swapped,
		skipped = swapSkipped,
		retried = swapRetried,
	}
end

-- Makes sure `meshId`'s master is cached: true if it is (now), false if the
-- load failed. Safe to call from many threads at once: the first one loads,
-- the others wait for it.
local function ensure(meshId: number, fidelity: Enum.CollisionFidelity): boolean
	if masters[meshId] then
		return true
	end
	if failed[meshId] then
		return false
	end
	if inflight[meshId] then
		while inflight[meshId] do
			task.wait()
		end
		return (masters[meshId] :: MeshPart?) ~= nil
	end
	inflight[meshId] = true
	local okLoad, made = pcall(load, meshId, fidelity)
	inflight[meshId] = nil
	if okLoad and made then
		remember(meshId, made)
		resolved(meshId)
		return true
	end
	failed[meshId] = true
	resolved(meshId)
	return false
end

local function pumpRequests()
	while requestActive < MeshKit.RequestConcurrency and requestHead <= #requestQueue do
		local item = requestQueue[requestHead]
		requestQueue[requestHead] = nil :: any
		requestHead += 1
		requestActive += 1
		MeshKit.Scheduler.spawn(function()
			pcall(ensure, item.id, item.fidelity)
			requestActive -= 1
			pumpRequests()
		end)
	end
	if requestHead > #requestQueue then
		table.clear(requestQueue)
		requestHead = 1
	end
end

-- Asks for `meshId` in the background (a Create miss does this). Never yields.
function MeshKit.Request(meshId: number, fidelity: Enum.CollisionFidelity?)
	if masters[meshId] or failed[meshId] or inflight[meshId] or requested[meshId] then
		return
	end
	requested[meshId] = true
	table.insert(requestQueue, { id = meshId, fidelity = fidelity or Enum.CollisionFidelity.Box })
	pumpRequests()
end

-- True while `meshId` is on its way (asked for, not cached, not failed).
function MeshKit.IsPending(meshId: number): boolean
	return (masters[meshId] :: MeshPart?) == nil
		and not failed[meshId]
		and (inflight[meshId] == true or requested[meshId] == true)
end

-- True inside an Attempt when a Create missed only because a mesh is still on
-- its way: the caller's fallback is temporary, so it must not warn.
function MeshKit.WasPending(): boolean
	return collecting ~= nil and next(collecting) ~= nil
end

local function create(
	meshId: number,
	name: string,
	size: Vector3,
	collision: Enum.CollisionFidelity?,
	blocking: boolean
): MeshPart?
	if type(meshId) ~= "number" or meshId == 0 or meshId ~= meshId then
		return nil
	end
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return nil
	end
	if failed[meshId] then
		return nil
	end
	local fidelity = collision or Enum.CollisionFidelity.Box
	local master = masters[meshId]
	if master then
		return finish(master:Clone(), name, size, fidelity)
	end

	local override = MeshKit.Override
	if override then
		local ok, part = pcall(override, meshId, name, size)
		if not ok or typeof(part) ~= "Instance" or not part:IsA("MeshPart") then
			failed[meshId] = true
			return nil
		end
		remember(meshId, part)
		return finish(part:Clone(), name, size, fidelity)
	end

	-- The engine's import pivot (CreateMeshPartAsync) beats a template,
	-- which only has the mesh id. The template is the fallback.
	if not blocking then
		-- Not cached: never wait for it. The caller keeps its part-built art;
		-- the mesh is asked for in the background and, inside an Attempt, the
		-- dress step runs again when it lands.
		MeshKit.Request(meshId, fidelity)
		if failed[meshId] then
			return nil
		end
		local after = masters[meshId]
		if after then
			return finish(after:Clone(), name, size, fidelity)
		end
		local seen = collecting
		if seen then
			seen[meshId] = true
		end
		return nil
	end
	if not ensure(meshId, fidelity) then
		return nil
	end
	local loaded = masters[meshId]
	if not loaded then
		return nil
	end
	return finish(loaded:Clone(), name, size, fidelity)
end

-- A MeshPart named `name` at `size`, or nil. Never throws and NEVER YIELDS:
-- an uncached mesh is nil now (part-built art stays) and loads in the
-- background. `collision` defaults to Box. Pass Hull for a shape a box would
-- get wrong.
function MeshKit.Create(meshId: number, name: string, size: Vector3, collision: Enum.CollisionFidelity?): MeshPart?
	return create(meshId, name, size, collision, false)
end

-- The old yielding Create. Only for background threads and player actions
-- (tests/BuildBudget.spec lists who may call it); never on the world build.
function MeshKit.CreateAwait(meshId: number, name: string, size: Vector3, collision: Enum.CollisionFidelity?): MeshPart?
	return create(meshId, name, size, collision, true)
end

-- Runs a dress step (it calls Create, may fail, and leaves the part-built art
-- alone when it does). If it failed only because meshes were still loading,
-- the same step runs again, in the background and a few ms a frame, once they
-- have arrived: the swap. `alive` is the model being dressed; a step whose
-- model has been removed by then is dropped. `inBuildFrame`: the step writes
-- absolute coordinates (a model built at the origin and moved after), so the
-- swap puts the model back where it was built, dresses it, and moves it on
-- again. Returns what the step returned.
function MeshKit.Attempt<T>(alive: Instance?, attempt: () -> T, inBuildFrame: boolean?): T
	local outer = collecting
	local mine: { [number]: boolean } = {}
	collecting = mine
	local ok, result = pcall(attempt)
	collecting = outer
	if not ok then
		error(result, 0)
	end
	if falsy(result) and next(mine) ~= nil then
		local again: () -> any = attempt
		if inBuildFrame == true and alive ~= nil and alive:IsA("Model") then
			local model = alive :: Model
			local built = model:GetPivot()
			again = function(): any
				local now = model:GetPivot()
				model:PivotTo(built)
				local okRetry, value = pcall(attempt)
				model:PivotTo(now)
				if not okRetry then
					error(value, 0)
				end
				return value
			end
		end
		schedule(alive, again, missesOf(mine), 1)
	end
	return result :: T
end

export type Entry = { id: number, hull: boolean? }

export type PreloadResult = {
	total: number,
	loaded: number, -- ids cached when it ended (already cached ones too)
	failed: number,
	timedOut: boolean,
	seconds: number,
}

MeshKit.PreloadConcurrency = 24
MeshKit.PreloadTimeout = 40 -- seconds the join waits at most; stragglers go on by themselves

-- Loads every id at once-ish (MeshKit.PreloadConcurrency at a time) and
-- returns when all are cached or failed, or the timeout passes. Ids that are
-- already cached cost nothing. Never throws. With an Override (tests) it
-- asks the override for each id once.
function MeshKit.Preload(entries: { Entry }, options: { concurrency: number?, timeout: number? }?): PreloadResult
	local startedAt = os.clock()
	local wanted: { Entry } = {}
	local seen: { [number]: boolean } = {}
	for _, entry in ipairs(entries) do
		local id = entry.id
		if type(id) == "number" and id ~= 0 and id == id and not seen[id] and not masters[id] and not failed[id] then
			seen[id] = true
			table.insert(wanted, entry)
		end
	end
	local result = WorkPool.Run(wanted, function(entry: Entry)
		local fidelity = if entry.hull then Enum.CollisionFidelity.Hull else Enum.CollisionFidelity.Box
		if MeshKit.Override then
			local part = MeshKit.Create(entry.id, "Preload", Vector3.new(1, 1, 1), fidelity)
			if part then
				part:Destroy()
			end
			return
		end
		ensure(entry.id, fidelity)
	end, {
		concurrency = (options and options.concurrency) or MeshKit.PreloadConcurrency,
		timeout = (options and options.timeout) or MeshKit.PreloadTimeout,
	})
	local have, missed, distinct = 0, 0, 0
	local counted: { [number]: boolean } = {}
	for _, entry in ipairs(entries) do
		local id = entry.id
		if type(id) == "number" and id ~= 0 and not counted[id] then
			counted[id] = true
			distinct += 1
			if masters[id] then
				have += 1
			elseif failed[id] then
				missed += 1
			end
		end
	end
	return {
		total = distinct,
		loaded = have,
		failed = missed,
		timedOut = result.timedOut,
		seconds = os.clock() - startedAt,
	}
end

-- Preload on its own thread: returns at once, `onDone` (if any) gets the
-- result when the join ends. The way the start path asks for meshes.
function MeshKit.PreloadAsync(
	entries: { Entry },
	options: { concurrency: number?, timeout: number? }?,
	onDone: ((PreloadResult) -> ())?
)
	MeshKit.Scheduler.spawn(function()
		local result = MeshKit.Preload(entries, options)
		if onDone then
			onDone(result)
		end
	end)
end

-- True when `meshId` is cached (a clone is instant).
function MeshKit.Has(meshId: number): boolean
	return (masters[meshId] :: MeshPart?) ~= nil
end

return MeshKit
