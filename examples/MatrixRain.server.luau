-- MatrixRain -- the falling green code, using the bitmap font.
--
-- One stream per text column: a bright head glyph at the bottom of its trail, fading green
-- glyphs above it, and a randomly changing character set. Streams fall at their own speed and
-- respawn at the top. Shows off Canvas:Text. Drop in ServerScriptService with IMGN under
-- ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 80, 96
local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local COL_STEP = 4 -- font advance (3px glyph + 1 gap)
local ROW_STEP = 6 -- glyph height 5 + 1 gap

local part = Instance.new("Part")
part.Name = "IMGNMatrix"
part.Size = Vector3.new(13, 16, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })
canvas:Fill(Color3.new(0, 0, 0))

local function randChar()
	local i = math.random(1, #CHARS)
	return string.sub(CHARS, i, i)
end

-- one stream per text column
local rows = math.floor(H / ROW_STEP)
local streams = {}
for col = 0, math.floor(W / COL_STEP) - 1 do
	streams[col] = {
		head = math.random(-rows, 0),
		speed = math.random(1, 3),
		tail = math.random(4, 9),
	}
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 14 then
		return
	end
	accumulator = 0

	for col, stream in streams do
		local x = col * COL_STEP
		stream.head += stream.speed

		-- erase the glyph just past the end of the tail
		local clearRow = stream.head - stream.tail - 1
		if clearRow >= 0 and clearRow < rows then
			canvas:DrawRect(x, clearRow * ROW_STEP, 3, 5, Color3.new(0, 0, 0), true)
		end

		-- draw the tail, brightest at the head
		for t = 0, stream.tail do
			local row = stream.head - t
			if row >= 0 and row < rows then
				local shade
				if t == 0 then
					shade = Color3.fromRGB(200, 255, 200) -- white-green head
				else
					local f = 1 - t / stream.tail
					shade = Color3.fromRGB(0, math.floor(80 + 160 * f), 0)
				end
				canvas:DrawRect(x, row * ROW_STEP, 3, 5, Color3.new(0, 0, 0), true)
				canvas:Text(randChar(), x, row * ROW_STEP, shade)
			end
		end

		if stream.head - stream.tail > rows then
			stream.head = math.random(-rows, 0)
			stream.speed = math.random(1, 3)
			stream.tail = math.random(4, 9)
		end
	end

	canvas:Render()
end)

print("MatrixRain: streaming glyphs from the IMGN bitmap font")
