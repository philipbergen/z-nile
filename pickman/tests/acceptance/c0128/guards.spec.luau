--!strict
-- c0128 AC3: each of the seven narrowed cases keeps the guard it had for the per-player boards and allows only
-- d0124's HiscoreTop besides. titles.spec pins that no case is removed, renamed or added. Both read the files as text;
-- running them is AC1.
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local ROOT = "tests/" .. "acceptance/"
local F24 = ROOT .. renamed.id("f0024") .. "/adapter.spec.luau"
local F26 = ROOT .. renamed.id("f0026") .. "/adapters.spec.luau"

-- the text of one case: from its title to the next case, or the end of the spec
local function case(path: string, title: string): string
	local src = fs.readFile(path)
	local at = string.find(src, `"{title}"`, 1, true)
	assert(at ~= nil, `no case "{title}" in {path}`)
	local nextAt = string.find(src, '%f[%w]it%(%s*"', at + #title + 2)
	return string.sub(src, at, (nextAt or #src + 1) - 1)
end

local function has(body: string, needle: string): boolean
	return string.find(body, needle, 1, true) ~= nil
end

local function count(body: string, needle: string): number
	local n, from = 0, 1
	while true do
		local at = string.find(body, needle, from, true)
		if at == nil then
			return n
		end
		n += 1
		from = at + #needle
	end
end

return t.spec("c0128 narrowed guards", function(it)
	it(
		"the stores case still names all six per-player stores, and allows only HiscoreTop|all besides",
		function()
			local body = case(
				F24,
				"stores are the shared names scoped by period, budgets are the modern request types"
			)
			for _, name in
				{
					"HiscoreEntries|all",
					"HiscoreEntries|day:2026-10-16",
					"HiscoreEntries|week:2026-10-12",
					"Hiscores|all",
					"Hiscores|day:2026-10-16",
					"Hiscores|week:2026-10-12",
					"HiscoreTop|all",
				}
			do
				t.expect(has(body, `"{name}"`)).toBe(true)
			end
			t.expect(has(body, "DataStoreRequestType.OrderedWrite")).toBe(true)
			t.expect(has(body, "then 7 else 6")).toBe(true)
		end
	)

	it(
		"the budgets case still counts six per-player updates, each after both budgets of its own store",
		function()
			local body = case(F24, "each update is preceded by the read and write budgets of its own store")
			t.expect(has(body, "toBe(6)")).toBe(true)
			t.expect(has(body, "HiscoreTop")).toBe(true)
			for _, kind in { "OrderedRead", "OrderedWrite", "StandardRead", "StandardWrite" } do
				t.expect(has(body, `DataStoreRequestType.{kind}`)).toBe(true)
			end
		end
	)

	it("the three answer cases compare the first four values, and keep the values they compared", function()
		local failed =
			case(F26, "a failed read still answers once, with failed = true and the rows it had, or none")
		-- every whole-answer comparison the case made is still made, on the first four values
		t.expect(count(failed, "four(")).toBe(7)
		t.expect(has(failed, '{ "all", {}, nil, true }')).toBe(true)
		t.expect(has(failed, '{ "all", healthy[2], 2, true }')).toBe(true)
		local wedged = case(
			F26,
			"an error anywhere in the read, opening the store included, is a failed read and the board is not wedged"
		)
		t.expect(count(wedged, "four(")).toBe(2)
		t.expect(has(wedged, '{ "all", {}, nil, true }')).toBe(true)
		local short = case(
			F26,
			"a companion row that cannot be read fails the read: no short board is answered as healthy or cached"
		)
		t.expect(count(short, "four(")).toBe(2)
		t.expect(has(short, 'name = "Ada", score = 50, level = 2')).toBe(true)
	end)

	it(
		"the opens case still requires the per-player stores, and allows only HiscoreTop|all besides",
		function()
			local body = case(
				F26,
				"Boards opens the ordered and the companion store under their own names and the board's scope"
			)
			t.expect(has(body, '"companion|HiscoreEntries|all"')).toBe(true)
			t.expect(has(body, '"companion|HiscoreTop|all"')).toBe(true)
			t.expect(has(body, '"ordered|Hiscores|all"')).toBe(true)
			t.expect(has(body, 'table.find(w.opens, "companion|HiscoreEntries|all") ~= nil')).toBe(true)
		end
	)

	it("the page-of-50 case still caps the row reads at N, and requires some", function()
		local body = case(
			F26,
			"a page of 50 after the size-10 fallback is cut to the top N before any companion is read"
		)
		t.expect(has(body, "<= Hiscores.N")).toBe(true)
		t.expect(has(body, "> 0")).toBe(true)
		t.expect(has(body, "toBe(50)")).toBe(true)
	end)
end)
