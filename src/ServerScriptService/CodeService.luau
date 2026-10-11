--!strict
-- CodeService: redeem codes (rules in Shared/CodeLogic, the codes in CodeData).
--   * RedeemCode(code) from the Settings Codes tab. Rate limited (one a
--     second), and a run of wrong codes locks the box for a short while.
--   * The server decides everything: it normalises the text, finds the code,
--     checks it is enabled and unexpired on the SERVER's clock, and that this
--     player has not used it. The client only types and reads the answer.
--   * One use per player ever: "Code:<id>" in profile.onboarding (account-
--     wide, so it holds across save slots). It is marked before the reward
--     is paid and unmarked if the reward could not be given at all.
--   * Rewards are cash (EconomyService.AddCash: clamped to the wallet cap) or
--     a free furniture piece (PlotService.GrantPiece). Never Robux, never a
--     paid item (CodeLogic.ValidReward).
--   * The answer goes back as CodeResult(ok, message), and is a toast too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodeLogic = require(ReplicatedStorage.Shared.CodeLogic)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local Util = require(ReplicatedStorage.Shared.Util)
local CodeData = require(script.Parent.CodeData)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local CodeService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local resultRemote: RemoteEvent? = nil
local clock: () -> number = os.time -- UTC unix seconds; specs replace it
local list: { CodeLogic.Entry } = CodeData.List
local misses: { [Player]: { number } } = {}

-- Specs: swap the clock and the code list.
function CodeService.SetClock(fn: () -> number)
	clock = fn
end

function CodeService.SetList(codes: { CodeLogic.Entry })
	list = codes
end

local function reply(player: Player, ok: boolean, message: string)
	local remote = resultRemote
	if remote then
		remote:FireClient(player, ok, message)
	end
	notify(player, message)
end

local function book(profile: ProfileService.Profile): { [string]: boolean }
	if type(profile.onboarding) ~= "table" then
		profile.onboarding = {}
	end
	return profile.onboarding
end

-- Tries `raw` for `player`. Returns (ok, message): the message is what the
-- player is told. Public so specs can call it without a remote.
function CodeService.Redeem(player: Player, raw: unknown): (boolean, string)
	local now = clock()
	local recent = misses[player] or {}
	if CodeLogic.Locked(recent, now) > 0 then
		return false, CodeLogic.Messages.locked
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return false, CodeLogic.Messages.invalid
	end
	local code = CodeLogic.Normalize(raw)
	if code == nil then
		return false, CodeLogic.Messages.empty
	end
	local flags = book(profile)
	local entry = CodeLogic.Find(list, code)
	local verdict = CodeLogic.Check(entry, flags, now)
	if verdict ~= "ok" or entry == nil then
		if verdict == "invalid" then
			misses[player] = CodeLogic.NoteMiss(recent, now)
		end
		return false, CodeLogic.Messages[verdict]
	end

	local key = CodeLogic.FlagKey(entry)
	local reward = entry.reward
	if reward.kind == "cash" then
		-- AddCash clamps to the wallet cap. A full wallet takes none of it, so the
		-- code is not used up.
		flags[key] = true
		local credited, overflow = EconomyService.AddCash(player, reward.amount, "code: " .. entry.id, "code")
		if credited <= 0 then
			flags[key] = nil
			return false, CodeLogic.Messages.wallet
		end
		local text = "Code accepted: " .. Util.formatCash(credited) .. " added."
		if overflow > 0 then
			text ..= " (Your wallet was nearly full, so " .. Util.formatCash(overflow) .. " didn't fit.)"
		end
		return true, text
	end

	local okGrant, why = PlotService.CanGrant(player, reward.id)
	if not okGrant then
		return false, if why == "full" then CodeLogic.Messages.stock else CodeLogic.Messages.invalid
	end
	flags[key] = true
	local granted = PlotService.GrantPiece(player, reward.id, "code")
	if not granted then
		flags[key] = nil
		return false, CodeLogic.Messages.stock
	end
	local bp = PlotData.Blueprint(reward.id)
	local name = if bp then bp.displayName else reward.id
	return true, "Code accepted: you got a " .. CodeLogic.RewardText(reward, name) .. "."
end

local function onRedeem(player: Player, raw: unknown)
	if not RateLimiter.Allow(player, "RedeemCode") then
		return
	end
	local ok, message = CodeService.Redeem(player, raw)
	reply(player, ok, message)
end

-- `redeemRemote` is RedeemCode, `resultEvent` CodeResult, `notifyFn` shows a toast.
function CodeService.Init(redeemRemote: RemoteEvent, resultEvent: RemoteEvent, notifyFn: (Player, string) -> ())
	notify = notifyFn
	resultRemote = resultEvent
	redeemRemote.OnServerEvent:Connect(onRedeem)
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		misses[player] = nil
	end)
end

return CodeService
