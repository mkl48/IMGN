-- IMGN
-- _Classes/Raycaster/init.luau
-- Plinko Labs
--
-- A software 3D engine on a Canvas - a textured raycaster (Wolfenstein/Doom style). It casts one
-- ray per screen column across a grid map (DDA), draws a perspective-correct, textured wall slice
-- with distance fog + N/S face shading, fills a faded floor/ceiling, and depth-sorts billboard
-- sprites against the wall depth buffer. One ray per column (not per pixel) keeps it fast enough to
-- run live on a Frame canvas. Real-time 3D, rendered into a GUI, no MeshParts.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Canvas = require(script.Parent.Canvas)

--[=[
	@class Raycaster
	A textured raycasting 3D renderer drawing on a [Canvas]. Build with [IMGN.Raycaster], move the
	camera (`:Move`/`:Turn`/`:SetCamera`), add `:AddSprite`s, and `:Render()` (or `:Start()` for a
	built-in WASD loop).
]=]
local Raycaster = {}
Raycaster.__index = Raycaster

export type RaycasterConfig = {
	Canvas: Canvas.Canvas?,
	Resolution: Vector2?,
	Parent: Instance?,
	Driver: any?,
	Map: { string }, -- rows of wall ids; "." or " " is empty, any other char is a wall id
	Textures: { [string]: (u: number, v: number) -> Color3? }, -- per wall-id texture sampler
	Default: ((u: number, v: number) -> Color3?)?, -- fallback wall texture
	FOV: number?, -- degrees (default 66)
	Ceiling: Color3?,
	Floor: Color3?,
	Fog: Color3?,
	FogStart: number?,
	FogEnd: number?,
	StartX: number?,
	StartY: number?,
	StartAngle: number?,
	MoveSpeed: number?,
	TurnSpeed: number?,
}

export type Raycaster = typeof(setmetatable({} :: any, Raycaster))

local function pick<T>(v: T?, d: T): T
	if v == nil then
		return d
	end
	return v
end

function Raycaster.new(config: RaycasterConfig): Raycaster
	local canvas = config.Canvas
	if not canvas then
		assert(config.Resolution, "IMGN.Raycaster: pass a Canvas or a Resolution")
		canvas = Canvas.new({ Resolution = config.Resolution, Parent = config.Parent, Driver = config.Driver })
	end

	local fog = config.Fog or Color3.fromRGB(20, 22, 30)
	local ceiling = config.Ceiling or Color3.fromRGB(35, 40, 60)
	local floor = config.Floor or Color3.fromRGB(45, 40, 35)

	-- precompute the floor/ceiling vertical gradient (same every column): fade to fog at the horizon
	local H = canvas.Height
	local half = H / 2
	local vert = {}
	for y = 0, H - 1 do
		if y < half then
			vert[y] = ceiling:Lerp(fog, y / half) -- top -> horizon
		else
			vert[y] = fog:Lerp(floor, (y - half) / half) -- horizon -> bottom
		end
	end

	local self = setmetatable({
		Canvas = canvas,
		Map = config.Map,
		MapW = #config.Map[1],
		MapH = #config.Map,
		Fog = fog,
		Ceiling = ceiling,
		Floor = floor,
		FogStart = config.FogStart or 1.5,
		FogEnd = config.FogEnd or 12,
		MoveSpeed = config.MoveSpeed or 3,
		TurnSpeed = config.TurnSpeed or 2.4,
		DefaultTexture = config.Default or function()
			return Color3.fromRGB(120, 120, 130)
		end,
		_tex = config.Textures or {},
		_sprites = {},
		_depth = {},
		_vert = vert,
		_conn = nil,
		PosX = config.StartX or 2,
		PosY = config.StartY or 2,
	}, Raycaster)

	self._maxSteps = self.MapW + self.MapH + 8
	local planeLen = math.tan(math.rad(config.FOV or 66) / 2)
	self._planeLen = planeLen
	Raycaster.SetCamera(self, self.PosX, self.PosY, config.StartAngle or 0)
	return self
end

-- the wall id at a map cell ("0"/empty -> 0; out of bounds -> a border wall)
function Raycaster.wallAt(self: Raycaster, mx: number, my: number): any
	if mx < 0 or my < 0 or mx >= self.MapW or my >= self.MapH then
		return "#"
	end
	local ch = string.sub(self.Map[my + 1], mx + 1, mx + 1)
	if ch == "." or ch == " " or ch == "" then
		return 0
	end
	return ch
end

--[=[
	@within Raycaster
	Points the camera: position `(x, y)` and facing `angle` (radians).
]=]
function Raycaster.SetCamera(self: Raycaster, x: number, y: number, angle: number)
	self.PosX, self.PosY = x, y
	self.DirX, self.DirY = math.cos(angle), math.sin(angle)
	self.PlaneX, self.PlaneY = -self.DirY * self._planeLen, self.DirX * self._planeLen
end

--[=[
	@within Raycaster
	Moves the camera `forward` (+/-1) and `strafe` (+/-1) for `dt` seconds, sliding along walls.
]=]
function Raycaster.Move(self: Raycaster, forward: number, strafe: number, dt: number)
	local speed = self.MoveSpeed * dt
	local nx = self.PosX + (self.DirX * forward - self.DirY * strafe) * speed
	local ny = self.PosY + (self.DirY * forward + self.DirX * strafe) * speed
	if Raycaster.wallAt(self, math.floor(nx), math.floor(self.PosY)) == 0 then
		self.PosX = nx
	end
	if Raycaster.wallAt(self, math.floor(self.PosX), math.floor(ny)) == 0 then
		self.PosY = ny
	end
end

--[=[
	@within Raycaster
	Rotates the camera by `amount` radians.
]=]
function Raycaster.Turn(self: Raycaster, amount: number)
	local c, s = math.cos(amount), math.sin(amount)
	local dx, dy = self.DirX, self.DirY
	self.DirX, self.DirY = dx * c - dy * s, dx * s + dy * c
	local px, py = self.PlaneX, self.PlaneY
	self.PlaneX, self.PlaneY = px * c - py * s, px * s + py * c
end

--[=[
	@within Raycaster
	Adds a billboard sprite at world `(x, y)` with a texture sampler. Returns the sprite (mutate its
	`X`/`Y` to move it).
]=]
function Raycaster.AddSprite(self: Raycaster, x: number, y: number, texture: (u: number, v: number) -> Color3?)
	local sprite = { X = x, Y = y, Texture = texture }
	table.insert(self._sprites, sprite)
	return sprite
end

local function shade(self: Raycaster, color: Color3, dist: number, side: number): Color3
	local f = math.clamp((self.FogEnd - dist) / (self.FogEnd - self.FogStart), 0, 1)
	if side == 1 then
		f *= 0.7 -- darken N/S faces so corners read
	end
	return color:Lerp(self.Fog, 1 - f)
end

--[=[
	@within Raycaster
	Renders the 3D view to the canvas and flushes it.
]=]
function Raycaster.Render(self: Raycaster)
	local canvas = self.Canvas
	local W, H = canvas.Width, canvas.Height
	local posX, posY = self.PosX, self.PosY
	local dirX, dirY = self.DirX, self.DirY
	local planeX, planeY = self.PlaneX, self.PlaneY
	local depth, vert = self._depth, self._vert
	local halfH = H / 2

	for x = 0, W - 1 do
		local cameraX = 2 * x / W - 1
		local rayX = dirX + planeX * cameraX
		local rayY = dirY + planeY * cameraX

		local mapX, mapY = math.floor(posX), math.floor(posY)
		local deltaX = if rayX == 0 then 1e30 else math.abs(1 / rayX)
		local deltaY = if rayY == 0 then 1e30 else math.abs(1 / rayY)
		local stepX, sideX, stepY, sideY
		if rayX < 0 then
			stepX, sideX = -1, (posX - mapX) * deltaX
		else
			stepX, sideX = 1, (mapX + 1 - posX) * deltaX
		end
		if rayY < 0 then
			stepY, sideY = -1, (posY - mapY) * deltaY
		else
			stepY, sideY = 1, (mapY + 1 - posY) * deltaY
		end

		local side, id, steps = 0, 0, 0
		repeat
			if sideX < sideY then
				sideX += deltaX
				mapX += stepX
				side = 0
			else
				sideY += deltaY
				mapY += stepY
				side = 1
			end
			id = Raycaster.wallAt(self, mapX, mapY)
			steps += 1
		until id ~= 0 or steps > self._maxSteps

		local dist = math.max(if side == 0 then sideX - deltaX else sideY - deltaY, 0.0001)
		depth[x] = dist

		local lineH = H / dist
		local top = halfH - lineH / 2
		local drawStart = math.max(0, math.floor(top))
		local drawEnd = math.min(H - 1, math.floor(halfH + lineH / 2))

		local wallX = if side == 0 then posY + dist * rayY else posX + dist * rayX
		wallX -= math.floor(wallX)
		if (side == 0 and rayX > 0) or (side == 1 and rayY < 0) then
			wallX = 1 - wallX -- keep texture orientation consistent on opposite faces
		end
		local tex = self._tex[id] or self.DefaultTexture

		-- ceiling above the wall, then the wall slice, then floor below
		for y = 0, drawStart - 1 do
			canvas:SetPixel(x, y, vert[y])
		end
		for y = drawStart, drawEnd do
			local v = (y - top) / lineH
			local c = tex(wallX, v) or self.DefaultTexture(wallX, v) or self.Floor
			canvas:SetPixel(x, y, shade(self, c, dist, side))
		end
		for y = drawEnd + 1, H - 1 do
			canvas:SetPixel(x, y, vert[y])
		end
	end

	-- billboard sprites: depth-sorted, projected, depth-tested per column
	local sprites = self._sprites
	if #sprites > 0 then
		table.sort(sprites, function(a, b)
			local da = (a.X - posX) ^ 2 + (a.Y - posY) ^ 2
			local db = (b.X - posX) ^ 2 + (b.Y - posY) ^ 2
			return da > db -- far first
		end)
		local invDet = 1 / (planeX * dirY - dirX * planeY)
		for _, sprite in sprites do
			local relX, relY = sprite.X - posX, sprite.Y - posY
			local tX = invDet * (dirY * relX - dirX * relY)
			local tY = invDet * (-planeY * relX + planeX * relY) -- depth
			if tY > 0.1 then
				local screenX = math.floor((W / 2) * (1 + tX / tY))
				local size = math.abs(math.floor(H / tY))
				local startX = math.max(0, math.floor(screenX - size / 2))
				local endX = math.min(W - 1, math.floor(screenX + size / 2))
				local startY = math.max(0, math.floor(halfH - size / 2))
				local endY = math.min(H - 1, math.floor(halfH + size / 2))
				for stripe = startX, endX do
					if tY < (depth[stripe] or 1e9) then -- in front of the wall here
						local u = (stripe - (screenX - size / 2)) / size
						for y = startY, endY do
							local v = (y - (halfH - size / 2)) / size
							local c = sprite.Texture(u, v)
							if c then
								canvas:SetPixel(stripe, y, shade(self, c, tY, 0))
							end
						end
					end
				end
			end
		end
	end

	canvas:Render()
end

--[=[
	@within Raycaster
	Starts a built-in loop: WASD to move + strafe, arrow/Q-E to turn, rendering every frame.
	Client-side. Returns nothing; call [Raycaster:Stop] to end.
]=]
function Raycaster.Start(self: Raycaster)
	if self._conn then
		return
	end
	self._conn = RunService.RenderStepped:Connect(function(dt)
		local fwd = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0)
			- (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
		local strafe = (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
			- (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
		local turn = (if UserInputService:IsKeyDown(Enum.KeyCode.Right) or UserInputService:IsKeyDown(Enum.KeyCode.E) then 1 else 0)
			- (if UserInputService:IsKeyDown(Enum.KeyCode.Left) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then 1 else 0)
		if fwd ~= 0 or strafe ~= 0 then
			Raycaster.Move(self, fwd, strafe, dt)
		end
		if turn ~= 0 then
			Raycaster.Turn(self, turn * self.TurnSpeed * dt)
		end
		Raycaster.Render(self)
	end)
end

--[=[
	@within Raycaster
	Stops the built-in loop.
]=]
function Raycaster.Stop(self: Raycaster)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

return Raycaster
