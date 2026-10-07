--!nocheck
-- BoxWindows: the Lower and Higher quality choice applied to a real shop box
-- (built by BoxService, the way the game builds it). LOWER takes the item copy
-- out of the windows and tints the glass; HIGHER leaves the box exactly as the
-- server made it; switching back restores it. Either way the box is the same
-- thing to the game: the same hover marks, attributes, size, collision, tag
-- and part layout (everything but the item copy and the glass colour).
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local BoxWindows = t.shared("BoxWindows")
	local BoxLogic = t.shared("BoxLogic")
	local HoverTag = t.shared("HoverTag")
	local QualityBudgets = t.shared("QualityBudgets")
	local QualityProfile = t.shared("QualityProfile")

	local function makeBoxes()
		local loader = t.loader({
			mocks = {
				ShopService = {
					Loop = function()
						return 2
					end,
					ChargeAndGrant = function()
						return true, "thanks", nil
					end,
				},
				ProfileService = {
					GetProfile = function()
						return nil
					end,
				},
			},
		})
		local Box = loader:server("BoxService")
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 2, 6)
		counter.CFrame = CFrame.new(0, 3, 0)
		local out = {}
		for i, slotId in ipairs({
			"toolshed-SteelAxe",
			"toolshed-Millmaster200L",
			"toolshed-PlanerSteam",
			"hearth-Lantern",
			"hearth-Shed",
		}) do
			local rec = Box.Make({ slotId = slotId, cf = CFrame.new(-8 + i * 3, 5, 0), counter = counter })
			table.insert(out, rec)
		end
		return out
	end

	local function attributes(inst)
		local out = {}
		for k, v in pairs(inst:GetAttributes()) do
			out[k] = v
		end
		return out
	end

	-- Everything a player, the server or the hover tag could see on a box, except
	-- the item copy (Contents) and the glass's colour and transparency.
	local function snapshot(model)
		local snap = { attributes = attributes(model), parts = {}, tags = {}, hover = HoverTag.SpecOf(model) }
		for _, tag in ipairs({ "ShopBox", "HoverItem" }) do
			snap.tags[tag] = model:HasTag(tag)
		end
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") then
				local isGlass = d.Name == "Window" or d.Name == "WindowTop" or d.Name == "SideWindow"
				snap.parts[d.Name] = {
					size = d.Size,
					cframe = d.CFrame,
					canCollide = d.CanCollide,
					canQuery = d.CanQuery,
					canTouch = d.CanTouch,
					massless = d.Massless,
					anchored = d.Anchored,
					group = d.CollisionGroup,
					material = d.Material,
					transparency = if isGlass or d.Name == "Box" then nil else d.Transparency,
					color = if isGlass then nil else d.Color,
					attributes = attributes(d),
				}
			end
		end
		return snap
	end

	local function count(model)
		local n, contents = 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				if d:IsDescendantOf(model:FindFirstChild("Contents") or Instance.new("Model")) then
					contents += 1
				end
			end
		end
		return n, contents
	end

	t.test("LOWER takes the item out of every window and tints the glass; HIGHER keeps the box as built", function()
		for _, rec in ipairs(makeBoxes()) do
			local model = rec.model
			local label = rec.slotId
			local total, items = count(model)
			t.ok(items >= 1, label .. " is built with an item in its window")
			t.ok(model:FindFirstChild("Contents") ~= nil)
			local windows = {}
			for _, name in ipairs(BoxWindows.WindowNames) do
				local pane = model:FindFirstChild(name)
				if pane then
					windows[name] = { color = pane.Color, transparency = pane.Transparency }
				end
			end
			t.ok(windows.Window ~= nil and windows.WindowTop ~= nil)

			-- HIGHER: nothing at all changes.
			local as_built = snapshot(model)
			t.eq(BoxWindows.Apply(model, true), false, label .. ": Higher on a fresh box changes nothing")
			t.eq(snapshot(model), as_built)
			t.eq((count(model)), total)
			t.ok(BoxWindows.ShowsItem(model))
			t.eq(BoxWindows.IsTinted(model), false)

			-- LOWER: the item is gone, the glass is the accent colour, nothing else moved.
			t.eq(BoxWindows.Apply(model, false), true)
			t.eq(model:FindFirstChild("Contents"), nil, label .. ": no item copy in the window")
			t.eq(BoxWindows.ShowsItem(model), false)
			t.eq(BoxWindows.IsTinted(model), true)
			local lowTotal, lowItems = count(model)
			t.eq(lowItems, 0)
			t.eq(lowTotal, total - items, label .. ": exactly the item's parts are gone")
			t.ok(lowTotal <= BoxLogic.ShellPartCap, label .. " is just the shell now: " .. lowTotal)
			local accent = model:FindFirstChild("Strip").Color
			for name, was in pairs(windows) do
				local pane = model:FindFirstChild(name)
				t.eq(pane.Color, accent, label .. " " .. name .. " is tinted in the item's accent colour")
				t.ok(math.abs(pane.Transparency - BoxWindows.TintTransparency) < 1e-3)
				t.ok(pane.Transparency < 1 and pane.Transparency > 0, "still glass, not a hole")
				t.ok(pane.Color ~= was.color, "and it did change")
				t.eq(pane.Size, snapshot(model).parts[name].size)
			end
			-- Hover marks, attributes, tags, sizes and collisions are identical.
			t.eq(snapshot(model), as_built, label .. ": everything else is as the server built it")
			t.eq(HoverTag.SpecOf(model), as_built.hover, label .. ": the same hover tag")
			t.ok(model:HasTag("ShopBox"))
			t.eq(model:GetAttribute("ForSale"), true)
			t.eq(model:GetAttribute("HoverKind"), rec.itemKind)
			t.eq(model:GetAttribute("HoverId"), rec.itemId)
			t.ok(model:GetAttribute("BoxUid") ~= nil)
			t.eq(rec.part.CanCollide, true, "the box still collides, is aimed at and carried")
			t.eq(rec.part.CanQuery, true)
			t.eq(model:FindFirstChild("Window").CanQuery, true, "the glass is still aimed through")

			-- Again is a no-op.
			t.eq(BoxWindows.Apply(model, false), false)
			t.eq((count(model)), lowTotal)

			-- Back to HIGHER: the same item, the same glass.
			t.eq(BoxWindows.Apply(model, true), true)
			t.ok(model:FindFirstChild("Contents") ~= nil, label .. ": the item is back")
			t.eq((count(model)), total)
			t.eq(BoxWindows.IsTinted(model), false)
			for name, was in pairs(windows) do
				local pane = model:FindFirstChild(name)
				t.eq(pane.Color, was.color, name .. " is clear glass again")
				t.ok(math.abs(pane.Transparency - was.transparency) < 1e-3)
			end
			t.eq(snapshot(model), as_built, label .. ": exactly as it was built")
			-- The item itself is still decor: weightless, no collision, never aimed at.
			for _, p in ipairs(model:FindFirstChild("Contents"):GetDescendants()) do
				if p:IsA("BasePart") then
					t.eq(p.CanCollide, false)
					t.eq(p.CanQuery, false)
					t.eq(p.Massless, true)
				end
			end
		end
	end)

	t.test("the budgets pick it: low strips, medium and high keep, by QualityBudgets.BoxContents", function()
		local model = makeBoxes()[1].model
		local _, items = count(model)
		for _, tier in ipairs({ "low", "medium", "high" }) do
			BoxWindows.Apply(model, QualityBudgets.For(tier).BoxContents)
			local _, now = count(model)
			t.eq(now, if tier == "low" then 0 else items, tier .. " window items")
		end
		-- And through the player's choice: Lower is low, Higher on a phone is medium (items shown).
		for _, case in ipairs({
			{ "low", "high", false },
			{ "low", "low", false },
			{ "high", "high", true },
			{ "high", "low", true },
			{ "high", "medium", true },
			{ "unset", "high", true },
			{ "unset", "low", false },
		}) do
			local tier = QualityProfile.TierFor(case[1], case[2])
			t.eq(
				QualityBudgets.For(tier).BoxContents,
				case[3],
				string.format("saved %s on a %s device shows items: %s", case[1], case[2], tostring(case[3]))
			)
		end
	end)

	t.test("a box opened on the server (no item, no windows) is left alone either way", function()
		local rec = makeBoxes()[1]
		local BoxArt = t.load("ReplicatedStorage/Shared/Art/BoxArt")
		BoxArt.Open(rec.model)
		t.eq(rec.model:FindFirstChild("Contents"), nil)
		t.eq(BoxWindows.Apply(rec.model, false), false, "nothing to strip")
		t.eq(BoxWindows.Apply(rec.model, true), false, "nothing to restore")
		t.eq(rec.model:GetAttribute("Open"), true)
		-- A box that was stripped and is opened on the server meanwhile does not get its item back.
		local second = makeBoxes()[2]
		BoxWindows.Apply(second.model, false)
		BoxArt.Open(second.model)
		BoxWindows.Apply(second.model, true)
		t.eq(second.model:FindFirstChild("Contents"), nil, "an opened box stays empty")
	end)

	t.test("the client module applies it on the ShopBox tag and when the choice changes", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QualityDressing.luau")
		t.ok(string.find(source, "GetInstanceAddedSignal(BOX_TAG)", 1, true), "boxes that stream in later are dressed")
		t.ok(string.find(source, "Quality.OnChange(redress)", 1, true), "and a change of choice redresses every box")
		t.ok(string.find(source, "BoxWindows.Apply(box, Quality.Budget().BoxContents)", 1, true))
		t.ok(string.find(source, 'child.Name == "Contents"', 1, true), "a late Contents is dressed too")
		-- The server builds one box: BoxService does not read the choice.
		local box = fs.readFile("src/ServerScriptService/BoxService.luau")
		t.eq(string.find(box, "BoxContents", 1, true), nil)
		t.eq(string.find(box, "Quality", 1, true), nil)
	end)
end
