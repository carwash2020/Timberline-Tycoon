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
end

local function pass()
	local home = treesFolder
	if not home then
		return
	end
	local list = people()
	-- Nobody here: leave every tree where MapBuilder put it.
	if #list == 0 then
		return
	end
	local away = asleepFolder()
	for model in pairs(known) do
		if model.Parent == nil then
			known[model] = nil
			continue
		end
		if model:GetAttribute("TutorialGrove") == true then
			if model.Parent ~= home then
				model.Parent = home
			end
			continue
		end
		local region = model:GetAttribute("Region")
		local regionId = if type(region) == "string" then region else "wild"
		local pivot = model:GetPivot().Position
		local keep = RegionLogic.KeepTree(regionId, pivot.X, pivot.Z, pivot.Y, list)
		local want = if keep then home else away
		if model.Parent ~= want then
			model.Parent = want
		end
	end
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
		treesFolder = trees
		for _, child in ipairs(trees:GetChildren()) do
			watch(child)
		end
		trees.ChildAdded:Connect(watch)
		local elapsed = RegionWake.Tick
		RunService.Heartbeat:Connect(function(dt: number)
			elapsed += dt
			if elapsed < RegionWake.Tick then
				return
			end
			elapsed = 0
			local ok, err = pcall(function(): any
				pass()
				return true
			end)
			if not ok then
				warn("[RegionWake] " .. tostring(err))
			end
		end)
	end)
end

return RegionWake
