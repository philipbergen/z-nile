--!strict
-- c0165 AC8 (learning and declared inputs): a full gate that fails a spec the selector missed finds the file it depends
-- on (a tracker file's too), records it in the db and prints the inputs.tsv line, and `affected --learned` then selects
-- the spec while a bare `affected` doesn't; learning runs in a clone with no remote; a declared folder entry selects its
-- spec for a file added to that folder later. Fixtures under .cache/c0165-gate-learn (gatefix.luau).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local gatefix = require("./gatefix")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local here = gatefix.trim(process.exec("pwd", { "-P" }).stdout)
local base = `{here}/.cache/c0165-gate-learn`
local has, count, ran, clearRan, write =
	gatefix.has, gatefix.count, gatefix.ran, gatefix.clearRan, gatefix.write

return t.spec("c0165 learning and declared inputs", function(it)
	it(
		"AC8: a seeded graph miss: the full gate fails, records and prints the dependency, and affected then selects it",
		function()
			local dir = gatefix.make(
				base,
				"miss",
				{ extra = { broken = { broken = true }, text = { reads = "data/x.txt", probe = true } } }
			)
			-- the change: data/x.txt, which text.spec reads as text (no require edge); broken.spec fails on the base too
			write(`{dir}/pickman/data/x.txt`, "bad\n")
			fixture.git(dir, { "commit", "-qam", "change x" })
			local before = process.exec(
				"lune",
				{ "run", "z-nile/affected", "--", "--project", "pickman", "pickman/data/x.txt" },
				{ cwd = dir, env = gatefix.env(dir) }
			)
			t.expect((string.gsub(before.stdout, "%s+$", ""))).toBe("")
			local refsBefore = fixture.git(dir, { "for-each-ref", "--format=%(refname) %(objectname)" })
			local ok, out = gatefix.gate(dir, { "--full" })
			t.expect(ok).toBe(false)
			-- learning's trials ran in a clone with no remote: the fixture's own refs are as they were
			t.expect(fixture.git(dir, { "for-each-ref", "--format=%(refname) %(objectname)" }))
				.toBe(refsBefore)
			-- seen from inside the trials: the clone has no remote, and the ref guard is told the real repository
			local common =
				gatefix.trim(fixture.git(dir, { "rev-parse", "--path-format=absolute", "--git-common-dir" }))
			t.expect(count(ran(dir), "remote:origin")).toBe(0)
			t.expect(count(ran(dir), `realgit:{common}`) >= 1).toBe(true)
			t.expect(has(out, "graph miss: pickman/tests/unit/text.spec.luau depends on pickman/data/x.txt"))
				.toBe(true)
			t.expect(has(out, "add to pickman/tests/inputs.tsv:")).toBe(true)
			t.expect(has(out, "tests/unit/text.spec.luau\tpickman/data/x.txt")).toBe(true)
			t.expect(has(out, "tests/unit/broken.spec.luau: fails on the base too: not a graph miss"))
				.toBe(true)
			t.expect(has(out, "graph miss: pickman/tests/unit/broken.spec.luau")).toBe(false)
			-- the edge is in the db now: affected selects text.spec for that file, in this worktree and every other
			local after = process.exec(
				"lune",
				{ "run", "z-nile/affected", "--", "--project", "pickman", "--learned", "pickman/data/x.txt" },
				{ cwd = dir, env = gatefix.env(dir) }
			)
			-- a bare call never reads the db: what reviewers paste and promoted specs run stays the committed answer
			local bare = process.exec(
				"lune",
				{ "run", "z-nile/affected", "--", "--project", "pickman", "pickman/data/x.txt" },
				{ cwd = dir, env = gatefix.env(dir) }
			)
			t.expect((string.gsub(bare.stdout, "%s+$", ""))).toBe("")
			t.expect((string.gsub(after.stdout, "%s+$", ""))).toBe("tests/unit/text.spec.luau")
			-- the gate wrote no committed file: inputs.tsv is untouched, the tree is as it was
			t.expect(fs.readFile(`{dir}/pickman/tests/inputs.tsv`)).toBe("# extra inputs per spec\n")
			t.expect((string.gsub(fixture.git(dir, { "status", "--porcelain" }), "%s+$", ""))).toBe("")
			-- the learning clone is gone
			for _, name in fs.readDir(`{dir}/.cache`) do
				t.expect(string.sub(name, 1, 6) ~= "learn-").toBe(true)
			end
		end
	)
	it(
		"AC8: a miss caused by a tracker file is learned too, and affected reads learned rows only when asked",
		function()
			local dir = gatefix.make(base, "trackmiss", {
				extra = { trk = { reads = ".tracker/issues/f0009/notes.md" } },
				setup = function(d: string)
					write(`{d}/pickman/.tracker/issues/f0009/notes.md`, "ok\n")
				end,
			})
			write(`{dir}/pickman/.tracker/issues/f0009/notes.md`, "bad\n")
			fixture.git(dir, { "commit", "-qam", "change notes" })
			local ok, out = gatefix.gate(dir, { "--full" })
			t.expect(ok).toBe(false)
			t.expect(
				has(
					out,
					"graph miss: pickman/tests/unit/trk.spec.luau depends on pickman/.tracker/issues/f0009/notes.md"
				)
			).toBe(true)
			local function affected(args: { string }): string
				local argv = { "run", "z-nile/affected", "--", "--project", "pickman" }
				for _, a in args do
					table.insert(argv, a)
				end
				local r = process.exec("lune", argv, { cwd = dir, env = gatefix.env(dir) })
				return (string.gsub(r.stdout, "%s+$", ""))
			end
			local file = "pickman/.tracker/issues/f0009/notes.md"
			t.expect(affected({ "--learned", file })).toBe("tests/unit/trk.spec.luau")
			t.expect(affected({ file })).toBe("")
		end
	)

	it(
		"AC8: a declared folder entry selects its spec for a file added there later, and changes its fingerprint",
		function()
			local dir = gatefix.make(base, "folder", {
				setup = function(d: string)
					-- a scanner: reads every file under data/ as text (no require edge), declared by a folder entry
					write(
						`{d}/pickman/tests/unit/scan.spec.luau`,
						"--!strict\n"
							.. "local fs = req"
							.. 'uire("@lune/fs")\n'
							.. "local process = req"
							.. 'uire("@lune/process")\n'
							.. "local t = req"
							.. 'uire("@tests/lib/t")\n'
							.. 'return t.spec("scan", function(it)\n'
							.. '\tit("runs", function()\n'
							.. `\t\tprocess.exec("sh", \{ "-c", 'echo scan >> "$1"', "_", "{d}/ran.log" })\n`
							.. '\t\tfor _, name in fs.readDir("data") do t.expect(fs.readFile("data/" .. name)).toBe("ok\\n") end\n'
							.. "\tend)\nend)\n"
					)
					write(
						`{d}/pickman/tests/inputs.tsv`,
						"# extra inputs per spec\ntests/unit/scan.spec.luau\tpickman/data/\n"
					)
				end,
			})
			local scan = { "--", "tests/unit/scan.spec.luau" }
			local ok1, _ = gatefix.specs(dir, scan)
			t.expect(ok1).toBe(true)
			local ok2, out2 = gatefix.specs(dir, scan)
			t.expect(ok2).toBe(true)
			t.expect(has(out2, "reused tests/unit/scan.spec.luau")).toBe(true)
			-- a new file under the declared folder: the bare selector picks the scanner, and its pass is not reused
			write(`{dir}/pickman/data/new.txt`, "bad\n")
			t.expect(gatefix.affected(dir, { "pickman/data/new.txt" })).toBe("tests/unit/scan.spec.luau")
			local ok3, _ = gatefix.specs(dir, scan)
			t.expect(ok3).toBe(false)
			t.expect(count(ran(dir), "scan")).toBe(2)
		end
	)

	it(
		"AC8: a * entry (always run): any change selects the spec, a tracker file included, and its pass is never reused",
		function()
			local dir = gatefix.make(base, "always", {
				setup = function(d: string)
					write(
						`{d}/pickman/tests/inputs.tsv`,
						"# extra inputs per spec\ntests/unit/b.spec.luau\t*\n"
					)
				end,
			})
			t.expect(gatefix.affected(dir, { "pickman/.tracker/issues/f0009/f0009.md" }))
				.toBe("tests/unit/b.spec.luau")
			t.expect(gatefix.affected(dir, { "AGENTS.md" })).toBe("tests/unit/b.spec.luau")
			local one = { "--", "tests/unit/b.spec.luau" }
			local ok1, _ = gatefix.specs(dir, one)
			local ok2, out2 = gatefix.specs(dir, one)
			t.expect(ok1 and ok2).toBe(true)
			t.expect(count(ran(dir), "b")).toBe(2)
			t.expect(has(out2, "reused tests/unit/b.spec.luau")).toBe(false)
		end
	)
end)
