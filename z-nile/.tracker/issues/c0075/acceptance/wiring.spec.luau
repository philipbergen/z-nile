--!strict
-- c0075 AC6: the Linux jail is wired in everywhere a Linux run starts: a host is told to get it before it runs the gate,
-- the fence sets no ref hooks under it (the kernel already denies the writes, as under macOS's jail), and the documents
-- say what is true now. Static reads, plus one run of the fence's shell half in a fixture.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0075-wiring`

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
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
	-- c0173: this case used to read the CI workflow's gate job. GitHub Actions no longer runs the gate (c0172), so the
	-- places a Linux run starts are the host's own: its owner reads SETUP.md's prerequisites before running
	-- z-nile/setup.sh. The case checks the row, not an order. It uses only fs, t, root and has.
	it("a Linux host's prerequisites name the jail script", function()
		local setup = fs.readFile(`{root}/SETUP.md`)
		local from = string.find(setup, "\n## Prerequisites", 1, true)
		t.expect(from ~= nil).toBe(true)
		local upto = string.find(setup, "\n## ", (from :: number) + 1, true) or (#setup + 1)
		local named = false
		for line in string.gmatch(string.sub(setup, from :: number, upto - 1), "[^\n]+") do
			-- a table row `| need | macOS | Linux |`: split at the bars, the Linux cell is the fourth piece
			local cells = string.split(line, "|")
			if
				string.sub(line, 1, 1) == "|"
				and cells[4] ~= nil
				and has(cells[4], "scripts/linux-jail.sh")
			then
				named = true
			end
		end
		t.expect(named).toBe(true)
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
