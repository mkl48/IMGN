-- IMGN
-- _Classes/Liquid/init.luau
-- Plinko Labs
--
-- A liquid cellular simulation on a Canvas - splats that flow, drip, pool and dry. Each cell holds
-- an AMOUNT of fluid; every step it transfers downward (gravity), leaving a thin CLING film behind
-- so drips streak instead of sliding off clean, spreads sideways only when backed up (high surface
-- tension = narrow rivulets, not a watery sheet), slowly EVAPORATES, and DRIES from its fresh
-- colour toward its dry colour. Blood is the headline preset; Water/Paint/Lava/Slime/Honey reuse
-- the same engine with different constants.
--
-- Gravity is a canvas-space direction: a wall SurfaceGui uses (0, 1) (down), a floor uses (0, 0)
-- so fluid just pools where it lands. Only changed cells are repainted, so once it dries the sim
-- costs almost nothing.

local RunService = game:GetService("RunService")

local Canvas = require(script.Parent.Canvas)

--[=[
	@class Liquid
	A flowing/dripping fluid on a [Canvas]. Create with [IMGN.Liquid], `:Splat` to add fluid, and
	`:Start` to run the sim. `Canvas`, `Width`, `Height` are readable; tuning fields (`Capacity`,
	`Cling`, `Evaporation`, `DryRate`, `Spread`, `Gravity`) are writable live.
]=]
local Liquid = {}
Liquid.__index = Liquid

type RGB = { number }

type Preset = {
	Capacity: number, -- max fluid per cell
	Cling: number, -- film left behind when fluid flows down (the streak)
	Evaporation: number, -- fluid lost per second
	DryRate: number, -- how fast it dries (0..1 per second)
	Spread: number, -- lateral pooling strength (0 = none, 1 = watery)
	Stain: number, -- faint permanent mark left after drying (0 = none)
	Fresh: RGB, -- colour when wet
	Dry: RGB, -- colour when dried
	AlphaAt: number, -- amount at which the fluid is fully opaque
}

local PRESETS: { [string]: Preset } = {
	-- Dark, clingy, dries to brown. The good stuff.
	Blood = { Capacity = 4, Cling = 0.55, Evaporation = 0.03, DryRate = 0.06, Spread = 0.35, Stain = 0.2, Fresh = { 140, 8, 10 }, Dry = { 58, 18, 14 }, AlphaAt = 1.4 },
	-- Thin, spreads flat, evaporates fast, barely stains.
	Water = { Capacity = 4, Cling = 0.15, Evaporation = 0.12, DryRate = 0.04, Spread = 0.9, Stain = 0, Fresh = { 90, 150, 235 }, Dry = { 90, 150, 235 }, AlphaAt = 1.8 },
	-- Sticky, slow, vivid, never dries (override Fresh for colour).
	Paint = { Capacity = 5, Cling = 0.9, Evaporation = 0, DryRate = 0.02, Spread = 0.25, Stain = 1, Fresh = { 230, 40, 60 }, Dry = { 200, 36, 54 }, AlphaAt = 1.2 },
	-- Glowing, viscous, hardly spreads, permanent.
	Lava = { Capacity = 5, Cling = 0.8, Evaporation = 0, DryRate = 0.015, Spread = 0.2, Stain = 1, Fresh = { 255, 150, 40 }, Dry = { 120, 30, 20 }, AlphaAt = 1 },
	-- Very clingy, slow ooze.
	Slime = { Capacity = 5, Cling = 1.0, Evaporation = 0.01, DryRate = 0.02, Spread = 0.3, Stain = 0.5, Fresh = { 80, 220, 90 }, Dry = { 60, 150, 70 }, AlphaAt = 1.2 },
	-- Thick, golden, the slowest drip.
	Honey = { Capacity = 6, Cling = 1.3, Evaporation = 0, DryRate = 0.01, Spread = 0.2, Stain = 1, Fresh = { 235, 170, 30 }, Dry = { 205, 140, 20 }, AlphaAt = 1.1 },
}

export type LiquidConfig = {
	Canvas: Canvas.Canvas?, -- an existing canvas to flow on; else built from the fields below
	Resolution: Vector2?,
	Parent: Instance?,
	Driver: any?,
	Preset: string?, -- "Blood" (default), "Water", "Paint", "Lava", "Slime", "Honey"
	Gravity: Vector2?, -- canvas-space down (default (0,1)); use (0,0) for a floor (pool, no drip)
	Color: (Color3 | RGB)?, -- override the fresh colour (handy for Paint)
	-- any Preset field can be overridden directly:
	Capacity: number?,
	Cling: number?,
	Evaporation: number?,
	DryRate: number?,
	Spread: number?,
}

export type Liquid = typeof(setmetatable({} :: any, Liquid))

local function pick<T>(value: T?, fallback: T): T
	if value == nil then
		return fallback
	end
	return value
end

local function asRGB(color: (Color3 | RGB)?): RGB?
	if color == nil then
		return nil
	end
	if typeof(color) == "Color3" then
		return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
	end
	return color :: RGB
end

--[=[
	@within Liquid
	Builds a Liquid. Pass an existing `Canvas`, or `Resolution`/`Parent` to build one.
]=]
function Liquid.new(config: LiquidConfig): Liquid
	local preset = PRESETS[config.Preset or "Blood"]
	assert(preset, `IMGN.Liquid: unknown Preset "{tostring(config.Preset)}"`)

	local canvas = config.Canvas
	if not canvas then
		assert(config.Resolution, "IMGN.Liquid: pass a Canvas or a Resolution")
		canvas = Canvas.new({ Resolution = config.Resolution, Parent = config.Parent, Driver = config.Driver })
	end

	local count = canvas.Width * canvas.Height
	local self = setmetatable({
		Canvas = canvas,
		Width = canvas.Width,
		Height = canvas.Height,
		Capacity = pick(config.Capacity, preset.Capacity),
		Cling = pick(config.Cling, preset.Cling),
		Evaporation = pick(config.Evaporation, preset.Evaporation),
		DryRate = pick(config.DryRate, preset.DryRate),
		Spread = pick(config.Spread, preset.Spread),
		Stain = preset.Stain,
		AlphaAt = preset.AlphaAt,
		Fresh = asRGB(config.Color) or preset.Fresh,
		Dry = preset.Dry,
		Gravity = config.Gravity or Vector2.new(0, 1),
		_amount = table.create(count, 0),
		_dry = table.create(count, 0),
		_shown = table.create(count, -1),
		_delta = table.create(count, 0),
		_active = false, -- sim sleeps when nothing is moving/drying; Add/Splat wakes it
		_settledFlow = false, -- once flow stops we skip the flow/spread passes (just keep drying)
		_conn = nil,
		_running = false,
	}, Liquid)

	return self
end

-- Add fluid to one cell (clamped to capacity), no-op out of bounds.
function Liquid.Add(self: Liquid, x: number, y: number, amount: number)
	x, y = math.floor(x), math.floor(y)
	if x < 0 or y < 0 or x >= self.Width or y >= self.Height then
		return
	end
	local i = y * self.Width + x + 1
	self._amount[i] = math.min(self.Capacity, self._amount[i] + amount)
	self._dry[i] = 0 -- fresh again
	self._active = true -- wake the sim
	self._settledFlow = false -- new fluid may flow again
end

-- Add a soft radial blob of fluid.
function Liquid._blob(self: Liquid, cx: number, cy: number, radius: number, amount: number)
	local r2 = radius * radius
	for y = math.floor(cy - radius), math.ceil(cy + radius) do
		for x = math.floor(cx - radius), math.ceil(cx + radius) do
			local dx, dy = x - cx, y - cy
			local d2 = dx * dx + dy * dy
			if d2 <= r2 then
				Liquid.Add(self, x, y, amount * (1 - d2 / r2))
			end
		end
	end
end

--[=[
	@within Liquid
	Splats fluid around `(x, y)`: a central blob plus scattered droplets. `options.Spread` sets the
	splatter radius, `options.Velocity` (Vector2) biases the spray direction (a hit's momentum), and
	`options.Droplets` the number of satellites.
]=]
function Liquid.Splat(self: Liquid, x: number, y: number, amount: number, options: { Spread: number?, Velocity: Vector2?, Droplets: number? }?)
	local opts = options or {}
	local spread = opts.Spread or 6
	local vel = opts.Velocity or Vector2.zero
	local droplets = opts.Droplets or math.clamp(math.floor(amount * 1.5), 4, 24)

	Liquid._blob(self, x, y, spread * 0.4, amount)
	for _ = 1, droplets do
		local ang = math.random() * math.pi * 2
		local dist = math.random() * spread
		local px = x + math.cos(ang) * dist + vel.X * math.random()
		local py = y + math.sin(ang) * dist + vel.Y * math.random()
		Liquid._blob(self, px, py, math.random() + 0.5, amount * 0.35)
	end
end

--[=[
	@within Liquid
	Advances the simulation one step (`dt` seconds). Called for you by the loop when running; call
	directly for a fixed-step or headless sim.
]=]
function Liquid.Step(self: Liquid, dt: number)
	-- Sleep when fully settled + dried: stepping a static stain over and over is the difference
	-- between "free" and "melts the game" when there are lots of surfaces.
	if not self._active then
		return
	end

	local W, H = self.Width, self.Height
	local amount, dry, shown, delta = self._amount, self._dry, self._shown, self._delta
	local CAP, CLING, SPREAD = self.Capacity, self.Cling, self.Spread
	local cellCount = W * H

	-- Gravity is an arbitrary canvas-space vector, so fluid drips along whatever direction the
	-- surface's "downhill" maps to (walls, slopes, rotated parts). Its magnitude is the flow rate.
	local gx, gy = self.Gravity.X, self.Gravity.Y
	local gmag = math.sqrt(gx * gx + gy * gy)
	local sgnX = if gx > 1e-4 then 1 elseif gx < -1e-4 then -1 else 0
	local sgnY = if gy > 1e-4 then 1 elseif gy < -1e-4 then -1 else 0

	-- Once the fluid has stopped flowing we keep drying/repainting but skip the two expensive flow
	-- passes entirely (a settling pool no longer pays for flow + spread every frame).
	local doFlow = not self._settledFlow
	local moved = false

	-- 1) directional flow via a delta buffer (mass-conserving, capacity-aware). Sends are inlined -
	-- no per-cell closures or table allocations in the hot loop.
	if doFlow and gmag > 1e-4 then
		local nx, ny = gx / gmag, gy / gmag
		local wx, wy = math.abs(nx), math.abs(ny)
		local wd = wx * wy
		local total = wx + wy + wd
		if total <= 0 then
			total = 1
		end
		local fy, fx, fd = wy / total, wx / total, wd / total

		for i = 1, cellCount do
			delta[i] = 0
		end

		for y = 0, H - 1 do
			local row = y * W
			for x = 0, W - 1 do
				local i = row + x + 1
				local a = amount[i]
				if a > CLING then
					local movable = a - CLING
					local out = 0
					-- vertical
					local ty = y + sgnY
					if sgnY ~= 0 and ty >= 0 and ty < H then
						local ti = ty * W + x + 1
						local space = CAP - (amount[ti] + delta[ti])
						if space > 0 then
							local f = math.min(movable * fy, space)
							delta[ti] += f
							out += f
						end
					end
					-- horizontal
					local tx = x + sgnX
					if sgnX ~= 0 and tx >= 0 and tx < W then
						local ti = row + tx + 1
						local space = CAP - (amount[ti] + delta[ti])
						if space > 0 then
							local f = math.min(movable * fx, space)
							delta[ti] += f
							out += f
						end
					end
					-- diagonal
					if sgnX ~= 0 and sgnY ~= 0 and tx >= 0 and tx < W and ty >= 0 and ty < H then
						local ti = ty * W + tx + 1
						local space = CAP - (amount[ti] + delta[ti])
						if space > 0 then
							local f = math.min(movable * fd, space)
							delta[ti] += f
							out += f
						end
					end
					delta[i] -= out
				end
			end
		end

		for i = 1, cellCount do
			local d = delta[i]
			if d ~= 0 then
				amount[i] += d
				if d > 1e-4 or d < -1e-4 then
					moved = true
				end
			end
		end
	end

	-- 2) lateral pooling, only where the downhill cell is blocked (or there's no gravity) - keeps
	-- drips narrow on walls while pools level out. Neighbours inlined, no allocation.
	if doFlow and SPREAD > 0 then
		local k = 0.25 * SPREAD
		for y = 0, H - 1 do
			local row = y * W
			for x = 0, W - 1 do
				local i = row + x + 1
				local a = amount[i]
				if a > CLING then
					local backed = gmag <= 1e-4
					if not backed then
						local dx, dy = x + sgnX, y + sgnY
						if dx < 0 or dy < 0 or dx >= W or dy >= H then
							backed = true
						else
							backed = (CAP - amount[dy * W + dx + 1]) < 0.01
						end
					end
					if backed then
						if x > 0 then
							local ni = i - 1
							local diff = a - amount[ni]
							if diff > 0.05 then
								local m = diff * k
								amount[i] = a - m
								amount[ni] += m
								a = amount[i]
								moved = true
							end
						end
						if x < W - 1 then
							local ni = i + 1
							local diff = a - amount[ni]
							if diff > 0.05 then
								local m = diff * k
								amount[i] = a - m
								amount[ni] += m
								moved = true
							end
						end
					end
				end
			end
		end
	end

	-- flow has stopped: stop paying for the flow/spread passes (drying continues below)
	if doFlow and not moved then
		self._settledFlow = true
	end

	-- 3) evaporate, dry, repaint changed cells, and decide whether to keep simulating
	local evap = self.Evaporation * dt
	local dryStep = self.DryRate * dt
	local stain = self.Stain
	local alphaAt = self.AlphaAt
	local fr, dr = self.Fresh, self.Dry
	local canvas = self.Canvas
	local active = false

	for y = 0, H - 1 do
		local row = y * W
		for x = 0, W - 1 do
			local i = row + x + 1
			local a = amount[i]
			if a > 0 then
				if dry[i] < 1 then
					dry[i] = math.min(1, dry[i] + dryStep)
				end
				a = a - evap
				if a < stain then
					a = if dry[i] >= 0.999 then stain else math.max(a, 0)
				end
				amount[i] = a
				-- still working if anything can still flow or is still drying
				if a > CLING or dry[i] < 0.999 then
					active = true
				end
			end

			if math.abs(a - shown[i]) > 0.02 then
				shown[i] = a
				if a <= 0.001 then
					canvas:SetPixel(x, y, Color3.new(0, 0, 0), 0)
				else
					local fresh = 1 - dry[i]
					local r = dr[1] + (fr[1] - dr[1]) * fresh
					local g = dr[2] + (fr[2] - dr[2]) * fresh
					local b = dr[3] + (fr[3] - dr[3]) * fresh
					local thick = math.clamp(a / CAP, 0, 1) * 0.25
					canvas:SetPixel(
						x,
						y,
						Color3.fromRGB(r * (1 - thick), g * (1 - thick), b * (1 - thick)),
						math.clamp(a / alphaAt, 0, 1)
					)
				end
			end
		end
	end

	self._active = active
	canvas:Render()
end

--[=[
	@within Liquid
	Starts the per-frame simulation loop. Idempotent.
]=]
function Liquid.Start(self: Liquid)
	if self._running then
		return
	end
	self._running = true
	self._conn = RunService.Heartbeat:Connect(function(dt)
		Liquid.Step(self, math.min(dt, 1 / 30)) -- clamp dt so a lag spike doesn't teleport fluid
	end)
end

--[=[
	@within Liquid
	Stops the loop.
]=]
function Liquid.Stop(self: Liquid)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._running = false
end

--[=[
	@within Liquid
	Clears all fluid.
]=]
function Liquid.Clear(self: Liquid)
	for i = 1, self.Width * self.Height do
		self._amount[i] = 0
		self._dry[i] = 0
	end
	self.Canvas:Fill(Color3.new(0, 0, 0), 0)
	for i = 1, self.Width * self.Height do
		self._shown[i] = 0
	end
	self.Canvas:Render()
end

--[=[
	@within Liquid
	Stops the loop and destroys the canvas.
]=]
function Liquid.Destroy(self: Liquid)
	Liquid.Stop(self)
	self.Canvas:Destroy()
end

return Liquid
