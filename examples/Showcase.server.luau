-- Showcase -- the headline demo, self-contained (builds its own part).
--
-- This is what `place.project.json` loads: open the dev place, press Play, and an
-- animated procedural canvas appears in the air with zero setup. It shows every
-- pillar of IMGN at once -- Surface mounting, a static drawn scene, and a per-frame
-- :Shader sweep -- all from GUI Frames, no EditableImage, no verification.
--
-- Build & run from the command line:
--   rojo build place.project.json -o IMGN.rbxl   (then open IMGN.rbxl and Play)
-- or live-sync:
--   rojo serve place.project.json                (connect the Rojo Studio plugin)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local RESOLUTION = 48

-- 1. A floating screen to draw on -- made here so the demo needs nothing in the place.
local screen = Instance.new("Part")
screen.Name = "IMGNScreen"
screen.Size = Vector3.new(12, 12, 1)
screen.Position = Vector3.new(0, 14, -16)
screen.Anchored = true
screen.CanCollide = false
screen.Color = Color3.new(0, 0, 0)
screen.Material = Enum.Material.SmoothPlastic
screen.Parent = workspace

-- 2. Mount a canvas onto its front face. IMGN.Surface builds the SurfaceGui for us.
local canvas = IMGN.Surface(screen, Enum.NormalId.Front, {
	Resolution = Vector2.new(RESOLUTION, RESOLUTION),
})

-- 3. A static frame border drawn once with the rect primitive.
canvas:DrawRect(0, 0, RESOLUTION, RESOLUTION, Color3.fromRGB(20, 20, 30), true)
canvas:DrawRect(1, 1, RESOLUTION - 2, RESOLUTION - 2, Color3.fromRGB(80, 200, 255), false)

-- 4. Animate a plasma field with :Shader -- the procedural path. Throttled to ~20fps so a
--    full-canvas redraw stays light (full-frame animation is the heavy case for a Frame-based
--    canvas; per-pixel drawing that only dirties a few pixels is far cheaper).
local INSET = 2
local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 20 then
		return
	end
	accumulator = 0

	local t = os.clock()
	canvas:Shader(function(x, y, color)
		-- Leave the drawn border untouched.
		if x < INSET or y < INSET or x >= RESOLUTION - INSET or y >= RESOLUTION - INSET then
			return nil
		end
		local v = math.sin(x * 0.3 + t)
			+ math.sin(y * 0.3 - t * 1.3)
			+ math.sin((x + y) * 0.2 + t * 0.7)
		local hue = (v + 3) / 6 -- map roughly -3..3 -> 0..1
		return Color3.fromHSV(hue % 1, 0.8, 1)
	end)
	canvas:Render()
end)

print("Showcase: animated plasma canvas spawned at " .. tostring(screen.Position) .. " -- no EditableImage used")
