--!nocheck
-- AetherService under the v2 loop (V2_PLAN.md §5, M1.7b), against fakes:
-- the clock, players and their saves, the box query (every part in the
-- Wood folder: the hopper's own test of a piece's middle decides), and
-- ProximityPrompts (Lune's have no events). Real Lune instances for the
-- wood and the hoppers. It proves:
--   * a piece resting in a Cloud Chute's hopper goes down into its payee's
--     Sky Bin as an entry (wood, u³, figure, plank, boost), after the
--     settle time, released, forgotten and destroyed, with one toast;
--   * a piece beside the hopper, or that leaves it, isn't taken;
--   * the bin holds 120 u³: a piece that won't fit stays, with a toast at
--     most every few seconds;
--   * an offline owner's piece goes to its last holder; nobody online, it
--     stays; a piece already going, dead, a shop's or unknown stays;
--   * the chute's prompt says "Check Sky Bin" under v2;
--   * "Sell Sky Bin" by the pad pays the bin through SellService.PayEntries
--     (as a pad sale), empties it, only from beside the bin, rate-limited,
--     and keeps it while the pad isn't selling;
--   * the hoppers' boxes fit BuildingArt's chute and forge;
--   * the Starfall Forge takes plain lumenwood's u³ up to the recipe (60)
--     and refuses other woods, figured wood and wood past the recipe;
--     "Forge" spends forgeWood and never touches forgeLogs;
--   * wood that falls off the isles is lost to the clouds (one toast to its
--     owner); wood that never was on them isn't; a cloak wearer dragging a
--     piece glides down with it.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end

	local CHUTE_AT = CFrame.new(100, 1.5, 0) -- the hopper box's centre (4 x 3 x 4: its top at y 3)
	local BIN_AT = CFrame.new(-18, 2, 86) -- the Sky Bin by the pad (WorldPlan town.skyBin)
	local ON_TOP = Vector3.new(100, 4.3, 0) -- a 2.6-thick log lying on it
	-- The forge, turned a quarter, off on its own.
	local FORGE_AT = CFrame.new(300, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local BuildingArt = t.loader():load("ReplicatedStorage/Shared/Art/BuildingArt")
	local UP = Vector3.new(0, 1, 0)

	local function setup(options)
		options = options or {}
		local s = {
			clock = 0,
			toasts = {},
			released = {},
			forgotten = {},
			prompts = {},
			records = {},
			profiles = {},
			players = {},
			online = { [1] = true, [2] = true },
			held = {},
		}
		local FakeInstance = setmetatable({
			new = function(className, ...)
				if className == "ProximityPrompt" then
					local prompt = { ClassName = "ProximityPrompt", Name = "ProximityPrompt" }
					prompt.Triggered = {
						Connect = function(_, fn)
							prompt.fire = fn
						end,
					}
					table.insert(s.prompts, prompt)
					return prompt
				end
				return Instance.new(className, ...)
			end,
		}, { __index = Instance })

		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local Util = loader:shared("Util")
		function s.player(id)
			local p = s.players[id]
			if not p then
				p = {
					UserId = id,
					Name = "P" .. id,
					attrs = {},
					SetAttribute = function(self, key, value)
						self.attrs[key] = value
					end,
				}
				local character = Instance.new("Model")
				local hrp = Instance.new("Part")
				hrp.Name = "HumanoidRootPart"
				hrp.CFrame = BIN_AT * CFrame.new(0, 1, -6) -- on the pad's edge, beside the bin
				hrp.Parent = character
				p.Character = character
				p.hrp = hrp
				s.players[id] = p
				local profile = Util.deepCopy(Schema.Template)
				s.profiles[id] = profile
			end
			return p
		end
		s.player(1)
		s.player(2)

		local chute = Instance.new("Part")
		chute.Name = "CloudChute"
		chute.Size = Vector3.new(4, 3, 4)
		chute.CFrame = CHUTE_AT
		s.chute = chute
		local isle = Instance.new("Folder")
		chute.Parent = isle
		local forge = BuildingArt.StarfallForge()
		forge:PivotTo(FORGE_AT * forge:GetPivot()) -- as Kit.placeAt (MapBuilder) places it
		forge.Parent = isle
		s.anvil = forge:FindFirstChild("StarfallForge")
		s.hearth = forge:FindFirstChild("ForgeHearth")
		-- A 2.6-thick log lying on the hearth.
		s.onHearth = s.hearth.CFrame * Vector3.new(0, s.hearth.Size.Y / 2, 0) + UP * 1.3
		local tagged = { CloudChute = { chute }, StarfallForge = { s.anvil } }
		s.granted = {}

		loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return s.profiles[p.UserId]
					end,
				},
				TreeService = {
					GetLog = function()
						return nil
					end,
				},
				CarryService = {
					Hands = function()
						return {}
					end,
					TakeLogs = function()
						return {}
					end,
					TakeWhere = function()
						return {}
					end,
				},
				AxeService = {
					OwnedCounts = function()
						return {}, 0
					end,
					Grant = function(_, axeId)
						table.insert(s.granted, axeId)
						return { uid = "u", id = axeId }, nil
					end,
				},
				NodeService = { Publish = function() end },
			},
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					GetPlayerByUserId = function()
						return nil
					end,
					PlayerRemoving = signal(),
					PlayerAdded = signal(),
				},
				RunService = { Heartbeat = signal() },
				CollectionService = {
					GetTagged = function(_, tag)
						return tagged[tag] or {}
					end,
					GetInstanceAddedSignal = function()
						return signal()
					end,
				},
			},
			globals = { Instance = FakeInstance },
		})
		local Aether = loader:server("AetherService")
		s.A = Aether
		s.loader = loader
		-- The sell pad's side of the Sky Bin's sale (the same module
		-- AetherService required).
		s.paid, s.sold = {}, {}
		s.Sell = loader:server("SellService")
		s.Sell._use({
			zone = Instance.new("Part"),
			woodFolder = Instance.new("Folder"),
			resolve = function()
				return nil
			end,
			addCash = function(p, amount, reason, sku)
				table.insert(s.paid, { id = p.UserId, amount = amount, reason = reason, sku = sku })
				return nil
			end,
			saleMultiplier = function()
				return 1
			end,
			notify = function(p, text)
				table.insert(s.toasts, { id = p.UserId, text = text })
			end,
			release = function() end,
			forget = function() end,
			onSold = function(sale)
				table.insert(s.sold, sale)
			end,
		})
		local bin = Instance.new("Part")
		bin.Name = "SkyBin"
		bin.Size = Vector3.new(4, 4, 4)
		bin.CFrame = BIN_AT
		s.bin = bin
		Aether.Init(function(p, message)
			table.insert(s.toasts, { id = p.UserId, text = message })
		end)
		-- Each prompt by its text as made (under v1, before InitV2).
		s.byV1 = {}
		for _, prompt in ipairs(s.prompts) do
			s.byV1[prompt.ActionText] = prompt
		end
		s.chutePrompt = s.byV1["Send logs down"]
		s.v1Text = s.chutePrompt and s.chutePrompt.ActionText

		local folder = Instance.new("Folder")
		folder.Name = "Wood"
		s.folder = folder
		-- A one-part piece of `woodId`, `volume` u³, whose part (and middle)
		-- is at `at` (on top of the chute by default).
		function s.piece(id, owner, woodId, volume, extra, at)
			extra = extra or {}
			local m = Instance.new("Model")
			m.Name = "Wood_" .. id
			m:AddTag("Wood")
			local part = Instance.new("Part")
			part.Size = Vector3.new(2.6, 6, 2.6)
			part.CFrame = CFrame.new(at or ON_TOP)
			part.Parent = m
			m.PrimaryPart = part
			m:SetAttribute("WoodId", woodId)
			m:SetAttribute("Volume", volume)
			for _, key in ipairs({ "Kind", "Figure", "Boost" }) do
				if extra[key] ~= nil then
					m:SetAttribute(key, extra[key])
				end
			end
			m.Parent = folder
			s.records[m] = { model = m, ownerId = owner, lastHolderId = extra.holder }
			return m, part
		end
		Aether.InitV2({
			woodFolder = folder,
			skyBin = if options.noBin then nil else bin,
			heldBy = function(model)
				return s.held[model]
			end,
			resolve = function(model)
				return s.records[model]
			end,
			release = function(model)
				table.insert(s.released, model)
			end,
			forget = function(model)
				table.insert(s.forgotten, model)
				s.records[model] = nil
			end,
			partsInBox = function(_cf, _size, within)
				local out = {}
				for _, d in ipairs(within:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(out, d)
					end
				end
				return out
			end,
			now = function()
				return s.clock
			end,
			player = function(id)
				return if s.online[id] then s.player(id) else nil
			end,
		})
		for _, prompt in ipairs(s.prompts) do
			if prompt.Name == "SellSkyBin" then
				s.binPrompt = prompt
			end
		end
		function s.tick(dt)
			s.clock += dt or 0
			Aether.HopperTick()
		end
		-- Lets the hopper see it, then waits past the settle time.
		function s.settle()
			s.tick(0)
			s.tick(0.5)
		end
		function s.gone(model)
			return model.Parent == nil
		end
		return s
	end

	local function toastsFor(s, id)
		local out = {}
		for _, toast in ipairs(s.toasts) do
			if toast.id == id then
				table.insert(out, toast.text)
			end
		end
		return out
	end

	t.test("a piece laid in the chute goes down into its owner's Sky Bin as an entry", function()
		local s = setup()
		local m = s.piece("a", 1, "maple", 2.5, { Kind = "plank", Figure = "curly", Boost = 2 })
		s.tick(0)
		s.tick(0.1)
		t.eq(#s.profiles[1].skyWood, 0, "not before it has settled")
		s.tick(0.3)
		t.eq(s.profiles[1].skyWood, { { w = "maple", v = 2.5, f = "curly", p = true, b = 2 } })
		t.ok(s.gone(m), "the piece went down the chute")
		t.eq(s.released, { m })
		t.eq(s.forgotten, { m })
		t.eq(s.players[1].attrs.SkyBinVolume, 2.5)
		t.eq(toastsFor(s, 1), { "Sent 1 piece down the Cloud Chute. Sky Bin 2.5/120 u³." })
		-- A plain log keeps only its wood and volume.
		s.piece("b", 1, "lumenwood", 12)
		s.settle()
		t.eq(s.profiles[1].skyWood[2], { w = "lumenwood", v = 12 })
		t.eq(s.players[1].attrs.SkyBinVolume, 14.5)
	end)

	t.test("wood beside the hopper isn't in it; wood that leaves starts its wait again", function()
		local s = setup()
		local beside = s.piece("a", 1, "oak", 4, nil, Vector3.new(103.5, 1.3, 0))
		local below = s.piece("b", 1, "oak", 4, nil, Vector3.new(100, -2, 0))
		s.settle()
		s.tick(1)
		t.ok(not s.gone(beside) and not s.gone(below))
		t.eq(#s.profiles[1].skyWood, 0)
		local m, part = s.piece("c", 1, "oak", 4)
		s.tick(0)
		s.tick(0.2)
		part.CFrame = CFrame.new(110, 1.3, 0) -- rolled off
		s.tick(0.05)
		part.CFrame = CFrame.new(ON_TOP)
		s.tick(0.1)
		t.ok(not s.gone(m), "back in: it waits again")
		s.tick(0.35)
		t.ok(s.gone(m))
	end)

	t.test("the bin holds 120 u³: a piece that won't fit stays, and says so now and then", function()
		local s = setup()
		s.profiles[1].skyWood = { { w = "oak", v = 60 }, { w = "pine", v = 40 } }
		local big = s.piece("a", 1, "lumenwood", 30)
		s.settle()
		t.ok(not s.gone(big), "left where it is")
		t.eq(#s.forgotten, 0)
		t.eq(#s.profiles[1].skyWood, 2)
		t.eq(toastsFor(s, 1), { "Your Sky Bin is full (120 u³). Sell it at the sawmill." })
		s.tick(1)
		s.tick(1)
		t.eq(#toastsFor(s, 1), 1, "not every poll")
		s.tick(2.5)
		t.eq(#toastsFor(s, 1), 2, "again after a few seconds")
		-- Exactly what's left fits.
		local exact = s.piece("b", 1, "oak", 20)
		s.settle()
		t.ok(s.gone(exact))
		t.eq(s.players[1].attrs.SkyBinVolume, 120)
		-- A piece bigger than the whole bin says so.
		local s2 = setup()
		s2.piece("c", 1, "pine", 130)
		s2.settle()
		t.eq(toastsFor(s2, 1), { "That piece is too big for the Sky Bin (120 u³). Cut it smaller." })
	end)

	t.test("an offline owner's piece goes to its last holder; with nobody online it stays", function()
		local s = setup()
		local mine = s.piece("a", 1, "oak", 4, { holder = 2 })
		local left = s.piece("b", 9, "oak", 5, { holder = 2 })
		local nobody = s.piece("c", 9, "oak", 6, { holder = 8 })
		s.settle()
		t.eq(s.profiles[1].skyWood, { { w = "oak", v = 4 } }, "the owner, not the one who pushed it")
		t.eq(s.profiles[2].skyWood, { { w = "oak", v = 5 } }, "the last holder, for an owner who left")
		t.ok(s.gone(mine) and s.gone(left))
		t.ok(not s.gone(nobody), "nobody to take it: it stays")
	end)

	t.test("never twice: a piece already going, dead, a shop's or unknown is left alone", function()
		local s = setup()
		local selling = s.piece("a", 1, "oak", 4)
		local dead = s.piece("b", 1, "oak", 4)
		local shop = s.piece("c", 1, "oak", 4)
		local unknown = s.piece("d", 1, "oak", 4)
		local noVolume = s.piece("e", 1, "oak", 0)
		s.records[selling].selling = true
		s.records[dead].dead = true
		s.records[shop].shopItem = true
		s.records[unknown] = nil
		s.settle()
		for _, m in ipairs({ selling, dead, shop, unknown, noVolume }) do
			t.ok(not s.gone(m), m.Name .. " stays")
		end
		t.eq(#s.profiles[1].skyWood, 0)
		local good = s.piece("f", 1, "oak", 4)
		s.settle()
		local record = s.forgotten[1] == good
		t.ok(record, "the good one went")
		s.tick(1)
		t.eq(#s.profiles[1].skyWood, 1, "and only once")
	end)

	t.test("the chute's prompt sends logs under v1 and says how full your bin is under v2", function()
		local s = setup()
		t.eq(s.v1Text, "Send logs down", "made under v1")
		t.eq(s.chutePrompt.ActionText, "Check Sky Bin", "relabelled by InitV2")
		s.profiles[1].skyWood = { { w = "oak", v = 14 } }
		s.chutePrompt.fire(s.player(1))
		t.eq(
			toastsFor(s, 1),
			{ "Lay wood in the Cloud Chute and it goes down to your Sky Bin by the sawmill. Sky Bin 14/120 u³." }
		)
	end)

	t.test("Sell Sky Bin pays the bin as a pad sale and empties it", function()
		local s = setup()
		local SellLogic = t.shared("SellLogic")
		t.ok(s.binPrompt ~= nil, "the prompt is on the bin")
		t.eq(s.binPrompt.Parent, s.bin)
		t.eq(s.binPrompt.ActionText, "Sell Sky Bin")
		local entries = {
			SellLogic.Entry("lumenwood", "log", 12, nil, 1),
			SellLogic.Entry("maple", "plank", 2, "curly", 2),
		}
		s.profiles[1].skyWood = entries
		s.binPrompt.fire(s.player(1))
		local value = SellLogic.EntriesValue(entries)
		t.eq(#s.paid, 1)
		t.eq(s.paid[1].amount, SellLogic.Payout(value, 1))
		t.eq(s.profiles[1].skyWood, {}, "the bin is empty")
		t.eq(s.players[1].attrs.SkyBinVolume, 0)
		t.eq(#s.sold, 1, "the tutorial, dailies and reveals hear of it")
		t.eq(s.sold[1].figures, { "curly" })
		t.eq(toastsFor(s, 1), { SellLogic.SaleText(2, 14, s.paid[1].amount) })
	end)

	t.test("Sell Sky Bin: not from afar, says when it's empty, keeps the bin if the pad isn't selling", function()
		local s = setup()
		local entry = { w = "oak", v = 10 }
		s.profiles[1].skyWood = { entry }
		local p1 = s.player(1)
		p1.hrp.CFrame = BIN_AT * CFrame.new(0, 0, -40)
		s.binPrompt.fire(p1)
		t.eq(#s.paid, 0, "too far from the bin")
		t.eq(s.profiles[1].skyWood, { entry })
		local p2 = s.player(2)
		s.binPrompt.fire(p2)
		t.eq(toastsFor(s, 2), {
			"Your Sky Bin is empty. Lay wood in a Cloud Chute on the Aether Isles to fill it.",
		})
		p1.hrp.CFrame = BIN_AT * CFrame.new(0, 1, -6)
		s.Sell._reset()
		s.binPrompt.fire(p1)
		t.eq(s.profiles[1].skyWood, { entry }, "kept for later")
		t.eq(#s.paid, 0)
	end)

	t.test("Sell Sky Bin is rate-limited", function()
		local s = setup()
		local p1 = s.player(1)
		for _ = 1, 3 do
			s.profiles[1].skyWood = { { w = "oak", v = 10 } }
			s.binPrompt.fire(p1)
		end
		t.eq(#s.paid, 2, "2 a second")
		t.eq(#s.profiles[1].skyWood, 1, "the third press waited")
	end)

	t.test("without a Sky Bin part there's no sale prompt, and a warning", function()
		local s = setup({ noBin = true })
		t.eq(s.binPrompt, nil)
		t.ok(string.find(s.loader.warnings[1] or "", "No Sky Bin", 1, true) ~= nil, "warned")
	end)

	t.test("the hoppers' boxes fit the art: wood laid on them is in, wood on the ground beside isn't", function()
		local s = setup()
		local function inside(cf, size, point)
			local l = cf:PointToObjectSpace(point)
			return math.abs(l.X) <= size.X / 2 and math.abs(l.Y) <= size.Y / 2 and math.abs(l.Z) <= size.Z / 2
		end
		local cf, size = s.A.HopperZone(s.anvil, "forge")
		t.ok(inside(cf, size, s.onHearth), "on the hearth")
		t.ok(inside(cf, size, s.anvil.CFrame * Vector3.new(0, s.anvil.Size.Y / 2, 0) + UP * 1.3), "on the anvil")
		t.ok(not inside(cf, size, FORGE_AT * Vector3.new(0, 1.3, -3)), "on the ground in front")
		t.ok(not inside(cf, size, FORGE_AT * Vector3.new(4.5, 1.3, 1)), "on the ground beside")
		local chute = BuildingArt.CloudChute()
		chute:PivotTo(CFrame.new(-50, 0, 20) * CFrame.Angles(0, 0.7, 0) * chute:GetPivot())
		local box = chute:FindFirstChild("CloudChute")
		local ccf, csize = s.A.HopperZone(box, "chute")
		t.ok(inside(ccf, csize, box.CFrame * Vector3.new(0, box.Size.Y / 2, 0) + UP * 1.3), "on the chute")
		t.ok(
			not inside(ccf, csize, box.CFrame * Vector3.new(box.Size.X / 2 + 1.3, -box.Size.Y / 2 + 1.3, 0)),
			"beside it"
		)
		local step = chute:FindFirstChild("ChuteStep")
		t.ok(not inside(ccf, csize, step.CFrame * Vector3.new(0, step.Size.Y / 2, 0) + UP * 1.3), "on its step")
	end)

	t.test("the forge takes plain lumenwood's u³ up to 60 and leaves forgeLogs alone", function()
		local s = setup()
		local profile = s.profiles[1]
		profile.forgeWood = { lumenwood = 50 }
		profile.forgeLogs = { lumenwood = 12 }
		local a = s.piece("a", 1, "lumenwood", 4, nil, s.onHearth)
		s.settle()
		t.ok(s.gone(a), "into the forge")
		t.eq(profile.forgeWood.lumenwood, 54)
		t.eq(s.players[1].attrs.ForgeWood, "lumenwood=54")
		t.eq(toastsFor(s, 1), { "Into the forge: 4 u³. Lumenwood 54/60 u³ · Sky Shards 0/12 · $60,000" })
		local b = s.piece("b", 1, "lumenwood", 10, nil, s.onHearth)
		s.settle()
		t.ok(s.gone(b), "a piece bigger than what's left is used up")
		t.eq(profile.forgeWood.lumenwood, 60, "never past the recipe")
		t.eq(
			toastsFor(s, 1)[2],
			"Into the forge: 6 u³ (all it needed). Lumenwood 60/60 u³ · Sky Shards 0/12 · $60,000"
		)
		local c = s.piece("c", 1, "lumenwood", 3, nil, s.onHearth)
		s.settle()
		t.ok(not s.gone(c), "full: it stays")
		t.eq(toastsFor(s, 1)[3], "The forge has all the Lumenwood it needs.")
		t.eq(profile.forgeLogs, { lumenwood = 12 }, "forgeLogs untouched")
		t.eq(#profile.skyWood, 0, "the forge isn't a chute")
	end)

	t.test(
		"the forge refuses other woods and figured lumenwood, and the last holder's offline owner rule holds",
		function()
			local s = setup()
			local oak = s.piece("a", 1, "oak", 4, nil, s.onHearth)
			local figured = s.piece("b", 1, "lumenwood", 4, { Figure = "starfall" }, s.onHearth)
			local left = s.piece("c", 9, "lumenwood", 5, { holder = 2 }, s.onHearth)
			s.settle()
			t.ok(not s.gone(oak) and not s.gone(figured))
			t.eq(s.profiles[1].forgeWood, {})
			local said = toastsFor(s, 1)
			table.sort(said)
			t.eq(said, {
				"Figured wood is worth more sold than forged: take it to the sawmill.",
				"The forge takes plain Lumenwood only.",
			})
			t.ok(s.gone(left))
			t.eq(s.profiles[2].forgeWood, { lumenwood = 5 }, "the last holder's forge, for an owner who left")
		end
	)

	t.test("Forge under v2 spends forgeWood, keeps forgeLogs, and says what's short in u³", function()
		local s = setup()
		local profile = s.profiles[1]
		profile.cash = 70000
		profile.forgeWood = { lumenwood = 47.5 }
		profile.forgeLogs = { lumenwood = 40 }
		profile.materials = { SkyShard = 12 }
		local forgePrompt = s.byV1["Forge the Starfall Axe"]
		forgePrompt.fire(s.player(1))
		t.eq(s.granted, {})
		t.eq(toastsFor(s, 1), { "The forge needs 12.5 more u³ of Lumenwood." })
		t.eq(profile.cash, 70000)
		profile.forgeWood.lumenwood = 60
		forgePrompt.fire(s.player(1))
		t.eq(s.granted, { "StarfallAxe" })
		t.eq(profile.cash, 10000)
		t.eq(profile.forgeWood.lumenwood, 0)
		t.eq(profile.forgeLogs.lumenwood, 40, "forgeLogs untouched (a rollback to v1 keeps it)")
		t.eq(profile.materials.SkyShard, 0)
		t.eq(s.players[1].attrs.ForgeWood, "")
		local said = toastsFor(s, 1)
		t.ok(
			string.find(said[#said], "^The Starfall Axe is yours! It cuts a Lumenwood trunk in %d+ hits%.$") ~= nil,
			said[#said]
		)
	end)

	t.test("the forge's feed prompt says how far along it is under v2", function()
		local s = setup()
		local feed = s.byV1["Add lumenwood"]
		t.eq(feed.ActionText, "Check the forge")
		s.profiles[1].forgeWood = { lumenwood = 18 }
		s.profiles[1].materials = { SkyShard = 5 }
		feed.fire(s.player(1))
		t.eq(toastsFor(s, 1), {
			"Lay plain Lumenwood on the forge to feed it. Lumenwood 18/60 u³ · Sky Shards 5/12 · $60,000",
		})
	end)

	-- The isles (BiomeData sky.area): x -1050, z 1050, y 650; the deck is 40
	-- over that (690), and falling off is 40 under the deck (650).
	local ISLE = Vector3.new(-1050, 700, 1050)

	t.test("wood that falls off the isles is lost to the clouds, with one toast to its owner", function()
		local s = setup()
		local m, part = s.piece("a", 1, "lumenwood", 12, nil, ISLE)
		s.A.FallTick()
		t.ok(not s.gone(m), "on the isle")
		part.CFrame = CFrame.new(ISLE - Vector3.new(0, 30, 0)) -- falling, not yet gone
		s.A.FallTick()
		t.ok(not s.gone(m))
		part.CFrame = CFrame.new(ISLE - Vector3.new(0, 55, 0))
		s.A.FallTick()
		t.ok(s.gone(m), "lost to the clouds")
		t.eq(s.released, { m })
		t.eq(s.forgotten, { m })
		t.eq(toastsFor(s, 1), { "Your Lumenwood log fell off the isles: lost to the clouds." })
		-- Two at once: one toast.
		local a, pa = s.piece("b", 2, "lumenwood", 3, nil, ISLE + Vector3.new(60, 0, 0))
		local b, pb = s.piece("c", 2, "maple", 3, { Kind = "plank" }, ISLE + Vector3.new(-60, 0, 0))
		s.A.FallTick()
		pa.CFrame = CFrame.new(ISLE + Vector3.new(80, -300, 0))
		pb.CFrame = CFrame.new(ISLE + Vector3.new(-80, -300, 0))
		s.A.FallTick()
		t.ok(s.gone(a) and s.gone(b))
		t.eq(toastsFor(s, 2), { "2 pieces of your wood fell off the isles: lost to the clouds." })
	end)

	t.test("wood that never was on the isles, or left them some other way, isn't lost", function()
		local s = setup()
		local below = s.piece("a", 1, "oak", 4, nil, Vector3.new(-1050, 20, 1050)) -- the ground under the isles
		s.A.FallTick()
		s.A.FallTick()
		t.ok(not s.gone(below))
		local m, part = s.piece("b", 1, "lumenwood", 4, nil, ISLE)
		s.A.FallTick()
		part.CFrame = CFrame.new(0, 3, 40) -- teleported to town (a respawn's /spawnwood, say)
		s.A.FallTick()
		part.CFrame = CFrame.new(-1050, 20, 1050)
		s.A.FallTick()
		t.ok(not s.gone(m), "not watched once it left sideways")
		local unknown = s.piece("c", 1, "lumenwood", 4, nil, ISLE)
		s.A.FallTick()
		s.records[unknown] = nil
		unknown.PrimaryPart.CFrame = CFrame.new(ISLE - Vector3.new(0, 80, 0))
		s.A.FallTick()
		t.ok(not s.gone(unknown), "only pieces with a record")
		t.eq(#s.toasts, 0)
	end)

	t.test("a piece dragged by a cloak wearer glides down with them; without the cloak it's lost", function()
		local s = setup()
		local p1 = s.player(1)
		table.insert(s.profiles[1].gear, "FeatherfallCloak")
		local m, part = s.piece("a", 1, "lumenwood", 4, nil, ISLE)
		s.held[m] = p1
		s.A.FallTick()
		part.CFrame = CFrame.new(ISLE - Vector3.new(0, 30, 0)) -- 20 under the deck: past GLIDE_BELOW (15), not yet FALL_BELOW (40)
		s.A.FallTick()
		part.CFrame = CFrame.new(-1050, 20, 1050) -- landed
		s.held[m] = nil
		s.A.FallTick()
		t.ok(not s.gone(m), "glided down")
		local p2 = s.player(2)
		local n, pn = s.piece("b", 2, "lumenwood", 4, nil, ISLE)
		s.held[n] = p2 -- no cloak
		s.A.FallTick()
		pn.CFrame = CFrame.new(ISLE - Vector3.new(0, 60, 0))
		s.A.FallTick()
		t.ok(s.gone(n), "lost")
	end)
end
