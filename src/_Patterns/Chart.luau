-- IMGN
-- _Patterns/Chart.luau
-- Plinko Labs
--
-- Charts drawn onto any canvas/region: line, bar and pie. `target` is anything with `Width`,
-- `Height`, `SetPixel`, `DrawLine`, `DrawRect` (a Canvas or a Region), so a chart drops straight
-- onto a HUD, a stat panel, or a sub-region of a bigger canvas. Useful for the boring-but-needed
-- stuff: economy dashboards, leaderboards, fps/ping overlays, admin tooling.

--[=[
	@class Chart
	Line / bar / pie chart drawing onto a [Canvas] or [Region]. Reached via `IMGN.Chart`.
]=]
local Chart = {}

local function extent(data: { number }): (number, number)
	local min, max = math.huge, -math.huge
	for _, v in data do
		min = math.min(min, v)
		max = math.max(max, v)
	end
	if min == math.huge then
		return 0, 1
	end
	if max == min then
		max = min + 1
	end
	return min, max
end

--[=[
	@within Chart
	Plots `data` (an array of numbers) as a line graph. `options`: `Color`, `Min`/`Max` (else auto),
	`Pad` (margin px). The line is drawn left-to-right, low values at the bottom.
]=]
function Chart.line(target: any, data: { number }, options: { Color: Color3?, Min: number?, Max: number?, Pad: number? }?)
	local opts = options or {}
	local n = #data
	if n < 2 then
		return
	end
	local W, H = target.Width, target.Height
	local pad = opts.Pad or 1
	local dmin, dmax = extent(data)
	local lo = opts.Min or dmin
	local hi = opts.Max or dmax
	if hi == lo then
		hi = lo + 1
	end
	local color = opts.Color or Color3.fromRGB(90, 200, 255)
	local innerW, innerH = W - 1 - 2 * pad, H - 1 - 2 * pad

	local function point(i: number): (number, number)
		local x = pad + (i - 1) / (n - 1) * innerW
		local v = (data[i] - lo) / (hi - lo)
		local y = (H - 1 - pad) - v * innerH
		return math.round(x), math.round(y)
	end

	for i = 1, n - 1 do
		local x0, y0 = point(i)
		local x1, y1 = point(i + 1)
		target:DrawLine(x0, y0, x1, y1, color)
	end
end

--[=[
	@within Chart
	Plots `data` as vertical bars. `options`: `Color`, `Max` (else auto), `Gap` (px between bars).
]=]
function Chart.bar(target: any, data: { number }, options: { Color: Color3?, Max: number?, Gap: number? }?)
	local opts = options or {}
	local n = #data
	if n == 0 then
		return
	end
	local W, H = target.Width, target.Height
	local _, max = extent(data)
	max = opts.Max or max
	if max <= 0 then
		max = 1
	end
	local color = opts.Color or Color3.fromRGB(120, 220, 140)
	local gap = opts.Gap or 1
	local slot = W / n

	for i = 1, n do
		local h = math.max(0, math.round(data[i] / max * (H - 1)))
		local x = math.round((i - 1) * slot)
		local w = math.max(1, math.floor(slot) - gap)
		target:DrawRect(x, H - h, w, h, color, true)
	end
end

--[=[
	@within Chart
	Draws a pie chart from `slices` (`{ { value = n, color = Color3 }, ... }`). Fills each sector by
	scanning the disc; centred, sized to fit.
]=]
function Chart.pie(target: any, slices: { { value: number, color: Color3 } })
	local W, H = target.Width, target.Height
	local cx, cy = (W - 1) / 2, (H - 1) / 2
	local radius = math.min(W, H) / 2 - 1

	local total = 0
	for _, s in slices do
		total += s.value
	end
	if total <= 0 then
		return
	end

	-- cumulative end fraction per slice
	local ends = {}
	local acc = 0
	for i, s in slices do
		acc += s.value
		ends[i] = acc / total
	end

	local TAU = math.pi * 2
	local r2 = radius * radius
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local dx, dy = x - cx, y - cy
			if dx * dx + dy * dy <= r2 then
				local ang = math.atan2(dy, dx)
				if ang < 0 then
					ang += TAU
				end
				local frac = ang / TAU
				for i, e in ends do
					if frac <= e then
						target:SetPixel(x, y, slices[i].color)
						break
					end
				end
			end
		end
	end
end

return Chart
