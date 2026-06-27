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
-- Placement: `Scale` + `X`/`Y`, or a `Fit` mode ("Contain"/"Cover"/"Stretch") with optional
-- `Align`. `blitAsync` does the copy through a Pacer that yields on a time budget so a big image
-- loads without dropping frames; `fromPixels` lets web-service JSON reuse the same path.

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
	Align: string?, -- placement for Contain/Cover: Center (default), Top, Bottom, Left, Right, TopLeft, ...
	Format: ("PNG" | "BMP" | "TGA" | "JPG")?, -- skip format auto-detection
	SkipTransparent: boolean?, -- don't write fully-transparent source pixels (composite instead of replace)
}

export type PacerOptions = {
	Budget: number?, -- seconds of work per frame before yielding (time-based; preferred)
	RowsPerYield: number?, -- fallback when Budget is nil: yield every N units
	Yield: () -> (), -- how to give up the frame (e.g. task.wait)
	OnProgress: ((number) -> ())?, -- 0..1, called at each yield
	BeforeYield: (() -> ())?, -- run just before yielding (e.g. canvas:Render)
}

-- Pacer: call the returned function once per unit of work (a row); it yields when the per-frame
-- time Budget is spent (or every RowsPerYield units if no Budget), keeping the frame responsive.
type Pacer = (progress: number) -> ()

type Placement = { scaleX: number, scaleY: number, ox: number, oy: number, destW: number, destH: number }

local ALIGN: { [string]: { number } } = {
	Center = { 0.5, 0.5 },
	Top = { 0.5, 0 },
	Bottom = { 0.5, 1 },
	Left = { 0, 0.5 },
	Right = { 1, 0.5 },
	TopLeft = { 0, 0 },
	TopRight = { 1, 0 },
	BottomLeft = { 0, 1 },
	BottomRight = { 1, 1 },
}

--[=[
	@within Image
	Builds a [PacerOptions]-driven pacer. Call it once per row; it yields on the time budget.
]=]
function Image.newPacer(opts: PacerOptions): Pacer
	local budget = opts.Budget
	local step = math.max(1, opts.RowsPerYield or 8)
	local frameStart = os.clock()
	local since = 0

	return function(progress: number)
		since += 1
		local doYield = if budget then (os.clock() - frameStart) >= budget else since >= step
		if doYield then
			if opts.BeforeYield then
				opts.BeforeYield()
			end
			if opts.OnProgress then
				opts.OnProgress(progress)
			end
			opts.Yield()
			frameStart = os.clock()
			since = 0
		end
	end
end

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
	`{ width, height, rows = { { {count,r,g,b,a}, ... } } }` (per-row run-length runs).
]=]
function Image.fromPixels(data: any): any
	local w, h = data.width, data.height
	assert(w and h, "IMGN: pixel data needs width and height")

	local grid
	if data.pixels then
		grid = data.pixels
	elseif data.rows then
		grid = {}
		for y, runs in ipairs(data.rows) do
			local row = {}
			local x = 0
			for _, run in ipairs(runs) do
				for _ = 1, run[1] do
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
			local s = if mode == "Cover" then math.max(cw / iw, ch / ih) else math.min(cw / iw, ch / ih)
			scaleX, scaleY = s, s
		end
		local a = ALIGN[opts.Align or "Center"] or ALIGN.Center
		ox = math.floor((cw - iw * scaleX) * a[1] + 0.5)
		oy = math.floor((ch - ih * scaleY) * a[2] + 0.5)
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
	Copies a decoded image onto `canvas` per the options. Returns drawn width/height.
]=]
function Image.blit(canvas: any, img: any, options: LoadOptions?): (number, number)
	local opts = options or {}
	local p = resolvePlacement(canvas, img, opts)
	blitRows(canvas, img, p, opts.SkipTransparent, 0, p.destH - 1)
	return p.destW, p.destH
end

--[=[
	@within Image
	Like `blit`, but draws one row at a time and calls `pace((rowsDone)/total)` after each, so the
	pacer can yield on its time budget - the image fills in without dropping frames. Must run on a
	yielding thread. Returns drawn width/height.
]=]
function Image.blitAsync(canvas: any, img: any, options: LoadOptions?, pace: Pacer): (number, number)
	local opts = options or {}
	local p = resolvePlacement(canvas, img, opts)
	for dy = 0, p.destH - 1 do
		blitRows(canvas, img, p, opts.SkipTransparent, dy, dy)
		pace((dy + 1) / p.destH)
	end
	canvas:Render()
	return p.destW, p.destH
end

return Image
