-- Raycaster -- a textured software-3D level (Doom-in-a-GUI) via IMGN.Raycaster.
--
-- Casts a ray per column over a grid map and draws textured walls + a glowing sprite, all on a
-- canvas of GUI frames - real-time 3D with no MeshParts. WASD to move/strafe, arrow keys (or Q/E)
-- to turn. Drop in StarterPlayerScripts with IMGN under ReplicatedStorage. Lower the Resolution if
-- it's heavy (every pixel is redrawn each frame).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local W, H = 96, 64

local part = Instance.new("Part")
part.Name = "IMGN3D"
part.Size = Vector3.new(18, 18 * H / W, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

local MAP = {
	"################",
	"#..............#",
	"#..BB....CC....#",
	"#..B......C....#",
	"#..............#",
	"#....####......#",
	"#....#..#..BB..#",
	"#....#..#......#",
	"#..........CC..#",
	"#..BB..........#",
	"#..B...####....#",
	"#......#..#....#",
	"#..............#",
	"################",
}

local rc = IMGN.Raycaster({
	Canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) }),
	Map = MAP,
	Textures = {
		["#"] = IMGN.Texture.brick(rgb(150, 60, 50), rgb(40, 20, 18), 4, 2),
		["B"] = IMGN.Texture.brick(rgb(70, 95, 165), rgb(20, 26, 44), 4, 2),
		["C"] = IMGN.Texture.checker(rgb(220, 210, 40), rgb(30, 30, 30), 4),
	},
	Ceiling = rgb(40, 46, 66),
	Floor = rgb(48, 42, 36),
	StartX = 2.5,
	StartY = 2.5,
	StartAngle = 0.6,
})

-- a glowing orb sprite to walk up to
rc:AddSprite(8.5, 8.5, function(u, v)
	local dx, dy = u - 0.5, v - 0.5
	local d = dx * dx + dy * dy
	if d < 0.22 then
		return Color3.fromHSV(0.6 - d, 0.8, 1)
	end
	return nil -- transparent outside the orb
end)

rc:Start() -- WASD move/strafe, arrows or Q/E turn

print("Raycaster: WASD to move, arrows/Q-E to turn - software-rendered 3D on a GUI canvas")
