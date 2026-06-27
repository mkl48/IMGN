-- IMGN
-- _Patterns/Draw.luau
-- Plinko Labs
--
-- Pure rasterisation primitives - line (Bresenham), rectangle, circle (midpoint). Every
-- function takes a `plot(x, y)` callback and writes nothing itself, so the Canvas hands in its
-- own `:SetPixel` (already clipping + dirty-tracking) and stays lean. Integer-only maths; no
-- allocations in the inner loops.

--[=[
	@class Draw
	Stateless raster primitives over a `plot(x, y)` callback. Used internally by [Canvas]; you
	can call them directly with any plotter.
]=]
local Draw = {}

export type Plot = (x: number, y: number) -> ()

--[=[
	@within Draw
	Bresenham line from `(x0, y0)` to `(x1, y1)`, inclusive of both ends.
]=]
function Draw.line(plot: Plot, x0: number, y0: number, x1: number, y1: number)
	x0, y0, x1, y1 = math.round(x0), math.round(y0), math.round(x1), math.round(y1)
	local dx = math.abs(x1 - x0)
	local dy = -math.abs(y1 - y0)
	local sx = if x0 < x1 then 1 else -1
	local sy = if y0 < y1 then 1 else -1
	local err = dx + dy

	while true do
		plot(x0, y0)
		if x0 == x1 and y0 == y1 then
			break
		end
		local e2 = 2 * err
		if e2 >= dy then
			err += dy
			x0 += sx
		end
		if e2 <= dx then
			err += dx
			y0 += sy
		end
	end
end

--[=[
	@within Draw
	Rectangle with top-left `(x, y)` and size `width` x `height`. `filled` draws every interior
	pixel; otherwise only the one-pixel border.
]=]
function Draw.rect(plot: Plot, x: number, y: number, width: number, height: number, filled: boolean?)
	x, y, width, height = math.round(x), math.round(y), math.round(width), math.round(height)
	if width <= 0 or height <= 0 then
		return
	end

	local x1 = x + width - 1
	local y1 = y + height - 1

	if filled then
		for py = y, y1 do
			for px = x, x1 do
				plot(px, py)
			end
		end
		return
	end

	for px = x, x1 do
		plot(px, y)
		plot(px, y1)
	end
	for py = y + 1, y1 - 1 do
		plot(x, py)
		plot(x1, py)
	end
end

--[=[
	@within Draw
	Midpoint circle of radius `radius` centred on `(cx, cy)`. `filled` draws the disc; otherwise
	only the one-pixel outline.
]=]
function Draw.circle(plot: Plot, cx: number, cy: number, radius: number, filled: boolean?)
	cx, cy, radius = math.round(cx), math.round(cy), math.round(radius)
	if radius < 0 then
		return
	end
	if radius == 0 then
		plot(cx, cy)
		return
	end

	local x = radius
	local y = 0
	local err = 1 - radius

	while x >= y do
		if filled then
			-- Fill the horizontal spans between the eight symmetric octant points.
			for px = cx - x, cx + x do
				plot(px, cy + y)
				plot(px, cy - y)
			end
			for px = cx - y, cx + y do
				plot(px, cy + x)
				plot(px, cy - x)
			end
		else
			plot(cx + x, cy + y)
			plot(cx - x, cy + y)
			plot(cx + x, cy - y)
			plot(cx - x, cy - y)
			plot(cx + y, cy + x)
			plot(cx - y, cy + x)
			plot(cx + y, cy - x)
			plot(cx - y, cy - x)
		end

		y += 1
		if err < 0 then
			err += 2 * y + 1
		else
			x -= 1
			err += 2 * (y - x) + 1
		end
	end
end

return Draw
