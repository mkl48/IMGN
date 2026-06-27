-- BloodArena -- a play area for the blood engine, with a click-to-bleed button.
--
-- Builds a floor, walls, a ramp and a steeper slope, plus a red button that floats above your
-- character. Click it to take lethal damage instantly: blood sprays from you, lands on the
-- surfaces, drips down them, sheds off their bottom edges, and pools on the ground (cross-surface
-- dripping). Blood is told to IGNORE you and the button, so it only paints the arena.
--
-- Drop in StarterPlayerScripts with IMGN under ReplicatedStorage.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local IMGN = game:GetService("ReplicatedStorage"):WaitForChild("IMGN")
IMGN = require(IMGN)

local player = Players.LocalPlayer

-- ---- play area ----
local function makePart(name, size, cframe, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.Color = color or Color3.fromRGB(222, 218, 210)
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = workspace
	return p
end

makePart("BloodFloor", Vector3.new(90, 1, 90), CFrame.new(0, 0, 0))
makePart("BloodWallA", Vector3.new(32, 20, 1), CFrame.new(0, 10, -16))
makePart("BloodWallB", Vector3.new(1, 20, 32), CFrame.new(16, 10, 0))
makePart("BloodRamp", Vector3.new(16, 1, 20), CFrame.new(-12, 6, 8) * CFrame.Angles(math.rad(-30), 0, 0))
makePart("BloodSlope", Vector3.new(14, 1, 16), CFrame.new(10, 8, 12) * CFrame.Angles(math.rad(-48), math.rad(18), 0))

-- ---- the floating "bleed" button that follows your character ----
local button = Instance.new("Part")
button.Name = "BleedButton"
button.Shape = Enum.PartType.Ball
button.Size = Vector3.new(2, 2, 2)
button.Color = Color3.fromRGB(200, 0, 0)
button.Material = Enum.Material.Neon
button.Anchored = true
button.CanCollide = false
button.CanQuery = false -- raycasts skip it (so blood ignores it too)
button.Parent = workspace

local billboard = Instance.new("BillboardGui")
billboard.Size = UDim2.fromOffset(120, 36)
billboard.StudsOffset = Vector3.new(0, 1.6, 0)
billboard.AlwaysOnTop = true
billboard.Parent = button
local label = Instance.new("TextLabel")
label.Size = UDim2.fromScale(1, 1)
label.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
label.TextColor3 = Color3.new(1, 1, 1)
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.Text = "CLICK TO BLEED"
label.Parent = billboard

local click = Instance.new("ClickDetector")
click.MaxActivationDistance = 64
click.Parent = button

IMGN.Blood.Ignore(button)

-- ---- spray blood from a point ----
local function spray(origin)
	for _ = 1, 10 do
		local v = Vector3.new(
			(math.random() - 0.5) * 22,
			14 + math.random() * 14,
			(math.random() - 0.5) * 22
		)
		IMGN.Blood.Emit(origin, v, { Amount = 3 + math.random() * 3 })
	end
end

-- ---- keep blood ignoring the current character, and follow it with the button ----
local currentChar
local function onCharacter(character)
	if currentChar then
		IMGN.Blood.Unignore(currentChar)
	end
	currentChar = character
	IMGN.Blood.Ignore(character)
end
if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

click.MouseClick:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid:IsA("Humanoid") and humanoid.Health > 0 and root then
		spray(root.Position)
		humanoid.Health = 0
	end
end)

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		button.CFrame = CFrame.new(root.Position + Vector3.new(0, 5, 0))
	end
end)

print("BloodArena: click the floating red button to bleed - watch it drip down the ramp and pool")
