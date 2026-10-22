--!nocheck
-- PipelineE2E (T409): the player story, end to end, on the real server modules and the built world.
--   buy an axe -> chop a tree -> drag the log -> the mill's Intake -> planks past the Output ->
--   sell on the pad -> cash goes up -> a raw log at the town sawmill pays and marks the first sale.
-- No physics: the engine's queries (which parts sit in a box), players and timers are faked, and
-- belts' motion stays a Studio check; every rule between those is the real code (ShopService,
-- EconomyService, SectionTrees, WoodService, GrabService, SawmillService, BeltService,
-- SellService). The Tool Shed counter, the town sell zone and the mill are the built ones (the
-- cached build in tests/support/WorldBuild, the machine from MachineArt). A failing step names
-- itself and the last state reached, e.g. "log at belt end, Intake not found".
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local Clearance = t.load("ReplicatedStorage/Shared/World/Clearance")
	local Geometry = t.load("ReplicatedStorage/Shared/Lint/Geometry")

	-- Which parts of `folder` sit inside the box (the fake of workspace:GetPartBoundsInBox).
	local function partsInBox(cf, size, folder)
		local box = Clearance.Box(cf, size)
		local out = {}
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") and Clearance.BoxDepth(box, Geometry.BoxOf(d)) > 0.01 then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Runs the story once. `options.removeIntake` takes the Intake off the mill and `options.loseAxes` makes the
	-- save forget the axes (the controls).
	-- Returns { ok, step, err, state, ... } and never throws: a spec reads it.
	local function story(options)
		options = options or {}
		local world = t.support("WorldBuild").Get(t)
		local result = { ok = false, step = 0, stepName = "setup", state = "nothing happened yet", cash = {} }
		local s = {
			now = 1000,
			delays = {},
			byId = {},
			toasts = {},
			marks = {},
			quests = {},
			granted = {},
			fx = {},
		}

		local function step(name, fn)
			result.step += 1
			result.stepName = name
			fn()
		end
		local function state(text)
			result.state = text
		end
		local function need(cond, message)
			if not cond then
				error(message, 0)
			end
		end

		local ok, err = pcall(function()
			local workspaceFolder = Instance.new("Folder")
			workspaceFolder.Name = "Workspace"
			local map = Instance.new("Folder")
			map.Name = "TimberlineMap"
			map.Parent = workspaceFolder
			local fakeWorkspace = {
				WaitForChild = function(_, name)
					return if name == "TimberlineMap" then map else nil
				end,
				FindFirstChild = function(_, name)
					return if name == "TimberlineMap" then map else nil
				end,
				-- MapBuilder publishes the loop the server runs; this is the v2 loop.
				GetAttribute = function(_, name)
					return if name == "CoreLoopActive" then 2 else nil
				end,
				GetServerTimeNow = function()
					return s.now
				end,
				Raycast = function()
					return nil
				end,
				GetPartBoundsInBox = function(_, cf, size, params)
					local out = {}
					for _, inst in ipairs(params and params.FilterDescendantsInstances or {}) do
						if typeof(inst) == "Instance" then
							for _, p in ipairs(partsInBox(cf, size, inst)) do
								table.insert(out, p)
							end
						end
					end
					return out
				end,
			}
			local Players = {
				GetPlayers = function()
					local list = {}
					for _, p in pairs(s.byId) do
						table.insert(list, p)
					end
					return list
				end,
				GetPlayerByUserId = function(_, id)
					return s.byId[id]
				end,
			}
			local CollectionService = {
				AddTag = function(_, inst, tag)
					inst:AddTag(tag)
				end,
				HasTag = function(_, inst, tag)
					return inst:HasTag(tag)
				end,
				RemoveTag = function(_, inst, tag)
					inst:RemoveTag(tag)
				end,
				GetTagged = function()
					return {}
				end,
			}
			local params = {
				new = function()
					return {}
				end,
			}

			-- A DataStore in memory behind the real ProfileService and ProfileSchema (the vendored ProfileStore is
			-- the only fake): what a session ends with is what the next session starts from.
			local disk = {}
			local function copy(v)
				if type(v) ~= "table" then
					return v
				end
				local out = {}
				for k, x in pairs(v) do
					out[k] = copy(x)
				end
				return out
			end
			local function signal()
				local listeners = {}
				return {
					Connect = function(_, fn)
						table.insert(listeners, fn)
						return { Disconnect = function() end }
					end,
					Fire = function(_, ...)
						for _, fn in ipairs(listeners) do
							fn(...)
						end
					end,
					Wait = function()
						return nil
					end,
				}
			end
			local template
			local fakeStore = {
				StartSessionAsync = function(_, key)
					local session = {
						Data = copy(disk[key] or {}),
						LastSavedData = {},
						OnSessionEnd = signal(),
						OnLastSave = signal(),
						OnAfterSave = signal(),
						active = true,
					}
					function session:AddUserId() end
					function session:Reconcile()
						for k, v in pairs(template) do
							if self.Data[k] == nil then
								self.Data[k] = copy(v)
							end
						end
					end
					function session:IsActive()
						return self.active
					end
					function session:Save()
						disk[key] = copy(self.Data)
						self.LastSavedData = disk[key]
						self.OnAfterSave:Fire(self.LastSavedData)
					end
					function session:EndSession()
						self.OnLastSave:Fire()
						self:Save()
						self.active = false
					end
					return session
				end,
			}
			s.disk = disk
			local player
			local loader = t.loader({
				services = {
					Players = Players,
					CollectionService = CollectionService,
					PhysicsService = {},
					TextChatService = {},
				},
				mocks = {
					RateLimiter = {
						Allow = function()
							return true
						end,
					},
					ProfileStore = {
						New = function(_, tpl)
							template = tpl
							return fakeStore
						end,
						SetConstant = function() end,
						IsClosing = false,
					},
					GameAnalytics = {
						Economy = function() end,
					},
					MilestoneService = {
						Mark = function(_, name)
							table.insert(s.marks, name)
						end,
						Event = function() end,
						CashEarned = function() end,
						WoodSold = function() end,
					},
					QuestService = {
						Event = function(_, event)
							table.insert(s.quests, event)
						end,
						RefreshNextGoal = function() end,
						WoodSold = function(_, pieces, credited)
							table.insert(s.quests, string.format("woodSold %d pieces $%d", pieces, credited))
						end,
					},
					VehicleService = {},
					BlueprintService = {},
				},
				globals = {
					workspace = fakeWorkspace,
					task = {
						delay = function(seconds, fn, ...)
							table.insert(s.delays, { seconds = seconds, fn = fn, args = table.pack(...) })
						end,
						spawn = function(fn, ...)
							fn(...)
						end,
						wait = function()
							return 0
						end,
					},
					RaycastParams = params,
					OverlapParams = params,
					os = setmetatable({
						clock = function()
							return s.now
						end,
					}, { __index = os }),
				},
			})

			local ProfileService = loader:server("ProfileService")
			local Economy = loader:server("EconomyService")
			local Shop = loader:server("ShopService")
			local Trees = loader:server("SectionTrees")
			local Wood = loader:server("WoodService")
			local Grab = loader:server("GrabService")
			local Sawmill = loader:server("SawmillService")
			local Belts = loader:server("BeltService")
			local Sell = loader:server("SellService")
			local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
			local Catalog = loader:shared("ItemCatalog")
			local ShopLogic = loader:shared("ShopLogic")
			local SellLogic = loader:shared("SellLogic")
			local SectionLogic = loader:shared("SectionLogic")
			local GameConfig = loader:shared("GameConfig")
			local SawmillLogic = loader:shared("SawmillLogic")
			local GrabLogic = loader:shared("GrabLogic")
			s.loader = loader

			Wood.Physics = {
				SetOwner = function()
					return true
				end,
				SetAuto = function() end,
				-- Whoever is dragging a piece owns its physics (WoodWatch judges that owner's moves).
				GetOwner = function()
					return s.dragger
				end,
				Speed = function()
					return 0, 0
				end,
				GetVelocity = function()
					return Vector3.zero, Vector3.zero
				end,
				SetVelocity = function() end,
			}
			-- GameServer's wiring: the grab's pieces are WoodService's records.
			Grab.SetResolver(function(part)
				return Wood.FromPart(part)
			end)
			Grab.JudgeMoves = false
			Grab.Physics.SetOwner = function()
				return true
			end
			Grab.Physics.SetAuto = function() end
			local remote = {
				FireClient = function(_, p, kind, payload)
					table.insert(s.fx, { player = p, kind = kind, payload = payload })
				end,
			}
			local equipped = nil
			Wood.Init({
				worldFx = remote,
				manual = true,
				clock = function()
					return s.now
				end,
			})
			Trees.Init({
				notify = function(p, message)
					table.insert(s.toasts, message)
				end,
				worldFx = remote,
				getAxe = function()
					return if equipped then Catalog.GetAxe(equipped) else nil
				end,
				canChop = function()
					return true, nil
				end,
				swingDue = function()
					return 0
				end,
				setSwingDue = function() end,
				clock = function()
					return s.now
				end,
				manual = true,
			})
			-- The player, standing at the built Tool Shed counter's customer side.
			local counter = world.map.ToolShed.Counter
			local shopPoint = counter.CFrame * Vector3.new(0, 0, -(counter.Size.Z / 2 + 0.5))
			local root = {
				Position = shopPoint,
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
			local humanoid = {
				Health = 100,
				SeatPart = nil,
				EquipTool = function() end,
			}
			local character = {
				FindFirstChild = function(_, name)
					return if name == "HumanoidRootPart" then root else nil
				end,
				FindFirstChildOfClass = function(_, class)
					return if class == "Humanoid" then humanoid else nil
				end,
			}
			local function newPlayer()
				local p = {
					UserId = 1,
					Name = "Tester",
					DisplayName = "Tester",
					Character = character,
					Parent = Players,
					SetAttribute = function() end,
					-- (a Backpack-less player: AxeService keeps the axe in the save and hands the tool over later)
					FindFirstChildOfClass = function()
						return nil
					end,
					FindFirstChild = function()
						return nil
					end,
				}
				p.root = root
				s.byId[1] = p
				return p
			end
			player = newPlayer()
			local profile = ProfileService.LoadProfile(player)
			need(profile ~= nil, "the first join did not load a save")
			Economy.AddCash(player, 500, "test: the starting purse", "test")

			----------------------------------------------------------------------------------------
			step("buy the starter axe at the Tool Shed", function()
				local ladder = Catalog.AxeLadder()
				local axe = ladder[2]
				need(
					axe and axe.id == "SteelAxe",
					"the first axe to buy is no longer the Steel Axe: " .. tostring(axe and axe.id)
				)
				local price = ShopLogic.Price(axe, 2)
				-- ShopService reads each ShopPoint's WorldPosition (Lune has no such property), so the shop
				-- map hands it the built counter's customer-side point.
				local point = {
					WorldPosition = shopPoint,
					IsA = function(_, class)
						return class == "Attachment"
					end,
				}
				local shop = {
					FindFirstChild = function(_, name)
						if name == "ToolShed" then
							return {
								FindFirstChild = function(_, n)
									return if n == "Counter"
										then {
											FindFirstChild = function(_, p)
												return if p == "ShopPoint" then point else nil
											end,
										}
										else nil
								end,
							}
						end
						return nil
					end,
				}
				local handler
				Shop.Hour = function()
					return 12
				end
				Shop.Init(shop, {
					OnServerEvent = {
						Connect = function(_, fn)
							handler = fn
						end,
					},
				}, { OnServerEvent = { Connect = function() end } }, function(_, message)
					table.insert(s.toasts, message)
				end, 2)
				local before = Economy.GetCash(player)
				state(string.format("at the counter with $%d, the %s costs $%d", before, axe.id, price))
				handler(player, "Axe", axe.id)
				local after = Economy.GetCash(player)
				need(
					after == before - price,
					string.format(
						"buying the %s: cash went %d -> %d, expected exactly -%d (toast: %s)",
						axe.id,
						before,
						after,
						price,
						tostring(s.toasts[#s.toasts])
					)
				)
				local mine = profile.axes[#profile.axes]
				need(mine ~= nil and mine.id == axe.id, "the shop did not put the " .. axe.id .. " in the save")
				need(profile.bestAxeTier >= 2, "buying the axe did not raise bestAxeTier")
				equipped = mine.id
				result.axeUid = mine.uid
				result.axe = axe.id
				result.axePrice = price
				state(string.format("bought the %s for $%d, cash $%d", axe.id, price, after))
			end)

			----------------------------------------------------------------------------------------
			local tree, piece
			step("chop a common tree with that axe", function()
				local axeDef = Catalog.GetAxe(equipped)
				need(axeDef ~= nil, "no equipped axe")
				local model = Trees.SpawnTree("oak", CFrame.new(Vector3.new(0, 0, 400)), {
					seed = 7,
					size = loader:shared("TreeLogic").Sizes[2],
					stage = 1,
				})
				tree = Trees.GetTree(model:GetAttribute("Uid"))
				need(tree ~= nil, "the oak did not spawn")
				root.Position = Vector3.new(4, 3, 400)
				local base = tree.sections[1]
				local swings = 0
				local freed
				repeat
					swings += 1
					s.now += 0.7
					local hit, normal = SectionLogic.AimAt(base.CFrame, base.Size, root.Position, nil, nil)
					local accepted, why, outcome = Trees.Chop(player, base, hit, normal)
					need(accepted, "swing " .. swings .. " refused: " .. tostring(why))
					freed = outcome and outcome.freed[1]
				until freed or swings >= 120
				state(string.format("%d swings with the %s", swings, equipped))
				need(freed, "the tree never came down in 120 swings")
				piece = freed
				need(piece.volume and piece.volume > 0, "the felled log has no volume")
				need(piece.ownerId == 1, "the log is not the cutter's")
				result.swings = swings
				result.logVolume = piece.volume
				state(string.format("log %s of oak, %.3f u3, felled in %d swings", piece.uid, piece.volume, swings))
			end)

			----------------------------------------------------------------------------------------
			step("limb the log straight", function()
				-- The felled tree still has its limbs, and a mill takes only a straight log: cut the
				-- trunk through just under the limbs (the same Chop remote, on the loose piece), so the
				-- limbs fall away as their own piece and a straight length stays.
				local cuts = 0
				local fork, forkPart
				for id, part in pairs(piece.parts) do
					local node = piece.nodes[id]
					if node and #node.children > 1 then
						fork, forkPart = id, part
					end
				end
				need(forkPart ~= nil, "the felled oak has no fork to cut under")
				root.Position = forkPart.CFrame.Position + Vector3.new(0, 0, 2.5)
				local through = false
				for _ = 1, 160 do
					s.now += 0.7
					local hit, normal = SectionLogic.AimAt(forkPart.CFrame, forkPart.Size, root.Position, nil, nil)
					local accepted, why, outcome = Trees.Chop(player, forkPart, hit, normal)
					need(accepted, "a swing under the limbs was refused: " .. tostring(why))
					cuts += 1
					if outcome and #outcome.freed > 0 then
						through = true
						break
					end
				end
				need(through, "the trunk never came through under the limbs")
				local sections = 0
				for _ in pairs(piece.parts) do
					sections += 1
				end
				state(
					string.format(
						"log limbed straight in %d swings: %d sections, %.3f u3",
						cuts,
						sections,
						piece.volume
					)
				)
				need(piece.volume > 0, "limbing left no volume")
				result.logVolume = piece.volume
			end)

			----------------------------------------------------------------------------------------
			step("drag the log: grab reach", function()
				local section = piece.model.PrimaryPart
				local hit = section.CFrame.Position
				need(GameConfig.GrabRange == 26, "GrabRange moved from 26: " .. tostring(GameConfig.GrabRange))
				-- 12 studs away: held. Past GrabRange + the tolerance: refused ("far").
				s.now += GameConfig.PickupGraceSec + 1
				root.Position = hit + Vector3.new(12, 0, 0)
				local held, why = Grab.Grab(player, section, hit)
				need(held, "a grab from 12 studs was refused: " .. tostring(why))
				need(Grab.Holding(player) == piece.model, "the log is not held after the grab")
				Grab.Release(player, section)
				root.Position = hit + Vector3.new(GameConfig.GrabRange + GameConfig.RangeTolerance + 1, 0, 0)
				local farHeld, farWhy = Grab.Grab(player, section, hit)
				need(not farHeld and farWhy == "far", "a grab from beyond reach was not refused: " .. tostring(farWhy))
				need(GrabLogic.ClampHold(99) == GameConfig.HoldMax, "a hold is not kept to HoldMax")
				need(GrabLogic.ClampHold(-5) == GameConfig.HoldMin, "a hold is not kept to HoldMin")
				state("grab at 12 studs held; grab past reach refused (far); hold distance clamped")
			end)

			----------------------------------------------------------------------------------------
			local mill, plot
			step("log reaches the mill Intake", function()
				plot = Instance.new("Folder")
				plot.Name = "Plot"
				plot.Parent = map
				mill = MachineArt.Build("SawmillRickety", false)
				need(mill ~= nil, "the starter mill did not build")
				mill:PivotTo(CFrame.new(Vector3.new(300, 5, 0)))
				mill.Parent = plot
				mill:SetAttribute("OwnerId", 1)
				local intake = mill:FindFirstChild("Intake")
				if options.removeIntake and intake then
					intake:Destroy()
					intake = nil
				end
				state("log dragged to the mill's belt end")
				need(intake and intake:IsA("BasePart"), "log at belt end, Intake not found")
				-- The drag: the player holds the log and walks it to the Intake box at 40 studs a
				-- second, WoodWatch judging each step (a teleport would be put back).
				s.dragger = player
				local target = intake.CFrame
				local guard = 0
				while (piece.model:GetPivot().Position - target.Position).Magnitude > 0.5 and guard < 100 do
					guard += 1
					s.now += 1
					local here = piece.model:GetPivot()
					local togo = target.Position - here.Position
					local hop = math.min(togo.Magnitude, 40)
					piece.model:PivotTo(
						CFrame.fromMatrix(
							here.Position + togo.Unit * hop,
							target.XVector,
							target.YVector,
							target.ZVector
						)
					)
					Wood.Watch(s.now)
					need(
						piece.verdictOk,
						string.format(
							"WoodWatch put the log back after hop %d (%s)",
							guard,
							tostring(piece.putBackUntil)
						)
					)
				end
				s.dragger = nil
				Wood.Watch(s.now)
				piece.model:PivotTo(target)
				state(string.format("log dragged %d hops to the Intake box", guard))
				local clock = s.now
				Sawmill._use({
					notify = function(_, message)
						table.insert(s.toasts, message)
					end,
					now = function()
						return clock
					end,
					partsIn = function(box)
						local got = partsInBox(box.CFrame, box.Size, Wood.Folder())
						return got
					end,
					mills = function()
						return { mill }
					end,
					online = function()
						return true
					end,
				})
				Sawmill.Tick()
				need(not piece.selling, "the log was taken before it rested")
				clock += Sawmill.Settle + 0.1
				Sawmill.Tick()
				state(string.format("log in the Intake box, selling=%s", tostring(piece.selling)))
				need(piece.selling == true, "log in the Intake but the mill did not take it")
				-- The cut runs; planks come out one by one.
				local before = {}
				for uid in pairs(Wood.All()) do
					before[uid] = true
				end
				clock += SawmillLogic.ProcessSeconds(piece.volume) + 0.1
				for _ = 1, 40 do
					Sawmill.Tick()
					clock += Sawmill.PlankGap
				end
				local planks = {}
				for uid, p in pairs(Wood.All()) do
					if not before[uid] and p.kind == "plank" then
						table.insert(planks, p)
					end
				end
				need(#planks > 0, "the mill took the log but no plank came out")
				local total = 0
				for _, p in ipairs(planks) do
					total += p.volume
				end
				local expected = piece.volume * GameConfig.PlankYield
				state(string.format("%d planks, %.4f u3 out of %.4f u3 in", #planks, total, piece.volume))
				need(
					math.abs(total - expected) < 1e-3 * math.max(1, expected),
					string.format(
						"planks add up to %.4f u3, expected the log's %.4f x %.2f = %.4f",
						total,
						piece.volume,
						GameConfig.PlankYield,
						expected
					)
				)
				-- Past the Output, not inside the mill's walls.
				local output = mill:FindFirstChild("Output", true)
				need(output ~= nil, "planks came out but the mill has no Output")
				local out = output.Parent.CFrame * output.CFrame
				local walls = {}
				for _, d in ipairs(mill:GetDescendants()) do
					if d:IsA("BasePart") and d.CanCollide and d.Name ~= "Conveyor" then
						table.insert(walls, d)
					end
				end
				for _, p in ipairs(planks) do
					local at = p.root.CFrame.Position
					local ahead = (at - out.Position):Dot(out.LookVector)
					need(
						ahead > 0.5,
						string.format("a plank is %.2f studs along the outfeed, not past the Output", ahead)
					)
					local box = Clearance.Box(p.root.CFrame, p.root.Size)
					for _, wall in ipairs(walls) do
						need(
							Clearance.BoxDepth(box, Geometry.BoxOf(wall)) <= 0.05,
							string.format("a plank spawned inside the mill's %s", wall.Name)
						)
					end
				end
				result.planks = planks
				result.mill = mill
				result.out = out
			end)

			----------------------------------------------------------------------------------------
			step("step BeltService: the belt carries planks away from the Output", function()
				local belt = MachineArt.BuildBelt("ConveyorStraight", false)
				need(belt ~= nil, "the belt did not build")
				belt:PivotTo(
					CFrame.lookAt(
						result.out.Position + result.out.LookVector * 6,
						result.out.Position + result.out.LookVector * 12
					)
				)
				belt.Parent = plot
				belt:SetAttribute("OwnerId", 1)
				Belts._use({
					belts = function()
						return { belt }
					end,
					online = function()
						return true
					end,
					outputs = function()
						return 0
					end,
				})
				local running = Belts.Tick()
				need(running == 1, "BeltService.Tick ran " .. running .. " belts, expected 1")
				local band
				for _, d in ipairs(belt:GetDescendants()) do
					if d.Name == "Conveyor" and d:IsA("BasePart") then
						band = d
					end
				end
				need(band ~= nil, "the belt has no Conveyor part")
				need(
					band.AssemblyLinearVelocity.Magnitude > 0.1
						and band.AssemblyLinearVelocity.Unit:Dot(result.out.LookVector) > 0.9,
					"the belt does not carry planks away from the Output"
				)
				state("belt running, carrying planks away from the Output")
			end)

			----------------------------------------------------------------------------------------
			step("sell the planks on the pad", function()
				local zone = world.map.SellArea.SellZone
				local sold = {}
				Sell._use({
					zone = zone,
					woodFolder = Wood.Folder(),
					resolve = function(model)
						return Wood.FromModel(model)
					end,
					addCash = function(p, amount, reason, sku)
						return (Economy.AddCash(p, amount, reason, sku))
					end,
					saleMultiplier = function()
						return 1
					end,
					notify = function(_, message)
						table.insert(s.toasts, message)
					end,
					release = function(model)
						Grab.ReleasePiece(model)
					end,
					forget = function(model)
						Wood.Forget(model)
						Grab.Unregister(model)
					end,
					onSold = function(sale)
						-- GameServer's onWoodSold, in the order it tells the others.
						table.insert(sold, sale)
						loader:server("MilestoneService").Mark(sale.payee, "First sale")
						loader:server("QuestService").WoodSold(sale.payee, sale.pieces, sale.credited)
					end,
					partsInZone = function(z, folder)
						return partsInBox(z.CFrame, z.Size, folder)
					end,
					now = function()
						return s.now
					end,
					player = function(id)
						return s.byId[id]
					end,
				})
				local expected = 0
				local pieces = 0
				for _, p in ipairs(result.planks) do
					need(not p.dead, "a plank was already gone before the sale")
					p.model:PivotTo(zone.CFrame)
					expected += SellLogic.PieceValue(
						p.woodId,
						"plank",
						p.volume,
						p.figure,
						p.boost,
						p.lux,
						nil,
						nil,
						nil
					)
					pieces += 1
				end
				local before = Economy.GetCash(player)
				Sell.Tick()
				s.now += Sell.Settle + 0.1
				local sales = Sell.Tick()
				state(string.format("%d planks on the pad, %d sale(s)", pieces, #sales))
				need(#sales == 1, "expected one sale, got " .. #sales)
				local gained = Economy.GetCash(player) - before
				local wanted = SellLogic.Payout(expected, 1)
				need(
					gained == wanted,
					string.format(
						"selling %d planks: cash rose by $%d, SellLogic.PieceValue says $%d",
						pieces,
						gained,
						wanted
					)
				)
				need(sales[1].pieces == pieces, "sold " .. sales[1].pieces .. " pieces, expected " .. pieces)
				-- Nothing sells twice.
				local again = Sell.Tick()
				s.now += 5
				again = #again + #Sell.Tick()
				need(again == 0 and Economy.GetCash(player) == before + gained, "a sold plank paid again")
				result.planksSold = gained
				state(string.format("planks sold for $%d, cash $%d", gained, Economy.GetCash(player)))
			end)

			----------------------------------------------------------------------------------------
			step("a raw log at the town sawmill pays and marks the first sale", function()
				local zone = world.map.SellArea.SellZone
				local model = Trees.SpawnTree("oak", CFrame.new(Vector3.new(0, 0, 440)), {
					seed = 9,
					size = loader:shared("TreeLogic").Sizes[2],
					stage = 1,
				})
				local rec = Trees.GetTree(model:GetAttribute("Uid"))
				root.Position = Vector3.new(4, 3, 440)
				local base = rec.sections[1]
				local freed
				for _ = 1, 120 do
					s.now += 0.7
					local hit, normal = SectionLogic.AimAt(base.CFrame, base.Size, root.Position, nil, nil)
					local accepted, _, outcome = Trees.Chop(player, base, hit, normal)
					freed = outcome and outcome.freed[1]
					if freed or not accepted then
						break
					end
				end
				need(freed, "the second tree never came down")
				freed.model:PivotTo(zone.CFrame)
				local expected = SellLogic.PieceValue(
					freed.woodId,
					"log",
					freed.volume,
					freed.figure,
					freed.boost,
					freed.lux,
					nil,
					nil,
					nil
				)
				local before = Economy.GetCash(player)
				local marksBefore = #s.marks
				Sell.Tick()
				s.now += Sell.Settle + 0.1
				local sales = Sell.Tick()
				need(#sales == 1, "the raw log did not sell at the town sawmill pad (" .. #sales .. " sales)")
				local gained = Economy.GetCash(player) - before
				need(
					gained == SellLogic.Payout(expected, 1),
					string.format("raw log paid $%d, expected $%d", gained, SellLogic.Payout(expected, 1))
				)
				need(
					s.marks[#s.marks] == "First sale" and #s.marks == marksBefore + 1,
					"the first-sale step was not marked"
				)
				need(
					table.find(s.quests, string.format("woodSold %d pieces $%d", 1, gained)) ~= nil,
					"the tutorial's sell step did not hear of the sale"
				)
				result.logSold = gained
				state(string.format("raw log sold for $%d, first sale marked", gained))
			end)

			----------------------------------------------------------------------------------------
			step("save, rejoin: cash and the axe read back", function()
				local cash = Economy.GetCash(player)
				local earned = profile.totalEarned
				local axes = {}
				for _, item in ipairs(profile.axes) do
					table.insert(axes, item.uid .. ":" .. item.id)
				end
				local tier = profile.bestAxeTier
				state(string.format("leaving with $%d and %d axe(s)", cash, #axes))
				-- The leave: the final save, the session ends. Then the same account joins again.
				ProfileService.ReleaseProfile(player)
				s.byId[1] = nil
				need(s.disk.profile_1 ~= nil, "leaving wrote nothing to the DataStore")
				if options.loseAxes then
					s.disk.profile_1.axes = {} -- the control: a save that dropped the axes
				end
				need(
					s.disk.profile_1.cash == cash,
					string.format("the save holds $%s, the player had $%d", tostring(s.disk.profile_1.cash), cash)
				)
				local second = newPlayer()
				local again, why = ProfileService.LoadProfile(second)
				need(again ~= nil, "the rejoin did not load the save: " .. tostring(why))
				need(again ~= profile, "the rejoin handed back the old table, not a fresh load of the save")
				need(again.cash == cash, string.format("rejoined with $%d, left with $%d", again.cash, cash))
				need(again.totalEarned == earned, "totalEarned did not survive the rejoin")
				need(again.bestAxeTier == tier, "bestAxeTier did not survive the rejoin")
				local back = {}
				for _, item in ipairs(again.axes) do
					table.insert(back, item.uid .. ":" .. item.id)
				end
				need(
					table.concat(back, ",") == table.concat(axes, ","),
					"the axes after the rejoin: " .. table.concat(back, ",") .. ", before: " .. table.concat(axes, ",")
				)
				need(
					table.concat(back, ","):find(result.axeUid, 1, true) ~= nil,
					"the bought axe is not in the rejoined save"
				)
				state(string.format("rejoined with $%d and the same axes", again.cash))
			end)
		end)

		result.ok = ok
		if not ok then
			result.err = tostring(err)
		end
		return result
	end

	t.test("the player story: buy an axe, chop, drag, mill, sell, cash goes up", function()
		local r = story()
		if not r.ok then
			error(
				string.format(
					"PipelineE2E step %d (%s) failed: %s | last state: %s",
					r.step,
					r.stepName,
					r.err,
					r.state
				),
				0
			)
		end
		t.eq(r.step, 9)
		t.ok(r.planksSold > 0 and r.logSold > 0)
	end)

	t.test(
		"a mill without its Intake fails at the log-to-Intake step, naming it, not later and not with a nil error",
		function()
			local r = story({ removeIntake = true })
			t.eq(r.ok, false)
			t.eq(r.stepName, "log reaches the mill Intake")
			t.eq(r.step, 5)
			t.eq(r.err, "log at belt end, Intake not found")
			t.ok(string.find(r.state, "log dragged to the mill's belt end", 1, true), r.state)
		end
	)

	t.test("a save that forgets the axe fails at the rejoin step, naming what came back", function()
		local r = story({ loseAxes = true })
		t.eq(r.ok, false)
		t.eq(r.step, 9)
		t.eq(r.stepName, "save, rejoin: cash and the axe read back")
		t.ok(
			string.find(r.err, "the axes after the rejoin: ", 1, true) and string.find(r.err, "SteelAxe", 1, true),
			r.err
		)
	end)
end
