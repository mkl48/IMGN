-- PaintApp -- draw on a canvas with your mouse, using interactive input.
--
-- Canvas:OnInput maps clicks/drags to canvas pixels, so this is a real little paint program. The
-- same code works on a SurfaceGui (an in-world touchscreen) - just mount the canvas onto one.
-- Press 1-4 to switch colour. Drop in StarterPlayerScripts with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local IMGN = ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local gui = Instance.new("ScreenGui")
gui.Name = "PaintApp"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.Size = UDim2.fromOffset(500, 500)
holder.Position = UDim2.fromScale(0.5, 0.5)
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
holder.Parent = gui

local canvas = IMGN.new({
	Resolution = Vector2.new(96, 96),
	Background = Color3.new(1, 1, 1),
	AutoRender = true,
	Parent = holder,
})

local colors = {
	Color3.fromRGB(0, 0, 0),
	Color3.fromRGB(230, 40, 60),
	Color3.fromRGB(40, 120, 230),
	Color3.fromRGB(40, 200, 90),
}
local color = colors[1]
local brush = 3
local painting = false

-- the interactive bit: pixel under the cursor on click/drag
canvas:OnInput(function(x, y, phase)
	if phase == "Began" then
		painting = true
	elseif phase == "Ended" then
		painting = false
	end
	if phase == "Began" or (phase == "Changed" and painting) then
		canvas:DrawCircle(x, y, brush, color, true)
	end
end)

-- 1-4 pick a colour
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	local n = tonumber(input.KeyCode.Name:match("%d"))
	if n and colors[n] then
		color = colors[n]
	end
end)

print("PaintApp: click-drag on the white square to paint; press 1-4 for colours")
