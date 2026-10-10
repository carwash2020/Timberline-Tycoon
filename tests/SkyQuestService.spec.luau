--!nocheck
-- Gus's Charter on the server, against mocks: range, the steps, planks laid
-- by the station used up (paying nothing), the pass once, no cash charged.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3

	local function setup(opts)
		opts = opts or {}
		local profile = {
			cash = 5000,
			gear = {},
			skyQuest = opts.skyQuest or { step = "none", progress = {}, done = false },
			gondolaPass = opts.pass == true,
			skyPass = false,
		}
		-- Plain tables: @lune/roblox has no Position on a part.
		local station = { Position = Vector3.new(0, 1, 0) }
		local root = { Position = Vector3.new(opts.distance or 6, 3, 0) }
		function root:IsA(class)
			return class == "BasePart"
		end
		local char = {}
		function char:FindFirstChild(name)
			return if name == "HumanoidRootPart" then root else nil
		end
		local attrs = {}
		local player = { UserId = 7, Name = "Ann", Character = char }
		function player:SetAttribute(k, v)
			attrs[k] = v
		end
		local toasts, taken, spent = {}, {}, {}
		local pieces = opts.pieces or {}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				AxeService = {
					OwnedCounts = function()
						return opts.axes or { RustyAxe = 1 }, 1
					end,
				},
				HandInWood = {
					Near = function()
						local byUid = {}
						for _, c in ipairs(pieces) do
							byUid[c.uid] = c
						end
						return pieces, byUid
					end,
					Take = function(_, uids)
						local n = 0
						for _, uid in ipairs(uids) do
							table.insert(taken, uid)
							for i, c in ipairs(pieces) do
								if c.uid == uid then
									n += c.volume
									table.remove(pieces, i)
									break
								end
							end
						end
						return n
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
				EconomyService = {
					SpendCash = function(_, amount)
						table.insert(spent, amount)
						return true
					end,
				},
			},
			services = {
				AnalyticsService = {},
				Players = {
					PlayerAdded = { Connect = function() end },
					GetPlayers = function()
						return {}
					end,
				},
			},
		})
		local S = loader:server("SkyQuestService")
		S._reset()
		S.V1Init({
			notify = function(_, text)
				table.insert(toasts, text)
			end,
		})
		S._setStation(station)
		return {
			S = S,
			profile = profile,
			player = player,
			attrs = attrs,
			toasts = toasts,
			taken = taken,
			spent = spent,
			pieces = pieces,
			root = root,
		}
	end

	local function plank(uid, woodId, volume, owner)
		return {
			uid = uid,
			woodId = woodId,
			kind = "plank",
			volume = volume,
			owner = owner or 7,
			welded = false,
			held = false,
			distance = 4,
		}
	end

	t.test("out of range, nothing happens", function()
		local w = setup({ distance = 40 })
		t.eq(w.S.Act(w.player, "accept"), nil)
		t.eq(w.profile.skyQuest.step, "none")
		t.eq(#w.toasts, 0)
	end)

	t.test("junk actions are ignored", function()
		local w = setup()
		t.eq(w.S.Act(w.player, "steal"), nil)
		t.eq(w.S.Act(w.player, 5), nil)
		t.eq(w.profile.skyQuest.step, "none")
	end)

	t.test("the whole charter: steps advance, wood is used up and pays nothing, the pass once, no cash", function()
		local w = setup({
			axes = { ObsidianAxe = 1 },
			pieces = {
				plank("f1", "frostwood", 60),
				plank("f2", "frostwood", 70),
				plank("e1", "emberwood", 120),
				plank("g1", "phantomwood", 40),
				plank("theirs", "frostwood", 500, 9),
			},
		})
		w.S.Act(w.player, "accept")
		t.eq(w.profile.skyQuest.step, "proven")
		t.eq(w.attrs.SkyQuestStep, "proven")
		w.S.Act(w.player, "turnin")
		t.eq(w.profile.skyQuest.step, "frost", "owns the Obsidian Axe")
		w.S.Act(w.player, "turnin")
		t.eq(w.profile.skyQuest.step, "ember", "120 Frostwood in")
		t.ok(table.find(w.taken, "f1") and table.find(w.taken, "f2"), "the frost planks are used up")
		t.eq(table.find(w.taken, "theirs"), nil, "someone else's plank is never taken")
		w.S.Act(w.player, "turnin")
		t.eq(w.profile.skyQuest.step, "gloam")
		t.eq(w.profile.gondolaPass, false, "no pass yet")
		w.S.Act(w.player, "turnin")
		t.eq(w.profile.skyQuest.done, true)
		t.eq(w.profile.gondolaPass, true)
		t.eq(w.profile.skyPass, true)
		t.eq(table.find(w.profile.gear, "GondolaPass") ~= nil, true, "in the inventory")
		t.eq(w.attrs.GondolaPass, true)
		t.eq(w.attrs.SkyQuestStep, "done")
		t.eq(w.profile.cash, 5000, "no cash charged or paid")
		t.eq(#w.spent, 0)
		-- Again: nothing more.
		w.S.Act(w.player, "turnin")
		local count = 0
		for _, g in ipairs(w.profile.gear) do
			if g == "GondolaPass" then
				count += 1
			end
		end
		t.eq(count, 1, "granted once")
	end)

	t.test("progress is saved per step and survives a fresh service (rejoin)", function()
		local w = setup({
			skyQuest = { step = "frost", progress = {}, done = false },
			pieces = { plank("a", "frostwood", 50) },
		})
		w.S.Act(w.player, "turnin")
		t.eq(w.profile.skyQuest.progress.frost, 50)
		local saved = w.profile.skyQuest
		local w2 = setup({ skyQuest = saved, pieces = { plank("b", "frostwood", 70) } })
		w2.S.Act(w2.player, "turnin")
		t.eq(w2.profile.skyQuest.step, "ember")
		local view = w2.S.State(w2.player)
		t.eq(view.step, "ember")
	end)

	t.test("an existing save with the pass flag is done; one without is not given it", function()
		local w = setup({ pass = true })
		t.eq(w.S.State(w.player).done, true)
		local w2 = setup({ axes = { StarfallAxe = 1, ObsidianAxe = 1 } })
		t.eq(w2.S.State(w2.player).done, false, "owning Starfall doesn't grant it")
		t.eq(w2.profile.gondolaPass, false)
	end)
end
