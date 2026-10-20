--!nocheck
-- BoxPriceState (StarterPlayerScripts/BoxPriceState): the price printed on a shop
-- box is built by the server and shared, so the client colours it for the viewer:
-- CoinGold when the player's cash covers it, StopRed when not. Run against a fake
-- player (a Cash attribute with a change signal) and a fake CollectionService.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3

	local GOLD, RED = Color3.fromHex("#F2C14E"), Color3.fromHex("#D9534F")

	local function signal()
		local handlers = {}
		return {
			Connect = function(_, fn)
				table.insert(handlers, fn)
				return { Disconnect = function() end }
			end,
			fire = function(...)
				for _, fn in ipairs(handlers) do
					fn(...)
				end
			end,
		}
	end

	local function world(cash)
		local attrs = { Cash = cash }
		local cashChanged = signal()
		local player = {
			GetAttribute = function(_, name)
				return attrs[name]
			end,
			GetAttributeChangedSignal = function(_, name)
				assert(name == "Cash", "only Cash is watched")
				return cashChanged
			end,
		}
		local tagged, added = {}, signal()
		local loader = t.loader({
			services = {
				Players = { LocalPlayer = player },
				CollectionService = {
					GetTagged = function(_, tag)
						return if tag == "BoxPriceTag" then tagged else {}
					end,
					GetInstanceAddedSignal = function(_, tag)
						assert(tag == "BoxPriceTag")
						return added
					end,
				},
			},
		})
		local State = loader:load("StarterPlayer/StarterPlayerScripts/BoxPriceState")
		local BoxArt = loader:load("ReplicatedStorage/Shared/Art/BoxArt")
		local function box(price)
			local model = Instance.new("Model")
			local body = Instance.new("Part")
			body.Size = Vector3.new(3, 3, 3)
			body.CFrame = CFrame.new(0, 1.5, 0)
			body.Parent = model
			BoxArt.Dress(model, body, { name = "Thing", kind = "Axe", itemId = "SteelAxe", price = price })
			local plate = model:FindFirstChild("PriceTag")
			table.insert(tagged, plate)
			return plate, plate:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Price")
		end
		return {
			State = State,
			box = box,
			setCash = function(n)
				attrs.Cash = n
				cashChanged.fire()
			end,
			added = added,
		}
	end

	t.test("an affordable price is CoinGold and an unaffordable one StopRed, for a fake cash value", function()
		local w = world(50)
		local _, cheap = w.box(32)
		local _, dear = w.box(500)
		w.State.Start()
		t.eq(cheap.TextColor3, GOLD, "$32 with $50")
		t.eq(dear.TextColor3, RED, "$500 with $50")
		t.eq(dear.Text, "$500")
	end)

	t.test("a cash change recolours every box, and a new box is coloured when it arrives", function()
		local w = world(0)
		local _, a = w.box(100)
		w.State.Start()
		t.eq(a.TextColor3, RED)
		w.setCash(100)
		t.eq(a.TextColor3, GOLD, "exactly enough")
		w.setCash(99)
		t.eq(a.TextColor3, RED, "one short")
		local plate, late = w.box(150)
		w.added.fire(plate)
		t.eq(late.TextColor3, RED, "$150 with $99")
		local plate2, cheap = w.box(40)
		w.added.fire(plate2)
		t.eq(cheap.TextColor3, GOLD, "$40 with $99")
	end)
end
