-- IMGN
-- _Patterns/Effect.luau
-- Plinko Labs
--
-- Post-processing effects for a Canvas (or Region): read the pixels, transform, write them back.
-- The movie/game-screen looks - CRT scanlines, chromatic aberration, glitch, hologram, edge-detect,
-- wave warp, film grain, bloom, ASCII - plus the basics (grayscale/invert/posterize). Each takes a
-- `target` with Width/Height/GetPixel/SetPixel (so it works on a whole canvas or a sub-region) and
-- is reached through [Canvas:Effect] or `IMGN.Effects`.

local Font = require(script.Parent.Font)

--[=[
	@class Effects
	Post-processing filters over a [Canvas]/[Region]. `IMGN.Effects.<name>(target, ...)`, or
	`canvas:Effect("Name", options)`.
]=]
local Effect = {}

local function clamp01(v: number): number
	return if v < 0 then 0 elseif v > 1 then 1 else v
end

-- read the target into a flat array of {r, g, b, a}
local function snapshot(target: any): ({ { number } }, number, number)
	local W, H = target.Width, target.Height
	local px = table.create(W * H)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local c, a = target:GetPixel(x, y)
			px[y * W + x + 1] = { c.R, c.G, c.B, a }
		end
	end
	return px, W, H
end

local function lum(p: { number }): number
	return 0.3 * p[1] + 0.59 * p[2] + 0.11 * p[3]
end

--[=[
	@within Effects
	Desaturates to grayscale (luminance).
]=]
function Effect.grayscale(target: any)
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				local l = lum(p)
				target:SetPixel(x, y, Color3.new(l, l, l), p[4])
			end
		end
	end
end

--[=[
	@within Effects
	Inverts colours.
]=]
function Effect.invert(target: any)
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				target:SetPixel(x, y, Color3.new(1 - p[1], 1 - p[2], 1 - p[3]), p[4])
			end
		end
	end
end

--[=[
	@within Effects
	Posterizes each channel to `levels` steps (default 4) - a flat, banded look.
]=]
function Effect.posterize(target: any, levels: number?)
	local n = (levels or 4) - 1
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				target:SetPixel(
					x,
					y,
					Color3.new(math.floor(p[1] * n + 0.5) / n, math.floor(p[2] * n + 0.5) / n, math.floor(p[3] * n + 0.5) / n),
					p[4]
				)
			end
		end
	end
end

--[=[
	@within Effects
	Darkens every `Gap`-th row by `Darkness` - CRT scanlines.
]=]
function Effect.scanlines(target: any, options: { Gap: number?, Darkness: number? }?)
	local opts = options or {}
	local gap = opts.Gap or 2
	local dark = opts.Darkness or 0.45
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		local f = if y % gap == 0 then 1 - dark else 1
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				target:SetPixel(x, y, Color3.new(p[1] * f, p[2] * f, p[3] * f), p[4])
			end
		end
	end
end

--[=[
	@within Effects
	Darkens toward the edges (radial falloff) - a lens vignette.
]=]
function Effect.vignette(target: any, options: { Strength: number? }?)
	local strength = (options or {}).Strength or 0.8
	local px, W, H = snapshot(target)
	local cx, cy = (W - 1) / 2, (H - 1) / 2
	local maxD = math.sqrt(cx * cx + cy * cy)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / maxD
				local f = clamp01(1 - strength * d * d)
				target:SetPixel(x, y, Color3.new(p[1] * f, p[2] * f, p[3] * f), p[4])
			end
		end
	end
end

--[=[
	@within Effects
	Splits the red and blue channels horizontally by `amount` px - chromatic aberration / 3D-glasses.
]=]
function Effect.chromatic(target: any, amount: number?)
	local a = amount or 2
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		local row = y * W
		for x = 0, W - 1 do
			local cp = px[row + x + 1]
			if cp[4] > 0.004 then
				local rp = px[row + math.clamp(x - a, 0, W - 1) + 1]
				local bp = px[row + math.clamp(x + a, 0, W - 1) + 1]
				target:SetPixel(x, y, Color3.new(rp[1], cp[2], bp[3]), cp[4])
			end
		end
	end
end

--[=[
	@within Effects
	Random horizontal band shifts + a colour split - a digital glitch / datamosh.
]=]
function Effect.glitch(target: any, options: { Bands: number?, MaxShift: number? }?)
	local opts = options or {}
	local bands = opts.Bands or 6
	local maxShift = opts.MaxShift or 6
	local px, W, H = snapshot(target)
	for _ = 1, bands do
		local y0 = math.random(0, H - 1)
		local bh = math.random(2, 6)
		local shift = math.random(-maxShift, maxShift)
		local cShift = math.random(-2, 2)
		for y = y0, math.min(y0 + bh, H - 1) do
			local row = y * W
			for x = 0, W - 1 do
				local p = px[row + math.clamp(x - shift, 0, W - 1) + 1]
				local rp = px[row + math.clamp(x - shift - cShift, 0, W - 1) + 1]
				if p[4] > 0.004 then
					target:SetPixel(x, y, Color3.new(rp[1], p[2], p[3]), p[4])
				end
			end
		end
	end
end

--[=[
	@within Effects
	Sobel edge detection - a glowing wireframe / blueprint look. `Color`/`Background` set the lines.
]=]
function Effect.edges(target: any, options: { Color: Color3?, Background: Color3? }?)
	local opts = options or {}
	local color = opts.Color or Color3.new(1, 1, 1)
	local bg = opts.Background or Color3.new(0, 0, 0)
	local px, W, H = snapshot(target)
	local function L(x: number, y: number): number
		return lum(px[math.clamp(y, 0, H - 1) * W + math.clamp(x, 0, W - 1) + 1])
	end
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local gx = L(x - 1, y - 1) + 2 * L(x - 1, y) + L(x - 1, y + 1) - L(x + 1, y - 1) - 2 * L(x + 1, y) - L(x + 1, y + 1)
			local gy = L(x - 1, y - 1) + 2 * L(x, y - 1) + L(x + 1, y - 1) - L(x - 1, y + 1) - 2 * L(x, y + 1) - L(x + 1, y + 1)
			local m = clamp01(math.sqrt(gx * gx + gy * gy))
			target:SetPixel(x, y, bg:Lerp(color, m), 1)
		end
	end
end

--[=[
	@within Effects
	Sine-warps columns vertically - a ripple / heat-haze. `Amplitude`/`Frequency`/`Phase` shape it.
]=]
function Effect.wave(target: any, options: { Amplitude: number?, Frequency: number?, Phase: number? }?)
	local opts = options or {}
	local amp = opts.Amplitude or 3
	local freq = opts.Frequency or 0.2
	local phase = opts.Phase or 0
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		local row = y * W
		for x = 0, W - 1 do
			local sx = math.clamp(math.round(x + math.sin(y * freq + phase) * amp), 0, W - 1)
			local p = px[row + sx + 1]
			target:SetPixel(x, y, Color3.new(p[1], p[2], p[3]), p[4])
		end
	end
end

--[=[
	@within Effects
	Adds random luminance noise - film grain / static. `amount` is the strength (default 0.15).
]=]
function Effect.grain(target: any, amount: number?)
	local a = amount or 0.15
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				local n = (math.random() - 0.5) * a
				target:SetPixel(x, y, Color3.new(clamp01(p[1] + n), clamp01(p[2] + n), clamp01(p[3] + n)), p[4])
			end
		end
	end
end

--[=[
	@within Effects
	Tints toward `color` by `strength` (0..1).
]=]
function Effect.tint(target: any, color: Color3, strength: number?)
	local s = strength or 0.4
	local px, W, H = snapshot(target)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				local base = Color3.new(p[1], p[2], p[3])
				target:SetPixel(x, y, base:Lerp(color, s), p[4])
			end
		end
	end
end

--[=[
	@within Effects
	Blooms bright areas: box-blurs the pixels above `Threshold` and adds the glow back. `Radius`
	sets the spread.
]=]
function Effect.bloom(target: any, options: { Threshold: number?, Radius: number?, Intensity: number? }?)
	local opts = options or {}
	local threshold = opts.Threshold or 0.65
	local radius = opts.Radius or 2
	local intensity = opts.Intensity or 0.7
	local px, W, H = snapshot(target)

	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local p = px[y * W + x + 1]
			if p[4] > 0.004 then
				-- average the bright neighbours
				local sr, sg, sb, count = 0, 0, 0, 0
				for dy = -radius, radius do
					for dx = -radius, radius do
						local nx, ny = x + dx, y + dy
						if nx >= 0 and nx < W and ny >= 0 and ny < H then
							local q = px[ny * W + nx + 1]
							if lum(q) > threshold then
								sr += q[1]
								sg += q[2]
								sb += q[3]
							end
							count += 1
						end
					end
				end
				if count > 0 then
					target:SetPixel(
						x,
						y,
						Color3.new(
							clamp01(p[1] + sr / count * intensity),
							clamp01(p[2] + sg / count * intensity),
							clamp01(p[3] + sb / count * intensity)
						),
						p[4]
					)
				end
			end
		end
	end
end

--[=[
	@within Effects
	Renders the target as coloured ASCII characters (by brightness) - the Teletext / terminal look.
]=]
function Effect.ascii(target: any)
	local ramp = " .:-=+*#%@"
	local px, W, H = snapshot(target)
	local cw, ch = Font.Advance, Font.Height + 1 -- glyph cell
	target:Fill(Color3.new(0, 0, 0), 1)
	for cy = 0, math.floor(H / ch) - 1 do
		for cx = 0, math.floor(W / cw) - 1 do
			local sr, sg, sb, l, n = 0, 0, 0, 0, 0
			for dy = 0, ch - 1 do
				for dx = 0, cw - 1 do
					local p = px[(cy * ch + dy) * W + (cx * cw + dx) + 1]
					if p then
						sr += p[1]
						sg += p[2]
						sb += p[3]
						l += lum(p)
						n += 1
					end
				end
			end
			if n > 0 then
				local idx = 1 + math.floor(clamp01(l / n) * (#ramp - 1))
				local ch2 = string.sub(ramp, idx, idx)
				target:Text(ch2, cx * cw, cy * ch, Color3.new(sr / n, sg / n, sb / n))
			end
		end
	end
end

--[=[
	@within Effects
	The full old-TV look: chromatic aberration + scanlines + vignette.
]=]
function Effect.crt(target: any)
	Effect.chromatic(target, 1)
	Effect.scanlines(target, { Gap = 2, Darkness = 0.35 })
	Effect.vignette(target, { Strength = 0.6 })
end

--[=[
	@within Effects
	A sci-fi hologram: blue tint + scanlines + a little grain.
]=]
function Effect.hologram(target: any)
	Effect.tint(target, Color3.fromRGB(80, 190, 255), 0.45)
	Effect.scanlines(target, { Gap = 2, Darkness = 0.4 })
	Effect.grain(target, 0.08)
end

return Effect
