--!nocheck
-- Plots on the server: claiming, placing, moving, selling back, growing,
-- and rebuilding a saved layout on whichever slot you get.
return function(t)
	local Vector2, Vector3 = t.roblox.Vector2, t.roblox.Vector3
	local spendDuring: (() -> ())? = nil
	local explode = false

	-- Just enough of Roblox's Instance for PlotService: properties, children,
	-- attributes, and events that record their handler.
	local function fakeInstances()
		local Instance = {}
		local methods = {}
		function methods:SetAttribute(key, value)
			self._attrs[key] = value
		end
		function methods:GetAttribute(key)
			return self._attrs[key]
		end
		function methods:GetChildren()
			return table.clone(self._children)
		end
		function methods:FindFirstChild(name)
			for _, child in ipairs(self._children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		function methods:ClearAllChildren()
			for _, child in ipairs(self:GetChildren()) do
				child.Parent = nil
			end
		end
		function methods:Destroy()
			self.Parent = nil
			self.destroyed = true
		end
		function methods:IsA(class)
			return class == self.ClassName or (class == "BasePart" and self.ClassName == "Part")
		end
		function methods:PivotTo(cframe)
			self.pivot = cframe
		end
		function Instance.new(className)
			local props = { ClassName = className, Name = className, _children = {}, _attrs = {} }
			local inst = {}
			return setmetatable(inst, {
				__index = function(_, key)
					if props[key] ~= nil then
						return props[key]
					end
					if key == "Triggered" or key == "OnServerEvent" then
						local signal = {}
						function signal:Connect(fn)
							self.fn = fn
						end
						props[key] = signal
						return signal
					end
					return methods[key]
				end,
				__newindex = function(_, key, value)
					if key == "Parent" then
						local old = props.Parent
						if old then
							local list = old._children
							table.remove(list, table.find(list, inst))
						end
						if value then
							table.insert(value._children, inst)
						end
					end
					props[key] = value
				end,
			})
		end
		return Instance
	end

	local function setup(options)
		options = options or {}
		local Instance = fakeInstances()
		local clock = 0
		local toasts, tags, questEvents = {}, {}, {}
		local base = t.loader()
		local Schema = base:server("ProfileSchema")
		local Util = base:shared("Util")
		local PlotData = base:shared("PlotData")

		local players, profiles = {}, {}
		local function newPlayer(userId, name)
			local profile = Util.deepCopy(Schema.Template)
			profile.cash = options.cash or 100000
			local root = { Position = Vector3.new(0, 3, 0) }
			local player = {
				UserId = userId,
				Name = name,
				DisplayName = name,
				attrs = {},
				Character = {
					FindFirstChild = function(_, child)
						return if child == "HumanoidRootPart" then root else nil
					end,
				},
				SetAttribute = function(self, key, value)
					self.attrs[key] = value
				end,
			}
			profiles[player] = profile
			table.insert(players, player)
			-- Stand on plot `i` (or far away when nil).
			function player.standOn(i)
				local c = if i then PlotData.Slots[i] else Vector2.new(-2000, -2000)
				root.Position = Vector3.new(c.X, 3, c.Y)
			end
			player.root = root
			-- At the unclaimed sign. The board's height follows the shelf,
			-- so the spot is the sign itself, not a guess from y = 3.
			function player.standAtSign(i)
				root.Position = Vector3.new(PlotData.Slots[i].X, 3, PlotData.Slots[i].Y)
			end
			return player, profile
		end

		local loader = t.loader({
			globals = {
				Instance = Instance,
				task = {
					spawn = function(fn)
						fn()
					end,
				},
				os = {
					clock = function()
						return clock
					end,
					time = os.time,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return players
					end,
				},
				CollectionService = {
					AddTag = function(_, inst, tag)
						tags[inst] = tag
					end,
				},
			},
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						return profiles[player]
					end,
				},
				RateLimiter = {
					Allow = function()
						return options.rate ~= false
					end,
				},
				QuestService = {
					Event = function(_player, event)
						table.insert(questEvents, event)
					end,
				},
				EconomyService = {
					GetCash = function(player)
						return profiles[player].cash
					end,
					SpendCash = function(player, amount)
						local profile = profiles[player]
						if profile.cash < amount then
							return false
						end
						profile.cash -= amount
						if spendDuring then
							spendDuring()
						end
						return true
					end,
					Refund = function(player, amount)
						profiles[player].cash += amount
						return amount, 0
					end,
				},
				BlueprintModels = {
					Build = function(bp)
						if explode then
							error("the plot would not build")
						end
						local model = Instance.new("Model")
						model.Name = bp.id
						return model
					end,
					Place = function(model, plotCFrame, x, z, rot)
						model.placedAt = { x, z, rot }
						-- World pose: the pad's origin, then the plot-local offset.
						local world = plotCFrame * t.roblox.CFrame.new(x, 0, z)
						model.placedWorld = world.Position
					end,
				},
				MachineArt = {
					Build = function(id)
						local model = Instance.new("Model")
						model.Name = id
						local root = Instance.new("Part")
						root.Name = "Root"
						root.Parent = model
						model.PrimaryPart = root
						return model
					end,
					BuildChopSaw = function()
						local model = Instance.new("Model")
						model.Name = "ChopSaw"
						return model
					end,
					SetCut = function(model, x, y)
						model:SetAttribute("CutShown", string.format("%.1f %.1f", x, y))
					end,
					SetLength = function(model, cut)
						model:SetAttribute("LengthShown", cut)
					end,
				},
				WoodService = options.wood,
				PlotFill = options.plotFill,
			},
		})
		local PlotService = loader:server("PlotService")
		local map = Instance.new("Folder")
		local remotes = {}
		for _, name in ipairs({ "PlaceBlueprint", "MoveBlueprint", "SellPlaced", "UpgradePlot", "VisitPlot" }) do
			remotes[name] = Instance.new("RemoteEvent")
		end
		PlotService.Init(map, remotes, function(_, message)
			table.insert(toasts, message)
		end)
		local plots = map:FindFirstChild("Plots")

		local function plot(i)
			return plots:FindFirstChild("Plot_" .. i)
		end
		local office = map:FindFirstChild("LandOffice")
		local counter = office:FindFirstChild("Counter")
		local prompt = counter:FindFirstChild("LandOfficePrompt")
		local function atOffice(player)
			player.root.Position = counter.CFrame.Position
		end
		-- Buys plot i the real way (stand at the Land Office, ClaimPlot). The
		-- price is topped up first, so a test's cash arithmetic is its own;
		-- the charge itself is tested where cash is the point.
		local function claim(player, i)
			local profile = profiles[player]
			if profile.plot.claimed ~= true then
				profile.cash += loader:shared("GameConfig").PlotPrice
			end
			atOffice(player)
			PlotService.Claim(player, i)
		end
		-- Placed models live beside the plot shell (PlotItems_N), not inside it.
		local function itemFolder(i)
			return plots:FindFirstChild("PlotItems_" .. i)
		end
		local function items(i)
			return itemFolder(i):GetChildren()
		end
		return {
			P = PlotService,
			config = loader:shared("GameConfig"),
			PlotData = PlotData,
			newPlayer = newPlayer,
			plot = plot,
			claim = claim,
			atOffice = atOffice,
			spendDuring = function(fn)
				spendDuring = fn
			end,
			explodeOnBuild = function(on)
				explode = on
			end,
			prompt = prompt,
			counter = counter,
			profiles = profiles,
			items = items,
			itemFolder = itemFolder,
			toasts = toasts,
			questEvents = questEvents,
			tags = tags,
			remotes = remotes,
			lastToast = function()
				return toasts[#toasts]
			end,
			advance = function(seconds)
				clock += seconds
			end,
		}
	end

	t.test("the district has an open plot per slot, each with a sign, and one Land Office that sells them", function()
		local s = setup()
		t.ok(s.prompt ~= nil, "the Land Office has its prompt")
		t.eq(s.prompt.ActionText, "Buy a plot")
		for i = 1, #s.PlotData.Slots do
			local sign = s.plot(i):FindFirstChild("Sign")
			t.eq(sign:FindFirstChild("ProximityPrompt"), nil, "no plot is claimable at its own sign: nothing is free")
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
			for _, gui in ipairs(sign:GetChildren()) do
				if gui.ClassName == "SurfaceGui" then -- sized to the board, so its text isn't stretched
					t.eq(gui.SizingMode, t.roblox.Enum.SurfaceGuiSizingMode.PixelsPerStud)
				end
			end
		end
		t.ok(s.remotes.PlaceBlueprint.OnServerEvent.fn ~= nil)
		t.ok(s.remotes.MoveBlueprint.OnServerEvent.fn ~= nil)
		t.ok(s.remotes.SellPlaced.OnServerEvent.fn ~= nil)
		t.ok(s.remotes.UpgradePlot.OnServerEvent.fn ~= nil)
	end)

	t.test("claiming a plot makes it yours, once", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 3)
		t.ok(profile.plot.claimed)
		t.eq(s.questEvents, { "plotClaimed" })
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(ann.attrs.PlotTier, 1)
		t.eq(s.plot(3):GetAttribute("OwnerId"), 1)
		s.claim(ann, 4)
		t.eq(s.lastToast(), "You already have a plot here.")
		t.eq(s.plot(4):GetAttribute("OwnerId"), nil)
		local bob = s.newPlayer(2, "Bob")
		s.claim(bob, 3) -- taken: nothing happens
		t.eq(s.plot(3):GetAttribute("OwnerId"), 1)
	end)

	t.test("placing: on your plot, snapped, paid for, saved and built", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(nil)
		s.P.Place(ann, "Bench", 10.6, -3.4, 1)
		t.eq(s.lastToast(), "Stand on your plot to build.")
		t.eq(#profile.plot.placed, 0)

		ann.standOn(1)
		s.P.Place(ann, "Bench", 10.6, -3.4, 1)
		t.eq(profile.cash, 1000 - 80)
		t.eq(#profile.plot.placed, 1)
		local item = profile.plot.placed[1]
		t.eq({ item.blueprintId, item.x, item.z, item.rot }, { "Bench", 10, -4, 1 })
		local models = s.items(1)
		t.eq(#models, 1)
		t.eq(models[1].Name, item.uid)
		t.eq(models[1]:GetAttribute("OwnerId"), 1)
		t.eq(models[1]:GetAttribute("X"), 10)
		t.eq(s.tags[models[1]], "PlacedItem")
	end)

	t.test("placing is refused (and free) when it doesn't fit", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Bench", 0, 0, 0)
		s.P.Place(ann, "Bench", 1, 0, 0)
		t.eq(s.lastToast(), "Something's in the way.")
		s.P.Place(ann, "Fence", 80, 0, 0)
		t.eq(s.lastToast(), "Outside your plot.")
		s.P.Place(ann, "Warehouse", 20, 20, 0)
		t.eq(s.lastToast(), "Needs a Homestead plot.")
		s.P.Place(ann, "Cabin", 30, 30, 0)
		t.eq(s.lastToast(), "You need $1,080 more for the Cabin.")
		for _, junk in ipairs({
			{ "Nope", 0, 0, 0 },
			{ "Flag", "x", 0, 0 },
			{ "Flag", 0 / 0, 0, 0 },
			{ "Flag", 0, 0, 7 },
		}) do
			s.P.Place(ann, table.unpack(junk))
		end
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, 1000 - 80)
	end)

	t.test("moving is free and checked like placing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.furnitureBlueprints = { Fence = true }
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Fence", 0, 0, 0)
		s.P.Place(ann, "Fence", 0, 10, 0)
		local cash = profile.cash
		local first = profile.plot.placed[1]
		s.P.Move(ann, first.uid, 0, 10, 0)
		t.eq(s.lastToast(), "Something's in the way.")
		s.P.Move(ann, first.uid, 20.9, -5, 1)
		t.eq({ first.x, first.z, first.rot }, { 20, -4, 1 })
		t.eq(profile.cash, cash)
		local model = s.itemFolder(1):FindFirstChild(first.uid)
		t.eq(model.placedAt, { 20, -4, 1 })
		t.eq(model:GetAttribute("Rot"), 1)
		s.P.Move(ann, "someone-else", 0, 0, 0) -- not yours: nothing happens
		t.eq(#profile.plot.placed, 2)
	end)

	t.test("selling back: all of it within a minute, half after", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Cabin", 0, 0, 0)
		s.P.Place(ann, "Cabin", 0, 20, 0)
		t.eq(profile.cash, 1000)
		s.P.Sell(ann, profile.plot.placed[1].uid)
		t.eq(profile.cash, 3000)
		t.eq(s.lastToast(), "Took back the Cabin: $2,000 refunded.")
		s.advance(s.P.UndoSeconds + 1)
		s.P.Sell(ann, profile.plot.placed[1].uid)
		t.eq(profile.cash, 4000)
		t.eq(s.lastToast(), "Sold the Cabin for $1,000.")
		t.eq(#profile.plot.placed, 0)
		t.eq(#s.items(1), 0)
	end)

	t.test("selling won't overflow a full wallet", function()
		local s = setup({ cash = 2000000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Flag", 0, 0, 0)
		profile.cash = 2000000
		s.P.Sell(ann, profile.plot.placed[1].uid)
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), "Your wallet is too full to sell that. Spend some first.")
	end)

	t.test("growing the plot through its tiers", function()
		local s = setup({ cash = 3000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 2)
		t.eq(profile.cash, 500)
		t.eq(ann.attrs.PlotTier, 2)
		t.eq(s.plot(1):GetAttribute("Tier"), 2)
		t.eq(s.plot(1):FindFirstChild("Pad").Size.X, 110)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 2)
		t.eq(s.lastToast(), "You need $9,500 more for a Lumber Yard.")
		profile.plot.tier = #s.PlotData.Tiers
		s.P.Upgrade(ann)
		t.eq(s.lastToast(), "Your plot size is already the biggest.")
	end)

	t.test("your layout comes back on whichever plot is free when you rejoin", function()
		local s = setup()
		local bob = s.newPlayer(2, "Bob")
		s.claim(bob, 1)
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = {
			{ uid = "a", blueprintId = "Bench", x = 4, z = 4, rot = 0 },
			{ uid = "b", blueprintId = "Retired", x = 0, z = 0, rot = 0 }, -- a blueprint that no longer exists
		}
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, nil, "joining opens the picker, it doesn't assign")
		s.P.Pass(ann)
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(#s.items(2), 1)
		t.eq(s.items(2)[1].Name, "a")
		-- P6: the bench is the pad 2 origin plus the saved (4, 4), plot-local.
		local slot = s.PlotData.Slots[2]
		local bench = s.items(2)[1]
		t.eq(bench.placedAt, { 4, 4, 0 })
		t.eq(bench.placedWorld.X, slot.X + 4)
		t.eq(bench.placedWorld.Z, slot.Y + 4)
		s.P.PlayerRemoving(ann)
		t.eq(#s.items(2), 0)
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		t.eq(#profile.plot.placed, 2, "leaving keeps the save")

		local cara, fresh = s.newPlayer(3, "Cara")
		s.P.PlayerJoined(cara, fresh) -- never bought: no plot, and no picker either
		t.eq(cara.attrs.PlotSlot, nil)
		t.eq(cara.attrs.Picking, nil)
	end)

	t.test("a sawmill from stock places free; one you don't own is a box at the Tool Shed", function()
		local s = setup({ cash = 200 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.sawmillStock = { "SawmillRickety" }
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "SawmillRickety", 0, 0, 0)
		t.eq(profile.cash, 200)
		t.eq(profile.sawmillStock, {})
		t.eq(ann.attrs.SawmillStock, "")
		t.eq(profile.plot.placed[1].data, { x = 1, y = 0.6 })
		t.eq(s.items(1)[1]:GetAttribute("CutX"), 1)
		t.eq(s.tags[s.items(1)[1]], "PlacedItem")
		-- The palette is not a shop: with none in stock, nothing is charged
		-- or placed, and the toast says where the box is.
		s.P.Place(ann, "SawmillRickety", 0, 20, 0)
		t.eq(profile.cash, 200)
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), "Buy the Rickety Sawmill at the Tool Shed first.")
	end)

	t.test("the chop saw is the same: stock places it free, none in stock is refused", function()
		local s = setup({ cash = 20000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "ChopSaw", 0, 0, 0)
		t.eq(profile.cash, 20000, "no charge at the palette")
		t.eq(#profile.plot.placed, 0)
		t.eq(s.lastToast(), "Buy the Chop Saw at the Tool Shed first.")
		profile.sawmillStock = { "ChopSaw" }
		s.P.Place(ann, "ChopSaw", 0, 0, 0)
		t.eq(profile.cash, 20000)
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.sawmillStock, {})
		t.eq(ann.attrs.SawmillStock, "")
	end)

	t.test("with boxed stores off, the old pay-as-you-place comes back (the rollback)", function()
		local s = setup({ cash = 200 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.config.BoxedStores = false
		s.P.Place(ann, "SawmillRickety", 0, 20, 0)
		s.config.BoxedStores = nil
		t.eq(profile.cash, 70)
		t.eq(#profile.plot.placed, 1)
	end)

	t.test("a saved cut comes back on the mill", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = {
			{ uid = "mill", blueprintId = "SawmillRickety", x = 0, z = 0, rot = 0, data = { x = 1.4, y = 0.8 } },
		}
		s.P.PlayerJoined(ann, profile)
		s.P.Pass(ann)
		local model = s.items(1)[1]
		t.eq(model:GetAttribute("CutX"), 1.4)
		t.eq(model:GetAttribute("CutY"), 0.8)
		t.eq(model:GetAttribute("CutShown"), "1.4 0.8")
		t.eq(profile.plot.placed[1].data, { x = 1.4, y = 0.8 })
	end)

	t.test("a saved chop saw length comes back, and the mill beside it keeps its cut", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = {
			{ uid = "saw", blueprintId = "ChopSaw", x = 0, z = 0, rot = 0, data = { x = 12, y = 0 } },
			{ uid = "mill", blueprintId = "SawmillRickety", x = 8, z = 0, rot = 0, data = { x = 1.4, y = 0.8 } },
		}
		s.P.PlayerJoined(ann, profile)
		s.P.Pass(ann)
		local saw, mill
		for _, item in ipairs(s.items(1)) do
			if item.Name == "saw" then
				saw = item
			elseif item.Name == "mill" then
				mill = item
			end
		end
		t.eq(saw:GetAttribute("CutU"), 12)
		t.eq(saw:GetAttribute("LengthShown"), 12)
		t.eq(profile.plot.placed[1].data, { x = 12, y = 0 })
		t.eq(mill:GetAttribute("CutX"), 1.4)
		t.eq(mill:GetAttribute("CutY"), 0.8)
		t.eq(profile.plot.placed[2].data, { x = 1.4, y = 0.8 })
	end)

	t.test("a sawmill on someone else's plot stays in stock", function()
		local s = setup({ cash = 200 })
		local ann, profile = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		profile.sawmillStock = { "SawmillRickety" }
		s.claim(ann, 1)
		s.claim(bob, 2)
		ann.standOn(2)
		s.P.Place(ann, "SawmillRickety", 0, 0, 0)
		t.eq(profile.sawmillStock, { "SawmillRickety" })
		t.eq(profile.cash, 200)
		t.eq(#profile.plot.placed, 0)
		t.eq(s.lastToast(), "You can't build on this plot.")
	end)

	t.test("buying only works at the Land Office", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		ann.standOn(nil)
		local cash = profile.cash
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, nil, "the prompt from across the map opens nothing")
		t.eq(s.lastToast(), "Walk up to the Land Office counter to buy a plot.")
		s.P.Claim(ann, 1)
		t.eq(profile.plot.claimed, false)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(profile.cash, cash, "out of range: nothing charged")
		t.eq(s.lastToast(), "Walk up to the Land Office in town to buy a plot.")
		s.atOffice(ann)
		s.P.Claim(ann, 1)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(profile.cash, cash - s.config.PlotPrice)
	end)

	t.test("growing only works while you stand on your plot", function()
		local s = setup({ cash = 3000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(nil)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 1)
		t.eq(profile.cash, 3000)
		t.eq(s.lastToast(), "Stand on your plot to raise its size.")
	end)

	t.test("you can only build on your own plot", function()
		local s = setup({ cash = 1000 })
		local ann, annProfile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		s.claim(bob, 2)
		ann.standOn(2)
		s.P.Place(ann, "Bench", 0, 0, 0)
		t.eq(#annProfile.plot.placed, 0)
		t.eq(annProfile.cash, 1000)
		t.eq(s.lastToast(), "You can't build on this plot.")
		t.eq(#bobProfile.plot.placed, 0)
	end)

	t.test("a plot and what you place on it stream as whole models, beside the shell", function()
		local s = setup()
		local ann = s.newPlayer(1, "Ann")
		local Atomic = t.roblox.Enum.ModelStreamingMode.Atomic
		for i = 1, #s.PlotData.Slots do
			t.eq(s.plot(i).ModelStreamingMode, Atomic, "plot " .. i)
		end
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Bench", 0, 0, 0)
		local models = s.items(1)
		t.eq(#models, 1)
		t.eq(models[1].ModelStreamingMode, Atomic)
		t.eq(models[1].Parent.Name, "PlotItems_1")
		t.ok(models[1].Parent.Parent == s.plot(1).Parent, "placed items sit in the Plots folder")
		t.ok(models[1].Parent ~= s.plot(1), "placed items are not children of the plot model")
	end)

	t.test("joining twice does not hand out a second plot", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = { { uid = "a", blueprintId = "Bench", x = 4, z = 4, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		s.P.Pass(ann)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(#s.items(1), 1)
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		t.eq(#s.items(1), 1)
	end)

	t.test("a full district keeps a saved layout until a slot frees", function()
		local s = setup()
		local owners = {}
		for i = 1, #s.PlotData.Slots do
			local player = s.newPlayer(i, "P" .. i)
			s.claim(player, i)
			table.insert(owners, player)
			t.eq(player.attrs.PlotSlot, i)
		end
		local extra, profile = s.newPlayer(99, "Extra")
		profile.plot.claimed = true
		profile.plot.placed = { { uid = "bench", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		s.P.PlayerJoined(extra, profile)
		t.eq(extra.attrs.PlotSlot, nil)
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), "This server's plot district is full, so your plot isn't out today. Try another server!")
		s.P.PlayerRemoving(owners[1])
		t.eq(owners[1].attrs.PlotSlot, nil)
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		s.P.PlayerJoined(extra, profile)
		s.P.Pass(extra)
		t.eq(extra.attrs.PlotSlot, 1)
		t.eq(#s.items(1), 1)
		t.eq(s.items(1)[1].Name, "bench")
		s.P.PlayerJoined(extra, profile)
		t.eq(extra.attrs.PlotSlot, 1)
		local taken = 0
		for i = 1, #s.PlotData.Slots do
			if s.plot(i):GetAttribute("OwnerId") ~= nil then
				taken += 1
			end
		end
		t.eq(taken, #s.PlotData.Slots)
	end)

	t.test("twelve players each get a plot, and two pads stay open", function()
		local s = setup()
		local lastOffer
		for i = 1, 12 do
			local player, profile = s.newPlayer(i, "P" .. i)
			s.P.PlayerJoined(player, profile)
			s.atOffice(player)
			s.prompt.Triggered.fn(player)
			if i == 12 then
				lastOffer = s.P.OfferOf(player)
				local free = 0
				for _, plot in ipairs(lastOffer.plots) do
					if not plot.taken then
						free += 1
					end
				end
				t.eq(free, 3, "the last player still has a choice")
			end
			s.claim(player, i)
			t.eq(player.attrs.PlotSlot, i)
		end
		local free = 0
		for i = 1, #s.PlotData.Slots do
			if s.plot(i):GetAttribute("OwnerId") == nil then
				free += 1
			end
		end
		t.eq(free, #s.PlotData.Slots - 12)
	end)

	t.test("two claims of one plot in the same breath: one wins, the other is told to pick again", function()
		local s = setup()
		local ann, annProfile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		annProfile.plot.placed = { { uid = "ann", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		bobProfile.plot.placed = { { uid = "bob", blueprintId = "Flag", x = 4, z = 4, rot = 0 } }
		s.P.PlayerJoined(ann, annProfile)
		s.P.PlayerJoined(bob, bobProfile)
		for _, who in ipairs({ ann, bob }) do
			s.atOffice(who)
			s.prompt.Triggered.fn(who)
		end
		s.claim(ann, 4)
		s.claim(bob, 4)
		t.eq(ann.attrs.PlotSlot, 4)
		t.eq(bob.attrs.PlotSlot, nil)
		t.eq(s.plot(4):GetAttribute("OwnerId"), 1)
		t.eq(#s.items(4), 1)
		t.eq(s.items(4)[1].Name, "ann")
		t.eq(s.lastToast(), "Someone else claimed that plot. Pick another.")
		local offer = s.P.OfferOf(bob)
		t.eq(offer.notice, "taken")
		t.eq(offer.plots[4].taken, true)
		local jump = t.shared("PlotPickerLogic").NextOpen(offer.plots, 4)
		t.ok(jump ~= 4 and offer.plots[jump].taken ~= true, "the picker moves on")
		s.claim(bob, jump)
		t.eq(bob.attrs.PlotSlot, jump)
		t.eq(#s.items(jump), 1)
		t.eq(s.items(jump)[1].Name, "bob")
	end)

	t.test("a returning owner's picker: closing it or letting it time out takes a free pad, free", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		local cash = profile.cash
		profile.plot.placed = { { uid = "a", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(ann.attrs.Picking, true)
		s.advance(59)
		s.P.Sweep()
		t.eq(ann.attrs.PlotSlot, nil, "the timer has not run out")
		s.advance(1)
		s.P.Sweep()
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(#s.items(1), 1)
		t.eq(ann.attrs.Picking, nil)

		local bob, bobProfile = s.newPlayer(2, "Bob")
		bobProfile.plot.claimed = true
		s.P.PlayerJoined(bob, bobProfile)
		s.P.Pass(bob)
		t.eq(bob.attrs.PlotSlot, 2)
		t.eq(s.lastToast(), "It's yours! This pad is your spawn. Press BUILD to start building.")
		t.eq(profile.cash, cash, "a plot you already own is never charged again")
	end)

	t.test("leaving while the picker is open reserves nothing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.Picking, true)
		s.P.PlayerRemoving(ann)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		s.advance(120)
		s.P.Sweep()
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil, "the timer was cancelled")
		for i = 1, #s.PlotData.Slots do
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
		end
	end)

	t.test("looking through the picker does not reserve a pad", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		s.P.PlayerJoined(ann, profile)
		local offer = s.P.OfferOf(ann)
		t.eq(offer.price, 0, "a save that owns a plot sees no price")
		t.eq(#offer.plots, #s.PlotData.Slots)
		t.eq(offer.plots[1].name, "Birch Side")
		t.eq(offer.plots[1].region, "Starter Forest")
		for _, plot in ipairs(offer.plots) do
			t.eq(plot.taken, false)
		end
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
	end)

	t.test("a claimed plot is the spawn; before that, town", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local landed = nil
		ann.Character.PivotTo = function(_, cf)
			landed = cf
		end
		ann.CharacterAdded = {
			Connect = function(self, fn)
				self.fn = fn
			end,
		}
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.RespawnLocation, nil)
		if ann.CharacterAdded.fn then
			ann.CharacterAdded.fn()
		end
		t.eq(landed, nil, "still the town spawn")
		s.claim(ann, 3)
		t.ok(ann.RespawnLocation == s.plot(3):FindFirstChild("PlotSpawn"))
		t.eq(ann.attrs.PlotSlot, 3)
		landed = nil
		ann.CharacterAdded.fn()
		t.ok(landed ~= nil, "death and rejoin put them on the pad")
	end)

	t.test("loading another save keeps the pad you already stand on", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.tier = 1
		profile.plot.placed = { { uid = "old", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 5)
		local other = {
			plot = {
				claimed = true,
				tier = 3,
				placed = { { uid = "new", blueprintId = "Flag", x = 6, z = 6, rot = 1 } },
			},
		}
		t.eq(s.P.Reload(ann, other), true)
		t.eq(ann.attrs.PlotSlot, 5)
		t.eq(ann.attrs.Picking, nil)
		t.eq(ann.attrs.PlotTier, 3)
		t.eq(#s.items(5), 1)
		t.eq(s.items(5)[1].Name, "new")
		t.eq(s.plot(5):GetAttribute("OwnerId"), 1)
	end)

	t.test("a bad saved spot moves onto the plot", function()
		local s = setup()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local ann, profile = s.newPlayer(1, "Ann")
		local lake = WorldLayout.Lake
		local pad = s.PlotData.Slots[2]
		profile.truckAt = { x = lake.x, y = 4, z = lake.z }
		profile.leftLoad = { { woodId = "oak", value = 8, x = pad.X, y = 3, z = pad.Y } }
		profile.groundLoad = { { g = { pad.X, -40, pad.Y } } }
		profile.truckAt = profile.truckAt
		local town = { x = 0, y = 4, z = 40 }
		-- A second log that is fine stays put: checked after, on a fresh profile field.
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 1)
		-- There is no road-edge delivery pad any more: a stray spot goes to the
		-- middle of the plot that was claimed.
		t.eq(s.P.GetDeliveryPad, nil, "no delivery pad API")
		t.eq(s.P.DeliveryCFrame, nil, "no delivery pad API")
		local claimed = s.PlotData.Slots[1]
		local function nearDrop(x, z)
			return math.abs(x - claimed.X) < 0.01 and math.abs(z - claimed.Y) < 0.01
		end
		t.ok(nearDrop(profile.truckAt.x, profile.truckAt.z), "truckAt left the lake")
		t.ok(nearDrop(profile.leftLoad[1].x, profile.leftLoad[1].z), "leftLoad left the pad")
		t.ok(nearDrop(profile.groundLoad[1].g[1], profile.groundLoad[1].g[3]), "groundLoad left the hole")
		-- A dry town spot is not a pad and not under the ground.
		local kept = { x = town.x, y = town.y, z = town.z }
		profile.truckAt = kept
		s.P.Reload(ann, profile)
		t.eq(profile.truckAt.x, town.x)
		t.eq(profile.truckAt.z, town.z)
	end)

	t.test("a saved truckAt that sits on a new pad must spawn elsewhere on join", function()
		local s = setup()
		local _, profile = s.newPlayer(1, "Ann")
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local pad = s.PlotData.Slots[1]
		profile.truckAt = { x = pad.X, y = 3, z = pad.Y }
		profile.leftLoad = { { woodId = "oak", value = 4, x = pad.X, y = 3, z = pad.Y } }
		profile.groundLoad = { { g = { pad.X, 3, pad.Y } } }
		local server = require("@lune/fs").readFile("src/ServerScriptService/GameServer.server.luau")
		local parkAt = string.find(server, "PlotService.ParkStrays", 1, true)
		local padsAt = string.find(server, "ShopService.PlayerJoined(player, profile)", 1, true)
		t.ok(parkAt ~= nil and padsAt ~= nil and parkAt < padsAt, "the lot pass runs before the pads come back")
		t.eq(string.find(server, "VehicleService.SpawnTruck", 1, true), nil, "joining builds no truck: only a pad does")
		s.P.ParkStrays(profile)
		t.eq(WorldLayout.OnPlotPad(profile.truckAt.x, profile.truckAt.z), false)
		local lot = WorldLayout.ParkingLot
		t.ok(profile.truckAt.x > lot.x0 and profile.truckAt.x < lot.x1, "truckAt is in the town lot")
		t.ok(profile.truckAt.z > lot.z0 and profile.truckAt.z < lot.z1, "truckAt is in the town lot")
		t.eq(WorldLayout.OnPlotPad(profile.leftLoad[1].x, profile.leftLoad[1].z), false)
		t.eq(WorldLayout.OnPlotPad(profile.groundLoad[1].g[1], profile.groundLoad[1].g[3]), false)
	end)

	t.test("a build saved on one pad loads at the same spot on the pad you claim next", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.placed = {
			{ uid = "bench", blueprintId = "Bench", x = 12, z = -6, rot = 1 },
			{ uid = "flag", blueprintId = "Flag", x = -4, z = 8, rot = 2 },
		}
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 2)
		t.eq(#s.items(2), 2)
		s.P.PlayerRemoving(ann)
		t.eq(#s.items(2), 0, "the old pad is clear")
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 5)
		t.eq(#s.items(2), 0, "nothing left on the first pad")
		t.eq(#s.items(5), 2)
		local found = {}
		for _, model in ipairs(s.items(5)) do
			found[model.Name] = model.placedAt
		end
		t.eq(found.bench, { 12, -6, 1 })
		t.eq(found.flag, { -4, 8, 2 })
	end)

	t.test("a claim has to be a whole slot you don't already own", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 1.5)
		s.claim(ann, 0)
		s.claim(ann, #s.PlotData.Slots + 1)
		s.claim(ann, "nope")
		t.eq(ann.attrs.PlotSlot, nil)
		s.claim(ann, 2)
		s.claim(ann, 3)
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(s.plot(3):GetAttribute("OwnerId"), nil)
		t.eq(s.lastToast(), "You already have a plot here.")
	end)

	-- Loose wood for FillStep. One real part: every record can share it, and
	-- FillStep still sees each record (typeof Instance, a BasePart).
	local function loose(origin, uid, opts)
		opts = opts or {}
		local CFrame = t.roblox.CFrame
		local model = t.roblox.Instance.new("Model")
		model.Name = uid
		local root = t.roblox.Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(1.6, 4, 1.6)
		local at = origin + (opts.offset or Vector3.zero)
		root.CFrame = CFrame.new(at)
		root.Position = at
		root.Anchored = true
		root.Parent = model
		model.PrimaryPart = root
		model:SetAttribute("HeldBy", opts.heldBy or 0)
		return {
			uid = uid,
			kind = opts.kind or "plank",
			woodId = opts.woodId or "birch",
			volume = if opts.volume == nil then 2 else opts.volume,
			ownerId = if opts.ownerId == nil then 1 else opts.ownerId,
			root = root,
			model = model,
			figure = nil,
			boost = 0,
			lux = false,
		}
	end

	local function plotOrigin(data, index)
		local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
		local c = data.Slots[index]
		return Vector3.new(c.X, TerrainGen.HeightAt(c.X, c.Y), c.Y)
	end

	local function woodApi(pieces)
		return {
			All = function()
				return pieces
			end,
			Get = function(id)
				return pieces[id]
			end,
			Remove = function(piece)
				pieces[piece.uid] = nil
			end,
			SpawnPlank = function()
				return { uid = "left" }
			end,
		}
	end

	t.test("200 built pieces and 2500 planks give zero PlotFill.Apply calls", function()
		local applies = 0
		local pieces = {}
		local s = setup({
			wood = woodApi(pieces),
			plotFill = {
				Apply = function()
					applies += 1
					return false, "built"
				end,
			},
		})
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)
		local placed = {}
		for i = 1, 200 do
			placed[i] = {
				uid = "w" .. i,
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 8 },
				wood = "birch",
			}
		end
		profile.plot.placed = placed
		for i = 1, 2500 do
			pieces["p" .. i] = loose(origin, "p" .. i)
		end
		s.P.FillStep()
		t.eq(applies, 0)
		t.eq(placed[1].fill.units, 8, "a built piece keeps the wood it already has")
		t.eq(placed[#placed].fill.units, 8)
	end)

	t.test("a plank on the plot is offered; one past the plot plus reach is not", function()
		local applies = 0
		local pieces = {}
		local s = setup({
			wood = woodApi(pieces),
			plotFill = {
				Apply = function()
					applies += 1
					return false, "busy"
				end,
			},
		})
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)
		profile.plot.placed = {
			{ uid = "wall", blueprintId = "Wall", x = 0, z = 0, rot = 0, fill = { units = 0 } },
		}
		pieces.near = loose(origin, "near")
		pieces.far = loose(origin, "far", { offset = Vector3.new(0, 0, 500) })
		s.P.FillStep()
		t.eq(applies, 1, "only the plank inside the plot plus reach")
		t.eq(profile.plot.placed[1].fill.units, 0, "the plank past reach did not fill it")
	end)

	local function clearPieces(pieces)
		for key in pairs(pieces) do
			pieces[key] = nil
		end
	end

	t.test("a plank resting near a built wall, and a held plank near a blueprint, each give zero notifies", function()
		local pieces = {}
		local s = setup({ wood = woodApi(pieces) })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)

		profile.plot.placed = {
			{
				uid = "built",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 8 },
				wood = "birch",
			},
		}
		pieces.resting = loose(origin, "resting")
		local n = #s.toasts
		s.P.FillStep()
		t.eq(#s.toasts, n, "a plank resting near a built wall")
		t.eq(profile.plot.placed[1].fill.units, 8, "a built wall takes no more wood")

		s.advance(1)
		clearPieces(pieces)
		profile.plot.placed = {
			{ uid = "ghost", blueprintId = "Wall", x = 0, z = 0, rot = 0, fill = { units = 0 } },
		}
		pieces.held = loose(origin, "held", { heldBy = 1 })
		s.P.NoteRelease(ann, pieces.held)
		s.P.FillStep()
		t.eq(#s.toasts, n, "a held plank near a blueprint")
		t.eq(profile.plot.placed[1].fill.units, 0, "a held plank does not fill")

		-- The same blueprint, wood that isn't yours, and a log left sitting.
		s.advance(1)
		clearPieces(pieces)
		pieces.theirs = loose(origin, "theirs", { ownerId = 2 })
		pieces.log = loose(origin, "log", { kind = "log" })
		s.P.NoteRelease(ann, pieces.theirs)
		s.P.FillStep()
		t.eq(#s.toasts, n, "someone else's wood, and a log left sitting, never toast")
		t.eq(profile.plot.placed[1].fill.units, 0)
	end)

	t.test("a just-dropped log or the wrong wood toasts once, and leaving forgets that", function()
		local pieces = {}
		local s = setup({ wood = woodApi(pieces) })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)
		profile.plot.placed = {
			{
				uid = "ghost",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 0 },
				wood = "birch",
			},
		}
		pieces.oak = loose(origin, "oak", { woodId = "oak" })
		local n = #s.toasts
		s.advance(10)
		s.P.FillStep()
		t.eq(#s.toasts, n, "resting on the blueprint: no toast")
		t.eq(profile.plot.placed[1].fill.units, 0, "wrong wood left sitting does not fill")

		s.advance(1)
		s.P.NoteRelease(ann, pieces.oak)
		s.P.FillStep()
		t.eq(s.lastToast(), "This Wall is being built with Birch.")
		t.eq(#s.toasts, n + 1)
		t.eq(profile.plot.placed[1].fill.units, 0, "wrong wood does not fill")

		-- Still inside the two seconds, so the same refusal stays quiet.
		s.advance(0.2)
		s.P.NoteRelease(ann, pieces.oak)
		s.P.FillStep()
		t.eq(#s.toasts, n + 1, "told already")

		s.P.PlayerRemoving(ann)
		s.claim(ann, 1)
		s.advance(0.2)
		s.P.NoteRelease(ann, pieces.oak)
		s.P.FillStep()
		t.eq(s.lastToast(), "This Wall is being built with Birch.")
		t.eq(#s.toasts, n + 3, "leaving cleared the toast memory")

		clearPieces(pieces)
		profile.plot.placed = {
			{ uid = "open", blueprintId = "Wall", x = 0, z = 0, rot = 0, fill = { units = 0 } },
		}
		pieces.log = loose(origin, "log", { kind = "log" })
		s.advance(1)
		s.P.NoteRelease(ann, pieces.log)
		s.P.FillStep()
		t.eq(s.lastToast(), "Saw logs into planks first.")
		t.eq(profile.plot.placed[1].fill.units, 0, "a log does not fill")
	end)

	t.test("the land office uses the interact button and opens once the plot is claimed", function()
		local s = setup()
		local sign = s.plot(1):FindFirstChild("Sign")
		local office = sign:FindFirstChild("LandOffice")
		t.eq(office.Name, "LandOffice")
		t.eq(office.GamepadKeyCode, t.roblox.Enum.KeyCode.ButtonX)
		t.eq(office.KeyboardKeyCode, t.roblox.Enum.KeyCode.E)
		t.eq(office.Enabled, false)
		t.eq(sign:FindFirstChild("ProximityPrompt"), nil, "the sign no longer claims anything")
		local ann = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		t.eq(office.Enabled, true)
	end)

	t.test("expanding deducts the shown price, and too little cash buys nothing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.cash = 100
		s.P.Expand(ann, 2, 2, 0)
		t.eq(s.lastToast(), "Expand onto a square that touches your plot.")
		t.eq(profile.plot.squares, {})
		t.eq(profile.cash, 100)
		local GameConfig = t.shared("GameConfig")
		local Util = t.shared("Util")
		local step = GameConfig.ExpansionPriceStep
		s.P.Expand(ann, 1, 0, 0)
		t.eq(profile.cash, 0)
		t.eq(profile.plot.squares, { "1,0" })
		t.eq(s.lastToast(), "You expanded your plot for $100. The next square is " .. Util.formatCash(step) .. ".")
		t.eq(ann.attrs.PlotSquares, "1,0")
		s.P.Expand(ann, 1, 1, 1)
		t.eq(s.lastToast(), "You don't have enough to expand there.")
		t.eq(profile.cash, 0)
		t.eq(#profile.plot.squares, 1)
		profile.cash = step
		s.P.Expand(ann, 1, 1, 1)
		t.eq(profile.cash, 0)
		t.eq(#profile.plot.squares, 2)
		t.eq(
			s.lastToast(),
			"You expanded your plot for "
				.. Util.formatCash(step)
				.. ". The next square is "
				.. Util.formatCash(step * 2)
				.. "."
		)
		ann.standOn(nil)
		profile.cash = 6000
		s.P.Expand(ann, 0, 2, 2)
		t.eq(s.lastToast(), "Stand on your plot to expand it.")
		t.eq(#profile.plot.squares, 2)
		t.eq(profile.cash, 6000)
	end)

	t.test("two rapid expands charge once and add one square", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.cash = 10000
		local nested = 0
		spendDuring = function()
			nested += 1
			if nested == 1 then
				-- Still inside the first spend: same count, a second square.
				s.P.Expand(ann, 1, 1, 0)
			end
		end
		local ran, err = pcall(function()
			s.P.Expand(ann, 1, 0, 0)
		end)
		spendDuring = nil
		if not ran then
			error(err)
		end
		t.eq(nested, 1)
		t.eq(profile.plot.squares, { "1,0" })
		t.eq(profile.cash, 9900)
		-- The tap after that still quotes the old count.
		s.P.Expand(ann, 2, 1, 0)
		t.eq(s.lastToast(), "The price changed. The Land panel shows the new one.")
		t.eq(profile.plot.squares, { "1,0" })
		t.eq(profile.cash, 9900)
	end)

	t.test("a friend cannot build until build is ticked, and a stranger with visit off is moved off", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Bench", 0, 0, 0)
		local first = profile.plot.placed[1]
		local annCash = profile.cash
		bob.standOn(1)
		s.P.Place(bob, "Bench", 20, 0, 0)
		t.eq(s.lastToast(), "You can't build on this plot.")
		s.P.Move(bob, first.uid, 10, 0, 0)
		t.eq(s.lastToast(), "You can't build on this plot.")
		t.eq(first.x, 0)
		s.P.Sell(bob, first.uid)
		t.eq(s.lastToast(), "You can't take that apart.")
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, annCash)
		t.eq(bobProfile.cash, 100000)

		profile.permissions = { anyone = { build = true } }
		s.P.Place(bob, "Bench", 20, 0, 0)
		t.eq(#profile.plot.placed, 2)
		t.eq(profile.cash, annCash, "the host does not pay")
		t.eq(bobProfile.cash, 100000 - 80)
		local second = profile.plot.placed[2]
		t.eq(s.itemFolder(1):FindFirstChild(second.uid):GetAttribute("OwnerId"), 1)
		s.P.Move(bob, first.uid, 10, 0, 1)
		t.eq({ first.x, first.z, first.rot }, { 10, 0, 1 })
		s.P.Sell(bob, first.uid)
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, annCash + 80, "the refund goes to the owner")
		t.eq(bobProfile.cash, 100000 - 80)

		profile.permissions = { anyone = { visit = false } }
		local center = s.PlotData.Slots[1]
		bob.standOn(1)
		s.P.VisitStep({ bob, ann })
		t.eq(bob.root.Position.X, center.X)
		t.eq(bob.root.Position.Z, center.Y + 48)
		t.eq(ann.root.Position.X, center.X)
		t.eq(ann.root.Position.Z, center.Y)
	end)

	-- Plot visits: Settings > Visitors lists the people whose plot lets you
	-- in, and PlotService.Visit puts you on a safe spot of their plot.
	local function onPlot(s, spot, i)
		local c = s.PlotData.Slots[i]
		return math.abs(spot.X - c.X) <= 56 and math.abs(spot.Z - c.Y) <= 56
	end

	t.test("a visit lands on the owner's plot, on dry ground off the roads, and costs nothing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		bob.standOn(nil)
		local cash = bobProfile.cash
		t.ok(s.P.Visit(bob, 1))
		t.ok(onPlot(s, bob.root.Position, 1), "inside the plot")
		local PlotLogic = t.shared("PlotLogic")
		t.ok(not PlotLogic.InWater(bob.root.Position.X, bob.root.Position.Z), "not in water")
		t.ok(not PlotLogic.OnRoad(bob.root.Position.X, bob.root.Position.Z), "not on a road")
		t.eq(s.lastToast(), "Visiting Ann's plot.")
		t.eq(bobProfile.cash, cash)
		t.eq(profile.cash, 100000)
		-- The bound remote does the same thing.
		bob.standOn(nil)
		s.remotes.VisitPlot.OnServerEvent.fn(bob, 1)
		t.ok(onPlot(s, bob.root.Position, 1))
	end)

	t.test("a visit is refused: visit off, you in particular, yourself, no plot, junk, or too fast", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		local cat = s.newPlayer(3, "Cat")
		s.newPlayer(4, "Dan") -- in the server with no plot
		s.claim(ann, 1)
		local function away(p)
			p.standOn(nil)
			return p.root.Position
		end
		profile.permissions = { anyone = { visit = false } }
		local start = away(bob)
		t.eq(s.P.Visit(bob, 1), false)
		t.eq(bob.root.Position, start, "nobody moved")
		t.eq(s.lastToast(), "That plot isn't open to visitors.")
		-- One named friend is let in over the closed door.
		profile.permissions = { anyone = { visit = false }, ["3"] = { visit = true } }
		t.ok(s.P.Visit(cat, 1))
		t.eq(s.P.Visit(bob, 1), false)
		-- A stranger turned away by name.
		profile.permissions = { ["2"] = { visit = false } }
		t.eq(s.P.Visit(bob, 1), false)
		profile.permissions = {}
		t.eq(s.P.Visit(ann, 1), false, "not your own plot")
		t.eq(s.P.Visit(bob, 4), false, "Dan has no plot")
		t.eq(s.lastToast(), "That player has no plot to visit right now.")
		t.eq(s.P.Visit(bob, 99), false, "not in the server")
		for _, junk in ipairs({ "1", -1, 0, 1.5, 0 / 0, math.huge, {}, true }) do
			t.eq(s.P.Visit(bob, junk), false, tostring(junk))
		end
		t.eq(bob.root.Position, start)
		t.ok(s.P.Visit(bob, 1), "and a plain visit still works")
	end)

	t.test("a visit is rate limited by the RateLimiter and a visitor with no character goes nowhere", function()
		local s = setup({ rate = false })
		local ann = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		bob.standOn(nil)
		local start = bob.root.Position
		t.eq(s.P.Visit(bob, 1), false)
		t.eq(bob.root.Position, start)
		local s2 = setup()
		local ann2 = s2.newPlayer(1, "Ann")
		local bob2 = s2.newPlayer(2, "Bob")
		s2.claim(ann2, 1)
		bob2.Character = nil
		t.eq(s2.P.Visit(bob2, 1), false)
	end)

	---------------------------------------------------------------------------
	-- Nobody is given a plot: the Land Office sells the first (GameConfig.PlotPrice)
	---------------------------------------------------------------------------

	t.test("the plot price is real, and the picker shows the price the server charges", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		t.ok(s.config.PlotPrice >= 100, "a plot costs real money")
		s.atOffice(ann)
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		local offer = s.P.OfferOf(ann)
		t.eq(offer.price, s.config.PlotPrice)
		s.P.Claim(ann, 2)
		t.eq(profile.cash, 1000 - offer.price, "exactly the shown price")
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(ann.attrs.Picking, nil)
		t.eq(s.questEvents, { "plotClaimed" })
	end)

	t.test("buying with enough cash assigns and charges exactly once, even ten rapid fires", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		for _ = 1, 10 do
			s.P.Claim(ann, 1)
		end
		t.eq(profile.cash, 5000 - s.config.PlotPrice)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(s.questEvents, { "plotClaimed" })
		-- Ten more, naming other pads: still one plot, one charge.
		for i = 2, 11 do
			s.P.Claim(ann, i)
		end
		t.eq(profile.cash, 5000 - s.config.PlotPrice)
		for i = 2, 11 do
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
		end
		t.eq(s.lastToast(), "You already have a plot here.")
	end)

	t.test("a fire that lands while the charge is going through cannot buy a second plot", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		local again = 0
		-- The purse call is the one place the claim could be re-entered.
		s.spendDuring(function()
			again += 1
			s.P.Claim(ann, 2)
		end)
		s.P.Claim(ann, 1)
		s.spendDuring(nil)
		t.eq(again, 1)
		t.eq(profile.cash, 5000 - s.config.PlotPrice)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
	end)

	t.test("too little cash refuses, charges nothing and says how much is missing", function()
		local s = setup({ cash = 100 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 100)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(profile.plot.claimed, false)
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		t.eq(s.lastToast(), string.format("You need $%d more for a plot.", s.config.PlotPrice - 100))
		t.eq(s.questEvents, {})
		-- One dollar short is still short; the exact price is enough.
		profile.cash = s.config.PlotPrice - 1
		s.P.Claim(ann, 1)
		t.eq(s.lastToast(), "You need $1 more for a plot.")
		t.eq(ann.attrs.PlotSlot, nil)
		profile.cash = s.config.PlotPrice
		s.P.Claim(ann, 1)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(profile.cash, 0)
	end)

	t.test("out of range of the Land Office refuses with nothing charged", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		ann.standOn(nil)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 5000)
		t.eq(ann.attrs.PlotSlot, nil)
		-- Standing on a plot's own sign is not the Land Office either.
		ann.standAtSign(1)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 5000)
		t.eq(ann.attrs.PlotSlot, nil)
	end)

	t.test("an owner cannot buy twice, and a junk index buys nothing", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		for _, junk in ipairs({ "1", 0, -1, 1.5, 0 / 0, math.huge, {}, true, 9999 }) do
			s.P.Claim(ann, junk)
			t.eq(profile.cash, 5000, tostring(junk))
			t.eq(ann.attrs.PlotSlot, nil)
		end
		s.P.Claim(ann, 3)
		local after = profile.cash
		s.prompt.Triggered.fn(ann)
		t.eq(s.lastToast(), "You already have a plot. Plots are bought here, one each.")
		s.P.Claim(ann, 4)
		t.eq(profile.cash, after)
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(s.plot(4):GetAttribute("OwnerId"), nil)
	end)

	t.test("a taken pad refuses before any charge", function()
		local s = setup({ cash = 5000 })
		local ann = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 3)
		s.atOffice(bob)
		s.P.Claim(bob, 3)
		t.eq(bobProfile.cash, 5000)
		t.eq(bob.attrs.PlotSlot, nil)
		t.eq(s.lastToast(), "Someone else claimed that plot. Pick another.")
	end)

	t.test("the claim is rate limited", function()
		local s = setup({ cash = 5000, rate = false })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 5000)
		t.eq(ann.attrs.PlotSlot, nil)
	end)

	t.test("no free plot at join or on a timeout, for a save that never bought one", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(ann.attrs.Picking, nil, "no picker at join")
		t.eq(s.P.OfferOf(ann), nil)
		s.advance(600)
		s.P.Sweep()
		s.P.Pass(ann)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(profile.plot.claimed, false)
		for i = 1, #s.PlotData.Slots do
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
		end
		-- The Land Office's picker has no timer and Close hands nothing out.
		s.atOffice(ann)
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		s.advance(600)
		s.P.Sweep()
		t.eq(ann.attrs.PlotSlot, nil)
		s.P.Pass(ann)
		t.eq(ann.attrs.Picking, nil)
		t.eq(ann.attrs.PlotSlot, nil, "closing the picker is not a free plot")
		t.eq(profile.cash, 100000)
	end)

	t.test("returning players are unaffected: their pad comes back free, saved layout and all", function()
		local s = setup({ cash = 40 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = { { uid = "a", blueprintId = "Bench", x = 4, z = 4, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.Picking, true)
		t.eq(s.P.OfferOf(ann).price, 0)
		-- Even broke and far from the office, they pick a pad from the join picker.
		ann.standOn(nil)
		s.P.Claim(ann, 2)
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(profile.cash, 40, "nothing charged")
		t.eq(#s.items(2), 1)
	end)

	t.test("a returning owner is never charged, at the Land Office either", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		s.atOffice(ann)
		s.P.Claim(ann, 4)
		t.eq(ann.attrs.PlotSlot, 4)
		t.eq(profile.cash, 5000)
	end)

	t.test("another save that never bought a plot does not inherit the pad", function()
		local s = setup()
		local ann = s.newPlayer(1, "Ann")
		s.claim(ann, 5)
		local fresh = { plot = { claimed = false, tier = 1, placed = {} } }
		t.eq(s.P.Reload(ann, fresh), false)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(s.plot(5):GetAttribute("OwnerId"), nil)
	end)

	t.test("a purchase that fails to build the plot is refunded and the pad stays free", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.placed = { { uid = "x", blueprintId = "Bench", x = 1, z = 1, rot = 0 } }
		s.atOffice(ann)
		s.explodeOnBuild(true)
		local ok = pcall(s.P.Claim, ann, 1)
		s.explodeOnBuild(false)
		t.eq(ok, false)
		t.eq(profile.cash, 1000, "refunded")
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		t.eq(ann.attrs.PlotSlot, nil)
	end)
	---------------------------------------------------------------------------
	-- Old Hank, the plot salesman: his Talk prompt runs the same purchase flow
	---------------------------------------------------------------------------

	-- NPCService builds him after PlotService.Init; fake just his Talk prompt.
	local function withHank(s)
		local Instance = fakeInstances()
		local map = Instance.new("Folder")
		local folder = Instance.new("Folder")
		folder.Name = "Townsfolk"
		folder.Parent = map
		local hank = Instance.new("Model")
		hank.Name = "OldHank"
		hank.Parent = folder
		local talk = Instance.new("ProximityPrompt")
		talk.Name = "Talk"
		talk.Parent = hank
		s.P.HookSalesman(map)
		return talk
	end

	t.test("talking to Old Hank at the counter opens the same picker, with the server's price", function()
		local s = setup({ cash = 1000 })
		local talk = withHank(s)
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		talk.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		t.eq(s.P.OfferOf(ann).price, s.config.PlotPrice)
		t.eq(profile.cash, 1000, "talking charges nothing")
		s.P.Claim(ann, 3)
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(profile.cash, 1000 - s.config.PlotPrice, "charged once, at the one price")
	end)

	t.test("Old Hank from across the map opens nothing; an owner is told so, nothing opens", function()
		local s = setup({ cash = 1000 })
		local talk = withHank(s)
		local ann, profile = s.newPlayer(1, "Ann")
		ann.standOn(nil)
		talk.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, nil)
		t.eq(profile.cash, 1000)
		s.claim(ann, 1)
		local cash = profile.cash
		s.atOffice(ann)
		talk.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, nil)
		t.eq(s.lastToast(), t.shared("PlotSalesmanData").OwnsLine)
		t.eq(profile.cash, cash)
	end)

	t.test("the counter's own Buy a plot prompt still works beside Old Hank", function()
		local s = setup({ cash = 1000 })
		withHank(s)
		local ann = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		t.eq(s.prompt.ActionText, "Buy a plot")
	end)
end
