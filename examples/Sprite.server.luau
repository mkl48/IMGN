-- Sprite -- a static, flat-colour image rendered with the RowMerge driver.
--
-- Sprites are mostly runs of identical pixels, so RowMerge collapses each row to
-- a few wide Frames instead of one per pixel -- far fewer Instances than the
-- default PixelGrid. Here a tiny pixel-art heart is drawn from a string map. Drop
-- this in ServerScriptService with IMGN under ReplicatedStorage and a Part named
-- "Sign" in the Workspace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

-- '.' = transparent, 'R' = red. An 8x7 heart.
local ART = {
	".RR.RR..",
	"RRRRRRR.",
	"RRRRRRR.",
	"RRRRRRR.",
	".RRRRR..",
	"..RRR...",
	"...R....",
}

local WIDTH = #ART[1]
local HEIGHT = #ART
local PALETTE = { R = Color3.fromRGB(220, 40, 70) }

local sign = workspace:WaitForChild("Sign")
local canvas = IMGN.Surface(sign, Enum.NormalId.Front, {
	Resolution = Vector2.new(WIDTH, HEIGHT),
	Driver = "RowMerge", -- run-length-merged rows: far fewer Frames for flat art
})

for y, row in ART do
	for x = 1, #row do
		local cell = row:sub(x, x)
		local color = PALETTE[cell]
		if color then
			-- ART is 1-indexed; canvas pixels are 0-indexed.
			canvas:SetPixel(x - 1, y - 1, color)
		end
	end
end

canvas:Render()

print(`Sprite: drew an {WIDTH}x{HEIGHT} heart via RowMerge`)
