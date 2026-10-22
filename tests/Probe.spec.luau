--!nocheck
return function(t)
	t.test("probe", function()
		local w = t.support("WorldBuild").Get(t)
		local p = w.map.ToolShed.Counter:FindFirstChild("ShopPoint")
		print(
			p,
			pcall(function()
				return p.WorldPosition
			end)
		)
		print(pcall(function()
			return p.CFrame
		end))
	end)
end
