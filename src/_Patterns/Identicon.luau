-- IMGN
-- _Patterns/Identicon.luau
-- Plinko Labs
--
-- Deterministic GitHub-style avatars: hash a seed (a username, UserId, item id, anything) into a
-- symmetric coloured grid. Same seed always gives the same icon, every seed looks different - so
-- every player/item gets a unique avatar with zero uploads and zero moderation. Draws onto any
-- canvas/region.

--[=[
	@class Identicon
	Procedural symmetric avatars from a seed. Reached via `IMGN.Identicon`.
]=]
local Identicon = {}

-- djb2 string hash -> 0 .. 2^32
local function hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 4294967296
	end
	return h
end

local function bitAt(h: number, i: number): boolean
	return math.floor(h / 2 ^ i) % 2 >= 1
end

--[=[
	@within Identicon
	Draws an identicon for `seed` onto `target` (a Canvas or Region). `options`: `Grid` (cells per
	side, default 5), `Color`/`Background` (else derived from the seed), `Density` (0..1 chance a
	cell is filled, default 0.5).
]=]
function Identicon.draw(target: any, seed: any, options: { Grid: number?, Color: Color3?, Background: Color3?, Density: number? }?)
	local opts = options or {}
	local grid = opts.Grid or 5
	local h = hash(tostring(seed))
	local color = opts.Color or Color3.fromHSV((math.floor(h / 2 ^ 24) % 256) / 256, 0.55, 0.72)
	local background = opts.Background or Color3.fromRGB(235, 238, 242)

	local W, Hh = target.Width, target.Height
	local cell = math.max(1, math.floor(math.min(W, Hh) / grid))
	local span = cell * grid
	local offX = math.floor((W - span) / 2)
	local offY = math.floor((Hh - span) / 2)

	-- background panel
	target:DrawRect(offX, offY, span, span, background, true)

	-- fill the left half + centre column from the hash bits, mirror to the right -> symmetric
	local half = math.ceil(grid / 2)
	local threshold = (opts.Density or 0.5) * 32 -- bit-derived value in 0..31 compared to this
	local bit = 0
	for col = 0, half - 1 do
		for row = 0, grid - 1 do
			-- a 0..31 value from 5 hash bits per cell
			local v = 0
			for b = 0, 4 do
				if bitAt(h, (bit + b) % 31) then
					v += 2 ^ b
				end
			end
			bit += 5
			if v < threshold then
				for _, c in { col, grid - 1 - col } do
					target:DrawRect(offX + c * cell, offY + row * cell, cell, cell, color, true)
				end
			end
		end
	end
end

return Identicon
