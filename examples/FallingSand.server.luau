-- FallingSand -- a little powder game.
--
-- A grid of cells (empty / sand / wall). Emitters at the top drip sand; each frame, scanning
-- bottom-up, every grain tries to fall straight down, then diagonally, piling into heaps. A
-- funnel of wall cells shapes the flow. Auto-running, no input. Drop in ServerScriptService with
-- IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 80, 80
local EMPTY, SAND, WALL = 0, 1, 2
local BG = Color3.fromRGB(10, 10, 14)
local WALL_COLOR = Color3.fromRGB(70, 70, 90)

local part = Instance.new("Part")
part.Name = "IMGNSand"
part.Size = Vector3.new(13, 13, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })
canvas:Fill(BG)

local cells = table.create(W * H, EMPTY)
local function at(x, y)
	return cells[y * W + x + 1]
end
local function set(x, y, kind, color)
	cells[y * W + x + 1] = kind
	canvas:SetPixel(x, y, color)
end

-- a couple of funnel walls
for i = 0, 24 do
	set(20 + i, 30 + i, WALL, WALL_COLOR)
	set(60 - i, 30 + i, WALL, WALL_COLOR)
end

-- each grain gets a slightly different sandy tone, looked up by column for variety
local sandTone = {}
for x = 0, W - 1 do
	sandTone[x] = Color3.fromRGB(200 + math.random(-20, 30), 175 + math.random(-20, 25), 90 + math.random(-15, 20))
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	accumulator = 0

	-- drip from three emitters
	for _, ex in { 35, 40, 45 } do
		if at(ex, 0) == EMPTY then
			set(ex, 0, SAND, sandTone[ex])
		end
	end

	-- settle, bottom-up so a grain only moves once per frame
	for y = H - 2, 0, -1 do
		-- alternate scan direction by row to avoid a left/right bias
		local x0, x1, step = 0, W - 1, 1
		if y % 2 == 0 then
			x0, x1, step = W - 1, 0, -1
		end
		for x = x0, x1, step do
			if at(x, y) == SAND then
				local below = at(x, y + 1)
				if below == EMPTY then
					set(x, y, EMPTY, BG)
					set(x, y + 1, SAND, sandTone[x])
				else
					local dl = x > 0 and at(x - 1, y + 1) == EMPTY
					local dr = x < W - 1 and at(x + 1, y + 1) == EMPTY
					if dl and dr then
						if math.random() < 0.5 then dl = false else dr = false end
					end
					if dl then
						set(x, y, EMPTY, BG)
						set(x - 1, y + 1, SAND, sandTone[x])
					elseif dr then
						set(x, y, EMPTY, BG)
						set(x + 1, y + 1, SAND, sandTone[x])
					end
				end
			end
		end
	end

	-- clear sand that reached the floor so it doesn't fill forever
	for x = 0, W - 1 do
		if at(x, H - 1) == SAND then
			set(x, H - 1, EMPTY, BG)
		end
	end

	canvas:Render()
end)

print("FallingSand: sand pouring through a funnel on an 80x80 grid")
