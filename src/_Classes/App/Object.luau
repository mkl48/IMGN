-- IMGN
-- _Classes/App/Object.luau
-- Plinko Labs
--
-- An Object is the thing you spawn into an App: a transform (Position + Velocity) carrying one
-- or more shapes - circles, rects, pixels - that draw and collide as a single union. You never
-- place the shapes in canvas space; you give them offsets relative to the Object's Position, and
-- moving the Object moves the whole union. Presets ("Dynamic", "Wall", "Ghost") seed the
-- behaviour flags (CanCollide, Anchored, Bounce, Visible) so the common cases are one word.
--
-- Collision uses the union's axis-aligned bounding box (AABB) - the App resolves walls and
-- object-object overlaps off these. :Overlaps / :TouchingEdge expose the same tests for when you
-- want to drive the response yourself instead of letting the engine bounce things.

local PRESETS: { [string]: { CanCollide: boolean, Anchored: boolean, Bounce: number, Visible: boolean } } = {
	-- A free-moving body that bounces off everything. The default.
	Dynamic = { CanCollide = true, Anchored = false, Bounce = 1, Visible = true },
	-- An immovable solid - other bodies bounce off it, it never moves. (Static is an alias.)
	Wall = { CanCollide = true, Anchored = true, Bounce = 1, Visible = true },
	Static = { CanCollide = true, Anchored = true, Bounce = 1, Visible = true },
	-- Moves and draws but passes through everything (still answers :Overlaps).
	Ghost = { CanCollide = false, Anchored = false, Bounce = 1, Visible = true },
}

type Shape = {
	Kind: "Circle" | "Rect" | "Pixel",
	OX: number,
	OY: number,
	W: number, -- radius for Circle, width for Rect (0 for Pixel)
	H: number, -- height for Rect (0 otherwise)
	Color: Color3,
	Filled: boolean,
	Alpha: number?,
}

export type AABB = { minX: number, minY: number, maxX: number, maxY: number }

--[=[
	@class Object
	@within App
	A union of shapes with a transform and collision presets. Created with [App:Object]; never
	constructed directly. Read/write `Position`, `Velocity`, `CanCollide`, `Anchored`, `Bounce`,
	`Visible` and `Name` as plain fields.
]=]
local Object = {}
Object.__index = Object

export type Object = typeof(setmetatable(
	{} :: {
		Name: string?,
		Position: Vector2,
		Velocity: Vector2,
		CanCollide: boolean,
		Anchored: boolean,
		Bounce: number,
		Visible: boolean,
		OnUpdate: ((self: Object, dt: number) -> ())?,
		OnCollide: ((self: Object, other: Object | string) -> ())?,
		_app: any,
		_shapes: { Shape },
		_lastBounds: AABB?,
	},
	Object
))

--[=[
	@interface ObjectConfig
	@within Object
	.Position Vector2? -- union anchor in canvas pixels (default canvas centre)
	.Velocity Vector2? -- pixels per second (default zero)
	.Preset ("Dynamic" | "Wall" | "Static" | "Ghost")? -- seeds the flags below (default "Dynamic")
	.CanCollide boolean? -- participates in wall + object collisions
	.Anchored boolean? -- immovable: ignores Velocity, never pushed
	.Bounce number? -- restitution 0..1 applied on collision
	.Visible boolean? -- drawn each frame
	.Name string? -- optional id for App:Find
	.OnUpdate (self, dt) -> ()? -- per-frame callback before physics integrates
	.OnCollide (self, other) -> ()? -- fired on collision; `other` is an Object or an edge name
]=]
export type ObjectConfig = {
	Position: Vector2?,
	Velocity: Vector2?,
	Preset: string?,
	CanCollide: boolean?,
	Anchored: boolean?,
	Bounce: number?,
	Visible: boolean?,
	Name: string?,
	OnUpdate: ((self: Object, dt: number) -> ())?,
	OnCollide: ((self: Object, other: Object | string) -> ())?,
}

local function pick<T>(value: T?, fallback: T): T
	if value == nil then
		return fallback
	end
	return value
end

function Object.new(app: any, config: ObjectConfig): Object
	local preset = PRESETS[config.Preset or "Dynamic"]
	assert(preset, `IMGN App:Object: unknown Preset "{tostring(config.Preset)}"`)

	return setmetatable({
		Name = config.Name,
		Position = config.Position or Vector2.new(app.Width / 2, app.Height / 2),
		Velocity = config.Velocity or Vector2.zero,
		CanCollide = pick(config.CanCollide, preset.CanCollide),
		Anchored = pick(config.Anchored, preset.Anchored),
		Bounce = pick(config.Bounce, preset.Bounce),
		Visible = pick(config.Visible, preset.Visible),
		OnUpdate = config.OnUpdate,
		OnCollide = config.OnCollide,
		_app = app,
		_shapes = {},
		_lastBounds = nil,
	}, Object)
end

--[=[
	@within Object
	Adds a circle of `radius` at `offset` (relative to Position) to the union. Chainable.
]=]
function Object.Circle(self: Object, offset: Vector2, radius: number, color: Color3, filled: boolean?, alpha: number?): Object
	table.insert(self._shapes, {
		Kind = "Circle",
		OX = offset.X,
		OY = offset.Y,
		W = radius,
		H = radius,
		Color = color,
		Filled = pick(filled, true),
		Alpha = alpha,
	})
	return self
end

--[=[
	@within Object
	Adds a `size`-wide rectangle with its top-left at `offset` (relative to Position). Chainable.
]=]
function Object.Rect(self: Object, offset: Vector2, size: Vector2, color: Color3, filled: boolean?, alpha: number?): Object
	table.insert(self._shapes, {
		Kind = "Rect",
		OX = offset.X,
		OY = offset.Y,
		W = size.X,
		H = size.Y,
		Color = color,
		Filled = pick(filled, true),
		Alpha = alpha,
	})
	return self
end

--[=[
	@within Object
	Adds a single pixel at `offset` (relative to Position) to the union. Chainable.
]=]
function Object.Pixel(self: Object, offset: Vector2, color: Color3, alpha: number?): Object
	table.insert(self._shapes, {
		Kind = "Pixel",
		OX = offset.X,
		OY = offset.Y,
		W = 0,
		H = 0,
		Color = color,
		Filled = true,
		Alpha = alpha,
	})
	return self
end

-- Integer AABB of the union in canvas space, snapped to the Position the Object will actually
-- draw at this frame (so erase rectangles cover exactly what was drawn).
local function computeBounds(self: Object): AABB?
	if #self._shapes == 0 then
		return nil
	end

	local px = math.round(self.Position.X)
	local py = math.round(self.Position.Y)
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge

	for _, shape in self._shapes do
		local ox = math.round(shape.OX)
		local oy = math.round(shape.OY)
		local sMinX, sMinY, sMaxX, sMaxY
		if shape.Kind == "Circle" then
			local r = math.round(shape.W)
			sMinX, sMinY, sMaxX, sMaxY = ox - r, oy - r, ox + r, oy + r
		elseif shape.Kind == "Rect" then
			sMinX, sMinY = ox, oy
			sMaxX, sMaxY = ox + math.round(shape.W) - 1, oy + math.round(shape.H) - 1
		else -- Pixel
			sMinX, sMinY, sMaxX, sMaxY = ox, oy, ox, oy
		end
		minX = math.min(minX, sMinX)
		minY = math.min(minY, sMinY)
		maxX = math.max(maxX, sMaxX)
		maxY = math.max(maxY, sMaxY)
	end

	return { minX = px + minX, minY = py + minY, maxX = px + maxX, maxY = py + maxY }
end

--[=[
	@within Object
	The union's axis-aligned bounding box in canvas pixels, or `nil` if it has no shapes yet.
]=]
function Object.Bounds(self: Object): AABB?
	return computeBounds(self)
end

--[=[
	@within Object
	Draws every shape onto `canvas` at the current Position and returns the AABB it covered (used
	by the App to erase last frame's footprint). Internal - the App calls this each frame.
]=]
function Object.Draw(self: Object, canvas: any): AABB?
	local px = math.round(self.Position.X)
	local py = math.round(self.Position.Y)
	for _, shape in self._shapes do
		local x = px + math.round(shape.OX)
		local y = py + math.round(shape.OY)
		if shape.Kind == "Circle" then
			canvas:DrawCircle(x, y, math.round(shape.W), shape.Color, shape.Filled, shape.Alpha)
		elseif shape.Kind == "Rect" then
			canvas:DrawRect(x, y, math.round(shape.W), math.round(shape.H), shape.Color, shape.Filled, shape.Alpha)
		else
			canvas:SetPixel(x, y, shape.Color, shape.Alpha)
		end
	end
	return computeBounds(self)
end

--[=[
	@within Object
	Whether this Object's AABB overlaps `other`'s. Works regardless of CanCollide, so you can use
	it for triggers/pickups the engine shouldn't physically bounce.
]=]
function Object.Overlaps(self: Object, other: Object): boolean
	local a, b = computeBounds(self), computeBounds(other)
	if not a or not b then
		return false
	end
	return not (a.maxX < b.minX or a.minX > b.maxX or a.maxY < b.minY or a.minY > b.maxY)
end

--[=[
	@within Object
	Which canvas edges the union is touching or past, as `{ Left, Right, Top, Bottom }` booleans.
]=]
function Object.TouchingEdge(self: Object): { Left: boolean, Right: boolean, Top: boolean, Bottom: boolean }
	local b = computeBounds(self)
	if not b then
		return { Left = false, Right = false, Top = false, Bottom = false }
	end
	return {
		Left = b.minX <= 0,
		Right = b.maxX >= self._app.Width - 1,
		Top = b.minY <= 0,
		Bottom = b.maxY >= self._app.Height - 1,
	}
end

--[=[
	@within Object
	Removes the Object from its App. It stops updating, and its last footprint is cleared on the
	next frame.
]=]
function Object.Destroy(self: Object)
	self._app:Remove(self)
end

return Object
