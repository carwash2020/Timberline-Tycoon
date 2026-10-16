--!nocheck
-- Wood colours (WORLD-T323): every new wood's leaf and core colour is at least
-- 18 CIE76 delta E (sRGB, D65, Lab) from every older wood's leaf, bark and core
-- colour, and its bark at least 10, so two woods are never confused at a glance.
return function(t)
	local WoodData = t.shared("WoodData")

	local function lin(c)
		return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end

	local function lab(hex)
		local h = string.gsub(hex, "#", "")
		local r = lin(tonumber(string.sub(h, 1, 2), 16) / 255)
		local g = lin(tonumber(string.sub(h, 3, 4), 16) / 255)
		local b = lin(tonumber(string.sub(h, 5, 6), 16) / 255)
		local x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
		local y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
		local z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
		local function f(v)
			return if v > 216 / 24389 then v ^ (1 / 3) else (24389 / 27 * v + 16) / 116
		end
		local fx, fy, fz = f(x), f(y), f(z)
		return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)
	end

	local function deltaE(a, b)
		local l1, a1, b1 = lab(a)
		local l2, a2, b2 = lab(b)
		return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
	end

	local function hexOf(color3)
		return "#" .. color3:ToHex()
	end

	-- The three colours a wood is known by.
	local function colours(def)
		return {
			leaf = hexOf(def.leafColor),
			bark = hexOf(def.trunkColor),
			core = def.v2.core,
		}
	end

	local NEW = { cherry = true, willow = true }

	t.test("the delta E maths: identical is 0, black to white is 100", function()
		t.ok(deltaE("#336699", "#336699") < 1e-9)
		t.ok(math.abs(deltaE("#000000", "#FFFFFF") - 100) < 0.5)
	end)

	t.test(
		"a new wood's leaf and core are at least 18 from every older wood's leaf, bark and core; its bark at least 10",
		function()
			local lowest = {}
			for id in pairs(NEW) do
				local mine = colours(WoodData.Get(id))
				for _, other in ipairs(WoodData.All()) do
					if not NEW[other.id] then
						local theirs = colours(other)
						for _, kind in ipairs({ "leaf", "core" }) do
							for _, against in ipairs({ "leaf", "bark", "core" }) do
								local d = deltaE(mine[kind], theirs[against])
								lowest[id .. " " .. kind] = math.min(lowest[id .. " " .. kind] or math.huge, d)
								t.ok(
									d >= 18,
									string.format("%s %s vs %s %s: delta E %.1f", id, kind, other.id, against, d)
								)
							end
						end
						for _, against in ipairs({ "leaf", "bark", "core" }) do
							local d = deltaE(mine.bark, theirs[against])
							lowest[id .. " bark"] = math.min(lowest[id .. " bark"] or math.huge, d)
							t.ok(d >= 10, string.format("%s bark vs %s %s: delta E %.1f", id, other.id, against, d))
						end
					end
				end
			end
			for id in pairs(NEW) do
				print(
					string.format(
						"%s lowest delta E: leaf %.1f, core %.1f, bark %.1f",
						id,
						lowest[id .. " leaf"],
						lowest[id .. " core"],
						lowest[id .. " bark"]
					)
				)
			end
		end
	)

	t.test("the new cores are the approved ones and plain Wood", function()
		t.eq(WoodData.Get("cherry").v2.core, "#C9737A")
		t.eq(WoodData.Get("willow").v2.core, "#BFD6A0")
		for id in pairs(NEW) do
			t.eq(WoodData.Get(id).v2.coreMaterial, "Wood", id .. " core is Wood: no Neon, no glow")
			t.eq(WoodData.Get(id).v2.shape.glow, nil, id .. " has no glow")
		end
	end)
end
