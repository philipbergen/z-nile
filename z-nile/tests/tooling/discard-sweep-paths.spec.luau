--!strict
-- c0277 review-004 F1: the sweep removes a discarded worktree only when every uncommitted path is explicitly recovered.
-- git quotes a path with a space or a non-ASCII byte and prints a rename as `old -> new` unless it is read with -z; a
-- staged change can differ from the work-tree copy (MM); a detached head can hold commits the renamed branch does not.
-- All of them are kept and listed, and a clean worktree still goes. Time is ZN_NOW. Fixture under .cache/c0277-paths.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local T0 = os.time()
local LATE = T0 + 3 * heartbeat.STALE
local P = "pickman/.tracker/issues"
local GH =
	'#!/bin/sh\nif [ "$1" = pr ] && [ "$2" = list ]; then\n  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"\n  exit 0\nfi\nexit 0\n'

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
	if now then
		env.ZN_NOW = tostring(now)
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function trim(s: string): string
	return (string.gsub(s, "%s+$", ""))
end
local function dir(name: string): string
	return `{h.f.main}/.worktree/{name}`
end
local function gone(name: string): string -- the renamed directory of a discarded worktree
	return dir(`{name}-discarded-1`)
end

local KINDS: { { name: string, id: string, extra: (string) -> () } } = {
	{ name = "prep-clean", id = "c0010", extra = function(_) end },
	{
		name = "prep-space",
		id = "c0020",
		extra = function(wt)
			fs.writeFile(`{wt}/pickman/my notes.txt`, "kept\n")
		end,
	},
	{
		name = "prep-accent",
		id = "c0030",
		extra = function(wt)
			fs.writeFile(`{wt}/pickman/\u{fc}n\u{ef}.txt`, "kept\n")
		end,
	},
	{
		name = "prep-dir",
		id = "c0040",
		extra = function(wt)
			fs.writeDir(`{wt}/pickman/my dir`)
			fs.writeFile(`{wt}/pickman/my dir/f.txt`, "kept\n")
		end,
	},
	{
		name = "prep-rename",
		id = "c0050",
		extra = function(wt)
			fs.writeFile(`{wt}/pickman/doc.txt`, "one\n")
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "doc" })
			fixture.git(wt, { "push", "-q", "origin", "HEAD:refs/heads/prep-rename" })
			fixture.git(wt, { "mv", "pickman/doc.txt", "pickman/doc2.txt" })
			fs.writeFile(`{wt}/pickman/doc2.txt`, "one\ntwo\n")
			fixture.git(wt, { "add", "-A" })
		end,
	},
	{
		name = "prep-staged",
		id = "c0060",
		extra = function(wt)
			-- the work tree equals main; the staged version does not
			local f = `{wt}/pickman/.tracker/architecture.md`
			local original = fs.readFile(f)
			fs.writeFile(f, "staged only\n")
			fixture.git(wt, { "add", f })
			fs.writeFile(f, original)
		end,
	},
	{
		name = "prep-detached",
		id = "c0070",
		extra = function(_) end,
	},
}

-- an old worker in `name` that claimed `id`, pushed its branch, and then left `extra` behind
local function worker(name: string, id: string, extra: (string) -> ())
	local wt = trim(must(zn(h.f.main, { "worktree", name }), "worktree"))
	must(zn(wt, { "status", id, "preparing" }, T0), `claim {id}`)
	fs.writeFile(`{wt}/pickman/{name}.txt`, "pushed\n")
	fixture.git(wt, { "add", "-A" })
	fixture.git(wt, { "commit", "-q", "-m", `{name} pushed` })
	fixture.git(wt, { "push", "-q", "origin", `HEAD:refs/heads/{name}` })
	extra(wt)
end

return t.spec("c0277 review-004 F1: the sweep keeps every path it cannot prove recovered", function(it)
	it("reads git status -z: quoted paths, renames and conflicts", function()
		local e =
			heartbeat.statusEntries("?? pickman/my notes.txt\0R  new name.txt\0old name.txt\0 M a.txt\0")
		t.expect(#e).toBe(3)
		t.expect(e[1].path).toBe("pickman/my notes.txt")
		t.expect(e[2].xy).toBe("R ")
		t.expect(e[2].path).toBe("new name.txt")
		t.expect(e[2].from).toBe("old name.txt")
		t.expect(e[3].from == nil).toBe(true)
		t.expect(heartbeat.statusLabel(e[2])).toBe("old name.txt -> new name.txt")
		t.expect(#heartbeat.statusEntries("")).toBe(0)
	end)

	it("sets up one old worker per kind of unrecovered work, all taken over and then given back", function()
		local files: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
		}
		for _, k in KINDS do
			files[`{P}/{k.id}/{k.id}.md`] = trackerfix.stub(k.id, k.id, "new-a-b-c")
		end
		h = fakecli.new("c0277-paths", files)
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		for _, k in KINDS do
			worker(k.name, k.id, k.extra)
		end
		for _, k in KINDS do
			must(zn(h.f.main, { "worktree", k.name, "--takeover" }, LATE), `takeover {k.name}`)
		end
		-- the old process wakes up in its renamed folder and commits on a detached head
		local det = gone("prep-detached")
		fixture.git(det, { "checkout", "-q", "--detach" })
		fs.writeFile(`{det}/pickman/late.txt`, "late\n")
		fixture.git(det, { "add", "-A" })
		fixture.git(det, { "commit", "-q", "-m", "late commit" })
		for _, k in KINDS do
			must(zn(dir(`{k.name}-1`), { "status", k.id, "new" }, LATE), `give back {k.id}`)
		end
	end)

	it("the sweep removes the clean one and keeps and lists every other", function()
		local synced = zn(h.f.main, { "sync" }, LATE)
		must(synced, "sync")
		t.expect(fs.isDir(gone("prep-clean"))).toBe(false)
		t.expect(has(synced.stderr, `removed discarded worktree {gone("prep-clean")}`)).toBe(true)
		t.expect(fs.isFile(`{gone("prep-space")}/pickman/my notes.txt`)).toBe(true)
		t.expect(fs.isFile(`{gone("prep-accent")}/pickman/\u{fc}n\u{ef}.txt`)).toBe(true)
		t.expect(fs.isFile(`{gone("prep-dir")}/pickman/my dir/f.txt`)).toBe(true)
		t.expect(fs.isFile(`{gone("prep-rename")}/pickman/doc2.txt`)).toBe(true)
		t.expect(fs.isDir(gone("prep-staged"))).toBe(true)
		t.expect(fs.isFile(`{gone("prep-detached")}/pickman/late.txt`)).toBe(true)
		for _, k in KINDS do
			if k.name ~= "prep-clean" then
				t.expect(has(synced.stderr, `kept discarded worktree {gone(k.name)}`)).toBe(true)
			end
		end
	end)
end)
