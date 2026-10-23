--!strict
-- E3 re-run: contrast of the four series colors on the page surfaces and the palette surfaces.
-- Prints one line per pair. A mark under 3:1 is a WARN (the legend, tooltips and Table carry it).

local function lin(c: number): number
	local s = c / 255
	return if s <= 0.04045 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
end

local function lum(hex: string): number
	local r = tonumber(string.sub(hex, 2, 3), 16) :: number
	local g = tonumber(string.sub(hex, 4, 5), 16) :: number
	local b = tonumber(string.sub(hex, 6, 7), 16) :: number
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

local function contrast(fg: string, bg: string): number
	local a, b = lum(fg), lum(bg)
	local hi, lo = math.max(a, b), math.min(a, b)
	return (hi + 0.05) / (lo + 0.05)
end

local light = { feature = "#2a78d6", defect = "#eb6834", chore = "#1baf7a", net = "#6b7280" }
local dark = { feature = "#3987e5", defect = "#d95926", chore = "#199e70", net = "#9aa3ad" }
local surfaces = {
	{ "page-light", "#ffffff", light },
	{ "page-dark", "#15171a", dark },
	{ "palette-light", "#fcfcfb", light },
	{ "palette-dark", "#1a1a19", dark },
}

for _, s in surfaces do
	local name, bg, colors = s[1], s[2], s[3]
	for _, key in { "feature", "defect", "chore", "net" } do
		local ratio = contrast(colors[key], bg)
		local flag = if ratio < 3 then "WARN" else "pass"
		print(string.format("%s %s %s on %s %.2f:1", flag, name, key, bg, ratio))
	end
end
