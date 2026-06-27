-- WebImage -- load an image by URL through a web service (no client-side decoding).
--
-- A free FastAPI service (see server/) fetches + resizes + decodes the image and returns pixel
-- JSON; Roblox just plots it. Handy when you don't want to ship a decoder or a giant grid - the
-- server does the heavy lifting.
--
-- SETUP:
--   1. Deploy server/ (Render/HF/Vercel - see server/README.md) and set API below to its URL.
--   2. Enable Game Settings -> Security -> Allow HTTP Requests.
--   3. Put a Part named "Photo" in the Workspace, and set IMAGE_URL to any image.
--
-- Drop this in ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local API = "https://your-app.onrender.com/convert" -- <- your deployed service
local IMAGE_URL = "https://example.com/picture.png" -- <- any image URL

local request = API
	.. "?url=" .. HttpService:UrlEncode(IMAGE_URL)
	.. "&max_width=64&format=rle"

local ok, json = pcall(function()
	return HttpService:GetAsync(request)
end)
if not ok then
	warn("[WebImage] request failed (set API/IMAGE_URL, enable Allow HTTP Requests): " .. tostring(json))
	return
end

local data = HttpService:JSONDecode(json)

-- a SurfaceGui to mount onto; PixelCanvas sizes the canvas to the returned image
local part = workspace:WaitForChild("Photo")
local surface = Instance.new("SurfaceGui")
surface.Name = "IMGNWebImage"
surface.Face = Enum.NormalId.Front
surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
surface.PixelsPerStud = 50
surface.Adornee = part
surface.Parent = part

-- GreedyMesh keeps the instance count low for a static image.
local canvas = IMGN.PixelCanvas(data, { Parent = surface, Driver = "GreedyMesh" })

print(`WebImage: drew a {canvas.Width}x{canvas.Height} image from the web service`)
