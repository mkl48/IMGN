-- CombWipe -- App:Comb sweeping the canvas row by row.
--
-- Comb(axis, direction, fn) hands your callback one line at a time: a row for "Y", a column for
-- "X". Here a "Y" sweep paints each row a hue from a scrolling rainbow, so the whole thing reads
-- as a vertical gradient that animates. No Objects, no engine loop -- Comb is usable on its own;
-- we just drive a throttled render ourselves. Drop in ServerScriptService with IMGN under
-- ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local SIZE = 64

local part = Instance.new("Part")
part.Name = "IMGNComb"
part.Size = Vector3.new(12, 12, 1)
part.Position = Vector3.new(20, 14, -16)
part.Anchored = true
part.Parent = workspace

-- An App with no objects -- we only want its Comb + Canvas.
local app = IMGN.App({
	Canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(SIZE, SIZE) }),
})

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 1 / 24 then
		return
	end
	accumulator = 0

	local phase = os.clock() * 0.15
	-- One full line per call; section.Index is the row's y, section.Length its width.
	app:Comb("Y", "Forward", function(section)
		local hue = (section.Index / SIZE + phase) % 1
		section:Fill(Color3.fromHSV(hue, 0.85, 1))
	end)
	app.Canvas:Render()
end)

print("CombWipe: a scrolling rainbow painted one row per Comb call")
