-- IMGN
-- _Classes/Particles/init.luau
-- Plinko Labs
--
-- A 2D particle system on a canvas: an emitter spawns short-lived particles that move under
-- gravity, fade with age, and draw themselves as pixels. Presets cover Fire/Sparks/Rain/Snow/
-- Explosion/Confetti; everything (rate, speed, spread, gravity, life, colour) is tunable. Each
-- particle erases its previous pixel and draws its new one, so only the moving pixels repaint, and
-- the loop sleeps when there are no particles and nothing's emitting.

local RunService = game:GetService("RunService")

local Canvas = require(script.Parent.Canvas)

--[=[
	@class Particles
	A particle emitter drawing on a [Canvas]. Create with [IMGN.Particles], `:Start` for continuous
	emission or `:Burst(n)` for a one-shot, and `:Stop` to stop emitting.
]=]
local Particles = {}
Particles.__index = Particles

local PI = math.pi

type Preset = {
	Rate: number,
	Direction: number,
	Spread: number,
	SpeedMin: number,
	SpeedMax: number,
	Gravity: number,
	LifeMin: number,
	LifeMax: number,
	ColorStart: Color3,
	ColorEnd: Color3,
	RandomColors: boolean?,
	Sky: boolean?, -- spawn across the top edge (rain/snow) rather than from a point
}

local PRESETS: { [string]: Preset } = {
	Fire = { Rate = 70, Direction = -PI / 2, Spread = 0.7, SpeedMin = 10, SpeedMax = 26, Gravity = -14, LifeMin = 0.5, LifeMax = 1.0, ColorStart = Color3.fromRGB(255, 235, 120), ColorEnd = Color3.fromRGB(190, 25, 0) },
	Sparks = { Rate = 0, Direction = 0, Spread = PI * 2, SpeedMin = 25, SpeedMax = 70, Gravity = 90, LifeMin = 0.3, LifeMax = 0.8, ColorStart = Color3.fromRGB(255, 210, 90), ColorEnd = Color3.fromRGB(120, 20, 0) },
	Rain = { Rate = 120, Direction = PI / 2, Spread = 0.08, SpeedMin = 70, SpeedMax = 100, Gravity = 30, LifeMin = 1.2, LifeMax = 1.8, ColorStart = Color3.fromRGB(150, 180, 255), ColorEnd = Color3.fromRGB(120, 150, 230), Sky = true },
	Snow = { Rate = 45, Direction = PI / 2, Spread = 0.5, SpeedMin = 8, SpeedMax = 18, Gravity = 4, LifeMin = 3, LifeMax = 6, ColorStart = Color3.fromRGB(255, 255, 255), ColorEnd = Color3.fromRGB(220, 230, 245), Sky = true },
	Explosion = { Rate = 0, Direction = 0, Spread = PI * 2, SpeedMin = 35, SpeedMax = 90, Gravity = 50, LifeMin = 0.4, LifeMax = 0.9, ColorStart = Color3.fromRGB(255, 190, 70), ColorEnd = Color3.fromRGB(80, 0, 0) },
	Confetti = { Rate = 0, Direction = -PI / 2, Spread = 1.2, SpeedMin = 30, SpeedMax = 75, Gravity = 60, LifeMin = 1.2, LifeMax = 2.4, ColorStart = Color3.fromRGB(255, 80, 120), ColorEnd = Color3.fromRGB(255, 80, 120), RandomColors = true },
}

export type ParticlesConfig = {
	Canvas: Canvas.Canvas?,
	Resolution: Vector2?,
	Parent: Instance?,
	Driver: any?,
	Preset: string?,
	Position: Vector2?, -- emit point (default centre, or top for Sky presets)
	-- any preset field can be overridden:
	Rate: number?,
	Gravity: number?,
	SpeedMin: number?,
	SpeedMax: number?,
	Spread: number?,
	Direction: number?,
	LifeMin: number?,
	LifeMax: number?,
	ColorStart: Color3?,
	ColorEnd: Color3?,
}

export type Particles = typeof(setmetatable({} :: any, Particles))

local function pick<T>(v: T?, d: T): T
	if v == nil then
		return d
	end
	return v
end

function Particles.new(config: ParticlesConfig): Particles
	local preset = PRESETS[config.Preset or "Fire"]
	assert(preset, `IMGN.Particles: unknown Preset "{tostring(config.Preset)}"`)

	local canvas = config.Canvas
	if not canvas then
		assert(config.Resolution, "IMGN.Particles: pass a Canvas or a Resolution")
		canvas = Canvas.new({ Resolution = config.Resolution, Parent = config.Parent, Driver = config.Driver })
	end

	local sky = preset.Sky == true
	local position = config.Position or (if sky then Vector2.new(canvas.Width / 2, 0) else Vector2.new(canvas.Width / 2, canvas.Height / 2))

	return setmetatable({
		Canvas = canvas,
		Width = canvas.Width,
		Height = canvas.Height,
		Position = position,
		Rate = pick(config.Rate, preset.Rate),
		Direction = pick(config.Direction, preset.Direction),
		Spread = pick(config.Spread, preset.Spread),
		SpeedMin = pick(config.SpeedMin, preset.SpeedMin),
		SpeedMax = pick(config.SpeedMax, preset.SpeedMax),
		Gravity = pick(config.Gravity, preset.Gravity),
		LifeMin = pick(config.LifeMin, preset.LifeMin),
		LifeMax = pick(config.LifeMax, preset.LifeMax),
		ColorStart = pick(config.ColorStart, preset.ColorStart),
		ColorEnd = pick(config.ColorEnd, preset.ColorEnd),
		RandomColors = preset.RandomColors == true,
		_sky = sky,
		_particles = {},
		_spawnAcc = 0,
		_emitting = false,
		_conn = nil,
	}, Particles)
end

local function spawnOne(self: Particles)
	local angle = self.Direction + (math.random() - 0.5) * self.Spread
	local speed = self.SpeedMin + math.random() * (self.SpeedMax - self.SpeedMin)
	local px = self.Position.X
	if self._sky then
		px = math.random() * self.Width -- spread across the top
	end
	table.insert(self._particles, {
		x = px,
		y = self.Position.Y,
		vx = math.cos(angle) * speed,
		vy = math.sin(angle) * speed,
		life = self.LifeMin + math.random() * (self.LifeMax - self.LifeMin),
		maxLife = 0,
		color = if self.RandomColors then Color3.fromHSV(math.random(), 0.9, 1) else self.ColorStart,
		lpx = -1,
		lpy = -1,
	})
	local p = self._particles[#self._particles]
	p.maxLife = p.life
end

--[=[
	@within Particles
	Spawns `count` particles immediately (a one-shot burst - explosions, confetti).
]=]
function Particles.Burst(self: Particles, count: number)
	for _ = 1, count do
		spawnOne(self)
	end
	if not self._conn then
		Particles.Start(self, true)
	end
end

--[=[
	@within Particles
	Advances the system: emits per `Rate`, moves/ages/draws every particle, drops dead ones.
]=]
function Particles.Step(self: Particles, dt: number)
	local canvas = self.Canvas
	local W, H = self.Width, self.Height
	local gravity = self.Gravity
	local colorEnd = self.ColorEnd

	if self._emitting and self.Rate > 0 then
		self._spawnAcc += self.Rate * dt
		while self._spawnAcc >= 1 do
			self._spawnAcc -= 1
			spawnOne(self)
		end
	end

	local list = self._particles
	local i = 1
	while i <= #list do
		local p = list[i]
		-- erase last drawn pixel
		if p.lpx >= 0 then
			canvas:SetPixel(p.lpx, p.lpy, Color3.new(0, 0, 0), 0)
		end

		p.vy += gravity * dt
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.life -= dt

		if p.life <= 0 then
			list[i] = list[#list] -- swap-remove (already erased)
			list[#list] = nil
		else
			local nx, ny = math.round(p.x), math.round(p.y)
			if nx >= 0 and nx < W and ny >= 0 and ny < H then
				local t = p.life / p.maxLife -- 1 fresh -> 0 dead
				canvas:SetPixel(nx, ny, p.color:Lerp(colorEnd, 1 - t), math.clamp(t * 1.5, 0, 1))
				p.lpx, p.lpy = nx, ny
			else
				p.lpx = -1
			end
			i += 1
		end
	end

	canvas:Render()

	-- sleep when nothing's left to do
	if not self._emitting and #list == 0 and self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

--[=[
	@within Particles
	Starts continuous emission (per `Rate`) and the update loop. Pass `false` rate-wise by leaving
	`Rate` at 0 and using `:Burst` instead.
]=]
function Particles.Start(self: Particles, _internal: boolean?)
	if not _internal then
		self._emitting = true
	end
	if self._conn then
		return
	end
	self._conn = RunService.Heartbeat:Connect(function(dt)
		Particles.Step(self, math.min(dt, 1 / 30))
	end)
end

--[=[
	@within Particles
	Stops emitting new particles; existing ones finish their life, then the loop sleeps.
]=]
function Particles.Stop(self: Particles)
	self._emitting = false
end

--[=[
	@within Particles
	Stops everything and destroys the canvas.
]=]
function Particles.Destroy(self: Particles)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._particles = {}
	self.Canvas:Destroy()
end

return Particles
