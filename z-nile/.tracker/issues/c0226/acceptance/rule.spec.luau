--!strict
-- c0226 AC1: the one rule history (c0118) and `trail.cuts` judge compactions by, `ids.cutFile`, over one commit's map
-- diffs: a commit is a compaction when it changes a map in place, or adds one whose content no map it deletes in the same
-- commit had. Moving the map unchanged (c0114) is none; moving it and changing it in the same commit is one, named by
-- the file it moved to; the content is compared line by line, so a reordered map is a change. And the map patch's one
-- reader, `ids.mapPatchLine`, which history and trail.cuts both read map diffs through: the add and delete markers, the
-- content lines without the `+++ `/`--- ` headers, and every other line (`\ No newline at end of file` too) ignored.
-- Pure: writes nothing.
local ids = require("@znile/engine/ids")
local t = require("@tests/lib/t")

local OLD, NEW = "tracker/compaction.txt", "z-nile/compaction.txt"

local function diff(path: string, kind: string, lines: { string }): ids.MapDiff
	return {
		path = path,
		added = kind == "add",
		deleted = kind == "delete",
		plus = if kind == "delete" then {} else lines,
		minus = if kind == "add" then {} else lines,
	}
end

return t.spec("c0226 the compaction rule over map diffs", function(it)
	it("AC1: a map changed in place makes a compaction, named by its file", function()
		t.expect(ids.cutFile({ diff(NEW, "change", { "c0300 c0030" }) })).toBe(NEW)
	end)

	it("AC1: a map added with no deletion makes a compaction", function()
		t.expect(ids.cutFile({ diff(NEW, "add", { "# map", "c0300 c0030" }) })).toBe(NEW)
	end)

	it("AC1: a map moved unchanged is no compaction, in either order of its two diffs", function()
		local lines = { "# map", "c0300 c0030" }
		t.expect(ids.cutFile({ diff(OLD, "delete", lines), diff(NEW, "add", lines) })).toBe(nil)
		t.expect(ids.cutFile({ diff(NEW, "add", lines), diff(OLD, "delete", lines) })).toBe(nil)
	end)

	it(
		"AC1: a map moved and changed in the same commit is a compaction, named by the file it moved to",
		function()
			local maps = {
				diff(OLD, "delete", { "# map", "c0300 c0030" }),
				diff(NEW, "add", { "# map", "c0301 c0031" }),
			}
			t.expect(ids.cutFile(maps)).toBe(NEW)
		end
	)

	it(
		"AC1: a map moved with only its lines reordered is a compaction: the content is compared line by line",
		function()
			local maps = {
				diff(OLD, "delete", { "c0300 c0030", "c0400 c0040" }),
				diff(NEW, "add", { "c0400 c0040", "c0300 c0030" }),
			}
			t.expect(ids.cutFile(maps)).toBe(NEW)
		end
	)

	it("AC1: a deleted map, or no map at all, is no compaction", function()
		t.expect(ids.cutFile({ diff(OLD, "delete", { "c0300 c0030" }) })).toBe(nil)
		t.expect(ids.cutFile({})).toBe(nil)
	end)

	it("AC1: beside a move of one map, a change of another names the compaction", function()
		local lines = { "# map", "c0300 c0030" }
		local maps = {
			diff(OLD, "delete", lines),
			diff(NEW, "add", lines),
			diff("z-nile/other.txt", "change", { "x" }),
		}
		t.expect(ids.cutFile(maps)).toBe("z-nile/other.txt")
	end)

	local function read(path: string, lines: { string }): ids.MapDiff
		local m: ids.MapDiff = { path = path, added = false, deleted = false, plus = {}, minus = {} }
		for _, line in lines do
			ids.mapPatchLine(m, line)
		end
		return m
	end

	it("AC1: the map patch reader marks an added map and keeps its content lines, not the headers", function()
		local m = read(NEW, {
			"new file mode 100644",
			"index 0000000..1111111",
			"--- /dev/null",
			"+++ b/z-nile/compaction.txt",
			"@@ -0,0 +1,2 @@",
			"+# map",
			"+c0300 c0030",
			"\\ No newline at end of file",
		})
		t.expect(m)
			.toEqual({ path = NEW, added = true, deleted = false, plus = { "# map", "c0300 c0030" }, minus = {} })
	end)

	it(
		"AC1: the map patch reader marks a deleted map and keeps its content lines, not the headers",
		function()
			local m = read(OLD, {
				"deleted file mode 100644",
				"index 1111111..0000000",
				"--- a/tracker/compaction.txt",
				"+++ /dev/null",
				"@@ -1,2 +0,0 @@",
				"-# map",
				"-c0300 c0030",
			})
			t.expect(m)
				.toEqual({ path = OLD, added = false, deleted = true, plus = {}, minus = { "# map", "c0300 c0030" } })
		end
	)

	it("AC1: the map patch reader reads a change in place as neither added nor deleted", function()
		local m = read(NEW, {
			"index 1111111..2222222 100644",
			"--- a/z-nile/compaction.txt",
			"+++ b/z-nile/compaction.txt",
			"@@ -2 +2 @@",
			"-c0300 c0030",
			"+c0300 c0031",
		})
		t.expect(m).toEqual({
			path = NEW,
			added = false,
			deleted = false,
			plus = { "c0300 c0031" },
			minus = { "c0300 c0030" },
		})
	end)
end)
