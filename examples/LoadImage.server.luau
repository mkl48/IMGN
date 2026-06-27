-- LoadImage -- decode a real PNG onto a surface (no EditableImage, no verification).
--
-- IMGN doesn't bundle a decoder; it drives osgl-rbx/image, which you install yourself.
--
-- SETUP:
--   1. Get osgl: https://github.com/osgl-rbx/image (grab the v1.0 .rbxm release), and put it
--      under ReplicatedStorage named "Image".
--   2. Enable Game Settings -> Security -> Allow HTTP Requests (so we can fetch the file).
--   3. Put a Part named "Photo" in the Workspace, and set PNG_URL below to a SMALL png.
--
-- Keep images small (<= ~128px on the long side, or use Scale < 1) -- a Frame-based canvas is
-- bound by instance count. Drop this in ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local Image = require(ReplicatedStorage:WaitForChild("Image")) -- the osgl-rbx/image module

local PNG_URL = "https://example.com/your-small-image.png" -- <- set me to a real PNG

-- fetch the raw file bytes (a string is fine; osgl also accepts a buffer)
local ok, bytes = pcall(function()
	return HttpService:GetAsync(PNG_URL)
end)
if not ok then
	warn("[LoadImage] couldn't fetch the PNG (set PNG_URL, enable Allow HTTP Requests): " .. tostring(bytes))
	return
end

-- a SurfaceGui to mount onto (ImageCanvas builds the canvas, sized to the decoded image)
local part = workspace:WaitForChild("Photo")
local surface = Instance.new("SurfaceGui")
surface.Name = "IMGNPhoto"
surface.Face = Enum.NormalId.Front
surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
surface.PixelsPerStud = 50
surface.Adornee = part
surface.Parent = part

-- Decode + draw in one call. Scale = 1 keeps native size; use e.g. 0.5 to halve a big image.
local canvas = IMGN.ImageCanvas(Image, bytes, {
	Parent = surface,
	Scale = 1,
	Format = "PNG", -- skip auto-detection
})

print(`LoadImage: decoded a {canvas.Width}x{canvas.Height} PNG onto the part, no EditableImage`)
