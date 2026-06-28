-- Dashboard -- a live stats panel: a rolling line chart over a bar chart, drawn with IMGN.Chart.
--
-- The canvas is split into regions with :Query, and each chart draws into its own region in local
-- coordinates. Drop in ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local W, H = 120, 80
local BG = Color3.fromRGB(16, 18, 26)

local part = Instance.new("Part")
part.Name = "IMGNDashboard"
part.Size = Vector3.new(16, 16 * H / W, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

-- two regions: a line chart up top, a bar chart below
local lineView = canvas:Query(3, 3, W - 6, math.floor(H * 0.55) - 5)
local barView = canvas:Query(3, math.floor(H * 0.55), W - 6, H - math.floor(H * 0.55) - 3)

local series = {}
for _ = 1, lineView.Width do
	table.insert(series, 50)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.2 then
		return
	end
	accumulator = 0

	-- roll the series, append a noisy new value
	table.remove(series, 1)
	table.insert(series, math.clamp(series[#series] + math.random(-12, 12), 0, 100))

	canvas:Fill(BG)
	lineView:Text("CPU", 1, 0, Color3.fromRGB(120, 200, 255))
	IMGN.Chart.line(lineView, series, { Min = 0, Max = 100, Color = Color3.fromRGB(120, 200, 255) })

	local bars = {}
	for i = 1, 8 do
		bars[i] = math.random(10, 100)
	end
	IMGN.Chart.bar(barView, bars, { Max = 100, Color = Color3.fromRGB(120, 230, 140) })

	canvas:Render()
end)

print("Dashboard: a live line + bar chart (IMGN.Chart) drawn into :Query regions")
