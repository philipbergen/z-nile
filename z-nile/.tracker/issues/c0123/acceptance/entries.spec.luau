--!strict
-- c0123 AC5: the places that start a shell are privileged and clean, found by a scan rather than a list. Every script a
-- caller can start (a tracked file with a shebang, the sourced libraries and the item check.sh files aside) starts with
-- `#!/bin/bash -p`; the git hooks (the guard's, and the repository's own, c0189) with `#!/bin/sh -p`; and the Lune launchers (the engine, z-nile/lib, the runner and
-- its fence) start a shell only as an absolute `/bin/bash` or `/bin/sh` with `-p` first. The scans are pure functions
-- over text, planted-proof; the real tree is then run through them. Read-only: git grep in this checkout.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- Scripts that are sourced, never started (they keep the shebang that marks them as bash), and the item check.sh files,
-- which the engine starts with `bash -p`.
local SOURCED = { ["z-nile/lib/ac.sh"] = true, ["z-nile/lib/par.sh"] = true, ["scripts/lib/ac.sh"] = true }
local function exempt(path: string): boolean
	if SOURCED[path] then
		return true
	end
	if string.find(path, "/%.tracker/") or string.find(path, "^z%-nile/templates/") then
		return true -- an item's or a template's check.sh
	end
	return string.find(path, "^[^/]+/tests/acceptance/") ~= nil
end

-- `path:1:#!...` lines (git grep output) -> the paths whose shebang is not the privileged one
local function badShebangs(lines: { string }): { string }
	local bad: { string } = {}
	for _, line in lines do
		local path, shebang = string.match(line, "^([^:]+):1:(#!.*)$")
		if path and shebang and not exempt(path) then
			-- the git hooks (the guard's, and the repository's own reference-transaction hook, c0189) and the mktemp shim
			-- (c0194) are `sh` scripts: no prologue, `-p` alone
			local hook = string.find(path, "^z%-nile/lib/git%-hooks/") ~= nil
				or string.find(path, "^z%-nile/lib/repo%-hooks/") ~= nil
				or path == "z-nile/bin/mktemp"
			local want = if hook then "#!/bin/sh -p" else "#!/bin/bash -p"
			if
				(string.find(shebang, "sh", 1, true) or string.find(shebang, "bash", 1, true))
				and shebang ~= want
			then
				table.insert(bad, `{path}: {shebang}`)
			end
		end
	end
	return bad
end

-- Lune source text -> the shell starts that are not `/bin/bash -p` / `/bin/sh -p`
local function count(text: string, pattern: string): number
	local n = 0
	for _ in string.gmatch(text, pattern) do
		n += 1
	end
	return n
end

local function badSpawns(text: string): { string }
	local bad: { string } = {}
	for _, name in { "bash", "sh" } do
		local bare = count(text, '"' .. name .. '",%s*{')
		local absolute = count(text, '"/bin/' .. name .. '",%s*{')
		local privileged = count(text, '"/bin/' .. name .. '",%s*{%s*"%-p"')
		if bare > 0 then
			table.insert(bad, `{bare} start(s) of "{name}" by name`)
		end
		if absolute ~= privileged then
			table.insert(bad, `{absolute - privileged} start(s) of /bin/{name} without -p first`)
		end
	end
	return bad
end

local LAUNCHERS = {
	"z-nile/tests/run.luau",
	"z-nile/tests/lib/fence.luau",
	"z-nile/engine/main.luau",
	"z-nile/lib/sh.luau",
	"z-nile/lib/tmp.luau",
}

return t.spec("c0123 the places that start a shell are privileged", function(it)
	it(
		"the shebang scan flags a script that starts with a plain bash, and passes the privileged forms",
		function()
			t.expect(badShebangs({ "scripts/new.sh:1:#!/usr/bin/env bash" })).toEqual({
				"scripts/new.sh: #!/usr/bin/env bash",
			})
			t.expect(badShebangs({ "z-nile/lib/git-hooks/pre-commit:1:#!/bin/sh" })).toEqual({
				"z-nile/lib/git-hooks/pre-commit: #!/bin/sh",
			})
			t.expect(badShebangs({ "z-nile/bin/mktemp:1:#!/bin/sh" }))
				.toEqual({ "z-nile/bin/mktemp: #!/bin/sh" })
			t.expect(badShebangs({ "z-nile/bin/mktemp:1:#!/bin/sh -p" })).toEqual({})
			-- the repository's own hook (c0189): a plain sh imports an exported function as `sh` does for any hook
			t.expect(badShebangs({ "z-nile/lib/repo-hooks/reference-transaction:1:#!/bin/sh" })).toEqual({
				"z-nile/lib/repo-hooks/reference-transaction: #!/bin/sh",
			})
			t.expect(badShebangs({ "z-nile/lib/repo-hooks/reference-transaction:1:#!/bin/sh -p" }))
				.toEqual({})
			t.expect(badShebangs({ "z-nile/lib/repo-hooks/reference-transaction:1:#!/bin/bash -p" }))
				.toEqual({
					"z-nile/lib/repo-hooks/reference-transaction: #!/bin/bash -p",
				})
			t.expect(badShebangs({ "z-nile/lib/git-hooks/pre-commit:1:#!/bin/bash -p" })).toEqual({
				"z-nile/lib/git-hooks/pre-commit: #!/bin/bash -p",
			})
			t.expect(badShebangs({
				"zn:1:#!/bin/bash -p",
				"z-nile/lib/git-hooks/pre-commit:1:#!/bin/sh -p",
				"z-nile/lib/ac.sh:1:#!/usr/bin/env bash",
				"z-nile/.tracker/issues/c0123/check.sh:1:#!/usr/bin/env bash",
				"z-nile/lib/replace-file.pl:1:#!/usr/bin/perl",
			})).toEqual({})
		end
	)

	it("every tracked script a caller can start is privileged", function()
		local r = process.exec(
			"git",
			{ "grep", "-nI", "-e", "^#!", "--", ".", ":(exclude)*.md" },
			{ cwd = root }
		)
		t.expect(r.ok).toBe(true)
		local lines: { string } = {}
		for line in string.gmatch(r.stdout, "[^\n]+") do
			table.insert(lines, line)
		end
		t.expect(#lines > 20).toBe(true) -- the scan reads something (git grep prints `path:line:text`)
		local bad = badShebangs(lines)
		if #bad > 0 then
			error("scripts that start without bash -p / sh -p:\n  " .. table.concat(bad, "\n  "))
		end
	end)

	it(
		"the spawn scan flags a shell started by name or without -p, and passes the privileged form",
		function()
			t.expect(#badSpawns('process.exec("bash", { "-c", x })')).toBe(1)
			t.expect(#badSpawns('sh.stream("sh", { "-c", x })')).toBe(1)
			t.expect(#badSpawns('sh.stream("/bin/bash", { "-c", x })')).toBe(1)
			t.expect(#badSpawns('sh.run("/bin/sh", {\n\t"-c", x })')).toBe(1)
			t.expect(
				badSpawns(
					'sh.stream("/bin/bash", { "-p", "-c", x })\nprocess.exec("/bin/sh", {\n\t"-p", "-c", y })'
				)
			).toEqual({})
		end
	)

	it("every Lune launcher starts its shells as /bin/bash -p or /bin/sh -p", function()
		for _, rel in LAUNCHERS do
			local bad = badSpawns(fs.readFile(`{root}/{rel}`))
			if #bad > 0 then
				error(`{rel}: {table.concat(bad, "; ")}`)
			end
		end
		-- the one spawn built from parts: the jail's shell line starts with -p
		local fence = fs.readFile(`{root}/z-nile/tests/lib/fence.luau`)
		t.expect(string.find(fence, 'local argv = {%s*"%-p"') ~= nil).toBe(true)
		t.expect(has(fence, 'local command = "/bin/bash"')).toBe(true)
	end)
end)
