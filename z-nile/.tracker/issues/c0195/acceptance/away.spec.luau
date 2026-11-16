--!strict
-- c0195 AC3: a copy or rename run from another folder but aimed at the protected repository by git's own options
-- (`-C`, `--git-dir`, `--work-tree`) is refused: the fence's git asks git which repository the command acts on, with
-- the same options. Neither repository changes. On every git this machine has (harness.luau).
local fs = require("@lune/fs")
local h = require("./harness")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local base = h.fresh("away")

return t.spec("c0195 a copy aimed at the protected repository from elsewhere is refused", function(it)
	for _, g in h.GITS do
		it(
			`AC3: a copy or rename aimed at the protected repository by -C or --git-dir is refused ({g.version})`,
			function()
				local forms: { h.Form } = {
					{ where = "away", args = { "-C", "@REAL@", "branch", "-c", "main", "evil" } },
					{ where = "away", args = { "--git-dir", "@REAL@/.git", "branch", "-C", "main", "side" } },
					{ where = "away", args = { "--git-dir=@REAL@/.git", "branch", "-m", "side", "moved" } },
					{
						where = "away",
						args = { "--work-tree", "@REAL@", "-C", "@REAL@", "branch", "--copy", "main", "evil" },
					},
				}
				-- the same repository under other letters (only a case-folding volume makes it one: -ef decides)
				local up = string.upper(base)
				if up ~= base and process.exec("test", { up, "-ef", base }).ok then
					table.insert(forms, {
						where = "away",
						args = { "--git-dir=@REALUP@/.git", "branch", "-c", "main", "evil" },
					})
				end
				local b = h.runForms(base, g, "away", forms)
				for i, f in forms do
					if b.ran[i].code == 0 or not h.has(b.ran[i].stderr, h.REFUSED_COPY) then
						error(
							`{g.version}: {h.show(f)} was not refused (exit {b.ran[i].code}): {b.ran[i].stderr}`
						)
					end
					-- the folder the command ran in is untouched as well
					t.expect(b.ran[i].after).toBe(b.freeBefore)
				end
				t.expect(b.after).toBe(b.before)
			end
		)
	end

	it("cleans up", function()
		h.remove(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
