-- DoomFire -- the classic PSX Doom fire effect, drawn from GUI frames.
--
-- An intensity grid: the bottom row is pinned to maximum, and every frame each cell pulls from
-- the cell below it minus a little random decay, drifting sideways. Map intensity to a
-- black -> red -> yellow -> white palette and you get rolling flame. Drop in ServerScriptService
-- with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 64, 48
local MAX = 36 -- top of the intensity scale

local part = Instance.new("Part")
part.Name = "IMGNFire"
part.Size = Vector3.new(14, 11, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

-- intensity 0..MAX -> colour (black -> red -> yellow -> white)
local palette = {}
for i = 0, MAX do
	local t = i / MAX
	palette[i] = Color3.new(
		math.clamp(t * 3, 0, 1),
		math.clamp(t * 3 - 1, 0, 1),
		math.clamp(t * 3 - 2, 0, 1)
	)
end

-- flat WxH grid; start cold, pin the bottom row to MAX (the fuel)
local fire = table.create(W * H, 0)
for x = 0, W - 1 do
	fire[(H - 1) * W + x + 1] = MAX
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	accumulator = 0

	-- propagate upward
	for x = 0, W - 1 do
		for y = 1, H - 1 do
			local src = y * W + x + 1
			local intensity = fire[src]
			if intensity == 0 then
				fire[src - W] = 0
			else
				local rnd = math.random(0, 3)
				local dstx = math.clamp(x - rnd + 1, 0, W - 1)
				fire[(y - 1) * W + dstx + 1] = math.max(intensity - (rnd % 2), 0)
			end
		end
	end

	-- paint
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			canvas:SetPixel(x, y, palette[fire[y * W + x + 1]])
		end
	end
	canvas:Render()
end)

print("DoomFire: rolling flame on a 64x48 canvas, no EditableImage")
