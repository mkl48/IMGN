-- GameOfLife -- Conway's Game of Life on the canvas.
--
-- Each cell lives or dies by its 8 neighbours: a live cell with 2-3 neighbours survives, a dead
-- cell with exactly 3 is born. Edges wrap (a torus). Starts from a random soup; reseeds if it
-- ever goes still. Drop in ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 72, 72
local ALIVE = Color3.fromRGB(120, 255, 160)
local DEAD = Color3.fromRGB(8, 12, 16)

local part = Instance.new("Part")
part.Name = "IMGNLife"
part.Size = Vector3.new(13, 13, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

local function index(x, y)
	return (y % H) * W + (x % W) + 1
end

local grid = table.create(W * H, false)
local function seed()
	for i = 1, W * H do
		grid[i] = math.random() < 0.3
	end
end
seed()

local scratch = table.create(W * H, false)
local accumulator = 0

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 12 then
		return
	end
	accumulator = 0

	local changed = false
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local n = 0
			for dy = -1, 1 do
				for dx = -1, 1 do
					if (dx ~= 0 or dy ~= 0) and grid[index(x + dx, y + dy)] then
						n += 1
					end
				end
			end
			local here = grid[index(x, y)]
			local live = (here and (n == 2 or n == 3)) or (not here and n == 3)
			scratch[index(x, y)] = live
			if live ~= here then
				changed = true
				canvas:SetPixel(x, y, if live then ALIVE else DEAD)
			end
		end
	end

	grid, scratch = scratch, grid
	canvas:Render()

	if not changed then
		seed()
		canvas:Fill(DEAD)
		for i = 1, W * H do
			local x = (i - 1) % W
			local y = (i - 1 - x) / W
			if grid[i] then
				canvas:SetPixel(x, y, ALIVE)
			end
		end
		canvas:Render()
	end
end)

print("GameOfLife: a wrapping 72x72 world, reseeds when it stalls")
