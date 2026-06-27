-- Breakout -- a whole mini-game on the App engine.
--
-- Shows every piece working together: a Dynamic ball, an anchored "Wall" paddle you steer with
-- A/D (or arrow keys), a grid of "Wall" bricks that delete themselves via OnCollide, and the
-- ball resetting when it hits the bottom edge. The App handles all the physics + drawing; this
-- script is just rules. Drop in StarterPlayerScripts with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 100, 100
local PADDLE_W = 20
local PADDLE_SPEED = 90 -- pixels per second

-- the screen
local part = Instance.new("Part")
part.Name = "IMGNBreakout"
part.Size = Vector3.new(16, 16, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local app = IMGN.App({
	Canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) }),
	Background = Color3.fromRGB(10, 10, 16),
})

-- bricks: a 4x8 grid of anchored solids near the top
local BRICK_W, BRICK_H = 10, 5
local ROW_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 170, 70),
	Color3.fromRGB(120, 220, 120),
	Color3.fromRGB(90, 170, 255),
}
local dead = {}        -- bricks awaiting removal (don't mutate the list mid-collision)
local bricksLeft = 0
local won = false

for row = 0, 3 do
	for col = 0, 7 do
		bricksLeft += 1
		app:Object({
			Position = Vector2.new(6 + col * (BRICK_W + 1), 10 + row * (BRICK_H + 1)),
			Preset = "Wall",
			Name = "brick",
			OnCollide = function(self)
				-- only the ball can reach the bricks, so any collision = a hit
				table.insert(dead, self)
			end,
		}):Rect(Vector2.zero, Vector2.new(BRICK_W, BRICK_H), ROW_COLORS[row + 1])
	end
end

-- paddle: anchored solid the ball reflects off; we drive its X from input
local paddle = app:Object({
	Position = Vector2.new((W - PADDLE_W) / 2, H - 6),
	Preset = "Wall",
}):Rect(Vector2.zero, Vector2.new(PADDLE_W, 4), Color3.fromRGB(235, 235, 245))

-- ball: a Dynamic body
local ball = app:Object({
	Position = Vector2.new(W / 2, 70),
	Velocity = Vector2.new(34, -46),
	OnCollide = function(self, other)
		if other == "Bottom" then
			-- fell past the paddle: respawn at center heading up
			self.Position = Vector2.new(W / 2, 70)
			self.Velocity = Vector2.new(math.random(-40, 40), -46)
		end
	end,
}):Circle(Vector2.zero, 3, Color3.fromRGB(255, 255, 255))

-- per-frame rules: steer the paddle, clear destroyed bricks, check for a win
app.OnUpdate = function(_, dt)
	local dir = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		dir -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		dir += 1
	end
	local x = math.clamp(paddle.Position.X + dir * PADDLE_SPEED * dt, 0, W - PADDLE_W)
	paddle.Position = Vector2.new(x, paddle.Position.Y)

	for _, brick in dead do
		brick:Destroy()
		bricksLeft -= 1
	end
	table.clear(dead)

	if bricksLeft <= 0 and not won then
		won = true
		print("Breakout: you cleared every brick! 🎉")
	end
end

app:Start()
print("Breakout: steer with A/D (or arrow keys) -- don't let the ball hit the bottom")
