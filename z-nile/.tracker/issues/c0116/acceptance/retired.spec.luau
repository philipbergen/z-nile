--!strict
-- c0116 AC2 (review 002 F2): a raft `recombine` retired keeps its folder in `<root>/rafts/retired/<R-id>` with
-- `retired: <keeper>`. On a copy of this checkout's working tree holding one (its lowest backlog z-nile raft, retired the way
-- recombine does it), the readers that walk rafts stay green: the promoted c0114 classification and c0043 rounds specs
-- (overridden for retired/), `lessons --check` and `audit`. `engine.empty`, which fixtures use to start from no items,
-- clears retired/ too. Fixtures under .cache/c0116-retired: the copy is a fresh repository holding this checkout's working tree.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local store = require("@znile/engine/store")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- the fixture lives in this home's .cache (z-nile/.cache since c0120), the only place a spec may write
local base = `{fixture.physical(".") :: string}/.cache/c0116-retired`
local work = `{base}/work`
local ACC = "tests/" .. "acceptance/"

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end

local ID = { "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid" }

-- A repository of its own at `dest` holding `src`'s working tree as it is, committed or not, in one commit. A fresh
-- `git init`, never a clone of HEAD with the working tree copied over it: a file moved or deleted and not yet
-- committed (as `./zn done` leaves the tree while its gate runs) would otherwise be there twice (found by a simulated
-- `done` of c0116 itself).
local function copyTree(src: string, dest: string)
	fs.writeDir(dest)
	must(process.exec("git", { "init", "-q" }, { cwd = dest }), "git init")
	local listed = must(
		process.exec("git", { "ls-files", "-co", "--exclude-standard", "-z" }, { cwd = src }),
		"ls-files"
	)
	for _, path in string.split(listed, "\0") do
		local inCache = string.find("/" .. path, "/.cache/", 1, true) ~= nil
		if path ~= "" and not inCache and fs.isFile(`{src}/{path}`) then
			local parent = string.match(path, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{dest}/{parent}`)
			end
			must(process.exec("cp", { "-p", `{src}/{path}`, `{dest}/{path}` }), `copy {path}`)
		end
	end
	must(fixture.exec(dest, "git", { "add", "-A" }), "git add")
	local commit = table.clone(ID)
	for _, a in { "commit", "-qm", "the source's working tree" } do
		table.insert(commit, a)
	end
	must(fixture.exec(dest, "git", commit), "git commit")
end

return t.spec(
	"c0116 a retired raft keeps its folder, and every reader that walks rafts stays green",
	function(it)
		it("engine.empty clears retired/ with the lifecycle folders", function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			local dir = `{base}/empty`
			fs.writeDir(`{dir}/z-nile/.tracker/rafts/retired/R0999`)
			fs.writeFile(
				`{dir}/z-nile/.tracker/rafts/retired/R0999/R0999.md`,
				"---\nid: R0999\nretired: R0998\n---\n"
			)
			fs.writeDir(`{dir}/z-nile/.tracker/rafts/R0998`)
			fs.writeFile(`{dir}/z-nile/.tracker/rafts/R0998/R0998.md`, "---\nid: R0998\n---\n")
			engine.empty(dir)
			t.expect(fs.isDir(`{dir}/z-nile/.tracker/rafts/R0998`)).toBe(false)
			t.expect(fs.isDir(`{dir}/z-nile/.tracker/rafts/retired/R0999`)).toBe(false)
		end)

		it("copies a moved, uncommitted item once: at its new place, never also at its old", function()
			local src = `{base}/moved-src`
			fs.writeDir(`{src}/z-nile/.tracker/issues/c0001`)
			must(process.exec("git", { "init", "-q" }, { cwd = src }), "git init")
			fs.writeFile(`{src}/z-nile/.tracker/issues/c0001/c0001.md`, "---\nid: c0001\n---\n")
			fs.writeFile(`{src}/kept.txt`, "kept\n")
			fs.writeFile(`{src}/gone.txt`, "gone\n")
			must(fixture.exec(src, "git", { "add", "-A" }), "git add")
			local commit = table.clone(ID)
			for _, a in { "commit", "-qm", "seed" } do
				table.insert(commit, a)
			end
			must(fixture.exec(src, "git", commit), "git commit")
			-- as `done` leaves it while its gate runs: moved and deleted, nothing committed
			fs.writeDir(`{src}/z-nile/.tracker/issues/done`)
			must(
				fixture.exec(
					src,
					"git",
					{ "mv", "z-nile/.tracker/issues/c0001", "z-nile/.tracker/issues/done/c0001" }
				),
				"git mv"
			)
			must(fixture.exec(src, "git", { "rm", "-q", "gone.txt" }), "git rm")
			fs.writeFile(`{src}/new.txt`, "new\n")
			local dest = `{base}/moved-dest`
			copyTree(src, dest)
			t.expect(fs.isFile(`{dest}/z-nile/.tracker/issues/done/c0001/c0001.md`)).toBe(true)
			t.expect(fs.isDir(`{dest}/z-nile/.tracker/issues/c0001`)).toBe(false)
			t.expect(fs.isFile(`{dest}/gone.txt`)).toBe(false)
			t.expect(fs.isFile(`{dest}/kept.txt`)).toBe(true)
			t.expect(fs.isFile(`{dest}/new.txt`)).toBe(true)
			t.expect(fixture.git(dest, { "status", "--porcelain" })).toBe("")
		end)

		it(
			"on a clone holding a retired raft, the classification, rounds, lessons and audit checks pass",
			function()
				copyTree(root, work)
				-- retire the lowest backlog raft of z-nile's root the way recombine does: the whole folder, retired: <keeper>
				local rafts = `{work}/z-nile/.tracker/rafts`
				-- prefer a raft no issue names (what recombine retires); else the lowest
				local named: { [string]: boolean } = {}
				for _, state in { "", "active/", "done/" } do
					local dir = `{work}/z-nile/.tracker/issues/{state}`
					local names: { string } = if fs.isDir(dir) then fs.readDir(dir) else {}
					for _, name in names do
						local d = `{dir}{name}/{name}.md`
						if fs.isDir(`{dir}{name}`) and fs.isFile(d) then
							local r = string.match(fs.readFile(d), "\nraft: (R%d+)\n")
							if r then
								named[r] = true
							end
						end
					end
				end
				local pick: string? = nil
				local free = false
				local candidates: { string } = fs.readDir(rafts)
				table.sort(candidates)
				for _, name in candidates do
					if string.match(name, "^R%d%d%d%d$") then
						if not pick or (not free and not named[name]) then
							pick, free = name, not named[name]
						end
					end
				end
				assert(pick, "the clone has no backlog z-nile raft to retire")
				local id = pick :: string
				local doc = `{rafts}/{id}/{id}.md`
				local text = store.withFront(fs.readFile(doc), "retired", "R0001") :: string
				fs.writeFile(doc, text)
				fs.writeDir(`{rafts}/retired`)
				must(
					fixture.exec(
						work,
						"git",
						{ "mv", `z-nile/.tracker/rafts/{id}`, `z-nile/.tracker/rafts/retired/{id}` }
					),
					"git mv"
				)
				local specs = must(
					-- z-nile's specs run from its home, z-nile/ (c0120)
					process.exec("lune", {
						"run",
						"tests/run",
						"--",
						`{ACC}c0114/classified.spec.luau`,
						`{ACC}c0043/rounds.spec.luau`,
					}, { cwd = `{work}/z-nile` }),
					"the classification and rounds specs"
				)
				t.expect(string.find(specs, " 0 failed", 1, true) ~= nil).toBe(true)
				t.expect(
					must(
						fixture.exec(work, "bash", { "scripts/tracker.sh", "lessons", "--check" }),
						"lessons --check"
					)
				)
				local audit = fixture.exec(work, "bash", { "scripts/tracker.sh", "audit" })
				t.expect(string.find(audit.stdout, "audit: 0 errors", 1, true) ~= nil).toBe(true)
				t.expect(
					(string.find(audit.stdout, `orphan-raft z-nile/.tracker/rafts/retired/{id}`, 1, true))
				)
					.toBe(nil)
			end
		)
	end
)
