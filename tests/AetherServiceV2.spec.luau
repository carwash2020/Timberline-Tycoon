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
--   * the chute's prompt says "Check Sky Bin" under v2.
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
	local ON_TOP = Vector3.new(100, 4.3, 0) -- a 2.6-thick log lying on it

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
		local tagged = { CloudChute = { chute } }

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
		Aether.Init(function(p, message)
			table.insert(s.toasts, { id = p.UserId, text = message })
		end)
		s.chutePrompt = s.prompts[1]
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
end
