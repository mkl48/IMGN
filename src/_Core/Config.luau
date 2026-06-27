-- IMGN
-- _Core/Config.luau
-- Plinko Labs
--
-- Global, process-wide defaults every Canvas reads when a field is left out of its config -
-- call IMGN.Configure to flip one. None of this is per-canvas state; it's the suite-wide
-- fallback table, read once at Canvas.new time, so changing it only affects canvases created
-- afterwards.

--[=[
	@class Config
	Suite-wide defaults - set with [IMGN.Configure]. Defaults match what the rest of IMGN's docs
	assume.
]=]
export type Config = {
	DefaultDriver: string,
	MaxPixels: number,
	WarnOnLargeCanvas: boolean,
	AutoRender: boolean,
}

local Config: Config = {
	--[=[
		@within Config
		@prop DefaultDriver string
		Default `"PixelGrid"`. Which renderer a Canvas uses when its config omits `Driver`.
		`"PixelGrid"` (one Frame per pixel) suits live drawing; `"RowMerge"` (run-length-merged
		rows) suits flat-colour sprites with far fewer Frames.
	]=]
	DefaultDriver = "PixelGrid",
	--[=[
		@within Config
		@prop MaxPixels number
		Default `16384` (128x128). A canvas larger than this warns once on creation - instance
		count, not memory, is the real ceiling for a Frame-based canvas, and photo-resolution
		content will tank framerate. The canvas is still created; this is only a heads-up.
	]=]
	MaxPixels = 16384,
	--[=[
		@within Config
		@prop WarnOnLargeCanvas boolean
		Default `true`. Set `false` to silence the [Config.MaxPixels] warning if you know what
		you're doing.
	]=]
	WarnOnLargeCanvas = true,
	--[=[
		@within Config
		@prop AutoRender boolean
		Default `false`. When `true`, every Canvas (whose config omits `AutoRender`) wires a
		`RunService.Heartbeat` connection that flushes dirty pixels each frame, so you never call
		`:Render()` by hand. Leave `false` to batch many edits and flush once explicitly.
	]=]
	AutoRender = false,
}

--[=[
	@within Config
	Merges `overrides` into the shared config table. Unknown keys error immediately instead of
	being silently ignored.
]=]
local function configure(overrides: { [string]: any })
	for key, value in overrides do
		assert((Config :: any)[key] ~= nil, `IMGN.Configure: unknown key "{tostring(key)}"`);
		(Config :: any)[key] = value
	end
end

return {
	Config = Config,
	configure = configure,
}
