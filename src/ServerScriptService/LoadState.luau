--!strict
-- LoadState: the server's start-up bookkeeping, shared by MapBuilder,
-- GameServer and the services that build late.
--
--   * Gates (Shared/ReadyGates): "meshes", "terrain", "town", "world",
--     "services", "firstPlayer", "npcs", "deferred". A system opens its gate
--     when it is usable; anything that needs it waits on, or is refused by,
--     the gate instead of assuming.
--   * Queue (Shared/LoadQueue): the deferred build. Anything nobody needs in
--     the first minute is Add-ed here and built after the world is ready,
--     nearest the players first, a slice at a time.
--   * Stage(id): the milestone shown on the client's loading bar (workspace
--     attribute "LoadStage", Shared/LoadStages).
--   * Track / Finish / Seal: what "fully built" means. Background work that
--     is not a queue step (the forest planter) is tracked by name; the
--     summary line prints when the queue is empty, every tracked job is done
--     and the server has sealed its start-up.
--   * The one summary line the next Studio run is read from:
--       [Load] ready for play at +X s; fully built at +Y s
--     X is when the first player could play (their save loaded), Y when the
--     last deferred step finished. Both count from this script's start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LoadQueue = require(ReplicatedStorage.Shared.LoadQueue)
local LoadStages = require(ReplicatedStorage.Shared.LoadStages)
local ReadyGates = require(ReplicatedStorage.Shared.ReadyGates)

local LoadState = {}

local t0 = os.clock()

-- Seconds since the server's scripts started.
function LoadState.Since(): number
	return os.clock() - t0
end

-- A `[Load] +X.Xs ...` line (the same shape MapBuilder's own lines use).
function LoadState.Line(what: string)
	print(string.format("[Load] +%.1fs %s", LoadState.Since(), what))
end

LoadState.Gates = ReadyGates.new()
for _, name in ipairs({ "meshes", "terrain", "town", "world", "services", "firstPlayer", "npcs", "deferred" }) do
	LoadState.Gates.Define(name)
end

-- Where the players are, for nearest-first: each character's root, else the
-- spawn area (the origin). A bad character never throws.
local function focus(): { LoadQueue.Point }
	local points: { LoadQueue.Point } = {}
	local okPlayers, list = pcall(function(): { Player }
		return game:GetService("Players"):GetPlayers()
	end)
	if not okPlayers then
		return points
	end
	for _, player in ipairs(list) do
		local char = player.Character
		local ok, position = pcall(function(): Vector3?
			local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				return root.Position
			end
			return nil
		end)
		if ok and position then
			table.insert(points, { x = position.X, z = position.Z })
		end
	end
	return points
end

LoadState.Queue = LoadQueue.new({
	budget = 0.012,
	focus = focus,
	log = function(line: string)
		print(string.format("%s (done at +%.1fs)", line, LoadState.Since()))
	end,
	traceback = function(err: any): string
		return debug.traceback(tostring(err), 2)
	end,
})

-- The milestone the client's loading bar shows. Only moves forward.
function LoadState.Stage(id: string)
	local ok = pcall(function()
		if LoadStages.IsLater(id, workspace:GetAttribute("LoadStage")) then
			workspace:SetAttribute("LoadStage", id)
		end
	end)
	if not ok then
		return
	end
	LoadState.Line("stage " .. id)
end

local tracked: { [string]: boolean } = {}
local sealed = false
local readyAt: number? = nil
local builtAt: number? = nil
local summarised = false

local function summarise()
	if summarised or readyAt == nil or builtAt == nil then
		return
	end
	summarised = true
	print(string.format("[Load] ready for play at +%.1f s; fully built at +%.1f s", readyAt, builtAt))
end

local function checkBuilt()
	if builtAt ~= nil or not sealed then
		return
	end
	if next(tracked) ~= nil or LoadState.Queue.Pending() > 0 or LoadState.Queue.Running() then
		return
	end
	builtAt = LoadState.Since()
	LoadState.Gates.Set("deferred")
	local stats = LoadState.Queue.Stats()
	LoadState.Line(
		string.format(
			"everything is built: %d deferred steps (%d failed) in %.1fs of work",
			stats.ran,
			stats.failed,
			stats.busySeconds
		)
	)
	summarise()
end

LoadState.Queue.OnIdle(checkBuilt)

-- Background work that is not a queue step (the forest planter): the server
-- is not "fully built" until every tracked name has Finish-ed.
function LoadState.Track(name: string)
	tracked[name] = true
end

function LoadState.Finish(name: string)
	tracked[name] = nil
	checkBuilt()
end

-- GameServer: every start-up step has been queued or run. From now "fully
-- built" can be declared as soon as the queue and tracked jobs are done.
function LoadState.Seal()
	sealed = true
	checkBuilt()
end

-- A player's save is loaded and they can play. The first call fixes X.
function LoadState.PlayerCanPlay(name: string)
	if readyAt ~= nil then
		return
	end
	readyAt = LoadState.Since()
	LoadState.Gates.Set("firstPlayer")
	LoadState.Line(string.format("first player %s can play", name))
	summarise()
end

-- For specs and the boot report: the two times (nil until they happen).
function LoadState.Times(): (number?, number?)
	return readyAt, builtAt
end

return LoadState
