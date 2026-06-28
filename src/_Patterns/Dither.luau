-- IMGN
-- _Patterns/Dither.luau
-- Plinko Labs
--
-- Colour reduction for a Canvas: snap every pixel to the nearest colour in a palette (Quantize),
-- or do it with Floyd-Steinberg error diffusion (Dither) so the limited palette reads as smooth
-- shading - the classic retro / GameBoy look. Beyond looks, fewer colours means longer same-colour
-- runs, which makes the RowMerge / GreedyMesh / RichText drivers dramatically cheaper.

local Dither = {}

export type Palette = { Color3 }

-- nearest palette colour to (r,g,b) by squared distance
local function nearest(palette: Palette, r: number, g: number, b: number): Color3
	local best, bestD = palette[1], math.huge
	for _, c in palette do
		local dr, dg, db = r - c.R, g - c.G, b - c.B
		local d = dr * dr + dg * dg + db * db
		if d < bestD then
			bestD = d
			best = c
		end
	end
	return best
end

--[=[
	@class Dither
	Palette reduction for a [Canvas] - reached via [Canvas:Quantize] and [Canvas:Dither].
]=]

--[=[
	@within Dither
	Snaps every visible pixel of `canvas` to its nearest colour in `palette` (no error diffusion).
]=]
function Dither.quantize(canvas: any, palette: Palette)
	local W, H = canvas.Width, canvas.Height
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local c, a = canvas:GetPixel(x, y)
			if a > 0.004 then
				canvas:SetPixel(x, y, nearest(palette, c.R, c.G, c.B), a)
			end
		end
	end
end

--[=[
	@within Dither
	Floyd-Steinberg dithers `canvas` to `palette`: snaps each visible pixel to the nearest palette
	colour and pushes the rounding error onto its neighbours, so the limited palette looks shaded.
]=]
function Dither.floydSteinberg(canvas: any, palette: Palette)
	local W, H = canvas.Width, canvas.Height
	local r, g, b, alpha = {}, {}, {}, {}

	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local c, a = canvas:GetPixel(x, y)
			local i = y * W + x + 1
			r[i], g[i], b[i], alpha[i] = c.R, c.G, c.B, a
		end
	end

	local function spread(x: number, y: number, er: number, eg: number, eb: number, f: number)
		if x >= 0 and x < W and y >= 0 and y < H then
			local j = y * W + x + 1
			r[j] += er * f
			g[j] += eg * f
			b[j] += eb * f
		end
	end

	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local i = y * W + x + 1
			if alpha[i] > 0.004 then
				local p = nearest(palette, r[i], g[i], b[i])
				local er, eg, eb = r[i] - p.R, g[i] - p.G, b[i] - p.B
				canvas:SetPixel(x, y, p, alpha[i])
				spread(x + 1, y, er, eg, eb, 7 / 16)
				spread(x - 1, y + 1, er, eg, eb, 3 / 16)
				spread(x, y + 1, er, eg, eb, 5 / 16)
				spread(x + 1, y + 1, er, eg, eb, 1 / 16)
			end
		end
	end
end

--[=[
	@within Dither
	A grayscale palette of `n` evenly-spaced shades (n >= 2).
]=]
function Dither.grayscale(n: number): Palette
	local palette = {}
	for i = 0, n - 1 do
		local v = i / (n - 1)
		table.insert(palette, Color3.new(v, v, v))
	end
	return palette
end

return Dither
