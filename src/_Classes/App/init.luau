-- IMGN
-- _Classes/App/init.luau
-- Plinko Labs
--
-- The managed layer over a Canvas: an App owns a canvas, a list of Objects, and a per-frame loop
-- that steps physics, resolves collisions, and redraws - so building something like the bouncing
-- ball is "spawn an Object, app:Start()" instead of writing the loop yourself. It draws
-- efficiently: each frame it erases only last frame's object footprints (back to Background) and
-- redraws the objects, so a flush touches the moving pixels, not the whole canvas.
--
-- The canvas is yours to draw on directly too (app.Canvas) - but anything you draw that ISN'T an
-- Object won't be re-erased, so a static backdrop drawn once stays put behind the objects, as
-- long as it matches Background where objects pass over it.

local RunService = game:GetService("RunService")

local Canvas = require(script.Parent.Canvas)
local Object = require(script.Object)
local Section = require(script.Section)
local Collision = require(script.Collision)

--[=[
	@class App
	A canvas application: an owned [Canvas] plus managed [Object]s and a step/draw loop. Create one
	with [IMGN.App], spawn Objects with [App:Object], then [App:Start]. `Canvas` (the underlying
	canvas) and `Objects` are readable fields; `OnUpdate` is an optional per-frame hook.
]=]
local App = {}
App.__index = App

export type Object = Object.Object
export type ObjectConfig = Object.ObjectConfig
export type Section = Section.Section

--[=[
	@interface AppConfig
	@within App
	.Canvas Canvas? -- an existing Canvas to drive (e.g. from IMGN.Surface); else one is built from the fields below
	.Resolution Vector2? -- canvas size when building one (required if no Canvas given)
	.Parent Instance? -- GUI container to mount the built canvas into
	.Driver ("PixelGrid" | "RowMerge")? -- renderer for the built canvas
	.Background (Color3 | false)? -- fill colour objects erase back to; `false` = erase to transparent, no initial fill (default black)
	.Clock ("Heartbeat" | "RenderStepped" | "Stepped")? -- which RunService signal drives the loop (default "Heartbeat")
	.OnUpdate (self, dt) -> ()? -- per-frame hook, after physics + collisions, before draw
]=]
export type AppConfig = {
	Canvas: Canvas.Canvas?,
	Resolution: Vector2?,
	Parent: Instance?,
	Driver: any?,
	Background: (Color3 | false)?,
	Clock: ("Heartbeat" | "RenderStepped" | "Stepped")?,
	OnUpdate: ((self: any, dt: number) -> ())?,
}

export type App = typeof(setmetatable(
	{} :: {
		Canvas: Canvas.Canvas,
		Width: number,
		Height: number,
		Objects: { Object.Object },
		Background: Color3 | false,
		OnUpdate: ((self: any, dt: number) -> ())?,
		_clock: string,
		_conn: RBXScriptConnection?,
		_running: boolean,
	},
	App
))

--[=[
	@within App
	Builds an App. Pass `Canvas` to drive an existing canvas (e.g. from [IMGN.Surface]); otherwise
	a canvas is built from `Resolution`/`Parent`/`Driver`.
]=]
function App.new(config: AppConfig): App
	local canvas = config.Canvas
	if not canvas then
		assert(config.Resolution, "IMGN.App: pass either a Canvas or a Resolution to build one")
		canvas = Canvas.new({
			Resolution = config.Resolution,
			Parent = config.Parent,
			Driver = config.Driver,
		})
	end

	local background: Color3 | false = if config.Background == nil then Color3.new(0, 0, 0) else config.Background

	return setmetatable({
		Canvas = canvas,
		Width = canvas.Width,
		Height = canvas.Height,
		Objects = {},
		Background = background,
		OnUpdate = config.OnUpdate,
		_clock = config.Clock or "Heartbeat",
		_conn = nil,
		_running = false,
	}, App)
end

--[=[
	@within App
	Spawns an [Object] (see [ObjectConfig]) into the App and returns it. Add shapes to it with
	`obj:Circle/:Rect/:Pixel`.
]=]
function App.Object(self: App, config: Object.ObjectConfig?): Object.Object
	local object = Object.new(self, config or {})
	table.insert(self.Objects, object)
	return object
end

--[=[
	@within App
	Removes `object` from the App and clears its last footprint on the next frame.
]=]
function App.Remove(self: App, object: Object.Object)
	local index = table.find(self.Objects, object)
	if index then
		table.remove(self.Objects, index)
		-- Erase its footprint now so it doesn't linger when the loop is stopped.
		if object._lastBounds then
			App._erase(self, object._lastBounds)
			object._lastBounds = nil
		end
	end
end

--[=[
	@within App
	Finds the first Object with `Name`, or `nil`.
]=]
function App.Find(self: App, name: string): Object.Object?
	for _, object in self.Objects do
		if object.Name == name then
			return object
		end
	end
	return nil
end

--[=[
	@within App
	Sweeps the canvas across `axis` (`"X"` columns, `"Y"` rows, `"XY"` = a Y pass then an X pass),
	in `direction` (`"Forward"` 0..n-1 or `"Backward"` n-1..0), calling `fn(section)` once per
	line - see [Section]. Marks pixels dirty but does not flush; the App's loop (or your
	`app.Canvas:Render()`) shows the result. Great for wipes, scanlines and per-line effects.
]=]
function App.Comb(
	self: App,
	axis: "X" | "Y" | "XY",
	direction: "Forward" | "Backward",
	fn: (section: Section.Section) -> ()
)
	local function sweep(orientation: "Row" | "Column")
		local count = if orientation == "Row" then self.Height else self.Width
		if direction == "Forward" then
			for index = 0, count - 1 do
				fn(Section.new(self.Canvas, orientation, index))
			end
		else
			for index = count - 1, 0, -1 do
				fn(Section.new(self.Canvas, orientation, index))
			end
		end
	end

	if axis == "Y" or axis == "XY" then
		sweep("Row")
	end
	if axis == "X" or axis == "XY" then
		sweep("Column")
	end
end

--[=[
	@within App
	Fills the whole canvas with the App's Background (or `color` if given) - a clean slate.
]=]
function App.Clear(self: App, color: Color3?)
	local fill = color or (if self.Background then self.Background else Color3.new(0, 0, 0))
	local alpha = if color or self.Background then 1 else 0
	self.Canvas:Fill(fill, alpha)
end

-- Erase a footprint back to the App's Background (or transparent when Background is false).
function App._erase(self: App, bounds: Object.AABB)
	local color = if self.Background then self.Background else Color3.new(0, 0, 0)
	local alpha = if self.Background then 1 else 0
	local w = bounds.maxX - bounds.minX + 1
	local h = bounds.maxY - bounds.minY + 1
	self.Canvas:DrawRect(bounds.minX, bounds.minY, w, h, color, true, alpha)
end

function App._draw(self: App)
	-- Erase last frame's footprints first, then draw everyone, so overlapping objects redraw
	-- cleanly regardless of order.
	for _, object in self.Objects do
		if object._lastBounds then
			App._erase(self, object._lastBounds)
			object._lastBounds = nil
		end
	end
	for _, object in self.Objects do
		if object.Visible then
			object._lastBounds = object:Draw(self.Canvas)
		end
	end
	self.Canvas:Render()
end

function App._step(self: App, dt: number)
	-- 1. per-object update hook + velocity integration (px/sec).
	for _, object in self.Objects do
		if object.OnUpdate then
			object.OnUpdate(object, dt)
		end
		if not object.Anchored then
			object.Position += object.Velocity * dt
		end
	end

	-- 2. walls, then 3. object-object.
	for _, object in self.Objects do
		if object.CanCollide and not object.Anchored then
			Collision.resolveWalls(object, self.Width, self.Height)
		end
	end
	Collision.resolvePairs(self.Objects)

	-- 4. app-level hook, then 5. draw.
	if self.OnUpdate then
		self.OnUpdate(self, dt)
	end
	App._draw(self)
end

--[=[
	@within App
	Fills the Background once, then starts the per-frame loop (step physics -> resolve collisions
	-> redraw). Idempotent while running.
]=]
function App.Start(self: App)
	if self._running then
		return
	end
	self._running = true

	if self.Background then
		self.Canvas:Fill(self.Background, 1)
		self.Canvas:Render()
	end

	local signal = (RunService :: any)[self._clock] :: RBXScriptSignal
	self._conn = signal:Connect(function(dt: number)
		App._step(self, dt)
	end)
end

--[=[
	@within App
	Stops the loop. Objects and their drawn pixels are left as-is; call [App:Start] to resume.
]=]
function App.Stop(self: App)
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self._running = false
end

--[=[
	@within App
	Stops the loop and destroys the underlying Canvas. The App is unusable afterwards.
]=]
function App.Destroy(self: App)
	App.Stop(self)
	self.Canvas:Destroy()
	self.Objects = {}
end

return App
