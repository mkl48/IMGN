-- IMGN
-- _Drivers/RichText.luau
-- Plinko Labs
--
-- The one-instance renderer: the entire image is a single TextLabel full of block glyphs (U+2588),
-- coloured per-pixel with RichText <font> tags. A 100x100 image is ONE instance instead of 10,000.
-- Same-colour runs share a tag (RLE), so flat art compresses hard; transparent pixels are block
-- glyphs made invisible with transparency="1" so every column keeps the same width.
--
-- Caveats, be honest: alignment is font-metric dependent (we use the monospace Code font with
-- TextScaled, so it's APPROXIMATE, not pixel-perfect - you may need to tune the part's aspect),
-- and RichText has a practical per-label string-length ceiling (~16k chars), so this is for low
-- resolutions (~64x64 and under). For pixel-perfect output use PixelGrid / GreedyMesh. Like
-- GreedyMesh, any change rebuilds the whole string - great for static images, not animation.

local RichText = {}
RichText.__index = RichText

local PixelBuffer = require(script.Parent.Parent._Core.PixelBuffer)
type PixelBuffer = PixelBuffer.PixelBuffer

local BLOCK = utf8.char(0x2588) -- █
local LENGTH_WARN = 16000

export type RichText = typeof(setmetatable(
	{} :: {
		_buffer: PixelBuffer,
		_width: number,
		_height: number,
		_label: TextLabel?,
		_container: Frame?,
		_dirty: boolean,
		_warned: boolean,
	},
	RichText
))

--[=[
	@class RichText
	@within Canvas
	The whole image as a single RichText TextLabel - the lowest possible instance count. Selected
	with `Driver = "RichText"`. Approximate alignment; best for static, low-resolution images.
]=]
function RichText.new(pixelBuffer: PixelBuffer): RichText
	return setmetatable({
		_buffer = pixelBuffer,
		_width = pixelBuffer.Width,
		_height = pixelBuffer.Height,
		_label = nil,
		_container = nil,
		_dirty = false,
		_warned = false,
	}, RichText)
end

--[=[
	@within RichText
	Builds the container and the single TextLabel the image is rendered into.
]=]
function RichText.Mount(self: RichText, parent: Instance): Frame
	local container = Instance.new("Frame")
	container.Name = "IMGNCanvas"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true

	local label = Instance.new("TextLabel")
	label.Name = "Pixels"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.RichText = true
	label.Font = Enum.Font.Code -- monospace, so columns line up
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = container

	container.Parent = parent
	self._container = container
	self._label = label
	return container
end

-- Any change rebuilds the whole string.
function RichText.SetDirty(self: RichText)
	self._dirty = true
end

function RichText.SetAllDirty(self: RichText)
	self._dirty = true
end

--[=[
	@within RichText
	Rebuilds the RichText string from the buffer (RLE per row) and assigns it to the label.
]=]
function RichText.Flush(self: RichText)
	if not self._dirty or not self._label then
		return
	end
	self._dirty = false

	local pixelBuffer = self._buffer
	local width, height = self._width, self._height
	local parts: { string } = {}

	for y = 0, height - 1 do
		local r0, g0, b0, a0 = PixelBuffer.GetBytes(pixelBuffer, 0, y)
		local runStart = 0

		local function emit(fromX: number, toX: number, r: number, g: number, b: number, a: number)
			local count = toX - fromX + 1
			local hex = string.format("#%02X%02X%02X", r, g, b)
			if a >= 255 then
				table.insert(parts, `<font color="{hex}">`)
			else
				table.insert(parts, `<font color="{hex}" transparency="{1 - a / 255}">`)
			end
			table.insert(parts, string.rep(BLOCK, count))
			table.insert(parts, "</font>")
		end

		for x = 1, width - 1 do
			local r, g, b, a = PixelBuffer.GetBytes(pixelBuffer, x, y)
			if r ~= r0 or g ~= g0 or b ~= b0 or a ~= a0 then
				emit(runStart, x - 1, r0, g0, b0, a0)
				runStart = x
				r0, g0, b0, a0 = r, g, b, a
			end
		end
		emit(runStart, width - 1, r0, g0, b0, a0)

		if y < height - 1 then
			table.insert(parts, "\n")
		end
	end

	local text = table.concat(parts)
	if not self._warned and #text > LENGTH_WARN then
		self._warned = true
		warn(
			`IMGN RichText: the image string is {#text} chars, past the ~{LENGTH_WARN} RichText limit - `
				.. `it may be truncated. Use a lower resolution, or the GreedyMesh/PixelGrid driver.`
		)
	end
	self._label.Text = text
end

--[=[
	@within RichText
	Destroys the label and container.
]=]
function RichText.Destroy(self: RichText)
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	self._label = nil
end

return RichText
