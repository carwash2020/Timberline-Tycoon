--!strict
-- IdlePing: tells the server the player is at the controls, so the idle
-- kick (ServerScriptService/IdleService, Shared/IdleLogic) never removes
-- someone who is only reading, looking round or holding a stick. Any key,
-- click, tap, controller button, or mouse / stick / touch movement counts,
-- including ones a menu swallowed. It sends at most one tiny intent every
-- PING_EVERY seconds and carries no data; the server never trusts it for
-- anything but resetting that timer. It binds no action, so no other
-- control loses a button (the controller rules in CLAUDE.md hold).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)

local IdlePing = {}

local PING_EVERY = 30 -- seconds; the server's warning comes after 18 minutes

function IdlePing.Start()
	local remote = Net.Remote("Activity")
	local lastSent = -PING_EVERY

	local function ping()
		local now = os.clock()
		if now - lastSent < PING_EVERY then
			return
		end
		lastSent = now
		remote:FireServer()
	end

	UserInputService.InputBegan:Connect(ping)
	UserInputService.InputChanged:Connect(ping)
end

return IdlePing
