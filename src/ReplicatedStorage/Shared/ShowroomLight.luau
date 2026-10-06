--!strict
-- ShowroomLight: how bright the Dealership's showroom may be. Pure data. The
-- first showroom lit its strips at brightness 1.0 range 26 and its plinth
-- lanterns at 1.4 range 17; it read far brighter than the other shops at night,
-- so every light and glow in it was cut by about 30% (Connor, store polish).
-- Max* are the caps a spec pins on every Light in the hall and its lot.

local ShowroomLight = {}

ShowroomLight.MaxBrightness = 1 -- no showroom light is brighter than this
ShowroomLight.MaxRange = 22 -- or reaches further than this (studs)

ShowroomLight.StripBrightness = 0.7 -- the PointLight on each ceiling strip (was 1.0)
ShowroomLight.StripRange = 18 -- (was 26)
ShowroomLight.SpotBrightness = 0.65 -- the SpotLight over each bay
ShowroomLight.SpotRange = 20
ShowroomLight.LanternBrightness = 1 -- the lamp posts on the plinths (was 1.4)
ShowroomLight.LanternRange = 12 -- (was 17)
ShowroomLight.StripColor = Color3.fromRGB(214, 201, 176) -- the strip's neon (was 255, 241, 214)

return ShowroomLight
