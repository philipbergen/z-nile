--!strict
-- c0195 AC5: git's other commands run in a repository the fence protects as they did before (reads, `branch` without a
-- copy or rename, an alias defined but not used, git's own options first), and the ref guard's hook still refuses
-- what it refused (a new branch, a tag): the fence's git hands them to the real git unchanged. On every git this
-- machine has (harness.luau).
local fs = require("@lune/fs")
local h = require("./harness")
local t = require("@tests/lib/t")

local base = h.fresh("reads")

return t.spec("c0195 git's other commands are untouched in a protected repository", function(it)
	for _, g in h.GITS do
		it(`AC5: git's other commands run in the protected repository as before ({g.version})`, function()
			local reads: { h.Form } = {
				{ where = "real", args = { "branch" } },
				{ where = "real", args = { "branch", "--list", "-v" } },
				{ where = "real", args = { "branch", "--show-current" } },
				{ where = "real", args = { "branch", "--contains", "HEAD~1" } },
				{ where = "real", args = { "rev-parse", "HEAD" } },
				{ where = "real", args = { "log", "-1", "--format=%s" } },
				{ where = "real", args = { "status", "--short" } },
				{ where = "real", args = { "--version" } },
				{ where = "real", args = { "-C", "@REAL@", "show", "-s", "--format=%s", "side" } },
				{ where = "real", args = { "-c", "alias.lg=log -1", "log", "-1" } }, -- an alias defined, not used
			}
			local b = h.runForms(base, g, "reads", reads)
			for i, f in reads do
				if b.ran[i].code ~= 0 then
					error(
						`{g.version}: {h.show(f)} failed in the protected repository (exit {b.ran[i].code}): {b.ran[i].stderr}`
					)
				end
				t.expect(h.has(b.ran[i].stderr, "fence:")).toBe(false)
			end
			t.expect(b.after).toBe(b.before)
		end)

		it(`AC5: the ref guard's hook still refuses a new branch and a tag ({g.version})`, function()
			local writes: { h.Form } = {
				{ where = "real", args = { "branch", "new" } },
				{ where = "real", args = { "tag", "t2" } },
			}
			local w = h.runForms(base, g, "writes", writes)
			for i, f in writes do
				if w.ran[i].code == 0 or not h.has(w.ran[i].stderr, "refused") then
					error(`{g.version}: {h.show(f)} was not refused by the ref guard: {w.ran[i].stderr}`)
				end
			end
			t.expect(w.after).toBe(w.before)
		end)
	end

	it("cleans up", function()
		h.remove(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
