-- IMGN
-- _Classes/Blood/init.luau
-- Plinko Labs
--
-- A blood engine built on the Liquid sim, using BLOOD PROXIES. Instead of painting onto whatever
-- part a droplet hits (which scales the canvas to the whole part - a splat on a huge wall comes
-- out low-res and stretched, and forces a per-face axis convention), a hit spawns a small,
-- fixed-size proxy Part at the impact, oriented to the surface, and the blood is painted on THAT.
--
-- The win is twofold: every splat has the same crisp resolution no matter what it landed on, and
-- the proxy is oriented so its canvas +Y points DOWNHILL - so the sim's gravity is just (0,1) and
-- drips run correctly down walls and slopes without guessing SurfaceGui face conventions. Proxies
-- are welded to the hit part (blood follows it) and reused when splats land near each other.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Canvas = require(script.Parent.Canvas)
local Liquid = require(script.Parent.Liquid)
local VectorBlood = require(script.Vector)
local Surface = require(script.Surface)

--[=[
	@class Blood
	A droplet-and-drip blood engine over [Liquid] using [BloodProxy] surfaces. `Blood.Emit` throws
	a droplet, `Blood.KillBrick` makes a brick that spurts blood, `Blood.Splat` paints a hit point.
]=]
local Blood = {}

local SETTINGS = {
	-- "Vector" (default): smooth animated Path2D drips - no pixels, no edges, cheap on any surface.
	-- "Pixel": the Liquid cellular sim (raster; tiles into proxies). Vector is recommended for blood.
	Renderer = "Vector",
	VectorFresh = Color3.fromRGB(135, 8, 10),
	VectorDry = Color3.fromRGB(62, 16, 12),
	ProxySize = 10, -- footprint of a blood proxy, in studs (drip room; vector is cheap at any size)
	ProxyThickness = 0.08,
	ProxyOffset = 0.02, -- how far off the surface to float the proxy (avoid z-fighting)
	PixelsPerStud = 6, -- (Pixel renderer only) resolution per proxy stud, capped below
	MaxResolution = 64,
	EdgeFade = 3, -- (Pixel renderer only) border alpha falloff so its square edge blends out
	ReuseRadius = 6, -- splats within this many studs reuse a proxy (fewer, bigger blood patches)
	Preset = "Blood",
	DropletSize = 0.4,
	DropletColor = Color3.fromRGB(120, 6, 8),
	DropletLifetime = 6,
	SplatAmount = 4,
	FlipDrip = false, -- flip if drips run UP instead of down in your place (single global knob)
	-- cross-surface dripping: fluid reaching a proxy's bottom edge falls off as a droplet
	EdgeDrip = true,
	DripInterval = 0.25, -- min seconds between drips off one proxy edge (throttle = perf)
	DripMin = 1.2, -- bottom-edge fluid must exceed this to shed a drip
	DripTake = 2.5, -- how much fluid each drip carries away
	Ignore = {} :: { Instance }, -- droplets never land on these (your character, the button, …)
}

--[=[
	@within Blood
	Overrides engine defaults: `ProxySize`, `ProxyThickness`, `ProxyOffset`, `PixelsPerStud`,
	`MaxResolution`, `ReuseRadius`, `Preset`, `DropletSize`, `DropletColor`, `DropletLifetime`,
	`SplatAmount`, and `FlipDrip` (set true if drips run upward in your place).
]=]
function Blood.Configure(overrides: { [string]: any })
	for key, value in overrides do
		assert(SETTINGS[key] ~= nil, `IMGN Blood.Configure: unknown key "{tostring(key)}"`)
		SETTINGS[key] = value
	end
end

--[=[
	@within Blood
	Adds an instance (and its descendants) to the ignore list - droplets never land on it. Use it
	for the player's own character, the kill button, etc.
]=]
function Blood.Ignore(instance: Instance)
	if not table.find(SETTINGS.Ignore, instance) then
		table.insert(SETTINGS.Ignore, instance)
	end
end

--[=[
	@within Blood
	Removes an instance from the ignore list.
]=]
function Blood.Unignore(instance: Instance)
	local i = table.find(SETTINGS.Ignore, instance)
	if i then
		table.remove(SETTINGS.Ignore, i)
	end
end

local dropletFolder: Folder
local proxyFolder: Folder

local function folder(name: string, ref: Folder?): Folder
	if not ref or not ref.Parent then
		ref = Instance.new("Folder")
		ref.Name = name
		ref.Parent = Workspace
	end
	return ref
end

-- ============================ BloodProxy ============================

local BloodProxy = {}
BloodProxy.__index = BloodProxy

-- proxies grouped by the part they landed on, for reuse + cleanup (weak so GC can collect)
local proxiesByPart: { [BasePart]: { any } } = setmetatable({}, { __mode = "k" }) :: any

function BloodProxy.new(hitPart: BasePart?, worldPos: Vector3, normal: Vector3)
	local right, up, gravity = Surface.dripBasis(normal)
	if SETTINGS.FlipDrip then
		up = -up
		right = -right
	end

	local vector = SETTINGS.Renderer == "Vector"
	local size = SETTINGS.ProxySize

	local part = Instance.new("Part")
	part.Name = "BloodProxy"
	part.Size = Vector3.new(size, size, SETTINGS.ProxyThickness)
	part.Transparency = 1 -- only the SurfaceGui is visible
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	-- (right, up, normal) is right-handed, so the part's +Z face (Back) points outward along normal
	part.CFrame = CFrame.fromMatrix(worldPos + normal * SETTINGS.ProxyOffset, right, up, normal)

	if hitPart and not hitPart.Anchored then
		part.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = hitPart
		weld.Parent = part
	else
		part.Anchored = true
	end
	part.Parent = folder("IMGNBloodProxies", proxyFolder)
	proxyFolder = part.Parent :: Folder

	local gui = Instance.new("SurfaceGui")
	gui.Name = "IMGNBlood"
	gui.Face = Enum.NormalId.Back -- the +Z face, which faces outward
	gui.Adornee = part

	local self = setmetatable({
		Part = part,
		HitPart = hitPart,
		Center = worldPos,
		Normal = normal,
		Up = up,
		Size = size,
		IsDrip = gravity.Y > 0.5, -- a wall/slope sheds off its bottom edge; a floor just pools
		_dripCD = 0,
	}, BloodProxy)

	if vector then
		-- vector: a fixed 100x100 virtual canvas, smooth Path2D drips, +Y = downhill
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(100, 100)
		gui.Parent = part
		self.Vector = VectorBlood.new(gui, {
			Fresh = SETTINGS.VectorFresh,
			Dry = SETTINGS.VectorDry,
			OnDrip = if SETTINGS.EdgeDrip and self.IsDrip then function(x, y)
				BloodProxy.shed(self, x, y, SETTINGS.SplatAmount * 0.6)
			end else nil,
		})
		self.Vector:Start()
	else
		-- pixel: the Liquid cellular sim on a Frame canvas
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = part
		local res = math.clamp(math.floor(size * SETTINGS.PixelsPerStud), 8, SETTINGS.MaxResolution)
		self.Res = res
		self.Liquid = Liquid.new({
			Canvas = Canvas.new({ Resolution = Vector2.new(res, res), Parent = gui }),
			Preset = SETTINGS.Preset,
			Gravity = gravity,
			EdgeFade = SETTINGS.EdgeFade,
		})
		self.Liquid:Start()
		if SETTINGS.EdgeDrip and self.IsDrip then
			self.Liquid.OnStep = function(dt)
				BloodProxy.checkEdge(self, dt)
			end
		end
	end

	return self
end

-- world position of a canvas point (x, y in 0..1 scale), just off the front of the surface
function BloodProxy.worldOfScale(self: any, x: number, y: number): Vector3
	local lx = (x - 0.5) * self.Size
	local ly = (0.5 - y) * self.Size -- +Y scale is downhill, +Y local is up-slope
	return self.Part.CFrame:PointToWorldSpace(Vector3.new(lx, ly, SETTINGS.ProxyThickness))
end

-- distance (in 0..1 scale, downhill) from a splat point to the hit part's real edge, so drips
-- stop at the actual surface edge instead of floating out onto the oversized proxy.
function BloodProxy.edgeDistanceScale(self: any, worldPos: Vector3): number
	local hp = self.HitPart
	if not hp then
		return 0.96
	end
	local localP = hp.CFrame:PointToObjectSpace(worldPos)
	local localD = hp.CFrame:VectorToObjectSpace(-self.Up) -- downhill in the part's local space
	local half = hp.Size * 0.5
	local tExit = math.huge
	for _, axis in { "X", "Y", "Z" } do
		local d = localD[axis]
		if math.abs(d) > 1e-4 then
			local bound = if d > 0 then half[axis] else -half[axis]
			local t = (bound - localP[axis]) / d
			if t > 0 then
				tExit = math.min(tExit, t)
			end
		end
	end
	if tExit == math.huge then
		return 0.96
	end
	return tExit / self.Size -- studs -> proxy scale
end

-- shed a falling droplet off the edge at scale `(x, y)`, continuing the cascade below
function BloodProxy.shed(self: any, x: number, y: number, amount: number)
	local pos = BloodProxy.worldOfScale(self, x, y)
	local downhill = -self.Up
	local velocity = downhill * 6 + Vector3.new(0, -2, 0)
	Blood.Emit(pos + self.Normal * 0.2, velocity, { Amount = math.max(2, amount) })
end

-- (Pixel renderer) shed off the bottom edge if enough fluid pooled there (throttled)
function BloodProxy.checkEdge(self: any, dt: number)
	self._dripCD -= dt
	if self._dripCD > 0 then
		return
	end
	local x, taken = self.Liquid:TakeFromBottom(SETTINGS.DripMin, SETTINGS.DripTake)
	if not x then
		return
	end
	self._dripCD = SETTINGS.DripInterval
	BloodProxy.shed(self, (x + 0.5) / self.Res, 0.97, taken :: number)
end

-- world point -> this proxy's canvas scale (0..1, +Y down)
function BloodProxy.Scale(self: any, worldPos: Vector3): (number, number)
	local lp = self.Part.CFrame:PointToObjectSpace(worldPos)
	return math.clamp(0.5 + lp.X / self.Size, 0, 1), math.clamp(0.5 - lp.Y / self.Size, 0, 1)
end

function BloodProxy.Splat(self: any, worldPos: Vector3, amount: number)
	local sx, sy = BloodProxy.Scale(self, worldPos)
	if self.Vector then
		if self.IsDrip then
			-- stop drips at the part's real edge (or the proxy's, whichever is nearer)
			local edgeY = math.clamp(sy + BloodProxy.edgeDistanceScale(self, worldPos), sy + 0.02, 0.96)
			self.Vector:Splat(sx, sy, amount, { EdgeY = edgeY })
		else
			self.Vector:Splat(sx, sy, amount, { Puddle = true }) -- floor/ceiling: spread a puddle
		end
	else
		self.Liquid:Splat(math.floor(sx * self.Res), math.floor(sy * self.Res), amount, { Spread = 3 + amount })
	end
end

-- find a nearby proxy on the same part facing the same way, or make a new one
local function proxyFor(hitPart: BasePart?, worldPos: Vector3, normal: Vector3)
	local key = hitPart or Workspace
	local list = proxiesByPart[key]
	if not list then
		list = {}
		proxiesByPart[key] = list
	end
	for i = #list, 1, -1 do
		local p = list[i]
		if not p.Part.Parent then
			table.remove(list, i) -- cleaned up elsewhere
		elseif (p.Center - worldPos).Magnitude <= SETTINGS.ReuseRadius and p.Normal:Dot(normal) > 0.8 then
			return p
		end
	end
	local proxy = BloodProxy.new(hitPart, worldPos, normal)
	table.insert(list, proxy)
	return proxy
end

--[=[
	@within Blood
	Splats `amount` of blood at `worldPos` on a surface with outward `normal` (e.g. a raycast hit).
	`hitPart` is what it landed on (so the proxy can follow it); pass `nil` for a static splat.
]=]
function Blood.Splat(hitPart: BasePart?, worldPos: Vector3, normal: Vector3, amount: number?)
	proxyFor(hitPart, worldPos, normal):Splat(worldPos, amount or SETTINGS.SplatAmount)
end

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
	when it lands it spawns a [BloodProxy] there (drips down the surface) and is destroyed.
]=]
function Blood.Emit(origin: Vector3, velocity: Vector3, options: { Amount: number? }?)
	local opts = options or {}
	dropletFolder = folder("IMGNBloodDroplets", dropletFolder)

	local drop = Instance.new("Part")
	drop.Name = "BloodDroplet"
	drop.Shape = Enum.PartType.Ball
	drop.Size = Vector3.new(SETTINGS.DropletSize, SETTINGS.DropletSize, SETTINGS.DropletSize)
	drop.Color = SETTINGS.DropletColor
	drop.Material = Enum.Material.SmoothPlastic
	drop.CanCollide = false
	drop.CanQuery = false
	drop.CFrame = CFrame.new(origin)
	drop.Parent = dropletFolder
	drop.AssemblyLinearVelocity = velocity

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- never land on our own droplets/proxies, or anything the user told us to ignore (their
	-- character, the kill button, …)
	local exclude = { dropletFolder, proxyFolder }
	for _, inst in SETTINGS.Ignore do
		table.insert(exclude, inst)
	end
	params.FilterDescendantsInstances = exclude

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
			if hit then
				conn:Disconnect()
				Blood.Splat(hit.Instance, hit.Position, hit.Normal, opts.Amount or SETTINGS.SplatAmount)
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
	Turns `part` into a kill brick: a character with a Humanoid that touches it is killed and a
	spray of droplets bursts from the contact point, each landing and dripping. `options`:
	`Droplets`, `Spread`, `Up`, `Amount`.
]=]
function Blood.KillBrick(part: BasePart, options: { Droplets: number?, Spread: number?, Up: number?, Amount: number? }?)
	local opts = options or {}
	local droplets = opts.Droplets or 6
	local spread = opts.Spread or 14
	local up = opts.Up or 20
	local debounce: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	part.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then
			return
		end
		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid or not humanoid:IsA("Humanoid") or humanoid.Health <= 0 or debounce[character] then
			return
		end
		debounce[character] = true

		local origin = hit.Position + Vector3.new(0, 2, 0)
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
