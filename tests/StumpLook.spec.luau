--!nocheck
-- T416 item 5: a decor stump (Greenery.Stump, the roadside scatter) has the species' core hex on its cut face
-- and bark on its sides, and nothing about it is white. Written first.
return function(t)
	local Greenery = t.load("ReplicatedStorage/Shared/Art/Greenery")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local WoodData = t.load("ReplicatedStorage/Shared/WoodData")

	local REGIONS = { "starter", "hills", "snow", "gloam", "volcano", "country", "mesa", "bayou", "meadow" }

	local function luma(c)
		return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	end
	-- White or near white: bright overall, or every channel above 0.92.
	local function nearWhite(c)
		return luma(c) > 0.9 or (c.R > 0.92 and c.G > 0.92 and c.B > 0.92)
	end

	local function eachStump(fn)
		for _, region in ipairs(REGIONS) do
			for variant = 0, 11 do
				fn(Greenery.Stump(region, variant, 3), region, variant)
			end
		end
	end

	t.test("the cut face equals the species core hex, for every species a stump can be", function()
		local seen = {}
		eachStump(function(model, region, variant)
			local id = model:GetAttribute("Species")
			t.ok(type(id) == "string", region .. variant .. " names its species")
			local def = WoodData.Get(id)
			t.ok(def ~= nil, "a real species " .. tostring(id))
			local core = TreeArt.Core(def)
			local top = model:FindFirstChild("StumpTop")
			t.eq(top.Color, core, region .. " " .. id .. " cut face is the core hex")
			seen[id] = true
		end)
		t.ok(seen.oak and seen.pine, "the common species are covered")
		t.ok(not seen.frostwood, "frostwood (an ice-white core) is not a decor stump")
	end)

	t.test("sides are bark, never white", function()
		eachStump(function(model, region, variant)
			local def = WoodData.Get(model:GetAttribute("Species"))
			local body = model:FindFirstChild("StumpBody")
			t.ok(not nearWhite(body.Color), region .. variant .. " sides read white")
			t.ok(luma(body.Color) <= 0.6, region .. variant .. " sides are bark-dark: " .. luma(body.Color))
			if luma(def.trunkColor) <= 0.6 then
				for _, ch in ipairs({ "R", "G", "B" }) do
					t.ok(math.abs(body.Color[ch] - def.trunkColor[ch]) <= 0.08, region .. variant .. " bark colour")
				end
			end
		end)
	end)

	t.test("no part of any stump is white or near white", function()
		eachStump(function(model, region, variant)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok(not nearWhite(d.Color), region .. variant .. " " .. d.Name .. " is white")
				end
			end
		end)
	end)

	t.test("still a square Block of Wood that collides, with a cut face and a crack", function()
		eachStump(function(model)
			local body = model:FindFirstChild("StumpBody")
			t.eq(body.Material, t.roblox.Enum.Material.Wood)
			t.ok(math.abs(body.Size.X - body.Size.Z) < 1e-6)
			t.ok(model:FindFirstChild("StumpTop") and model:FindFirstChild("StumpCrack"))
		end)
	end)
end
