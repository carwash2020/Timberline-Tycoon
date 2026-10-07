--!nocheck
-- Paying, opening, putting an unpaid box back, and keeping a paid one.
return function(t)
	local GameConfig = t.shared("GameConfig")
	local Instance = t.roblox.Instance
	local CFrame = t.roblox.CFrame
	local Vector3 = t.roblox.Vector3
	local Enum = t.roblox.Enum

	local function boot(grant, hour)
		local charges = { delayed = {} }
		local grants = {}
		local profile = {
			cash = 1000,
			storage = {},
			axes = { { uid = "owned", id = "SteelAxe" } },
			materials = {},
		}
		local loader = t.loader({
			-- The fold-away's delayed destroy is held here, so a test can look at the box first.
			globals = {
				task = {
					delay = function(_, fn)
						table.insert(charges.delayed, fn)
					end,
				},
			},
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
						charges.deferred = box.deferGrant
						return true, "thanks", "axe-1"
					end,
					GrantItem = function(_player, box)
						table.insert(grants, box.uid)
						return true, nil
					end,
				},
				ProfileService = {
					GetProfile = function(p)
						return if p and p.UserId == 7 then profile else nil
					end,
				},
			},
		})
		return loader, loader:server("BoxService"), charges, profile, grants
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
		t.ok(parts >= 5 and parts <= 6, "the body and its packaging, at most six parts")
		t.eq(marks, 2)
		-- The one price is on the box's label: world-space text, never a floating tag.
		t.eq(rec.part:FindFirstChild("PriceTag"), nil, "no floating price tag")
		local label
		for _, d in ipairs(rec.model:GetDescendants()) do
			t.ok(not d:IsA("BillboardGui"), "no billboard on a shelf box")
			if d.Name == "Price" and d:IsA("TextLabel") then
				t.eq(label, nil, "one price label only")
				label = d
			end
		end
		t.eq(label.Text, "$120")
		t.eq(label.TextTruncate, Enum.TextTruncate.None, "the whole price shows")
		t.eq(label.Parent.Name, "NameMark")
		t.eq(label.Parent.Parent.Name, "Label", "on the front label")
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
		t.eq(open.KeyboardKeyCode, Enum.KeyCode.E, "Interact: E on a keyboard")
		t.eq(open.GamepadKeyCode, Enum.KeyCode.ButtonX, "and X on a gamepad")
		t.eq(open.RequiresLineOfSight, false, "it works while the box is held")
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

	-- The cap sequence from the playtest: take a box, let it go, take another...
	-- then try to pick up ONE and be told "you can only carry 3 unpaid boxes".
	t.test("the carry cap counts only boxes in your hands: loose, put-back and refused ones never do", function()
		local BoxLogic = t.shared("BoxLogic")
		local GrabLogic = t.shared("GrabLogic")
		local _, Box = boot()
		local counter = counterPart()
		local boxes = {}
		for i = 1, 5 do
			boxes[i] = Box.Make({
				uid = "cap-" .. i,
				shop = "ToolShed",
				itemKind = "Axe",
				itemId = "SteelAxe",
				displayName = "Steel Axe",
				cf = CFrame.new(i * 6, 4.5, 0),
				counter = counter,
				zoneCf = CFrame.new(),
				zoneSize = Vector3.new(60, 1, 14),
				onShelf = true,
			})
		end
		local player = person(Vector3.new(0, 4.5, 0))
		local other = person(Vector3.new(0, 4.5, 0), 9)
		local function canTake(rec, who)
			who = who or player
			local facts = Box.Facts(who, { model = rec.model })
			facts.shopBox = true
			facts.userId = who.UserId
			facts.now = os.clock()
			facts.heldBy = 0
			return GrabLogic.CanGrab(facts)
		end

		-- Nothing taken: the first pickup is allowed and the numbers are zero.
		local mine, all = Box.UnpaidOffShelf(7)
		t.eq({ mine, all }, { 0, 0 })
		t.eq({ canTake(boxes[1]) }, { true })

		-- Take three, one after another, and drop each on the floor of the shop.
		for i = 1, 3 do
			t.eq({ canTake(boxes[i]) }, { true }, "box " .. i .. " may be taken")
			Box.NoteGrab(player, { model = boxes[i].model })
			mine, all = Box.UnpaidOffShelf(7)
			t.eq({ mine, all }, { 1, i }, "one in hand, " .. i .. " off the shelves")
			boxes[i].part.CFrame = CFrame.new(i * 6, 1, 30) -- the floor, far from its shelf spot
			Box.NoteRelease(player, { model = boxes[i].model }, "released")
			t.eq(boxes[i].onShelf, false, "a dropped box stays loose where it fell")
			mine, all = Box.UnpaidOffShelf(7)
			t.eq({ mine, all }, { 0, i }, "nothing in hand")
		end

		-- The fourth pickup used to be refused (three stale claims); now it is fine.
		t.eq({ canTake(boxes[4]) }, { true }, "a fourth box can be picked up with empty hands")
		t.eq(BoxLogic.CapMessage(0, 3), nil, "no cap message when you hold nothing")
		t.eq(BoxLogic.CapMessage(1, 3), nil, "or one box")
		t.eq(BoxLogic.CapMessage(3, 3), "You can only carry 3 unpaid boxes.", "only when you really hold three")

		-- Other people's boxes are not yours.
		t.eq({ canTake(boxes[5], other) }, { true })
		Box.NoteGrab(other, { model = boxes[5].model })
		mine = Box.UnpaidOffShelf(7)
		t.eq(mine, 0, "someone else's box is not counted against you")
		t.eq(select(1, Box.UnpaidOffShelf(9)), 1)

		-- Holding one and reaching for a second: 1 is below the cap.
		Box.NoteGrab(player, { model = boxes[4].model })
		t.eq(select(1, Box.UnpaidOffShelf(7)), 1)
		t.eq({ canTake(boxes[1]) }, { true }, "re-taking a loose box is never capped")
		-- Holding three at once (a future multi-hold) does hit the cap.
		for i = 1, 3 do
			boxes[i].heldBy = 7
		end
		boxes[4].heldBy = 0
		t.eq(select(1, Box.UnpaidOffShelf(7)), 3)
		boxes[4].onShelf = true
		boxes[4].claimUserId = 0
		t.eq({ canTake(boxes[4]) }, { false, "cap" }, "a real fourth in hand is refused")
		t.eq(
			GrabLogic.Message("cap", Box.Facts(player, { model = boxes[4].model })),
			"You can only carry 3 unpaid boxes."
		)
	end)

	t.test("a box let go back at its shelf spot goes back on the shelf, and stops counting", function()
		local _, Box = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local home = rec.home.Position
		local player = person(home)
		Box.NoteGrab(player, { model = rec.model })
		t.eq(rec.onShelf, false)
		t.eq(rec.heldBy, 7)
		rec.part.Anchored = false
		-- Let go 1 stud off its spot, a little above it.
		rec.part.CFrame = CFrame.new(home + Vector3.new(1, 0.8, 0))
		Box.NoteRelease(player, { model = rec.model }, "released")
		t.eq(rec.onShelf, true, "back on its shelf")
		t.eq(rec.heldBy, 0)
		t.eq(rec.claimUserId, 0)
		t.eq(rec.part.Anchored, true)
		t.ok((rec.part.CFrame.Position - home).Magnitude < 1e-3, "exactly on its spot")
		t.eq({ Box.UnpaidOffShelf(7) }, { 0, 0 })
		-- A paid box is never snapped anywhere.
		rec.onShelf = false
		rec.paid = true
		rec.buyerId = 7
		rec.part.CFrame = CFrame.new(home + Vector3.new(1, 0, 0))
		Box.NoteRelease(player, { model = rec.model }, "released")
		t.eq(rec.onShelf, false)
		t.ok((rec.part.CFrame.Position - (home + Vector3.new(1, 0, 0))).Magnitude < 1e-3)
	end)

	t.test("a grab the server refuses after freeing the box leaves nothing counted and the box on its shelf", function()
		local _, Box = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local player = person(rec.home.Position)
		-- GrabService unanchored it for the grab, then could not hand over its physics.
		rec.part.Anchored = false
		rec.part.CFrame = CFrame.new(rec.home.Position + Vector3.new(0, -0.4, 0.3))
		Box.NoteRefused(player, { model = rec.model }, "stuck")
		t.eq(rec.part.Anchored, true, "anchored again")
		t.ok((rec.part.CFrame.Position - rec.home.Position).Magnitude < 1e-3, "and back where it stood")
		t.eq(rec.onShelf, true)
		t.eq(rec.heldBy, 0)
		t.eq({ Box.UnpaidOffShelf(7) }, { 0, 0 }, "no ghost")
		-- A box someone really holds is left alone.
		Box.NoteGrab(player, { model = rec.model })
		rec.part.Anchored = false
		Box.NoteRefused(player, { model = rec.model }, "stuck")
		t.eq(rec.part.Anchored, false)
		t.eq(rec.heldBy, 7)
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
		t.eq(sent[2].line, "sleepy", "the Tool Shed shuts at night too (6 AM to 8 PM)")
		t.ok(string.find(sent[2].text, "6:00", 1, true) ~= nil, sent[2].text)
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
		local priceLabels = {}
		for _, d in ipairs(rec.model:GetDescendants()) do
			if d.Name == "Price" and d:IsA("TextLabel") then
				table.insert(priceLabels, d.Text)
			end
		end
		t.eq(priceLabels, { "R$" }, "one price line on the label; Roblox sets the number")
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

	t.test("paying hands over the BOX: the counter charges with the grant deferred", function()
		local _, Box, charges = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local player = person(rec.part.CFrame.Position)
		t.eq(Box.Pay(player, rec.uid), true)
		t.eq(charges.deferred, true, "no item yet: it is still in the box")
		t.eq(rec.pendingGrant, true)
		t.eq(rec.model ~= nil, true, "and the box is there to open")
	end)

	t.test("opening a tool box: it comes out as a pickup, the box folds away, taking it grants once", function()
		local _, Box, charges, _, grants = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local player = person(rec.part.CFrame.Position)
		Box.Pay(player, rec.uid)
		local model = rec.model
		t.eq(Box.TryOpen(player, rec.uid), true)
		t.eq(#grants, 0, "nothing is in the inventory until it is picked up")
		t.eq(model:GetAttribute("Poof"), true, "the empty box folds away")
		t.eq(#charges.delayed, 1, "and is destroyed a moment later")
		charges.delayed[1]()
		t.eq(rec.model, nil)
		local pickup = Box.Pickups()[rec.uid]
		t.ok(pickup ~= nil, "the axe came out as a physical object")
		t.ok(pickup.model:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil)
		-- Someone else, or someone far away, cannot take it.
		local thief = person(Vector3.new(0, 4.5, 0), 8)
		t.eq(Box.TakePickup(thief, rec.uid), false)
		local far = person(Vector3.new(100, 4.5, 0))
		t.eq(Box.TakePickup(far, rec.uid), false)
		t.eq(#grants, 0)
		t.eq(Box.TakePickup(player, rec.uid), true)
		t.eq(grants, { rec.uid }, "granted exactly once")
		t.eq(Box.TakePickup(player, rec.uid), false, "a second take finds nothing")
		t.eq(#grants, 1)
		t.eq(Box.Pickups()[rec.uid], nil)
	end)

	t.test(
		"a leaving player, or a pickup nobody takes, converts into the inventory: nothing is lost or doubled",
		function()
			local _, Box, _, _, grants = boot()
			local counter = counterPart()
			local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
			local player = person(rec.part.CFrame.Position)
			Box.Pay(player, rec.uid)
			Box.TryOpen(player, rec.uid)
			Box.ConvertPickups(nil, os.clock() + 1)
			t.eq(#grants, 0, "not expired yet")
			Box.Commit(player)
			t.eq(#grants, 1, "the owner left: the item is converted")
			Box.Commit(player)
			Box.ConvertPickups(nil, os.clock() + 100000)
			t.eq(#grants, 1, "never twice")
			t.eq(Box.Pickups()[rec.uid], nil)
		end
	)

	t.test("a paid box that is not opened is saved with what it still owes, and restored", function()
		local _, Box, _, profile, grants = boot()
		local counter = counterPart()
		local rec = place(Box, Vector3.new(0, 4.5, 0), counter)
		local player = person(rec.part.CFrame.Position)
		Box.Pay(player, rec.uid)
		local uid = rec.uid
		Box.Commit(player)
		t.eq(profile.storage[1].pending, true)
		Box.RememberShop("ToolShed", { counter = counter, zoneCf = CFrame.new(), zoneSize = Vector3.new(18, 1, 14) })
		Box.Restore(player, profile)
		local back = nil
		for _, item in ipairs(Box.Each()) do
			if item.paid and item.buyerId == 7 then
				back = item
			end
		end
		t.eq(back.pendingGrant, true, "still owed after the round trip")
		t.eq(Box.TryOpen(person(back.part.CFrame.Position), back.uid), true)
		t.eq(#grants, 0)
		t.ok(Box.Pickups()[back.uid] ~= nil)
		t.ok(uid ~= nil)
	end)

	t.test("a box from an older save has nothing owed: opening it only unpacks it", function()
		local _, Box, _, profile, grants = boot()
		local counter = counterPart()
		profile.storage = { { uid = "old-1", itemId = "SteelAxe", shop = "ToolShed" } }
		Box.RememberShop("ToolShed", { counter = counter, zoneCf = CFrame.new(), zoneSize = Vector3.new(18, 1, 14) })
		Box.Restore(person(Vector3.new(0, 0, 0)), profile)
		local back = nil
		for _, item in ipairs(Box.Each()) do
			if item.uid == "old-1" then
				back = item
			end
		end
		t.ok(back ~= nil)
		t.eq(back.pendingGrant, false)
		t.eq(Box.TryOpen(person(back.part.CFrame.Position), "old-1"), true)
		t.eq(#grants, 0, "its item was granted at the counter long ago")
		t.eq(Box.Pickups()["old-1"], nil)
	end)

	t.test("two unopened boxes of the same gear cannot both be bought", function()
		local _, Box = boot()
		local counter = counterPart()
		local function gear(uid, x)
			return Box.Make({
				uid = uid,
				shop = "HearthAndHome",
				itemKind = "Gear",
				itemId = "Lantern",
				displayName = "Lantern",
				cf = CFrame.new(x, 4.5, 0),
				counter = counter,
				zoneCf = CFrame.new(),
				zoneSize = Vector3.new(18, 1, 14),
				onShelf = true,
			})
		end
		local a, b = gear("g-1", 0), gear("g-2", 0.5)
		local player = person(a.part.CFrame.Position)
		t.eq(Box.Pay(player, a.uid), true)
		local ok, line = Box.Pay(player, b.uid)
		t.eq(ok, false)
		t.eq(line, "alreadyOwned")
	end)

	t.test("two unopened Sky Bin boxes cannot both be bought (one per player), other machines can", function()
		local _, Box = boot()
		local counter = counterPart()
		local function machine(uid, itemId, x)
			return Box.Make({
				uid = uid,
				shop = "ToolShed",
				itemKind = "Machine",
				itemId = itemId,
				displayName = itemId,
				cf = CFrame.new(x, 4.5, 0),
				counter = counter,
				zoneCf = CFrame.new(),
				zoneSize = Vector3.new(18, 1, 14),
				onShelf = true,
			})
		end
		local a, b = machine("sb-1", "SkyBin", 0), machine("sb-2", "SkyBin", 0.5)
		local player = person(a.part.CFrame.Position)
		t.eq(Box.Pay(player, a.uid), true)
		local ok, line = Box.Pay(player, b.uid)
		t.eq(ok, false)
		t.eq(line, "alreadyOwned")
	end)

	local function machineBox(Box, counter, kind, itemId)
		return Box.Make({
			uid = "box-" .. itemId,
			shop = "ToolShed",
			itemKind = kind,
			itemId = itemId,
			displayName = itemId,
			cf = CFrame.new(Vector3.new(0, 4.5, 0)),
			counter = counter,
			zoneCf = CFrame.new(),
			zoneSize = Vector3.new(18, 1, 14),
			onShelf = true,
		})
	end

	t.test(
		"opening a sawmill, planer or belt box starts a one-time placement; nothing is granted, the box stays",
		function()
			for _, case in ipairs({
				{ "Sawmill", "SawmillSturdy" },
				{ "Machine", "PlanerHand" },
				{ "Machine", "ConveyorStraight" },
			}) do
				local _, Box, _, profile, grants = boot()
				local counter = counterPart()
				local rec = machineBox(Box, counter, case[1], case[2])
				local player = person(rec.part.CFrame.Position)
				local started = {}
				Box.OnPlace = function(who, uid, itemId)
					table.insert(started, { who, uid, itemId })
				end
				Box.Pay(player, rec.uid)
				t.eq(rec.pendingGrant, true)
				-- Opening starts the ghost and nothing else.
				t.eq(Box.TryOpen(player, rec.uid), true)
				t.eq(#started, 1)
				t.eq({ started[1][2], started[1][3] }, { rec.uid, case[2] })
				t.eq(#grants, 0, "no stock, no hammer: the item is not delivered by opening")
				t.eq(rec.opened, false, "cancelling keeps the box")
				t.ok(rec.model ~= nil and rec.model:GetAttribute("Poof") == nil, "the box is still there")
				t.eq(rec.pendingGrant, true, "and still owed")
				-- A second open is fine (cancelled, try again).
				t.eq(Box.TryOpen(player, rec.uid), true)
				t.eq(#started, 2)
				-- The placing checks the box, then spends it once.
				t.eq(Box.ReadyForPlacement(player, rec.uid, case[2]), true)
				t.eq(Box.ReadyForPlacement(player, rec.uid, "ChopSaw"), false, "a different item is not this box")
				t.eq(Box.ReadyForPlacement(person(Vector3.zero, 8), rec.uid, case[2]), false, "someone else's box")
				t.eq(Box.ReadyForPlacement(player, "nope", case[2]), false)
				t.eq(Box.ReadyForPlacement(player, nil, case[2]), false)
				t.eq(Box.SpendForPlacement(person(Vector3.zero, 8), rec.uid, case[2]), false)
				t.eq(rec.opened, false, "a stranger can't spend it")
				t.eq(Box.SpendForPlacement(player, rec.uid, case[2]), true)
				t.eq(rec.opened, true)
				t.eq(rec.pendingGrant, false)
				t.eq(#profile.storage, 0)
				t.eq(Box.SpendForPlacement(player, rec.uid, case[2]), false, "one use")
				t.eq(Box.ReadyForPlacement(player, rec.uid, case[2]), false)
				t.eq(#grants, 0)
			end
		end
	)

	t.test("an unpaid, an old-save or a hammer-flow box can't start or spend a placement", function()
		local _, Box, _, profile = boot()
		local counter = counterPart()
		local rec = machineBox(Box, counter, "Machine", "PlanerBench")
		local player = person(rec.part.CFrame.Position)
		local started = 0
		Box.OnPlace = function()
			started += 1
		end
		t.eq(Box.ReadyForPlacement(player, rec.uid, "PlanerBench"), false, "unpaid")
		t.eq(Box.TryOpen(player, rec.uid), false)
		t.eq(started, 0)
		-- The chop saw still unpacks into stock (the hammer flow).
		local saw = machineBox(Box, counter, "Machine", "ChopSaw")
		Box.Pay(player, saw.uid)
		t.eq(Box.ReadyForPlacement(player, saw.uid, "ChopSaw"), false, "not a placement box")
		t.eq(profile.storage, {})
	end)

	t.test("a paid planer box that is not placed is kept in the save and still places after a reload", function()
		local _, Box, _, profile = boot()
		local counter = counterPart()
		local rec = machineBox(Box, counter, "Machine", "PlanerSteam")
		local player = person(rec.part.CFrame.Position)
		Box.Pay(player, rec.uid)
		t.eq(
			Box.CountUnopened(7, function(id)
				return id == "PlanerSteam"
			end),
			1
		)
		Box.Commit(player)
		t.eq(profile.storage[1].itemId, "PlanerSteam")
		t.eq(profile.storage[1].pending, true)
		Box.RememberShop("ToolShed", { counter = counter, zoneCf = CFrame.new(), zoneSize = Vector3.new(18, 1, 14) })
		Box.Restore(player, profile)
		local back = nil
		for _, item in ipairs(Box.Each()) do
			if item.paid and item.buyerId == 7 then
				back = item
			end
		end
		t.ok(back ~= nil)
		t.eq(Box.ReadyForPlacement(player, back.uid, "PlanerSteam"), true, "owed after the round trip")
		t.eq(Box.SpendForPlacement(player, back.uid, "PlanerSteam"), true)
		t.eq(profile.storage, {}, "spent: gone from the save too")
		t.eq(
			Box.CountUnopened(7, function()
				return true
			end),
			0
		)
	end)

	t.test(
		"a sawmill box from an older save has nothing owed: opening it folds it away and starts no placement",
		function()
			local _, Box, _, profile, grants = boot()
			local counter = counterPart()
			profile.storage = { { uid = "old-saw", itemId = "SawmillRickety", shop = "ToolShed" } }
			Box.RememberShop(
				"ToolShed",
				{ counter = counter, zoneCf = CFrame.new(), zoneSize = Vector3.new(18, 1, 14) }
			)
			Box.Restore(person(Vector3.new(0, 0, 0)), profile)
			local back = nil
			for _, item in ipairs(Box.Each()) do
				if item.uid == "old-saw" then
					back = item
				end
			end
			t.ok(back ~= nil)
			t.eq(back.pendingGrant, false)
			local started = 0
			Box.OnPlace = function()
				started += 1
			end
			t.eq(Box.TryOpen(person(back.part.CFrame.Position), "old-saw"), true)
			t.eq(started, 0, "its mill is already in stock: no ghost")
			t.eq(#grants, 0)
			t.eq(Box.ReadyForPlacement(person(Vector3.zero), "old-saw", "SawmillRickety"), false)
		end
	)
end
