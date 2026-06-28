-- Raymarch -- a raytraced-style 3D scene (soft shadows + AO + lighting) rendered into GUI frames.
--
-- A signed-distance scene: a smooth-blended sphere + box morphing over a checkered floor, with an
-- orbiting camera. The raymarcher shades it with diffuse light, soft shadows, ambient occlusion and
-- fog. No meshes, no EditableImage. It's per-pixel heavy, so the canvas is small - lower the
-- Resolution if it's choppy. Drop in StarterPlayerScripts with IMGN under ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IMGN = ReplicatedStorage:WaitForChild("IMGN")
IMGN = require(IMGN)
local SDF = IMGN.SDF

local W, H = 72, 54

local part = Instance.new("Part")
part.Name = "IMGNRaymarch"
part.Size = Vector3.new(16, 16 * H / W, 1)
part.Position = Vector3.new(0, 14, -16)
part.Anchored = true
part.Parent = workspace

-- the scene SDF (mutated over time via OnUpdate)
local morph = 0
local function sceneSDF(p)
	local floor = SDF.plane(p, -1)
	local sphere = SDF.sphere(p, Vector3.new(-0.7, math.sin(morph) * 0.3, 0), 1)
	local box = SDF.box(p, Vector3.new(0.9, 0, 0), Vector3.new(0.7, 0.7, 0.7))
	box = SDF.round(box, 0.1)
	local blob = SDF.smoothUnion(sphere, box, 0.5)
	local ring = SDF.torus(p, Vector3.new(0, 0.2, 0), 1.9, 0.18)
	return SDF.union(SDF.union(floor, blob), ring)
end

local rm = IMGN.Raymarcher({
	Canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(W, H) }),
	Scene = sceneSDF,
	Light = Vector3.new(0.5, 0.9, -0.4),
	Sky = Color3.fromRGB(150, 175, 215),
	Material = function(p, _n)
		if p.Y < -0.98 then
			-- checkered floor
			local c = (math.floor(p.X) + math.floor(p.Z)) % 2
			return if c == 0 then Color3.fromRGB(210, 210, 215) else Color3.fromRGB(80, 85, 95)
		end
		-- colour the object by its position
		return Color3.fromHSV((p.X * 0.15 + 0.55) % 1, 0.55, 0.95)
	end,
	OnUpdate = function(self, t)
		morph = t
		local r = 5
		self:SetCamera(Vector3.new(math.cos(t * 0.4) * r, 2.2, math.sin(t * 0.4) * r), Vector3.new(0, 0, 0))
	end,
})

rm:Start()

print("Raymarch: a raytraced-style SDF scene (soft shadows + AO) on a GUI canvas - no meshes")
