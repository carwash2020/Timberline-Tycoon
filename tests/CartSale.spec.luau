--!nocheck
-- S3: a v1 cart sale that takes no logs must not use up the cart.
-- GameServer's SellLogs handler runs here, on loop 1, with the map's cart
-- zone and the services that sale touches stubbed.
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame

	local function signal()
		local s = {}
		function s:Connect()
			return { Disconnect = function() end }
		end
		return s
	end

	t.test("S3: a v1 cart sale that takes nothing does not use the cart; a real log does", function()
		local TutorialData = t.shared("TutorialData")
		local Schema = t.server("ProfileSchema")
		local sellAt = 1
		for i, step in ipairs(TutorialData.Steps) do
			if step.id == "sell" then
				sellAt = i
			end
		end
		local profile = t.shared("Util").deepCopy(Schema.Template)
		profile.cash = 20
		profile.tutorialDone = false
		profile.tutorialStep = sellAt
		profile.cartUsed = false
		profile.stats.logsSold = 0

		local ws = Instance.new("Folder")
		ws.Name = "Workspace"
		ws:SetAttribute("CoreLoopActive", 1)
		local map = Instance.new("Folder")
		map.Name = "TimberlineMap"
		map.Parent = ws
		local sellArea = Instance.new("Folder")
		sellArea.Name = "SellArea"
		sellArea.Parent = map
		local sellZone = Instance.new("Part")
		sellZone.Name = "SellZone"
		sellZone.Size = Vector3.new(10, 10, 10)
		sellZone.CFrame = CFrame.new(100, 5, 100)
		sellZone.Parent = sellArea
		local grove = Instance.new("Folder")
		grove.Name = "TutorialGrove"
		grove.Parent = map
		local cart = Instance.new("Part")
		cart.Name = "CartZone"
		cart.Size = Vector3.new(20, 20, 20)
		cart.CFrame = CFrame.new(0, 5, 0)
		cart.Parent = grove

		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = CFrame.new(0, 5, 0)
		-- Lune parts don't derive Position from CFrame.
		hrp.Position = Vector3.new(0, 5, 0)
		local character = Instance.new("Model")
		character.Name = "Character"
		humanoid.Parent = character
		hrp.Parent = character
		local player = {
			Name = "Tester",
			UserId = 7,
			Character = character,
		}
		function player:SetAttribute() end
		function player:GetAttribute() end

		local hands = { ghost = true }
		local taken = {}
		local realLog = {
			value = 12,
			def = { id = "oak" },
			tags = {},
			model = {
				Destroy = function()
					table.insert(taken, "destroyed")
				end,
			},
		}
		local giveReal = false
		local noop = function() end
		local handlers = {}

		-- Remotes are plain tables. GameServer parents the folder onto the
		-- loader's ReplicatedStorage node, which is not an Instance, so a
		-- real RemoteEvent would refuse that Parent.
		local function fake(class, parent)
			local inst = { Name = "", ClassName = class, Parent = parent }
			function inst:IsA(wanted)
				return wanted == class or wanted == "Instance"
			end
			if class == "RemoteEvent" then
				inst.OnServerEvent = {
					Connect = function(_, fn)
						handlers[inst.Name] = fn
						return { Disconnect = noop }
					end,
				}
				function inst:FireClient() end
			end
			return inst
		end

		local New = Instance.new
		local InstanceWrap = setmetatable({
			new = function(class, parent)
				if class == "RemoteEvent" or class == "Folder" then
					return fake(class, parent)
				end
				return New(class, parent)
			end,
		}, { __index = Instance })

		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
					LoadProfile = function()
						return nil, "left"
					end,
					ReleaseProfile = noop,
				},
				CarryService = {
					Hands = function()
						return hands
					end,
					Start = noop,
					Stop = noop,
				},
				TreeService = {
					TakeLog = function(uid)
						if not giveReal then
							return nil
						end
						table.insert(taken, uid)
						return realLog
					end,
					DropLog = noop,
					TakeLeftBehind = function()
						return {}
					end,
				},
				QuestService = { Init = noop, Event = noop, Start = noop, WoodSold = noop, RefreshNextGoal = noop },
				DailyService = { Init = noop, Event = noop, Start = noop, WoodSold = noop },
				MilestoneService = {
					Init = noop,
					Mark = noop,
					CashEarned = noop,
					LogsSold = noop,
					WoodSold = noop,
				},
				MonetizationService = {
					Init = noop,
					SetPassListener = noop,
					SaleMultiplier = function()
						return 1
					end,
					LogMultiplier = function()
						return 1
					end,
					HasPass = function()
						return false
					end,
					PlayerRemoving = noop,
				},
				ForestService = { Init = noop, OnSale = noop, PlayerJoined = noop, PlayerRemoving = noop },
				-- Pulls in vendored ProfileStore, which connects Heartbeat at require.
				PlaceCheck = { Run = noop },
				EconomyService = {
					Init = noop,
					AddCash = function(_, amount)
						local credited = math.floor(amount)
						profile.cash += credited
						return credited, 0
					end,
					PayPending = noop,
					AddOwedCash = function()
						return 0, 0
					end,
				},
			},
			services = {
				Players = {
					PlayerAdded = signal(),
					PlayerRemoving = signal(),
					GetPlayers = function()
						return {}
					end,
				},
			},
			globals = {
				workspace = ws,
				Instance = InstanceWrap,
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		-- GameServer requires every service at boot. Idle stand-ins skip their
		-- real Init (trucks, plots, the forest). A blank GetService stand-in
		-- covers chat, physics, and storage, which those modules ask for
		-- even when this sale never calls them.
		local function idle()
			return setmetatable({ Hooks = {} }, {
				__index = function(self, key)
					local fn = function() end
					rawset(self, key, fn)
					return fn
				end,
			})
		end
		for _, name in ipairs({
			"AetherService",
			"AxeService",
			"BiomeService",
			"DevCommands",
			"FieldGuideService",
			"GondolaService",
			"GrabService",
			"LeftLoad",
			"NodeService",
			"NPCService",
			"PaintService",
			"PickupGrace",
			"PlotService",
			"RegionWake",
			"SaveSlotService",
			"SawmillService",
			"SectionTrees",
			"SellService",
			"ShopService",
			"TruckLoad",
			"VehicleService",
			"WeatherService",
			"WoodService",
		}) do
			loader.options.mocks[name] = idle()
		end
		setmetatable(loader.services, {
			__index = function()
				return setmetatable({}, {
					__index = function()
						return function() end
					end,
				})
			end,
		})
		loader:run("ServerScriptService/GameServer.server")
		local sell = handlers.SellLogs
		t.ok(sell, "SellLogs is connected on the v1 loop")

		sell(player)
		t.eq(profile.cartUsed, false, "a sale that took no logs does not use the cart")
		t.eq(profile.cash, 20, "nothing was credited")
		t.eq(profile.stats.logsSold, 0)

		giveReal = true
		hands.oak = true
		sell(player)
		t.eq(profile.cartUsed, true, "a real log uses the cart")
		t.eq(profile.cash, 32, "the log's value was credited")
		t.eq(profile.stats.logsSold, 1)
		t.eq(taken[1], "oak")
	end)
end
