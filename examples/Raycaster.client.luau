-- Raycaster -- a Wolfenstein-style pseudo-3D renderer, drawn from GUI frames.
--
-- For every screen column we cast a ray across a grid map (DDA), find the wall it hits, and draw
-- a vertical slice whose height is inverse to the distance - near walls are tall, far walls
-- short. Ceiling and floor fill the rest. Walk with W/S, turn with A/D (or arrow keys). A real
-- first-person view with no EditableImage in sight. Drop in StarterPlayerScripts with IMGN under
-- ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 84, 64
local MOVE_SPEED = 3.0 -- map cells per second
local TURN_SPEED = 2.4 -- radians per second

local MAP = {
	"################",
	"#..............#",
	"#..##......##..#",
	"#..#........#..#",
	"#..............#",
	"#....######....#",
	"#..............#",
	"#..#........#..#",
	"#..#........#..#",
	"#..............#",
	"#....##..##....#",
	"#..............#",
	"#..##......##..#",
	"#..............#",
	"#..............#",
	"################",
}
local MAP_W, MAP_H = #MAP[1], #MAP

local function isWall(mx, my)
	if mx < 0 or my < 0 or mx >= MAP_W or my >= MAP_H then
		return true
	end
	return string.sub(MAP[my + 1], mx + 1, mx + 1) == "#"
end

local part = Instance.new("Part")
part.Name = "IMGNRaycaster"
part.Size = Vector3.new(16, 16 * H / W, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

-- player: position, facing direction, and a camera plane (FOV) perpendicular to it
local posX, posY = 8.5, 8.5
local dirX, dirY = 1, 0
local planeX, planeY = 0, 0.66

local CEILING = Color3.fromRGB(30, 35, 55)
local FLOOR = Color3.fromRGB(40, 35, 30)

local function render()
	for x = 0, W - 1 do
		-- ray direction for this column
		local cameraX = 2 * x / W - 1
		local rayX = dirX + planeX * cameraX
		local rayY = dirY + planeY * cameraX

		local mapX, mapY = math.floor(posX), math.floor(posY)
		local deltaX = if rayX == 0 then 1e30 else math.abs(1 / rayX)
		local deltaY = if rayY == 0 then 1e30 else math.abs(1 / rayY)

		local stepX, stepY, sideX, sideY
		if rayX < 0 then
			stepX = -1
			sideX = (posX - mapX) * deltaX
		else
			stepX = 1
			sideX = (mapX + 1 - posX) * deltaX
		end
		if rayY < 0 then
			stepY = -1
			sideY = (posY - mapY) * deltaY
		else
			stepY = 1
			sideY = (mapY + 1 - posY) * deltaY
		end

		-- DDA: march cell to cell until we hit a wall
		local side = 0
		while not isWall(mapX, mapY) do
			if sideX < sideY then
				sideX += deltaX
				mapX += stepX
				side = 0
			else
				sideY += deltaY
				mapY += stepY
				side = 1
			end
		end

		-- perpendicular distance avoids the fisheye warp
		local dist
		if side == 0 then
			dist = sideX - deltaX
		else
			dist = sideY - deltaY
		end
		dist = math.max(dist, 0.0001)

		local lineHeight = math.floor(H / dist)
		local drawStart = math.max(math.floor(-lineHeight / 2 + H / 2), 0)
		local drawEnd = math.min(math.floor(lineHeight / 2 + H / 2), H - 1)

		-- shade by distance, and darken N/S faces so corners read
		local shade = math.clamp(1 - dist / 12, 0.15, 1)
		if side == 1 then
			shade *= 0.65
		end
		local wall = Color3.fromRGB(
			math.floor(180 * shade),
			math.floor(120 * shade),
			math.floor(90 * shade)
		)

		-- ceiling, wall slice, floor
		if drawStart > 0 then
			canvas:DrawLine(x, 0, x, drawStart - 1, CEILING)
		end
		canvas:DrawLine(x, drawStart, x, drawEnd, wall)
		if drawEnd < H - 1 then
			canvas:DrawLine(x, drawEnd + 1, x, H - 1, FLOOR)
		end
	end
	canvas:Render()
end

local function tryMove(nx, ny)
	if not isWall(math.floor(nx), math.floor(posY)) then
		posX = nx
	end
	if not isWall(math.floor(posX), math.floor(ny)) then
		posY = ny
	end
end

RunService.RenderStepped:Connect(function(dt)
	local forward = 0
	local turn = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		forward += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		forward -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		turn += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		turn -= 1
	end

	if forward ~= 0 then
		local d = forward * MOVE_SPEED * dt
		tryMove(posX + dirX * d, posY + dirY * d)
	end
	if turn ~= 0 then
		local a = -turn * TURN_SPEED * dt
		local cos, sin = math.cos(a), math.sin(a)
		dirX, dirY = dirX * cos - dirY * sin, dirX * sin + dirY * cos
		planeX, planeY = planeX * cos - planeY * sin, planeX * sin + planeY * cos
	end

	render()
end)

print("Raycaster: W/S to walk, A/D to turn")
