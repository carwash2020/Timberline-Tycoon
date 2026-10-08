--!strict
-- NPCTalkService: who each NPC is talking to (rules in Shared/TalkLock).
--
-- Pressing Talk on an NPC starts a conversation: the dialogue box opens on
-- that player's screen. The server learns of it from the Talk prompt's
-- Triggered (it checks the player is within reach), and of its end from the
-- client's "end" intent on the Dialogue remote (the box was dismissed), or
-- by itself: the player walked out of range, went down or left, the NPC was
-- removed or lay down, or the box has been up far too long. While anyone is
-- talking, the NPC model carries the attribute TalkLock.Attribute (the
-- UserId to face: the most recent talker). Clients turn the NPC toward that
-- player and hold a walker still, which is only ever visual. The attribute
-- going away is the release, so no state outlives the conversation.
--
-- Nothing here moves an NPC or grants anything.

local CollectionService = game:GetService("CollectionService")

local RunService = game:GetService("RunService")

local TalkLock = require(game:GetService("ReplicatedStorage").Shared.TalkLock)
local RateLimiter = require(script.Parent.RateLimiter)

local NPCTalkService = {}

local SWEEP_SECONDS = 0.25

local talks: { [Model]: { TalkLock.Talker } } = {}
local hooked: { [Model]: boolean } = {}
local started = false

local function clock(): number
	return os.clock()
end

local function playerOf(userId: number): Player?
	local ok, found = pcall(function()
		return game:GetService("Players"):GetPlayerByUserId(userId)
	end)
	if ok and found then
		return found
	end
	return nil
end

-- What the server sees of a player: how far they are from `model`, and
-- whether they have a living character.
local function factOf(userId: number, model: Model): TalkLock.Fact?
	local player = playerOf(userId)
	if player == nil then
		return nil
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local root = model.PrimaryPart
	if hrp == nil or not hrp:IsA("BasePart") then
		return { distance = nil, down = true }
	end
	local down = humanoid ~= nil and humanoid.Health <= 0
	local distance: number? = nil
	if root ~= nil then
		distance = (hrp.Position - root.Position).Magnitude
	end
	return { distance = distance, down = down }
end

-- Writes the attribute from the list: the target's UserId, or nothing.
local function publish(model: Model)
	local list = talks[model] or {}
	local distances: { [number]: number } = {}
	for _, talker in ipairs(list) do
		local fact = factOf(talker.userId, model)
		if fact ~= nil and fact.distance ~= nil then
			distances[talker.userId] = fact.distance
		end
	end
	local target = TalkLock.Target(list, distances)
	if model:GetAttribute(TalkLock.Attribute) ~= target then
		model:SetAttribute(TalkLock.Attribute, target)
	end
	if #list == 0 then
		talks[model] = nil
	end
end

local function forget(model: Model)
	talks[model] = nil
	hooked[model] = nil
	pcall(function()
		if model:GetAttribute(TalkLock.Attribute) ~= nil then
			model:SetAttribute(TalkLock.Attribute, nil)
		end
	end)
end

-- Someone pressed Talk on `model`. False when it does not start (too far,
-- a keeper asleep, no character).
function NPCTalkService.Begin(player: Player, model: Model, now: number?): boolean
	if model.Parent == nil or model:GetAttribute("Asleep") == true then
		return false
	end
	local fact = factOf(player.UserId, model)
	if fact == nil or fact.down == true then
		return false
	end
	local distance = fact.distance
	if distance == nil or distance > TalkLock.BeginReach() then
		return false
	end
	talks[model] = TalkLock.Begin(talks[model] or {}, player.UserId, now or clock())
	publish(model)
	return true
end

-- The server just put a line from `npcId` on this player's screen (a
-- keeper's reply to Yes or No, a payment's thanks): that box is a talk too,
-- so the nearest tracked NPC of that id takes it up again. False when none is
-- in reach.
function NPCTalkService.BeginById(player: Player, npcId: string, now: number?): boolean
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local best: Model? = nil
	local bestDistance = math.huge
	for model in pairs(hooked) do
		local root = model.PrimaryPart
		if model:GetAttribute("NPCId") == npcId and root ~= nil and hrp ~= nil and hrp:IsA("BasePart") then
			local d = (hrp.Position - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = model, d
			end
		end
	end
	if best == nil then
		return false
	end
	return NPCTalkService.Begin(player, best, now)
end

-- The player's box for the NPC called `npcId` is over (dismissed, or taken
-- over by another). Only that NPC lets them go.
function NPCTalkService.End(player: Player, npcId: string)
	for model, list in pairs(talks) do
		if model:GetAttribute("NPCId") == npcId then
			local kept = TalkLock.End(list, player.UserId)
			if #kept ~= #list then
				talks[model] = kept
				publish(model)
			end
		end
	end
end

-- Every talk, checked: lets go of whoever left, died, walked off or timed
-- out, and of everyone when the NPC is gone or asleep.
function NPCTalkService.Sweep(now: number?)
	local at = now or clock()
	local models: { Model } = {}
	for model in pairs(talks) do
		table.insert(models, model)
	end
	for _, model in ipairs(models) do
		local list = talks[model]
		if list == nil then
			continue
		end
		local gone = model.Parent == nil
		if gone then
			forget(model)
			continue
		end
		local facts: { [number]: TalkLock.Fact } = {}
		for _, talker in ipairs(list) do
			local fact = factOf(talker.userId, model)
			if fact ~= nil then
				facts[talker.userId] = fact
			end
		end
		local asleep = model:GetAttribute("Asleep") == true
		local kept = TalkLock.Prune(list, facts, at, false, asleep)
		if #kept ~= #list then
			talks[model] = kept
		end
		publish(model)
	end
end

-- A player left: they are nobody's conversation.
function NPCTalkService.Left(player: Player)
	for model, list in pairs(talks) do
		local kept = TalkLock.End(list, player.UserId)
		if #kept ~= #list then
			talks[model] = kept
			publish(model)
		end
	end
end

-- Who `model` is talking to now (a UserId), for the specs and the admin.
function NPCTalkService.TalkingWith(model: Model): number?
	local list = talks[model]
	if list == nil then
		return nil
	end
	return TalkLock.Target(list, nil)
end

-- Starts watching an NPC model: its Talk prompt, and its removal.
function NPCTalkService.Track(model: Model)
	if hooked[model] then
		return
	end
	local talk = model:FindFirstChild("Talk")
	if talk == nil or not talk:IsA("ProximityPrompt") then
		return
	end
	hooked[model] = true
	talk.Triggered:Connect(function(who: Player)
		if RateLimiter.Allow(who, "NPCTalk") then
			local ok, began = pcall(NPCTalkService.Begin, who, model)
			if not ok then
				warn("[Talk] NPCTalkService.Begin failed: " .. tostring(began))
			end
		end
	end)
	pcall(function()
		model.Destroying:Connect(function()
			forget(model)
		end)
	end)
end

local function consider(inst: Instance)
	if inst:IsA("Model") then
		NPCTalkService.Track(inst)
	end
end

function NPCTalkService.Init()
	if started then
		return
	end
	started = true
	pcall(function()
		for _, inst in ipairs(CollectionService:GetTagged("NPC")) do
			consider(inst)
		end
		CollectionService:GetInstanceAddedSignal("NPC"):Connect(consider)
		CollectionService:GetInstanceRemovedSignal("NPC"):Connect(function(inst: Instance)
			if inst:IsA("Model") then
				forget(inst)
			end
		end)
		game:GetService("Players").PlayerRemoving:Connect(NPCTalkService.Left)
	end)
	if type(RunService.IsRunning) == "function" and RunService:IsRunning() then
		task.spawn(function()
			while RunService:IsRunning() do
				task.wait(SWEEP_SECONDS)
				pcall(NPCTalkService.Sweep)
			end
		end)
	end
end

return NPCTalkService
