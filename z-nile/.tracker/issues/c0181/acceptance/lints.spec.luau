--!strict
-- c0181 AC4: a lint is a pure scan over the texts of a scope (`z-nile/lints/lib/lint.luau`), run over the repository
-- by `lune run z-nile/lints` in the gate's static stage. It names the lesson it enforces, flags a planted bad
-- fixture and passes a good one (self-test), honours `lint-ok <lesson id>: <reason>` marks and a path baseline,
-- and fails closed when its scope matches no file. The runner reads the tracked and untracked-but-not-ignored files of a
-- git work tree (a plain walk elsewhere), prints the lesson's body once after a violation, and skips z-nile/lints/
-- (the lints' own fixtures) unless a lint opts in with `scanLints`.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local lint = require("@znile/lints/lib/lint")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ID = "zz-test/no-todo"
local function def(extra: { [string]: any }?): lint.Def
	local d: any = {
		lesson = ID,
		under = { "z-nile/" },
		match = { "%.luau$" },
		skip = { "/.cache/", "/done/" },
		allow = {},
		scan = function(_path: string, text: string): { lint.Hit }
			local hits = {}
			local n = 0
			for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
				n += 1
				if string.find(line, "TODO", 1, true) then
					table.insert(hits, { line = n, message = "a TODO is left" })
				end
			end
			return hits
		end,
		bad = { ["z-nile/x.luau"] = "local a = 1\n-- TODO\n" },
		good = { ["z-nile/x.luau"] = "local a = 1\n" },
	}
	if extra then
		for k, v in extra do
			d[k] = v
		end
	end
	return d :: lint.Def
end

return t.spec("c0181 lints", function(it)
	it("reads only its scope and names the lesson, the file and the line", function()
		local files = {
			["z-nile/a.luau"] = "x\n-- TODO\n",
			["z-nile/a.md"] = "-- TODO\n", -- not the match
			["pickman/b.luau"] = "-- TODO\n", -- not under
			["z-nile/.cache/c.luau"] = "-- TODO\n", -- skipped
			["z-nile/.tracker/issues/done/c1/d.luau"] = "-- TODO\n", -- skipped
		}
		t.expect(lint.run(def(), files))
			.toEqual({ "lesson zz-test/no-todo: z-nile/a.luau:2: a TODO is left" })
		t.expect(lint.scanned(def(), files)).toBe(1)
	end)

	it(
		"a lint-ok mark with this lesson's id and a reason clears the line it is on or the line above",
		function()
			local function hits(text: string): number
				return #lint.run(def(), { ["z-nile/a.luau"] = text })
			end
			t.expect(hits("-- TODO -- lint-ok zz-test/no-todo: a quoted example\n")).toBe(0)
			t.expect(hits("-- lint-ok zz-test/no-todo: a quoted example\n-- TODO\n")).toBe(0)
			t.expect(hits("-- lint-ok zz-test/no-todo:\n-- TODO\n")).toBe(1) -- no reason
			t.expect(hits("-- lint-ok zz-test/other: a reason here\n-- TODO\n")).toBe(1) -- another lesson's
			t.expect(hits("-- lint-ok zz-test/no-todo: a reason here\n\n-- TODO\n")).toBe(1) -- two lines above
		end
	)

	it(
		"a baseline path is cleared with its reason; a baseline path that is not scanned is a problem",
		function()
			local files = { ["z-nile/a.luau"] = "-- TODO\n" }
			t.expect(lint.run(def({ allow = { ["z-nile/a.luau"] = "history, never edited" } }), files))
				.toEqual({})
			t.expect(#lint.baseline(def({ allow = { ["z-nile/a.luau"] = "history, never edited" } }), files))
				.toBe(0)
			local stale = lint.baseline(def({ allow = { ["z-nile/gone.luau"] = "history" } }), files)
			t.expect(#stale).toBe(1)
			t.expect(string.find(stale[1], "z-nile/gone.luau", 1, true) ~= nil).toBe(true)
			local bare = lint.baseline(def({ allow = { ["z-nile/a.luau"] = "" } }), files)
			t.expect(#bare).toBe(1)
		end
	)

	it(
		"an item's lint-allow.md clears its hits in any folder and under any id, and is a problem when stale",
		function()
			local allow = "- zz-test/no-todo: mid-prep, the check.sh is sequestered\n"
			local d = def({ under = { "z-nile/", "pickman/" } })
			local function hits(files: { [string]: string }): number
				return #lint.run(d, files)
			end
			local planted = "-- TODO\n"
			local base = "z-nile/.tracker/issues"
			-- the backlog folder, the active folder, and a renumbered id: the file moves with the folder, holds no item id
			for _, folder in { `{base}/c0083`, `{base}/active/c0083`, `{base}/c0100` } do
				t.expect(hits({ [`{folder}/x.luau`] = planted, [`{folder}/lint-allow.md`] = allow })).toBe(0)
			end
			-- another item's hit is not cleared, and neither is a hit when the file names another lesson
			t.expect(hits({
				["pickman/.tracker/issues/c0090/x.luau"] = planted,
				[`{base}/c0083/lint-allow.md`] = allow,
			})).toBe(1)
			local another = {
				[`{base}/c0083/x.luau`] = planted,
				[`{base}/c0083/lint-allow.md`] = "- zz-test/other: a reason\n",
			}
			t.expect(hits(another)).toBe(1)
			-- a line with no reason clears nothing and is a problem; so is a line whose lint no longer hits in the folder
			local bare =
				{ [`{base}/c0083/x.luau`] = planted, [`{base}/c0083/lint-allow.md`] = "- zz-test/no-todo:\n" }
			t.expect(hits(bare)).toBe(1)
			t.expect(#lint.baseline(d, bare)).toBe(1)
			local stale = { [`{base}/c0083/x.luau`] = "clean\n", [`{base}/c0083/lint-allow.md`] = allow }
			t.expect(#lint.baseline(d, stale)).toBe(1)
			-- a finished item's baseline is history: the same stale file is a problem in the backlog and none in done/ or retired/
			for _, folder in { `{base}/done/c0083`, "z-nile/.tracker/rafts/retired/R0030" } do
				local finished = { [`{folder}/x.luau`] = "clean\n", [`{folder}/lint-allow.md`] = allow }
				t.expect(#lint.baseline(d, finished)).toBe(0)
			end
			local live = { [`{base}/c0083/x.luau`] = planted, [`{base}/c0083/lint-allow.md`] = allow }
			t.expect(#lint.baseline(d, live)).toBe(0)

			-- reach: an item folder is <root>/{issues,rafts}[/active|/done|/retired]/<id>; its file clears that folder and below
			local deep =
				{ [`{base}/c0083/acceptance/x.spec.luau`] = planted, [`{base}/c0083/lint-allow.md`] = allow }
			t.expect(hits(deep)).toBe(0)
			-- a lint-allow.md anywhere else clears nothing and is a problem
			local stray = { ["z-nile/x.luau"] = planted, ["z-nile/lint-allow.md"] = allow }
			t.expect(hits(stray)).toBe(1)
			t.expect(#lint.baseline(d, stray)).toBe(1)
			-- a line naming a lesson that no lint enforces is reported (a typo, a lint removed)
			local typo = { [`{base}/c0083/lint-allow.md`] = "- zz-test/no-such: a reason\n" .. allow }
			local unknown = lint.unknownAllows(typo, { "zz-test/no-todo" })
			t.expect(#unknown).toBe(1)
			t.expect(string.find(unknown[1], "zz-test/no-such", 1, true) ~= nil).toBe(true)
		end
	)

	it("a lint reads nothing under z-nile/lints/ unless it opts in", function()
		local files = { ["z-nile/lints/own.luau"] = "-- TODO\n" }
		t.expect(lint.run(def(), files)).toEqual({})
		t.expect(#lint.run(def({ scanLints = true }), files)).toBe(1)
	end)

	it("the self-test fails a lint whose bad fixture is not flagged or whose good fixture is", function()
		t.expect(lint.selfTest(def())).toEqual({})
		local blind = lint.selfTest(def({ bad = { ["z-nile/x.luau"] = "local a = 1\n" } }))
		t.expect(#blind).toBe(1)
		t.expect(string.find(blind[1], ID, 1, true) ~= nil).toBe(true)
		local jumpy = lint.selfTest(def({ good = { ["z-nile/x.luau"] = "-- TODO\n" } }))
		t.expect(#jumpy).toBe(1)
		-- a fixture outside the lint's own scope proves nothing
		local outside = lint.selfTest(def({ bad = { ["elsewhere/x.luau"] = "-- TODO\n" } }))
		t.expect(#outside >= 1).toBe(true)
	end)

	it(
		"the runner scans a root, names the lesson once with its body, exits 1, and fails closed on an empty scope",
		function()
			local root = fixture.physical(".") or error("no home")
			local dir = `{root}/.cache/lints-e2e`
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			local function run(only: string, at: string?): process.ExecResult
				return process.exec("perl", {
					"-e",
					"alarm 60; exec @ARGV",
					"lune",
					"run",
					`{engine.TOP}/z-nile/lints`,
					"--",
					"--root",
					at or dir,
					"--only",
					only,
				}, { cwd = root })
			end
			local MARKERS = "zz-rules/grep-markers-before-merge-commit"
			local function out(r: process.ExecResult): string
				return r.stdout .. r.stderr
			end
			fs.writeDir(`{dir}/z-nile/skills/zz-rules/lessons`)
			engine.registry(dir)
			fs.writeFile(
				`{dir}/z-nile/skills/zz-rules/SKILL.md`,
				"---\nname: zz-rules\ndescription: x\n---\n"
			)
			fs.writeFile(
				`{dir}/z-nile/skills/zz-rules/lessons/grep-markers-before-merge-commit.md`,
				"---\ntitle: Markers\nwhen: build\ntags: [merge]\ncheck: Is a marker left?\nenforced_by: z-nile/lints/markers.luau\nenforced: full\nfrom: test\n---\nResolve every marker before you commit.\n"
			)
			fs.writeFile(
				`{dir}/z-nile/skills/zz-rules/planted.md`,
				"# x\n<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n"
			)
			local dirty = run(MARKERS)
			t.expect(dirty.code).toBe(1)
			t.expect(
				string.find(out(dirty), `lesson {MARKERS}: z-nile/skills/zz-rules/planted.md:2`, 1, true)
					~= nil
			)
				.toBe(true)
			-- three hits in the file, the lesson's body once
			local _, bodies = string.gsub(out(dirty), "Resolve every marker before you commit%.", "")
			t.expect(bodies).toBe(1)
			fs.writeFile(`{dir}/z-nile/skills/zz-rules/planted.md`, "# x\nclean\n")
			t.expect(run(MARKERS).code).toBe(0)
			fs.removeDir(`{dir}/z-nile`)
			fs.writeDir(dir)
			local empty = run(MARKERS)
			t.expect(empty.code).toBe(1)
			t.expect(string.find(out(empty), "scanned 0 files", 1, true) ~= nil).toBe(true)
			t.expect(run("zz-test/no-such-lesson").code).toBe(2)
			t.expect(run(MARKERS, `{dir}/nope`).code).toBe(2) -- a root that is not a folder
			fs.removeDir(dir)
		end
	)

	it("in a git work tree the runner reads tracked and untracked files but not ignored ones", function()
		local root = fixture.physical(".") or error("no home")
		local dir = `{root}/.cache/lints-git`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/z-nile`)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
		local planted = "# x\n<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n"
		fs.writeFile(`{dir}/.gitignore`, "ignored.md\n")
		fs.writeFile(`{dir}/z-nile/ignored.md`, planted)
		fs.writeFile(`{dir}/z-nile/untracked.md`, planted)
		-- tracked entries that are not readable files: a link to a folder, and a file deleted from the tree but still indexed
		fs.writeFile(`{dir}/z-nile/gone.md`, planted)
		t.expect(process.exec("ln", { "-s", ".", `{dir}/z-nile/linkdir` }).ok).toBe(true)
		fixture.git(dir, { "add", "z-nile/gone.md", "z-nile/linkdir" })
		fs.removeFile(`{dir}/z-nile/gone.md`)
		-- a binary file (a NUL byte first) that holds a marker-shaped line is not read
		fs.writeFile(`{dir}/z-nile/blob.bin`, "\0\n=======\n")
		fixture.git(dir, { "add", "z-nile/blob.bin" })
		local r = process.exec("perl", {
			"-e",
			"alarm 60; exec @ARGV",
			"lune",
			"run",
			`{engine.TOP}/z-nile/lints`,
			"--",
			"--root",
			dir,
			"--only",
			"zz-rules/grep-markers-before-merge-commit",
		}, { cwd = root })
		local text = r.stdout .. r.stderr
		t.expect(r.code).toBe(1)
		t.expect(string.find(text, "z-nile/untracked.md:2", 1, true) ~= nil).toBe(true)
		t.expect((string.find(text, "ignored.md", 1, true))).toBe(nil)
		t.expect((string.find(text, "gone.md", 1, true))).toBe(nil) -- skipped silently, not read, not a crash
		t.expect((string.find(text, "blob.bin", 1, true))).toBe(nil)
		t.expect((string.find(text, "linkdir", 1, true))).toBe(nil)
		fs.removeDir(dir)
	end)
end)
