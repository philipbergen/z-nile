--!strict
-- c0075 AC6: the Linux jail is wired in everywhere a Linux run starts: CI provisions it before the gate, the fence
-- sets no ref hooks under it (the kernel already denies the writes, as under macOS's jail), and the documents say what
-- is true now. Static reads, plus one run of the fence's shell half in a fixture.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0075-wiring`

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function stepIndex(steps: any, run: string): number?
	for i, step in steps do
		if type(step.run) == "string" and (string.gsub(step.run, "%s+$", "")) == run then
			return i
		end
	end
	return nil
end

-- the hooks path the fence leaves in git's environment for a given jail name, in a fixture checkout
local function hooksPath(jail: string): string
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	local co = `{base}/co`
	fs.writeDir(co)
	assert(process.exec("git", { "init", "-q", co }).ok, "could not make the fixture checkout")
	local r = process.exec("bash", {
		"-c",
		'. "$1/scripts/lib/fence.sh" && pickman_fence "$2" specs "$3" && cd "$2" && git config --get core.hooksPath; true',
		"_",
		root,
		co,
		jail,
	}, { cwd = root })
	return (string.gsub(r.stdout, "%s+$", ""))
end

return t.spec("c0075 the Linux jail is wired in", function(it)
	it("CI makes bubblewrap usable before the gate runs", function()
		local wf = serde.decode("yaml", fs.readFile(".github/workflows/check.yml"))
		local steps = wf.jobs.gate.steps
		local jailAt = stepIndex(steps, "scripts/linux-jail.sh --apply-sysctl")
		local setupAt = stepIndex(steps, "scripts/setup.sh")
		t.expect(jailAt ~= nil).toBe(true)
		t.expect(setupAt ~= nil).toBe(true)
		t.expect((jailAt :: number) < (setupAt :: number)).toBe(true)
		local step = steps[jailAt :: number]
		t.expect(step["if"]).toBe(nil) -- every gate run, pull request or dispatch
		t.expect(step["continue-on-error"] == nil or step["continue-on-error"] == false).toBe(true)
	end)

	it("the script is there and executable", function()
		t.expect(fs.isFile("scripts/linux-jail.sh")).toBe(true)
		t.expect(process.exec("test", { "-x", "scripts/linux-jail.sh" }).ok).toBe(true)
	end)

	it("the fence sets no ref hooks under the bubblewrap jail, as under the macOS one", function()
		t.expect(hooksPath("bwrap")).toBe("")
		t.expect(hooksPath("sandbox-exec")).toBe("")
	end)

	it("the fence still sets its ref hooks where there is no jail", function()
		t.expect(has(hooksPath("none (unjailed)"), "scripts/lib/git-hooks")).toBe(true)
		t.expect(has(hooksPath("outer sandbox (protects the repository)"), "scripts/lib/git-hooks"))
			.toBe(true)
	end)

	it("fixtures never sign: the fence turns commit and tag signing off in a spec run", function()
		for _, jail in { "bwrap", "none (unjailed)" } do
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			local co = `{base}/sign`
			fs.writeDir(co)
			assert(process.exec("git", { "init", "-q", co }).ok, "could not make the fixture checkout")
			local r = process.exec("bash", {
				"-c",
				'. "$1/scripts/lib/fence.sh" && pickman_fence "$2" specs "$3" && cd "$2" && git config --get commit.gpgsign && git config --get tag.gpgsign',
				"_",
				root,
				co,
				jail,
			}, { cwd = root })
			t.expect(r.stdout).toBe("false\nfalse\n")
		end
	end)

	it("the documents say specs are jailed on Linux too", function()
		local agents = fs.readFile("AGENTS.md")
		local testing = fs.readFile("z-nile/skills/zz-test/SKILL.md")
		local setup = fs.readFile("SETUP.md")
		t.expect(has(agents, "unjailed runs on Linux")).toBe(false)
		t.expect(has(agents, "bubblewrap")).toBe(true)
		t.expect(has(testing, "specs there are unjailed")).toBe(false)
		t.expect(has(testing, "bubblewrap")).toBe(true)
		t.expect(has(testing, "scripts/linux-jail.sh")).toBe(true)
		t.expect(has(testing, "systemd-run")).toBe(true) -- handing work to a daemon outside the jail is review's to catch
		t.expect(has(setup, "scripts/linux-jail.sh")).toBe(true)
	end)
end)
