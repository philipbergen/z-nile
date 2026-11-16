--!strict
-- c0195 AC7: the fence's git fails closed. The fence refuses (before it changes anything) where it would set the hooks
-- but their folder has no fence's git, and where the PATH has no git besides the fence's own; the fence's git refuses
-- to run when it does not know the real git (unset, missing, or itself, which would start itself forever).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local h = require("./harness")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local base = h.fresh("closed")

return t.spec("c0195 the fence's git fails closed", function(it)
	it("AC7: the fence refuses when the hooks' folder has no fence's git", function()
		local g = h.GITS[1]
		h.makeRepo(`{base}/a`, g)
		-- a copy of the guards whose hook folder lacks the fence's git, with no hook folder inherited
		fs.writeDir(`{base}/kit/z-nile/lib`)
		t.expect(process.exec("cp", { h.FENCE, `{base}/kit/z-nile/lib/fence.sh` }).ok).toBe(true)
		t.expect(process.exec("cp", { "-R", h.HOOKS, `{base}/kit/z-nile/lib/git-hooks` }).ok).toBe(true)
		fs.removeFile(`{base}/kit/z-nile/lib/git-hooks/git`)
		local r = fixture.exec(`{base}/a`, "bash", {
			"-c",
			'. "$1" || exit 90; pickman_fence "$2" && echo FENCED',
			"_",
			`{base}/kit/z-nile/lib/fence.sh`,
			`{base}/a`,
		}, { env = { PICKMAN_FENCE_HOOKS = "", PICKMAN_TEST_JAIL = "" } })
		t.expect(r.ok).toBe(false)
		t.expect(h.has(r.stdout, "FENCED")).toBe(false)
		t.expect(h.has(r.stderr, "no ref guard")).toBe(true)
	end)

	it("AC7: the fence refuses when the PATH has no git besides the fence's own", function()
		local g = h.GITS[1]
		h.makeRepo(`{base}/b`, g)
		-- the hooks' folder and a folder holding perl alone (what the guards may need to read their own files)
		fs.writeDir(`{base}/perl-only`)
		local perl = h.trim(process.exec("sh", { "-c", "command -v perl" }).stdout)
		t.expect(process.exec("ln", { "-s", perl, `{base}/perl-only/perl` }).ok).toBe(true)
		local r = fixture.exec(`{base}/b`, "bash", {
			"-c",
			'. "$1" || exit 90; PATH="$2:$3"; pickman_fence "$4" && echo FENCED',
			"_",
			h.FENCE,
			h.HOOKS,
			`{base}/perl-only`,
			`{base}/b`,
		})
		t.expect(r.ok).toBe(false)
		t.expect(h.has(r.stdout, "FENCED")).toBe(false)
		t.expect(h.has(r.stderr, "no git on the PATH besides the fence's own")).toBe(true)
	end)

	it(
		"AC7: the fence's git refuses when it does not know the real git, or would only start itself",
		function()
			local g = h.GITS[1]
			h.makeRepo(`{base}/c`, g)
			for _, value in { "", `{h.HOOKS}/git`, `{base}/nonexistent` } do
				-- under an alarm, so a git that starts itself forever ends (an alarm outlives exec) and fails the case
				local r = fixture.exec(
					`{base}/c`,
					"perl",
					{ "-e", "alarm 20; exec @ARGV", `{h.HOOKS}/git`, "rev-parse", "HEAD" },
					{ env = { PICKMAN_FENCE_GIT = value, PICKMAN_FENCE_GIT_BUILTINS = "rev-parse" } } -- a builtin, so a start-itself loops by exec in one process (the alarm ends it), never by fork
				)
				t.expect(r.ok).toBe(false)
				t.expect(h.has(r.stderr, "the real git is not known")).toBe(true)
			end
		end
	)

	it("AC7: the fence's git refuses a copy it can't place, and a second start of itself", function()
		local g = h.GITS[1]
		h.makeRepo(`{base}/d`, g)
		-- a real git that fails the question "which repository?" (as a fork failure or an old git would) and records any other call
		local stub = `{base}/stub-git`
		fs.writeFile(
			stub,
			`#!/bin/sh\ncase "$*" in *rev-parse*) exit 128 ;; esac\necho called >> {base}/marker\nexit 0\n`
		)
		t.expect(process.exec("chmod", { "+x", stub }).ok).toBe(true)
		local env = {
			PICKMAN_FENCE_GIT = stub,
			PICKMAN_FENCE_GIT_BUILTINS = "branch",
			PICKMAN_FENCE_REAL_GIT = `{base}/d/.git`,
		}
		local r = fixture.exec(`{base}/d`, `{h.HOOKS}/git`, { "branch", "-c", "main", "evil" }, { env = env })
		t.expect(r.ok).toBe(false)
		t.expect(h.has(r.stderr, "could not tell which repository")).toBe(true)
		t.expect(fs.isFile(`{base}/marker`)).toBe(false)
		-- an option the fence's git does not know before the command is no harmless flag
		local r2 = fixture.exec(
			`{base}/d`,
			`{h.HOOKS}/git`,
			{ "--unknown-flag", "x", "status" },
			{ env = env }
		)
		t.expect(r2.ok).toBe(false)
		t.expect(fs.isFile(`{base}/marker`)).toBe(false)
		-- a second start while the first asks its question
		env.PICKMAN_FENCE_DEPTH = "1"
		local r3 = fixture.exec(`{base}/d`, `{h.HOOKS}/git`, { "status" }, { env = env })
		t.expect(r3.ok).toBe(false)
		t.expect(h.has(r3.stderr, "started by its own question")).toBe(true)
	end)

	it("cleans up", function()
		h.remove(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
