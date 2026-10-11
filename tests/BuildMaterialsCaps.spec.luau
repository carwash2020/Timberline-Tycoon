--!nocheck
-- V1 hardening: BuildMaterials.EnforceCaps keeps the loose-parts caps on the
-- real parts (fake CollectionService and Workspace, real Lune instances).
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance

	local function setup(options)
		options = options or {}
		local tagged = {}
		local mining = Instance.new("Folder")
		mining.Name = "Mining"
		local slabs = Instance.new("Folder")
		slabs.Name = "Slabs"
		local world = {
			FindFirstChild = function(_, name)
				return if name == "Mining" then mining else nil
			end,
		}
		local loader = t.loader({
			services = {
				CollectionService = {
					GetTagged = function()
						-- Destroyed parts drop out, as the engine's list would.
						local live = {}
						for _, inst in ipairs(tagged) do
							if inst.Parent ~= nil then
								table.insert(live, inst)
							end
						end
						return live
					end,
				},
				Workspace = world,
				HttpService = {
					GenerateGUID = function()
						return "guid"
					end,
				},
			},
		})
		local BuildMaterials = loader:server("BuildMaterials")
		local GameConfig = loader:shared("GameConfig")
		if options.perPlayer then
			GameConfig.MaxLooseMaterialsPerPlayer = options.perPlayer
		end
		if options.perServer then
			GameConfig.MaxLooseMaterialsServer = options.perServer
		end
		local n = 0
		local function slab(ownerId, born, opts)
			opts = opts or {}
			n += 1
			local part = Instance.new("Part")
			part.Name = "Slab"
			part:SetAttribute("OwnerId", ownerId)
			part:SetAttribute("Uid", "slab" .. n)
			part:SetAttribute("Born", born)
			if opts.heldBy then
				part:SetAttribute("HeldBy", opts.heldBy)
			end
			part.Parent = if opts.inside then opts.inside else slabs
			table.insert(tagged, part)
			return part
		end
		local function ore(kind, ownerId, born)
			n += 1
			local model = Instance.new("Model")
			model.Name = kind
			model:SetAttribute("OwnerId", ownerId)
			model:SetAttribute("Uid", "ore" .. n)
			model:SetAttribute("Born", born)
			model:SetAttribute("Ore", "Copper")
			model.Parent = mining
			return model
		end
		return { M = BuildMaterials, slab = slab, ore = ore, slabs = slabs, mining = mining }
	end

	t.test("under the caps nothing is touched", function()
		local s = setup()
		local a = s.slab(1, 1)
		local b = s.ore("Ingot", 1, 2)
		t.eq(s.M.EnforceCaps(), 0)
		t.ok(a.Parent ~= nil and b.Parent ~= nil)
	end)

	t.test("a player over their cap loses their oldest, slabs and ore alike", function()
		local s = setup({ perPlayer = 3 })
		local oldSlab = s.slab(1, 1)
		local chunk = s.ore("OreChunk", 1, 2)
		local ingot = s.ore("Ingot", 1, 3)
		local newest = s.slab(1, 4)
		local others = s.slab(2, 0)
		t.eq(s.M.EnforceCaps(), 1)
		t.eq(oldSlab.Parent, nil, "the oldest went")
		t.ok(chunk.Parent and ingot.Parent and newest.Parent, "the rest stayed")
		t.ok(others.Parent ~= nil, "someone else's never counts against this player")
	end)

	t.test("the server cap takes the oldest of anyone's once nobody is over their own", function()
		local s = setup({ perPlayer = 10, perServer = 3 })
		local a = s.slab(1, 1)
		local b = s.slab(2, 2)
		local c = s.ore("Ingot", 3, 3)
		local d = s.ore("OreChunk", 4, 4)
		t.eq(s.M.EnforceCaps(), 1)
		t.eq(a.Parent, nil)
		t.ok(b.Parent and c.Parent and d.Parent)
	end)

	t.test("a piece in a hand, or inside a box or machine, is never taken", function()
		local s = setup({ perPlayer = 1, perServer = 1 })
		local box = Instance.new("Model")
		box.Name = "Box"
		local held = s.slab(1, 1, { heldBy = 1 })
		local boxed = s.slab(1, 2, { inside = box })
		local carried = s.ore("Ingot", 1, 3)
		local weld = Instance.new("Weld")
		weld.Name = "CarryWeld"
		weld.Parent = carried
		local loose = s.slab(1, 4)
		s.M.EnforceCaps()
		t.ok(held.Parent ~= nil, "held (HeldBy)")
		t.ok(boxed.Parent ~= nil, "in a box")
		t.ok(carried.Parent ~= nil, "carried (CarryWeld)")
		t.eq(loose.Parent, nil, "the only loose one made room")
	end)

	t.test("things the module does not own are left alone: other models, parts with no uid", function()
		local s = setup({ perPlayer = 0, perServer = 0 })
		local stray = Instance.new("Model")
		stray.Name = "Ingot"
		stray.Parent = s.mining -- no Uid: not ours to count
		local rock = Instance.new("Model")
		rock.Name = "Boulder"
		rock:SetAttribute("Uid", "rock")
		rock.Parent = s.mining
		s.M.EnforceCaps()
		t.ok(stray.Parent ~= nil and rock.Parent ~= nil)
	end)
end
