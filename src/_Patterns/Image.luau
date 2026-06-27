-- IMGN
-- _Patterns/Image.luau
-- Plinko Labs
--
-- Adapter for loading real image files (PNG/BMP/TGA/JPG) onto a Canvas. The actual deserializer
-- is osgl-rbx/image (https://github.com/osgl-rbx/image), vendored under _Packages/Image and used
-- internally - so callers just pass bytes, no separate install. This module drives osgl's API and
-- copies the decoded RGBA8 buffer onto a Canvas (osgl's DynamicImage buffer is the same
-- 4-bytes-per-pixel layout IMGN uses, so it's a straight per-pixel copy).
--
-- Placement: pass `Scale` + `X`/`Y`, or a `Fit` mode ("Contain"/"Cover"/"Stretch") to size the
-- image against the canvas. `blitAsync` does the same copy but yields every N rows so a big image
-- doesn't freeze the frame - see Canvas:LoadImageAsync.
--
-- Bytes come from you: HttpService:GetAsync(url) returns the file as a string, or bake the file
-- into a ModuleScript (scripts/embed-image.luau) - either a `string` or a `buffer` works.

local Decoder = require(script.Parent.Parent._Packages.Image)

--[=[
	@class Image
	Internal helper behind [Canvas:LoadImage] and [IMGN.ImageCanvas]. Not part of the public
	surface; you reach it through those two entry points.
]=]
local Image = {}

export type LoadOptions = {
	X: number?, -- destination top-left x (default 0; ignored when Fit is set)
	Y: number?, -- destination top-left y (default 0; ignored when Fit is set)
	Scale: number?, -- nearest-neighbour scale (default 1; <1 shrinks, >1 enlarges)
	Fit: (boolean | "Contain" | "Cover" | "Stretch")?, -- size to the canvas instead of Scale (true = "Contain")
	Format: ("PNG" | "BMP" | "TGA" | "JPG")?, -- skip format auto-detection
	SkipTransparent: boolean?, -- don't write fully-transparent source pixels (composite instead of replace)
}

type Placement = { scaleX: number, scaleY: number, ox: number, oy: number, destW: number, destH: number }

-- Decode `bytes` (string|buffer) with the bundled decoder into a DynamicImage.
function Image.decode(bytes: string | buffer, format: string?): any
	local reader
	if format then
		local fmt = Decoder.ImageFormat[format]
		assert(fmt, `IMGN: unknown image Format "{format}"`)
		reader = Decoder.ImageReader.withFormat(bytes, fmt)
	else
		reader = Decoder.ImageReader.open(bytes)
		local guess = reader:WithGuessedFormat()
		if guess and guess.isOk == false then
			error("IMGN: could not detect the image format (pass Format = \"PNG\" to be explicit)")
		end
	end

	local result = reader:Decode()
	assert(result.isOk, "IMGN: image decode failed (is the data a valid image of that format?)")
	return result:Unwrap()
end

--[=[
	@within Image
	Wraps a decoded pixel table (from a web service / JSONDecode) as something [Image.blit] can
	draw. Accepts `{ width, height, pixels = { { {r,g,b[,a]}, ... } } }` (a 2D grid) or the compact
	`{ width, height, rows = { { {count,r,g,b,a}, ... } } }` (per-row run-length runs). Returns an
	object with `width`, `height` and `ReadPixelRGBA`, matching the decoder's image shape.
]=]
function Image.fromPixels(data: any): any
	local w, h = data.width, data.height
	assert(w and h, "IMGN: pixel data needs width and height")

	local grid -- grid[y][x] = {r,g,b,a?}
	if data.pixels then
		grid = data.pixels
	elseif data.rows then
		grid = {}
		for y, runs in ipairs(data.rows) do
			local row = {}
			local x = 0
			for _, run in ipairs(runs) do
				local count = run[1]
				for _ = 1, count do
					x += 1
					row[x] = { run[2], run[3], run[4], run[5] }
				end
			end
			grid[y] = row
		end
	else
		error("IMGN: pixel data needs a `pixels` grid or `rows` (RLE)")
	end

	return {
		width = w,
		height = h,
		ReadPixelRGBA = function(_self: any, x: number, y: number): (number, number, number, number)
			local px = grid[y + 1] and grid[y + 1][x + 1]
			if not px then
				return 0, 0, 0, 0
			end
			return px[1], px[2], px[3], px[4] or 255
		end,
	}
end

-- Work out destination scale + offset from the options and the target canvas size.
local function resolvePlacement(canvas: any, img: any, opts: LoadOptions): Placement
	local iw, ih = img.width, img.height
	local scaleX, scaleY, ox, oy

	if opts.Fit then
		local mode = if opts.Fit == true then "Contain" else opts.Fit
		local cw, ch = canvas.Width, canvas.Height
		if mode == "Stretch" then
			scaleX, scaleY = cw / iw, ch / ih
		else
			-- Contain fits inside (letterbox); Cover fills and crops.
			local s = if mode == "Cover" then math.max(cw / iw, ch / ih) else math.min(cw / iw, ch / ih)
			scaleX, scaleY = s, s
		end
		ox = math.floor((cw - iw * scaleX) / 2 + 0.5)
		oy = math.floor((ch - ih * scaleY) / 2 + 0.5)
	else
		local s = opts.Scale or 1
		assert(s > 0, "IMGN: image Scale must be > 0")
		scaleX, scaleY = s, s
		ox, oy = opts.X or 0, opts.Y or 0
	end

	return {
		scaleX = scaleX,
		scaleY = scaleY,
		ox = ox,
		oy = oy,
		destW = math.max(1, math.floor(iw * scaleX + 0.5)),
		destH = math.max(1, math.floor(ih * scaleY + 0.5)),
	}
end

-- Copy one band of destination rows [fromY, toY] (inclusive) onto the canvas.
local function blitRows(canvas: any, img: any, p: Placement, skip: boolean?, fromY: number, toY: number)
	local iw, ih = img.width, img.height
	for dy = fromY, toY do
		local sy = math.min(ih - 1, math.floor(dy / p.scaleY))
		for dx = 0, p.destW - 1 do
			local sx = math.min(iw - 1, math.floor(dx / p.scaleX))
			local r, g, b, a = img:ReadPixelRGBA(sx, sy)
			if not (skip and a == 0) then
				canvas:SetPixel(p.ox + dx, p.oy + dy, Color3.fromRGB(r, g, b), a / 255)
			end
		end
	end
end

--[=[
	@within Image
	Copies a decoded DynamicImage onto `canvas` per the options. Returns drawn width/height.
]=]
function Image.blit(canvas: any, img: any, options: LoadOptions?): (number, number)
	local opts = options or {}
	local p = resolvePlacement(canvas, img, opts)
	blitRows(canvas, img, p, opts.SkipTransparent, 0, p.destH - 1)
	return p.destW, p.destH
end

--[=[
	@within Image
	Same as `blit`, but copies `rowsPerYield` destination rows at a time, calling `yield()` (and
	flushing the canvas) between bands so a large image spreads across frames. Reports
	`onProgress(fraction)` per band. Must run on a thread that can yield.
]=]
function Image.blitAsync(
	canvas: any,
	img: any,
	options: LoadOptions?,
	rowsPerYield: number,
	yield: () -> (),
	onProgress: ((number) -> ())?
): (number, number)
	local opts = options or {}
	local p = resolvePlacement(canvas, img, opts)
	local step = math.max(1, rowsPerYield)

	local y = 0
	while y < p.destH do
		local toY = math.min(y + step - 1, p.destH - 1)
		blitRows(canvas, img, p, opts.SkipTransparent, y, toY)
		canvas:Render()
		if onProgress then
			onProgress((toY + 1) / p.destH)
		end
		y = toY + 1
		if y < p.destH then
			yield()
		end
	end

	return p.destW, p.destH
end

return Image
