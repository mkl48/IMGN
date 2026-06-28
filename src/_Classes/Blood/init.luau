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
	-- "Pixel" (default): the Liquid cellular SIM on a canvas that covers the WHOLE part (the
	--   original full-surface look), rendered with the Sparse driver so only painted pixels cost
	--   anything - the way to run it on big parts without the lag.
	-- "Fluid": the Liquid sim on a small Blob-circle patch (smooth/organic, localized).
	-- "Vector": smooth animated Path2D drips (scripted, the cheapest).
	Renderer = "Pixel",
	VectorFresh = Color3.fromRGB(135, 8, 10),
	VectorDry = Color3.fromRGB(62, 16, 12),
	ProxySize = 10, -- (Fluid/Vector) footprint of a localized patch, in studs (clamped to the part)
	ProxyThickness = 0.08,
	ProxyOffset = 0.02, -- how far off the surface to float the canvas (avoid z-fighting)
	PixelsPerStud = 4, -- (Pixel) resolution per stud of the full-part canvas
	FluidPixelsPerStud = 3, -- (Fluid) low res - the circles melt the grid so it still looks smooth
	MaxResolution = 160, -- per-axis cap so a huge part doesn't make a giant grid
	EdgeFade = 0, -- (Fluid/Pixel) border alpha falloff (0 = off; the canvas now matches the part)
	ReuseRadius = 6, -- (Fluid/Vector) splats within this many studs reuse a patch
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

-- full extent (studs) of `part`'s box projected onto world direction `dir`
local function extentAlong(part: BasePart, dir: Vector3): number
	local cf = part.CFrame
	local s = part.Size
	return math.abs(dir:Dot(cf.RightVector)) * s.X
		+ math.abs(dir:Dot(cf.UpVector)) * s.Y
		+ math.abs(dir:Dot(cf.LookVector)) * s.Z
end

-- distance from `worldPos` along world `dir` until it exits `part`'s box (studs)
local function exitDistance(part: BasePart, worldPos: Vector3, dir: Vector3): number
	local localP = part.CFrame:PointToObjectSpace(worldPos)
	local localD = part.CFrame:VectorToObjectSpace(dir)
	local half = part.Size * 0.5
	local t = math.huge
	for _, axis in { "X", "Y", "Z" } do
		local d = (localD :: any)[axis]
		if math.abs(d) > 1e-4 then
			local bound = if d > 0 then (half :: any)[axis] else -(half :: any)[axis]
			local tt = (bound - (localP :: any)[axis]) / d
			if tt > 0 then
				t = math.min(t, tt)
			end
		end
	end
	return t
end

function BloodProxy.new(hitPart: BasePart?, worldPos: Vector3, normal: Vector3)
	local right, up, gravity = Surface.dripBasis(normal)
	if SETTINGS.FlipDrip then
		up = -up
		right = -right
	end

	local renderer = SETTINGS.Renderer
	local vector = renderer == "Vector"
	local fullFace = renderer == "Pixel" -- cover the whole part (sparse) vs a localized patch

	-- size + position the canvas. Full-face: a rectangle covering the whole part, centred on its
	-- face. Patch: a small square clamped to fit inside the part around the splat.
	local sizeR, sizeU, center
	if fullFace and hitPart then
		sizeR = math.max(extentAlong(hitPart, right), 0.5)
		sizeU = math.max(extentAlong(hitPart, up), 0.5)
		center = hitPart.Position + normal * (extentAlong(hitPart, normal) * 0.5)
	else
		local s = SETTINGS.ProxySize
		if hitPart then
			local dR = math.min(exitDistance(hitPart, worldPos, right), exitDistance(hitPart, worldPos, -right))
			local dU = math.min(exitDistance(hitPart, worldPos, up), exitDistance(hitPart, worldPos, -up))
			s = math.clamp(math.min(s, 2 * dR, 2 * dU), 1, SETTINGS.ProxySize)
		end
		sizeR, sizeU, center = s, s, worldPos
	end

	local part = Instance.new("Part")
	part.Name = "BloodProxy"
	part.Size = Vector3.new(sizeR, sizeU, SETTINGS.ProxyThickness)
	part.Transparency = 1 -- only the SurfaceGui is visible
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	-- (right, up, normal) is right-handed, so the part's +Z face (Back) points outward along normal
	part.CFrame = CFrame.fromMatrix(center + normal * SETTINGS.ProxyOffset, right, up, normal)

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
		Center = center,
		Normal = normal,
		Up = up,
		SizeR = sizeR,
		SizeU = sizeU,
		FullFace = fullFace,
		IsDrip = gravity.Y > 0.5, -- a wall/slope sheds off its bottom edge; a floor just pools
		_dripCD = 0,
	}, BloodProxy)

	if vector then
		-- a fixed 100x100 virtual canvas, smooth Path2D drips, +Y = downhill
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
		-- the Liquid cellular sim. "Pixel" = full part, Sparse driver (only painted pixels cost);
		-- "Fluid" = a Blob-circle patch.
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.Parent = part
		local ppstud = if fullFace then SETTINGS.PixelsPerStud else SETTINGS.FluidPixelsPerStud
		self.ResW = math.clamp(math.floor(sizeR * ppstud), 8, SETTINGS.MaxResolution)
		self.ResH = math.clamp(math.floor(sizeU * ppstud), 8, SETTINGS.MaxResolution)
		self.Liquid = Liquid.new({
			Canvas = Canvas.new({
				Resolution = Vector2.new(self.ResW, self.ResH),
				Parent = gui,
				Driver = if fullFace then "Sparse" else "Blob",
			}),
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
	local lx = (x - 0.5) * self.SizeR
	local ly = (0.5 - y) * self.SizeU -- +Y scale is downhill, +Y local is up-slope
	return self.Part.CFrame:PointToWorldSpace(Vector3.new(lx, ly, SETTINGS.ProxyThickness))
end

-- distance (in 0..1 scale, downhill) from a splat point to the hit part's real edge, so drips
-- stop at the actual surface edge instead of floating out onto the canvas.
function BloodProxy.edgeDistanceScale(self: any, worldPos: Vector3): number
	if not self.HitPart then
		return 0.96
	end
	local tExit = exitDistance(self.HitPart, worldPos, -self.Up) -- downhill to the part edge
	if tExit == math.huge then
		return 0.96
	end
	return tExit / self.SizeU -- studs -> scale (downhill is the up/U axis)
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
	BloodProxy.shed(self, (x + 0.5) / self.ResW, 0.97, taken :: number)
end

-- world point -> this proxy's canvas scale (0..1, +Y down)
function BloodProxy.Scale(self: any, worldPos: Vector3): (number, number)
	local lp = self.Part.CFrame:PointToObjectSpace(worldPos)
	return math.clamp(0.5 + lp.X / self.SizeR, 0, 1), math.clamp(0.5 - lp.Y / self.SizeU, 0, 1)
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
		self.Liquid:Splat(math.floor(sx * self.ResW), math.floor(sy * self.ResH), amount, { Spread = 3 + amount })
	end
end

-- find an existing canvas for this hit, or make one. Full-face (Pixel) keeps ONE canvas per
-- part+face (it covers the whole part); patch renderers reuse any canvas within ReuseRadius.
local function proxyFor(hitPart: BasePart?, worldPos: Vector3, normal: Vector3)
	local key = hitPart or Workspace
	local list = proxiesByPart[key]
	if not list then
		list = {}
		proxiesByPart[key] = list
	end
	local fullFace = SETTINGS.Renderer == "Pixel"
	for i = #list, 1, -1 do
		local p = list[i]
		if not p.Part.Parent then
			table.remove(list, i) -- cleaned up elsewhere
		elseif p.Normal:Dot(normal) > 0.8 then
			-- same face (full-face), or a near-enough patch
			if fullFace or (p.Center - worldPos).Magnitude <= SETTINGS.ReuseRadius then
				return p
			end
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
