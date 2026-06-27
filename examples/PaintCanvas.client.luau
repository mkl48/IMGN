-- PaintCanvas -- the live-drawing path: a finger-paint surface on the screen.
--
-- A 96x96 canvas on a ScreenGui with AutoRender on, so brush strokes appear as
-- you drag without ever calling :Render(). Because only the pixels under the
-- brush go dirty, a flush touches a handful of Frames, not the whole grid -- the
-- reason PixelGrid (the default driver) suits drawing. Drop this in
-- StarterPlayerScripts with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local RESOLUTION = 96
local BRUSH = 3
local BRUSH_COLOR = Color3.fromRGB(255, 80, 120)

local gui = Instance.new("ScreenGui")
gui.Name = "PaintCanvas"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- A square container the canvas fills; tweak to taste.
local holder = Instance.new("Frame")
holder.Size = UDim2.fromOffset(480, 480)
holder.Position = UDim2.fromScale(0.5, 0.5)
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
holder.Parent = gui

local canvas = IMGN.new({
	Resolution = Vector2.new(RESOLUTION, RESOLUTION),
	Background = Color3.new(1, 1, 1),
	AutoRender = true, -- flush dirty pixels every Heartbeat
	Parent = holder,
})

-- Map an absolute screen position onto canvas pixel coordinates.
local function paintAt(position: Vector2)
	local topLeft = holder.AbsolutePosition
	local size = holder.AbsoluteSize
	local px = math.floor((position.X - topLeft.X) / size.X * RESOLUTION)
	local py = math.floor((position.Y - topLeft.Y) / size.Y * RESOLUTION)
	canvas:DrawCircle(px, py, BRUSH, BRUSH_COLOR, true)
end

local painting = false
UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		painting = true
		paintAt(Vector2.new(input.Position.X, input.Position.Y))
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		painting = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if painting and input.UserInputType == Enum.UserInputType.MouseMovement then
		paintAt(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

print("PaintCanvas: click-drag on the white square to paint")
