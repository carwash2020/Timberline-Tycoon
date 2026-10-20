--!nocheck
-- The hammer's blueprint list (PlotUI.Plans): what the rows say, how the
-- filter row cycles, what a click does, and that the BUILD toggle is gone
-- while the hammer, the placer and the drop button work together.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local fs = require("@lune/fs")
	local dir = "src/StarterPlayer/StarterPlayerScripts/"

	-- CopperTrim4, SandWall4, SandFloor4, SandArch8: gated plans a stage teaches.
	local LOCKED = 4

	local function setup(attributes)
		local player = { attrs = { PlotTier = 1, Cash = 1000, PlotSlot = 1 } }
		for k, v in pairs(attributes or {}) do
			player.attrs[k] = v
		end
		function player:GetAttribute(key)
			return self.attrs[key]
		end
		local begun, toasts, reopened, closes, fires = {}, {}, {}, {}, {}
		local menuOpens, menuCloses = {}, {}
		local C = setmetatable({}, {
			__index = function()
				return roblox.Color3.new(0, 0, 0)
			end,
		})
		local loader = t.loader({
			services = {
				ContextActionService = {},
				GuiService = {},
				Players = { LocalPlayer = player },
				ProximityPromptService = {},
				UserInputService = { LastInputTypeChanged = { Connect = function() end } },
			},
			mocks = {
				UITheme = {
					Colors = C,
					Fonts = {},
					Device = function()
						return "desktop"
					end,
				},
				HUD = {
					Toast = function(text)
						table.insert(toasts, text)
					end,
				},
				ShopUI = {
					Close = function()
						table.insert(closes, true)
					end,
					OpenCustom = function(_, focus)
						table.insert(reopened, focus)
					end,
					Refresh = function() end,
				},
				BuildMenuUI = {
					Start = function() end,
					Open = function(o)
						table.insert(menuOpens, o)
					end,
					Close = function()
						table.insert(menuCloses, true)
					end,
				},
				BlueprintPlacer = {
					PlotCFrame = function()
						return CFrame.new(0, 0, 0)
					end,
					Active = function()
						return false
					end,
					Begin = function(bp, opts)
						table.insert(begun, { bp = bp, opts = opts })
					end,
					Stop = function() end,
				},
				DragController = { SetBuildMode = function() end },
				WireTool = {
					SetBuilding = function() end,
					Active = function()
						return false
					end,
				},
				HammerController = {
					Held = function()
						return true
					end,
				},
				Net = {
					Remote = function(name)
						return {
							FireServer = function(_, ...)
								table.insert(fires, { name, ... })
							end,
						}
					end,
				},
			},
		})
		local PlotUI = loader:load("StarterPlayer/StarterPlayerScripts/PlotUI")
		local char = { HumanoidRootPart = { Position = Vector3.new(0, 3, 0) } }
		function char:FindFirstChild(name)
			return self[name]
		end
		player.Character = char
		return {
			PlotUI = PlotUI,
			shop = PlotUI.Plans(),
			player = player,
			begun = begun,
			toasts = toasts,
			reopened = reopened,
			closes = closes,
			fires = fires,
			menuOpens = menuOpens,
			menuCloses = menuCloses,
			-- The mocked plot is centred on the origin.
			stand = function(on)
				char.HumanoidRootPart.Position = if on then Vector3.new(0, 3, 0) else Vector3.new(-3000, 3, -3000)
			end,
			PlotData = loader:shared("PlotData"),
			Book = loader:shared("BlueprintBook"),
		}
	end

	local function rowsOf(s)
		local out = {}
		for _, id in ipairs(s.shop.ids()) do
			out[id] = s.shop.view(id)
		end
		return out
	end

	t.test("the list is a filter row, a Land row, then the book's buildings", function()
		local s = setup({ Blueprints = "Bench,Wall,Shed" })
		local ids = s.shop.ids()
		t.eq(ids[1], "#filter")
		t.eq(ids[2], "#land")
		-- Lane F: after the book come four locked rows (the sandstone and copper
		-- plans a stage will teach), so the list says what is coming.
		t.eq(#ids, 5 + LOCKED)
		local seen = {}
		for i = 3, 5 do
			seen[ids[i]] = true
		end
		t.eq(seen, { Bench = true, Wall = true, Shed = true })
		for i = 6, #ids do
			t.ok(s.shop.view(ids[i]).state == "locked", ids[i] .. " is a locked row")
		end
		t.eq(s.shop.title, "Blueprints")
		t.ok(#s.shop.subtitle <= 40, "the subtitle fits two phone lines")
	end)

	t.test("a row says the name, the size and what it needs", function()
		local s = setup({ Blueprints = "Wall" })
		local row = s.shop.view("Wall")
		t.eq(row.name, "Wall")
		t.ok(string.find(row.detail, "8 × 1 studs", 1, true), row.detail)
		t.ok(string.find(row.detail, "8 u³ of planks", 1, true), row.detail)
		t.eq(row.button, "Place $32")
		t.eq(row.state, "buy")
	end)

	t.test("a boxed sawmill shows only while you hold one, with its count", function()
		local none = setup({ Blueprints = "Wall" })
		t.eq(none.shop.ids()[3], "Wall")
		t.eq(#none.shop.ids(), 3 + LOCKED)
		local held = setup({ Blueprints = "Wall", SawmillStock = "SawmillRickety,SawmillRickety" })
		local row = held.shop.view("SawmillRickety")
		t.eq(row.own, "· 2 in stock")
		t.eq(row.button, "Place")
	end)

	t.test("the filter row cycles the groups and reopens the list on itself", function()
		local s = setup({ Blueprints = "Bench,Wall,Shed" })
		local rows = rowsOf(s)
		t.eq(rows["#filter"].name, "Showing: All")
		rows["#filter"].onClick()
		t.eq(s.reopened, { "#filter" }, "the pad's selection stays on the filter")
		t.eq(s.shop.view("#filter").name, "Showing: Buildings")
		local ids = s.shop.ids()
		t.eq(
			#ids,
			2 + 2 + (LOCKED - 1),
			"Wall and Shed are Buildings (and the three locked sandstone rows); the Bench is Decor"
		)
		s.shop.view("#filter").onClick()
		t.eq(s.shop.ids()[3], "Bench")
		t.eq(#s.shop.ids(), 3 + 1, "Decor: the Bench, and the locked Copper Trim")
		s.shop.view("#filter").onClick()
		s.shop.view("#filter").onClick()
		t.eq(s.shop.view("#filter").name, "Showing: All")
	end)

	t.test("a click on a ready row closes the list and starts the ghost", function()
		local s = setup({ Blueprints = "Bench" })
		s.stand(true)
		s.shop.view("Bench").onClick()
		t.eq(#s.begun, 1)
		t.eq(s.begun[1].bp.id, "Bench")
		t.eq(s.begun[1].bp.priceCash, 80, "a plan that costs to place keeps its price")
		t.eq(#s.closes, 1)
	end)

	t.test("a learned store unlock and a boxed machine in stock place free", function()
		-- (a Mailbox: the Shed is a kit plan now and pays its kit fee on every place)
		local s = setup({ Blueprints = "Mailbox", SawmillStock = "SawmillRickety", Cash = 0 })
		s.stand(true)
		s.shop.view("Mailbox").onClick()
		t.eq(s.begun[1].bp.priceCash, 0)
		s.shop.view("SawmillRickety").onClick()
		t.eq(s.begun[2].bp.priceCash, 0)
		t.eq(#s.toasts, 0)
	end)

	t.test("a locked or unaffordable row toasts why and starts nothing", function()
		local s = setup({ Blueprints = "Warehouse,Cabin", Cash = 10 })
		s.stand(true)
		s.shop.view("Warehouse").onClick()
		t.ok(string.find(s.toasts[1], "Homestead", 1, true), s.toasts[1])
		s.shop.view("Cabin").onClick()
		t.ok(string.find(s.toasts[2], "You need", 1, true), s.toasts[2])
		t.eq(#s.begun, 0)
	end)

	t.test("off your plot a row will not start a ghost", function()
		local s = setup({ Blueprints = "Bench" })
		s.stand(false)
		s.shop.view("Bench").onClick()
		t.eq(#s.begun, 0)
		t.eq(s.toasts, { "Walk onto your plot to build." })
	end)

	t.test("a plan that is not in your book is not listed, and cannot be started by an old row", function()
		local s = setup({ Blueprints = "Wall" })
		local ids = s.shop.ids()
		for _, id in ipairs(ids) do
			t.ok(id ~= "Shed" and id ~= "Cabin", id)
		end
		s.stand(true)
		-- A row kept open from before the box ran out: it says so and does nothing.
		local gone = s.shop.view("SawmillRickety")
		t.eq(gone.button, "Gone")
		gone.onClick()
		t.eq(#s.begun, 0)
	end)

	t.test("the Land row opens the Land panel", function()
		local s = setup({ Blueprints = "Wall" })
		s.shop.view("#land").onClick()
		t.eq(#s.closes, 1)
	end)

	t.test("the BUILD toggle is gone: no BUILD button, no build-mode prompts, hammer-driven", function()
		local plot = fs.readFile(dir .. "PlotUI.luau")
		t.eq(string.find(plot, 'text = "BUILD"', 1, true), nil)
		t.eq(string.find(plot, "setBuilding(true)", 1, true), nil, "nothing turns building on by a button")
		t.eq(string.find(plot, "addPrompts", 1, true), nil, "no Move and Sell prompts on every piece")
		t.eq(string.find(plot, "BLUEPRINTS", 1, true), nil)
		t.ok(string.find(plot, "HammerController.Held()", 1, true))
		t.ok(string.find(plot, "HammerController.OnHeldChanged", 1, true))
		t.ok(string.find(plot, 'text = "PLANS"', 1, true), "the bar's clear button for a phone")
		t.ok(string.find(plot, 'text = "HAMMER"', 1, true), "a phone takes the hammer out from the side column")
		t.ok(string.find(plot, 'text = "LAND"', 1, true))
		t.ok(string.find(plot, 'text = "WIRE"', 1, true))
	end)

	t.test("the tutorial hears the list opened, only on your plot", function()
		local plot = fs.readFile(dir .. "PlotUI.luau")
		t.ok(string.find(plot, 'FireServer("build")', 1, true))
		local at = string.find(plot, "local function openPlans()", 1, true)
		local nextIf = string.find(plot, "if building then", at, true)
		t.ok(at and nextIf and nextIf - at < 80, "it is sent only while building (the hammer on your plot)")
	end)

	t.test("the placer keeps the hammer in hand and stops when it goes away", function()
		local src = fs.readFile(dir .. "BlueprintPlacer.luau")
			.. fs.readFile(dir .. "PlaceControls.luau")
			.. fs.readFile("src/ReplicatedStorage/Shared/PlaceControlsLogic.luau")
		t.ok(string.find(src, "isHammer(inHand)", 1, true), "it does not unequip the hammer")
		t.ok(string.find(src, "char.ChildRemoved:Connect", 1, true), "putting the hammer away ends it")
		t.ok(string.find(src, "BlueprintPlacer.OnPlaced", 1, true), "placing tells the hammer to swing")
		-- The old bindings are all still there, unchanged.
		for _, needle in ipairs({
			'"R"',
			"DPadRight",
			"ButtonL2",
			"Thumbstick1", -- LT + the LEFT stick flicks the ghost; the right stick is the camera's
			"ButtonR1",
			"ButtonL1",
			"PlotLogic.Check(",
			"GrabLogic.StickFlick",
		}) do
			t.ok(string.find(src, needle, 1, true), needle)
		end
	end)

	t.test("the drop keys also drop a plan", function()
		local src = fs.readFile(dir .. "AxeController.luau")
		t.ok(string.find(src, '"DropBlueprint"', 1, true))
		t.ok(string.find(src, "heldPlan()", 1, true))
		t.ok(string.find(src, "HudRules.DropPress", 1, true), "still two presses")
	end)

	t.test("the hammer adds no key: the D-pad stays as HudRules and InputKit have it", function()
		local InputKit = t.shared("InputKit")
		-- The target map is unchanged, and still safe with prompts off.
		t.ok(InputKit.PlacerSafe(InputKit.Target.placer, false))
		for _, file in ipairs({ "HammerController.luau", "PlotUI.luau" }) do
			local src = fs.readFile(dir .. file)
			t.eq(string.find(src, "DPad", 1, true), nil, file .. " binds no D-pad button")
		end
		local bar = fs.readFile(dir .. "PlotUI.luau")
		-- The side button has no gamepad key.
		local hammerButton = string.match(bar, 'name = "Hammer".-onPress = [%w%.]+')
		t.ok(hammerButton and not string.find(hammerButton, "key =", 1, true), "no gamepad key on the HAMMER button")
	end)

	t.test("the Client module list names the hammer", function()
		local client = fs.readFile(dir .. "Client.client.luau")
		t.ok(string.find(client, '"HammerController"', 1, true))
		t.ok(string.find(client, "require(script.Parent.HammerController)", 1, true))
	end)

	t.test("the hammer's list opens the build menu, not the row list; a card places through planRow", function()
		local s = setup({ Blueprints = "Bench,Wall,Shed", PlotTier = 3, Cash = 1000 })
		s.PlotUI.OpenPlans()
		t.eq(#s.reopened, 0, "the ShopUI row list is not opened")
		t.eq(#s.menuOpens, 1, "the build menu is")
		local o = s.menuOpens[1]
		t.eq(type(o.land), "function")
		-- Its entries are the whole book, unfiltered, locked rows last.
		local ids = {}
		for _, e in ipairs(o.entries()) do
			ids[e.id] = true
		end
		t.ok(ids.Bench and ids.Wall and ids.Shed, "the book's plans are on the cards")
		t.eq(o.ctx().tier, 3)
		t.eq(o.ctx().cash, 1000)
		-- A ready card on your plot: the menu closes (not ShopUI), the ghost starts.
		local wall
		for _, e in ipairs(o.entries()) do
			if e.id == "Wall" then
				wall = e
			end
		end
		o.place(wall)
		t.eq(#s.menuCloses, 1, "the build menu closed")
		t.eq(#s.closes, 0, "ShopUI.Close was not used for it")
		t.eq(#s.begun, 1)
		t.eq(s.begun[1].bp.id, "Wall", "BlueprintPlacer.Begin got the right blueprint")
	end)

	t.test("a card off your plot or locked toasts the reason and starts nothing", function()
		local s = setup({ Blueprints = "Bench,Wall,Shed", PlotTier = 1, Cash = 1000 })
		s.PlotUI.OpenPlans()
		local o = s.menuOpens[1]
		local bench
		local locked
		for _, e in ipairs(o.entries()) do
			if e.id == "Bench" then
				bench = e
			end
			if e.unlockStage ~= nil then
				locked = e
			end
		end
		s.stand(false)
		o.place(bench)
		t.eq(#s.begun, 0, "off your plot nothing starts")
		t.ok(#s.toasts >= 1 and string.find(s.toasts[#s.toasts], "plot", 1, true), "the plot toast")
		s.stand(true)
		o.place(locked)
		t.eq(#s.begun, 0, "a locked card never places")
		t.ok(#s.toasts >= 2, "and says why")
		t.eq(#s.menuCloses, 0, "the menu stays open on a refusal")
	end)
end
