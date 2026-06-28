-- IMGN
-- _Classes/Canvas/Region.luau
-- Plinko Labs
--
-- A Region is a sub-canvas: a window onto a parent Canvas at a position + size, with its OWN local
-- (0,0)-origin coordinate space. Everything you draw is in the region's coordinates and clipped to
-- it, then written into the parent at the offset. Paired with the Sparse driver this is the way to
-- handle giant surfaces: one big logical Canvas (empty pixels cost nothing), and you `:Query` a
-- region wherever you actually want to draw - a splat, a UI panel, a tile - and work in convenient
-- local space without touching the rest of the canvas.

local Draw = require(script.Parent.Parent.Parent._Patterns.Draw)
local Font = require(script.Parent.Parent.Parent._Patterns.Font)

--[=[
	@class Region
	A sub-canvas of a [Canvas] (from [Canvas:Query]) with local coordinates clipped to its bounds.
	Has the same drawing surface as a Canvas - `SetPixel`, `Draw*`, `Text`, `Shader`, `Fill` - plus
	`Width`/`Height` (the region size). Call the parent's `:Render()` (or this region's, which
	forwards) to show edits.
]=]
local Region = {}
Region.__index = Region

export type Region = typeof(setmetatable({} :: any, Region))

function Region.new(canvas: any, x: number, y: number, width: number, height: number): Region
	-- clamp the window to the parent canvas
	x = math.clamp(math.floor(x), 0, canvas.Width)
	y = math.clamp(math.floor(y), 0, canvas.Height)
	width = math.clamp(math.floor(width), 0, canvas.Width - x)
	height = math.clamp(math.floor(height), 0, canvas.Height - y)
	return setmetatable({
		Canvas = canvas,
		X = x,
		Y = y,
		Width = width,
		Height = height,
	}, Region)
end

--[=[
	@within Region
	Writes a pixel at local `(x, y)`; clipped to the region.
]=]
function Region.SetPixel(self: Region, x: number, y: number, color: Color3, alpha: number?)
	if x < 0 or y < 0 or x >= self.Width or y >= self.Height then
		return
	end
	self.Canvas:SetPixel(self.X + x, self.Y + y, color, alpha)
end

--[=[
	@within Region
	Reads the pixel at local `(x, y)`. Out of bounds returns transparent black.
]=]
function Region.GetPixel(self: Region, x: number, y: number): (Color3, number)
	if x < 0 or y < 0 or x >= self.Width or y >= self.Height then
		return Color3.new(0, 0, 0), 0
	end
	return self.Canvas:GetPixel(self.X + x, self.Y + y)
end

--[=[
	@within Region
	Fills the whole region with `color`/`alpha`.
]=]
function Region.Fill(self: Region, color: Color3, alpha: number?)
	for y = 0, self.Height - 1 do
		for x = 0, self.Width - 1 do
			self.Canvas:SetPixel(self.X + x, self.Y + y, color, alpha)
		end
	end
end

--[=[
	@within Region
	Clears the region to transparent.
]=]
function Region.Clear(self: Region)
	Region.Fill(self, Color3.new(0, 0, 0), 0)
end

local function plotter(self: Region, color: Color3, alpha: number?)
	return function(x: number, y: number)
		Region.SetPixel(self, x, y, color, alpha)
	end
end

--[=[
	@within Region
	Line from `(x0, y0)` to `(x1, y1)` in local space.
]=]
function Region.DrawLine(self: Region, x0: number, y0: number, x1: number, y1: number, color: Color3, alpha: number?)
	Draw.line(plotter(self, color, alpha), x0, y0, x1, y1)
end

--[=[
	@within Region
	Rectangle at local `(x, y)`, size `width` x `height`.
]=]
function Region.DrawRect(self: Region, x: number, y: number, width: number, height: number, color: Color3, filled: boolean?, alpha: number?)
	Draw.rect(plotter(self, color, alpha), x, y, width, height, filled)
end

--[=[
	@within Region
	Circle of `radius` centred on local `(cx, cy)`.
]=]
function Region.DrawCircle(self: Region, cx: number, cy: number, radius: number, color: Color3, filled: boolean?, alpha: number?)
	Draw.circle(plotter(self, color, alpha), cx, cy, radius, filled)
end

--[=[
	@within Region
	Bitmap text at local `(x, y)`.
]=]
function Region.Text(self: Region, text: string, x: number, y: number, color: Color3, scale: number?, alpha: number?): number
	return Font.draw(plotter(self, color, alpha), text, math.floor(x), math.floor(y), scale)
end

--[=[
	@within Region
	Runs `shader(x, y, color, alpha)` over every pixel of the region (local coords); a returned
	colour is opaque unless an alpha is returned, `nil` leaves the pixel.
]=]
function Region.Shader(self: Region, shader: (x: number, y: number, color: Color3, alpha: number) -> (Color3?, number?))
	for y = 0, self.Height - 1 do
		for x = 0, self.Width - 1 do
			local current, currentAlpha = Region.GetPixel(self, x, y)
			local color, alpha = shader(x, y, current, currentAlpha)
			if color then
				Region.SetPixel(self, x, y, color, if alpha ~= nil then alpha else 1)
			end
		end
	end
end

--[=[
	@within Region
	A sub-region of this region (coordinates relative to this region).
]=]
function Region.Query(self: Region, x: number, y: number, width: number, height: number): Region
	return Region.new(self.Canvas, self.X + x, self.Y + y, width, height)
end

--[=[
	@within Region
	Flushes the parent canvas (forwards to its `:Render`).
]=]
function Region.Render(self: Region)
	self.Canvas:Render()
end

return Region
