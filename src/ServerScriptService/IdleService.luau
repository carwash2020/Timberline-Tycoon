--!strict
-- IdleService: warns, then removes, a player who has done nothing for a
-- long time, so an abandoned tab does not hold one of the server's seats
-- (GameConfig.MaxPlayers) or one of its plots. The rules are in
-- Shared/IdleLogic (18 minutes warns, 20 removes, never in the first five
-- minutes in the world); this module feeds them what the server can see:
--
--   * any remote the player sends (RateLimiter.OnRequest sees every one,
--     even a throttled one),
--   * the client's own Activity ping (IdlePing: a key, tap, click or stick
--     move, sent at most once in 30 s),
--   * chat (Player.Chatted),
--   * the character moving (sampled every CHECK_EVERY seconds; driving a
--     truck moves it too).
--
-- Removing a player is Player:Kick, so the normal leave path runs: the save
-- is committed and written, then the plot comes down (GameServer's
-- onPlayerRemoving). The clock starts when the save is loaded and the
-- player can play (Start), not at join.
--
-- Studio: off unless the workspace has an "IdleScale" number attribute
-- (0.02 makes the 20 minutes pass in 24 seconds), so a playtest left alone
-- is never ended by it. On a live server the attribute is ignored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IdleLogic = require(ReplicatedStorage.Shared.IdleLogic)
local RateLimiter = require(script.Parent.RateLimiter)

local IdleService = {}

local CHECK_EVERY = 5 -- seconds between looks at everyone

local states: { [Player]: IdleLogic.State } = {}
local lastAt: { [Player]: IdleLogic.Point } = {}
local notifyFn: ((Player, string) -> ())? = nil
local clockFn: () -> number = os.clock
local started = false

-- The clock the rules read. In Studio, IdleScale shrinks the minutes.
local function now(): number
	return clockFn()
end

local function scaled(): number
	if RunService:IsStudio() then
		local scale = workspace:GetAttribute("IdleScale")
		if type(scale) == "number" and scale > 0 then
			return now() / scale
		end
	end
	return now()
end

local function enabled(): boolean
	if not RunService:IsStudio() then
		return true
	end
	return type(workspace:GetAttribute("IdleScale")) == "number"
end

local function positionOf(player: Player): IdleLogic.Point?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local at = root.Position
	return { x = at.X, y = at.Y, z = at.Z }
end

-- The player has done something.
function IdleService.Touch(player: Player)
	local state = states[player]
	if state ~= nil then
		IdleLogic.Touch(state, scaled())
	end
end

-- Their save is loaded and they can play: the idle clock starts now.
function IdleService.Start(player: Player)
	if states[player] ~= nil then
		return
	end
	states[player] = IdleLogic.New(scaled())
	lastAt[player] = positionOf(player) :: any
	player.Chatted:Connect(function()
		IdleService.Touch(player)
	end)
end

function IdleService.Stop(player: Player)
	states[player] = nil
	lastAt[player] = nil
end

function IdleService.IsTracked(player: Player): boolean
	return states[player] ~= nil
end

-- One look at every tracked player: movement counts as activity, then the
-- rules say nothing, warn or remove. Called every CHECK_EVERY seconds.
function IdleService.Tick()
	if not enabled() then
		return
	end
	local t = scaled()
	for player, state in pairs(states) do
		if player.Parent ~= Players then
			states[player] = nil
			lastAt[player] = nil
			continue
		end
		local here = positionOf(player)
		if IdleLogic.Moved(lastAt[player], here) then
			IdleLogic.Touch(state, t)
		end
		if here ~= nil then
			lastAt[player] = here
		end
		local action = IdleLogic.Step(state, t)
		if action == "warn" then
			if notifyFn ~= nil then
				notifyFn(player, IdleLogic.WarnText(IdleLogic.SecondsLeft(state, t)))
			end
		elseif action == "kick" then
			states[player] = nil
			lastAt[player] = nil
			print(string.format("[IdleService] removing %s: idle for %d s", player.Name, IdleLogic.IdleFor(state, t)))
			player:Kick(IdleLogic.KickMessage)
		end
	end
end

-- `deps.notify(player, text)` shows a toast. `deps.clock` is for specs.
function IdleService.Init(deps: { notify: (Player, string) -> (), clock: (() -> number)?, loop: boolean? })
	notifyFn = deps.notify
	if deps.clock ~= nil then
		clockFn = deps.clock
	end
	RateLimiter.OnRequest(function(player: Player, _remote: string)
		IdleService.Touch(player)
	end)
	if started or deps.loop == false then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = (pcall :: any)(IdleService.Tick)
			if not ok then
				warn("[IdleService] tick failed: " .. tostring(err))
			end
		end
	end)
end

return IdleService
