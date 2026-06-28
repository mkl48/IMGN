-- Weather -- rain and snow particles falling across a surface, swapping every so often.
--
-- Shows the Rain/Snow particle presets (which spawn across the top edge) on a dark "sky". Drop in
-- ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 80, 96

local part = Instance.new("Part")
part.Name = "IMGNWeather"
part.Size = Vector3.new(13, 13 * H / W, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Color = Color3.fromRGB(18, 22, 34) -- a dark sky behind the drops
part.Material = Enum.Material.SmoothPlastic
part.Parent = workspace

-- particles draw on the canvas and erase to transparent, so the dark part shows through
local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

local rain = IMGN.Particles({ Canvas = canvas, Preset = "Rain" })
local snow = IMGN.Particles({ Canvas = canvas, Preset = "Snow" })

local raining = true
rain:Start()

task.spawn(function()
	while part.Parent do
		task.wait(8)
		raining = not raining
		if raining then
			snow:Stop()
			rain:Start()
			print("Weather: rain")
		else
			rain:Stop()
			snow:Start()
			print("Weather: snow")
		end
	end
end)

print("Weather: rain and snow falling across the surface (swaps every 8s)")
