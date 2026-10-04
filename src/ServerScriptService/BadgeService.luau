--!strict
-- BadgeService: awards Roblox badges once, and tells the client which
-- ones the player has earned.
--
-- Hooks are MilestoneService.Mark (a "mark" event) and
-- MilestoneService.Event(player, kind, data). This module listens there.
-- It also polls, and reports what it finds through that same Event:
--   * where the player stands (RegionLogic, via BadgeData.AreasAt)
--   * woods already in the field guide (profile.compendium)
--   * a plank they own (a WoodSection model with Kind "plank")
-- BadgeSync is server -> client. Nothing connects OnServerEvent, and it
-- has no rate limit. An id of 0 records the earn and never calls AwardBadge.
-- badgesAwarded is the earn (the panel). badgesSent is set only when
-- AwardBadge returns true. A live id is sent on the next join if the earn
-- was recorded while the id was 0.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BadgeData = require(ReplicatedStorage.Shared.BadgeData)
local MilestoneService = require(script.Parent.MilestoneService)
local ProfileService = require(script.Parent.ProfileService)

type Profile = ProfileService.Profile

type AwardFn = (userId: number, badgeId: number) -> boolean

type SyncRemote = {
	FireClient: (self: any, player: Player, payload: string) -> (),
}

export type InitOptions = {
	manual: boolean?, -- no Heartbeat; tests call Poll
	sync: boolean?, -- AwardBadge runs before Award returns (tests)
	award: AwardFn?,
	pause: ((number) -> ())?,
	remote: SyncRemote?,
}

local BadgeService = {}

local MAX_TRIES = 3
local RETRY_SEC = 2
local POLL_SEC = 1

local awardImpl: AwardFn? = nil
local pause: (number) -> () = function(seconds: number)
	task.wait(seconds)
end
local synchronous = false
local remoteOverride: SyncRemote? = nil
local started = false

local inflight: { [Player]: { [string]: boolean } } = {}
local failed: { [Player]: { [string]: boolean } } = {}
local greeted: { [Player]: boolean } = {}

local function defaultAward(userId: number, badgeId: number): boolean
	local api = game:GetService("BadgeService")
	return api:AwardBadge(userId, badgeId)
end

-- true: AwardBadge returned true. false: it returned false (do not retry
-- this session). nil: every try errored.
local function callAward(userId: number, badgeId: number): boolean?
	local fn = awardImpl or defaultAward
	for attempt = 1, MAX_TRIES do
		local ok, result = pcall(fn, userId, badgeId)
		if ok then
			return result == true
		end
		if attempt < MAX_TRIES then
			pause(RETRY_SEC)
		end
	end
	return nil
end

local function findRemote(): SyncRemote?
	local ok, remote = pcall(function(): SyncRemote?
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if folder == nil then
			return nil
		end
		local child = folder:FindFirstChild("BadgeSync")
		if child ~= nil and child:IsA("RemoteEvent") then
			return child :: SyncRemote
		end
		return nil
	end)
	if ok then
		return remote
	end
	return nil
end

local function publish(player: Player, profile: Profile)
	local payload = BadgeData.Encode(profile.badgesAwarded)
	player:SetAttribute("Badges", payload)
	local remote: SyncRemote? = remoteOverride or findRemote()
	if remote ~= nil then
		remote:FireClient(player, payload)
	end
end

local function bag(map: { [Player]: { [string]: boolean } }, player: Player): { [string]: boolean }
	local inner = map[player]
	if inner == nil then
		inner = {}
		map[player] = inner
	end
	return inner
end

local function ensureMaps(profile: Profile)
	if type(profile.badgesAwarded) ~= "table" then
		profile.badgesAwarded = {}
	end
	if type(profile.badgesSent) ~= "table" then
		profile.badgesSent = {}
	end
	if type(profile.areasVisited) ~= "table" then
		profile.areasVisited = {}
	end
end

local function remember(player: Player, profile: Profile, key: string)
	profile.badgesAwarded[key] = true
	local def = BadgeData.Get(key)
	local visit = if def then def.visit else nil
	if visit then
		profile.areasVisited[visit] = true
	end
	publish(player, profile)
end

-- Records `key` on the profile and, when its Creator Hub id is pasted,
-- asks Roblox to award it. Id 0 is recorded for the panel and never sent.
-- A live id that was already sent does not call again. An earn at id 0 is
-- sent later, once the id is live. Returns true when the earn was recorded
-- before this returns. A live id on a real server is sent in the background
-- and returns false here; the profile updates when Roblox answers.
function BadgeService.Award(player: Player, key: string): boolean
	if type(key) ~= "string" then
		return false
	end
	local def = BadgeData.Get(key)
	local profile = ProfileService.GetProfile(player)
	if not def or not profile then
		return false
	end
	ensureMaps(profile)
	local id = BadgeData.RobloxId(key)
	if not BadgeData.IsLive(id) then
		if profile.badgesAwarded[key] == true then
			return false
		end
		remember(player, profile, key)
		return true
	end
	if profile.badgesSent[key] == true then
		return false
	end
	if type(player.UserId) ~= "number" then
		return false
	end
	local pending = bag(inflight, player)
	local gaveUp = bag(failed, player)
	if pending[key] or gaveUp[key] then
		return false
	end
	pending[key] = true
	local userId = player.UserId
	local function finish()
		-- Stay in-flight for the whole Roblox call. AwardBadge yields, and
		-- a poll during that wait must not start a second one.
		local current = ProfileService.GetProfile(player)
		if current then
			ensureMaps(current)
		end
		if current and current.badgesSent[key] ~= true then
			local sent = callAward(userId, id)
			if sent == true then
				remember(player, current, key)
				current.badgesSent[key] = true
			elseif sent == false then
				-- The call answered. The earn sticks; Roblox did not take it.
				-- No retry until the next join.
				remember(player, current, key)
				gaveUp[key] = true
			else
				gaveUp[key] = true
				warn(string.format("[BadgeService] could not award %s (%d) to %s", key, id, player.Name))
			end
		end
		pending[key] = nil
	end
	if synchronous then
		finish()
		return profile.badgesAwarded[key] == true
	end
	task.spawn(finish)
	return false
end

local function onEvent(player: Player, kind: string, data: MilestoneService.EventData?)
	for _, key in ipairs(BadgeData.KeysFor(kind, data)) do
		BadgeService.Award(player, key)
	end
end

local function positionOf(player: Player): (number?, number?, number?)
	local character = player.Character
	if character == nil then
		return nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	local pos = root.Position
	return pos.X, pos.Y, pos.Z
end

-- A plank this player owns, sitting in the world. Missing tags (tests, a
-- server with no loose wood) is not an error.
local function ownsPlank(player: Player): boolean
	local userId = player.UserId
	local getTagged = (CollectionService :: any).GetTagged
	if type(getTagged) ~= "function" then
		return false
	end
	local ok, tagged = pcall(getTagged, CollectionService, "WoodSection")
	if not ok or type(tagged) ~= "table" then
		return false
	end
	for _, inst in ipairs(tagged :: { any }) do
		if typeof(inst) == "Instance" then
			local model = inst.Parent
			if model ~= nil and model:GetAttribute("Kind") == "plank" and model:GetAttribute("Owner") == userId then
				return true
			end
		end
	end
	return false
end

-- One pass: publish once, then report new areas, woods, and a first plank
-- through MilestoneService.Event. Standing still does not repeat a badge.
function BadgeService.Poll(player: Player)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	ensureMaps(profile)
	if not greeted[player] then
		greeted[player] = true
		publish(player, profile)
		-- Earned while the id was 0 (or a false AwardBadge): send once now
		-- that the id is live. The in-flight guard stops a second call.
		local awarded = profile.badgesAwarded
		local sent = profile.badgesSent
		for badgeKey, on in pairs(awarded) do
			if on == true and sent[badgeKey] ~= true and BadgeData.IsLive(BadgeData.RobloxId(badgeKey)) then
				BadgeService.Award(player, badgeKey)
			end
		end
	end
	local earned = profile.badgesAwarded
	local x, y, z = positionOf(player)
	if x ~= nil and y ~= nil and z ~= nil then
		for _, key in ipairs(BadgeData.AreasAt(x, y, z)) do
			if earned[key] ~= true then
				MilestoneService.Event(player, "area", { id = key })
			end
		end
	end
	local compendium = profile.compendium
	if type(compendium) == "table" then
		for woodId, on in pairs(compendium) do
			if on == true and type(woodId) == "string" then
				for _, key in ipairs(BadgeData.ForWood(woodId)) do
					if earned[key] ~= true then
						MilestoneService.Event(player, "wood", { woodId = woodId })
						break
					end
				end
			end
		end
	end
	if earned.FirstPlank ~= true and ownsPlank(player) then
		MilestoneService.Event(player, "plank", nil)
	end
end

function BadgeService.Forget(player: Player)
	inflight[player] = nil
	failed[player] = nil
	greeted[player] = nil
end

function BadgeService.Init(options: InitOptions?)
	if started then
		return
	end
	started = true
	if options then
		if options.award then
			awardImpl = options.award
		end
		if options.pause then
			pause = options.pause
		end
		if options.sync == true then
			synchronous = true
		end
		if options.remote ~= nil then
			remoteOverride = options.remote
		end
	end
	MilestoneService.Listen(onEvent)
	local manual = options ~= nil and options.manual == true
	if manual then
		return
	end
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(player: Player)
		BadgeService.Forget(player)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < POLL_SEC then
			return
		end
		acc = 0
		for _, player in Players:GetPlayers() do
			BadgeService.Poll(player)
		end
	end)
end

return BadgeService
