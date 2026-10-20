--!nocheck
-- T395: every shop counter is lower (2.6) and deeper (3.6) than it was, so the
-- keeper shows from the waist up and the top is clear for the boxes being
-- paid for. The keeper stands 1 stud behind it, the CHECKOUT board hangs on
-- the back wall 3 studs over his head, and the Talk card sits between.
-- Counter rules that other specs hold (CounterLogic.InZone, BoxService
-- InCounter, StockShop, T388's name fade) are read, not changed.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local BacklogModels = t.load("ReplicatedStorage/Shared/Art/BacklogModels")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local NPCData = t.shared("NPCData")
	local CounterLogic = t.shared("CounterLogic")
	local StoreStock = t.shared("StoreStock")
	local ShopHoursLogic = t.shared("ShopHoursLogic")
	local TextAnchor = t.shared("TextAnchor")

	local KINDS = { "ToolShed", "Dealership", "HearthAndHome", "Sparkworks" }
	local TOP = 2.6
	local EPS = 1e-3

	local function build(kind)
		return BuildingArt.Shop(kind, kind, Color3.fromRGB(120, 70, 40))
	end

	local function keeperOf(kind)
		for _, npc in ipairs(NPCData.All()) do
			if npc.spot.kind == "counter" and npc.spot.model == kind then
				return npc
			end
		end
		return nil
	end

	-- A part's world-axis box from its eight corners.
	local function bounds(part)
		local lo = Vector3.new(math.huge, math.huge, math.huge)
		local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
		local h = part.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local p = part.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
					lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
					hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
				end
			end
		end
		return lo, hi
	end

	local function counterOf(shop)
		local counter = shop:FindFirstChild("Counter")
		t.ok(counter and counter:IsA("BasePart"), shop.Name .. " has a Counter part")
		return counter
	end

	local function parts(shop)
		local out = {}
		for _, d in ipairs(shop:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test(
		"every shop: one collidable axis-aligned Counter, top at 2.6, 3.6 deep, 10 wide, at the keeper's waist",
		function()
			for _, kind in ipairs(KINDS) do
				local shop = build(kind)
				local counter = counterOf(shop)
				t.ok(math.abs(counter.Size.Y - 2.6) < EPS, kind .. " height")
				t.ok(math.abs(counter.Size.Z - 3.6) < EPS, kind .. " depth")
				t.ok(counter.Size.Z >= 3 and counter.Size.X >= 6, kind .. " is at least 3 deep and 6 wide")
				t.ok(counter.CanCollide, kind .. " counter collides")
				t.ok(
					math.abs(counter.CFrame.Position.Y + counter.Size.Y / 2 - TOP) < EPS,
					kind .. " top is at 2.6, whatever the shop's scale"
				)
				t.ok(
					(counter.CFrame.RightVector - Vector3.xAxis).Magnitude < EPS
						and (counter.CFrame.UpVector - Vector3.yAxis).Magnitude < EPS,
					kind .. " counter is axis-aligned"
				)
				local named = 0
				for _, p in ipairs(parts(shop)) do
					if p.Name == "Counter" and p.CanCollide then
						named += 1
					end
				end
				t.eq(named, 1, kind .. ": exactly one collidable part named Counter")
				local keeper = keeperOf(kind)
				t.ok(keeper, kind .. " has a keeper")
				local feet = NPCData.BehindCounter(counter.CFrame, counter.Size)
				local root = feet.Position.Y + CharacterArt.RootHeight(keeper.look)
				t.ok(TOP <= root, kind .. " counter top is at or below the keeper's HumanoidRootPart")
			end
		end
	)

	t.test(
		"every shop: the keeper stands behind the +Z face with at least 1 stud, facing -Z, in clear floor",
		function()
			for _, kind in ipairs(KINDS) do
				local shop = build(kind)
				local counter = counterOf(shop)
				local feet = NPCData.BehindCounter(counter.CFrame, counter.Size)
				local back = counter.CFrame.Position.Z + counter.Size.Z / 2
				t.ok(feet.Position.Z - back >= 1 - EPS, kind .. " keeper is 1 stud behind the back face")
				t.ok(feet.LookVector.Z < -0.99, kind .. " keeper faces -Z")
				t.eq(NPCData.CounterGap, 1.0)
				-- Nothing solid but the floor stands in his body box (1.8 wide x 1.2 deep, 1.2 up to 6.5 over his feet).
				local body = {
					lo = Vector3.new(feet.Position.X - 0.9, feet.Position.Y + 1.2, feet.Position.Z - 0.6),
					hi = Vector3.new(feet.Position.X + 0.9, feet.Position.Y + 6.5, feet.Position.Z + 0.6),
				}
				for _, p in ipairs(parts(shop)) do
					if p.CanCollide and p.Transparency < 1 then
						local lo, hi = bounds(p)
						local inside = lo.X < body.hi.X
							and hi.X > body.lo.X
							and lo.Y < body.hi.Y
							and hi.Y > body.lo.Y
							and lo.Z < body.hi.Z
							and hi.Z > body.lo.Z
						t.ok(
							not inside,
							string.format(
								"%s: %s stands in the keeper (z %.2f to %.2f, keeper z %.2f)",
								kind,
								p.Name,
								lo.Z,
								hi.Z,
								feet.Position.Z
							)
						)
					end
				end
			end
		end
	)

	t.test(
		"every shop: the middle of the top is clear, clutter is one register and one bell in the outer 1.2 at his left",
		function()
			for _, kind in ipairs(KINDS) do
				local shop = build(kind)
				local counter = counterOf(shop)
				local cf, size = counter.CFrame, counter.Size
				local left = cf.Position.X - size.X / 2 + BuildingArt.CounterClutterWidth
				local clutter = {}
				for _, p in ipairs(parts(shop)) do
					if p ~= counter and p.Name ~= "CounterFront" then
						local lo, hi = bounds(p)
						local over = lo.X < cf.Position.X + size.X / 2
							and hi.X > cf.Position.X - size.X / 2
							and lo.Z < cf.Position.Z + size.Z / 2
							and hi.Z > cf.Position.Z - size.Z / 2
							and lo.Y >= TOP - 0.05
							and lo.Y < TOP + 2
						if over then
							table.insert(clutter, p)
							t.ok(
								hi.X <= left + EPS,
								kind .. ": " .. p.Name .. " stands outside the outer 1.2 at the clerk's left"
							)
							t.ok(not p.CanCollide, kind .. ": " .. p.Name .. " on the counter is not solid")
						end
					end
				end
				local registers, props = 0, 0
				for _, p in ipairs(clutter) do
					if p.Name == "Register" or p.Name == "RegisterTag" then
						registers += 1
					else
						props += 1
					end
				end
				t.ok(registers > 0 and registers <= 3, kind .. ": one register (its three bits)")
				t.eq(props, 1, kind .. ": one prop besides the register")
				-- The clear top: 6 x 3 round the middle holds nothing at all.
				for _, p in ipairs(parts(shop)) do
					if p ~= counter and p.Name ~= "CounterFront" and p.CanCollide then
						local lo, hi = bounds(p)
						local hit = lo.X < cf.Position.X + 3
							and hi.X > cf.Position.X - 3
							and lo.Z < cf.Position.Z + 1.5
							and hi.Z > cf.Position.Z - 1.5
							and hi.Y > TOP + 0.05
							and lo.Y < TOP + 6
						t.ok(not hit, kind .. ": " .. p.Name .. " is a solid prop over the middle of the top")
					end
				end
			end
		end
	)

	t.test(
		"every shop: a box at the middle of the top is in the pay zone, one 1 stud past the customer edge is not",
		function()
			for _, kind in ipairs(KINDS) do
				local shop = build(kind)
				local counter = counterOf(shop)
				local cf, size = counter.CFrame, counter.Size
				local on = cf * Vector3.new(0, size.Y / 2 + 1, 0)
				t.ok(CounterLogic.InZone(on, cf, size), kind .. " box on the top is in the zone")
				local past = cf * Vector3.new(0, size.Y / 2 + 1, -size.Z / 2 - 1)
				t.ok(not CounterLogic.InZone(past, cf, size), kind .. " box past the customer edge is out")
				-- The box's own corner on the top's edge still counts from its middle.
				local edge = cf * Vector3.new(size.X / 2 - 0.5, size.Y / 2 + 1, -size.Z / 2 + 0.5)
				t.ok(CounterLogic.InZone(edge, cf, size), kind .. " box at the corner is in the zone")
			end
		end
	)

	-- The Tool Shed's ConveyorFunnel box is 4.4 square and the Sparkworks SwitchBelt 5.2 x 3.87: both are deeper
	-- than the 3.6 top the brief fixes, so they sit centred and overhang the long edges by under half a stud each
	-- side (Overhang). Every other box fits inside the top outright.
	local Overhang = 0.5
	t.test("every shop: the largest box it sells sits on the top, overhanging by at most half a stud a side", function()
		for _, kind in ipairs(KINDS) do
			local shop = build(kind)
			local counter = counterOf(shop)
			local clear = counter.Size.X - BuildingArt.CounterClutterWidth
			for _, slot in ipairs(StoreStock.ForShop(kind)) do
				local box = StoreStock.BoxSizeOf(slot)
				local across, deep = math.max(box.X, box.Z), math.min(box.X, box.Z)
				t.ok(
					deep <= counter.Size.Z + 2 * Overhang and across <= clear,
					string.format(
						"%s: %s's box %.1f x %.1f sits on the %.1f x %.1f top",
						kind,
						slot.itemId,
						box.X,
						box.Z,
						clear,
						counter.Size.Z
					)
				)
			end
		end
	end)

	t.test("every shop: the sleeping keeper stays below the top", function()
		for _, kind in ipairs(KINDS) do
			local shop = build(kind)
			local counter = counterOf(shop)
			local sleep = NPCData.SleepCFrame(counter.CFrame, counter.Size)
			t.ok(
				sleep.Position.Y + ShopHoursLogic.SleepBodyHalf <= TOP - ShopHoursLogic.SleepClearance + EPS,
				kind .. " sleeper's body is under the top"
			)
		end
	end)

	local function loadPromptUI()
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
				},
				Players = { LocalPlayer = {} },
				TextChatService = {},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
				ProximityPromptService = {},
				TweenService = {},
				CollectionService = {},
				RunService = {},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/PromptUI")
	end

	t.test(
		"every shop: the CHECKOUT board is over the keeper (the back wall; the Tool Shed hangs it from its last beam), 3 studs over the keeper's head, over his Talk card",
		function()
			local PromptUI = loadPromptUI()
			for _, kind in ipairs(KINDS) do
				local shop = build(kind)
				local counter = counterOf(shop)
				local keeper = keeperOf(kind)
				local feet = NPCData.BehindCounter(counter.CFrame, counter.Size)
				local figure = CharacterArt.Build(keeper.look)
				figure:PivotTo(feet)
				local height = figure:GetAttribute("Height")
				local head = figure.Head
				local boards = {}
				for _, p in ipairs(parts(shop)) do
					if p.Name == "CheckoutSign" or p.Name == "CheckoutSignAccent" then
						table.insert(boards, p)
					end
					t.ok(p.Name ~= "CheckoutPost", kind .. " has no CHECKOUT post on the counter")
				end
				t.eq(#boards, 2, kind .. " CHECKOUT board and its strip")
				local lowest, backwall = math.huge, -math.huge
				for _, p in ipairs(boards) do
					local lo, hi = bounds(p)
					lowest = math.min(lowest, lo.Y)
					backwall = math.max(backwall, hi.Z)
					t.ok(
						p.CFrame.Position.Z >= counter.CFrame.Position.Z + counter.Size.Z / 2 - 0.3,
						kind .. " " .. p.Name .. " is at the counter's back edge or behind it, over the keeper's lane"
					)
				end
				t.ok(
					lowest >= feet.Position.Y + height + ShopKit.CheckoutHeadClear - EPS,
					string.format(
						"%s: board's underside %.2f is 3 over the hat top %.2f",
						kind,
						lowest,
						feet.Position.Y + height
					)
				)
				-- The Talk card's tail sits HeadLift over the head; it grows up from there. At 12 studs
				-- on a TV (1.5x) the 72 px card is the tallest it gets in play.
				local tail = head.CFrame.Position.Y + PromptUI.HeadLift
				t.ok(tail > head.CFrame.Position.Y + 0.625, kind .. " card is over the head")
				local card = TextAnchor.CardStuds(72 * 1.5, 12, 1080)
				t.ok(
					tail + card <= lowest,
					string.format(
						"%s: card %.2f to %.2f clears the board's underside %.2f",
						kind,
						tail,
						tail + card,
						lowest
					)
				)
			end
		end
	)

	t.test(
		"every shop: a hidden 3 x 5 blocker past each end of the counter, as deep as it, solid and unseen",
		function()
			for _, kind in ipairs(KINDS) do
				local shop = build(kind)
				local counter = counterOf(shop)
				local ends = {}
				for _, p in ipairs(parts(shop)) do
					if p.Name == "CounterBack" then
						table.insert(ends, p)
						t.ok(
							math.abs(p.Size.X - 3) < EPS and math.abs(p.Size.Y - 5) < EPS,
							kind .. " blocker is 3 wide, 5 tall"
						)
						t.ok(math.abs(p.Size.Z - counter.Size.Z) < EPS, kind .. " blocker is as deep as the counter")
						t.ok(p.CanCollide and p.Transparency == 1, kind .. " blocker is solid and invisible")
						local along = counter.CFrame:PointToObjectSpace(p.CFrame.Position)
						t.ok(
							math.abs(math.abs(along.X) - (counter.Size.X / 2 + 1.5)) < EPS and math.abs(along.Z) < EPS,
							kind .. " blocker stands against the counter's end"
						)
					end
				end
				t.eq(#ends, 2, kind .. " has one at each end")
			end
		end
	)

	t.test("a keeper under scale 0.9 stands on a 0.4 solid riser, 3 x 2; a taller one does not", function()
		local feet = CFrame.new(10, 0, 20)
		local kid = { spot = { kind = "counter", model = "ToolShed" }, look = { scale = 0.78 } }
		local size, at = NPCData.KeeperStep(kid, feet)
		t.eq(size, Vector3.new(3, 0.4, 2))
		t.ok((at.Position - Vector3.new(10, 0.2, 20)).Magnitude < EPS, "the riser is under his feet")
		local grown = { spot = { kind = "counter", model = "ToolShed" }, look = { scale = 0.9 } }
		t.eq(NPCData.KeeperStep(grown, feet), nil)
		t.eq(NPCData.KeeperStep({ spot = { kind = "counter", model = "ToolShed" }, look = {} }, feet), nil)
		t.eq(
			NPCData.KeeperStep({ spot = { kind = "fixed" }, look = { scale = 0.5 } }, feet),
			nil,
			"only behind a counter"
		)
		for _, npc in ipairs(NPCData.All()) do
			if npc.spot.kind == "counter" then
				t.ok((npc.look.scale or 1) >= 0.9, npc.id .. " is tall enough: no riser needed today")
			end
		end
	end)

	t.test("the three meshed counters carry the new size and stay part-built until the re-upload", function()
		for _, id in ipairs({ "ToolShed", "Dealership", "GeneralStore" }) do
			local asset = TownModels.Get(id)
			local piece = TownModels.Piece(asset, "Counter")
			t.ok(math.abs(piece.size.Y - 2.6) < EPS, id .. " mesh height")
			t.ok(math.abs(piece.size.Z - 3.6) < EPS, id .. " mesh depth")
			t.eq(piece.reupload, true, id .. " waits for the new upload")
			for _, visual in ipairs(TownModels.Visual(asset)) do
				t.ok(visual.name ~= "Counter", id .. " does not draw the old mesh")
			end
		end
		for _, id in ipairs({ "Sparkworks", "LandOffice" }) do
			local piece = TownModels.Piece(BacklogModels.Get(id), "Counter")
			t.ok(math.abs(piece.size.Y - 2.6) < EPS, id .. " mesh height")
			t.ok(math.abs(piece.size.Z - 3.6) < EPS, id .. " mesh depth")
			t.eq(piece.reupload, true, id)
		end
	end)

	t.test(
		"with the shop meshes loaded the part counter stays: visible, solid, the one Counter, its register on it",
		function()
			MeshKit.Reset()
			MeshKit.Override = function(_id, name, size)
				local part = roblox.Instance.new("MeshPart")
				part.Name = name
				part.Size = size
				return part
			end
			local ok, err = pcall(function()
				for _, kind in ipairs({ "ToolShed", "HearthAndHome" }) do
					local shop = build(kind)
					t.ok(shop:GetAttribute("TownMesh") ~= nil, kind .. " is dressed")
					local counter = counterOf(shop)
					t.ok(
						(counter.Size - BuildingArt.CounterSize).Magnitude < EPS,
						kind .. " counter is the part-built one"
					)
					t.ok(counter.CanCollide and counter.Transparency == 0, kind .. " counter is solid and drawn")
					local named, registers = 0, 0
					for _, p in ipairs(parts(shop)) do
						if p.Name == "Counter" and p.CanCollide then
							named += 1
						end
						if p.Name == "Register" then
							registers += 1
						end
					end
					t.eq(named, 1, kind .. ": one collidable Counter")
					t.eq(registers, 2, kind .. ": the register stays on the counter")
				end
			end)
			MeshKit.Override = nil
			MeshKit.Reset()
			if not ok then
				error(err, 0)
			end
		end
	)
end
