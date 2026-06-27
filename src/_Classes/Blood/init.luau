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
local Surface = require(script.Surface)

--[=[
	@class Blood
	A droplet-and-drip blood engine over [Liquid] using [BloodProxy] surfaces. `Blood.Emit` throws
	a droplet, `Blood.KillBrick` makes a brick that spurts blood, `Blood.Splat` paints a hit point.
]=]
local Blood = {}

local SETTINGS = {
	ProxySize = 3, -- footprint of a blood proxy, in studs (fixed -> consistent resolution)
	ProxyThickness = 0.08,
	ProxyOffset = 0.02, -- how far off the surface to float the proxy (avoid z-fighting)
	PixelsPerStud = 12, -- resolution per proxy stud (ProxySize * this = canvas size)
	MaxResolution = 64,
	ReuseRadius = 2, -- splats within this many studs of an existing proxy reuse it
	Preset = "Blood",
	DropletSize = 0.4,
	DropletColor = Color3.fromRGB(120, 6, 8),
	DropletLifetime = 6,
	SplatAmount = 4,
	FlipDrip = false, -- flip if drips run UP instead of down in your place (single global knob)
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

	local size = SETTINGS.ProxySize
	local res = math.clamp(math.floor(size * SETTINGS.PixelsPerStud), 8, SETTINGS.MaxResolution)

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
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Adornee = part
	gui.Parent = part

	local canvas = Canvas.new({ Resolution = Vector2.new(res, res), Parent = gui })
	local liquid = Liquid.new({ Canvas = canvas, Preset = SETTINGS.Preset, Gravity = gravity })
	liquid:Start()

	return setmetatable({
		Part = part,
		HitPart = hitPart,
		Center = worldPos,
		Normal = normal,
		Liquid = liquid,
		Size = size,
		Res = res,
	}, BloodProxy)
end

-- world point -> this proxy's canvas pixel (proxy is a known fixed-size part, so this is exact)
function BloodProxy.Pixel(self: any, worldPos: Vector3): (number, number)
	local lp = self.Part.CFrame:PointToObjectSpace(worldPos)
	local u = 0.5 + lp.X / self.Size
	local v = 0.5 - lp.Y / self.Size -- +Y local is up-slope, so canvas v grows downward
	return math.clamp(math.floor(u * self.Res), 0, self.Res - 1), math.clamp(math.floor(v * self.Res), 0, self.Res - 1)
end

function BloodProxy.Splat(self: any, worldPos: Vector3, amount: number)
	local px, py = BloodProxy.Pixel(self, worldPos)
	self.Liquid:Splat(px, py, amount, { Spread = 3 + amount })
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
	params.FilterDescendantsInstances = { dropletFolder, proxyFolder }

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
