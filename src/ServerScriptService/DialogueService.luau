--!strict
-- DialogueService: the counter conversation. One connection on Dialogue.
-- The handler budgets the call, then offers the box at the front of the
-- queue. Yes pays through BoxService (the same charge as the prompt on
-- the box). The card is a screen, so it does not sit on top of that prompt.
-- Movement is never changed here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CounterLogic = require(ReplicatedStorage.Shared.CounterLogic)
local DialogueData = require(ReplicatedStorage.Shared.DialogueData)
local ShopHoursLogic = require(ReplicatedStorage.Shared.ShopHoursLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local BoxService = require(script.Parent.BoxService)
local RateLimiter = require(script.Parent.RateLimiter)

local DialogueService = {}

local SHOP_OF: { [string]: string } = {
	Tink = "ToolShed",
	Hazel = "HearthAndHome",
	Dale = "Dealership",
}

local bound = false
local remote: RemoteEvent? = nil
local talking: { [number]: string } = {}
local offeredTo: { [number]: string? } = {}
local hooked: { [Model]: boolean } = {}

DialogueService.Last = nil :: any

local function profileOf(player: Player): any
	local ok, service = pcall(function()
		return require(script.Parent.ProfileService)
	end)
	if not ok or service == nil then
		return nil
	end
	return service.GetProfile(player)
end

function DialogueService.Hour(): number
	local ok, shop = pcall(function()
		return require(script.Parent.ShopService)
	end)
	if ok and type(shop) == "table" and type(shop.Hour) == "function" then
		return shop.Hour()
	end
	return ShopHoursLogic.FallbackHour
end

local function shopClosed(shop: string): boolean
	return not ShopHoursLogic.IsOpen(shop, DialogueService.Hour())
end

function DialogueService.Say(player: Player, line: string, shop: string, rec: any)
	local text = DialogueData.Line(line, {
		shop = shop,
		name = if rec then rec.displayName else nil,
		price = if rec then Util.formatCash(rec.price) else nil,
		hour = DialogueService.Hour(),
	})
	local card = DialogueData.Card(line)
	local payload = {
		line = line,
		text = text,
		boxUid = if rec then rec.uid else nil,
		choice = card.choice,
		noLabel = card.noLabel,
		-- The Robux shelf's yes: which pass or pack to ask Roblox about. The
		-- client sends the same BuyRobuxItem intent the Store screen sends.
		robux = if line == "robuxAsk"
				and rec
				and rec.robux
			then { kind = rec.robux.kind, key = rec.robux.key }
			else nil,
	}
	DialogueService.Last = payload
	local event = remote :: any
	if event ~= nil and type(event.FireClient) == "function" then
		event:FireClient(player, payload)
	end
end

local function lineFor(player: Player, rec: any): string
	if rec == nil then
		return "greet"
	end
	if rec.robux ~= nil then
		return "robuxOffer"
	end
	local profile = profileOf(player)
	-- A truck or trailer box with no plot: the warning, before any payment.
	if rec.itemKind == "Truck" or rec.itemKind == "Trailer" then
		local plot = if profile then profile.plot else nil
		local claimed = type(plot) == "table" and plot.claimed == true
		if not claimed then
			return "needsPlot"
		end
	end
	local cash = if profile then profile.cash else 0
	return CounterLogic.Line({
		boxUid = rec.uid,
		inZone = BoxService.InCounter(rec),
		cash = cash,
		price = rec.price,
		paid = rec.paid,
		owned = false,
		needsLand = false,
	})
end

local function onDialogue(player: Player, action: unknown, a: unknown, b: unknown)
	if not RateLimiter.Allow(player, "Dialogue") then
		return
	end
	if type(action) ~= "string" then
		return
	end
	if action == "open" and type(a) == "string" then
		talking[player.UserId] = a
		if shopClosed(a) then
			DialogueService.Say(player, "sleepy", a, nil)
			return
		end
		local uid = BoxService.Offered(player, a)
		if uid == nil then
			local prev = offeredTo[player.UserId]
			local gone = if prev then BoxService.Get(prev) else nil
			if gone and not gone.paid and not BoxService.InCounter(gone) then
				DialogueService.Say(player, "missing", a, gone)
				return
			end
			DialogueService.Say(player, "greet", a, nil)
			return
		end
		offeredTo[player.UserId] = uid
		local rec = BoxService.Get(uid)
		DialogueService.Say(player, lineFor(player, rec), a, rec)
	elseif action == "pick" and a == "no" and type(b) == "string" then
		BoxService.Decline(player, b)
		offeredTo[player.UserId] = nil
		local shop = talking[player.UserId] or "ToolShed"
		DialogueService.Say(player, "declined", shop, BoxService.Get(b))
	elseif action == "pick" and a == "yes" and type(b) == "string" then
		local shop = talking[player.UserId] or "ToolShed"
		if shopClosed(shop) then
			DialogueService.Say(player, "sleepy", shop, nil)
			return
		end
		BoxService.Pay(player, b)
	elseif action == "pay" and type(a) == "string" then
		local shop = talking[player.UserId] or "ToolShed"
		if shopClosed(shop) then
			DialogueService.Say(player, "sleepy", shop, nil)
			return
		end
		BoxService.Pay(player, a)
	end
end

local function findTalk(model: Model): ProximityPrompt?
	local direct = model:FindFirstChild("Talk")
	if direct and direct:IsA("ProximityPrompt") then
		return direct
	end
	if type((model :: any).GetDescendants) ~= "function" then
		return nil
	end
	for _, child in ipairs(model:GetDescendants()) do
		if child.Name == "Talk" and child:IsA("ProximityPrompt") then
			return child
		end
	end
	return nil
end

local function hook(model: Model)
	if hooked[model] then
		return
	end
	local attr = model:GetAttribute("NPCId")
	local id = if type(attr) == "string" then attr else model.Name
	local shop = SHOP_OF[id]
	if shop == nil then
		return
	end
	local talk = findTalk(model)
	if talk == nil then
		return
	end
	hooked[model] = true
	talk.Triggered:Connect(function(who: Player)
		onDialogue(who, "open", shop)
	end)
end

local function watchKeepers()
	local Workspace = game:GetService("Workspace")
	local function consider(inst: Instance)
		if inst:IsA("Model") then
			hook(inst)
		end
	end
	if type((Workspace :: any).GetDescendants) == "function" then
		for _, child in ipairs(Workspace:GetDescendants()) do
			consider(child)
		end
	end
	local added = (Workspace :: any).DescendantAdded
	if type(added) == "table" and type(added.Connect) == "function" then
		added:Connect(consider)
	end
end

function DialogueService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remote = remoteEvent
	remoteEvent.OnServerEvent:Connect(function(player: Player, action: unknown, a: unknown, b: unknown)
		-- B15: a remote "open" must name a real shop (the keeper's prompt
		-- is the usual way in), so a made-up id is never stored.
		if
			action == "open"
			and (type(a) ~= "string" or not table.find({ "ToolShed", "HearthAndHome", "Dealership" }, a))
		then
			return
		end
		onDialogue(player, action, a, b)
	end)
	BoxService.Speaker = function(player: Player, line: string, rec: any)
		local shop = if rec then rec.shop else (talking[player.UserId] or "ToolShed")
		DialogueService.Say(player, line, shop, rec)
	end
	pcall(watchKeepers)
end

return DialogueService
