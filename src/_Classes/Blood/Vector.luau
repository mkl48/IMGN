-- IMGN
-- _Classes/Blood/Vector.luau
-- Plinko Labs
--
-- Vector blood: instead of a pixel grid (which tiles into visible squares and pixelates), a splat
-- is drawn as smooth, animated Path2D strokes - a blob plus a few drips that GROW downward over
-- time, each a Bezier path that tapers and dries. No pixels, so no edges and no resolution limit;
-- a whole splat is a handful of instances, not thousands of Frames.
--
-- The canvas is a FixedSize (100x100 virtual) SurfaceGui, so all positions are 0..1 scale with +Y
-- downhill (the proxy is oriented that way) and Path2D Thickness is in those virtual units. When a
-- drip reaches the bottom it fires OnDrip(x) so the engine can shed a 3D droplet onto the surface
-- below. NEEDS A STUDIO PASS: Path2D's exact thickness units / parenting are runtime-only.

local RunService = game:GetService("RunService")

local Vector = {}
Vector.__index = Vector

--[=[
	@class VectorBlood
	@within Blood
	Renders blood as animated Path2D strokes on a SurfaceGui. Created by a [BloodProxy] when the
	engine's `Renderer` is `"Vector"`.
]=]

local function circle(parent: Instance, x: number, y: number, size: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(size, size)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	f.Parent = parent
	return f
end

local function newPath(parent: Instance, color: Color3, thickness: number): any
	local p = Instance.new("Path2D")
	p.Color3 = color
	p.Thickness = thickness
	p.Parent = parent
	return p
end

local function setPath(path: any, x0, y0, x1, y1, x2, y2)
	path:SetControlPoints({
		Path2DControlPoint.new(UDim2.fromScale(x0, y0)),
		Path2DControlPoint.new(UDim2.fromScale(x1, y1)),
		Path2DControlPoint.new(UDim2.fromScale(x2, y2)),
	})
end

export type VectorConfig = {
	Fresh: Color3,
	Dry: Color3,
	DripWidth: number?, -- stroke thickness in virtual units (canvas is 100 wide)
	GrowSpeed: number?, -- how fast drips extend (scale per second)
	DryRate: number?, -- 0..1 per second
	MaxDrips: number?,
	OnDrip: ((x: number) -> ())?, -- fired when a drip reaches the bottom edge (x in 0..1)
}

function Vector.new(surfaceGui: SurfaceGui, config: VectorConfig)
	local container = Instance.new("Frame")
	container.Name = "VectorBlood"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = surfaceGui

	local self = setmetatable({
		Fresh = config.Fresh,
		Dry = config.Dry,
		DripWidth = config.DripWidth or 3,
		GrowSpeed = config.GrowSpeed or 0.6,
		DryRate = config.DryRate or 0.06,
		MaxDrips = config.MaxDrips or 4,
		OnDrip = config.OnDrip,
		_container = container,
		_drips = {},
		_blobs = {},
		_active = false,
		_conn = nil,
	}, Vector)

	return self
end

--[=[
	@within VectorBlood
	Splats blood at `(x, y)` (0..1 scale, +Y down) - a blob plus `amount`-scaled drips that grow.
]=]
function Vector.Splat(self: any, x: number, y: number, amount: number)
	table.insert(self._blobs, {
		frame = circle(self._container, x, y, math.clamp(0.04 + amount * 0.015, 0.04, 0.18), self.Fresh),
		dry = 0,
	})

	local count = math.clamp(math.floor(amount / 2), 1, self.MaxDrips)
	for _ = 1, count do
		local dx = (math.random() - 0.5) * 0.12
		local width = self.DripWidth * (0.6 + amount / 8)
		table.insert(self._drips, {
			x = math.clamp(x + dx, 0.02, 0.98),
			y = y,
			wiggle = (math.random() - 0.5) * 0.08,
			length = 0,
			target = math.clamp((0.2 + math.random() * 0.5) * (amount / 4), 0.1, 0.9),
			path = newPath(self._container, self.Fresh, width),
			head = circle(self._container, x + dx, y, width * 0.012 + 0.02, self.Fresh),
			dry = 0,
			shed = false,
		})
	end

	self._active = true
end

--[=[
	@within VectorBlood
	Advances the drip animation. Called by the loop; safe to call directly for a fixed step.
]=]
function Vector.Step(self: any, dt: number)
	if not self._active then
		return
	end
	local active = false

	for _, d in self._drips do
		if d.length < d.target then
			d.length = math.min(d.target, d.length + self.GrowSpeed * dt)
			active = true
		end
		local endY = math.min(0.99, d.y + d.length)
		setPath(d.path, d.x, d.y, d.x + d.wiggle, d.y + d.length * 0.5, d.x, endY)
		d.head.Position = UDim2.fromScale(d.x, endY)

		if d.dry < 1 then
			d.dry = math.min(1, d.dry + self.DryRate * dt)
			active = true
			local color = self.Fresh:Lerp(self.Dry, d.dry)
			d.path.Color3 = color
			d.head.BackgroundColor3 = color
		end

		-- reached the bottom edge: shed a droplet onto whatever's below
		if not d.shed and endY >= 0.95 then
			d.shed = true
			if self.OnDrip then
				self.OnDrip(d.x)
			end
		end
	end

	for _, b in self._blobs do
		if b.dry < 1 then
			b.dry = math.min(1, b.dry + self.DryRate * dt)
			active = true
			b.frame.BackgroundColor3 = self.Fresh:Lerp(self.Dry, b.dry)
		end
	end

	self._active = active
end

--[=[
	@within VectorBlood
	Starts the per-frame animation loop (sleeps automatically once everything has grown + dried).
]=]
function Vector.Start(self: any)
	if self._conn then
		return
	end
	self._conn = RunService.Heartbeat:Connect(function(dt)
		Vector.Step(self, math.min(dt, 1 / 30))
	end)
end

function Vector.Stop(self: any)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

function Vector.Destroy(self: any)
	Vector.Stop(self)
	self._container:Destroy()
	self._drips = {}
	self._blobs = {}
end

return Vector
