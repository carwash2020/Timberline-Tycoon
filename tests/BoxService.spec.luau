--!nocheck
-- Paying, opening, putting an unpaid box back, and keeping a paid one.
return function(t)
	local GameConfig = t.shared("GameConfig")
	local Instance = t.roblox.Instance
	local CFrame = t.roblox.CFrame
	local Vector3 = t.roblox.Vector3
	local Enum = t.roblox.Enum

	local function boot(grant, hour)
		local charges = {}
		local profile = {
			cash = 1000,
			storage = {},
			axes = { { uid = "owned", id = "SteelAxe" } },
			materials = {},
		}
		local loader = t.loader({
			mocks = {
				ShopService = {
					Loop = function()
						return 2
					end,
					Hour = if type(hour) == "number"
						then function()
							return hour
						end
						else nil,
					ChargeAndGrant = grant or function(_player, box)
						table.insert(charges, box.uid)
						return true, "thanks", "axe-1"
					end,
				},
				ProfileService = {
					GetProfile = function(p)
						return if p and p.UserId == 7 then profile else nil
					end,
				},
			},
		})
		return loader, loader:server("BoxService"), charges, profile
	end

	local function counterPart()
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 2, 6)
		counter.CFrame = CFrame.new(0, 3, 0)
		return counter
	end

	local function person(at, userId)
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = CFrame.new(at)
		local char = Instance.new("Model")
		hrp.Parent = char
		return {
			Name = "Tester",
			UserId = userId or 7,
			Character = char,
			FindFirstChild = function()
				return nil
			end,
		}
	end

	local function place(Box, at, counter)
		return Box.Make({
			uid = "box-1",
			shop = "ToolShed",
			itemKind = "Axe",
			itemId = "SteelAxe",
			displayName = "Steel Axe",
			cf = CFrame.new(at),
			counter = counter,
			zoneCf = CFrame.new(),
			zoneSize = Vector3.new(18, 1, 14),
			onShelf = true,
		})
	end

	t.test("a shelf box is anchored, tagged, priced, and paid from the counter", function()
		local _, Box, charges = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		t.eq(rec.part.Anchored, true)
		t.eq(rec.model:HasTag("ShopBox"), true)
		t.eq(rec.part.CollisionGroup, "Boxes")
		local parts, marks = 0, 0
		for _, d in ipairs(rec.model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
			if d.Name == "ItemMark" then
				marks += 1
			end
		end
		t.eq(parts, 1)
		t.eq(marks, 2)
		local tag = rec.part:FindFirstChild("PriceTag")
		t.eq(tag.MaxDistance, 20)
		t.eq(tag.AlwaysOnTop, false)
		local label = tag:FindFirstChild("Price")
		t.eq(label.Text, "$120")
		t.ok(label.TextSize >= 14)
		t.eq(label.TextTruncate, Enum.TextTruncate.None)
		local buy = rec.part:FindFirstChild("BuyPrompt")
		t.eq(buy.Enabled, true)
		t.eq(buy.MaxActivationDistance, GameConfig.CounterPayReach)
		t.eq(buy.KeyboardKeyCode, Enum.KeyCode.E)
		t.eq(buy.GamepadKeyCode, Enum.KeyCode.ButtonX)
		t.eq(buy:GetAttribute("TapPx"), 44)
		local player = person(Vector3.new(0, 4.5, 0))
		for _ = 1, 10 do
			Box.Pay(player, rec.uid)
		end
		t.eq(#charges, 1)
		t.eq(rec.paid, true)
		t.eq(rec.buyerId, 7)
		local open = rec.part:FindFirstChild("OpenPrompt")
		t.eq(open.Enabled, true)
		t.eq(open.MaxActivationDistance, 12)
		t.eq(open.KeyboardKeyCode, Enum.KeyCode.F)
		t.eq(open.GamepadKeyCode, Enum.KeyCode.ButtonY)
		t.eq(buy.Enabled, false)
	end)

	t.test("off the counter, or short, nothing is charged", function()
		local _, Box, charges = boot(function()
			return false, "broke", nil
		end)
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 40, 0), counter)
		local player = person(Vector3.new(0, 40, 0))
		local ok, line = Box.Pay(player, rec.uid)
		t.eq(ok, false)
		t.eq(line, "missing")
		t.eq(#charges, 0)
		t.eq(rec.paid, false)
		rec.part.CFrame = CFrame.new(0, 4.5, 0)
		player.Character:FindFirstChild("HumanoidRootPart").CFrame = CFrame.new(0, 4.5, 0)
		Box.RefreshPrompts()
		local broke, why = Box.Pay(player, rec.uid)
		t.eq(broke, false)
		t.eq(why, "broke")
		t.eq(rec.paid, false)
	end)

	t.test("an unpaid box outside for two watches goes back; one stud inside the door does not", function()
		local _, Box = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local home = rec.home.Position
		rec.onShelf = false
		rec.part.CFrame = CFrame.new(0, 1, -100)
		Box.Judge(1)
		t.eq(rec.onShelf, false)
		t.ok((rec.part.CFrame.Position - Vector3.new(0, 1, -100)).Magnitude < 1e-3)
		Box.Judge(2)
		t.eq(rec.onShelf, true)
		t.ok((rec.part.CFrame.Position - home).Magnitude < 1e-3, "back on its shelf")

		rec.onShelf = false
		rec.outsideStreak = 1
		local z = -rec.zoneSize.Z / 2 + 1
		rec.part.CFrame = rec.zoneCf * CFrame.new(0, 1, z)
		Box.Judge(3)
		Box.Judge(4)
		t.eq(rec.onShelf, false)
		t.eq(rec.outsideStreak, 0)
	end)

	t.test("opening delivers once, only to the buyer, only up close", function()
		local _, Box, charges, profile = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local player = person(rec.part.CFrame.Position)
		local unpaid, whyUnpaid = Box.TryOpen(player, rec.uid)
		t.eq(unpaid, false)
		t.eq(whyUnpaid, "unpaid")
		rec.paid = true
		rec.buyerId = 7
		rec.axeUid = "axe-1"
		local far = person(rec.part.CFrame.Position + Vector3.new(12.01, 0, 0))
		local tooFar, whyFar = Box.TryOpen(far, rec.uid)
		t.eq(tooFar, false)
		t.eq(whyFar, "far")
		local other = person(rec.part.CFrame.Position, 8)
		local stolen, whyStolen = Box.TryOpen(other, rec.uid)
		t.eq(stolen, false)
		t.eq(whyStolen, "owner")
		rec.part:SetAttribute("BoxUid", "nope")
		local mismatch, whyUid = Box.TryOpen(player, rec.uid)
		t.eq(mismatch, false)
		t.eq(whyUid, "uid")
		rec.part:SetAttribute("BoxUid", rec.uid)
		local near = person(rec.part.CFrame.Position + Vector3.new(12, 0, 0))
		t.eq(Box.TryOpen(near, rec.uid), true)
		t.eq(Box.TryOpen(near, rec.uid), false)
		t.eq(#charges, 0, "opening does not grant a second copy")
		t.eq(#profile.axes, 1)
	end)

	t.test("leaving with a paid box keeps it, and coming back shows it once", function()
		local _, Box, charges, profile = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local uid = rec.uid
		rec.paid = true
		rec.buyerId = 7
		rec.onShelf = false
		local player = person(Vector3.new(0, 4.5, 0))
		Box.Commit(player)
		t.eq(#profile.storage, 1)
		t.eq(profile.storage[1].uid, uid)
		t.eq(profile.storage[1].itemId, "SteelAxe")
		t.eq(#profile.axes, 1)
		t.eq(Box.Get(uid), nil)
		Box.RememberShop("ToolShed", {
			counter = counter,
			zoneCf = CFrame.new(),
			zoneSize = Vector3.new(18, 1, 14),
		})
		Box.Restore(player, profile)
		Box.Restore(player, profile)
		local shown = 0
		local back = nil
		for _, item in ipairs(Box.Each()) do
			if item.paid and item.buyerId == 7 then
				shown += 1
				back = item
			end
		end
		t.eq(shown, 1)
		local opener = person(back.part.CFrame.Position)
		t.eq(Box.TryOpen(opener, back.uid), true)
		t.eq(#profile.storage, 0)
		t.eq(#profile.axes, 1)
		t.eq(#charges, 0)
	end)

	t.test("a bought slot refills on its timer, and picking one up does not start it", function()
		local _, Box = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local player = person(rec.part.CFrame.Position)
		Box.NoteGrab(player, { model = rec.model })
		t.eq(rec.onShelf, false)
		t.eq(rec.claimUserId, 7)
		t.eq(Box.RespawnDue(100000), {})
		Box.NoteSold(rec.slotId, 50)
		t.eq(Box.RespawnDue(50 + GameConfig.BoxRespawnSec - 0.1), {})
		t.eq(Box.RespawnDue(50 + GameConfig.BoxRespawnSec), { rec.slotId })
		Box.NoteSold("hearth-LampPost", 50)
		t.eq(Box.RespawnDue(50 + GameConfig.BoxRespawnSec), { rec.slotId }, "the lamp uses its own pool")
	end)

	t.test("BoxOpen is budgeted, and boxes do not shove players", function()
		local handlers = {}
		local remote = {
			OnServerEvent = {
				Connect = function(_, fn)
					table.insert(handlers, fn)
					return { Disconnect = function() end }
				end,
			},
			Fire = function(_, player, action)
				for _, fn in ipairs(handlers) do
					fn(player, action)
				end
			end,
		}
		local loader, Box = boot()
		Box.Init(remote)
		Box.Init(remote)
		t.eq(#handlers, 1)
		local who = { Name = "Tester", UserId = 3 }
		for _ = 1, 4 do
			remote.Fire(remote, who, "no-such-box")
		end
		local RateLimiter = loader:server("RateLimiter")
		t.eq(RateLimiter.Allow(who, "BoxOpen"), false)

		local calls = {}
		local registered = {}
		local physics = t.loader({
			services = {
				PhysicsService = {
					IsCollisionGroupRegistered = function(_, name)
						return registered[name] == true
					end,
					RegisterCollisionGroup = function(_, name)
						registered[name] = true
					end,
					CollisionGroupSetCollidable = function(_, a, b, on)
						table.insert(calls, { a, b, on })
					end,
				},
			},
		})
		local Boxes = physics:server("BoxService")
		Boxes.Init(remote)
		t.eq(registered.Boxes, true)
		t.eq(calls[1], { "Boxes", "Players", false })
	end)

	t.test("the keeper offers the box on the counter by name and price", function()
		local loader, Box, _charges, profile = boot()
		profile.cash = 1000
		local counter = counterPart()
		place(Box, Vector3.new(0, 4.5, 0), counter)
		local sent = {}
		local handler
		local remote = {
			OnServerEvent = {
				Connect = function(_, fn)
					handler = fn
					return { Disconnect = function() end }
				end,
			},
			FireClient = function(_, _player, payload)
				table.insert(sent, payload)
			end,
		}
		local Dialogue = loader:server("DialogueService")
		Dialogue.Init(remote)
		local player = person(Vector3.new(0, 4.5, 0))
		handler(player, "open", "ToolShed")
		t.eq(sent[1].line, "offer")
		t.eq(sent[1].choice, true)
		t.ok(string.find(sent[1].text, "Steel Axe", 1, true) ~= nil, sent[1].text)
		t.ok(string.find(sent[1].text, "$120", 1, true) ~= nil, sent[1].text)
	end)

	t.test("a closed counter hides Buy and will not charge a carried box", function()
		local seen = {}
		local _, Box = boot(function(_player, box)
			table.insert(seen, box)
			return false, "sleepy", nil
		end, 22)
		local counter = counterPart()
		local rec = Box.Make({
			uid = "night-box",
			shop = "HearthAndHome",
			itemKind = "Gear",
			itemId = "InsulatedCoat",
			displayName = "Insulated Coat",
			price = 500,
			cf = CFrame.new(0, 4.5, 0),
			counter = counter,
			zoneCf = CFrame.new(),
			zoneSize = Vector3.new(18, 1, 14),
			onShelf = true,
		})
		local buy = rec.part:FindFirstChild("BuyPrompt")
		t.eq(buy.Enabled, false, "no buy prompt while the shop is closed")
		local player = person(Vector3.new(0, 4.5, 0))
		local ok, line = Box.Pay(player, rec.uid)
		t.eq(ok, false)
		t.eq(line, "sleepy")
		t.eq(seen[1].shop, "HearthAndHome")
		t.eq(rec.paid, false)
	end)

	t.test("a closed keeper offers no buy card and says when the shop opens", function()
		local loader = boot(nil, 22)
		local sent = {}
		local handler
		local remote = {
			OnServerEvent = {
				Connect = function(_, fn)
					handler = fn
					return { Disconnect = function() end }
				end,
			},
			FireClient = function(_, _player, payload)
				table.insert(sent, payload)
			end,
		}
		local Dialogue = loader:server("DialogueService")
		Dialogue.Init(remote)
		handler(person(Vector3.new(0, 4.5, 0)), "open", "HearthAndHome")
		t.eq(sent[1].line, "sleepy")
		t.eq(sent[1].choice, false)
		t.ok(string.find(sent[1].text, "7:00", 1, true) ~= nil, sent[1].text)
		handler(person(Vector3.new(0, 4.5, 0)), "open", "ToolShed")
		t.eq(sent[2].line, "greet", "the Tool Shed still greets at night")
	end)

	-- The gold Robux shelf: the same box and the same counter, but the
	-- counter takes no cash. Yes sends the client the item (the same
	-- BuyRobuxItem intent the Store sends); the box goes back on its shelf.
	local function robuxBox(Box, counter, at)
		return Box.Make({
			uid = "gold-1",
			shop = "ToolShed",
			displayName = "2x Cash",
			robux = { kind = "Pass", key = "DoubleCash" },
			cf = CFrame.new(at),
			counter = counter,
			zoneCf = CFrame.new(),
			zoneSize = Vector3.new(18, 1, 14),
			onShelf = true,
		})
	end

	t.test("a Robux box is gold, tagged R$, and never charges cash", function()
		local _, Box, charges, profile = boot()
		local counter = counterPart()
		local rec = robuxBox(Box, counter, Vector3.new(0, 4.5, 0))
		t.eq(rec.itemKind, "Robux")
		t.eq(rec.price, 0)
		t.eq(rec.limited, false)
		t.eq(rec.part.Material, Enum.Material.Metal)
		t.eq(rec.part.Color, t.roblox.Color3.fromHex("#E3B73C"))
		t.eq(rec.part:FindFirstChild("PriceTag"):FindFirstChild("Price").Text, "R$", "Roblox sets the price")
		local said = {}
		Box.Speaker = function(_player, line, r)
			table.insert(said, { line = line, robux = r.robux })
		end
		local player = person(Vector3.new(0, 4.5, 0))
		-- Away from the counter nothing happens.
		rec.part.CFrame = CFrame.new(0, 40, 0)
		local lost, why = Box.Pay(person(Vector3.new(0, 40, 0)), rec.uid)
		t.eq(lost, false)
		t.eq(why, "missing")
		rec.part.CFrame = CFrame.new(0, 4.5, 0)
		rec.onShelf = false
		Box.RefreshPrompts()
		for _ = 1, 3 do
			Box.Pay(player, rec.uid)
		end
		t.eq(#charges, 0, "ShopService was never asked to charge")
		t.eq(profile.cash, 1000)
		t.eq(rec.paid, false)
		t.eq(#said, 4, "missing once, then robuxAsk three times")
		t.eq(said[2].line, "robuxAsk")
		t.eq(said[2].robux, { kind = "Pass", key = "DoubleCash" })
		t.eq(rec.onShelf, true, "the box went back to its shelf")
		t.ok((rec.part.CFrame.Position - rec.home.Position).Magnitude < 1e-3)
	end)

	t.test("a Robux box only forwards an item the shelf lists", function()
		local _, Box, charges = boot()
		local counter = counterPart()
		local rec = Box.Make({
			uid = "gold-bad",
			shop = "ToolShed",
			displayName = "Nope",
			robux = { kind = "Pass", key = "NotARealPass" },
			cf = CFrame.new(0, 4.5, 0),
			counter = counter,
			zoneCf = CFrame.new(),
			zoneSize = Vector3.new(18, 1, 14),
			onShelf = true,
		})
		local lines = {}
		Box.Speaker = function(_player, line)
			table.insert(lines, line)
		end
		local ok, line = Box.Pay(person(Vector3.new(0, 4.5, 0)), rec.uid)
		t.eq(ok, false)
		t.eq(line, "locked")
		t.eq(lines, { "locked" })
		t.eq(#charges, 0)
	end)

	t.test("the keeper asks about a Robux box and hands the client the item on Yes", function()
		local loader, Box = boot()
		local counter = counterPart()
		robuxBox(Box, counter, Vector3.new(0, 4.5, 0))
		local sent = {}
		local handler
		local remote = {
			OnServerEvent = {
				Connect = function(_, fn)
					handler = fn
					return { Disconnect = function() end }
				end,
			},
			FireClient = function(_, _player, payload)
				table.insert(sent, payload)
			end,
		}
		local Dialogue = loader:server("DialogueService")
		Dialogue.Init(remote)
		local player = person(Vector3.new(0, 4.5, 0))
		handler(player, "open", "ToolShed")
		t.eq(sent[1].line, "robuxOffer")
		t.eq(sent[1].choice, true)
		t.eq(sent[1].noLabel, "No")
		t.eq(sent[1].robux, nil, "asking carries no purchase")
		t.ok(string.find(sent[1].text, "2x Cash", 1, true) ~= nil, sent[1].text)
		handler(player, "pick", "yes", "gold-1")
		local last = sent[#sent]
		t.eq(last.line, "robuxAsk")
		t.eq(last.choice, false)
		t.eq(last.robux, { kind = "Pass", key = "DoubleCash" })
		handler(player, "pick", "no", "gold-1")
		t.eq(sent[#sent].robux, nil, "No sends nothing to Roblox")
	end)

	t.test("the Tool Shed's gold slots stock gold boxes, and its tables stock cash boxes", function()
		local loader, Box = boot()
		local RobuxShelf = loader:shared("RobuxShelf")
		local StoreStock = loader:shared("StoreStock")
		local Instance2 = Instance
		local model = Instance2.new("Model")
		model.Name = "ToolShed"
		local counter = counterPart()
		counter.Parent = model
		local function slot(name, slotId, x)
			local att = Instance2.new("Attachment")
			att.Name = name
			att:SetAttribute("SlotId", slotId)
			att.Position = Vector3.new(x, 2, 0)
			att.Parent = counter
		end
		slot("ShelfSlot", "toolshed-SteelAxe", -2)
		slot("RobuxSlot", RobuxShelf.SlotId("Pass", "DoubleCash"), 1)
		slot("RobuxSlot", "robux-Pass-NotListed", 2)
		Box.StockShop(model)
		local gold, cash = 0, 0
		for _, rec in ipairs(Box.Each()) do
			if rec.robux then
				gold += 1
				t.eq(rec.slotId, "robux-Pass-DoubleCash")
			elseif rec.slotId == "toolshed-SteelAxe" then
				cash += 1
			end
		end
		t.eq(gold, 1, "an unlisted gold slot stocks nothing")
		t.eq(cash, 1)
		t.ok(StoreStock.Get("robux-Pass-DoubleCash") == nil, "the gold shelf is not cash stock")
	end)
end
