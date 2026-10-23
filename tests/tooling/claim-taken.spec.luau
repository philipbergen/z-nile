--!strict
-- R0025 review 005 F1: claims.taken answers whether a stamp is already on a ref, from git grep's exit code read
-- strictly: found, not found, or an error (never "free" on an error). Fixture under .cache/claim-taken.
local claims = require("@scripts/tracker/claims")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local repo = ""

return t.spec("claims.taken", function(it)
	it("sets up a repository whose tracker holds one claimed document", function()
		local root = fixture.physical(".") :: string
		repo = `{root}/.cache/claim-taken`
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(`{repo}/tracker/issues/done/c0010`)
		process.exec("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
		fixture.git(repo, { "config", "user.name", "claim-taken" })
		fixture.git(repo, { "config", "user.email", "claim-taken@example.invalid" })
		fs.writeFile(
			`{repo}/tracker/issues/done/c0010/c0010.md`,
			"---\nid: c0010\nstatus: active-quiet-copper-falcon\n---\n\nstatus: active-only-in-body is not frontmatter, but a line is a line\n"
		)
		fs.writeFile(`{repo}/notes.md`, "status: active-outside-tracker-dir\n")
		fixture.git(repo, { "add", "-A" })
		fixture.git(repo, { "commit", "-q", "-m", "seed" })
	end)

	it("a stamp on a whole status line under tracker/ is taken, done/ included", function()
		t.expect((claims.taken(repo, "active-quiet-copper-falcon", "main", { "tracker" }))).toBe(true)
	end)

	it(
		"a stamp nobody carries is free, and so is one only outside tracker/ or inside a longer line",
		function()
			t.expect((claims.taken(repo, "active-brisk-amber-otter", "main", { "tracker" }))).toBe(false)
			t.expect((claims.taken(repo, "active-outside-tracker-dir", "main", { "tracker" }))).toBe(false)
			t.expect((claims.taken(repo, "active-quiet-copper", "main", { "tracker" }))).toBe(false) -- a prefix is not the value
		end
	)

	it("an error is no answer: a bad ref, or a value that is not a stamp", function()
		local taken, err = claims.taken(repo, "active-brisk-amber-otter", "no-such-ref", { "tracker" })
		t.expect(taken).toBe(nil)
		t.expect(err ~= nil and err ~= "").toBe(true)
		local bad, why = claims.taken(repo, "active-a.*", "main", { "tracker" })
		t.expect(bad).toBe(nil)
		t.expect(why ~= nil).toBe(true)
	end)
end)
