--!strict
-- c0420: tracker documents are named <ID>.md with the slug in the frontmatter.
-- Fixture under .cache/naming-e2e: a clone of the repo's committed HEAD with `main` forced as its
-- branch, no `origin` (so every tracker command runs freely), the working tree's tooling overlaid,
-- and the tracker emptied. The spec passes from any branch and from a detached HEAD.
local clone = require("@tests/lib/clone")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/naming-e2e`
local seed = `{base}/seed`

-- Fixture repos are throwaway: no background gc/maintenance that could race a re-created fixture. The
-- runner's guard (scripts/lib/fence.sh) turns both off for every git a spec runs; a spec must not set
-- git config through the environment, which would replace the guard's (testing skill).
local NO_GC: { [string]: string } = {}

local function run(cwd: string, cmd: string, args: { string }): Result
	return fixture.exec(cwd, cmd, args, { env = NO_GC })
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function git(args: { string }): string
	return must(run(seed, "git", args), "git " .. table.concat(args, " "))
end

local function tr(args: { string }): Result
	return run(seed, "bash", { "scripts/tracker.sh", table.unpack(args) })
end

local function read(path: string): string
	return fs.readFile(`{seed}/{path}`)
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{seed}/{parent}`)
	end
	fs.writeFile(`{seed}/{path}`, text)
end

local legacyTip = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function ids(dir: string): string
	local names = fs.readDir(`{seed}/{dir}`)
	table.sort(names)
	return table.concat(names, " ")
end

-- A legacy-layout document: <ID>-<slug>.md with no slug in the frontmatter.
local function legacy(id: string, kind: string, title: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {title}\n---\n\n# body of {id}\n`
end

local function migrated(id: string, kind: string, title: string, slug: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {title}\nslug: {slug}\n---\n\n# body of {id}\n`
end

return t.spec("document naming", function(it)
	it("new issue writes <ID>.md with a slug in the frontmatter", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		clone.isolated(root, seed)
		git({ "config", "user.name", "e2e" })
		git({ "config", "user.email", "e2e@example.invalid" })
		git({ "checkout", "-q", "-B", "main" })
		git({ "remote", "remove", "origin" })
		-- overlay the working tree's tooling so uncommitted changes are what gets tested
		local listed = process.exec("git", {
			"ls-files",
			"-co",
			"--exclude-standard",
			"zn",
			"scripts",
			"z-nile",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
			".gitignore",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				write(path, fs.readFile(`{root}/{path}`))
			end
		end
		-- empty tracker
		-- c0114 override: every project root is emptied, and the counter moved to z-nile/next
		engine.empty(seed)

		local out = must(tr({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new issue")
		t.expect(out).toBe("tracker/issues/f0010/f0010.md")
		t.expect(fs.isFile(`{seed}/tracker/issues/f0010/f0010.md`)).toBe(true)
		t.expect(fs.isFile(`{seed}/tracker/issues/f0010/f0010-alpha.md`)).toBe(false)
		local doc = read("tracker/issues/f0010/f0010.md")
		t.expect(has(doc, "\nslug: alpha\n")).toBe(true)
		t.expect(has(doc, "\ntitle: Alpha\n")).toBe(true)
	end)

	it("new raft writes <ID>.md with a slug in the frontmatter", function()
		local out =
			must(tr({ "new", "raft", "feature", "demo", "f0010", "--project", "pickman" }), "new raft")
		t.expect(out).toBe("tracker/rafts/R0010/R0010.md")
		t.expect(fs.isFile(`{seed}/tracker/rafts/R0010/R0010-demo.md`)).toBe(false)
		local doc = read("tracker/rafts/R0010/R0010.md")
		t.expect(has(doc, "\nslug: demo\n")).toBe(true)
		t.expect(has(read("tracker/issues/f0010/f0010.md"), "\nraft: R0010\n")).toBe(true)
	end)

	it("new rejects a bad slug and creates nothing", function()
		local before = ids("tracker/issues")
		for _, bad in { "Bad Slug", "a/b", "UPPER", "9lead", "under_score", "" } do
			local r = tr({ "new", "issue", "f", bad, "--project", "pickman" })
			if r.ok then
				error(`new accepted the slug "{bad}"`)
			end
		end
		t.expect(ids("tracker/issues")).toBe(before)
	end)

	it("find, list, members and start work on the new layout", function()
		for _, doc in { "tracker/issues/f0010/f0010.md", "tracker/rafts/R0010/R0010.md" } do
			write(doc, (string.gsub(read(doc), "design: draft", "design: ready")))
		end
		git({ "add", "-A" })
		git({ "commit", "-qm", "fixture" })
		t.expect(must(tr({ "find", "f0010" }), "find")).toBe("tracker/issues/f0010")
		local list = must(tr({ "list" }), "list")
		t.expect(has(list, "f0010") and has(list, "Alpha")).toBe(true)
		t.expect(has(must(tr({ "members", "R0010" }), "members"), "tracker/issues/f0010")).toBe(true)
		must(tr({ "start", "R0010" }), "start")
		-- the branch name comes from the slug in the frontmatter
		t.expect(git({ "branch", "--show-current" })).toBe("R0010-demo")
		t.expect(fs.isFile(`{seed}/tracker/rafts/active/R0010/R0010.md`)).toBe(true)
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: start R0010 Demo")
	end)

	it("a document without a slug is an error naming the file", function()
		must(tr({ "new", "issue", "f", "beta", "--project", "pickman" }), "new beta")
		local path = "tracker/issues/f0020/f0020.md"
		local original = read(path)
		write(path, (string.gsub(original, "\nslug: beta\n", "\n")))
		local r = tr({ "find", "f0020" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "f0020.md") and has(r.stderr, "slug")).toBe(true)
		write(path, original)
		t.expect(tr({ "find", "f0020" }).ok).toBe(true)
	end)

	it("a legacy-named document is an error that points at migrate", function()
		write("tracker/issues/d0030/d0030-legacy.md", legacy("d0030", "defect", "Legacy"))
		local r = tr({ "find", "d0030" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "migrate") and has(r.stderr, "d0030-legacy.md")).toBe(true)
		-- a legacy name is refused even when the document already carries a slug
		write("tracker/issues/d0031/d0031-named.md", migrated("d0031", "defect", "Named", "named"))
		local named = tr({ "find", "d0031" })
		t.expect(named.ok).toBe(false)
		t.expect(has(named.stderr, "migrate") and has(named.stderr, "d0031-named.md")).toBe(true)
		fs.removeDir(`{seed}/tracker/issues/d0031`)
	end)

	it("migrate converts legacy documents in every state", function()
		write("tracker/issues/active/c0040/c0040-act.md", legacy("c0040", "chore", "Act"))
		write("tracker/issues/done/c0050/c0050-fin.md", legacy("c0050", "chore", "Fin"))
		write("tracker/rafts/R0020/R0020-rb.md", legacy("R0020", "chore", "Rb"))
		write("tracker/rafts/active/R0030/R0030-ra.md", legacy("R0030", "chore", "Ra"))
		write("tracker/rafts/done/R0040/R0040-rd.md", legacy("R0040", "chore", "Rd"))
		git({ "add", "-A" })
		git({ "commit", "-qm", "legacy documents" })
		legacyTip = git({ "rev-parse", "HEAD" })

		local r = tr({ "migrate" })
		local out = must(r, "migrate")
		local cases = {
			{ "tracker/issues/d0030/d0030", "d0030", "defect", "Legacy", "legacy" },
			{ "tracker/issues/active/c0040/c0040", "c0040", "chore", "Act", "act" },
			{ "tracker/issues/done/c0050/c0050", "c0050", "chore", "Fin", "fin" },
			{ "tracker/rafts/R0020/R0020", "R0020", "chore", "Rb", "rb" },
			{ "tracker/rafts/active/R0030/R0030", "R0030", "chore", "Ra", "ra" },
			{ "tracker/rafts/done/R0040/R0040", "R0040", "chore", "Rd", "rd" },
		}
		local renames = 0
		for line in string.gmatch(git({ "status", "--porcelain" }), "[^\n]+") do
			if string.find(line, "^R") then
				renames += 1
			end
		end
		t.expect(renames).toBe(#cases) -- renames, so history follows
		for _, c in cases do
			t.expect(fs.isFile(`{seed}/{c[1]}.md`)).toBe(true)
			t.expect(fs.isFile(`{seed}/{c[1]}-{c[5]}.md`)).toBe(false)
			t.expect(read(`{c[1]}.md`)).toBe(migrated(c[2], c[3], c[4], c[5]))
			t.expect(has(out, `{c[1]}-{c[5]}.md -> {c[1]}.md`)).toBe(true)
		end
		t.expect(tr({ "find", "d0030" }).ok).toBe(true)
		git({ "add", "-A" })
		git({ "commit", "-qm", "migrated" })
	end)

	it("migrate is idempotent and refuses an ambiguous directory", function()
		local again = tr({ "migrate" })
		t.expect(again.ok).toBe(true)
		t.expect(has(again.stdout, "->")).toBe(false)
		t.expect(git({ "status", "--porcelain" })).toBe("")

		write("tracker/issues/d0060/d0060.md", migrated("d0060", "defect", "Both", "both"))
		write("tracker/issues/d0060/d0060-x.md", legacy("d0060", "defect", "Both"))
		write("tracker/issues/d0070/d0070-ok.md", legacy("d0070", "defect", "Ok"))
		local r = tr({ "migrate" })
		t.expect(r.ok).toBe(false)
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr .. r.stdout, "d0060") and has(r.stderr .. r.stdout, "ambiguous")).toBe(true)
		t.expect(fs.isFile(`{seed}/tracker/issues/d0060/d0060-x.md`)).toBe(true) -- untouched
		t.expect(read("tracker/issues/d0060/d0060.md")).toBe(migrated("d0060", "defect", "Both", "both"))
		t.expect(fs.isFile(`{seed}/tracker/issues/d0070/d0070.md`)).toBe(true) -- the rest still converted
		fs.removeDir(`{seed}/tracker/issues/d0060`)
		git({ "add", "-A" })
		git({ "commit", "-qm", "more" })
	end)

	it("a branch that added a legacy document merges a migrated main, then migrate converts it", function()
		local branch = git({ "branch", "--show-current" })
		local migratedTip = git({ "rev-parse", "HEAD" })
		-- a branch cut before the migration adds one legacy document and edits another
		git({ "checkout", "-q", "-b", "inflight", legacyTip })
		write("tracker/issues/d0080/d0080-fresh.md", legacy("d0080", "defect", "Fresh"))
		write(
			"tracker/issues/d0030/d0030-legacy.md",
			legacy("d0030", "defect", "Legacy") .. "\nan edit on the branch\n"
		)
		git({ "add", "-A" })
		git({ "commit", "-qm", "work on a legacy branch" })
		local merge = run(seed, "git", { "merge", "-q", "--no-edit", migratedTip })
		t.expect(merge.ok).toBe(true)
		-- the edited document followed the rename; the new one is still legacy until migrate runs
		t.expect(has(read("tracker/issues/d0030/d0030.md"), "an edit on the branch")).toBe(true)
		t.expect(fs.isFile(`{seed}/tracker/issues/d0080/d0080-fresh.md`)).toBe(true)
		local r = tr({ "migrate" })
		local out = must(r, "migrate after merging")
		t.expect(has(out, "tracker/issues/d0080/d0080-fresh.md -> tracker/issues/d0080/d0080.md")).toBe(true)
		t.expect(select(2, string.gsub(out, "%->", ""))).toBe(1)
		t.expect(read("tracker/issues/d0080/d0080.md")).toBe(migrated("d0080", "defect", "Fresh", "fresh"))
		git({ "add", "-A" })
		git({ "commit", "-qm", "migrated on the branch" })
		git({ "checkout", "-q", branch })
	end)

	it("renumber renames the document and rewrites references", function()
		-- f0010 was moved to active/ when R0010 started
		write(
			"tracker/issues/active/f0010/f0010.md",
			read("tracker/issues/active/f0010/f0010.md") .. "\nsee f0020 too\n"
		)
		git({ "add", "-A" })
		git({ "commit", "-qm", "reference" })
		must(tr({ "renumber", "f0020", "f0025" }), "renumber")
		t.expect(fs.isDir(`{seed}/tracker/issues/f0020`)).toBe(false)
		t.expect(fs.isFile(`{seed}/tracker/issues/f0025/f0025.md`)).toBe(true)
		local doc = read("tracker/issues/f0025/f0025.md")
		t.expect(has(doc, "\nid: f0025\n") and has(doc, "\nslug: beta\n")).toBe(true)
		t.expect(has(read("tracker/issues/active/f0010/f0010.md"), "see f0025 too")).toBe(true)
		git({ "add", "-A" })
		git({ "commit", "-qm", "renumbered" })
	end)

	it("two branches creating the same id conflict on the document", function()
		local tip = git({ "rev-parse", "HEAD" })
		git({ "checkout", "-q", "-b", "collide-a" })
		local a = must(tr({ "new", "issue", "c", "first", "--project", "pickman" }), "new on a")
		git({ "add", "-A" })
		git({ "commit", "-qm", "a" })
		git({ "checkout", "-q", "-b", "collide-b", tip })
		local b = must(tr({ "new", "issue", "c", "second", "--project", "pickman" }), "new on b")
		git({ "add", "-A" })
		git({ "commit", "-qm", "b" })
		-- both branches picked the same number, so both wrote the same path
		local id = string.match(a, "/(c%d%d%d%d)%.md$")
		t.expect(id ~= nil).toBe(true)
		t.expect(b).toBe(a)
		local merge = run(seed, "git", { "merge", "collide-a" })
		t.expect(merge.ok).toBe(false)
		t.expect(has(merge.stdout, "CONFLICT (add/add)") and has(merge.stdout, `{id}.md`)).toBe(true)
		run(seed, "git", { "merge", "--abort" })
	end)
end)
