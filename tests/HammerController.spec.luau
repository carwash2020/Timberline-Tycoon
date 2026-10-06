--!nocheck
-- The hammer on the client: what a use does (list, sheet, kit bar, or
-- nothing), the sheet's Move, Turn and Sell, the plan tool's use, and that
-- no new key is bound for any of it.
return function(t)
	local roblox = t.roblox
	local Enum, Vector2, Vector3, CFrame = roblox.Enum, roblox.Vector2, roblox.Vector3, roblox.CFrame
	local fs = require("@lune/fs")

	local function signal()
		local s = { handlers = {} }
		function s:Connect(fn)
			table.insert(self.handlers, fn)
			return { Disconnect = function() end }
		end
		function s:fire(...)
			for _, fn in ipairs(self.handlers) do
				fn(...)
			end
		end
		return s
	end

	local function attrs(owner)
		return {
			SetAttribute = function(_, key, value)
				owner.attrs[key] = value
			end,
			GetAttribute = function(_, key)
				return owner.attrs[key]
			end,
		}
	end

	-- A Tool in the fake character.
	local function tool(attributes)
		local tl = { attrs = attributes, Activated = signal(), ClassName = "Tool" }
		function tl:IsA(class)
			return class == "Tool"
		end
		function tl:GetAttribute(key)
			return self.attrs[key]
		end
		return tl
	end

	-- A placed piece the aim can hit.
	local function model(attributes)
		local m = { attrs = attributes }
		function m:GetAttribute(key)
			return self.attrs[key]
		end
		return m
	end

	local function setup(options)
		options = options or {}
		local fires, toasts, opened, begun, selected, knocks = {}, {}, {}, {}, {}, {}
		local state = { placing = false, shopOpen = false, aimed = nil, last = Enum.UserInputType.MouseMovement }
		local placed = options.placed or {}
		local character = { kids = {}, ChildAdded = signal(), ChildRemoved = signal() }
		function character:GetChildren()
			return table.clone(self.kids)
		end
		local humanoid = {
			EquipTool = function(_, tl)
				table.insert(character.kids, tl)
				tl.Parent = character
				character.ChildAdded:fire(tl)
			end,
			UnequipTools = function() end,
		}
		function character:FindFirstChildOfClass(class)
			return if class == "Humanoid" then humanoid else nil
		end
		local backpack = { kids = {}, ChildAdded = signal() }
		function backpack:GetChildren()
			return table.clone(self.kids)
		end
		local player = {
			UserId = 7,
			Character = character,
			CharacterAdded = signal(),
			ChildAdded = signal(),
			attrs = { PlotTier = 1, Cash = 1000 },
		}
		function player:GetAttribute(key)
			return self.attrs[key]
		end
		function player:FindFirstChildOfClass(class)
			return if class == "Backpack" then backpack else nil
		end
		local remotes = {}
		local function remote(name)
			if not remotes[name] then
				remotes[name] = {
					OnClientEvent = signal(),
					FireServer = function(_, ...)
						table.insert(fires, { name, ... })
					end,
				}
			end
			return remotes[name]
		end
		local touch = signal()
		local render = signal()
		local clock = { now = 0 }
		local loader = t.loader({
			services = {
				Debris = { AddItem = function() end },
				Players = { LocalPlayer = player },
				RunService = { RenderStepped = render },
				UserInputService = {
					GetLastInputType = function()
						return state.last
					end,
					GetMouseLocation = function()
						return Vector2.new(400, 300)
					end,
					TouchTapInWorld = touch,
				},
			},
			globals = {
				os = {
					clock = function()
						return clock.now
					end,
					time = os.time,
				},
				task = {
					defer = function(fn, ...)
						fn(...)
					end,
				},
				workspace = { CurrentCamera = { ViewportSize = Vector2.new(1280, 720) } },
			},
			mocks = {
				Net = { Remote = remote },
				SoundData = {
					PlayAt = function(name, pos)
						table.insert(knocks, { name, pos })
					end,
				},
				HUD = {
					Toast = function(text)
						table.insert(toasts, text)
					end,
				},
				Quality = {
					Budget = function()
						return { ChipCount = 24 }
					end,
				},
				BlueprintPlacer = {
					Active = function()
						return state.placing
					end,
					OnPlaced = function() end,
					MyPlaced = function()
						return placed
					end,
					MySquares = function()
						return {}
					end,
					PlotCFrame = function()
						return CFrame.new(0, 0, 0)
					end,
					Begin = function(bp, opts)
						table.insert(begun, { bp = bp, opts = opts })
					end,
				},
				BuilderTools = {
					Aim = function()
						return state.aimed
					end,
					SelectModel = function(m)
						table.insert(selected, m)
					end,
				},
				ShopUI = {
					IsOpen = function()
						return state.shopOpen
					end,
					OpenCustom = function(shop)
						table.insert(opened, shop)
					end,
					Close = function() end,
				},
			},
		})
		local Controller = loader:load("StarterPlayer/StarterPlayerScripts/HammerController")
		Controller.Dust = function(pos)
			table.insert(knocks, { "dust", pos })
		end
		Controller.SetOpener(function()
			table.insert(opened, "plans")
		end)
		return {
			Controller = Controller,
			state = state,
			fires = fires,
			toasts = toasts,
			opened = opened,
			begun = begun,
			selected = selected,
			knocks = knocks,
			character = character,
			backpack = backpack,
			player = player,
			touch = touch,
			render = render,
			clock = clock,
			remote = remote,
			PlotData = loader:shared("PlotData"),
			placed = placed,
		}
	end

	local function placedItem(extra)
		local item = { uid = "u1", blueprintId = "Bench", x = 10, z = 10, rot = 0 }
		for k, v in pairs(extra or {}) do
			item[k] = v
		end
		return item
	end

	local function pieceModel(item, extra)
		local attributes = { Uid = item.uid, BlueprintId = item.blueprintId, OwnerId = 7 }
		for k, v in pairs(extra or {}) do
			attributes[k] = v
		end
		return model(attributes)
	end

	t.test("a use with nothing aimed at opens the blueprint list", function()
		local s = setup()
		s.Controller.Use()
		t.eq(s.opened, { "plans" })
	end)

	t.test("a use while a ghost is out, or a panel is up, does nothing (the click places)", function()
		local s = setup()
		s.state.placing = true
		s.Controller.Use()
		s.state.placing = false
		s.state.shopOpen = true
		s.Controller.Use()
		s.Controller.SetPanelCheck(function()
			return true
		end)
		s.state.shopOpen = false
		s.Controller.Use()
		t.eq(s.opened, {})
	end)

	t.test("aimed at someone else's piece, a use just opens the list", function()
		local s = setup()
		s.state.aimed = model({ Uid = "x", BlueprintId = "Bench", OwnerId = 99 })
		s.Controller.Use()
		t.eq(s.opened, { "plans" })
	end)

	t.test("aimed at your own piece, a use opens its sheet: Move, Turn, Sell", function()
		local item = placedItem()
		local s = setup({ placed = { item } })
		s.state.aimed = pieceModel(item)
		s.Controller.Use()
		t.eq(#s.opened, 1)
		local shop = s.opened[1]
		t.eq(shop.title, "Bench")
		t.eq(shop.ids(), { "move", "turn", "sell" })
		t.eq(shop.view("move").button, "Move")
		t.eq(shop.view("move").state, "buy")
		t.eq(shop.view("turn").button, "Turn")
		t.eq(shop.view("sell").name, "Sell +$40")
	end)

	t.test("Move hands the piece to the placer as a move; Turn sends the next quarter; Sell sends the uid", function()
		local item = placedItem()
		local s = setup({ placed = { item } })
		s.state.aimed = pieceModel(item)
		s.Controller.Use()
		local shop = s.opened[1]
		shop.view("move").onClick()
		t.eq(#s.begun, 1)
		t.eq(s.begun[1].opts.moveUid, "u1")
		t.eq(s.begun[1].bp.id, "Bench")
		shop.view("turn").onClick()
		t.eq(s.fires[#s.fires], { "MoveBlueprint", "u1", 10, 10, 1, 0 })
		shop.view("sell").onClick()
		t.eq(s.fires[#s.fires], { "SellPlaced", "u1" })
	end)

	t.test("a turn that would hit something is refused here, and nothing is sent", function()
		local item = placedItem({ x = 0, z = 0 })
		local wall = { uid = "w", blueprintId = "Bench", x = 0, z = 0, rot = 0 }
		local blocker = { uid = "b", blueprintId = "Bench", x = 1, z = 0, rot = 0 }
		local s = setup({ placed = { item, blocker, wall } })
		s.state.aimed = pieceModel(item)
		s.Controller.Use()
		s.opened[1].view("turn").onClick()
		t.eq(#s.fires, 0)
		t.ok(#s.toasts == 1 and string.find(s.toasts[1], "in the way", 1, true), s.toasts[1])
	end)

	t.test("a kit piece with wood in it cannot Move or Turn, and the row says why", function()
		local item = placedItem({ blueprintId = "Wall", paid = 32, fill = { units = 3 } })
		local s = setup({ placed = { item } })
		s.state.aimed = pieceModel(item, { Kit = true, FillUnits = 3 })
		s.Controller.Use()
		local shop = s.opened[1]
		t.eq(shop.view("move").state, "locked")
		t.eq(shop.view("move").detail, "This piece already has wood in it.")
		shop.view("move").onClick()
		shop.view("turn").onClick()
		t.eq(#s.begun, 0)
		t.eq(#s.fires, 0)
		t.eq(s.toasts, { "This piece already has wood in it.", "This piece already has wood in it." })
		t.eq(shop.view("sell").state, "bark", "it can still be taken apart")
		t.eq(shop.view("sell").name, "Take apart (planks back)")
	end)

	t.test("an unfilled kit ghost goes to the kit bar: a click already did (nothing here), RT is passed on", function()
		local item = placedItem({ blueprintId = "Wall", paid = 32, fill = { units = 0 } })
		local s = setup({ placed = { item } })
		local ghost = pieceModel(item, { Kit = true, FillUnits = 0 })
		s.state.aimed = ghost
		s.Controller.Use()
		t.eq(s.opened, {}, "no sheet for a ghost")
		t.eq(#s.selected, 0, "a mouse click is BuilderTools' own")
		s.state.last = Enum.UserInputType.Gamepad1
		s.Controller.Use()
		t.eq(s.selected, { ghost })
	end)

	t.test("a rolled plan used in hand asks the server, once per half second", function()
		local s = setup()
		local plan = tool({ BlueprintUid = "p1", BlueprintId = "Shed" })
		table.insert(s.backpack.kids, plan)
		s.Controller.Start()
		plan.Activated:fire()
		t.eq(s.fires, { { "UseBlueprint", "p1" } })
		plan.Activated:fire()
		t.eq(#s.fires, 1, "a double click is one use")
	end)

	t.test("the hammer's own use opens the list through Tool.Activated, no key bound", function()
		local s = setup()
		local hammer = tool({ Hammer = true })
		table.insert(s.backpack.kids, hammer)
		s.Controller.Start()
		hammer.Activated:fire()
		t.eq(s.opened, { "plans" })
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HammerController.luau")
		t.eq(string.find(src, "BindAction", 1, true), nil, "no ContextActionService bind")
		t.eq(string.find(src, "KeyCode", 1, true), nil, "no key")
	end)

	t.test("the hammer coming into the hand is announced, and leaving it too", function()
		local s = setup()
		local hammer = tool({ Hammer = true })
		hammer.Parent = nil
		table.insert(s.backpack.kids, hammer)
		local seen = {}
		s.Controller.OnHeldChanged(function(on)
			table.insert(seen, on)
		end)
		s.Controller.Start()
		t.eq(s.Controller.Held(), false)
		s.Controller.Equip()
		t.eq(s.Controller.Held(), true)
		hammer.Parent = nil
		s.character.ChildRemoved:fire(hammer)
		t.eq(s.Controller.Held(), false)
		t.eq(seen, { true, false })
	end)

	t.test(
		"placing swings the hammer: the grip tips back, strikes at the impact (sound and dust), and rests again",
		function()
			local s = setup()
			local HammerArt = t.load("ReplicatedStorage/Shared/Art/HammerArt")
			local Logic = t.shared("HammerLogic")
			local hammer = tool({ Hammer = true })
			hammer.Grip = HammerArt.Grip()
			table.insert(s.backpack.kids, hammer)
			s.Controller.Start()
			s.Controller.Equip()
			hammer.Parent = s.character
			t.eq(s.Controller.Held(), true)
			local spot = Vector3.new(5, 0, 5)
			s.Controller.Swing(spot)
			t.eq(s.Controller.Swinging(), true)
			-- Early in the swing the head is lifting.
			s.clock.now = Logic.SwingSeconds * 0.2
			s.render:fire()
			t.eq(hammer.Grip, HammerArt.Grip(Logic.Swing(0.2)))
			t.ok(hammer.Grip ~= HammerArt.Grip())
			t.eq(#s.knocks, 0, "no knock before the strike")
			-- The strike: the knock and the dust land together, at the spot.
			s.clock.now = Logic.SwingSeconds * (Logic.ImpactAt + 0.02)
			s.render:fire()
			t.eq(#s.knocks, 2)
			t.eq(s.knocks[1], { "HammerKnock", spot })
			t.eq(s.knocks[2], { "dust", spot })
			-- A second swing while one is going knocks but does not restart.
			s.Controller.Swing(spot)
			t.eq(#s.knocks, 4)
			-- Done: back to the resting grip, ready for the next.
			s.clock.now = Logic.SwingSeconds * 1.1
			s.render:fire()
			t.eq(hammer.Grip, HammerArt.Grip())
			t.eq(s.Controller.Swinging(), false)
			t.eq(#s.knocks, 4, "one knock per swing")
		end
	)

	t.test("another player's knock is heard and seen; junk payloads are ignored", function()
		local s = setup()
		s.Controller.Start()
		local fx = s.remote("WorldFX")
		fx.OnClientEvent:fire("Hammer", { pos = Vector3.new(1, 2, 3), by = 9 })
		t.eq(#s.knocks, 2, "a sound and a puff of dust")
		t.eq(s.knocks[1][1], "HammerKnock")
		t.eq(s.knocks[2][1], "dust")
		fx.OnClientEvent:fire("Hammer", { pos = "nowhere" })
		fx.OnClientEvent:fire("Hammer", "junk")
		fx.OnClientEvent:fire("Other", { pos = Vector3.new(1, 2, 3) })
		t.eq(#s.knocks, 2)
	end)

	t.test("the placer is never torn down by the hammer, and the hammer never trusts what it sees", function()
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HammerController.luau")
		-- Everything that changes the world goes through a remote the server validates.
		for _, name in ipairs({ "MoveBlueprint", "SellPlaced", "UseBlueprint" }) do
			t.ok(string.find(src, 'Net.Remote("' .. name .. '")', 1, true), name)
		end
		t.eq(string.find(src, "cash", 1, true), nil, "no cash here")
	end)
end
