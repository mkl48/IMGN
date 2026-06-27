-- AppBounce -- the App engine: many bodies bouncing off the walls AND each other.
--
-- Everything the bouncing-ball script did by hand is now "spawn Objects, app:Start()". The App
-- integrates velocity, resolves wall + object-object collisions, and redraws only what moved.
-- A center Wall (Preset "Wall" = anchored, solid) shows immovable collision. Drop in
-- ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local SIZE = 96

local part = Instance.new("Part")
part.Name = "IMGNBounce"
part.Size = Vector3.new(16, 16, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

-- App owns the canvas it builds; Background is what bodies erase back to each frame.
local app = IMGN.App({
	Canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(SIZE, SIZE) }),
	Background = Color3.fromRGB(12, 12, 20),
})

-- A static obstacle in the middle. "Wall" = anchored + collidable: balls bounce, it never moves.
app:Object({ Position = Vector2.new(SIZE / 2, SIZE / 2), Preset = "Wall" })
	:Rect(Vector2.new(-3, -22), Vector2.new(6, 44), Color3.fromRGB(90, 90, 120))

-- A handful of balls with random headings and colours.
local PALETTE = {
	Color3.fromRGB(0, 170, 255),
	Color3.fromRGB(255, 90, 120),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(200, 120, 255),
}

for i = 1, 5 do
	local angle = math.random() * math.pi * 2
	local speed = math.random(28, 52) -- pixels per second
	app:Object({
		Position = Vector2.new(math.random(12, SIZE - 12), math.random(12, SIZE - 12)),
		Velocity = Vector2.new(math.cos(angle) * speed, math.sin(angle) * speed),
		Bounce = 1,
	}):Circle(Vector2.zero, 5, PALETTE[i])
end

app:Start()

print("AppBounce: 5 balls bouncing off the walls and each other, around a center wall")
