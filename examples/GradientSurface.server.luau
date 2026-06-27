-- GradientSurface -- the procedural path: paint a part's face with a Shader.
--
-- IMGN.Surface builds the SurfaceGui for you, then :Shader runs a function per
-- pixel so you never touch a single SetPixel. No EditableImage, no verification.
-- Drop this in ServerScriptService with IMGN under ReplicatedStorage and a Part
-- named "Screen" in the Workspace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local screen = workspace:WaitForChild("Screen")

-- 64x64 canvas mounted onto the part's front face.
local canvas = IMGN.Surface(screen, Enum.NormalId.Front, {
	Resolution = Vector2.new(64, 64),
})

-- Fill every pixel from an (x, y) -> Color3 function: a diagonal hue sweep.
canvas:Shader(function(x, y)
	local hue = (x + y) / (64 + 64)
	return Color3.fromHSV(hue, 1, 1)
end)

-- One flush pushes the whole buffer to the Frames.
canvas:Render()

print("GradientSurface: painted a 64x64 gradient with zero EditableImage calls")
