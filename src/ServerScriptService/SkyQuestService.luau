--!strict
-- SkyQuestService: Gus's Charter on the server (rules: Shared/SkyQuestLogic).
--   * The SkyQuest remote: ("accept" | "turnin"), RateLimiter "SkyQuest",
--     only within STATION_RANGE of the Skyroot gate lodge door, where Gus
--     stands (NPCData: beside GateLodge's Door).
--   * A "Gus's Charter" prompt on that door does the same: it accepts the
--     charter, or turns in what is ready, and toasts the step and its progress.
--   * Turn-ins use up the player's own planks laid by the door
--     (HandInWood). They pay nothing.
--   * The last step grants the Sky Pass once: profile.gondolaPass (and
--     skyPass, its old name), and the GondolaPass gear for the inventory.
--     No cash is charged for it. There is no ride.
--   * Player attributes SkyQuestStep and GondolaPass mirror the save for
--     the HUD and Lane E's Gus talk. State(player) is the read API.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The bar is in SkyGate. A pass holder, and anyone already on the summit
-- side of it, is in SkyPasser, which does not collide with the bar. The
-- road side without a pass stays in Default and meets the bar. Leave never
-- strands: crossing back to the road side without a pass collides again.
local GATE_GROUP = "SkyGate"
local PASS_GROUP = "SkyPasser"
local BAR_LOCAL_Z = -1 -- summit is the model's +Z, past the bar

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local SkyQuestLogic = require(ReplicatedStorage.Shared.SkyQuestLogic)
local HandInLogic = require(ReplicatedStorage.Shared.HandInLogic)
local GameAnalytics = require(script.Parent.GameAnalytics)
local AxeService = require(script.Parent.AxeService)
local HandInWood = require(script.Parent.HandInWood)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local SkyQuestService = {}

SkyQuestService.StationRange = 20

export type Ctx = {
	remotes: { [string]: Instance }?,
	notify: ((Player, string) -> ())?,
	station: BasePart?,
}

local notify: (Player, string) -> () = function(_p: Player, _m: string) end
local station: BasePart? = nil
local started = false

local function hasPass(profile: any): boolean
	return profile.gondolaPass == true or profile.skyPass == true
end

local function ownsObsidian(player: Player): boolean
	local counts = AxeService.OwnedCounts(player)
	return (counts["ObsidianAxe"] or 0) > 0
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function nearStation(player: Player): boolean
	local root = rootOf(player)
	return station ~= nil
		and root ~= nil
		and (root.Position - station.Position).Magnitude <= SkyQuestService.StationRange
end

local function publish(player: Player, profile: any)
	local state = SkyQuestLogic.Clean(profile.skyQuest)
	player:SetAttribute("SkyQuestStep", if hasPass(profile) then "done" else state.step)
	player:SetAttribute("GondolaPass", hasPass(profile))
end

local function facts(player: Player, profile: any, offered: { [string]: number }?): SkyQuestLogic.Facts
	return { ownsObsidian = ownsObsidian(player), hasPass = hasPass(profile), offered = offered }
end

-- The player's quest as the logic sees it (for Lane E's Gus talk and the HUD).
function SkyQuestService.State(player: Player): SkyQuestLogic.View?
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return nil
	end
	return SkyQuestLogic.View(SkyQuestLogic.Clean(profile.skyQuest), facts(player, profile, nil))
end

local function grantPass(profile: any)
	profile.gondolaPass = true
	profile.skyPass = true
	if type(profile.gear) == "table" and table.find(profile.gear, "GondolaPass") == nil then
		table.insert(profile.gear, "GondolaPass")
	end
end

local function logStep(player: Player, stepId: string)
	-- The level is the step's number (a whole number: Roblox refuses a string).
	for i, step in ipairs(SkyQuestLogic.Steps) do
		if step.id == stepId then
			GameAnalytics.Progression(player, "SkyCharter", i, stepId)
			return
		end
	end
end

-- One action from the remote or the prompt. Returns the toast it showed.
function SkyQuestService.Act(player: Player, action: unknown): string?
	if action ~= "accept" and action ~= "turnin" then
		return nil
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or not nearStation(player) then
		return nil
	end
	local state = SkyQuestLogic.Clean(profile.skyQuest)
	local list, byUid = {}, {}
	local offered: { [string]: number }? = nil
	if action == "turnin" and station then
		list, byUid = HandInWood.Near((station :: BasePart).Position)
		offered = HandInLogic.Planks(list, player.UserId)
	end
	local before = state.step
	local nextState, reward, used = SkyQuestLogic.Advance(state, action :: string, facts(player, profile, offered))
	for woodId, u3 in pairs(used) do
		HandInWood.Take(byUid, HandInLogic.PickPlanks(list, player.UserId, woodId, u3), "charter")
	end
	profile.skyQuest = { step = nextState.step, progress = nextState.progress, done = nextState.done }
	if reward == "GondolaPass" then
		grantPass(profile)
	end
	if nextState.step ~= before and before ~= "none" then
		logStep(player, before)
	end
	publish(player, profile)
	local view = SkyQuestLogic.View(nextState, facts(player, profile, nil))
	local text: string
	if reward == "GondolaPass" then
		text = "Gus signs your charter. The Sky Pass is yours. The Skyroot gate is open."
	elseif action == "turnin" and next(used) == nil and nextState.step == before then
		text = view.text .. " " .. view.progress .. "."
	else
		text = view.title .. ": " .. view.text .. " " .. view.progress .. "."
	end
	notify(player, text)
	return text
end

-- The prompt's one button: accept first, then turn in.
local function onPrompt(player: Player)
	if not RateLimiter.Allow(player, "SkyQuest") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local state = SkyQuestLogic.Clean(profile.skyQuest)
	SkyQuestService.Act(player, if state.step == "none" and not hasPass(profile) then "accept" else "turnin")
end

local function addPrompt(platform: BasePart)
	if platform:FindFirstChild("CharterPoint") then
		return
	end
	local point = Instance.new("Attachment")
	point.Name = "CharterPoint"
	point.Position = Vector3.new(0, 2.5, 0)
	point.Parent = platform
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Charter"
	prompt.ActionText = "Gus's Charter"
	prompt.ObjectText = "Gus"
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0.3
	InputKit.PromptDefaults(prompt, "Open")
	prompt.RequiresLineOfSight = false
	prompt.Parent = point
	prompt.Triggered:Connect(onPrompt)
end

local function physicsService(): any
	local ok, svc = pcall(function()
		return game:GetService("PhysicsService")
	end)
	return if ok then svc else nil
end

local function armGate()
	local physics = physicsService()
	if physics == nil then
		return
	end
	pcall(function()
		physics:RegisterCollisionGroup(GATE_GROUP)
		physics:RegisterCollisionGroup(PASS_GROUP)
		physics:CollisionGroupSetCollidable(GATE_GROUP, PASS_GROUP, false)
		physics:CollisionGroupSetCollidable(GATE_GROUP, "Default", true)
	end)
	local lodge = if station then station.Parent else nil
	local bar = if lodge then lodge:FindFirstChild("GateBar") else nil
	if bar and bar:IsA("BasePart") then
		pcall(function()
			(bar :: BasePart).CollisionGroup = GATE_GROUP
		end)
	end
	local ok, run = pcall(function()
		return game:GetService("RunService")
	end)
	if not ok or run == nil or run.Heartbeat == nil then
		return
	end
	pcall(function()
		run.Heartbeat:Connect(function()
			local door = station
			local home = if door then door.Parent else nil
			if not home or not home:IsA("Model") then
				return
			end
			local pivot = home:GetPivot()
			for _, player in ipairs(Players:GetPlayers()) do
				local root = rootOf(player)
				local char = player.Character
				if not root or not char then
					continue
				end
				if (root.Position - pivot.Position).Magnitude > 160 then
					continue
				end
				local profile = ProfileService.GetProfile(player)
				local pass = profile ~= nil and hasPass(profile)
				local onSummit = pivot:PointToObjectSpace(root.Position).Z > BAR_LOCAL_Z
				local direction: "enter" | "leave" = if onSummit then "leave" else "enter"
				local group = if SkyQuestLogic.MayPass(direction, pass) then PASS_GROUP else "Default"
				for _, d in ipairs(char:GetDescendants()) do
					if d:IsA("BasePart") and d.CollisionGroup ~= group then
						d.CollisionGroup = group
					end
				end
			end
		end)
	end)
end

function SkyQuestService.V1Init(ctx: Ctx?)
	if started then
		return
	end
	started = true
	if ctx and ctx.notify then
		notify = ctx.notify
	end
	station = if ctx then ctx.station else nil
	if station then
		addPrompt(station :: BasePart)
		armGate()
	end
	local remote = if ctx and ctx.remotes then ctx.remotes.SkyQuest else nil
	if remote and remote:IsA("RemoteEvent") then
		remote.OnServerEvent:Connect(function(player: Player, action: unknown)
			if RateLimiter.Allow(player, "SkyQuest") then
				SkyQuestService.Act(player, action)
			end
		end)
	end
	local function joined(player: Player)
		task.spawn(function()
			for _ = 1, 60 do
				local profile = ProfileService.GetProfile(player)
				if profile then
					publish(player, profile)
					return
				end
				task.wait(1)
			end
		end)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in ipairs(Players:GetPlayers()) do
		joined(player)
	end
end

-- For the specs.
function SkyQuestService._setStation(part: BasePart?)
	station = part
end

function SkyQuestService._reset()
	started = false
	station = nil
	notify = function(_p: Player, _m: string) end
end

return SkyQuestService
