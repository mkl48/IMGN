-- IMGN
-- _Patterns/Texture.luau
-- Plinko Labs
--
-- Textures for the software 3D engine. A texture is just a function `(u, v) -> Color3?` sampling a
-- colour at 0..1 coordinates (return `nil` for a transparent texel - used by sprites). These
-- generators build common ones procedurally; `fromCanvas` turns any IMGN canvas (e.g. a loaded
-- image) into a texture, so you can wallpaper a raycast level with real images.

--[=[
	@class Texture
	Procedural texture generators for [Raycaster]. Each returns a `(u, v) -> Color3?` sampler.
]=]
local Texture = {}

export type Sampler = (u: number, v: number) -> Color3?

--[=[
	@within Texture
	A flat colour.
]=]
function Texture.solid(color: Color3): Sampler
	return function()
		return color
	end
end

--[=[
	@within Texture
	A checkerboard of `a`/`b` with `n` squares across.
]=]
function Texture.checker(a: Color3, b: Color3, n: number?): Sampler
	local cells = n or 8
	return function(u, v)
		local cx = math.floor(u * cells) % 2
		local cy = math.floor(v * cells) % 2
		return if cx == cy then a else b
	end
end

--[=[
	@within Texture
	A brick wall: `brick` blocks separated by `mortar`, `rows` tall, `cols` across, alternate rows
	offset by half a brick.
]=]
function Texture.brick(brick: Color3, mortar: Color3, rows: number?, cols: number?): Sampler
	local r = rows or 4
	local c = cols or 2
	local m = 0.09 -- mortar thickness (0..1 of a brick)
	return function(u, v)
		local row = math.floor(v * r)
		local uu = (u + (row % 2) * 0.5) % 1
		local fx = (uu * c) % 1
		local fy = (v * r) % 1
		if fx < m or fy < m then
			return mortar
		end
		return brick
	end
end

--[=[
	@within Texture
	Samples an IMGN canvas as a texture - so a loaded image becomes a wall/sprite texture. Texels
	the canvas leaves transparent come back as `nil` (transparent).
]=]
function Texture.fromCanvas(canvas: any): Sampler
	local w, h = canvas.Width, canvas.Height
	return function(u, v)
		local x = math.clamp(math.floor(u * w), 0, w - 1)
		local y = math.clamp(math.floor(v * h), 0, h - 1)
		local color, alpha = canvas:GetPixel(x, y)
		if alpha <= 0.004 then
			return nil
		end
		return color
	end
end

return Texture
