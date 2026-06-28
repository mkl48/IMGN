-- Identicons -- a grid of unique avatars, one per name, with zero uploads.
--
-- One canvas, split into a grid of regions with :Query; each region gets a deterministic identicon
-- for its seed. Use it for player avatars, item icons, guild crests - anything that needs a unique
-- picture without an asset. Drop in ServerScriptService with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("IMGN")
	or ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)

local seeds = {
	"kr3ative", "PlinkoLabs", "alice", "bob", "carol", "dave",
	"player_1042", "guild:redfang", "sword_of_dawn", "potion#7",
	"npc_merchant", "world.seed.42", "MrFlibble", "zzz", "0xDEADBEEF", "imgn",
}

local cols, rows = 4, 4
local CELL = 26
local W, H = cols * CELL, rows * CELL

local part = Instance.new("Part")
part.Name = "IMGNIdenticons"
part.Size = Vector3.new(14, 14, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Color = Color3.fromRGB(20, 20, 24)
part.Parent = workspace

local canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) })

for i, seed in seeds do
	local col = (i - 1) % cols
	local row = math.floor((i - 1) / cols)
	-- a sub-canvas for this icon; the identicon draws in its local space
	local region = canvas:Query(col * CELL + 1, row * CELL + 1, CELL - 2, CELL - 2)
	IMGN.Identicon(region, seed)
end

canvas:Render()

print("Identicons: 16 unique avatars from seeds, each drawn into a :Query region - no uploads")
