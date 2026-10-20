--!nocheck
-- T382: a bought or held shop box never jumps back to its counter or shelf.
-- BoxService and GrabService run together (the real hooks) over a fake
-- clock, so a box can be bought, grabbed, carried and watched the way the
-- 2 Hz Judge and GrabService's Watch see it. Each test names the reason a
-- box came back (BoxService.LastReturn) or proves nothing sent it back.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local function signal()
		local list = {}
		local s = {}
		function s:Connect(fn)
			table.insert(list, fn)
			return { Disconnect = function() end }
		end
		function s:Fire(...)
			for _, fn in ipairs(list) do
				fn(...)
			end
		end
		return s
	end

	local function setup()
		local now = 100
		local fakeOs = setmetatable({
			clock = function()
				return now
			end,
		}, { __index = os })
		local fakeWorkspace = {
			GetAttribute = function(_, name)
				return if name == "CoreLoopActive" then 2 else nil
			end,
		}
		local market = {
			PromptGamePassPurchaseFinished = signal(),
			PromptProductPurchaseFinished = signal(),
		}
		local profile = { cash = 1000, storage = {}, axes = {}, materials = {} }
		local charges = {}
		local loader = t.loader({
			services = {
				Players = {
					PlayerAdded = signal(),
					PlayerRemoving = signal(),
					GetPlayers = function()
						return {}
					end,
					GetPlayerByUserId = function()
						return nil
					end,
				},
				PhysicsService = {
					IsCollisionGroupRegistered = function()
						return true
					end,
					RegisterCollisionGroup = function() end,
					CollisionGroupSetCollidable = function() end,
				},
				RunService = {
					IsStudio = function()
						return false
					end,
					Heartbeat = signal(),
				},
				MarketplaceService = market,
			},
			globals = { os = fakeOs, workspace = fakeWorkspace },
			mocks = {
				ShopService = {
					Loop = function()
						return 2
					end,
					ChargeAndGrant = function(_player, box)
						table.insert(charges, box.uid)
						return true, "thanks", "axe-1"
					end,
					GrantItem = function()
						return true, nil
					end,
				},
				ProfileService = {
					GetProfile = function()
						return profile
					end,
				},
			},
		})
		local Grab = loader:server("GrabService")
		Grab.Physics.SetOwner = function()
			return true
		end
		Grab.Physics.SetAuto = function() end
		local function remote()
			return { OnServerEvent = { Connect = function() end } }
		end
		Grab.Init({ Grab = remote(), Release = remote() }, function() end)
		local Box = loader:server("BoxService")
		Box.Init(nil)

		local w = { Grab = Grab, Box = Box, market = market, charges = charges, homeReturns = {} }
		local realReturn = Box.ReturnHome
		Box.ReturnHome = function(rec, reason)
			table.insert(w.homeReturns, { uid = rec.uid, reason = reason })
			return realReturn(rec, reason)
		end
		local world = Instance.new("Folder")
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 2, 6)
		counter.CFrame = CFrame.new(0, 3, 0)
		w.counter = counter
		function w.box(at, over)
			local opts = {
				uid = "box-1",
				shop = "ToolShed",
				itemKind = "Axe",
				itemId = "SteelAxe",
				displayName = "Steel Axe",
				cf = CFrame.new(at),
				parent = world,
				counter = counter,
				zoneCf = CFrame.new(),
				zoneSize = Vector3.new(18, 1, 14),
				onShelf = true,
			}
			for k, v in pairs(over or {}) do
				opts[k] = v
			end
			return Box.Make(opts)
		end
		function w.player(id, at)
			local hrp = {
				Position = at,
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
			local humanoid = { Health = 100, SeatPart = nil }
			local character = {
				FindFirstChild = function(_, name)
					return if name == "HumanoidRootPart" then hrp else nil
				end,
				FindFirstChildOfClass = function(_, class)
					return if class == "Humanoid" then humanoid else nil
				end,
			}
			return { UserId = id, Name = "P" .. id, DisplayName = "P" .. id, Character = character }, hrp
		end
		function w.wait(seconds)
			now += seconds
		end
		function w.now()
			return now
		end
		-- One watch: the box 2 Hz Judge and GrabService's Watch.
		function w.tick(dt)
			now += dt
			Box.Judge(now)
			Grab.Watch(now)
		end
		function w.moveTo(rec, hrp, at)
			rec.part.CFrame = CFrame.new(at)
			hrp.Position = at + Vector3.new(0, 0, 3)
		end
		return w
	end

	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-3)
	end

	t.test("a bought cash box, grabbed and carried 20 studs out for 10 s, is never sent home", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0))
		local player, hrp = w.player(7, Vector3.new(0, 4.5, 3))
		t.eq({ w.Box.Pay(player, rec.uid) }, { true, "thanks" })
		t.eq(rec.paid, true)
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		t.eq(rec.heldBy, 7)
		-- 20 studs out of the shop, a stud per half second, then held there.
		for i = 1, 20 do
			w.moveTo(rec, hrp, Vector3.new(0, 4.5, -i))
			w.tick(0.5)
		end
		for _ = 1, 20 do
			w.tick(0.5)
		end
		t.eq(#w.homeReturns, 0, "ReturnHome was not called")
		t.eq(w.Box.LastReturn, nil)
		t.eq(rec.paid, true)
		t.eq(rec.heldBy, 7, "still in hand")
		t.ok(near(rec.part.CFrame.Position, Vector3.new(0, 4.5, -20)), "still where it was carried")
	end)

	t.test("an unpaid box carried out is sent home, and the reason is named: outside", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0))
		local player, hrp = w.player(7, Vector3.new(0, 4.5, 3))
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		w.moveTo(rec, hrp, Vector3.new(0, 4.5, -60))
		w.tick(0.5)
		w.tick(0.5)
		w.tick(0.5)
		t.eq(rec.onShelf, true)
		t.eq(w.Box.LastReturn, { uid = "box-1", reason = "outside" })
		t.eq(rec.model:GetAttribute("ReturnReason"), "outside")
	end)

	t.test("a Robux box stays in hand under Roblox's prompt, and ends paid where it is", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0), {
			uid = "gold-1",
			displayName = "2x Cash",
			itemKind = false,
			itemId = false,
			robux = { kind = "Pass", key = "DoubleCash" },
		})
		local player, hrp = w.player(7, Vector3.new(0, 4.5, 3))
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		t.eq({ w.Box.Pay(player, rec.uid) }, { true, "robuxAsk" })
		t.eq(rec.onShelf, false, "not sent home on robuxAsk")
		t.eq(rec.heldBy, 7)
		t.eq(#w.homeReturns, 0)
		-- The prompt is open for 10 s while the box is carried out of the shop.
		for i = 1, 20 do
			w.moveTo(rec, hrp, Vector3.new(0, 4.5, -i * 3))
			w.tick(0.5)
		end
		t.eq(#w.homeReturns, 0, "Judge leaves it alone while the prompt is open")
		local where = rec.part.CFrame.Position
		w.Box.RobuxFinished(7, "Pass", "DoubleCash", true)
		t.eq(rec.paid, true)
		t.eq(rec.buyerId, 7)
		t.ok(near(rec.part.CFrame.Position, where), "marked paid where it was")
		t.eq(#w.homeReturns, 0)
		-- The shelf keeps a separate display copy.
		local copies = 0
		for _, other in ipairs(w.Box.Each()) do
			if other.robux ~= nil and other.onShelf and other ~= rec then
				copies += 1
			end
		end
		t.eq(copies, 1, "a fresh copy on the shelf")
	end)

	t.test("a Robux prompt that ends unbought, or runs out of time, sends the box home with a reason", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0), {
			uid = "gold-2",
			itemKind = false,
			itemId = false,
			robux = { kind = "Pass", key = "DoubleCash" },
		})
		local player = w.player(7, Vector3.new(0, 4.5, 3))
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		w.Box.Pay(player, rec.uid)
		w.Box.RobuxFinished(7, "Pass", "DoubleCash", false)
		t.eq(rec.onShelf, true)
		t.eq(w.Box.LastReturn, { uid = "gold-2", reason = "robuxEnd" })
		-- Timed out: still claimed at 29 s, home at 31 s.
		local rec2 = w.box(Vector3.new(0, 4.5, 0), {
			uid = "gold-3",
			itemKind = false,
			itemId = false,
			robux = { kind = "Pass", key = "DoubleCash" },
		})
		t.eq({ w.Grab.Grab(player, rec2.part, rec2.part.CFrame.Position) }, { true, nil })
		w.Box.Pay(player, rec2.uid)
		w.wait(29)
		w.Box.Judge(w.now())
		t.eq(rec2.onShelf, false)
		w.wait(2)
		w.Box.Judge(w.now())
		t.eq(rec2.onShelf, true)
		t.eq(w.Box.LastReturn, { uid = "gold-3", reason = "robuxEnd" })
	end)

	t.test("an unpaid box 3.5 studs past the padded shop volume is not returned; the counter zone is inside", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0))
		local player, hrp = w.player(7, Vector3.new(0, 4.5, 3))
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		-- The footprint is 18 wide (edge x = 9); the shop already pads it by
		-- StoreDespawnPad (6). Grown by 4 more, x = 18.5 is still inside.
		local pad = t.shared("GameConfig").StoreDespawnPad
		w.moveTo(rec, hrp, Vector3.new(9 + pad + 3.5, 1, 0))
		for _ = 1, 8 do
			w.tick(0.5)
		end
		t.eq(rec.onShelf, false)
		t.eq(#w.homeReturns, 0)
		-- Well past it, it still goes home.
		w.moveTo(rec, hrp, Vector3.new(9 + pad + 4.5 + 4, 1, 0))
		for _ = 1, 3 do
			w.tick(0.5)
		end
		t.eq(rec.onShelf, true)
		t.eq(w.Box.LastReturn.reason, "outside")
		-- The counter's own zone is inside even when the volume is somewhere else.
		local rec2 = w.box(Vector3.new(0, 4.5, 0), {
			uid = "box-2",
			zoneCf = CFrame.new(0, 0, 60),
			zoneSize = Vector3.new(2, 1, 2),
		})
		t.eq({ w.Grab.Grab(player, rec2.part, rec2.part.CFrame.Position) }, { true, nil })
		rec2.part.CFrame = CFrame.new(0, 4.5, 2.5)
		for _ = 1, 8 do
			w.tick(0.5)
		end
		t.eq(rec2.onShelf, false, "on the counter, so inside")
	end)

	t.test("a forced release 2 studs from home right after the grab does not put the box back", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0))
		local player, hrp = w.player(7, Vector3.new(0, 4.5, 3))
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		w.wait(0.3)
		w.moveTo(rec, hrp, Vector3.new(2, 4.5, 0))
		w.Grab.ReleasePlayer(player, "died")
		t.eq(rec.onShelf, false, "not put back")
		t.eq(#w.homeReturns, 0)
		t.ok(near(rec.part.CFrame.Position, Vector3.new(2, 4.5, 0)))
		-- A player's own release after a short hold (under 0.75 s) is no put-back either...
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		w.wait(0.3)
		w.Grab.Release(player, rec.part)
		t.eq(rec.onShelf, false)
		-- ...but after a real hold, letting go at the shelf spot puts it back.
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		w.wait(1)
		w.Grab.Release(player, rec.part)
		t.eq(rec.onShelf, true)
		t.eq(w.Box.LastReturn, { uid = "box-1", reason = "release" })
	end)

	t.test("a lag spike in the first Watch after a grab does not put the box back", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0))
		local player, hrp = w.player(7, Vector3.new(0, 4.5, 3))
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { true, nil })
		-- The device catches up: 40 studs in 0.2 s (over what the speed judge allows).
		w.wait(0.2)
		w.moveTo(rec, hrp, Vector3.new(0, 4.5, -40))
		w.Grab.Watch(w.now())
		t.eq(w.Grab.Holding(player), rec.model, "still held")
		t.ok(near(rec.part.CFrame.Position, Vector3.new(0, 4.5, -40)), "not snapped back to the shelf")
		-- A real teleport after the first half second is still caught.
		w.wait(1)
		w.moveTo(rec, hrp, Vector3.new(0, 4.5, -400))
		w.Grab.Watch(w.now())
		t.eq(w.Grab.Holding(player), nil)
	end)

	t.test("a second player cannot grab someone else's paid box, and it stays put", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0))
		local a = w.player(7, Vector3.new(0, 4.5, 3))
		local b = w.player(8, Vector3.new(1, 4.5, 3))
		t.eq({ w.Box.Pay(a, rec.uid) }, { true, "thanks" })
		local where = rec.part.CFrame.Position
		local ok, why = w.Grab.Grab(b, rec.part, rec.part.CFrame.Position)
		t.eq(ok, false)
		t.eq(why, "owned")
		w.tick(0.5)
		w.tick(0.5)
		t.eq(rec.heldBy, 0)
		t.eq(rec.paid, true)
		t.eq(#w.homeReturns, 0)
		t.ok(near(rec.part.CFrame.Position, where))
	end)

	t.test("a grab refused after the box was freed is named: refused", function()
		local w = setup()
		local rec = w.box(Vector3.new(0, 4.5, 0))
		local player = w.player(7, Vector3.new(0, 4.5, 3))
		w.Grab.Physics.SetOwner = function()
			return false
		end
		t.eq({ w.Grab.Grab(player, rec.part, rec.part.CFrame.Position) }, { false, "stuck" })
		t.eq(rec.onShelf, true)
		t.eq(w.Box.LastReturn, { uid = "box-1", reason = "refused" })
	end)
end
