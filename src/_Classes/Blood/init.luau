-- IMGN
-- _Classes/Blood/init.luau
-- Plinko Labs
--
-- A small blood engine built on the Liquid sim. The flow: emit a real 3D droplet Part that flies
-- and falls under Roblox gravity; a per-frame raycast catches the surface it lands on; that
-- surface is turned (once) into an IMGN canvas with a Liquid("Blood") sim whose Gravity is the
-- face's downhill direction (so it drips correctly on walls, slopes, rotated parts); the droplet
-- shrinks and is destroyed. KillBrick wires all this to a Touched kill.
--
-- The 2D simulation + the gravity projection are verified; the 3D parts (droplet physics, the
-- raycast landing, face/UV mapping in Surface) follow Roblox conventions that need a Studio pass.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Canvas = require(script.Parent.Canvas)
local Liquid = require(script.Parent.Liquid)
local Surface = require(script.Surface)

--[=[
	@class Blood
	A droplet-and-drip blood engine over [Liquid]. `Blood.Emit` throws a droplet, `Blood.KillBrick`
	makes a brick that spurts blood when stepped on, `Blood.Splat` paints directly onto a surface.
]=]
local Blood = {}

local SETTINGS = {
	PixelsPerStud = 10, -- canvas resolution per stud of surface
	MaxResolution = 160, -- clamp so a big wall doesn't melt the renderer
	Preset = "Blood",
	DropletSize = 0.4,
	DropletColor = Color3.fromRGB(120, 6, 8),
	DropletLifetime = 6, -- seconds before a droplet that never lands is cleaned up
	SplatAmount = 4,
	Dynamic = true, -- recompute each surface's gravity per frame (drips react to rotation)
}

--[=[
	@within Blood
	Overrides engine defaults: `PixelsPerStud`, `MaxResolution`, `Preset`, `DropletSize`,
	`DropletColor`, `DropletLifetime`, `SplatAmount`, `Dynamic`.
]=]
function Blood.Configure(overrides: { [string]: any })
	for key, value in overrides do
		assert(SETTINGS[key] ~= nil, `IMGN Blood.Configure: unknown key "{tostring(key)}"`)
		SETTINGS[key] = value
	end
end

-- a folder to hold droplets, so raycasts can ignore them all at once
local dropletFolder: Folder

local function getDropletFolder(): Folder
	if not dropletFolder or not dropletFolder.Parent then
		dropletFolder = Instance.new("Folder")
		dropletFolder.Name = "IMGNBloodDroplets"
		dropletFolder.Parent = Workspace
	end
	return dropletFolder
end

-- ============================ BloodSurface ============================
-- One canvas + Liquid sim bound to a part's face. Created lazily on first splat, then reused.

local BloodSurface = {}
BloodSurface.__index = BloodSurface

-- key a part/face pair to its BloodSurface
local surfaces: { [BasePart]: { [Enum.NormalId]: any } } = setmetatable({}, { __mode = "k" })

local function faceExtent(part: BasePart, right: Vector3, down: Vector3): (number, number)
	local s = part.Size
	local w = math.abs(right.X * s.X) + math.abs(right.Y * s.Y) + math.abs(right.Z * s.Z)
	local h = math.abs(down.X * s.X) + math.abs(down.Y * s.Y) + math.abs(down.Z * s.Z)
	return w, h
end

function BloodSurface.new(part: BasePart, normalId: Enum.NormalId)
	local _normal, right, down = Surface.faceVectors(part, normalId)
	local wStuds, hStuds = faceExtent(part, right, down)
	local resW = math.clamp(math.floor(wStuds * SETTINGS.PixelsPerStud), 8, SETTINGS.MaxResolution)
	local resH = math.clamp(math.floor(hStuds * SETTINGS.PixelsPerStud), 8, SETTINGS.MaxResolution)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "IMGNBlood"
	gui.Face = normalId
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Adornee = part
	gui.Parent = part

	local canvas = Canvas.new({ Resolution = Vector2.new(resW, resH), Parent = gui })
	local liquid = Liquid.new({
		Canvas = canvas,
		Preset = SETTINGS.Preset,
		Gravity = Surface.gravityVector(right, down),
	})
	liquid:Start()

	local self = setmetatable({
		Part = part,
		Face = normalId,
		Liquid = liquid,
		Width = resW,
		Height = resH,
		_gui = gui,
	}, BloodSurface)

	-- drips react to the part's current orientation
	if SETTINGS.Dynamic then
		self._conn = RunService.Heartbeat:Connect(function()
			if not part.Parent then
				self:Destroy()
				return
			end
			local _n, r, d = Surface.faceVectors(part, normalId)
			liquid.Gravity = Surface.gravityVector(r, d)
		end)
	end

	return self
end

function BloodSurface.Splat(self: any, worldPos: Vector3, amount: number, velocity: Vector3?)
	local px, py = Surface.worldToPixel(self.Part, self.Face, worldPos, self.Width, self.Height)
	local canvasVel = Vector2.zero
	if velocity then
		local _n, right, down = Surface.faceVectors(self.Part, self.Face)
		canvasVel = Vector2.new(velocity:Dot(right), velocity:Dot(down)) * 0.5
	end
	self.Liquid:Splat(px, py, amount, { Spread = 4 + amount, Velocity = canvasVel })
end

function BloodSurface.Destroy(self: any)
	if self._conn then
		self._conn:Disconnect()
	end
	if surfaces[self.Part] then
		surfaces[self.Part][self.Face] = nil
	end
	self.Liquid:Destroy()
	if self._gui then
		self._gui:Destroy()
	end
end

--[=[
	@within Blood
	The [BloodSurface] for a part's face, creating and caching it on first use. Use this (or
	`Blood.Splat`) to paint onto a surface without going through a droplet.
]=]
function Blood.SurfaceFor(part: BasePart, normalId: Enum.NormalId): any
	local byFace = surfaces[part]
	if not byFace then
		byFace = {}
		surfaces[part] = byFace
	end
	if not byFace[normalId] then
		byFace[normalId] = BloodSurface.new(part, normalId)
	end
	return byFace[normalId]
end

--[=[
	@within Blood
	Splats `amount` of blood at `worldPos` on `part`'s `normalId` face (optionally biased by a 3D
	`velocity`), turning that face into a dripping canvas if it isn't one already.
]=]
function Blood.Splat(part: BasePart, normalId: Enum.NormalId, worldPos: Vector3, amount: number?, velocity: Vector3?)
	Blood.SurfaceFor(part, normalId):Splat(worldPos, amount or SETTINGS.SplatAmount, velocity)
end

-- shrink a landed droplet, then destroy it
local function popDroplet(drop: BasePart)
	local tween = TweenService:Create(drop, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Size = Vector3.new(0.01, 0.01, 0.01) })
	tween.Completed:Connect(function()
		drop:Destroy()
	end)
	tween:Play()
end

--[=[
	@within Blood
	Emits a real 3D blood droplet from `origin` with initial `velocity`. It falls under gravity;
	when it lands on a surface it splats there (drips down that surface) and is destroyed.
	`options.Amount` sets the splat size.
]=]
function Blood.Emit(origin: Vector3, velocity: Vector3, options: { Amount: number? }?)
	local opts = options or {}
	local drop = Instance.new("Part")
	drop.Name = "BloodDroplet"
	drop.Shape = Enum.PartType.Ball
	drop.Size = Vector3.new(SETTINGS.DropletSize, SETTINGS.DropletSize, SETTINGS.DropletSize)
	drop.Color = SETTINGS.DropletColor
	drop.Material = Enum.Material.Glass
	drop.CanCollide = false
	drop.CanQuery = false
	drop.CFrame = CFrame.new(origin)
	drop.Parent = getDropletFolder()
	drop.AssemblyLinearVelocity = velocity

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getDropletFolder() }

	local last = origin
	local born = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not drop.Parent then
			conn:Disconnect()
			return
		end
		if os.clock() - born > SETTINGS.DropletLifetime then
			conn:Disconnect()
			drop:Destroy()
			return
		end

		local cur = drop.Position
		local step = cur - last
		if step.Magnitude > 1e-3 then
			local hit = Workspace:Raycast(last, step, params)
			if hit and hit.Instance then
				conn:Disconnect()
				local face = Surface.faceFromNormal(hit.Instance, hit.Normal)
				Blood.Splat(hit.Instance, face, hit.Position, opts.Amount or SETTINGS.SplatAmount, velocity)
				drop.Anchored = true
				popDroplet(drop)
				return
			end
		end
		last = cur
	end)
end

--[=[
	@within Blood
	Turns `part` into a kill brick: when a character with a Humanoid touches it, the Humanoid is
	killed and a spray of droplets bursts from the contact point, landing and dripping on whatever
	they hit. `options`: `Droplets` (count), `Spread` (sideways speed), `Up` (upward speed),
	`Amount` (per-splat).
]=]
function Blood.KillBrick(part: BasePart, options: { Droplets: number?, Spread: number?, Up: number?, Amount: number? }?)
	local opts = options or {}
	local droplets = opts.Droplets or 14
	local spread = opts.Spread or 16
	local up = opts.Up or 24
	local debounce: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	part.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then
			return
		end
		local humanoid = character:FindFirstChildOfType("Humanoid")
		if not humanoid or humanoid.Health <= 0 or debounce[character] then
			return
		end
		debounce[character] = true

		local origin = (hit.Position + Vector3.new(0, 2, 0))
		humanoid.Health = 0
		for _ = 1, droplets do
			local v = Vector3.new(
				(math.random() - 0.5) * spread,
				up * (0.5 + math.random() * 0.5),
				(math.random() - 0.5) * spread
			)
			Blood.Emit(origin, v, { Amount = opts.Amount })
		end
	end)
end

return Blood
