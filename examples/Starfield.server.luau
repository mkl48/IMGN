-- Starfield -- a warp-speed flight through stars.
--
-- Each star has a 3D position; every frame its depth decreases (it rushes toward you), and it's
-- projected to the screen with perspective so it streaks outward from the centre and brightens as
-- it nears. Stars that pass the camera respawn far away. Drop in ServerScriptService with IMGN
-- under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 96, 96
local STARS = 90
local SPEED = 26 -- depth units per second

local part = Instance.new("Part")
part.Name = "IMGNStars"
part.Size = Vector3.new(14, 14, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

local cx, cy = W / 2, H / 2

local function spawn(star)
	star.x = (math.random() * 2 - 1) * W
	star.y = (math.random() * 2 - 1) * H
	star.z = math.random() * W + 1
end

local stars = {}
for i = 1, STARS do
	stars[i] = {}
	spawn(stars[i])
end

local function project(star)
	local k = W / star.z
	return cx + star.x * k / W * cx, cy + star.y * k / H * cy
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	local step = accumulator
	accumulator = 0

	canvas:Fill(Color3.new(0, 0, 0))

	for _, star in stars do
		-- erase nothing (full clear above); advance depth
		star.z -= SPEED * step
		if star.z <= 0.5 then
			spawn(star)
			star.z = W
		end

		local sx, sy = project(star)
		if sx >= 0 and sx < W and sy >= 0 and sy < H then
			-- closer = brighter and bigger
			local b = math.clamp(1 - star.z / W, 0, 1)
			local shade = Color3.new(b, b, b)
			canvas:SetPixel(sx, sy, shade)
			if b > 0.6 then
				-- a little cross for the nearest stars
				canvas:SetPixel(sx + 1, sy, shade)
				canvas:SetPixel(sx - 1, sy, shade)
				canvas:SetPixel(sx, sy + 1, shade)
				canvas:SetPixel(sx, sy - 1, shade)
			end
		end
	end

	canvas:Render()
end)

print("Starfield: 90 stars at warp on a 96x96 canvas")
