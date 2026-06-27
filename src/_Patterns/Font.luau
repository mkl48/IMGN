-- IMGN
-- _Patterns/Font.luau
-- Plinko Labs
--
-- A tiny 3x5 bitmap font so canvases can draw text - scores, labels, HUDs - without any external
-- asset. Each glyph is five 3-wide rows of '#'/'.'; `draw` walks them and calls a `plot(x, y)`
-- callback (so the Canvas hands in its own SetPixel, same pattern as _Patterns/Draw). Covers
-- 0-9, A-Z, space and a little punctuation; unknown characters render as a blank cell. Letters
-- are uppercase-only - lowercase input is folded up before lookup.

--[=[
	@class Font
	The built-in 3x5 bitmap font used by [Canvas:Text]. `Width`/`Height` are the glyph cell size;
	`Advance` is per-character spacing (cell + 1px gap) at scale 1.
]=]
local Font = {}

Font.Width = 3
Font.Height = 5
Font.Advance = 4 -- 3px glyph + 1px gap

-- '#' = lit pixel, '.' = empty. Five rows of three.
local GLYPHS: { [string]: { string } } = {
	["0"] = { "###", "#.#", "#.#", "#.#", "###" },
	["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
	["2"] = { "###", "..#", "###", "#..", "###" },
	["3"] = { "###", "..#", "###", "..#", "###" },
	["4"] = { "#.#", "#.#", "###", "..#", "..#" },
	["5"] = { "###", "#..", "###", "..#", "###" },
	["6"] = { "###", "#..", "###", "#.#", "###" },
	["7"] = { "###", "..#", "..#", "..#", "..#" },
	["8"] = { "###", "#.#", "###", "#.#", "###" },
	["9"] = { "###", "#.#", "###", "..#", "###" },
	["A"] = { "###", "#.#", "###", "#.#", "#.#" },
	["B"] = { "##.", "#.#", "##.", "#.#", "##." },
	["C"] = { "###", "#..", "#..", "#..", "###" },
	["D"] = { "##.", "#.#", "#.#", "#.#", "##." },
	["E"] = { "###", "#..", "##.", "#..", "###" },
	["F"] = { "###", "#..", "##.", "#..", "#.." },
	["G"] = { "###", "#..", "#.#", "#.#", "###" },
	["H"] = { "#.#", "#.#", "###", "#.#", "#.#" },
	["I"] = { "###", ".#.", ".#.", ".#.", "###" },
	["J"] = { "..#", "..#", "..#", "#.#", "###" },
	["K"] = { "#.#", "#.#", "##.", "#.#", "#.#" },
	["L"] = { "#..", "#..", "#..", "#..", "###" },
	["M"] = { "#.#", "###", "#.#", "#.#", "#.#" },
	["N"] = { "#.#", "##.", "#.#", ".##", "#.#" },
	["O"] = { "###", "#.#", "#.#", "#.#", "###" },
	["P"] = { "###", "#.#", "###", "#..", "#.." },
	["Q"] = { "###", "#.#", "#.#", "###", "..#" },
	["R"] = { "###", "#.#", "###", "##.", "#.#" },
	["S"] = { "###", "#..", "###", "..#", "###" },
	["T"] = { "###", ".#.", ".#.", ".#.", ".#." },
	["U"] = { "#.#", "#.#", "#.#", "#.#", "###" },
	["V"] = { "#.#", "#.#", "#.#", "#.#", ".#." },
	["W"] = { "#.#", "#.#", "#.#", "###", "#.#" },
	["X"] = { "#.#", "#.#", ".#.", "#.#", "#.#" },
	["Y"] = { "#.#", "#.#", ".#.", ".#.", ".#." },
	["Z"] = { "###", "..#", ".#.", "#..", "###" },
	[" "] = { "...", "...", "...", "...", "..." },
	["."] = { "...", "...", "...", "...", ".#." },
	[","] = { "...", "...", "...", ".#.", "#.." },
	[":"] = { "...", ".#.", "...", ".#.", "..." },
	["!"] = { ".#.", ".#.", ".#.", "...", ".#." },
	["?"] = { "###", "..#", ".##", "...", ".#." },
	["-"] = { "...", "...", "###", "...", "..." },
	["+"] = { "...", ".#.", "###", ".#.", "..." },
	["/"] = { "..#", "..#", ".#.", "#..", "#.." },
	["="] = { "...", "###", "...", "###", "..." },
	["<"] = { "..#", ".#.", "#..", ".#.", "..#" },
	[">"] = { "#..", ".#.", "..#", ".#.", "#.." },
	["%"] = { "#.#", "..#", ".#.", "#..", "#.#" },
	["*"] = { "...", "#.#", ".#.", "#.#", "..." },
	["("] = { ".#.", "#..", "#..", "#..", ".#." },
	[")"] = { ".#.", "..#", "..#", "..#", ".#." },
}

--[=[
	@within Font
	Walks `text` left-to-right from `(x, y)`, calling `plot(px, py)` for every lit pixel. `scale`
	(default 1) draws each font pixel as a `scale` x `scale` block. Returns the x just past the
	last glyph, so callers can chain or measure.
]=]
function Font.draw(plot: (number, number) -> (), text: string, x: number, y: number, scale: number?): number
	local s = scale or 1
	local cursor = x
	for i = 1, #text do
		local char = string.upper(string.sub(text, i, i))
		local glyph = GLYPHS[char] or GLYPHS[" "]
		for row = 1, Font.Height do
			local line = glyph[row]
			for col = 1, Font.Width do
				if string.sub(line, col, col) == "#" then
					local bx = cursor + (col - 1) * s
					local by = y + (row - 1) * s
					for sy = 0, s - 1 do
						for sx = 0, s - 1 do
							plot(bx + sx, by + sy)
						end
					end
				end
			end
		end
		cursor += Font.Advance * s
	end
	return cursor
end

--[=[
	@within Font
	Pixel width of `text` at `scale` (no trailing gap).
]=]
function Font.measure(text: string, scale: number?): number
	local s = scale or 1
	if #text == 0 then
		return 0
	end
	return (#text * Font.Advance - 1) * s
end

return Font
