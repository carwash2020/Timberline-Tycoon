--!strict
-- TownBoardService: builds the town leaderboard board at the town's
-- LeaderboardBoard anchor and keeps its text current (Lane X).
--
--   * The board is built once, on the server, so every player sees the same
--     rows. It is persistent under StreamingEnabled and sits on the ground
--     (a post is never in the air or under the terrain).
--   * It never reads a DataStore. It shows LeaderboardService.Top(), the
--     cache the Settings tab already uses, and redraws when that cache is
--     read again (LeaderboardService.OnRefresh, at most once a minute).
--     Only players who opted in are in that list.
--   * Booted by TownBoardBoot.server (V1Boot is left alone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local TownBoardArt = require(ReplicatedStorage.Shared.Art.TownBoardArt)
local TownBoardLogic = require(ReplicatedStorage.Shared.TownBoardLogic)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local LeaderboardService = require(script.Parent.LeaderboardService)

export type InitOptions = {
	parent: Instance?, -- where the board goes (default: workspace.TimberlineMap, waited for)
	cframe: CFrame?, -- where it stands (default: WorldPlan.LeaderboardBoard)
	ground: ((x: number, z: number) -> number)?, -- terrain height (default: TerrainGen)
	top: (() -> { any }?)?, -- LeaderboardService.Top (tests)
	failed: (() -> boolean)?, -- LeaderboardService.Failed (tests)
	onRefresh: ((fn: () -> ()) -> ())?, -- LeaderboardService.OnRefresh (tests)
}

local TownBoardService = {}

local board: Model? = nil
local lastSignature = ""
local topFn: () -> { any }? = LeaderboardService.Top
local failedFn: () -> boolean = LeaderboardService.Failed

local function terrainHeight(x: number, z: number): number
	local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
	return TerrainGen.HeightAt(x, z)
end

-- How far up the board must stand so its posts are on the ground: the
-- highest terrain under the posts and the middle. (Never below the plan's
-- own y; the plan puts the town at y = 0.)
function TownBoardService.GroundLift(cf: CFrame, ground: (number, number) -> number): number
	local lift = cf.Position.Y
	for _, dx in ipairs({ -TownBoardLogic.PostX, 0, TownBoardLogic.PostX }) do
		local p = cf:PointToWorldSpace(Vector3.new(dx, 0, 0))
		local ok, h = pcall(ground, p.X, p.Z)
		if ok and type(h) == "number" and h == h and h > lift then
			lift = h
		end
	end
	return lift
end

-- Builds the board, stands it at `cf` on the ground and parents it.
function TownBoardService.Place(parent: Instance, cf: CFrame, ground: ((number, number) -> number)?): Model
	local model = TownBoardArt.Build()
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local lift = TownBoardService.GroundLift(cf, ground or terrainHeight)
	local _, yaw = cf:ToEulerAnglesYXZ()
	Kit.placeAt(model, CFrame.new(cf.Position.X, lift, cf.Position.Z) * CFrame.Angles(0, yaw, 0))
	model.Parent = parent
	return model
end

local function signature(view: TownBoardLogic.View): string
	local parts: { string } = { view.state, view.message }
	for _, line in ipairs(view.lines) do
		table.insert(parts, line.rank .. "|" .. line.name .. "|" .. line.cash)
	end
	return table.concat(parts, "\n")
end

-- Redraws from the cache if anything changed. Safe to call any time.
function TownBoardService.Refresh()
	local model = board
	if model == nil then
		return
	end
	local view = TownBoardLogic.View(topFn(), failedFn())
	local sig = signature(view)
	if sig == lastSignature then
		return
	end
	lastSignature = sig
	TownBoardArt.Fill(model, view)
end

function TownBoardService.Board(): Model?
	return board
end

function TownBoardService.Init(options: InitOptions?)
	if board ~= nil then
		return
	end
	local opts: InitOptions = options or {}
	if opts.top then
		topFn = opts.top
	end
	if opts.failed then
		failedFn = opts.failed
	end
	local function go()
		local parent = opts.parent or workspace:WaitForChild("TimberlineMap", 60) or workspace
		if board ~= nil then
			return
		end
		board = TownBoardService.Place(parent, opts.cframe or WorldPlan.LeaderboardBoard, opts.ground)
		TownBoardService.Refresh()
	end
	local subscribe = opts.onRefresh or LeaderboardService.OnRefresh
	subscribe(function()
		-- Top() may look a name up, which yields: keep it off the read's thread.
		task.spawn(TownBoardService.Refresh)
	end)
	if opts.parent then
		go()
	else
		task.spawn(go)
	end
end

-- Specs only: forget the board so a test can Init again.
function TownBoardService.Reset()
	board = nil
	lastSignature = ""
end

return TownBoardService
