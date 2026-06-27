-- KillBrick -- step on it, die, and spray blood that drips down whatever it lands on.
--
-- Builds a red kill brick surrounded by a few walls/ramps. When a character touches the brick,
-- IMGN.Blood kills them and bursts a spray of real 3D droplets; each droplet falls, lands on a
-- surface, turns it into a dripping IMGN canvas, and runs the blood sim - drips run downhill, so
-- they streak down walls and slide along ramps. Drop in ServerScriptService with IMGN under
-- ReplicatedStorage, and walk a character onto the brick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local function makePart(name, size, cframe, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = workspace
	return p
end

-- surrounding surfaces for blood to land + drip on: two walls and a slope
makePart("Wall1", Vector3.new(24, 16, 1), CFrame.new(0, 8, -10), Color3.fromRGB(225, 222, 214))
makePart("Wall2", Vector3.new(1, 16, 24), CFrame.new(-12, 8, 0), Color3.fromRGB(225, 222, 214))
makePart("Ramp", Vector3.new(16, 1, 12), CFrame.new(8, 5, 6) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(210, 206, 198))

-- the kill brick
local brick = makePart("KillBrick", Vector3.new(8, 1, 8), CFrame.new(0, 0.5, 0), Color3.fromRGB(150, 0, 0))
brick.Material = Enum.Material.Neon

IMGN.Blood.KillBrick(brick, {
	Droplets = 18,
	Spread = 18,
	Up = 26,
	Amount = 4,
})

print("KillBrick: walk a character onto the red brick - blood sprays, lands, and drips downhill")
