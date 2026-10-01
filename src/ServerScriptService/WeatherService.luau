--!strict
-- WeatherService: the same weather on every server, from the clock
-- (Shared/WeatherSchedule): rain, storms with lightning, fog, snow, aurora,
-- ash. Publishes it as workspace attributes for clients to draw.
-- (Stub: the environment workstream fills this in.)

local WeatherService = {}

function WeatherService.Init(_worldFx: RemoteEvent) end

return WeatherService
