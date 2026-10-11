--!nocheck
-- A full save has to stay under 1 MB. The DataStore value limit is 4 MB,
-- and V2 building must not be able to grow plot.placed until a save no
-- longer fits. The live profile is the slot you're playing, and all three
-- slots are stored beside it, so a full base is encoded four times.
return function(t)
	local GameConfig = t.shared("GameConfig")
	local SaveSlotLogic = t.shared("SaveSlotLogic")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")
	local WireLogic = t.shared("WireLogic")
	local DailyData = t.shared("DailyData")
	local PlotData = t.shared("PlotData")
	local FurnitureData = t.shared("FurnitureData")
	local PaidItems = t.shared("PaidItems")
	local serde = require("@lune/serde")

	local MB = 1024 * 1024
	local WOODS = {
		"oak",
		"birch",
		"pine",
		"maple",
		"palmwood",
		"frostwood",
		"emberwood",
		"phantomwood",
		"lumenwood",
		"lanternwood",
	}
	-- Lane M and Lane E have not added these keys yet. The bytes are reserved
	-- so mining and the Sawmill Foreman can land without blowing the budget.
	local ORES = { "Stone", "IronOre", "Resin", "EmberGlass", "SkyShard", "CopperOre", "Coal", "Crystal" }

	local function guid(n: number): string
		return string.format("%08d-4000-8000-8000-%012d", n, n)
	end

	local function section(n: number): { number }
		return { 1.234, 2.345, 3.456, (n % 20) + 0.125, 1.5, 0.25, 0.1234, -0.5678, 1.5708, n % 4 }
	end

	local function sections(count: number): { { number } }
		local list = {}
		for i = 1, count do
			list[i] = section(i)
		end
		return list
	end

	-- MaxSavedPieces pieces whose sections add up to MaxSavedSections.
	local function savedWood(): { any }
		local pieces = {}
		local left = GameConfig.MaxSavedSections
		local n = GameConfig.MaxSavedPieces
		for i = 1, n do
			local share = math.ceil(left / (n - i + 1))
			left -= share
			pieces[i] = {
				w = "lanternwood",
				k = "plank",
				f = "greatelk",
				x = 2,
				l = true,
				m = 1.36,
				d = 1.8,
				t = 1.1,
				bed = "TrailerBed",
				at = { 12.345, 1.5, -6.789, 0.1234, -1.2345, 3.1416 },
				s = sections(share),
			}
		end
		return pieces
	end

	local function placedItem(i: number): { [string]: any }
		return {
			uid = guid(i),
			blueprintId = "PlanerIndustrial",
			x = 180,
			z = -180,
			rot = i % 4,
			y = 48,
			wood = "lanternwood",
			paint = "darkbrown",
			-- Lane F: a ghost can hold planks, sandstone slabs and ingots
			-- (BuildCost). No piece needs more than 4 slabs or one ingot of one ore, so a
			-- ghost short of one (3 slabs plus a Copper ingot) is the most one can hold.
			fill = { units = 99, slabs = 3, ingots = { Copper = 1 } },
			paid = 99999,
			len = 48,
			lenX = 48,
			lenZ = 48,
			data = { x = 12.5, y = 8.25 },
		}
	end

	local function mining(): { [string]: any }
		local nodes = {}
		for i = 1, 48 do
			nodes[i] = { id = "node-" .. guid(i), hits = 12, n = 8, at = 1893456000 + i }
		end
		local bag = {}
		for _, id in ipairs(ORES) do
			bag[id] = 9999
		end
		return { tool = "ProspectorsPickaxe", nodes = nodes, bag = bag }
	end

	local function foreman(): { [string]: any }
		return {
			day = 99999,
			bonusOwed = 999999,
			lastTalk = 1893456000,
			paid = { true, true, true },
		}
	end

	local function fillSlot(record: { [string]: any })
		record.cash = GameConfig.CashCap
		record.totalEarned = GameConfig.CashCap
		record.rebirths = 4
		local axes = {}
		local temper = {}
		for i = 1, GameConfig.MaxOwnedAxes do
			local uid = guid(1000 + i)
			axes[i] = { uid = uid, id = "ProspectorsPickaxe" }
			temper[uid] = { prefix = "Prosperous", tier = 3 }
		end
		record.axes = axes
		record.temper = temper
		record.bestAxeTier = 9
		record.equippedAxe = axes[1].uid
		record.ownedTrucks = { "LoggingRig", "Flatbed", "ScoutATV", "Pickup", "Rustbucket", "TimberClassic" }
		record.equippedTruck = "LoggingRig"
		record.ownedTrailers = { "PonyTrailer", "RanchTrailer", "HaulTrailer" }
		record.equippedTrailer = "HaulTrailer"
		record.ownedBoats = { "Rowboat", "RiverSkiff" }
		record.gear = { "InsulatedCoat", "HeatBoots", "Lantern", "FeatherfallCloak" }
		record.gondolaPass = true
		record.skyPass = true
		local placed = {}
		for i = 1, GameConfig.PlacedCap do
			placed[i] = placedItem(i)
		end
		local squares = {}
		local grid = GameConfig.PlotGrid
		for x = 0, grid - 1 do
			for z = 0, grid - 1 do
				table.insert(squares, string.format("%d,%d", x, z))
			end
		end
		local wires = {}
		for i = 1, WireLogic.MaxWires do
			wires[i] = { from = guid(2000 + i), to = guid(3000 + i) }
		end
		local switches = {}
		for i = 1, WireLogic.MaxSwitches do
			switches[i] = guid(4000 + i)
		end
		local loose = {}
		for i = 1, GameConfig.MaxLoosePieces do
			loose[i] = {
				w = "lanternwood",
				k = "log",
				f = "greatelk",
				x = 2,
				l = true,
				t = 1.1,
				bed = "Ground",
				at = { 1.25, 0.5, -3.5, 0, 1.5708, 0 },
				g = { 120.5, 4, -80.25 },
				s = sections(1),
			}
		end
		-- Lane F (LooseSave): the unloaded base's loose wood is plot-relative
		-- (bed "Plot") and may carry two sections a piece (MaxSections 300 over
		-- 150 pieces); slabs and ingots are small records of their own. The
		-- worst case is the heaviest of them all, so every record is a wood one.
		for i = 1, GameConfig.MaxLoosePieces do
			loose[i].bed = "Plot"
			loose[i].g = nil
			loose[i].s = sections(2)
		end
		local pads = {}
		for i, id in ipairs(record.ownedTrucks) do
			pads[i] = {
				uid = guid(5000 + i),
				itemId = id,
				x = i * 16,
				z = 8,
				rot = 0,
				presses = 20,
				paintFrom = "#6B4F3A",
				paintTo = "#3A3D42",
			}
		end
		record.plot = {
			claimed = true,
			tier = #PlotData.Tiers,
			placed = placed,
			squares = squares,
			wires = wires,
			switches = switches,
			pads = pads,
			loose = loose,
			logic = {},
		}
		for i = 1, GameConfig.MaxLogicPerPlot do
			record.plot.logic[i] = { from = guid(6000 + i), to = guid(7000 + i), op = "and" }
		end
		local storage = {}
		for i = 1, Schema.StorageCap do
			storage[i] = {
				uid = guid(8000 + i),
				itemId = "PlanerIndustrial",
				shop = "Dealership",
				pending = true,
			}
		end
		record.storage = storage
		local book = {}
		for i, bp in ipairs(PlotData.Blueprints) do
			book[i] = bp.id
		end
		record.blueprintBook = book
		local plans = {}
		for i = 1, 20 do
			plans[i] = { uid = guid(9000 + i), id = "Cabin" }
		end
		record.blueprintItems = plans
		-- Boxed machines, plus the crafted furniture and Sparkworks pieces waiting in
		-- stock (Lane F: FurnitureData.MaxStock of them).
		record.sawmillStock = { "SawmillIndustrial", "SawmillIndustrial", "ChopSaw" }
		for i = 1, FurnitureData.MaxStock do
			table.insert(record.sawmillStock, if i % 2 == 0 then "CopperLampPost" else "WoodSweeper")
		end
		local compendium = {}
		local materials = {}
		local forgeLogs = {}
		local forgeWood = {}
		for _, id in ipairs(WOODS) do
			compendium[id] = true
			forgeLogs[id] = 99
			forgeWood[id] = 999.5
		end
		for _, id in ipairs(ORES) do
			materials[id] = 9999
		end
		record.compendium = compendium
		record.materials = materials
		record.forgeLogs = forgeLogs
		record.forgeWood = forgeWood
		-- The truck and the wood left on the ground can both be full. A map
		-- move parks the ground load into strandedLoad and clears it, so
		-- stranded is the same shape but not a third copy of the cap.
		record.truckLoad = savedWood()
		record.groundLoad = savedWood()
		record.strandedLoad = { savedWood()[1] }
		local sky = {}
		for i = 1, 40 do
			sky[i] =
				{ w = "lanternwood", v = 12.5, f = "greatelk", p = true, b = 2, l = true, m = 1.36, d = 1.8, t = 1.1 }
		end
		record.skyWood = sky
		local bed = {}
		local left = {}
		for i = 1, GameConfig.MaxSavedPieces do
			bed[i] = { woodId = "lanternwood", value = 999, figure = "greatelk" }
			left[i] = { woodId = "lanternwood", value = 999, figure = "greatelk", x = 10.5, y = 4, z = -20.25 }
		end
		record.truckBed = bed
		record.leftLoad = left
		record.truckAt = { x = 12.5, y = 4, z = -80.5 }
		record.worldVersion = GameConfig.WorldVersion
		local secrets = {}
		for i = 1, 16 do
			secrets["carving-" .. i] = true
		end
		record.secrets = secrets
		local goals = {}
		for i = 1, DailyData.GoalsPerDay do
			goals[i] = {
				kind = "sellWoodVolume",
				target = 9999,
				progress = 9999,
				reward = 1300,
				wood = "lanternwood",
				done = true,
				paid = true,
			}
		end
		record.daily = {
			day = 99999,
			goals = goals,
			streak = 99,
			bestStreak = 99,
			lastCompleteDay = 99999,
			loginDay = 7,
			lastLoginDay = 99999,
			bonusOwed = 999999,
		}
		record.foreman = foreman()
		record.mining = mining()
		record.skyQuest = { step = 4, turnedIn = true }
		record.forgeOrder = { wood = "lumenwood", left = 60, cash = 20000 }
		record.relics = { carved = true, star = true }
		record.stats = { treesChopped = 99999, logsSold = 99999, playtimeMin = 99999, volumeSold = 99999, cuts = 99999 }
		record.tutorialDone = true
		record.tutorialStep = 12
		record.tutorialProgress = 4
		record.permissions = { ["123456789"] = { build = true, visit = true } }
	end

	local function fillAccount(data: { [string]: any })
		local flags = {}
		for i = 1, 24 do
			flags["badge-" .. i] = true
		end
		data.badgesAwarded = flags
		data.badgesSent = Util.deepCopy(flags)
		data.secretsFound = { hermit = true, lighthouse = true }
		data.areasVisited = { town = true, snow = true, volcano = true, isles = true }
		data.cosmetics = { pumpkinHat = true }
		data.guideStamps = { mill = true, plot = true }
		data.tipsSeen = { chop = true, sell = true }
		data.passes = { LuxAxe = true, TimberClassic = true }
		data.ownerGrants = {
			LuxAxe = { at = 1893456000, by = 1, byName = "Connor" },
		}
		local log = {}
		for i = 1, PaidItems.LogCap do
			log[i] = { op = "grant", id = "LuxAxe", at = 1893456000, by = 1, byName = "Connor" }
		end
		data.ownerGrantLog = log
		local receipts = {}
		for i = 1, Schema.PurchaseIdCacheSize do
			receipts[i] = guid(10000 + i)
		end
		data.purchaseIds = receipts
		data.accountAxes = { "LuxAxe" }
		data.pendingCash = GameConfig.CashCap
	end

	t.test("a full three-slot save, with mining and the foreman, stays under 1 MB", function()
		t.eq(Schema.StorageCap, 50)
		t.eq(GameConfig.MaxSavedSections, 300)
		t.eq(GameConfig.SlotCount, 3)
		local data = Util.deepCopy(Schema.Template)
		fillAccount(data)
		fillSlot(data)
		data.activeSlot = 1
		data.slots = {}
		for index = 1, SaveSlotLogic.Count do
			local snap = { fresh = false, lastPlayed = 1893456000, name = "Save " .. index }
			for key, value in pairs(data) do
				if not SaveSlotLogic.IsAccountKey(key) then
					snap[key] = Util.deepCopy(value)
				end
			end
			data.slots[index] = snap
		end
		local json = serde.encode("json", data)
		local bytes = #json
		print(string.format("[SaveSize] full three-slot save: %d bytes (%.1f%% of 1 MB)", bytes, bytes / MB * 100))
		t.ok(bytes <= MB, string.format("encoded %d bytes, over the 1 MB budget", bytes))
	end)
end
