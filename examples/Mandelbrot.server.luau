-- Mandelbrot -- an infinitely-zooming fractal via :Shader.
--
-- For each pixel, iterate z = z^2 + c and colour by how long it takes to escape - the classic
-- Mandelbrot set. The view slowly zooms toward a detailed point on the edge, so new structure
-- keeps unfolding. Pure procedural generation, one Shader call per frame. Drop in
-- ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 64, 64
local MAX_ITER = 60

local part = Instance.new("Part")
part.Name = "IMGNMandelbrot"
part.Size = Vector3.new(13, 13, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

-- a pretty point on the boundary to zoom toward
local targetX, targetY = -0.743643887, 0.131825904
local scale = 1.5

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 15 then
		return
	end
	accumulator = 0

	canvas:Shader(function(px, py)
		-- map pixel -> complex plane around the target at the current zoom
		local cr = targetX + (px / W - 0.5) * scale
		local ci = targetY + (py / H - 0.5) * scale

		local zr, zi = 0, 0
		local iter = 0
		while iter < MAX_ITER and zr * zr + zi * zi <= 4 do
			zr, zi = zr * zr - zi * zi + cr, 2 * zr * zi + ci
			iter += 1
		end

		if iter >= MAX_ITER then
			return Color3.new(0, 0, 0) -- inside the set
		end
		return Color3.fromHSV((iter / MAX_ITER + 0.6) % 1, 0.9, 1)
	end)
	canvas:Render()

	scale *= 0.95 -- zoom in
	if scale < 1e-4 then
		scale = 1.5 -- reset before float precision falls apart
	end
end)

print("Mandelbrot: a self-zooming fractal on a 64x64 canvas")
