-- Dither -- a colourful plasma reduced to a few colours, cycling through retro palettes.
--
-- Each tick it paints a full-colour animated plasma with :Shader, then Floyd-Steinberg dithers it
-- to the current palette and renders - so you see the same image as GameBoy green, 1-bit, CGA, etc.
-- Drop in ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 64, 64

local part = Instance.new("Part")
part.Name = "IMGNDither"
part.Size = Vector3.new(13, 13, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local palettes = {
	{ name = "GameBoy", colors = { rgb(15, 56, 15), rgb(48, 98, 48), rgb(139, 172, 15), rgb(155, 188, 15) } },
	{ name = "1-bit", colors = IMGN.Palette.Grayscale(2) },
	{ name = "Grayscale", colors = IMGN.Palette.Grayscale(5) },
	{ name = "CGA", colors = { rgb(0, 0, 0), rgb(255, 85, 255), rgb(85, 255, 255), rgb(255, 255, 255) } },
}

local index = 1
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 6 then
		return
	end
	accumulator = 0

	-- 1) full-colour animated plasma
	local t = os.clock()
	canvas:Shader(function(x, y)
		local v = math.sin(x * 0.2 + t) + math.sin(y * 0.25 - t) + math.sin((x + y) * 0.15 + t * 0.6)
		return Color3.fromHSV(((v + 3) / 6) % 1, 0.85, 1)
	end)

	-- 2) crush it down to the current palette
	canvas:Dither(palettes[index].colors)
	canvas:Render()
end)

-- cycle palette every few seconds
task.spawn(function()
	while part.Parent do
		task.wait(4)
		index = index % #palettes + 1
		print("Dither: palette ->", palettes[index].name)
	end
end)

print("Dither: animated plasma, dithered through GameBoy / 1-bit / grayscale / CGA palettes")
