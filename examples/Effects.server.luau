-- Effects -- the same little scene shown through every post-processing effect, side by side.
--
-- One canvas split into a 4x4 grid of :Query regions; each region draws the scene, then applies a
-- different effect (the dynamic ones - glitch/wave/grain - animate). Drop in ServerScriptService
-- with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local GRID = 4
local CELL = 40
local SIZE = GRID * CELL

local part = Instance.new("Part")
part.Name = "IMGNEffects"
part.Size = Vector3.new(16, 16, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Color = Color3.new(0, 0, 0)
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(SIZE, SIZE) })

-- a recognisable little scene to filter
local function scene(r)
	local W, H = r.Width, r.Height
	r:Shader(function(x, y)
		return Color3.fromHSV(x / W * 0.8, 0.7, 0.35 + 0.5 * (y / H))
	end)
	r:DrawCircle(W * 0.36, H * 0.4, W * 0.22, Color3.fromRGB(255, 230, 90), true)
	r:DrawCircle(W * 0.66, H * 0.62, W * 0.16, Color3.fromRGB(90, 190, 255), true)
	r:DrawLine(0, H - 1, W - 1, 0, Color3.new(1, 1, 1))
end

local effects = {
	{ "ORIG" },
	{ "CRT", "CRT" },
	{ "GLITCH", "Glitch" },
	{ "HOLO", "Hologram" },
	{ "EDGES", "Edges" },
	{ "WAVE", "Wave" },
	{ "BLOOM", "Bloom" },
	{ "SCAN", "Scanlines" },
	{ "CHROMA", "Chromatic", 2 },
	{ "VIGN", "Vignette" },
	{ "GRAIN", "Grain" },
	{ "ASCII", "ASCII" },
	{ "GRAY", "Grayscale" },
	{ "INVERT", "Invert" },
	{ "POSTER", "Posterize", 4 },
	{ "TINT", "Tint", Color3.fromRGB(255, 120, 40), 0.5 },
}

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 4 then
		return
	end
	accumulator = 0

	for i, e in effects do
		local col = (i - 1) % GRID
		local row = math.floor((i - 1) / GRID)
		local r = canvas:Query(col * CELL + 1, row * CELL + 1, CELL - 2, CELL - 2)
		scene(r)
		if e[2] == "Wave" then
			r:Effect("Wave", { Amplitude = 2, Frequency = 0.5, Phase = os.clock() * 4 })
		elseif e[2] then
			r:Effect(e[2], e[3], e[4])
		end
		r:Text(e[1], 1, 1, Color3.new(1, 1, 1)) -- label on top
	end

	canvas:Render()
end)

print("Effects: every post-processing effect on the same scene (CRT, glitch, hologram, edges, …)")
