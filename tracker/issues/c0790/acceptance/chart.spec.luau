--!strict
-- c0790: scripts/tracker/chart.luau draws the board's statistics as inline SVG. Pure; the spec reads the SVG text.
local chart = require("@scripts/tracker/chart")
local t = require("@tests/lib/t")

type Rect = { cls: string, y: number, height: number, title: string }

local function marks(svg: string): { Rect }
	local out: { Rect } = {}
	for tag, title in string.gmatch(svg, '(<rect class="mark [^"]*"[^>]*>)%s*<title>(.-)</title>') do
		table.insert(out, {
			cls = string.match(tag, 'class="mark ([^"]*)"') or "",
			y = tonumber(string.match(tag, ' y="([%-%d%.]+)"')) or 0 / 0,
			height = tonumber(string.match(tag, ' height="([%-%d%.]+)"')) or 0 / 0,
			title = title,
		})
	end
	return out
end
local function baseline(svg: string): number
	local tag = string.match(svg, '<line class="baseline"[^>]*>') or ""
	return tonumber(string.match(tag, ' y1="([%-%d%.]+)"')) or 0 / 0
end
local function count(s: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(s, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
local function opts(kind: any, labels: { string }, below: any?): chart.Options
	return {
		id = "test/chart",
		title = "Test chart",
		unit = "issues",
		labels = labels,
		kind = kind,
		below = below,
	}
end

return t.spec("tracker chart", function(it)
	it("a bar per non-zero value, each with its tooltip", function()
		local svg = chart.svg(
			{ { key = "net", label = "Net", values = { 2, 0, 5 } } },
			opts("bars", { "a", "b", "c" })
		)
		t.expect(string.find(svg, 'data-chart="test/chart"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(svg, 'role="img"', 1, true) ~= nil).toBe(true)
		local m = marks(svg)
		t.expect(#m).toBe(2)
		t.expect(m[1].title).toBe("Net, a: 2 issues")
		t.expect(m[2].title).toBe("Net, c: 5 issues")
		t.expect(m[2].height > m[1].height).toBe(true)
	end)

	it("stacked segments sit on each other, and negatives drop below the baseline", function()
		local svg = chart.svg({
			{ key = "feature", label = "Feature", values = { 2 } },
			{ key = "defect", label = "Defect", values = { 3 } },
		}, opts("stacked", { "a" }))
		local m = marks(svg)
		t.expect(#m).toBe(2)
		local feature = if string.find(m[1].cls, "s-feature", 1, true) then m[1] else m[2]
		local defect = if feature == m[1] then m[2] else m[1]
		t.expect(feature.y + feature.height <= baseline(svg) + 0.01).toBe(true) -- feature rests on the baseline
		t.expect(defect.y + defect.height <= feature.y + 0.01).toBe(true) -- defect stacks above it
		local neg =
			chart.svg({ { key = "net", label = "Net", values = { -3, 4 } } }, opts("bars", { "a", "b" }))
		local nm = marks(neg)
		t.expect(nm[1].y >= baseline(neg) - 0.01).toBe(true) -- -3 hangs below
		t.expect(nm[2].y + nm[2].height <= baseline(neg) + 0.01).toBe(true) -- 4 stands above
	end)

	it("mirror draws its below series under the baseline", function()
		local svg = chart.svg(
			{ { key = "feature", label = "Added", values = { 4 } } },
			opts("mirror", { "a" }, { { key = "feature", label = "Removed", values = { 2 } } })
		)
		local m = marks(svg)
		t.expect(#m).toBe(2)
		local added = if string.find(m[1].title, "Added", 1, true) then m[1] else m[2]
		local removed = if added == m[1] then m[2] else m[1]
		t.expect(added.y + added.height <= baseline(svg) + 0.01).toBe(true)
		t.expect(removed.y >= baseline(svg) - 0.01).toBe(true)
		t.expect(removed.title).toBe("Removed, a: 2 issues")
	end)

	it("a nil value breaks a line", function()
		local svg = chart.svg(
			{ { key = "count", label = "Defect %", values = { 10, nil, 30, 40 } } },
			{ id = "x", title = "Ratios", unit = "%", labels = { "a", "b", "c", "d" }, kind = "lines" }
		)
		local d = string.match(svg, '<path class="line s%-count"[^>]* d="([^"]*)"') or ""
		t.expect(count(d, "M")).toBe(2)
		t.expect(count(svg, "<circle")).toBe(3)
	end)

	it("one axis whose top tick covers the largest total", function()
		local svg = chart.svg({
			{ key = "feature", label = "Feature", values = { 7, 1 } },
			{ key = "defect", label = "Defect", values = { 6, 1 } },
		}, opts("stacked", { "a", "b" }))
		local top = -math.huge
		for v in string.gmatch(svg, '<text class="tick"[^>]*>([%-%d%.]+)</text>') do
			top = math.max(top, tonumber(v) :: number)
		end
		t.expect(top >= 13).toBe(true) -- the stacked total, not the largest single value
		t.expect(top <= 20).toBe(true) -- a nice number, not a far-off one
		t.expect(count(svg, 'class="baseline"')).toBe(1)
	end)

	it("a legend for two or more series, none for one", function()
		local two = chart.svg({
			{ key = "feature", label = "Feature", values = { 1 } },
			{ key = "chore", label = "Chore", values = { 1 } },
		}, opts("stacked", { "a" }))
		local legend = string.match(two, '<g class="legend".-</g>') or ""
		t.expect(string.find(legend, "Feature", 1, true) ~= nil).toBe(true)
		t.expect(string.find(legend, "Chore", 1, true) ~= nil).toBe(true)
		local one =
			chart.svg({ { key = "feature", label = "Feature", values = { 1 } } }, opts("stacked", { "a" }))
		t.expect(string.find(one, 'class="legend"', 1, true)).toBe(nil)
	end)

	it("colors are classes, never inline", function()
		local svg = chart.svg({
			{ key = "feature", label = "Feature", values = { 1, 2 } },
			{ key = "defect", label = "Defect", values = { 2, 1 } },
		}, opts("stacked", { "a", "b" }))
		t.expect(string.find(svg, "s-feature", 1, true) ~= nil).toBe(true)
		t.expect(string.find(svg, "s-defect", 1, true) ~= nil).toBe(true)
		t.expect(string.find(svg, 'fill="#', 1, true)).toBe(nil)
		t.expect(string.find(svg, 'stroke="#', 1, true)).toBe(nil)
		t.expect(string.find(svg, "style=", 1, true)).toBe(nil)
	end)

	it("no data draws an empty frame", function()
		for _, svg in
			{
				chart.svg({ { key = "net", label = "Net", values = { 0, 0 } } }, opts("bars", { "a", "b" })),
				chart.svg({ { key = "net", label = "Net", values = {} } }, opts("bars", {})),
			}
		do
			t.expect(#marks(svg)).toBe(0)
			t.expect(string.find(svg, '<text class="empty"', 1, true) ~= nil).toBe(true)
			t.expect(string.find(svg, "no data", 1, true) ~= nil).toBe(true)
		end
	end)

	it("the same input gives the same bytes", function()
		local function draw(): string
			return chart.svg({
				{ key = "feature", label = "Feature", values = { 1, 2.25, 3 } },
				{ key = "chore", label = "Chore", values = { 0.5, nil, 2 } },
			}, opts("stacked", { "a", "b", "c" }))
		end
		t.expect(draw()).toBe(draw())
		t.expect(string.find(draw(), "%d%.%d%d") == nil).toBe(true) -- at most one decimal anywhere
	end)
end)
