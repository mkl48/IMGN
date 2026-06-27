-- Snake -- the classic, on a pixel grid with a bitmap-font scoreboard.
--
-- A grid of cells: the snake steps once per tick in the current heading, eats food to grow, and
-- resets on hitting a wall or itself. The top strip is a HUD drawn with Canvas:Text. Steer with
-- WASD or the arrow keys. Drop in StarterPlayerScripts with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local CELL = 6
local GW, GH = 16, 16
local HUD = 12 -- top strip for the score
local W, H = GW * CELL, HUD + GH * CELL
local TICK = 0.14 -- seconds per step

local BG = Color3.fromRGB(10, 14, 12)
local SNAKE = Color3.fromRGB(90, 220, 110)
local HEAD = Color3.fromRGB(180, 255, 180)
local FOOD = Color3.fromRGB(255, 80, 90)

local part = Instance.new("Part")
part.Name = "IMGNSnake"
part.Size = Vector3.new(14, 14 * H / W, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

local snake, dir, pending, food, score
local function spawnFood()
	while true do
		local fx, fy = math.random(0, GW - 1), math.random(0, GH - 1)
		local clear = true
		for _, c in snake do
			if c.x == fx and c.y == fy then
				clear = false
				break
			end
		end
		if clear then
			food = { x = fx, y = fy }
			return
		end
	end
end

local function reset()
	snake = { { x = 8, y = 8 }, { x = 7, y = 8 }, { x = 6, y = 8 } }
	dir = { x = 1, y = 0 }
	pending = dir
	score = 0
	spawnFood()
end
reset()

local function cell(cx, cy, color)
	canvas:DrawRect(cx * CELL, HUD + cy * CELL, CELL, CELL, color, true)
end

local function draw()
	canvas:Fill(BG)
	canvas:Text("SCORE " .. score, 2, 3, Color3.fromRGB(180, 200, 190))
	cell(food.x, food.y, FOOD)
	for i, c in snake do
		cell(c.x, c.y, if i == 1 then HEAD else SNAKE)
	end
	canvas:Render()
end
draw()

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	local key = input.KeyCode
	if (key == Enum.KeyCode.W or key == Enum.KeyCode.Up) and dir.y == 0 then
		pending = { x = 0, y = -1 }
	elseif (key == Enum.KeyCode.S or key == Enum.KeyCode.Down) and dir.y == 0 then
		pending = { x = 0, y = 1 }
	elseif (key == Enum.KeyCode.A or key == Enum.KeyCode.Left) and dir.x == 0 then
		pending = { x = -1, y = 0 }
	elseif (key == Enum.KeyCode.D or key == Enum.KeyCode.Right) and dir.x == 0 then
		pending = { x = 1, y = 0 }
	end
end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < TICK then
		return
	end
	accumulator = 0

	dir = pending
	local head = snake[1]
	local nx, ny = head.x + dir.x, head.y + dir.y

	-- wall or self collision -> reset
	if nx < 0 or ny < 0 or nx >= GW or ny >= GH then
		reset()
		draw()
		return
	end
	for _, c in snake do
		if c.x == nx and c.y == ny then
			reset()
			draw()
			return
		end
	end

	table.insert(snake, 1, { x = nx, y = ny })
	if nx == food.x and ny == food.y then
		score += 1
		spawnFood()
	else
		table.remove(snake) -- didn't eat: drop the tail
	end

	draw()
end)

print("Snake: WASD / arrow keys")
