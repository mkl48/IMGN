-- Particles -- a fire that burns, with sparks bursting off it - all from GUI frames.
--
-- Two emitters share one canvas: a continuous Fire and periodic Sparks bursts. Drop in
-- ServerScriptService with IMGN under ReplicatedStorage. Try other presets: Rain, Snow,
-- Explosion, Confetti.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 72, 72

local part = Instance.new("Part")
part.Name = "IMGNParticles"
part.Size = Vector3.new(14, 14, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Color = Color3.new(0, 0, 0)
part.Parent = workspace

-- one canvas, two emitters drawing on it
local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

local fire = IMGN.Particles({ Canvas = canvas, Preset = "Fire", Position = Vector2.new(W / 2, H - 6) })
fire:Start()

local sparks = IMGN.Particles({ Canvas = canvas, Preset = "Sparks" })
task.spawn(function()
	while part.Parent do
		task.wait(1.2 + math.random())
		sparks.Position = Vector2.new(math.random(12, W - 12), math.random(10, H - 24))
		sparks:Burst(28)
	end
end)

print("Particles: a fire with sparks - swap Preset for Rain/Snow/Explosion/Confetti")
