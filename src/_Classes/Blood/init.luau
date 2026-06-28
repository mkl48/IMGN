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
	PixelsPerStud = 4, -- (Pixel) resolution per stud of the canvas
	FluidPixelsPerStud = 3, -- (Fluid) low res - the circles melt the grid so it still looks smooth
	MaxCanvasStuds = 18, -- (Pixel) if the part is bigger than this, use a good-size patch near the
	-- splat instead of one stretched canvas - keeps pixel density (and detail) consistent.
	MaxResolution = 96, -- per-axis pixel cap (safety net)
	EdgeFade = 0, -- (Fluid/Pixel) border alpha falloff (0 = off; the canvas now matches the part)
	ReuseRadius = 6, -- (Fluid/Vector) splats within this many studs reuse a patch
	Preset = "Blood",
	DropletSize = 0.4,
	DropletColor = Color3.fromRGB(120, 6, 8),
	DropletLifetime = 6,
	SplatAmount = 4,
	FlipDrip = false, -- flip if drips run UP instead of down in your place (single global knob)
	-- cross-surface dripping: fluid reaching an edge wraps onto / flows onto the next surface, and
	-- only falls as a droplet when there's nothing to travel down
	EdgeDrip = true,
	WrapReach = 3, -- how far (studs) past an edge to look for a surface to continue on before dripping
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

-- raycast params that ignore our own blood (droplets, proxies) and the user's ignore list
local function bloodRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if dropletFolder then
		table.insert(exclude, dropletFolder)
	end
	if proxyFolder then
		table.insert(exclude, proxyFolder)
	end
	for _, inst in SETTINGS.Ignore do
		table.insert(exclude, inst)
	end
	params.FilterDescendantsInstances = exclude
	return params
end

-- Blood reaching an edge at `worldPos` (on a face with outward `normal`, flowing along world
-- `downhill`): follow the geometry if it can, else fall. (1) wrap around a convex corner onto the
-- same part's adjacent face; (2) flow onto a surface just past/below the edge; (3) otherwise detach
-- as a falling droplet. Shared by the proxy and face-canvas renderers.
local function shedFrom(hitPart: BasePart?, worldPos: Vector3, normal: Vector3, downhill: Vector3, amount: number)
	amount = math.max(2, amount)

	-- 1) wrap onto the adjacent face the blood exits toward (its normal best matches downhill),
	-- unless that's the face we're on or an underside.
	if hitPart then
		local nid = Surface.faceFromNormal(hitPart, downhill)
		local wrapN = hitPart.CFrame:VectorToWorldSpace(Vector3.fromNormalId(nid)).Unit
		if wrapN:Dot(normal) < 0.9 and wrapN:Dot(Vector3.new(0, -1, 0)) < 0.45 then
			Blood.Splat(hitPart, worldPos + wrapN * 0.05, wrapN, amount)
			return
		end
	end

	-- 2) a surface just past/below the edge to continue on (wall meets floor, ledge to a step)
	local params = bloodRaycastParams()
	local start = worldPos + normal * 0.05
	local hit = Workspace:Raycast(start + downhill * 0.1, Vector3.new(0, -SETTINGS.WrapReach, 0), params)
		or Workspace:Raycast(start, downhill * SETTINGS.WrapReach, params)
	if hit and hit.Instance then
		Blood.Splat(hit.Instance, hit.Position, hit.Normal, amount)
		return
	end

	-- 3) nothing to travel down -> a real hanging drip
	Blood.Emit(worldPos + normal * 0.2, downhill * 4 + Vector3.new(0, -3, 0), { Amount = amount })
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
	local pixel = renderer == "Pixel"

	-- size + position the canvas. Pixel: cover the whole part if it fits within MaxCanvasStuds,
	-- otherwise a good-size patch near the splat (so pixel density stays consistent on huge parts).
	-- Fluid/Vector: a small square patch clamped to fit inside the part around the splat.
	local sizeR, sizeU, center
	if pixel and hitPart then
		local extR = math.max(extentAlong(hitPart, right), 0.5)
		local extU = math.max(extentAlong(hitPart, up), 0.5)
		local maxStuds = SETTINGS.MaxCanvasStuds
		sizeR = math.min(extR, maxStuds)
		sizeU = math.min(extU, maxStuds)
		local faceCenter = hitPart.Position + normal * (extentAlong(hitPart, normal) * 0.5)
		if sizeR >= extR - 1e-3 and sizeU >= extU - 1e-3 then
			center = faceCenter -- the whole part fits in one canvas
		else
			-- too big: a patch centred near the splat but kept fully inside the part
			local rel = worldPos - faceCenter
			local aR = math.clamp(rel:Dot(right), -(extR - sizeR) * 0.5, (extR - sizeR) * 0.5)
			local aU = math.clamp(rel:Dot(up), -(extU - sizeU) * 0.5, (extU - sizeU) * 0.5)
			center = faceCenter + right * aR + up * aU
		end
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
		local ppstud = if pixel then SETTINGS.PixelsPerStud else SETTINGS.FluidPixelsPerStud
		self.ResW = math.clamp(math.floor(sizeR * ppstud), 8, SETTINGS.MaxResolution)
		self.ResH = math.clamp(math.floor(sizeU * ppstud), 8, SETTINGS.MaxResolution)
		self.Liquid = Liquid.new({
			Canvas = Canvas.new({
				Resolution = Vector2.new(self.ResW, self.ResH),
				Parent = gui,
				Driver = if pixel then "Sparse" else "Blob", -- Pixel: sparse full/patch; Fluid: blob
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

-- Blood reaching a proxy edge -> shared wrap/continue/drip from that world point.
function BloodProxy.shed(self: any, x: number, y: number, amount: number)
	shedFrom(self.HitPart, BloodProxy.worldOfScale(self, x, y), self.Normal, -self.Up, amount)
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

-- ============================ FaceCanvas (Pixel renderer) ============================
-- "Pixel" paints directly on the hit part's actual face - a SurfaceGui adorned to the face, so it
-- lies flush and aligned (never floating/rotated), one canvas per part+face, Sparse-rendered. When
-- blood reaches the edge it wraps onto the adjacent face (a new FaceCanvas) and continues.

local FaceCanvas = {}
FaceCanvas.__index = FaceCanvas
local faceCanvases: { [BasePart]: { [Enum.NormalId]: any } } = setmetatable({}, { __mode = "k" }) :: any

function FaceCanvas.new(hitPart: BasePart, faceId: Enum.NormalId)
	local normal, right, down = Surface.faceVectors(hitPart, faceId)
	local gravity = Surface.gravityVector(right, down)
	if SETTINGS.FlipDrip then
		gravity = Vector2.new(gravity.X, -gravity.Y)
	end
	local downhill = Surface.faceDownhill(normal)

	local s = hitPart.Size
	local widthStuds = math.abs(right.X * s.X) + math.abs(right.Y * s.Y) + math.abs(right.Z * s.Z)
	local heightStuds = math.abs(down.X * s.X) + math.abs(down.Y * s.Y) + math.abs(down.Z * s.Z)
	local resW = math.clamp(math.floor(widthStuds * SETTINGS.PixelsPerStud), 8, SETTINGS.MaxResolution)
	local resH = math.clamp(math.floor(heightStuds * SETTINGS.PixelsPerStud), 8, SETTINGS.MaxResolution)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "IMGNBlood"
	gui.Face = faceId
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Adornee = hitPart
	gui.Parent = hitPart

	local liquid = Liquid.new({
		Canvas = Canvas.new({ Resolution = Vector2.new(resW, resH), Parent = gui, Driver = "Sparse" }),
		Preset = SETTINGS.Preset,
		Gravity = gravity,
		EdgeFade = SETTINGS.EdgeFade,
	})
	liquid:Start()

	local self = setmetatable({
		HitPart = hitPart,
		Face = faceId,
		Normal = normal,
		Downhill = downhill,
		Liquid = liquid,
		Gui = gui,
		ResW = resW,
		ResH = resH,
		_cd = 0,
	}, FaceCanvas)

	if SETTINGS.EdgeDrip and downhill then -- only faces with a downhill shed (floors just pool)
		liquid.OnStep = function(dt)
			FaceCanvas.checkEdge(self, dt)
		end
	end
	return self
end

function FaceCanvas.Splat(self: any, worldPos: Vector3, amount: number)
	local x, y = Surface.worldToPixel(self.HitPart, self.Face, worldPos, self.ResW, self.ResH)
	self.Liquid:Splat(x, y, amount, { Spread = 3 + amount })
end

function FaceCanvas.checkEdge(self: any, dt: number)
	self._cd -= dt
	if self._cd > 0 then
		return
	end
	local x, taken = self.Liquid:TakeFromBottom(SETTINGS.DripMin, SETTINGS.DripTake)
	if not x then
		return
	end
	self._cd = SETTINGS.DripInterval
	local pos = Surface.pixelToWorld(self.HitPart, self.Face, x, self.ResH - 1, self.ResW, self.ResH)
	shedFrom(self.HitPart, pos, self.Normal, self.Downhill or Vector3.new(0, -1, 0), taken :: number)
end

local function faceCanvasFor(hitPart: BasePart, worldPos: Vector3, normal: Vector3)
	local faceId = Surface.faceFromNormal(hitPart, normal)
	local byFace = faceCanvases[hitPart]
	if not byFace then
		byFace = {}
		faceCanvases[hitPart] = byFace
	end
	local fc = byFace[faceId]
	if not fc or not fc.Gui.Parent then
		fc = FaceCanvas.new(hitPart, faceId)
		byFace[faceId] = fc
	end
	return fc
end

-- does this canvas' rectangle already cover the hit point?
local function covers(p: any, worldPos: Vector3): boolean
	local lp = p.Part.CFrame:PointToObjectSpace(worldPos)
	return math.abs(lp.X) <= p.SizeR * 0.5 + 0.05 and math.abs(lp.Y) <= p.SizeU * 0.5 + 0.05
end

-- find an existing canvas on the same face that already covers this hit, or make a new one. This
-- works for both a whole-part canvas (covers everything) and good-size patches (each covers its
-- own region) - a big plate just ends up with a few patches where blood actually landed.
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
		elseif p.Normal:Dot(normal) > 0.8 and covers(p, worldPos) then
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
	amount = amount or SETTINGS.SplatAmount
	if SETTINGS.Renderer == "Pixel" and hitPart then
		-- paint directly on the part's face (aligned/flush), wrapping to adjacent faces at edges
		faceCanvasFor(hitPart, worldPos, normal):Splat(worldPos, amount)
	else
		proxyFor(hitPart, worldPos, normal):Splat(worldPos, amount)
	end
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

	-- never land on our own droplets/proxies, or anything the user told us to ignore
	local params = bloodRaycastParams()

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
