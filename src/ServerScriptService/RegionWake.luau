--!strict
-- RegionWake: choppable trees in a region nobody is near leave the
-- workspace, and come back before anyone arrives. SectionTrees still owns
-- every model (chops, regrowth, lightning); parking them in ServerStorage
-- means a phone doesn't replicate a forest it can't reach. Tutorial oaks
-- stay. An empty server keeps the whole forest (nothing to stream).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local RegionLogic = require(game:GetService("ReplicatedStorage").Shared.RegionLogic)

local RegionWake = {}

RegionWake.Tick = 0.75 -- seconds between passes

local treesFolder: Folder? = nil
local parked: Folder? = nil
local known: { [Model]: boolean } = {}

local function asleepFolder(): Folder
	local folder = parked
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "AsleepRegions"
	made.Parent = ServerStorage
	parked = made
	return made
end

local function people(): { RegionLogic.Person }
	local out: { RegionLogic.Person } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if root then
			local p = root.Position
			table.insert(out, { x = p.X, z = p.Z, y = p.Y })
		else
			-- Still loading in: treat them as standing at the spawn, so the
			-- far regions don't replicate for that first second.
			table.insert(out, { x = 0, z = 40, y = 6 })
		end
	end
	return out
end

RegionWake.Batch = 150 -- trees a frame a sweep looks at (about 1,400 in the forest)

local lastList: { RegionLogic.Person }? = nil -- the people the last sweep started with
local lastHeres: { RegionLogic.Here | boolean }? = nil
local doneSignature: string? = nil -- the people a finished sweep saw: the same again, nothing to redo
local dirty = true -- a tree arrived before any sweep: sweep
local queue: { Model } = {}
local cursor = 1 -- the next tree of `queue` a sweep looks at; past its end: no sweep running
local sweepSignature = ""

-- Whether `model` should be in the world or parked for these people, and put
-- it there. A tutorial oak always stays.
local function settle(model: Model, home: Folder, list: { RegionLogic.Person }, heres: { RegionLogic.Here | boolean })
	if model:GetAttribute("TutorialGrove") == true then
		if model.Parent ~= home then
			model.Parent = home
		end
		return
	end
	local region = model:GetAttribute("Region")
	local regionId = if type(region) == "string" then region else "wild"
	local pivot = model:GetPivot().Position
	local keep = RegionLogic.KeepTreeWith(regionId, pivot.X, pivot.Z, pivot.Y, list, heres)
	local want = if keep then home else asleepFolder()
	if model.Parent ~= want then
		model.Parent = want
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	if known[model] then
		return
	end
	known[model] = true
	model.Destroying:Connect(function()
		known[model] = nil
	end)
	-- A tree just planted is put where the last sweep's people want it in the
	-- same frame, before it replicates, not parked a sweep later (a client in
	-- a far corner was sent the whole forest and told to drop it again). The
	-- placer sets its attributes right after parenting, so look a beat later.
	local list, heres = lastList, lastHeres
	if not list or not heres then
		dirty = true
		return
	end
	task.defer(function()
		local home = treesFolder
		if home and model.Parent == home and lastList == list then
			settle(model, home, list, heres)
		end
	end)
end

local function signatureOf(list: { RegionLogic.Person }): string
	local parts: { string } = {}
	for _, p in ipairs(list) do
		table.insert(parts, string.format("%.9g,%.9g,%.9g", p.x, p.y, p.z))
	end
	return table.concat(parts, ";")
end

-- A slice of the sweep: Batch trees, then give the frame back.
local function work(list: { RegionLogic.Person }, heres: { RegionLogic.Here | boolean })
	local home = treesFolder
	if not home then
		cursor = #queue + 1
		return
	end
	local last = math.min(cursor + RegionWake.Batch - 1, #queue)
	for i = cursor, last do
		local model = queue[i]
		if model.Parent == nil then
			known[model] = nil
		else
			settle(model, home, list, heres)
		end
	end
	cursor = last + 1
	if cursor > #queue then
		doneSignature = sweepSignature
		queue = {}
	end
end

-- One heartbeat. Every Tick seconds a sweep over the trees starts if the
-- people are not where the last finished sweep saw them (standing still
-- changes no answer: nothing to do); a sweep runs RegionWake.Batch trees a
-- frame. Exposed for the specs.
local elapsed = RegionWake.Tick
function RegionWake.Step(dt: number)
	if cursor <= #queue and lastList and lastHeres then
		work(lastList, lastHeres)
		return
	end
	elapsed += dt
	if elapsed < RegionWake.Tick then
		return
	end
	elapsed = 0
	local list = people()
	-- Nobody here: leave every tree where MapBuilder put it.
	if #list == 0 then
		return
	end
	local signature = signatureOf(list)
	if signature == doneSignature and not dirty then
		return
	end
	dirty = false
	sweepSignature = signature
	local heres = RegionLogic.Heres(list)
	lastList, lastHeres = list, heres
	queue = {}
	for model in pairs(known) do
		table.insert(queue, model)
	end
	cursor = 1
	if #queue == 0 then
		doneSignature = signature
		return
	end
	work(list, heres)
end

-- Starts watching `trees` (Init does, once the map is in). Exposed for the specs.
function RegionWake.Attach(trees: Folder)
	treesFolder = trees
	for _, child in ipairs(trees:GetChildren()) do
		watch(child)
	end
	trees.ChildAdded:Connect(watch)
end

function RegionWake.Init()
	task.spawn(function()
		local map = workspace:WaitForChild("TimberlineMap", 180)
		if not map then
			warn("[RegionWake] no map; trees stay where they were built")
			return
		end
		local trees = map:WaitForChild("Trees", 180)
		if not trees or not trees:IsA("Folder") then
			warn("[RegionWake] no Trees folder")
			return
		end
		RegionWake.Attach(trees)
		RunService.Heartbeat:Connect(function(dt: number)
			local ok, err = pcall(function(): any
				RegionWake.Step(dt)
				return true
			end)
			if not ok then
				warn("[RegionWake] " .. tostring(err))
			end
		end)
	end)
end

return RegionWake
