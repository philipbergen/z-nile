--!strict
-- c0165 AC7 (the digest and the reads): the content digest of a gate ignores `spend.md` under a project root and every
-- ignored file, and changes for any other file, the tools line or the extra; the workspace reads give git's own blob
-- ids for tracked, modified and untracked files and write nothing to git (no object, no index); and the db path is the
-- main checkout's, from a worktree too. Fixture repository under .cache/c0165-digest.
local fingerprint = require("@znile/lib/fingerprint")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local workspace = require("@znile/lib/workspace")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0165-digest`
local repo = `{base}/repo`

local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
-- every file under the fixture's object store, and the index's bytes: what "writes nothing to git" compares
local function gitState(): string
	local r = fixture.exec(repo, "find", { ".git/objects", "-type", "f" })
	local idx = fs.readFile(`{repo}/.git/index`)
	return r.stdout .. "\n" .. tostring(#idx) .. ":" .. idx
end

local function setup()
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(base)
	t.expect(process.exec("git", { "init", "-q", repo }).ok).toBe(true)
	fixture.git(repo, { "config", "user.name", "c0165-digest" })
	fixture.git(repo, { "config", "user.email", "c0165-digest@example.invalid" })
	write(`{repo}/.gitignore`, "ignored.txt\n.cache/\n")
	write(`{repo}/kept.luau`, "return 1\n")
	write(`{repo}/changed.luau`, "return 2\n")
	write(`{repo}/gone.luau`, "return 3\n")
	write(`{repo}/pickman/.tracker/issues/f0001/spend.md`, "# spend\n")
	write(`{repo}/pickman/.tracker/issues/f0001/f0001.md`, "# f0001\n")
	fixture.git(repo, { "add", "-A" })
	fixture.git(repo, { "commit", "-qm", "seed" })
	write(`{repo}/changed.luau`, "return 22\n")
	fs.removeFile(`{repo}/gone.luau`)
	write(`{repo}/new.luau`, "return 4\n")
	write(`{repo}/ignored.txt`, "ignored\n")
end

return t.spec("c0165 content digest and workspace reads", function(it)
	it(
		"AC7: blobs are git's ids for tracked, modified and untracked files; deleted and ignored files are absent",
		function()
			setup()
			local before = gitState()
			local blobs = workspace.blobs(repo)
			t.expect(gitState()).toBe(before)
			local function id(rel: string): string
				return trim(fixture.git(repo, { "hash-object", "--no-filters", rel }))
			end
			t.expect(blobs["kept.luau"]).toBe("100644 " .. id("kept.luau"))
			t.expect(blobs["changed.luau"]).toBe("100644 " .. id("changed.luau"))
			t.expect(blobs["new.luau"]).toBe("100644 " .. id("new.luau"))
			t.expect(blobs["gone.luau"]).toBe(nil)
			t.expect(blobs["ignored.txt"]).toBe(nil)
			t.expect(blobs[".gitignore"] ~= nil).toBe(true)
			-- hash-object without -w wrote no object: the new file's blob is not in the store
			local cat = fixture.exec(repo, "git", { "cat-file", "-e", id("new.luau") })
			t.expect(cat.ok).toBe(false)
		end
	)

	it("AC7: the workspace reads never name a writing git command", function()
		local text = fs.readFile(`{root}/z-nile/lib/workspace.luau`)
		-- every quoting form of an argument, and the writing commands by name (lesson zz-test/absence-scans-cover-every-form)
		local names =
			{ "write-tree", "update-index", "GIT_INDEX_FILE", "GIT_DIR", "--stdin -w", "-w --stdin" }
		for _, word in { "-w", "add", "commit" } do
			for _, q in { '"', "'", "`" } do
				table.insert(names, q .. word .. q)
			end
		end
		for _, banned in names do
			if string.find(text, banned, 1, true) then
				error(`workspace.luau names {banned}`)
			end
		end
	end)

	it("AC7: the digest ignores spend.md under a project root and changes for anything else", function()
		setup()
		local blobs = workspace.blobs(repo)
		local tools = "Darwin arm64 | lune 0.11.1"
		local extra = { "full", "pickman,z-nile" }
		local d = fingerprint.digest(blobs, tools, extra)
		t.expect(#d).toBe(64)
		t.expect(fingerprint.digest(table.clone(blobs), tools, extra)).toBe(d)
		local function with(path: string, blob: string?): string
			local b = table.clone(blobs)
			b[path] = blob
			return fingerprint.digest(b, tools, extra)
		end
		t.expect(with("pickman/.tracker/issues/f0001/spend.md", "100644 " .. string.rep("9", 40))).toBe(d)
		t.expect(with("pickman/.tracker/issues/f0001/spend.md", nil)).toBe(d)
		t.expect(with("pickman/.tracker/issues/f0001/f0001.md", "100644 " .. string.rep("9", 40)) ~= d)
			.toBe(true)
		t.expect(with("kept.luau", "100644 " .. string.rep("9", 40)) ~= d).toBe(true)
		t.expect(with("kept.luau", "100755 " .. string.sub(blobs["kept.luau"], 8)) ~= d).toBe(true) -- mode
		t.expect(with("kept.luau", nil) ~= d).toBe(true)
		t.expect(with("extra.luau", "100644 " .. string.rep("9", 40)) ~= d).toBe(true)
		-- a spend.md outside a project root is ordinary content
		t.expect(with("spend.md", "100644 " .. string.rep("9", 40)) ~= d).toBe(true)
		t.expect(fingerprint.digest(blobs, tools .. " | git 2.50", extra) ~= d).toBe(true)
		t.expect(fingerprint.digest(blobs, tools, { "affected", "pickman,z-nile" }) ~= d).toBe(true)
		t.expect(fingerprint.digest(blobs, tools, { "full", "pickman" }) ~= d).toBe(true)
		-- an ignored file's edit leaves the digest alone (the read never lists it)
		write(`{repo}/ignored.txt`, "changed\n")
		t.expect(fingerprint.digest(workspace.blobs(repo), tools, extra)).toBe(d)
	end)

	it("AC7: the db path is the main checkout's .claude, from a worktree as well", function()
		setup()
		fixture.git(repo, { "commit", "-qam", "more" })
		local main = fixture.physical(repo) :: string
		t.expect(workspace.dbPath(repo)).toBe(`{main}/.claude/.znile_tests.sqlite`)
		fixture.git(repo, { "worktree", "add", "-q", `{base}/wt`, "-b", "wt" })
		t.expect(workspace.dbPath(`{base}/wt`)).toBe(`{main}/.claude/.znile_tests.sqlite`)
		-- a folder in no repository has no db path
		fs.writeDir(`{base}/plain`)
		local p, why = workspace.dbPath(`{base}/plain`)
		t.expect(p).toBe(nil)
		t.expect(why ~= nil).toBe(true)
	end)
end)
