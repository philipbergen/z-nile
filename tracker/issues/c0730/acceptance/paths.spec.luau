--!strict
-- c0730: scripts/tracker/paths.luau rewrites the item paths in a check.sh when ready, stop or done moves an item.
local paths = require("@scripts/tracker/paths")
local t = require("@tests/lib/t")

local TEXT = table.concat({
	'check "AC1: a" lune run tests/run -- tracker/issues/c0010/acceptance/a.spec.luau',
	'check "AC2: b" test -f tracker/issues/active/c0020/c0020.md',
	'check "AC3: c" test -f tracker/issues/done/c0010/check.sh',
	'check "RC1: d" bash tracker/rafts/R0010/check.sh',
	"# untouched: tracker/issues/c0090/x tracker/issues/c00100 tracker/issues/c0010-x tracker/issues/c0010_y",
	"# wrong kind, untouched: tracker/rafts/c0010 tracker/issues/R0010",
	'A="tracker/issues/c0010"',
	"",
}, "\n")

return t.spec("tracker paths", function(it)
	it("rewrite moves a listed id's paths to its target directory from any state form", function()
		local out = paths.rewrite(TEXT, {
			c0010 = "tracker/issues/active/c0010",
			c0020 = "tracker/issues/done/c0020",
			R0010 = "tracker/rafts/active/R0010",
		})
		local want = table.concat({
			'check "AC1: a" lune run tests/run -- tracker/issues/active/c0010/acceptance/a.spec.luau',
			'check "AC2: b" test -f tracker/issues/done/c0020/c0020.md',
			'check "AC3: c" test -f tracker/issues/active/c0010/check.sh',
			'check "RC1: d" bash tracker/rafts/active/R0010/check.sh',
			"# untouched: tracker/issues/c0090/x tracker/issues/c00100 tracker/issues/c0010-x tracker/issues/c0010_y",
			"# wrong kind, untouched: tracker/rafts/c0010 tracker/issues/R0010",
			'A="tracker/issues/active/c0010"',
			"",
		}, "\n")
		t.expect(out).toBe(want)
		-- and back to the backlog form
		local back = paths.rewrite(out, {
			c0010 = "tracker/issues/c0010",
			c0020 = "tracker/issues/active/c0020",
			R0010 = "tracker/rafts/R0010",
		})
		t.expect(back)
			.toBe((string.gsub(TEXT, "tracker/issues/done/c0010/check%.sh", "tracker/issues/c0010/check.sh")))
	end)

	it("rewrite leaves unlisted ids, other kinds and longer tokens alone", function()
		t.expect(paths.rewrite(TEXT, {})).toBe(TEXT)
		local only = paths.rewrite(TEXT, { c0090 = "tracker/issues/active/c0090" })
		t.expect(string.find(only, "tracker/issues/active/c0090/x", 1, true) ~= nil).toBe(true)
		t.expect(string.find(only, "tracker/issues/c00100", 1, true) ~= nil).toBe(true)
		t.expect(string.find(only, "tracker/issues/c0010-x", 1, true) ~= nil).toBe(true)
		t.expect(select(2, string.gsub(only, "active/", ""))).toBe(2) -- c0090 plus the c0020 line already active
		-- a raft id under issues/ and an issue id under rafts/ are not item paths
		local kinds =
			paths.rewrite(TEXT, { R0010 = "tracker/rafts/done/R0010", c0010 = "tracker/issues/done/c0010" })
		t.expect(string.find(kinds, "tracker/rafts/c0010 tracker/issues/R0010", 1, true) ~= nil).toBe(true)
		-- the end of the text is a boundary too
		t.expect(paths.rewrite("x tracker/rafts/R0010", { R0010 = "tracker/rafts/active/R0010" }))
			.toBe("x tracker/rafts/active/R0010")
	end)

	it("normalize strips the state segment and is unchanged by rewrite", function()
		t.expect(
			paths.normalize("a tracker/issues/active/c0010/b tracker/rafts/done/R0010 tracker/issues/f0020")
		)
			.toBe("a tracker/issues/c0010/b tracker/rafts/R0010 tracker/issues/f0020")
		local moved =
			paths.rewrite(TEXT, { c0010 = "tracker/issues/done/c0010", R0010 = "tracker/rafts/active/R0010" })
		t.expect(moved ~= TEXT).toBe(true)
		t.expect(paths.normalize(moved)).toBe(paths.normalize(TEXT))
		-- a real edit is not hidden by normalize
		t.expect(paths.normalize(moved .. "rm -rf /\n") ~= paths.normalize(TEXT)).toBe(true)
		t.expect(paths.normalize("tracker/issues/c00100")).toBe("tracker/issues/c00100")
	end)
end)
