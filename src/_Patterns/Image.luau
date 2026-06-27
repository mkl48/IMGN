-- IMGN
-- _Patterns/Image.luau
-- Plinko Labs
--
-- Adapter for loading real image files (PNG/BMP/TGA/JPG) onto a Canvas. The actual deserializer
-- is osgl-rbx/image (https://github.com/osgl-rbx/image), vendored under _Packages/Image and used
-- internally - so callers just pass bytes, no separate install. This module drives osgl's API and
-- copies the decoded RGBA8 buffer onto a Canvas (osgl's DynamicImage buffer is the same
-- 4-bytes-per-pixel layout IMGN uses, so it's a straight per-pixel copy with optional
-- nearest-neighbour scaling).
--
-- Bytes come from you: HttpService:GetAsync(url) returns the file as a string, or bake the file
-- into a ModuleScript - either a `string` or a `buffer` works.

local Decoder = require(script.Parent.Parent._Packages.Image)

--[=[
	@class Image
	Internal helper behind [Canvas:LoadImage] and [IMGN.ImageCanvas]. Not part of the public
	surface; you reach it through those two entry points.
]=]
local Image = {}

export type LoadOptions = {
	X: number?, -- destination top-left x (default 0)
	Y: number?, -- destination top-left y (default 0)
	Scale: number?, -- nearest-neighbour scale (default 1; <1 shrinks, >1 enlarges)
	Format: ("PNG" | "BMP" | "TGA" | "JPG")?, -- skip format auto-detection
	SkipTransparent: boolean?, -- don't write fully-transparent source pixels (composite instead of replace)
}

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

-- Copy a decoded DynamicImage onto `canvas` at the given offset/scale. Returns drawn width/height.
function Image.blit(canvas: any, img: any, options: LoadOptions?): (number, number)
	local opts = options or {}
	local ox = opts.X or 0
	local oy = opts.Y or 0
	local scale = opts.Scale or 1
	local skip = opts.SkipTransparent
	assert(scale > 0, "IMGN: image Scale must be > 0")

	local destW = math.max(1, math.floor(img.width * scale + 0.5))
	local destH = math.max(1, math.floor(img.height * scale + 0.5))

	for dy = 0, destH - 1 do
		local sy = math.min(img.height - 1, math.floor(dy / scale))
		for dx = 0, destW - 1 do
			local sx = math.min(img.width - 1, math.floor(dx / scale))
			local r, g, b, a = img:ReadPixelRGBA(sx, sy)
			if not (skip and a == 0) then
				canvas:SetPixel(ox + dx, oy + dy, Color3.fromRGB(r, g, b), a / 255)
			end
		end
	end

	return destW, destH
end

return Image
