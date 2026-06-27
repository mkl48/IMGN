-- BloodDrip -- realistic dripping blood on a wall, drawn from GUI frames.
--
-- A Liquid simulation (Preset "Blood") runs on a SurfaceGui canvas: splats land, drip down in
-- rivulets, pool at the bottom, and dry from red to brown. Self-contained - builds its own wall
-- and periodically splatters it (as if it's getting hit). Drop in ServerScriptService with IMGN
-- under ReplicatedStorage.
--
-- To make it interactive, splat where a player hits: raycast to the wall, convert the hit point to
-- a canvas pixel, and call blood:Splat(px, py, amount, { Velocity = ... }).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 96, 120

-- a wall to bleed on
local wall = Instance.new("Part")
wall.Name = "BloodWall"
wall.Size = Vector3.new(16, 16 * H / W, 1)
wall.Position = Vector3.new(0, 14, -16)
wall.Anchored = true
wall.Color = Color3.fromRGB(230, 225, 215)
wall.Material = Enum.Material.SmoothPlastic
wall.Parent = workspace

-- Blood flows down the wall (Gravity (0,1) is the default). PixelGrid suits a fast-changing sim.
local blood = IMGN.Liquid({
	Canvas = IMGN.Surface(wall, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) }),
	Preset = "Blood",
})
blood:Start()

-- periodically get splattered, as if hit
task.spawn(function()
	while wall.Parent do
		task.wait(1 + math.random() * 1.5)
		local x = math.random(12, W - 12)
		local y = math.random(8, math.floor(H * 0.45)) -- upper area, so it has room to drip
		local amount = 2 + math.random() * 3
		blood:Splat(x, y, amount, {
			Spread = 5 + math.random() * 6,
			Velocity = Vector2.new((math.random() - 0.5) * 3, math.random() * 2),
		})
	end
end)

print("BloodDrip: a Liquid 'Blood' sim splattering + dripping down a wall, no EditableImage")
