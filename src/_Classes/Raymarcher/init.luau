-- IMGN
-- _Classes/Raymarcher/init.luau
-- Plinko Labs
--
-- A software raymarcher (signed-distance-field renderer) on a Canvas. For every pixel it shoots a
-- ray from the camera and SPHERE-TRACES the scene's SDF until it hits a surface, then shades the
-- hit with diffuse lighting, SOFT SHADOWS (marching toward the light), AMBIENT OCCLUSION, a
-- specular highlight and distance fog. The result is smooth, lit, shadowed 3D - the Shadertoy look
-- - rendered into GUI frames, no meshes. It's heavy (per-pixel marching), so keep the canvas small.

local RunService = game:GetService("RunService")

local Canvas = require(script.Parent.Canvas)

--[=[
	@class Raymarcher
	A signed-distance-field 3D renderer drawing on a [Canvas]. Give it a `Scene(p) -> distance` (built
	from [SDF] primitives) and a `Material`, point the camera, and `:Render()` (or `:Start()` for an
	orbiting loop).
]=]
local Raymarcher = {}
Raymarcher.__index = Raymarcher

local UP = Vector3.new(0, 1, 0)

export type RaymarcherConfig = {
	Canvas: Canvas.Canvas?,
	Resolution: Vector2?,
	Parent: Instance?,
	Driver: any?,
	Scene: (p: Vector3) -> number, -- distance to the nearest surface
	Material: ((p: Vector3, normal: Vector3) -> Color3)?, -- surface colour (default gray)
	Light: Vector3?, -- direction TO the light (default high + to the side)
	Sky: Color3?, -- background / fog colour
	FOV: number?, -- degrees (default 60)
	MaxSteps: number?,
	MaxDist: number?,
	Epsilon: number?,
	FogDist: number?,
	Shadows: boolean?,
	AO: boolean?,
	OnUpdate: ((self: any, t: number) -> ())?, -- per-frame hook (animate the scene/camera)
}

export type Raymarcher = typeof(setmetatable({} :: any, Raymarcher))

local function pick<T>(v: T?, d: T): T
	if v == nil then
		return d
	end
	return v
end

function Raymarcher.new(config: RaymarcherConfig): Raymarcher
	local canvas = config.Canvas
	if not canvas then
		assert(config.Resolution, "IMGN.Raymarcher: pass a Canvas or a Resolution")
		canvas = Canvas.new({ Resolution = config.Resolution, Parent = config.Parent, Driver = config.Driver })
	end

	local self = setmetatable({
		Canvas = canvas,
		Scene = config.Scene,
		Material = config.Material or function()
			return Color3.fromRGB(200, 200, 205)
		end,
		LightDir = (config.Light or Vector3.new(0.6, 0.8, -0.3)).Unit,
		Sky = config.Sky or Color3.fromRGB(150, 175, 215),
		FOV = config.FOV or 60,
		MaxSteps = config.MaxSteps or 72,
		MaxDist = config.MaxDist or 24,
		Epsilon = config.Epsilon or 0.002,
		FogDist = config.FogDist or 22,
		Shadows = pick(config.Shadows, true),
		AO = pick(config.AO, true),
		OnUpdate = config.OnUpdate,
		_conn = nil,
		_t = 0,
		CamPos = Vector3.new(0, 2, -5),
		Forward = Vector3.new(0, 0, 1),
		Right = Vector3.new(1, 0, 0),
		CamUp = UP,
	}, Raymarcher)

	Raymarcher.SetCamera(self, self.CamPos, Vector3.new(0, 0, 0))
	return self
end

--[=[
	@within Raymarcher
	Places the camera at `pos` looking at `lookAt`.
]=]
function Raymarcher.SetCamera(self: Raymarcher, pos: Vector3, lookAt: Vector3)
	self.CamPos = pos
	self.Forward = (lookAt - pos).Unit
	self.Right = self.Forward:Cross(UP).Unit
	self.CamUp = self.Right:Cross(self.Forward)
end

--[=[
	@within Raymarcher
	Sphere-traces a ray. Returns `hit, distance, point`.
]=]
function Raymarcher.March(self: Raymarcher, origin: Vector3, dir: Vector3): (boolean, number, Vector3)
	local scene = self.Scene
	local eps, maxDist, maxSteps = self.Epsilon, self.MaxDist, self.MaxSteps
	local t = 0
	for _ = 1, maxSteps do
		local p = origin + dir * t
		local d = scene(p)
		if d < eps then
			return true, t, p
		end
		t += d
		if t > maxDist then
			break
		end
	end
	return false, t, origin + dir * t
end

--[=[
	@within Raymarcher
	The surface normal at `p` (gradient of the SDF by central differences).
]=]
function Raymarcher.Normal(self: Raymarcher, p: Vector3): Vector3
	local scene = self.Scene
	local e = 0.0015
	return Vector3.new(
		scene(p + Vector3.new(e, 0, 0)) - scene(p - Vector3.new(e, 0, 0)),
		scene(p + Vector3.new(0, e, 0)) - scene(p - Vector3.new(0, e, 0)),
		scene(p + Vector3.new(0, 0, e)) - scene(p - Vector3.new(0, 0, e))
	).Unit
end

-- penumbra soft shadow: march toward the light, narrowing the closer the ray passes a surface
local function softShadow(self: Raymarcher, origin: Vector3, dir: Vector3): number
	local scene = self.Scene
	local res, t = 1, 0.05
	for _ = 1, 28 do
		local d = scene(origin + dir * t)
		if d < 0.001 then
			return 0
		end
		res = math.min(res, 14 * d / t)
		t += d
		if t > 10 then
			break
		end
	end
	return math.clamp(res, 0, 1)
end

local function ambientOcclusion(self: Raymarcher, p: Vector3, n: Vector3): number
	local scene = self.Scene
	local occ, sca = 0, 1
	for i = 1, 5 do
		local h = 0.01 + 0.12 * i / 5
		occ += (h - scene(p + n * h)) * sca
		sca *= 0.85
	end
	return math.clamp(1 - 1.5 * occ, 0, 1)
end

local function clamp01(v: number): number
	return if v < 0 then 0 elseif v > 1 then 1 else v
end

--[=[
	@within Raymarcher
	Renders the scene to the canvas and flushes it.
]=]
function Raymarcher.Render(self: Raymarcher)
	local canvas = self.Canvas
	local W, H = canvas.Width, canvas.Height
	local origin = self.CamPos
	local fwd, right, up = self.Forward, self.Right, self.CamUp
	local fovScale = math.tan(math.rad(self.FOV) / 2)
	local aspect = W / H
	local lightDir = self.LightDir
	local sky, fogDist = self.Sky, self.FogDist

	for y = 0, H - 1 do
		local py = (1 - 2 * (y + 0.5) / H) * fovScale
		for x = 0, W - 1 do
			local px = (2 * (x + 0.5) / W - 1) * fovScale * aspect
			local dir = (fwd + right * px + up * py).Unit

			local hit, t, p = Raymarcher.March(self, origin, dir)
			local color
			if hit then
				local n = Raymarcher.Normal(self, p)
				local diff = math.max(0, n:Dot(lightDir))
				local sh = if self.Shadows and diff > 0 then softShadow(self, p + n * 0.02, lightDir) else 1
				local ao = if self.AO then ambientOcclusion(self, p, n) else 1
				local base = self.Material(p, n)
				local light = 0.22 * ao + diff * sh * 0.85
				-- specular (Blinn-Phong)
				local half = (lightDir - dir).Unit
				local spec = math.pow(math.max(0, n:Dot(half)), 24) * sh * 0.5
				color = Color3.new(
					clamp01(base.R * light + spec),
					clamp01(base.G * light + spec),
					clamp01(base.B * light + spec)
				)
				-- distance fog
				local f = clamp01(t / fogDist)
				color = color:Lerp(sky, f * f)
			else
				-- sky gradient by ray height
				color = sky:Lerp(Color3.new(1, 1, 1), clamp01(dir.Y) * 0.4)
			end
			canvas:SetPixel(x, y, color)
		end
	end

	canvas:Render()
end

--[=[
	@within Raymarcher
	Starts a render loop, calling `OnUpdate(self, t)` each frame first (animate the scene/camera).
	Heavy - low resolution recommended.
]=]
function Raymarcher.Start(self: Raymarcher)
	if self._conn then
		return
	end
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self._t += dt
		if self.OnUpdate then
			self.OnUpdate(self, self._t)
		end
		Raymarcher.Render(self)
	end)
end

--[=[
	@within Raymarcher
	Stops the render loop.
]=]
function Raymarcher.Stop(self: Raymarcher)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

return Raymarcher
