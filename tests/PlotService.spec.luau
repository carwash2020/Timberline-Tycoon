--!nocheck
-- Plots on the server: claiming, placing, moving, selling back, growing,
-- and rebuilding a saved layout on whichever slot you get.
return function(t)
	local Vector2, Vector3 = t.roblox.Vector2, t.roblox.Vector3

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
						return true
					end,
				},
				QuestService = {
					Event = function(_player, event)
						table.insert(questEvents, event)
					end,
				},
				EconomyService = {
					SpendCash = function(player, amount)
						local profile = profiles[player]
						if profile.cash < amount then
							return false
						end
						profile.cash -= amount
						return true
					end,
					Refund = function(player, amount)
						profiles[player].cash += amount
						return amount, 0
					end,
				},
				BlueprintModels = {
					Build = function(bp)
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
					SetCut = function(model, x, y)
						model:SetAttribute("CutShown", string.format("%.1f %.1f", x, y))
					end,
				},
			},
		})
		local PlotService = loader:server("PlotService")
		local map = Instance.new("Folder")
		local remotes = {}
		for _, name in ipairs({ "PlaceBlueprint", "MoveBlueprint", "SellPlaced", "UpgradePlot" }) do
			remotes[name] = Instance.new("RemoteEvent")
		end
		PlotService.Init(map, remotes, function(_, message)
			table.insert(toasts, message)
		end)
		local plots = map:FindFirstChild("Plots")

		local function plot(i)
			return plots:FindFirstChild("Plot_" .. i)
		end
		local function claim(player, i)
			local board = plot(i):FindFirstChild("Sign")
			player.root.Position = board.CFrame.Position
			board:FindFirstChild("ProximityPrompt").Triggered.fn(player)
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
			PlotData = PlotData,
			newPlayer = newPlayer,
			plot = plot,
			claim = claim,
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

	t.test("the district has a free plot per slot, each with a claim sign", function()
		local s = setup()
		for i = 1, #s.PlotData.Slots do
			local sign = s.plot(i):FindFirstChild("Sign")
			t.ok(sign:FindFirstChild("ProximityPrompt").Enabled, "plot " .. i .. " can be claimed")
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
		t.ok(not s.plot(3):FindFirstChild("Sign"):FindFirstChild("ProximityPrompt").Enabled)
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
		t.eq(s.plot(1):FindFirstChild("Pad").Size.X, 140)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 2)
		t.eq(s.lastToast(), "You need $9,500 more for a Lumber Yard.")
		profile.plot.tier = #s.PlotData.Tiers
		s.P.Upgrade(ann)
		t.eq(s.lastToast(), "Your plot is as big as it gets.")
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
		t.ok(s.plot(2):FindFirstChild("Sign"):FindFirstChild("ProximityPrompt").Enabled)
		t.eq(#profile.plot.placed, 2, "leaving keeps the save")

		local cara, fresh = s.newPlayer(3, "Cara")
		s.P.PlayerJoined(cara, fresh) -- never claimed: no plot yet
		t.eq(cara.attrs.PlotSlot, nil)
	end)

	t.test("a sawmill from stock places free, and one you don't own is paid for", function()
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
		s.P.Place(ann, "SawmillRickety", 0, 20, 0)
		t.eq(profile.cash, 70)
		t.eq(#profile.plot.placed, 2)
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
		t.eq(s.lastToast(), "Stand on your plot to build.")
	end)

	t.test("claiming only works at the sign", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		ann.standOn(nil)
		s.plot(1):FindFirstChild("Sign"):FindFirstChild("ProximityPrompt").Triggered.fn(ann)
		t.eq(profile.plot.claimed, false)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(s.lastToast(), "Walk up to the sign to claim this plot.")
	end)

	t.test("growing only works while you stand on your plot", function()
		local s = setup({ cash = 3000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(nil)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 1)
		t.eq(profile.cash, 3000)
		t.eq(s.lastToast(), "Stand on your plot to grow it.")
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
		t.eq(s.lastToast(), "Stand on your plot to build.")
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
			s.P.Claim(player, i)
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
		s.P.Claim(ann, 4)
		s.P.Claim(bob, 4)
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
		s.P.Claim(bob, jump)
		t.eq(bob.attrs.PlotSlot, jump)
		t.eq(#s.items(jump), 1)
		t.eq(s.items(jump)[1].Name, "bob")
	end)

	t.test("closing the picker or letting it time out assigns a free plot", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
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
		s.P.PlayerJoined(bob, bobProfile)
		s.P.Pass(bob)
		t.eq(bob.attrs.PlotSlot, 2)
		t.eq(s.lastToast(), s.PlotData.Homes[2].name .. " is yours. You'll wake up here.")
	end)

	t.test("leaving while the picker is open reserves nothing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
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
		s.P.PlayerJoined(ann, profile)
		local offer = s.P.OfferOf(ann)
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
		s.P.Claim(ann, 3)
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
		s.P.Claim(ann, 5)
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

	t.test("a bad saved spot moves onto the delivery pad", function()
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
		s.P.Claim(ann, 1)
		local drop = s.P.GetDeliveryPad(ann)
		t.ok(drop ~= nil)
		local function nearDrop(x, z)
			local p = drop.Position
			return math.abs(x - p.X) < 0.01 and math.abs(z - p.Z) < 0.01
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
		t.eq(s.P.GetDeliveryPad(ann).Position.X, drop.Position.X)
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
		local spawnAt = string.find(server, "VehicleService.SpawnTruck", 1, true)
		t.ok(parkAt ~= nil and spawnAt ~= nil and parkAt < spawnAt, "the lot pass runs before the truck spawns")
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
		s.P.Claim(ann, 2)
		t.eq(#s.items(2), 2)
		s.P.PlayerRemoving(ann)
		t.eq(#s.items(2), 0, "the old pad is clear")
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		s.P.PlayerJoined(ann, profile)
		s.P.Claim(ann, 5)
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
		s.P.Claim(ann, 1.5)
		s.P.Claim(ann, 0)
		s.P.Claim(ann, #s.PlotData.Slots + 1)
		s.P.Claim(ann, "nope")
		t.eq(ann.attrs.PlotSlot, nil)
		s.P.Claim(ann, 2)
		s.P.Claim(ann, 3)
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(s.plot(3):GetAttribute("OwnerId"), nil)
		t.eq(s.lastToast(), "You already have a plot here.")
	end)
end
